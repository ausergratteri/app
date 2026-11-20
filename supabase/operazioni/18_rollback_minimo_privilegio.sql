-- =====================================================================
--  AUSER GRATTERI – rollback di 20261124_minimo_privilegio_tabelle.sql
--  Ridà ad anon e authenticated TRUNCATE, REFERENCES e TRIGGER sulle 9 tabelle dell'app e
--  ripristina il privilegio predefinito per le tabelle future create da postgres in public,
--  cioè lo stato di partenza dei progetti Supabase (verificato con 17 PRIMA: 54 e
--  "postgres:anon/authenticated:TRUNCATE/REFERENCES/TRIGGER").
--  Riapre solo una difesa in profondità: le API non offrono questi comandi. Non tocca dati,
--  RLS, regole, funzioni o il DML dell'app. Dopo: rieseguire 17 (atteso di nuovo 54).
--  Usare SOLO se 20261124 avesse causato un problema.
-- =====================================================================
begin;
grant truncate, references, trigger on
  public.profili, public.attivita, public.assemblee, public.adesioni, public.bacheca,
  public.foto, public.tesserati, public.impostazioni, public.importazioni
  to anon, authenticated;
alter default privileges for role postgres in schema public
  grant truncate, references, trigger on tables to anon, authenticated;
commit;
