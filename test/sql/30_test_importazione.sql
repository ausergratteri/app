-- Importazione dei tesserati: SOLO il presidente può importare, controllato nel database.
-- Va eseguito dopo 20_test_accessi.sql (riusa le procedure t.*).
-- t.prova esegue come ruolo "authenticated" con l'utente nel JWT: è esattamente
-- quello che succede chiamando l'API di Supabase (rpc) direttamente, senza l'app.
truncate t.esiti;
-- Una importazione precedente nel registro, per provare chi può leggerlo
insert into public.importazioni (file, righe_file, inseriti) values ('precedente.xls', 10, 10);
\set P '''00000000-0000-0000-0000-000000000001'''
\set D '''00000000-0000-0000-0000-000000000002'''
\set S '''00000000-0000-0000-0000-000000000003'''
\set A '''00000000-0000-0000-0000-000000000004'''

-- ---------- Chi può importare ----------
call t.prova('import: presidente importa chiamando l''API → consentito', :P,
  $x$select public.importa_tesserati('[{"nome":"Nuova Socia","telefono":"3330001111"}]', '[]', 'soci.xls', 1)$x$, 'consentito');
call t.prova('import: direttivo chiamando l''API → negato', :D,
  $x$select public.importa_tesserati('[{"nome":"X","telefono":"3330001111"}]', '[]')$x$, 'negato');
call t.prova('import: direttivo anche con lista vuota → negato', :D,
  $x$select public.importa_tesserati('[]', '[]')$x$, 'negato');
call t.prova('import: direttivo prova ad aggiornare con l''importazione → negato', :D,
  $x$select public.importa_tesserati('[]', jsonb_build_array(jsonb_build_object('id', (select id from public.tesserati limit 1), 'campi', '{"email":"x@x.it"}'::jsonb, 'attuali', '{}'::jsonb)))$x$, 'negato');
call t.prova('import: socio → negato', :S,
  $x$select public.importa_tesserati('[{"nome":"X","telefono":"3330001111"}]', '[]')$x$, 'negato');
call t.prova('import: in attesa → negato', :A,
  $x$select public.importa_tesserati('[]', '[]')$x$, 'negato');
call t.prova('import: anon → negato', null,
  $x$select public.importa_tesserati('[]', '[]')$x$, 'negato');
call t.verifica('import: dopo il rifiuto al direttivo nulla è cambiato e nulla è registrato', :D,
  $x$do $d$ begin perform public.importa_tesserati('[{"nome":"X","telefono":"3330009999"}]', '[]'); exception when others then null; end $d$$x$,
  $c$not exists (select 1 from public.tesserati where telefono = '3330009999') and (select count(*) from public.importazioni) = 1$c$);

-- ---------- Cosa fa l'importazione del presidente ----------
call t.verifica('import: presidente aggiunge nuovi tesserati con email e tessera, registrato a suo nome', :P,
  $x$select public.importa_tesserati('[{"nome":"Nuova Socia","telefono":"3330001111","email":"Nuova@Example.it ","numero_tessera":"000200"}]', '[]', 'soci.xls', 1)$x$,
  $c$exists (select 1 from public.tesserati where telefono = '3330001111' and email = 'nuova@example.it' and numero_tessera = '000200' and origine = 'import')
     and (select inseriti from public.importazioni order by eseguita_il desc limit 1) = 1
     and (select eseguita_da from public.importazioni order by eseguita_il desc limit 1) = '00000000-0000-0000-0000-000000000001'$c$);
call t.verifica('import: numero tessera con zeri iniziali salvato identico', :P,
  $x$select public.importa_tesserati('[{"nome":"Zeri","telefono":"3330002222","numero_tessera":"000045"},{"nome":"Sigla","telefono":"3330003333","numero_tessera":"PA-2026/0045"}]', '[]')$x$,
  $c$(select numero_tessera from public.tesserati where telefono = '3330002222') = '000045'
     and (select numero_tessera from public.tesserati where telefono = '3330003333') = 'PA-2026/0045'$c$);
call t.verifica('import: telefono già presente (scritto diverso) → saltato, non sovrascritto', :P,
  $x$select public.importa_tesserati('[{"nome":"Impostore","telefono":"+39 333 111 1111","email":"x@x.it"}]', '[]')$x$,
  $c$(select nome from public.tesserati where public.solo_cifre_tel(telefono) = '3331111111') = 'Maria Rossi'
     and (select saltati from public.importazioni order by eseguita_il desc limit 1) = 1$c$);
call t.verifica('import: aggiornamento confermato applicato solo ai campi scelti', :P,
  $x$select public.importa_tesserati('[]', jsonb_build_array(jsonb_build_object(
       'id', (select id from public.tesserati where nome = 'Maria Rossi'),
       'campi', '{"email":"maria@example.it"}'::jsonb,
       'attuali', '{"nome":"Maria Rossi","email":"","numero_tessera":""}'::jsonb)))$x$,
  $c$(select email = 'maria@example.it' and nome = 'Maria Rossi' and telefono = '333 111 1111' from public.tesserati where nome = 'Maria Rossi')$c$);
call t.verifica('import: dati cambiati da altri dopo l''anteprima → aggiornamento saltato', :P,
  $x$update public.tesserati set email = 'cambiata@example.it' where nome = 'Maria Rossi';
     select public.importa_tesserati('[]', jsonb_build_array(jsonb_build_object(
       'id', (select id from public.tesserati where nome = 'Maria Rossi'),
       'campi', '{"email":"vecchia@example.it"}'::jsonb,
       'attuali', '{"nome":"Maria Rossi","email":"","numero_tessera":""}'::jsonb)))$x$,
  $c$(select email from public.tesserati where nome = 'Maria Rossi') = 'cambiata@example.it'$c$);
call t.verifica('import: il telefono non si cambia con un aggiornamento', :P,
  $x$select public.importa_tesserati('[]', jsonb_build_array(jsonb_build_object(
       'id', (select id from public.tesserati where nome = 'Maria Rossi'),
       'campi', '{"telefono":"3339999999","nome":"Maria Rossi"}'::jsonb,
       'attuali', '{"nome":"Maria Rossi","email":"","numero_tessera":""}'::jsonb)))$x$,
  $c$(select telefono from public.tesserati where nome = 'Maria Rossi') = '333 111 1111'$c$);
call t.prova('import: numero tessera ripetuto → tutta l''importazione annullata', :P,
  $x$select public.importa_tesserati('[{"nome":"A","telefono":"3330004444","numero_tessera":"T1"},{"nome":"B","telefono":"3330005555","numero_tessera":"T1"}]', '[]')$x$, 'negato');
call t.verifica('import: dopo un errore nessuna riga parziale resta salvata', :P,
  $x$do $d$ begin perform public.importa_tesserati('[{"nome":"A","telefono":"3330004444","numero_tessera":"T1"},{"nome":"B","telefono":"3330005555","numero_tessera":"T1"}]', '[]');
     exception when others then null; end $d$$x$,
  $c$not exists (select 1 from public.tesserati where telefono in ('3330004444', '3330005555'))$c$);
call t.prova('import: riga senza telefono → negato', :P,
  $x$select public.importa_tesserati('[{"nome":"Senza","telefono":""}]', '[]')$x$, 'negato');
call t.prova('import: dati non in forma di lista → negato', :P,
  $x$select public.importa_tesserati('{"nome":"X"}', '[]')$x$, 'negato');

-- ---------- Registro delle importazioni ----------
call t.conta('registro: il presidente lo vede', :P, $q$select count(*) from public.importazioni$q$, 1);
call t.conta('registro: il direttivo lo vede (sola lettura, come prima)', :D, $q$select count(*) from public.importazioni$q$, 1);
call t.prova('registro: nessuno scrive direttamente → negato', :P,
  $x$insert into public.importazioni (file) values ('finto.xls')$x$, 'negato');
call t.conta('registro: il socio non lo vede', :S, $q$select count(*) from public.importazioni$q$, 0);

-- ---------- Il direttivo mantiene la gestione dei tesserati di sempre ----------
call t.prova('direttivo: aggiunge un tesserato a mano → consentito', :D,
  $x$insert into public.tesserati (nome, telefono) values ('A mano', '3330007777')$x$, 'consentito');
call t.prova('direttivo: corregge un tesserato → consentito', :D,
  $x$update public.tesserati set nome = 'Maria Rossi (Gratteri)' where nome = 'Maria Rossi'$x$, 'consentito');
call t.prova('direttivo: toglie un tesserato dall''elenco → consentito', :D,
  $x$delete from public.tesserati where nome = 'Giovanni Bianchi'$x$, 'consentito');
call t.conta('direttivo: vede i tesserati', :D, $q$select count(*) from public.tesserati$q$, 2);
call t.prova('direttivo: approva chi è in attesa → consentito', :D,
  $x$update public.profili set ruolo = 'socio' where id = '00000000-0000-0000-0000-000000000004'$x$, 'consentito');
call t.prova('regole: email non valida inserita a mano → negato', :D,
  $x$insert into public.tesserati (nome, telefono, email) values ('X', '3330006666', 'non-una-email')$x$, 'negato');
call t.prova('regole: due tesserati con lo stesso telefono → negato', :D,
  $x$insert into public.tesserati (nome, telefono) values ('Doppio', '+39 3334444444')$x$, 'negato');
call t.verifica('registrazione: un tesserato importato si registra come prima', null,
  $x$select set_config('request.jwt.claim.sub', '', true);
     insert into public.tesserati (nome, telefono, email, numero_tessera) values ('Importata', '3337770000', 'imp@example.it', '000300');
     insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000c1', '3337770000@soci.ausergratteri.app')$x$,
  $c$(select ruolo from public.profili where id = '00000000-0000-0000-0000-0000000000c1') = 'socio'$c$);

\pset format unaligned
\pset tuples_only on
\pset fieldsep '|'
select case when ok then 'PASS' else 'FAIL' end, nome, dettaglio from t.esiti order by n;
