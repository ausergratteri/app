-- Minimo privilegio sulle tabelle dell'app (migrazione 20261124_minimo_privilegio_tabelle.sql).
-- Va eseguito dopo 20_test_accessi.sql (riusa t.esiti). Lo stub riproduce i privilegi predefiniti
-- dei progetti Supabase (TRUNCATE, REFERENCES, TRIGGER ad anon e authenticated).
truncate t.esiti;

-- Nessun privilegio in più per i client
insert into t.esiti (nome, ok, dettaglio)
select 'privilegi: ' || r || ' senza TRUNCATE/REFERENCES/TRIGGER su ' || tab,
       not (has_table_privilege(r, tab, 'TRUNCATE') or has_table_privilege(r, tab, 'REFERENCES')
            or has_table_privilege(r, tab, 'TRIGGER')), ''
  from unnest(array['anon', 'authenticated']) r,
       unnest(array['public.profili', 'public.attivita', 'public.assemblee', 'public.adesioni', 'public.bacheca',
                    'public.foto', 'public.tesserati', 'public.impostazioni', 'public.importazioni']) tab;

-- I permessi dell'app restano esattamente quelli previsti
with atteso(tab, sel, ins, upd, del) as (values
  ('public.profili', true, true, true, true), ('public.attivita', true, true, true, true),
  ('public.assemblee', true, true, true, true), ('public.adesioni', true, true, true, true),
  ('public.bacheca', true, true, true, true), ('public.foto', true, true, true, true),
  ('public.tesserati', true, true, true, true), ('public.impostazioni', true, false, true, false),
  ('public.importazioni', true, false, false, false))
insert into t.esiti (nome, ok, dettaglio)
select 'privilegi: authenticated ha esattamente il DML previsto su ' || tab,
       has_table_privilege('authenticated', tab, 'SELECT') = sel and has_table_privilege('authenticated', tab, 'INSERT') = ins
       and has_table_privilege('authenticated', tab, 'UPDATE') = upd and has_table_privilege('authenticated', tab, 'DELETE') = del, ''
  from atteso;
insert into t.esiti (nome, ok, dettaglio)
select 'privilegi: anon legge solo le impostazioni',
       has_table_privilege('anon', 'public.impostazioni', 'SELECT')
       and not exists (select 1 from information_schema.role_table_grants g
                        where g.grantee = 'anon' and g.table_schema = 'public'
                          and not (g.table_name = 'impostazioni' and g.privilege_type = 'SELECT')), '';
insert into t.esiti (nome, ok, dettaglio)
select 'privilegi: la tabella privata delle richieste resta chiusa ai client',
       not (has_table_privilege('anon', 'registrazione.richieste', 'SELECT') or has_table_privilege('authenticated', 'registrazione.richieste', 'SELECT')), '';

-- Le tabelle create in futuro da postgres in public non ricevono più i tre privilegi
insert into t.esiti (nome, ok, dettaglio)
select 'privilegi predefiniti: nessun TRUNCATE/REFERENCES/TRIGGER per i client sulle tabelle future',
       not exists (select 1 from pg_default_acl d, aclexplode(d.defaclacl) a
                    where d.defaclnamespace = 'public'::regnamespace and d.defaclobjtype = 'r'
                      and d.defaclrole = 'postgres'::regrole
                      and a.grantee in ('anon'::regrole, 'authenticated'::regrole)
                      and a.privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER')), '';
create table public.prova_tabella_futura (x int);
insert into t.esiti (nome, ok, dettaglio)
select 'privilegi predefiniti: una tabella nuova non dà TRUNCATE/REFERENCES/TRIGGER ai client',
       not (has_table_privilege('anon', 'public.prova_tabella_futura', 'TRUNCATE') or has_table_privilege('anon', 'public.prova_tabella_futura', 'TRIGGER')
            or has_table_privilege('authenticated', 'public.prova_tabella_futura', 'TRUNCATE') or has_table_privilege('authenticated', 'public.prova_tabella_futura', 'REFERENCES')), '';
drop table public.prova_tabella_futura;

\pset format unaligned
\pset tuples_only on
\pset fieldsep '|'
select case when ok then 'PASS' else 'FAIL' end, nome, dettaglio from t.esiti order by n;
\pset format aligned
\pset tuples_only off
