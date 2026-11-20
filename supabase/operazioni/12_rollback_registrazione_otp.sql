-- =====================================================================
--  AUSER GRATTERI – rollback di 20261123_registrazione_otp.sql
--  Riporta la registrazione com'era nel commit 59be38f: chi si registra con il telefono
--  di un tesserato entra subito come socio (riapre il difetto vuln-0001).
--  NON tocca account, PIN, profili, adesioni, foto o tesserati. Toglie le funzioni della
--  registrazione con OTP e le richieste in corso (solo codici temporanei, già in forma
--  di impronta). Prima ripubblicare la versione precedente dell'app (registrazione diretta)
--  e, se era stata disattivata, riattivare "Allow new users to sign up" in Supabase Auth.
-- =====================================================================
begin;

-- Nuovo profilo come prima (59be38f)
create or replace function public.nuovo_profilo() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  dominio constant text := '@soci.ausergratteri.app';  -- uguale a DOMINIO_FINTO in app.js
  tel text := '';
begin
  perform pg_advisory_xact_lock(hashtext('auser.primo_presidente'));
  if lower(coalesce(new.email, '')) like '%' || dominio then
    tel := public.solo_cifre_tel(split_part(new.email, '@', 1));
  end if;
  insert into public.profili (id, nome, telefono, ruolo)
  values (
    new.id,
    left(coalesce(new.raw_user_meta_data->>'nome', ''), 80),
    tel,
    case
      when not exists (select 1 from public.profili where ruolo = 'presidente') then 'presidente'
      when tel <> ''
           and exists (select 1 from public.tesserati t where public.solo_cifre_tel(t.telefono) = tel)
           and not exists (select 1 from public.profili p where public.solo_cifre_tel(p.telefono) = tel)
        then 'socio'
      else 'in_attesa' end
  );
  return new;
end $$;

drop function if exists public.registrazione_avvia(text, text, text, text, text);
drop function if exists public.registrazione_verifica(uuid, text);
drop function if exists public.registrazione_gettone(uuid, text);
drop function if exists public.registrazione_riprendi(uuid, text, uuid);
drop function if exists public.registrazione_manuale_consentita(text, text);
drop function if exists public.registrazione_prenota(uuid, text);
drop function if exists public.registrazione_elimina_attesa(uuid, text, uuid);
drop function if exists public.registrazione_conferma(uuid, text, uuid);
-- Strumenti del presidente (20261125): usano lo schema registrazione
drop function if exists public.imposta_email_tesserato(uuid, text);
drop function if exists public.annulla_registrazione(uuid);
drop schema if exists registrazione cascade;   -- anche registrazione.ha_dati e le colonne della prenotazione

commit;
