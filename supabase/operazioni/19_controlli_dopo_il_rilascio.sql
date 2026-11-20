-- =====================================================================
--  AUSER GRATTERI – controlli DOPO 20261123 + 20261125 (registrazione OTP e strumenti del presidente).
--  SOLA LETTURA: un'unica SELECT. Risultato: controllo | valore | atteso | esito (OK / ATTENZIONE / INFO).
--  Solo nomi tecnici e numeri. Se c'è un'ATTENZIONE: fermarsi (rollback: 12_rollback_registrazione_otp.sql).
--  Valori dei dati attesi = misure B-0 del 20/11/2026 (15.25.2): nessun dato deve cambiare con le migrazioni.
-- =====================================================================
with
attese(f, imp) as (values
  -- funzioni nuove o cambiate
  ('nuovo_profilo', '3adac188'), ('registrazione_avvia', '6b704981'), ('registrazione_verifica', '771510cd'),
  ('registrazione_prenota', 'da45f1c3'), ('registrazione_elimina_attesa', '296211bf'), ('registrazione_conferma', '91b3efca'),
  ('registrazione_manuale_consentita', 'cf293dc3'), ('imposta_email_tesserato', '888dc02f'), ('annulla_registrazione', 'a750eaf9'),
  -- funzioni che NON devono cambiare
  ('acc_valido', '4cdf8da2'), ('conteggi', '67696af9'), ('controlla_adesione', 'dc51d1e8'), ('controlla_foto', '4fc9e77e|6a6965d9'),
  ('controlla_ruolo', 'cdb7ca58'), ('importa_tesserati', '36f1f714'), ('reimposta_pin', 'bf88cbc1'), ('livello', '1d5541a5'),
  ('pulisci_adesioni', 'c7966924'), ('solo_cifre_tel', '2dcd1ade'), ('sveglia', 'ccea2d8b')),
attese_reg(f, imp) as (values ('ha_dati', '77b8b175'), ('parole', '4d146bf2'), ('nomi_corrispondono', '26bd802d')),
fpub as (select p.oid, p.proname, left(md5(p.prosrc), 8) imp from pg_proc p where p.pronamespace = 'public'::regnamespace),
r(ord, controllo, valore, atteso) as (
  select 10, 'impronta ' || a.f, coalesce((select string_agg(imp, ',') from fpub where proname = a.f), 'assente'), a.imp from attese a
  union all select 15, 'impronta registrazione.' || a.f,
    coalesce((select string_agg(left(md5(p.prosrc), 8), ',') from pg_proc p where p.pronamespace = to_regnamespace('registrazione') and p.proname = a.f), 'assente'), a.imp
    from attese_reg a
  union all select 20, 'funzioni di public non previste',
    coalesce((select string_agg(proname, ', ' order by proname) from fpub where proname not in (select f from attese) and proname <> 'rls_auto_enable'), 'nessuna'), 'nessuna'
  -- Permessi
  union all select 30, 'registrazione_*: eseguibili da anon o authenticated',
    (select count(*) from fpub where proname like 'registrazione\_%' and (has_function_privilege('anon', oid, 'execute') or has_function_privilege('authenticated', oid, 'execute')))::text, '0'
  union all select 31, 'registrazione_*: eseguibili da service_role',
    (select count(*) from fpub where proname like 'registrazione\_%' and has_function_privilege('service_role', oid, 'execute'))::text, '6'
  union all select 32, 'strumenti del presidente: anon / authenticated',
    (select string_agg(proname || '=' || has_function_privilege('anon', oid, 'execute') || '/' || has_function_privilege('authenticated', oid, 'execute'), ', ' order by proname)
       from fpub where proname in ('annulla_registrazione', 'imposta_email_tesserato')), 'annulla_registrazione=false/true, imposta_email_tesserato=false/true'
  union all select 33, 'schema registrazione: usato da anon/authenticated',
    (has_schema_privilege('anon', 'registrazione', 'USAGE') or has_schema_privilege('authenticated', 'registrazione', 'USAGE'))::text, 'false'
  union all select 34, 'registrazione.richieste: RLS attiva / privilegi dei client',
    (select relrowsecurity::text from pg_class where oid = 'registrazione.richieste'::regclass) || ' / ' ||
    (has_table_privilege('anon', 'registrazione.richieste', 'SELECT') or has_table_privilege('authenticated', 'registrazione.richieste', 'SELECT'))::text, 'true / false'
  union all select 35, 'trigger al_nuovo_utente → nuovo_profilo, attivo',
    coalesce((select (tgfoid = 'public.nuovo_profilo()'::regprocedure and tgenabled <> 'D')::text from pg_trigger where tgname = 'al_nuovo_utente' and tgrelid = 'auth.users'::regclass), 'assente'), 'true'
  union all select 36, 'TRUNCATE/REFERENCES/TRIGGER di anon/authenticated sulle 9 tabelle (20261124)',
    (select count(*) from unnest(array['anon','authenticated']) ro,
       unnest(array['profili','attivita','assemblee','adesioni','bacheca','foto','tesserati','impostazioni','importazioni']) tb,
       unnest(array['TRUNCATE','REFERENCES','TRIGGER']) pr where has_table_privilege(ro, 'public.' || tb, pr))::text, '0'
  union all select 37, 'tabelle di public senza RLS / con RLS forzata',
    (select count(*) filter (where not relrowsecurity) || ' / ' || count(*) filter (where relforcerowsecurity) from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r'), '0 / 0'
  -- Dati: invariati rispetto a B-0 (le migrazioni non toccano dati)
  union all select 50, 'account (auth.users)', (select count(*) from auth.users)::text, '3'
  union all select 51, 'profili per ruolo', (select string_agg(ruolo || '=' || n, ', ' order by ruolo) from (select ruolo, count(*) n from public.profili group by ruolo) x), 'direttivo=1, presidente=1, socio=1'
  union all select 52, 'tesserati / con e-mail', (select count(*) || ' / ' || count(*) filter (where email <> '') from public.tesserati), '38 / 0'
  union all select 53, 'adesioni / foto', (select count(*) from public.adesioni) || ' / ' || (select count(*) from public.foto), '21 / 204'
  union all select 54, 'richieste di registrazione', (select count(*) from registrazione.richieste)::text, 'INFO'
)
select controllo, valore, atteso,
       case when atteso = 'INFO' then 'INFO' when valore = any(string_to_array(atteso, '|')) then 'OK' else 'ATTENZIONE' end as esito
  from r order by ord, controllo;
