-- Correzioni del retest Strix (migrazione 20261122_correzioni_retest.sql):
--  - adesioni per ruolo, compreso chi è stato riportato "in attesa" (vuln-0007);
--  - impostazioni.tema solo con i temi esistenti (vuln-0006);
--  - bucket pubblico "foto" senza SVG (vuln-0002).
-- Va eseguito dopo 20_test_accessi.sql (riusa le procedure t.*). Dati propri "e46...".
truncate t.esiti;
\set P '''00000000-0000-0000-0000-000000000001'''
\set D '''00000000-0000-0000-0000-000000000002'''
\set S '''00000000-0000-0000-0000-000000000003'''
\set A '''00000000-0000-0000-0000-000000000004'''
\set S2 '''00000000-0000-0000-0000-000000000461'''
\set E '''00000000-0000-0000-0000-000000000462'''

-- ---------- Dati (come amministratore) ----------
do $$ begin perform set_config('request.jwt.claim.sub', '', false); end $$;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000461', '3335550461@soci.ausergratteri.app', '{"nome":"Socio Due"}'),
  ('00000000-0000-0000-0000-000000000462', '3335550462@soci.ausergratteri.app', '{"nome":"Ex Socio"}');
update public.profili set ruolo = 'socio' where id in
  ('00000000-0000-0000-0000-000000000461', '00000000-0000-0000-0000-000000000462');
-- Attività aperta senza limite di posti, con un'adesione ciascuno per S, S2, E e una manuale del direttivo
insert into public.attivita (id, titolo, data, ospiti, stato) values
  ('a4600000-0000-0000-0000-000000000001', 'Gita retest', current_date + 30, true, 'aperta');
insert into public.adesioni (id, attivita_id, user_id, nome, acc) values
  ('e4600000-0000-0000-0000-000000000003', 'a4600000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 'S', '[]'),
  ('e4600000-0000-0000-0000-000000000461', 'a4600000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000461', 'S2', '[]'),
  ('e4600000-0000-0000-0000-000000000462', 'a4600000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000462', 'E', '[{"nome":"Fam","rel":"Familiare"}]'),
  ('e4600000-0000-0000-0000-0000000000d1', 'a4600000-0000-0000-0000-000000000001', null, 'Iscritto a mano', '[]');
-- E viene riportato in attesa ("espulso"), con la sua adesione ancora presente
update public.profili set ruolo = 'in_attesa' where id = '00000000-0000-0000-0000-000000000462';

\set QA '$q$select count(*) from public.adesioni where attivita_id = ''a4600000-0000-0000-0000-000000000001''$q$'
\set QAL '$q$select count(*) from public.adesioni where attivita_id = ''a4600000-0000-0000-0000-000000000001'' and user_id is distinct from auth.uid()$q$'

-- ---------- Adesioni: leggere ----------
call t.conta('adesioni: presidente vede tutte le adesioni', :P, :QA, 4);
call t.conta('adesioni: direttivo vede tutte le adesioni', :D, :QA, 4);
call t.conta('adesioni: socio vede solo la sua', :S, :QA, 1);
call t.conta('adesioni: socio non vede quelle degli altri', :S, :QAL, 0);
call t.conta('adesioni: espulso non vede più nemmeno la sua', :E, :QA, 0);
call t.conta('adesioni: in attesa non vede nulla', :A, :QA, 0);
call t.prova('adesioni: anon non legge → negato', null, $x$select * from public.adesioni$x$, 'negato');

-- ---------- Adesioni: modificare ----------
call t.prova('adesioni: socio modifica le note della sua → consentito', :S,
  $x$update public.adesioni set note = 'x' where id = 'e4600000-0000-0000-0000-000000000003'$x$, 'consentito');
call t.prova('adesioni: socio modifica quella di un altro → negato', :S,
  $x$update public.adesioni set note = 'x' where id = 'e4600000-0000-0000-0000-000000000461'$x$, 'negato');
call t.prova('adesioni: direttivo modifica quella di un socio → consentito', :D,
  $x$update public.adesioni set note = 'x' where id = 'e4600000-0000-0000-0000-000000000461'$x$, 'consentito');
call t.prova('adesioni: presidente modifica quella manuale → consentito', :P,
  $x$update public.adesioni set note = 'x' where id = 'e4600000-0000-0000-0000-0000000000d1'$x$, 'consentito');
call t.prova('adesioni: espulso modifica la sua (con filtro) → negato', :E,
  $x$update public.adesioni set note = 'x' where id = 'e4600000-0000-0000-0000-000000000462'$x$, 'negato');
call t.prova('adesioni: espulso modifica le sue senza filtro → negato', :E,
  $x$update public.adesioni set acc = '[]'$x$, 'negato');
call t.prova('adesioni: in attesa modifica senza filtro → negato', :A,
  $x$update public.adesioni set note = 'x'$x$, 'negato');

-- ---------- Adesioni: cancellare ----------
call t.prova('adesioni: socio cancella la sua → consentito', :S,
  $x$delete from public.adesioni where id = 'e4600000-0000-0000-0000-000000000003'$x$, 'consentito');
call t.prova('adesioni: socio cancella quella di un altro → negato', :S,
  $x$delete from public.adesioni where id = 'e4600000-0000-0000-0000-000000000461'$x$, 'negato');
call t.conta('adesioni: socio senza filtro cancella solo la sua (0 di altri)', :S,
  $q$with via as (delete from public.adesioni returning user_id)
     select count(*) filter (where user_id is distinct from auth.uid()) from via$q$, 0);
call t.prova('adesioni: direttivo cancella quella di un socio → consentito', :D,
  $x$delete from public.adesioni where id = 'e4600000-0000-0000-0000-000000000461'$x$, 'consentito');
call t.prova('adesioni: presidente cancella quella dell''espulso → consentito', :P,
  $x$delete from public.adesioni where id = 'e4600000-0000-0000-0000-000000000462'$x$, 'consentito');
call t.prova('adesioni: espulso cancella la sua (con filtro) → negato', :E,
  $x$delete from public.adesioni where id = 'e4600000-0000-0000-0000-000000000462'$x$, 'negato');
call t.prova('adesioni: espulso cancella le sue senza filtro → negato', :E,
  $x$delete from public.adesioni$x$, 'negato');

-- ---------- Adesioni: iscriversi (invariato) ----------
call t.prova('adesioni: socio si iscrive → consentito', :S2,
  $x$insert into public.adesioni (attivita_id, user_id, nome, canale) values ('a0000000-0000-0000-0000-000000000003', auth.uid(), 'S2', 'App')$x$, 'consentito');
call t.prova('adesioni: espulso si iscrive → negato', :E,
  $x$insert into public.adesioni (attivita_id, user_id, nome, canale) values ('a0000000-0000-0000-0000-000000000003', auth.uid(), 'E', 'App')$x$, 'negato');
call t.prova('adesioni: direttivo iscrive una persona a mano → consentito', :D,
  $x$insert into public.adesioni (attivita_id, user_id, nome, canale) values ('a4600000-0000-0000-0000-000000000001', null, 'A mano', 'Telefono')$x$, 'consentito');

-- ---------- Regole concorrenti: una regola "apri tutto" aggiunta per errore ----------
create policy intrusa_adesioni on public.adesioni for all to anon, authenticated using (true) with check (true);
call t.conta('intrusa: espulso continua a non vedere nulla', :E, :QA, 0);
call t.conta('intrusa: in attesa continua a non vedere nulla', :A, :QA, 0);
call t.conta('intrusa: socio continua a vedere solo la sua', :S, :QAL, 0);
call t.prova('intrusa: espulso continua a non poter modificare → negato', :E,
  $x$update public.adesioni set note = 'x'$x$, 'negato');
call t.prova('intrusa: socio continua a non poter cancellare quella di un altro → negato', :S,
  $x$delete from public.adesioni where id = 'e4600000-0000-0000-0000-000000000461'$x$, 'negato');
call t.prova('intrusa: socio continua a non poter iscrivere un altro → negato', :S,
  $x$insert into public.adesioni (attivita_id, user_id, nome, canale) values ('a0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000461', 'X', 'App')$x$, 'negato');
drop policy intrusa_adesioni on public.adesioni;

call t.verifica('struttura: 2 regole restrittive e 4 permissive su public.adesioni', null, 'select 1',
  $c$(select count(*) from pg_policies where schemaname = 'public' and tablename = 'adesioni' and permissive = 'RESTRICTIVE') = 2
     and (select count(*) from pg_policies where schemaname = 'public' and tablename = 'adesioni' and permissive = 'PERMISSIVE') = 4$c$);

-- ---------- Tema ----------
call t.prova('tema: il presidente sceglie un tema esistente → consentito', :P,
  $x$update public.impostazioni set tema = 'natale' where id = 1$x$, 'consentito');
call t.prova('tema: il presidente salva un tema personalizzato → consentito', :P,
  $x$update public.impostazioni set tema = 'personalizzato' where id = 1$x$, 'consentito');
call t.prova('tema: il presidente sceglie il tema automatico → consentito', :P,
  $x$update public.impostazioni set tema = 'automatico' where id = 1$x$, 'consentito');
call t.prova('tema: "constructor" → negato', :P,
  $x$update public.impostazioni set tema = 'constructor' where id = 1$x$, 'negato');
call t.prova('tema: "__proto__" → negato', :P,
  $x$update public.impostazioni set tema = '__proto__' where id = 1$x$, 'negato');
call t.prova('tema: tema inesistente → negato', :P,
  $x$update public.impostazioni set tema = 'inesistente' where id = 1$x$, 'negato');
call t.verifica('tema: vincolo presente', null, 'select 1',
  $c$exists (select 1 from pg_constraint where conname = 'impostazioni_tema_valido')$c$);

-- ---------- Bucket pubblico senza SVG ----------
call t.verifica('bucket: "foto" non ammette più SVG, ammette le immagini normali', null, 'select 1',
  $c$(select not ('image/svg+xml' = any(allowed_mime_types))
          and allowed_mime_types @> array['image/jpeg','image/png','image/webp','image/gif']
     from storage.buckets where id = 'foto')$c$);
call t.verifica('bucket: "foto" resta pubblico, "foto-private" resta privato senza SVG', null, 'select 1',
  $c$(select public from storage.buckets where id = 'foto')
     and not (select public from storage.buckets where id = 'foto-private')
     and array_position((select allowed_mime_types from storage.buckets where id = 'foto-private'), 'image/svg+xml') is null$c$);

\pset format unaligned
\pset tuples_only on
\pset fieldsep '|'
select case when ok then 'PASS' else 'FAIL' end, nome, dettaglio from t.esiti order by n;
\pset format aligned
\pset tuples_only off
