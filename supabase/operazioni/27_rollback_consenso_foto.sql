-- =====================================================================
--  AUSER GRATTERI – rollback di 20261126_consenso_foto.sql
--  ATTENZIONE: MODIFICA LA PRODUZIONE e CANCELLA i consensi raccolti (profilo e storico).
--  Solo con autorizzazione esplicita del presidente e dopo un backup: lo storico dei consensi è la
--  prova da conservare. Riporta lo schema a prima della migrazione; non tocca foto, profili o altri dati.
-- =====================================================================
begin;
drop trigger if exists prima_di_cambiare_consenso on public.profili;
drop function if exists public.imposta_consenso_foto(boolean);
drop function if exists public.blocca_consenso_diretto();
drop table if exists public.consensi_foto;
alter table public.profili drop column if exists consenso_foto_il;
alter table public.profili drop column if exists consenso_foto;
alter table public.foto drop column if exists consenso_dichiarato;
commit;
