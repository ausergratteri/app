-- =====================================================================
--  AUSER GRATTERI – strumenti del presidente per la registrazione con OTP
--  Da eseguire DOPO 20261123_registrazione_otp.sql e 20261124_minimo_privilegio_tabelle.sql.
--  Si può rieseguire. NON tocca dati esistenti: aggiunge solo due funzioni.
--
--  1. imposta_email_tesserato: il presidente scrive (o toglie) l'e-mail di un tesserato.
--     I codici già chiesti per quel numero smettono di valere.
--  2. annulla_registrazione: il presidente "azzera il primo accesso" di un socio, cioè ne
--     elimina l'account SOLO se non ha dati (iscrizioni, foto, file, importazioni). Il socio
--     rifà poi il primo accesso con il codice via e-mail. Mai su sé stesso né su un presidente.
--  Il controllo del ruolo è qui nel database (prima istruzione), non solo nell'app.
--  Rollback: supabase/operazioni/12_rollback_registrazione_otp.sql (toglie anche queste).
-- =====================================================================
begin;

-- ---------- 1. E-mail di un tesserato (solo presidente) ----------
-- Restituisce 'ok', oppure 'ok_condivisa' se lo stesso indirizzo è già di un altro
-- tesserato (permesso: es. coppie, ma l'app lo fa notare).
create or replace function public.imposta_email_tesserato(p_tesserato uuid, p_email text)
returns text language plpgsql security definer set search_path = public as $$
declare
  e text := lower(btrim(coalesce(p_email, '')));
  tel text;
begin
  if public.livello() < 3 then
    raise exception 'Solo il presidente può cambiare l''e-mail di un tesserato';
  end if;
  if e <> '' and (length(e) > 254 or e !~* '^[^@\s"''<>]+@[^@\s"''<>]+\.[^@\s"''<>]{2,}$') then
    raise exception 'E-mail non valida';
  end if;
  update public.tesserati set email = e, aggiornato_il = now()
   where id = p_tesserato
  returning public.solo_cifre_tel(telefono) into tel;
  if not found then raise exception 'Tesserato non trovato'; end if;
  -- I codici e i gettoni già chiesti per questo numero non valgono più
  if tel <> '' then
    update registrazione.richieste set otp_hash = null, token_hash = null
     where tipo = 'otp' and telefono = tel and usata_il is null;
  end if;
  return case when e <> '' and exists (select 1 from public.tesserati t where lower(t.email) = e and t.id <> p_tesserato)
              then 'ok_condivisa' else 'ok' end;
end $$;

-- ---------- 2. Azzeramento del primo accesso (solo presidente) ----------
create or replace function public.annulla_registrazione(p_utente uuid)
returns text language plpgsql security definer set search_path = public as $$
declare p public.profili;
begin
  if public.livello() < 3 then
    raise exception 'Solo il presidente può azzerare il primo accesso';
  end if;
  if p_utente is null or p_utente = auth.uid() then
    raise exception 'Non puoi azzerare il tuo primo accesso';
  end if;
  select * into p from public.profili where id = p_utente for update;
  if not found then raise exception 'Utente non trovato'; end if;
  if p.ruolo = 'presidente' then
    raise exception 'Non puoi azzerare il primo accesso di un presidente';
  end if;
  if registrazione.ha_dati(p_utente) then
    raise exception 'Ha già iscrizioni o foto: non si può azzerare, usa Nuovo PIN';
  end if;
  -- Codici e gettoni ancora aperti per quel numero non valgono più
  if public.solo_cifre_tel(p.telefono) <> '' then
    update registrazione.richieste set otp_hash = null, token_hash = null
     where tipo = 'otp' and telefono = public.solo_cifre_tel(p.telefono) and usata_il is null;
  end if;
  -- Profilo, sessioni e token di rinnovo cadono a cascata con l'account
  delete from auth.users where id = p_utente;
  return 'ok';
end $$;

-- ---------- 3. Permessi: utenti autenticati (il ruolo lo controlla la funzione) ----------
revoke execute on function public.imposta_email_tesserato(uuid, text) from public, anon;
revoke execute on function public.annulla_registrazione(uuid) from public, anon;
grant execute on function public.imposta_email_tesserato(uuid, text) to authenticated;
grant execute on function public.annulla_registrazione(uuid) to authenticated;

commit;
