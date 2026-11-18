-- =====================================================================
--  AUSER GRATTERI – ROLLBACK della migrazione 20261119_importa_tesserati
--  Toglie la funzione di importazione, il registro e i vincoli di unicità.
--  Le colonne email e numero_tessera RESTANO (con i dati importati): toglierle
--  cancellerebbe quei dati. Se servisse davvero, vedere la parte B in fondo.
-- =====================================================================
begin;
drop function if exists public.importa_tesserati(jsonb, jsonb, text, int);
drop table if exists public.importazioni;
drop index if exists public.tesserati_telefono_unico;
drop index if exists public.tesserati_tessera_unica;
alter table public.tesserati drop constraint if exists tesserati_email_valida;
commit;

-- ---------- Parte B (facoltativa, CANCELLA i dati importati in queste colonne) ----------
-- alter table public.tesserati drop column if exists email;
-- alter table public.tesserati drop column if exists numero_tessera;
-- alter table public.tesserati drop column if exists origine;
-- alter table public.tesserati drop column if exists aggiornato_il;
