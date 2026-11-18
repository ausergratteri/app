-- Bucket privato delle gallerie ("foto-private") e colonna public.foto.bucket.
-- Va eseguito dopo 20_test_accessi.sql (riusa le procedure t.*).
truncate t.esiti;
\set P '''00000000-0000-0000-0000-000000000001'''
\set D '''00000000-0000-0000-0000-000000000002'''
\set S '''00000000-0000-0000-0000-000000000003'''
\set A '''00000000-0000-0000-0000-000000000004'''

-- Un file privato di Maria (S) e uno del presidente (P)
insert into storage.objects (bucket_id, name, owner) values
  ('foto-private', '00000000-0000-0000-0000-000000000003/10-privata.jpg', '00000000-0000-0000-0000-000000000003'),
  ('foto-private', '00000000-0000-0000-0000-000000000001/11-privata.jpg', '00000000-0000-0000-0000-000000000001');

-- ---------- Il bucket ----------
call t.verifica('bucket: "foto-private" esiste ed è privato, senza SVG', null, 'select 1',
  $c$exists (select 1 from storage.buckets where id = 'foto-private' and public = false
             and not ('image/svg+xml' = any(allowed_mime_types)) and file_size_limit = 5242880)$c$);
call t.verifica('bucket: "foto" resta pubblico (copertine, bacheca, logo)', null, 'select 1',
  $c$exists (select 1 from storage.buckets where id = 'foto' and public = true)$c$);

-- ---------- Chi vede i file privati (serve anche per ottenere l'URL temporaneo) ----------
call t.conta('privato: anon non vede i file', null, $q$select count(*) from storage.objects where bucket_id = 'foto-private'$q$, 0);
call t.conta('privato: in attesa non vede i file', :A, $q$select count(*) from storage.objects where bucket_id = 'foto-private'$q$, 0);
call t.conta('privato: il socio vede i file', :S, $q$select count(*) from storage.objects where bucket_id = 'foto-private'$q$, 2);
call t.conta('privato: il direttivo vede i file', :D, $q$select count(*) from storage.objects where bucket_id = 'foto-private'$q$, 2);

-- ---------- Chi carica ----------
call t.prova('privato: socio carica nella propria cartella → consentito', :S,
  $x$insert into storage.objects (bucket_id, name) values ('foto-private', '00000000-0000-0000-0000-000000000003/12-nuova.jpg')$x$, 'consentito');
call t.prova('privato: socio carica nella cartella di un altro → negato', :S,
  $x$insert into storage.objects (bucket_id, name) values ('foto-private', '00000000-0000-0000-0000-000000000001/12-nuova.jpg')$x$, 'negato');
call t.prova('privato: socio carica fuori da ogni cartella → negato', :S,
  $x$insert into storage.objects (bucket_id, name) values ('foto-private', '12-nuova.jpg')$x$, 'negato');
call t.prova('privato: in attesa carica nella propria cartella → negato', :A,
  $x$insert into storage.objects (bucket_id, name) values ('foto-private', '00000000-0000-0000-0000-000000000004/x.jpg')$x$, 'negato');
call t.prova('privato: anon carica → negato', null,
  $x$insert into storage.objects (bucket_id, name) values ('foto-private', 'x/x.jpg')$x$, 'negato');

-- ---------- Chi toglie ----------
call t.prova('privato: socio toglie un suo file → consentito', :S,
  $x$delete from storage.objects where bucket_id = 'foto-private' and name = '00000000-0000-0000-0000-000000000003/10-privata.jpg'$x$, 'consentito');
call t.prova('privato: socio toglie il file di un altro → negato', :S,
  $x$delete from storage.objects where bucket_id = 'foto-private' and name = '00000000-0000-0000-0000-000000000001/11-privata.jpg'$x$, 'negato');
call t.prova('privato: direttivo toglie il file di un altro → consentito', :D,
  $x$delete from storage.objects where bucket_id = 'foto-private' and name = '00000000-0000-0000-0000-000000000003/10-privata.jpg'$x$, 'consentito');
call t.prova('privato: in attesa toglie un file → negato', :A,
  $x$delete from storage.objects where bucket_id = 'foto-private'$x$, 'negato');

-- ---------- Le regole del bucket pubblico non sono cambiate ----------
call t.prova('pubblico: il direttivo carica una copertina nella sua cartella → consentito', :D,
  $x$insert into storage.objects (bucket_id, name) values ('foto', '00000000-0000-0000-0000-000000000002/locandina.jpg')$x$, 'consentito');
call t.conta('pubblico: in attesa continua a non elencare i file', :A, $q$select count(*) from storage.objects where bucket_id = 'foto'$q$, 0);

-- ---------- Righe di public.foto ----------
call t.prova('righe: socio pubblica una foto privata senza URL → consentito', :S,
  $x$insert into public.foto (attivita_id, user_id, url, percorso, bucket) values ('a0000000-0000-0000-0000-000000000001', auth.uid(), '', '00000000-0000-0000-0000-000000000003/12-nuova.jpg', 'foto-private')$x$, 'consentito');
call t.prova('righe: foto privata con un URL pubblico → negato', :S,
  $x$insert into public.foto (attivita_id, user_id, url, percorso, bucket) values ('a0000000-0000-0000-0000-000000000001', auth.uid(), 'https://x.supabase.co/a.jpg', '00000000-0000-0000-0000-000000000003/12-nuova.jpg', 'foto-private')$x$, 'negato');
call t.prova('righe: foto privata senza percorso → negato', :S,
  $x$insert into public.foto (attivita_id, user_id, url, percorso, bucket) values ('a0000000-0000-0000-0000-000000000001', auth.uid(), '', '', 'foto-private')$x$, 'negato');
call t.prova('righe: bucket inesistente → negato', :S,
  $x$insert into public.foto (attivita_id, user_id, url, percorso, bucket) values ('a0000000-0000-0000-0000-000000000001', auth.uid(), '', '00000000-0000-0000-0000-000000000003/12-nuova.jpg', 'altro')$x$, 'negato');
call t.prova('righe: foto privata nella cartella di un altro → negato', :S,
  $x$insert into public.foto (attivita_id, user_id, url, percorso, bucket) values ('a0000000-0000-0000-0000-000000000001', auth.uid(), '', '00000000-0000-0000-0000-000000000001/11-privata.jpg', 'foto-private')$x$, 'negato');
call t.verifica('righe: la vecchia app (senza colonna bucket) salva ancora nel bucket pubblico', :S,
  $x$insert into public.foto (attivita_id, user_id, url, percorso) values ('a0000000-0000-0000-0000-000000000001', auth.uid(), 'https://x.supabase.co/v.jpg', '00000000-0000-0000-0000-000000000003/13-vecchia.jpg')$x$,
  $c$(select bucket from public.foto where percorso = '00000000-0000-0000-0000-000000000003/13-vecchia.jpg') = 'foto'$c$);
call t.prova('righe: socio sposta la sua foto nel bucket privato → negato', :S,
  $x$update public.foto set bucket = 'foto-private', url = '' where id = 'd0000000-0000-0000-0000-000000000001'$x$, 'negato');
call t.prova('righe: il direttivo sposta una foto di bucket → negato', :D,
  $x$update public.foto set bucket = 'foto-private', url = '' where id = 'd0000000-0000-0000-0000-000000000001'$x$, 'negato');
call t.verifica('righe: l''amministratore (trasferimento) sposta una foto nel bucket privato', null,
  $x$update public.foto set bucket = 'foto-private', url = '' where id = 'd0000000-0000-0000-0000-000000000001'$x$,
  $c$(select bucket = 'foto-private' and url = '' from public.foto where id = 'd0000000-0000-0000-0000-000000000001')$c$);
call t.prova('righe: socio scrive la didascalia di una sua foto privata → consentito', :S,
  $x$insert into public.foto (id, attivita_id, user_id, url, percorso, bucket) values ('d0000000-0000-0000-0000-0000000000f1', 'a0000000-0000-0000-0000-000000000001', auth.uid(), '', '00000000-0000-0000-0000-000000000003/14-p.jpg', 'foto-private');
     update public.foto set didascalia = 'Ciao' where id = 'd0000000-0000-0000-0000-0000000000f1'$x$, 'consentito');
call t.prova('righe: in attesa non vede le foto private → negato', :A, $x$select * from public.foto$x$, 'negato');
call t.verifica('permessi: controlla_foto non è eseguibile direttamente', null, 'select 1',
  $c$not has_function_privilege('authenticated', 'public.controlla_foto()', 'execute')
     and not has_function_privilege('anon', 'public.controlla_foto()', 'execute')$c$);

\pset format unaligned
\pset tuples_only on
\pset fieldsep '|'
select case when ok then 'PASS' else 'FAIL' end, nome, dettaglio from t.esiti order by n;
\pset format aligned
\pset tuples_only off
