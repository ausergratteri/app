-- =====================================================================
--  AUSER GRATTERI – minimo privilegio sulle tabelle dell'app
--  Da eseguire DOPO 20261123_registrazione_otp.sql. Si può rieseguire.
--  NON tocca dati, regole (RLS), funzioni, trigger, service_role o schemi di sistema.
--
--  I progetti Supabase concedono per impostazione predefinita ad anon e authenticated
--  TRUNCATE (svuota una tabella ignorando la RLS), REFERENCES e TRIGGER sulle tabelle di
--  public. L'app usa solo SELECT/INSERT/UPDATE/DELETE concessi esplicitamente in schema.sql:
--  gli altri tre si tolgono, anche per le tabelle che verranno create in futuro.
-- =====================================================================
begin;

-- I progetti Supabase concedono per impostazione predefinita ad anon e authenticated anche
-- TRUNCATE (che ignora la RLS), REFERENCES e TRIGGER sulle nuove tabelle di public. L'app non li
-- usa: ai client restano solo i permessi concessi esplicitamente in schema.sql, filtrati dalla RLS.
-- service_role, il proprietario delle tabelle, le funzioni e i trigger esistenti non cambiano.
revoke truncate, references, trigger on
  public.profili, public.attivita, public.assemblee, public.adesioni, public.bacheca,
  public.foto, public.tesserati, public.impostazioni, public.importazioni
  from anon, authenticated;
-- Anche per le tabelle che il ruolo postgres creerà in futuro in public (es. dal pannello).
alter default privileges for role postgres in schema public
  revoke truncate, references, trigger on tables from anon, authenticated;

commit;
