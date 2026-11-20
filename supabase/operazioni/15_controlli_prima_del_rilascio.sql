-- =====================================================================
--  AUSER GRATTERI – controlli PRIMA del rilascio della registrazione con OTP
--  (20261123 + 20261124 + 20261125). SOLA LETTURA: un'unica SELECT, nessuna modifica.
--  Risultato: controllo | valore | atteso | esito (OK / ATTENZIONE / INFO).
--  Solo nomi tecnici e numeri: nessun nome, telefono, indirizzo o PIN.
--  Se un controllo è ATTENZIONE: fermarsi e non eseguire le migrazioni.
--  controlla_foto: 4fc9e77e se il database è stato aggiornato con le migrazioni (produzione),
--  6a6965d9 se installato da schema.sql: stesso codice, cambiano solo i commenti nella funzione.
-- =====================================================================
with
attese(f, imp) as (values
  ('acc_valido', '4cdf8da2'), ('conteggi', '67696af9'), ('controlla_adesione', 'dc51d1e8'),
  ('controlla_foto', '4fc9e77e|6a6965d9'), ('controlla_ruolo', 'cdb7ca58'), ('importa_tesserati', '36f1f714'),
  ('nuovo_profilo', 'd08f0d69'), ('reimposta_pin', 'bf88cbc1'), ('livello', '1d5541a5'),
  ('pulisci_adesioni', 'c7966924'), ('solo_cifre_tel', '2dcd1ade'), ('sveglia', 'ccea2d8b')),
pub as (select p.proname, left(md5(p.prosrc), 8) imp from pg_proc p where p.pronamespace = 'public'::regnamespace),
r(ord, controllo, valore, atteso) as (
  -- 1. Funzioni esistenti: devono essere quelle di 59be38f (punto di partenza delle migrazioni)
  select 10, 'impronta ' || a.f, coalesce(string_agg(pub.imp, ','), 'assente'), a.imp
    from attese a left join pub on pub.proname = a.f group by a.f, a.imp
  union all select 20, 'funzioni di public non previste', coalesce(string_agg(proname, ', ' order by proname), 'nessuna'), 'nessuna'
    from pub where proname not in (select f from attese) and proname <> 'rls_auto_enable'
  -- Funzione della piattaforma Supabase (trigger di evento ensure_rls): verificata con 16 (15.24); impronta del codice
  union all select 21, 'rls_auto_enable (piattaforma) impronta', coalesce((select left(md5(prosrc), 16) from pg_proc where proname = 'rls_auto_enable' and pronamespace = 'public'::regnamespace), 'assente'), 'c44fb229ea8a6b0a|assente'
  -- 2. Nulla dell'OTP è già presente
  union all select 30, 'schema registrazione presente', (to_regnamespace('registrazione') is not null)::text, 'false'
  union all select 31, 'funzioni registrazione_* / imposta_email_tesserato / annulla_registrazione', count(*)::text, '0'
    from pg_proc where proname like 'registrazione\_%' or proname in ('imposta_email_tesserato', 'annulla_registrazione')
  -- 3. Dipendenze delle migrazioni
  union all select 40, 'pgcrypto nello schema extensions', coalesce((select extnamespace::regnamespace::text from pg_extension where extname = 'pgcrypto'), 'assente'), 'extensions'
  union all select 41, 'storage.objects ha owner e owner_id',
    ((select count(*) from information_schema.columns where table_schema = 'storage' and table_name = 'objects' and column_name in ('owner', 'owner_id')) = 2)::text, 'true'
  union all select 42, 'auth.sessions presente', (to_regclass('auth.sessions') is not null)::text, 'true'
  union all select 43, 'trigger al_nuovo_utente su auth.users attivo',
    coalesce((select (tgenabled <> 'D')::text from pg_trigger where tgname = 'al_nuovo_utente' and tgrelid = 'auth.users'::regclass), 'assente'), 'true'
  union all select 44, 'tabella importazioni presente', (to_regclass('public.importazioni') is not null)::text, 'true'
  union all select 45, 'indice univoco del telefono dei tesserati', (to_regclass('public.tesserati_telefono_unico') is not null)::text, 'true'
  union all select 46, 'vincolo tesserati_email_valida presente', exists (select 1 from pg_constraint where conname = 'tesserati_email_valida')::text, 'true'
  union all select 47, 'telefoni dei tesserati ripetuti', (select count(*) from (select public.solo_cifre_tel(telefono) from public.tesserati where public.solo_cifre_tel(telefono) <> '' group by 1 having count(*) > 1) x)::text, '0'
  union all select 48, 'e-mail dei tesserati che violano il vincolo', (select count(*) from public.tesserati where email <> '' and email !~* '^[^@\s"''<>]+@[^@\s"''<>]+\.[^@\s"''<>]{2,}$')::text, '0'
  -- 4. Permessi: dopo 20261124 (applicata in produzione il 20/11) nessun TRUNCATE/REFERENCES/TRIGGER
  union all select 50, 'privilegi TRUNCATE/REFERENCES/TRIGGER di anon/authenticated sulle 9 tabelle',
    (select count(*) from unnest(array['anon','authenticated']) ro,
       unnest(array['profili','attivita','assemblee','adesioni','bacheca','foto','tesserati','impostazioni','importazioni']) tb,
       unnest(array['TRUNCATE','REFERENCES','TRIGGER']) pr
     where has_table_privilege(ro, 'public.' || tb, pr))::text, '0'
  union all select 51, 'funzioni eseguibili da anon (livello, conteggi, reimposta_pin, solo_cifre_tel, sveglia)',
    (select string_agg(f, ', ' order by f) from unnest(array['livello','conteggi','reimposta_pin','solo_cifre_tel','sveglia']) f
      where has_function_privilege('anon', (select oid from pg_proc where proname = f and pronamespace = 'public'::regnamespace limit 1), 'execute')), 'INFO'
  -- 5. Dati (solo numeri): servono a confrontare PRIMA e DOPO
  union all select 60, 'account (auth.users)', (select count(*) from auth.users)::text, 'INFO'
  union all select 61, 'profili per ruolo', (select string_agg(ruolo || '=' || n, ', ' order by ruolo) from (select ruolo, count(*) n from public.profili group by ruolo) x), 'INFO'
  union all select 62, 'presidenti', (select count(*) from public.profili where ruolo = 'presidente')::text, '1'
  union all select 63, 'account senza profilo', (select count(*) from auth.users u where not exists (select 1 from public.profili p where p.id = u.id))::text, '0'
  union all select 64, 'tesserati / con e-mail', (select count(*) || ' / ' || count(*) filter (where email <> '') from public.tesserati), 'INFO'
  union all select 65, 'adesioni / foto', (select count(*) from public.adesioni) || ' / ' || (select count(*) from public.foto), 'INFO'
  union all select 66, 'schemi di backup presenti', coalesce((select string_agg(nspname, ', ' order by nspname) from pg_namespace where nspname like 'backup\_%'), 'nessuno'), 'INFO'
)
select controllo, valore, atteso,
       case when atteso = 'INFO' then 'INFO' when valore = any(string_to_array(atteso, '|')) then 'OK' else 'ATTENZIONE' end as esito
  from r order by ord, controllo;
