-- Estende a 15 minuti la validità dei nuovi codici OTP.
-- Le richieste già emesse conservano la scadenza assegnata.
begin;

create or replace function public.registrazione_avvia(p_nome text, p_cognome text, p_telefono text,
                                                      p_ip_hash text, p_otp_hash text)
returns table (richiesta uuid, esito text, invia boolean, email text, nome text)
language plpgsql security definer set search_path = public, extensions as $$
declare
  tel text := public.solo_cifre_tel(p_telefono);
  t record;
  nuova uuid;
begin
  if tel !~ '^[0-9]{6,15}$' or length(coalesce(p_ip_hash, '')) < 16 or coalesce(p_otp_hash, '') !~ '^[0-9a-f]{64}$'
     or length(coalesce(p_nome, '')) > 80 or length(coalesce(p_cognome, '')) > 80 then
    return query select null::uuid, 'dati_non_validi', false, null::text, null::text; return;
  end if;
  perform pg_advisory_xact_lock(hashtext('auser.registrazione'), hashtext(tel));
  delete from registrazione.richieste where creata_il < now() - interval '7 days';
  -- Limiti uguali per tutti (tesserati e non): non rivelano nulla
  if exists (select 1 from registrazione.richieste r where r.telefono = tel and r.creata_il > now() - interval '60 seconds')
     or (select count(*) from registrazione.richieste r where r.telefono = tel and r.creata_il > now() - interval '1 hour') >= 3
     or (select count(*) from registrazione.richieste r where r.ip_hash = p_ip_hash and r.creata_il > now() - interval '1 hour') >= 10
     or (select count(*) from registrazione.richieste r where r.creata_il > now() - interval '1 hour') >= 60 then
    return query select null::uuid, 'troppe_richieste', false, null::text, null::text; return;
  end if;
  -- Le richieste precedenti dello stesso numero non valgono più
  update registrazione.richieste r set otp_hash = null, token_hash = null
   where r.telefono = tel and r.usata_il is null;
  -- Tesserato con quel telefono, nome corrispondente, e-mail valida in anagrafica, e nessun
  -- account già attivo (un account "in attesa" con lo stesso numero si può riprendere)
  select ts.id, ts.email, ts.nome into t
  from public.tesserati ts
  where public.solo_cifre_tel(ts.telefono) = tel
    and registrazione.nomi_corrispondono(ts.nome, p_nome, p_cognome)
    and ts.email ~* '^[^@\s"''<>]+@[^@\s"''<>]+\.[^@\s"''<>]{2,}$' and length(ts.email) <= 254
    and not exists (select 1 from public.profili p
                    where public.solo_cifre_tel(p.telefono) = tel and p.ruolo <> 'in_attesa')
  limit 1;
  insert into registrazione.richieste (tipo, telefono, tesserato_id, otp_hash, otp_scade_il, ip_hash)
  values ('otp', tel, t.id, case when t.id is not null then p_otp_hash end, now() + interval '15 minutes', p_ip_hash)
  returning id into nuova;
  return query select nuova, 'ok', t.id is not null, t.email, t.nome;
end $$;

commit;
