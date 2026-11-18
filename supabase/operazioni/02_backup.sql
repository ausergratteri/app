-- =====================================================================
--  AUSER GRATTERI – copia di sicurezza DENTRO il database, prima della migrazione
--  Crea lo schema backup_20261118 (non esposto all'app: l'API vede solo "public").
--  Si può cancellare dopo qualche settimana: drop schema backup_20261118 cascade;
-- =====================================================================
begin;
create schema if not exists backup_20261118;
revoke all on schema backup_20261118 from public, anon, authenticated;

create table backup_20261118.profili      as table public.profili;
create table backup_20261118.tesserati    as table public.tesserati;
create table backup_20261118.attivita     as table public.attivita;
create table backup_20261118.assemblee    as table public.assemblee;
create table backup_20261118.adesioni     as table public.adesioni;
create table backup_20261118.bacheca      as table public.bacheca;
create table backup_20261118.impostazioni as table public.impostazioni;
create table backup_20261118.foto         as table public.foto;

-- Definizioni attuali di funzioni e regole, per confronto o ripristino a mano
create table backup_20261118.funzioni as
  select p.proname as nome, pg_get_functiondef(p.oid) as definizione
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
create table backup_20261118.regole as
  select schemaname, tablename, policyname, cmd, roles::text, qual, with_check
  from pg_policies where schemaname in ('public','storage');
create table backup_20261118.trigger as
  select tgrelid::regclass::text as tabella, tgname, pg_get_triggerdef(oid) as definizione
  from pg_trigger where not tgisinternal;
commit;

-- Verifica: i conteggi devono essere uguali a quelli delle tabelle originali
select 'profili' t, (select count(*) from public.profili) originale, (select count(*) from backup_20261118.profili) copia
union all select 'adesioni', (select count(*) from public.adesioni), (select count(*) from backup_20261118.adesioni)
union all select 'foto', (select count(*) from public.foto), (select count(*) from backup_20261118.foto)
union all select 'bacheca', (select count(*) from public.bacheca), (select count(*) from backup_20261118.bacheca)
union all select 'funzioni', (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f'), (select count(*) from backup_20261118.funzioni);
