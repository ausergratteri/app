-- Consenso alle foto (migrazione 20261126_consenso_foto.sql). Va eseguito dopo 20_test_accessi.sql
-- (riusa t.esiti, t.prova, t.conta). Ogni prova è annullata alla fine; i dati aggiunti si tolgono.
-- Persone (10_dati_prova.sql): P presidente · D direttivo · S socia · A in attesa.
truncate t.esiti;
do $$ begin perform set_config('request.jwt.claim.sub', '', false); end $$;
\set P '''00000000-0000-0000-0000-000000000001'''
\set D '''00000000-0000-0000-0000-000000000002'''
\set S '''00000000-0000-0000-0000-000000000003'''
\set A '''00000000-0000-0000-0000-000000000004'''

-- 1. Permessi
insert into t.esiti (nome, ok, dettaglio) values
  ('permessi: anon non esegue imposta_consenso_foto', not has_function_privilege('anon', 'public.imposta_consenso_foto(boolean)', 'execute'), ''),
  ('permessi: authenticated esegue imposta_consenso_foto', has_function_privilege('authenticated', 'public.imposta_consenso_foto(boolean)', 'execute'), ''),
  ('permessi: anon non legge lo storico dei consensi', not has_table_privilege('anon', 'public.consensi_foto', 'select'), ''),
  ('permessi: authenticated non scrive direttamente lo storico',
     not has_table_privilege('authenticated', 'public.consensi_foto', 'insert') and not has_table_privilege('authenticated', 'public.consensi_foto', 'update')
     and not has_table_privilege('authenticated', 'public.consensi_foto', 'delete') and not has_table_privilege('authenticated', 'public.consensi_foto', 'truncate'), '');
insert into t.esiti (nome, ok, dettaglio)
select 'permessi: imposta_consenso_foto è SECURITY DEFINER con search_path fisso',
       p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%'), ''
  from pg_proc p where p.oid = 'public.imposta_consenso_foto(boolean)'::regprocedure;

-- 2. Chi può impostare il consenso
call t.prova('consenso: anon lo imposta → negato', null, $x$select public.imposta_consenso_foto(true)$x$, 'negato');
call t.prova('consenso: socia imposta il proprio → consentito', :S, $x$select public.imposta_consenso_foto(true)$x$, 'consentito');
call t.prova('consenso: in attesa imposta il proprio → consentito', :A, $x$select public.imposta_consenso_foto(false)$x$, 'consentito');
call t.prova('consenso: valore nullo → negato', :S, $x$select public.imposta_consenso_foto(null)$x$, 'negato');
call t.prova('consenso: socia lo cambia direttamente nel profilo (senza storico) → negato', :S,
  $x$update public.profili set consenso_foto = true where id = auth.uid()$x$, 'negato');
call t.prova('consenso: direttivo cambia quello della socia → negato', :D,
  $x$update public.profili set consenso_foto = true where id = '00000000-0000-0000-0000-000000000003'$x$, 'negato');
call t.prova('consenso: presidente cambia quello della socia → negato', :P,
  $x$update public.profili set consenso_foto = true, consenso_foto_il = now() where id = '00000000-0000-0000-0000-000000000003'$x$, 'negato');
call t.prova('consenso: socia scrive direttamente nello storico → negato', :S,
  $x$insert into public.consensi_foto (user_id, consenso) values (auth.uid(), true)$x$, 'negato');
call t.prova('consenso: il resto del profilo si modifica come prima (socia cambia il proprio nome) → consentito', :S,
  $x$update public.profili set nome = nome || ' ' where id = auth.uid()$x$, 'consentito');

-- 3. Effetti: dare e poi revocare il consenso (transazione annullata; risultati letti prima del rollback)
begin;
do $$ begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true); end $$;
set local role authenticated;
select public.imposta_consenso_foto(true) as r1 \gset
select public.imposta_consenso_foto(false) as r2 \gset
reset role;
select consenso_foto = false and consenso_foto_il is not null as profilo_ok from public.profili where id = :S \gset
select count(*) = 2 and bool_or(consenso) and not (array_agg(consenso order by id))[2] as storico_ok
  from public.consensi_foto where user_id = :S \gset
select count(*) = 0 as altri_ok from public.consensi_foto where user_id <> :S \gset
-- Lettura dello storico: la socia vede solo il suo, il direttivo vede tutto (righe di prova della stessa transazione)
insert into public.consensi_foto (user_id, consenso) values (:D, true);
set local role authenticated;
do $$ begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true); end $$;
select count(*) as visti_socia from public.consensi_foto \gset
do $$ begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true); end $$;
select count(*) as visti_direttivo from public.consensi_foto \gset
reset role;
rollback;
do $$ begin perform set_config('request.jwt.claim.sub', '', false); end $$;
insert into t.esiti (nome, ok, dettaglio) values
  ('effetti: risposte "ok"', :'r1' = 'ok' and :'r2' = 'ok', :'r1' || ' ' || :'r2'),
  ('effetti: nel profilo resta l''ultima scelta (revoca) con la data', :'profilo_ok', ''),
  ('effetti: nello storico restano entrambe le scelte, in ordine', :'storico_ok', ''),
  ('effetti: nessuna riga di storico per altre persone', :'altri_ok', ''),
  ('lettura: la socia vede solo il proprio storico', :visti_socia = 2, :'visti_socia' || ' righe'),
  ('lettura: il direttivo vede lo storico di tutti', :visti_direttivo = 3, :'visti_direttivo' || ' righe');

-- 4. Dichiarazione di chi carica la foto
insert into t.esiti (nome, ok, dettaglio)
select 'foto: colonna consenso_dichiarato presente, obbligatoria, predefinita false',
       is_nullable = 'NO' and column_default = 'false', coalesce(column_default, '')
  from information_schema.columns where table_schema = 'public' and table_name = 'foto' and column_name = 'consenso_dichiarato';
insert into t.esiti (nome, ok, dettaglio)
select 'foto: le foto già presenti restano senza dichiarazione', count(*) filter (where consenso_dichiarato) = 0, count(*) || ' foto'
  from public.foto;
call t.prova('foto: la socia carica una foto con la dichiarazione → consentito', :S,
  $x$insert into public.foto (attivita_id, user_id, url, percorso, bucket, consenso_dichiarato) values ('a0000000-0000-0000-0000-000000000001', auth.uid(), '', '00000000-0000-0000-0000-000000000003/55-nuova.jpg', 'foto-private', true)$x$, 'consentito');

\pset format unaligned
\pset tuples_only on
\pset fieldsep '|'
select case when ok then 'PASS' else 'FAIL' end, nome, dettaglio from t.esiti order by n;
\pset format aligned
\pset tuples_only off
