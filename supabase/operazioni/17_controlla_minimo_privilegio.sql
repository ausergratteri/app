-- =====================================================================
--  AUSER GRATTERI – controllo dei privilegi delle tabelle (migrazione 20261124). SOLA LETTURA.
--  Da eseguire PRIMA e DOPO 20261124_minimo_privilegio_tabelle.sql (e dopo un eventuale rollback 18).
--  Un'unica SELECT: controllo | valore | PRIMA (atteso) | DOPO (atteso).
--  Solo nomi tecnici e numeri.
-- =====================================================================
with
tab(t) as (values ('profili'), ('attivita'), ('assemblee'), ('adesioni'), ('bacheca'), ('foto'), ('tesserati'), ('impostazioni'), ('importazioni')),
ruoli(r) as (values ('anon'), ('authenticated')),
extra as (select r, t, p from ruoli, tab, unnest(array['TRUNCATE', 'REFERENCES', 'TRIGGER']) p where has_table_privilege(r, 'public.' || t, p)),
dml as (select r, t, p from ruoli, tab, unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) p where has_table_privilege(r, 'public.' || t, p)),
predef as (
  select pg_get_userbyid(d.defaclrole) as proprietario, a.grantee::regrole::text as ruolo, a.privilege_type as priv
    from pg_default_acl d, aclexplode(d.defaclacl) a
   where d.defaclnamespace = 'public'::regnamespace and d.defaclobjtype = 'r'
     and a.grantee in ('anon'::regrole, 'authenticated'::regrole)
     and a.privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER')),
r(ord, controllo, valore, prima, dopo) as (
  select 1, 'TRUNCATE/REFERENCES/TRIGGER di anon e authenticated sulle 9 tabelle', (select count(*) from extra)::text, '54', '0'
  union all select 2, '  di cui TRUNCATE (ignora la RLS)', (select count(*) from extra where p = 'TRUNCATE')::text, '18', '0'
  union all select 3, 'privilegi predefiniti per le tabelle FUTURE (proprietario:ruolo:privilegio)',
    coalesce((select string_agg(proprietario || ':' || ruolo || ':' || priv, ', ' order by 1) from predef), 'nessuno'), 'INFO', 'nessuno per postgres'
  union all select 4, 'proprietari dei privilegi predefiniti diversi da postgres',
    coalesce((select string_agg(distinct proprietario, ', ') from predef where proprietario <> 'postgres'), 'nessuno'), 'INFO', 'INFO'
  -- Il DML necessario all'app NON deve cambiare
  union all select 10, 'DML di authenticated (SELECT/INSERT/UPDATE/DELETE concessi)', (select count(*) from dml where r = 'authenticated')::text, 'INFO', 'uguale a PRIMA'
  union all select 11, 'DML di anon (deve essere solo impostazioni:SELECT)',
    coalesce((select string_agg(t || ':' || p, ', ' order by t, p) from dml where r = 'anon'), 'nessuno'), 'impostazioni:SELECT', 'impostazioni:SELECT'
  union all select 12, 'impronta del DML (per confrontare PRIMA e DOPO)',
    (select left(md5(string_agg(r || t || p, '|' order by r, t, p)), 12) from dml), 'INFO', 'uguale a PRIMA'
  -- Nessuna tabella senza RLS, nessuna RLS forzata
  union all select 20, 'tabelle di public senza RLS', (select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and not c.relrowsecurity)::text, '0', '0'
  union all select 21, 'tabelle di public con RLS forzata', (select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relforcerowsecurity)::text, '0', '0'
)
select controllo, valore, prima as "PRIMA (atteso)", dopo as "DOPO (atteso)" from r order by ord;
