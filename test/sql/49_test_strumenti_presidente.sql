-- Strumenti del presidente (migrazione 20261125_strumenti_presidente.sql):
-- imposta_email_tesserato e annulla_registrazione. Va eseguito dopo 20_test_accessi.sql
-- (riusa t.esiti, t.prova) e dopo 47 (schema registrazione). Ogni prova è annullata alla fine.
-- Persone (10_dati_prova.sql): P presidente · D direttivo · S socia con iscrizioni · A in attesa senza dati.
truncate t.esiti;
do $$ begin perform set_config('request.jwt.claim.sub', '', false); end $$;
\set P '''00000000-0000-0000-0000-000000000001'''
\set D '''00000000-0000-0000-0000-000000000002'''
\set S '''00000000-0000-0000-0000-000000000003'''
\set A '''00000000-0000-0000-0000-000000000004'''
\set MARIA '(select id from public.tesserati where nome = ''Maria Rossi'')'

-- =====================================================================
-- 1. Permessi
-- =====================================================================
insert into t.esiti (nome, ok, dettaglio)
select 'permessi: anon non esegue ' || f, not has_function_privilege('anon', f, 'execute'), ''
  from unnest(array['public.imposta_email_tesserato(uuid,text)', 'public.annulla_registrazione(uuid)']) f;
insert into t.esiti (nome, ok, dettaglio)
select 'permessi: authenticated esegue ' || f || ' (il ruolo lo controlla la funzione)', has_function_privilege('authenticated', f, 'execute'), ''
  from unnest(array['public.imposta_email_tesserato(uuid,text)', 'public.annulla_registrazione(uuid)']) f;
insert into t.esiti (nome, ok, dettaglio)
select 'permessi: ' || f || ' è SECURITY DEFINER con search_path fisso',
       p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%'), ''
  from unnest(array['public.imposta_email_tesserato(uuid,text)', 'public.annulla_registrazione(uuid)']) f
  join pg_proc p on p.oid = f::regprocedure;

-- =====================================================================
-- 2. E-mail del tesserato: solo il presidente
-- =====================================================================
call t.prova('e-mail: anon cambia l''e-mail di un tesserato → negato', null,
  $x$select public.imposta_email_tesserato('00000000-0000-0000-0000-000000000000', 'a@esempio.it')$x$, 'negato');
call t.prova('e-mail: in attesa cambia l''e-mail → negato', :A,
  $x$select public.imposta_email_tesserato('00000000-0000-0000-0000-000000000000', 'a@esempio.it')$x$, 'negato');
call t.prova('e-mail: socio cambia l''e-mail → negato', :S,
  $x$select public.imposta_email_tesserato('00000000-0000-0000-0000-000000000000', 'a@esempio.it')$x$, 'negato');
call t.prova('e-mail: direttivo cambia l''e-mail → negato', :D,
  $x$select public.imposta_email_tesserato((select id from public.tesserati where nome = 'Maria Rossi'), 'a@esempio.it')$x$, 'negato');
call t.prova('e-mail: presidente scrive un''e-mail valida → consentito', :P,
  $x$select public.imposta_email_tesserato((select id from public.tesserati where nome = 'Maria Rossi'), 'maria@esempio.it')$x$, 'consentito');
call t.prova('e-mail: presidente scrive un''e-mail non valida → negato', :P,
  $x$select public.imposta_email_tesserato((select id from public.tesserati where nome = 'Maria Rossi'), 'maria-esempio.it')$x$, 'negato');
call t.prova('e-mail: presidente scrive un''e-mail con < > → negato', :P,
  $x$select public.imposta_email_tesserato((select id from public.tesserati where nome = 'Maria Rossi'), '<x>@esempio.it')$x$, 'negato');
call t.prova('e-mail: presidente scrive un''e-mail di oltre 254 caratteri → negato', :P,
  $x$select public.imposta_email_tesserato((select id from public.tesserati where nome = 'Maria Rossi'), repeat('a', 250) || '@esempio.it')$x$, 'negato');
call t.prova('e-mail: presidente su un tesserato inesistente → negato', :P,
  $x$select public.imposta_email_tesserato('00000000-0000-0000-0000-000000000000', 'a@esempio.it')$x$, 'negato');

-- Effetti (in una transazione annullata; i risultati si leggono con \gset prima del rollback)
insert into registrazione.richieste (id, tipo, telefono, otp_hash, otp_scade_il, token_hash, token_scade_il, ip_hash, verificata_il)
values ('e0000000-0000-0000-0000-0000000000a1', 'otp', '3331111111', repeat('a', 64), now() + interval '10 minutes', null, null, 'prova-49', null),
       ('e0000000-0000-0000-0000-0000000000a2', 'otp', '3331111111', null, null, repeat('b', 64), now() + interval '15 minutes', 'prova-49', now()),
       ('e0000000-0000-0000-0000-0000000000a3', 'otp', '3334444444', repeat('c', 64), now() + interval '10 minutes', null, null, 'prova-49', null);
begin;
select set_config('request.jwt.claim.sub', :P, true);
set local role authenticated;
select public.imposta_email_tesserato(:MARIA, '  Maria.Rossi@Esempio.IT ') as esito1 \gset
reset role;
select (email = 'maria.rossi@esempio.it') as norm, (aggiornato_il is not null) as agg from public.tesserati where nome = 'Maria Rossi' \gset
select count(*) = 0 as codici_annullati from registrazione.richieste where telefono = '3331111111' and (otp_hash is not null or token_hash is not null) \gset
select count(*) = 1 as altri_intatti from registrazione.richieste where id = 'e0000000-0000-0000-0000-0000000000a3' and otp_hash is not null \gset
set local role authenticated;
select public.imposta_email_tesserato((select id from public.tesserati where nome = 'Giovanni Bianchi'), 'maria.rossi@esempio.it') as esito2 \gset
select public.imposta_email_tesserato(:MARIA, '') as esito3 \gset
reset role;
select (email = '') as vuota from public.tesserati where nome = 'Maria Rossi' \gset
rollback;
do $$ begin perform set_config('request.jwt.claim.sub', '', false); end $$;
insert into t.esiti (nome, ok, dettaglio) values
  ('e-mail: risposta "ok"', :'esito1' = 'ok', :'esito1'),
  ('e-mail: salvata in minuscolo e senza spazi', :'norm', ''),
  ('e-mail: data di aggiornamento impostata', :'agg', ''),
  ('e-mail: codici e gettoni aperti di quel numero annullati', :'codici_annullati', ''),
  ('e-mail: richieste di altri numeri intatte', :'altri_intatti', ''),
  ('e-mail: indirizzo già di un altro tesserato → "ok_condivisa"', :'esito2' = 'ok_condivisa', :'esito2'),
  ('e-mail: vuota → l''e-mail viene tolta', :'esito3' = 'ok' and :'vuota', :'esito3');
delete from registrazione.richieste where ip_hash = 'prova-49';

-- =====================================================================
-- 3. Azzeramento del primo accesso: solo il presidente, solo senza dati
-- =====================================================================
call t.prova('azzera: anon → negato', null, $x$select public.annulla_registrazione('00000000-0000-0000-0000-000000000004')$x$, 'negato');
call t.prova('azzera: in attesa su un altro → negato', :A, $x$select public.annulla_registrazione('00000000-0000-0000-0000-000000000003')$x$, 'negato');
call t.prova('azzera: socio su chi è in attesa → negato', :S, $x$select public.annulla_registrazione('00000000-0000-0000-0000-000000000004')$x$, 'negato');
call t.prova('azzera: direttivo su chi è in attesa → negato', :D, $x$select public.annulla_registrazione('00000000-0000-0000-0000-000000000004')$x$, 'negato');
call t.prova('azzera: presidente su sé stesso → negato', :P, $x$select public.annulla_registrazione('00000000-0000-0000-0000-000000000001')$x$, 'negato');
call t.prova('azzera: presidente su un utente inesistente → negato', :P, $x$select public.annulla_registrazione('00000000-0000-0000-0000-000000000000')$x$, 'negato');
call t.prova('azzera: presidente su una socia con iscrizioni → negato (usa Nuovo PIN)', :P, $x$select public.annulla_registrazione('00000000-0000-0000-0000-000000000003')$x$, 'negato');
call t.prova('azzera: presidente su chi è in attesa senza dati → consentito', :P, $x$select public.annulla_registrazione('00000000-0000-0000-0000-000000000004')$x$, 'consentito');
call t.prova('azzera: presidente sul direttivo che ha un''iscrizione → negato', :P, $x$select public.annulla_registrazione('00000000-0000-0000-0000-000000000002')$x$, 'negato');

-- Un altro presidente non si azzera (chi è in attesa, senza dati, promosso a presidente in una transazione annullata)
begin;
update public.profili set ruolo = 'presidente' where id = '00000000-0000-0000-0000-000000000004';
select set_config('request.jwt.claim.sub', :P, true);
set local role authenticated;
create temp table t_msg (m text);
do $$ begin perform public.annulla_registrazione('00000000-0000-0000-0000-000000000004'); exception when others then insert into t_msg values (sqlerrm); end $$;
reset role;
select count(*) = 1 and (select coalesce(max(m), '') like '%di un presidente%' from t_msg) as altro_pres_intatto from auth.users where id = '00000000-0000-0000-0000-000000000004' \gset
rollback;
insert into t.esiti (nome, ok, dettaglio) values ('azzera: presidente su un altro presidente → negato, account intatto', :'altro_pres_intatto', '');

-- Effetti dell'azzeramento
insert into registrazione.richieste (id, tipo, telefono, otp_hash, otp_scade_il, ip_hash)
values ('e0000000-0000-0000-0000-0000000000b1', 'otp', '3333333333', repeat('d', 64), now() + interval '10 minutes', 'prova-49');
insert into auth.sessions (user_id) values ('00000000-0000-0000-0000-000000000004');
select count(*) as utenti_prima from auth.users \gset
begin;
select set_config('request.jwt.claim.sub', :P, true);
set local role authenticated;
select public.annulla_registrazione('00000000-0000-0000-0000-000000000004') as az \gset
reset role;
select (select count(*) from auth.users where id = '00000000-0000-0000-0000-000000000004') = 0
   and (select count(*) from public.profili where id = '00000000-0000-0000-0000-000000000004') = 0
   and (select count(*) from auth.sessions where user_id = '00000000-0000-0000-0000-000000000004') = 0 as via_tutto \gset
select count(*) = 0 as codici_az from registrazione.richieste where telefono = '3333333333' and otp_hash is not null \gset
select (select count(*) from auth.users) = :utenti_prima - 1 as altri_ok \gset
rollback;
do $$ begin perform set_config('request.jwt.claim.sub', '', false); end $$;
delete from registrazione.richieste where ip_hash = 'prova-49';
delete from auth.sessions where user_id = '00000000-0000-0000-0000-000000000004';
insert into t.esiti (nome, ok, dettaglio) values
  ('azzera: risposta "ok"', :'az' = 'ok', :'az'),
  ('azzera: account, profilo e sessioni eliminati', :'via_tutto', ''),
  ('azzera: codici aperti di quel numero annullati', :'codici_az', ''),
  ('azzera: gli altri account restano', :'altri_ok', '');
-- La socia con iscrizioni resta intatta dopo il tentativo negato
insert into t.esiti (nome, ok, dettaglio)
select 'azzera: dopo i tentativi, socia con iscrizioni ancora presente', count(*) = 1, '' from auth.users where id = '00000000-0000-0000-0000-000000000003';

\pset format unaligned
\pset tuples_only on
\pset fieldsep '|'
select case when ok then 'PASS' else 'FAIL' end, nome, dettaglio from t.esiti order by n;
\pset format aligned
\pset tuples_only off
