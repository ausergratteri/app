-- Permessi sulle fotografie per ogni ruolo (migrazione 20261121_permessi_foto_ruoli.sql).
-- Va eseguito dopo 20_test_accessi.sql (riusa le procedure t.*). Usa solo file e righe
-- "45-..." creati qui, così non dipende dagli altri test.
--   P presidente · D direttivo · S socio · S2 altro socio · A in attesa (mai stato socio)
--   E "espulso": era socio, ha caricato foto, poi è stato riportato in attesa
--   X profilo eliminato: era socio, ha caricato foto, poi il profilo è stato cancellato
truncate t.esiti;
\set P '''00000000-0000-0000-0000-000000000001'''
\set D '''00000000-0000-0000-0000-000000000002'''
\set S '''00000000-0000-0000-0000-000000000003'''
\set A '''00000000-0000-0000-0000-000000000004'''
\set S2 '''00000000-0000-0000-0000-000000000045'''
\set E '''00000000-0000-0000-0000-000000000046'''
\set X '''00000000-0000-0000-0000-000000000047'''

-- ---------- Dati (come amministratore) ----------
do $$ begin perform set_config('request.jwt.claim.sub', '', false); end $$;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000045', '3335550045@soci.ausergratteri.app', '{"nome":"Socio Due"}'),
  ('00000000-0000-0000-0000-000000000046', '3335550046@soci.ausergratteri.app', '{"nome":"Ex Socio"}'),
  ('00000000-0000-0000-0000-000000000047', '3335550047@soci.ausergratteri.app', '{"nome":"Profilo Eliminato"}');
update public.profili set ruolo = 'socio' where id in
  ('00000000-0000-0000-0000-000000000045', '00000000-0000-0000-0000-000000000046', '00000000-0000-0000-0000-000000000047');

-- In ciascuno dei due bucket: un file di S, S2, E, X e D
insert into storage.objects (bucket_id, name, owner)
select b, u || '/45-file.jpg', u::uuid
from unnest(array['foto', 'foto-private']) b,
     unnest(array['00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000045',
                  '00000000-0000-0000-0000-000000000046', '00000000-0000-0000-0000-000000000047',
                  '00000000-0000-0000-0000-000000000002']) u;
-- Una foto (riga) privata ciascuno per S, S2, E, X
insert into public.foto (id, attivita_id, user_id, url, percorso, bucket) values
  ('e4500000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', '', '00000000-0000-0000-0000-000000000003/45-file.jpg', 'foto-private'),
  ('e4500000-0000-0000-0000-000000000045', 'a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000045', '', '00000000-0000-0000-0000-000000000045/45-file.jpg', 'foto-private'),
  ('e4500000-0000-0000-0000-000000000046', 'a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000046', '', '00000000-0000-0000-0000-000000000046/45-file.jpg', 'foto-private'),
  ('e4500000-0000-0000-0000-000000000047', 'a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000047', '', '00000000-0000-0000-0000-000000000047/45-file.jpg', 'foto-private');
-- E viene riportato in attesa ("espulso"); il profilo di X viene eliminato (le sue righe restano senza autore)
update public.profili set ruolo = 'in_attesa' where id = '00000000-0000-0000-0000-000000000046';
delete from public.profili where id = '00000000-0000-0000-0000-000000000047';

call t.verifica('dati: E è in attesa, X non ha più il profilo, la foto di X è senza autore', null, 'select 1',
  $c$(select ruolo from public.profili where id = '00000000-0000-0000-0000-000000000046') = 'in_attesa'
     and not exists (select 1 from public.profili where id = '00000000-0000-0000-0000-000000000047')
     and (select user_id from public.foto where id = 'e4500000-0000-0000-0000-000000000047') is null$c$);

-- ---------- File, per ciascuno dei due bucket ----------
do $$
declare
  b text;
  P constant uuid := '00000000-0000-0000-0000-000000000001';
  D constant uuid := '00000000-0000-0000-0000-000000000002';
  S constant uuid := '00000000-0000-0000-0000-000000000003';
  A constant uuid := '00000000-0000-0000-0000-000000000004';
  S2 constant uuid := '00000000-0000-0000-0000-000000000045';
  E constant uuid := '00000000-0000-0000-0000-000000000046';
  X constant uuid := '00000000-0000-0000-0000-000000000047';
  conta text; togli text;
begin
  foreach b in array array['foto', 'foto-private'] loop
    conta := format($q$select count(*) from storage.objects where bucket_id = %L and name like '%%/45-%%'$q$, b);
    togli := 'delete from storage.objects where bucket_id = %L and name = %L';
    -- Vedere (serve anche per ottenere l'URL temporaneo)
    call t.conta(b || ': presidente vede tutti i file', P, conta, 5);
    call t.conta(b || ': direttivo vede tutti i file', D, conta, 5);
    call t.conta(b || ': socio vede tutti i file', S, conta, 5);
    call t.conta(b || ': in attesa non vede i file', A, conta, 0);
    call t.conta(b || ': espulso non vede i file, nemmeno i suoi', E, conta, 0);
    call t.conta(b || ': profilo eliminato non vede i file, nemmeno i suoi', X, conta, 0);
    call t.conta(b || ': anon non vede i file', null, conta, 0);
    -- Caricare
    call t.prova(b || ': socio carica nella sua cartella → consentito', S,
      format('insert into storage.objects (bucket_id, name) values (%L, %L)', b, S || '/45-nuovo.jpg'), 'consentito');
    call t.prova(b || ': socio carica nella cartella di un altro → negato', S,
      format('insert into storage.objects (bucket_id, name) values (%L, %L)', b, S2 || '/45-nuovo.jpg'), 'negato');
    call t.prova(b || ': direttivo carica nella sua cartella → consentito', D,
      format('insert into storage.objects (bucket_id, name) values (%L, %L)', b, D || '/45-nuovo.jpg'), 'consentito');
    call t.prova(b || ': presidente carica nella sua cartella → consentito', P,
      format('insert into storage.objects (bucket_id, name) values (%L, %L)', b, P || '/45-nuovo.jpg'), 'consentito');
    call t.prova(b || ': in attesa carica nella sua cartella → negato', A,
      format('insert into storage.objects (bucket_id, name) values (%L, %L)', b, A || '/45-nuovo.jpg'), 'negato');
    call t.prova(b || ': espulso carica nella sua cartella → negato', E,
      format('insert into storage.objects (bucket_id, name) values (%L, %L)', b, E || '/45-nuovo.jpg'), 'negato');
    call t.prova(b || ': profilo eliminato carica nella sua cartella → negato', X,
      format('insert into storage.objects (bucket_id, name) values (%L, %L)', b, X || '/45-nuovo.jpg'), 'negato');
    call t.prova(b || ': anon carica → negato', null,
      format('insert into storage.objects (bucket_id, name) values (%L, %L)', b, 'anon/45-nuovo.jpg'), 'negato');
    -- Cancellare
    call t.prova(b || ': socio cancella un suo file → consentito', S, format(togli, b, S || '/45-file.jpg'), 'consentito');
    call t.prova(b || ': socio cancella il file di un altro socio → negato', S, format(togli, b, S2 || '/45-file.jpg'), 'negato');
    call t.prova(b || ': socio cancella il file del direttivo → negato', S, format(togli, b, D || '/45-file.jpg'), 'negato');
    call t.prova(b || ': socio cancella il file di un profilo eliminato → negato', S, format(togli, b, X || '/45-file.jpg'), 'negato');
    call t.prova(b || ': direttivo cancella il file di un socio → consentito', D, format(togli, b, S || '/45-file.jpg'), 'consentito');
    call t.prova(b || ': direttivo cancella il file di un profilo eliminato → consentito', D, format(togli, b, X || '/45-file.jpg'), 'consentito');
    call t.prova(b || ': presidente cancella il file del direttivo → consentito', P, format(togli, b, D || '/45-file.jpg'), 'consentito');
    call t.prova(b || ': in attesa cancella un file → negato', A,
      format($q$delete from storage.objects where bucket_id = %L and name like '%%/45-%%'$q$, b), 'negato');
    call t.prova(b || ': espulso cancella un suo file → negato', E, format(togli, b, E || '/45-file.jpg'), 'negato');
    call t.prova(b || ': profilo eliminato cancella un suo file → negato', X, format(togli, b, X || '/45-file.jpg'), 'negato');
    call t.prova(b || ': anon cancella un file → negato', null,
      format($q$delete from storage.objects where bucket_id = %L and name like '%%/45-%%'$q$, b), 'negato');
    -- Modificare (sovrascrivere/spostare): nessuno, come prima
    call t.prova(b || ': socio modifica un suo file → negato (come prima)', S,
      format('update storage.objects set name = name || %L where bucket_id = %L and name = %L', '.x', b, S || '/45-file.jpg'), 'negato');
    call t.prova(b || ': presidente modifica un file → negato (come prima)', P,
      format('update storage.objects set name = name || %L where bucket_id = %L and name = %L', '.x', b, S || '/45-file.jpg'), 'negato');
    call t.prova(b || ': espulso modifica un suo file → negato', E,
      format('update storage.objects set name = name || %L where bucket_id = %L and name = %L', '.x', b, E || '/45-file.jpg'), 'negato');
  end loop;
end $$;

-- ---------- Righe di public.foto ----------
\set QS '$q$select count(*) from public.foto where id::text like ''e45%''$q$'
call t.conta('righe: presidente vede tutte le foto', :P, :QS, 4);
call t.conta('righe: direttivo vede tutte le foto', :D, :QS, 4);
call t.conta('righe: socio vede tutte le foto', :S, :QS, 4);
call t.conta('righe: in attesa non vede le foto', :A, :QS, 0);
call t.conta('righe: espulso non vede le foto, nemmeno le sue', :E, :QS, 0);
call t.conta('righe: profilo eliminato non vede le foto', :X, :QS, 0);
call t.prova('righe: anon non legge le foto → negato', null, $x$select * from public.foto$x$, 'negato');

call t.prova('righe: socio cambia la didascalia di una sua foto → consentito', :S,
  $x$update public.foto set didascalia = 'x' where id = 'e4500000-0000-0000-0000-000000000003'$x$, 'consentito');
call t.prova('righe: socio cambia la didascalia della foto di un altro → negato', :S,
  $x$update public.foto set didascalia = 'x' where id = 'e4500000-0000-0000-0000-000000000045'$x$, 'negato');
call t.prova('righe: socio cede una sua foto a un altro socio → negato', :S,
  $x$update public.foto set user_id = '00000000-0000-0000-0000-000000000045' where id = 'e4500000-0000-0000-0000-000000000003'$x$, 'negato');
call t.prova('righe: direttivo cambia la didascalia della foto di un socio → consentito', :D,
  $x$update public.foto set didascalia = 'x' where id = 'e4500000-0000-0000-0000-000000000003'$x$, 'consentito');
call t.prova('righe: presidente cambia la didascalia della foto di un socio → consentito', :P,
  $x$update public.foto set didascalia = 'x' where id = 'e4500000-0000-0000-0000-000000000045'$x$, 'consentito');
call t.prova('righe: in attesa cambia una didascalia → negato', :A,
  $x$update public.foto set didascalia = 'x' where id::text like 'e45%'$x$, 'negato');
call t.prova('righe: espulso cambia la didascalia di una sua foto → negato', :E,
  $x$update public.foto set didascalia = 'x' where id = 'e4500000-0000-0000-0000-000000000046'$x$, 'negato');

call t.prova('righe: socio cancella una sua foto → consentito', :S,
  $x$delete from public.foto where id = 'e4500000-0000-0000-0000-000000000003'$x$, 'consentito');
call t.prova('righe: socio cancella la foto di un altro socio → negato', :S,
  $x$delete from public.foto where id = 'e4500000-0000-0000-0000-000000000045'$x$, 'negato');
call t.prova('righe: socio cancella la foto di un profilo eliminato → negato', :S,
  $x$delete from public.foto where id = 'e4500000-0000-0000-0000-000000000047'$x$, 'negato');
call t.prova('righe: direttivo cancella la foto di un socio → consentito', :D,
  $x$delete from public.foto where id = 'e4500000-0000-0000-0000-000000000003'$x$, 'consentito');
call t.prova('righe: direttivo cancella la foto di un profilo eliminato → consentito', :D,
  $x$delete from public.foto where id = 'e4500000-0000-0000-0000-000000000047'$x$, 'consentito');
call t.prova('righe: presidente cancella la foto di un socio → consentito', :P,
  $x$delete from public.foto where id = 'e4500000-0000-0000-0000-000000000045'$x$, 'consentito');
call t.prova('righe: in attesa cancella una foto → negato', :A,
  $x$delete from public.foto where id::text like 'e45%'$x$, 'negato');
call t.prova('righe: espulso cancella una sua foto → negato', :E,
  $x$delete from public.foto where id = 'e4500000-0000-0000-0000-000000000046'$x$, 'negato');
call t.prova('righe: profilo eliminato cancella una foto → negato', :X,
  $x$delete from public.foto where id::text like 'e45%'$x$, 'negato');
-- Senza filtro (WHERE) la regola di lettura non entra in gioco: qui contava solo
-- "user_id = auth.uid()", e l'espulso poteva ancora cancellare o cambiare le sue foto.
call t.prova('righe: espulso cancella tutte le sue foto senza filtro → negato', :E,
  $x$delete from public.foto$x$, 'negato');
call t.prova('righe: espulso cambia tutte le sue didascalie senza filtro → negato', :E,
  $x$update public.foto set didascalia = 'x'$x$, 'negato');
call t.prova('file: espulso cancella tutti i suoi file senza filtro → negato', :E,
  $x$delete from storage.objects$x$, 'negato');
call t.conta('righe: socio senza filtro cancella solo le sue foto (0 di altri)', :S,
  $q$with via as (delete from public.foto returning user_id)
     select count(*) filter (where user_id is distinct from auth.uid()) from via$q$, 0);

call t.prova('righe: socio pubblica una sua foto → consentito', :S,
  $x$insert into public.foto (attivita_id, user_id, url, percorso, bucket) values ('a0000000-0000-0000-0000-000000000001', auth.uid(), '', '00000000-0000-0000-0000-000000000003/45-nuovo.jpg', 'foto-private')$x$, 'consentito');
call t.prova('righe: espulso pubblica una foto → negato', :E,
  $x$insert into public.foto (attivita_id, user_id, url, percorso, bucket) values ('a0000000-0000-0000-0000-000000000001', auth.uid(), '', '00000000-0000-0000-0000-000000000046/45-nuovo.jpg', 'foto-private')$x$, 'negato');
call t.prova('righe: in attesa pubblica una foto → negato', :A,
  $x$insert into public.foto (attivita_id, user_id, url, percorso, bucket) values ('a0000000-0000-0000-0000-000000000001', auth.uid(), '', '00000000-0000-0000-0000-000000000004/45-nuovo.jpg', 'foto-private')$x$, 'negato');

-- ---------- Regole concorrenti: una regola permissiva "apri tutto" aggiunta per errore ----------
-- Le regole restrittive devono tenere fuori chi è in attesa e lasciare a un socio solo le sue foto.
create policy intrusa_righe on public.foto for all to anon, authenticated using (true) with check (true);
create policy intrusa_archivi on storage.objects for all to anon, authenticated using (true) with check (true);

call t.conta('intrusa: in attesa continua a non vedere le foto', :A, :QS, 0);
call t.conta('intrusa: espulso continua a non vedere le foto', :E, :QS, 0);
call t.prova('intrusa: espulso continua a non poter cancellare le sue foto → negato', :E,
  $x$delete from public.foto where id = 'e4500000-0000-0000-0000-000000000046'$x$, 'negato');
call t.prova('intrusa: socio continua a non poter cancellare la foto di un altro → negato', :S,
  $x$delete from public.foto where id = 'e4500000-0000-0000-0000-000000000045'$x$, 'negato');
call t.prova('intrusa: socio continua a non poter modificare la foto di un altro → negato', :S,
  $x$update public.foto set didascalia = 'x' where id = 'e4500000-0000-0000-0000-000000000045'$x$, 'negato');
call t.prova('intrusa: socio continua a non poter pubblicare a nome di un altro → negato', :S,
  $x$insert into public.foto (attivita_id, user_id, url, percorso, bucket) values ('a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000045', '', '00000000-0000-0000-0000-000000000045/45-z.jpg', 'foto-private')$x$, 'negato');
call t.conta('intrusa: in attesa continua a non vedere i file privati', :A,
  $q$select count(*) from storage.objects where bucket_id = 'foto-private'$q$, 0);
call t.conta('intrusa: anon continua a non vedere i file privati', null,
  $q$select count(*) from storage.objects where bucket_id = 'foto-private'$q$, 0);
call t.prova('intrusa: in attesa continua a non poter caricare → negato', :A,
  $x$insert into storage.objects (bucket_id, name) values ('foto-private', '00000000-0000-0000-0000-000000000004/45-z.jpg')$x$, 'negato');
call t.prova('intrusa: socio continua a non poter caricare nella cartella di un altro → negato', :S,
  $x$insert into storage.objects (bucket_id, name) values ('foto-private', '00000000-0000-0000-0000-000000000045/45-z.jpg')$x$, 'negato');
call t.prova('intrusa: socio continua a non poter cancellare il file di un altro → negato', :S,
  $x$delete from storage.objects where bucket_id = 'foto-private' and name = '00000000-0000-0000-0000-000000000045/45-file.jpg'$x$, 'negato');
call t.prova('intrusa: socio continua a non poter spostare il file di un altro → negato', :S,
  $x$update storage.objects set name = '00000000-0000-0000-0000-000000000003/45-preso.jpg' where bucket_id = 'foto-private' and name = '00000000-0000-0000-0000-000000000045/45-file.jpg'$x$, 'negato');
call t.prova('intrusa: espulso continua a non poter cancellare i suoi file → negato', :E,
  $x$delete from storage.objects where bucket_id = 'foto' and name = '00000000-0000-0000-0000-000000000046/45-file.jpg'$x$, 'negato');
call t.prova('intrusa: il socio cancella ancora i suoi file → consentito', :S,
  $x$delete from storage.objects where bucket_id = 'foto-private' and name = '00000000-0000-0000-0000-000000000003/45-file.jpg'$x$, 'consentito');

drop policy intrusa_righe on public.foto;
drop policy intrusa_archivi on storage.objects;

-- ---------- Struttura delle regole ----------
call t.verifica('struttura: 4 regole restrittive su public.foto e 4 su storage.objects', null, 'select 1',
  $c$(select count(*) from pg_policies where schemaname = 'public' and tablename = 'foto' and permissive = 'RESTRICTIVE') = 4
     and (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects' and permissive = 'RESTRICTIVE') = 4$c$);
call t.verifica('struttura: nessuna regola permissiva di modifica sui file', null, 'select 1',
  $c$not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
                 and permissive = 'PERMISSIVE' and cmd in ('UPDATE', 'ALL'))$c$);

\pset format unaligned
\pset tuples_only on
\pset fieldsep '|'
select case when ok then 'PASS' else 'FAIL' end, nome, dettaglio from t.esiti order by n;
\pset format aligned
\pset tuples_only off
