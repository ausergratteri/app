-- =====================================================================
--  AUSER GRATTERI – verifica in SOLA LETTURA (un'unica SELECT, nessuna modifica):
--  A. la funzione public.rls_auto_enable (origine, definizione, proprietario, permessi, dipendenze)
--  B. i trigger di evento che la usano e gli altri presenti
--  C. chi può creare oggetti in public; ruoli dei client
--  D. tabelle di public: RLS, permessi di anon/authenticated, regole che valgono per anon
--  E. funzioni eseguibili da anon
--  F. schemi di backup: tabelle e numero di righe (solo numeri)
--  Solo nomi tecnici, codice delle funzioni di sistema e numeri: nessun dato personale.
--  Da eseguire anche nel progetto di PROVA: se l'impronta di rls_auto_enable coincide, è la
--  funzione installata dalla piattaforma Supabase (nel progetto di prova nessuno l'ha creata).
-- =====================================================================
with
fn as (select p.* from pg_proc p where p.proname = 'rls_auto_enable'),
r(ord, sezione, voce, valore) as (
  -- A. La funzione
  select 100, 'A funzione', 'quante funzioni con questo nome', (select count(*) from fn)::text
  union all select 101, 'A funzione', 'schema.nome(argomenti)', (select string_agg(oid::regprocedure::text, ', ') from fn)
  union all select 102, 'A funzione', 'proprietario', (select string_agg(pg_get_userbyid(proowner)::text, ', ') from fn)
  union all select 103, 'A funzione', 'linguaggio / tipo restituito', (select string_agg((select lanname from pg_language l where l.oid = prolang) || ' / ' || prorettype::regtype::text, ', ') from fn)
  union all select 104, 'A funzione', 'security definer', (select string_agg(prosecdef::text, ', ') from fn)
  union all select 105, 'A funzione', 'impostazioni (search_path)', (select coalesce(string_agg(array_to_string(proconfig, ','), ', '), 'nessuna') from fn)
  union all select 106, 'A funzione', 'impronta del codice (md5, 16)', (select string_agg(left(md5(prosrc), 16), ', ') from fn)
  union all select 107, 'A funzione', 'commento', (select coalesce(string_agg(obj_description(oid, 'pg_proc'), ' | '), 'nessuno') from fn)
  union all select 108, 'A funzione', 'permessi (ACL)', (select coalesce(string_agg(coalesce(proacl::text, 'predefiniti (PUBLIC può eseguire)'), ', '), '-') from fn)
  union all select 109, 'A funzione', 'eseguibile da anon / authenticated',
    (select string_agg(has_function_privilege('anon', oid, 'execute') || ' / ' || has_function_privilege('authenticated', oid, 'execute'), ', ') from fn)
  union all select 110, 'A funzione', 'appartiene a un''estensione', (select coalesce(string_agg(e.extname, ', '), 'no') from fn join pg_depend d on d.classid = 'pg_proc'::regclass and d.objid = fn.oid and d.deptype = 'e' join pg_extension e on e.oid = d.refobjid)
  union all select 111, 'A funzione', 'oggetti che dipendono dalla funzione', (select coalesce(string_agg(d.classid::regclass::text || ':' || d.deptype::text, ', '), 'nessuno') from fn join pg_depend d on d.refclassid = 'pg_proc'::regclass and d.refobjid = fn.oid)
  union all select 112, 'A funzione', 'il codice FORZA la RLS (force row level security)', (select string_agg((prosrc ~* 'force\s+row\s+level\s+security')::text, ', ') from fn)
  union all select 113, 'A funzione', 'il codice ATTIVA la RLS (enable row level security)', (select string_agg((prosrc ~* 'enable\s+row\s+level\s+security')::text, ', ') from fn)
  union all select 114, 'A funzione', 'il codice usa SQL dinamico (execute)', (select string_agg((prosrc ~* '\mexecute\M')::text, ', ') from fn)
  union all select 115, 'A funzione', 'il codice contiene grant/revoke/drop/delete/alter role', (select string_agg((prosrc ~* '\m(grant|revoke|drop|delete|truncate)\M|alter\s+role')::text, ', ') from fn)
  union all select 119, 'A funzione', 'definizione completa', (select string_agg(pg_get_functiondef(oid), E'\n-----\n') from fn)
  -- B. Trigger di evento
  union all select 200 + row_number() over (order by e.evtname), 'B trigger di evento', e.evtname,
    'evento=' || e.evtevent || ' | attivo=' || (e.evtenabled <> 'D') || ' | funzione=' || e.evtfoid::regprocedure
    || ' | proprietario=' || pg_get_userbyid(e.evtowner) || ' | comandi=' || coalesce(array_to_string(e.evttags, ','), 'tutti')
    from pg_event_trigger e
  -- C. Chi può creare in public; ruoli dei client
  union all select 300, 'C creazione', 'anon / authenticated possono creare oggetti in public',
    has_schema_privilege('anon', 'public', 'CREATE') || ' / ' || has_schema_privilege('authenticated', 'public', 'CREATE')
  union all select 301, 'C ruoli', 'anon, authenticated: login / bypassrls / superuser',
    (select string_agg(rolname || '=' || rolcanlogin || '/' || rolbypassrls || '/' || rolsuper, ', ' order by rolname) from pg_roles where rolname in ('anon', 'authenticated'))
  union all select 302, 'C estensioni', 'pg_graphql installata', exists (select 1 from pg_extension where extname = 'pg_graphql')::text
  -- D. Tabelle di public
  union all select 400 + row_number() over (order by c.relname), 'D tabelle', c.relname,
    'rls=' || c.relrowsecurity || ' forzata=' || c.relforcerowsecurity
    || ' | anon S/I/U/D=' || has_table_privilege('anon', c.oid, 'SELECT')::int || has_table_privilege('anon', c.oid, 'INSERT')::int
    || has_table_privilege('anon', c.oid, 'UPDATE')::int || has_table_privilege('anon', c.oid, 'DELETE')::int
    || ' T/R/Tr=' || has_table_privilege('anon', c.oid, 'TRUNCATE')::int || has_table_privilege('anon', c.oid, 'REFERENCES')::int || has_table_privilege('anon', c.oid, 'TRIGGER')::int
    || ' | auth S/I/U/D=' || has_table_privilege('authenticated', c.oid, 'SELECT')::int || has_table_privilege('authenticated', c.oid, 'INSERT')::int
    || has_table_privilege('authenticated', c.oid, 'UPDATE')::int || has_table_privilege('authenticated', c.oid, 'DELETE')::int
    || ' T/R/Tr=' || has_table_privilege('authenticated', c.oid, 'TRUNCATE')::int || has_table_privilege('authenticated', c.oid, 'REFERENCES')::int || has_table_privilege('authenticated', c.oid, 'TRIGGER')::int
    || ' | regole=' || (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname)
    || ' di cui per anon/public=' || (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname and (p.roles && array['anon', 'public']::name[]))
    from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
  -- E. Funzioni di public eseguibili da anon
  union all select 500, 'E funzioni', 'eseguibili da anon e richiamabili dalle API',
    (select coalesce(string_agg(p.oid::regprocedure::text || case when p.prosecdef then ' [definer]' else '' end, ', ' order by p.proname), 'nessuna')
       from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')
        and p.prorettype not in ('trigger'::regtype, 'event_trigger'::regtype))
  union all select 501, 'E funzioni', 'di trigger (eseguibili da anon ma NON richiamabili dalle API)',
    (select coalesce(string_agg(p.oid::regprocedure::text, ', ' order by p.proname), 'nessuna')
       from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')
        and p.prorettype in ('trigger'::regtype, 'event_trigger'::regtype))
  -- F. Schemi di backup (solo numeri)
  union all select 600 + row_number() over (order by t.schemaname, t.tablename), 'F backup', t.schemaname || '.' || t.tablename,
    'righe=' || (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', t.schemaname, t.tablename), false, true, '')))[1]::text
    || ' | anon/authenticated usano lo schema=' || has_schema_privilege('anon', t.schemaname, 'USAGE') || '/' || has_schema_privilege('authenticated', t.schemaname, 'USAGE')
    from pg_tables t where t.schemaname like 'backup\_%'
)
select sezione, voce, valore from r order by ord;
