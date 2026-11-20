-- =====================================================================
--  AUSER GRATTERI – misure per verificare un backup. SOLA LETTURA, un'unica SELECT.
--  Si esegue in PRODUZIONE subito prima del backup e poi, uguale, sulla copia ripristinata
--  (lo fa verifica_backup.sh): i valori devono coincidere.
--  Solo numeri e nomi tecnici: nessun nome, telefono, indirizzo, PIN o percorso di file.
-- =====================================================================
with m(ord, misura, valore) as (
  select 1, 'versione PostgreSQL (major)', current_setting('server_version_num')::int / 10000 || ''
  union all select 10, 'auth.users', (select count(*) from auth.users)::text
  union all select 11, 'auth.users con password', (select count(*) from auth.users where encrypted_password is not null and encrypted_password <> '')::text
  union all select 12, 'auth.identities', (select count(*) from auth.identities)::text
  union all select 20, 'profili per ruolo', (select coalesce(string_agg(ruolo || '=' || n, ', ' order by ruolo), 'nessuno') from (select ruolo, count(*) n from public.profili group by ruolo) x)
  union all select 21, 'tesserati / con e-mail', (select count(*) || ' / ' || count(*) filter (where email <> '') from public.tesserati)
  union all select 22, 'attivita', (select count(*) from public.attivita)::text
  union all select 23, 'assemblee', (select count(*) from public.assemblee)::text
  union all select 24, 'adesioni', (select count(*) from public.adesioni)::text
  union all select 25, 'bacheca', (select count(*) from public.bacheca)::text
  union all select 26, 'foto (righe)', (select count(*) from public.foto)::text
  union all select 27, 'impostazioni', (select count(*) from public.impostazioni)::text
  union all select 28, 'importazioni', (select count(*) from public.importazioni)::text
  union all select 29, 'registrazione: funzioni / richieste',
    (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'registrazione') || ' / ' ||
    coalesce((select (xpath('/row/c/text()', query_to_xml('select count(*) as c from registrazione.richieste', false, true, '')))[1]::text
              where to_regclass('registrazione.richieste') is not null), 'tabella assente')
  union all select 30, 'storage: bucket', (select coalesce(string_agg(id || (case when public then '(pubblico)' else '(privato)' end), ', ' order by id), 'nessuno') from storage.buckets)
  union all select 31, 'storage: oggetti per bucket', (select coalesce(string_agg(bucket_id || '=' || n, ', ' order by bucket_id), 'nessuno') from (select bucket_id, count(*) n from storage.objects group by bucket_id) x)
  union all select 32, 'storage: byte totali (dai metadati)', (select coalesce(sum((metadata->>'size')::bigint), 0) from storage.objects)::text
  union all select 40, 'schemi di backup: tabelle e righe',
    (select coalesce(string_agg(t.schemaname || '.' || t.tablename || '=' || (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', t.schemaname, t.tablename), false, true, '')))[1]::text, ', ' order by t.schemaname, t.tablename), 'nessuno')
       from pg_tables t where t.schemaname like 'backup\_%')
  union all select 50, 'impronta dei dati dell''app (12)',
    (select left(md5(
       coalesce((select string_agg(id::text || ruolo || telefono, '|' order by id) from public.profili), '') ||
       coalesce((select string_agg(id::text || telefono || email, '|' order by id) from public.tesserati), '') ||
       coalesce((select string_agg(id::text, '|' order by id) from public.adesioni), '') ||
       coalesce((select string_agg(id::text || coalesce(percorso, ''), '|' order by id) from public.foto), '')), 12))
  union all select 51, 'impronta degli account (12)',
    (select left(md5(coalesce(string_agg(id::text || coalesce(email, '') || coalesce(encrypted_password, ''), '|' order by id), '')), 12) from auth.users)
)
select misura, valore from m order by ord;
