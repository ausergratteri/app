-- =====================================================================
--  AUSER GRATTERI – registrazione sicura con codice OTP via e-mail
--  Da eseguire DOPO 20261122_correzioni_retest.sql. Si può rieseguire.
--  NON tocca account, PIN, profili, adesioni, foto o tesserati esistenti.
--
--  Prima: chiunque conoscesse il telefono di un tesserato poteva registrarsi al suo
--  posto ed entrare subito come socio (punto aperto n. 1 di Strix, vuln-0001).
--  Ora:
--   * una registrazione diventa "socio" SOLO se passa dalla funzione server
--     "registrazione" (Edge Function) dopo un codice OTP inviato all'e-mail che
--     l'associazione ha in anagrafica (public.tesserati.email);
--   * qualsiasi altra registrazione (anche chiamando direttamente le API di Supabase
--     Auth) resta "in attesa" finché il direttivo non la approva;
--   * nessuno diventa più presidente registrandosi (prima: il primo iscritto quando
--     mancava un presidente). Su un database nuovo il presidente si nomina dal
--     SQL Editor con operazioni/14_nomina_primo_presidente.sql.
--  I codici e i gettoni non sono mai salvati in chiaro: solo impronte HMAC/SHA-256.
--  Le funzioni nuove sono eseguibili SOLO dal ruolo service_role (la funzione server).
-- =====================================================================
begin;

create extension if not exists pgcrypto with schema extensions;

-- ---------- 1. Richieste di registrazione (schema non esposto dalle API) ----------
create schema if not exists registrazione;
revoke all on schema registrazione from public, anon, authenticated;

create table if not exists registrazione.richieste (
  id            uuid primary key default gen_random_uuid(),
  tipo          text not null default 'otp' check (tipo in ('otp', 'manuale')),
  telefono      text not null,                 -- solo cifre, come public.solo_cifre_tel()
  tesserato_id  uuid references public.tesserati(id) on delete cascade,  -- null = nessuna corrispondenza
  otp_hash      text,                          -- HMAC del codice (mai il codice)
  otp_scade_il  timestamptz,
  tentativi     int not null default 0,
  verificata_il timestamptz,
  token_hash    text,                          -- SHA-256 del gettone monouso (mai il gettone)
  token_scade_il timestamptz,
  usata_il      timestamptz,
  ip_hash       text not null default '',      -- HMAC dell'indirizzo IP (mai l'IP)
  creata_il     timestamptz not null default now()
);
create index if not exists richieste_per_telefono on registrazione.richieste (telefono, creata_il);
create index if not exists richieste_per_ip on registrazione.richieste (ip_hash, creata_il);
alter table registrazione.richieste enable row level security;   -- nessuna regola: nessun accesso via API
revoke all on registrazione.richieste from public, anon, authenticated;

-- ---------- 2. Nome e cognome devono corrispondere alla voce dell'anagrafica ----------
-- Ogni parola scritta (nome e cognome, senza accenti e maiuscole) deve comparire nel
-- nome del tesserato, in qualsiasi ordine: "Maria" + "Rossi" va bene per "ROSSI MARIA GRAZIA".
create or replace function registrazione.parole(t text) returns text[]
language sql immutable set search_path = '' as $$
  select coalesce(array_agg(p), '{}') from unnest(regexp_split_to_array(
    translate(lower(coalesce(t, '')), 'àáâäèéêëìíîïòóôöùúûüç''’', 'aaaaeeeeiiiioooouuuuc  '), '[^a-z]+')) p
  where p <> '';
$$;
create or replace function registrazione.nomi_corrispondono(anagrafica text, nome text, cognome text)
returns boolean language sql immutable set search_path = '' as $$
  select cardinality(registrazione.parole(nome)) >= 1
     and cardinality(registrazione.parole(cognome)) >= 1
     and registrazione.parole(nome) || registrazione.parole(cognome) <@ registrazione.parole(anagrafica);
$$;

-- ---------- 3. Avvio: limiti, corrispondenza con l'anagrafica, nuova richiesta ----------
-- p_otp_hash = HMAC del codice calcolato dalla funzione server (il codice non arriva qui).
-- La risposta non dice MAI al chiamante se il numero è di un tesserato: "invia" e
-- "email" servono solo alla funzione server, che risponde sempre allo stesso modo.
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
  values ('otp', tel, t.id, case when t.id is not null then p_otp_hash end, now() + interval '10 minutes', p_ip_hash)
  returning id into nuova;
  return query select nuova, 'ok', t.id is not null, t.email, t.nome;
end $$;

-- ---------- 4. Verifica del codice: 5 tentativi, 10 minuti, una sola volta ----------
-- Se il codice è giusto restituisce un gettone monouso (valido 15 minuti) che serve
-- a scegliere il PIN. Il gettone è restituito una volta e salvato solo come SHA-256.
create or replace function public.registrazione_verifica(p_richiesta uuid, p_otp_hash text)
returns table (esito text, token text, tentativi_rimasti int)
language plpgsql security definer set search_path = public, extensions as $$
declare
  r registrazione.richieste;
  nuovo text;
  max_tentativi constant int := 5;
begin
  select * into r from registrazione.richieste where id = p_richiesta and tipo = 'otp' for update;
  if not found or r.usata_il is not null or r.verificata_il is not null then
    return query select 'non_valido', null::text, 0; return;
  end if;
  if r.tentativi >= max_tentativi then
    return query select 'bloccato', null::text, 0; return;
  end if;
  if now() > r.otp_scade_il then
    return query select 'scaduto', null::text, 0; return;
  end if;
  if r.otp_hash is null or coalesce(p_otp_hash, '') !~ '^[0-9a-f]{64}$' or r.otp_hash <> p_otp_hash then
    update registrazione.richieste set tentativi = tentativi + 1 where id = r.id;
    return query select case when r.tentativi + 1 >= max_tentativi then 'bloccato' else 'errato' end,
                        null::text, greatest(max_tentativi - r.tentativi - 1, 0);
    return;
  end if;
  nuovo := encode(extensions.gen_random_bytes(32), 'hex');
  update registrazione.richieste
     set verificata_il = now(), otp_hash = null, tentativi = tentativi + 1,
         token_hash = encode(extensions.digest(nuovo, 'sha256'), 'hex'),
         token_scade_il = now() + interval '15 minutes'
   where id = r.id;
  return query select 'ok', nuovo, max_tentativi - r.tentativi - 1;
end $$;

-- ---------- 5. Gettone ancora valido? (non lo consuma) ----------
-- Serve alla funzione server prima di creare l'account. Restituisce il telefono della
-- richiesta, perché l'indirizzo di accesso si ricava da lì e non da ciò che manda il client.
create or replace function public.registrazione_gettone(p_richiesta uuid, p_token text)
returns table (esito text, telefono text, nome text, account_in_attesa uuid)
language plpgsql security definer set search_path = public, extensions as $$
declare r registrazione.richieste; t public.tesserati; attesa uuid;
begin
  select * into r from registrazione.richieste where id = p_richiesta and tipo = 'otp';
  if not found or r.verificata_il is null or r.usata_il is not null or r.token_hash is null
     or now() > r.token_scade_il or r.tesserato_id is null
     or r.token_hash <> encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex') then
    return query select 'non_valido', null::text, null::text, null::uuid; return;
  end if;
  select * into t from public.tesserati where id = r.tesserato_id;
  if not found or public.solo_cifre_tel(t.telefono) <> r.telefono then
    return query select 'non_valido', null::text, null::text, null::uuid; return;
  end if;
  if exists (select 1 from public.profili p where public.solo_cifre_tel(p.telefono) = r.telefono and p.ruolo <> 'in_attesa') then
    return query select 'gia_registrato', null::text, null::text, null::uuid; return;
  end if;
  select p.id into attesa from public.profili p where public.solo_cifre_tel(p.telefono) = r.telefono and p.ruolo = 'in_attesa' limit 1;
  return query select 'ok', r.telefono, t.nome, attesa;
end $$;

-- ---------- 6. Consumo del gettone (usato dal trigger e per riprendere un account in attesa) ----------
-- Unico punto in cui una registrazione diventa "socio". Controlla tutto di nuovo, in modo
-- atomico, e segna la richiesta come usata: un secondo uso non è possibile.
create or replace function registrazione.consuma(p_richiesta uuid, p_token_hash text, p_telefono text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare r registrazione.richieste;
begin
  select * into r from registrazione.richieste where id = p_richiesta and tipo = 'otp' for update;
  if not found or r.verificata_il is null or r.usata_il is not null or r.token_hash is null
     or now() > r.token_scade_il or r.tesserato_id is null
     or r.token_hash <> coalesce(p_token_hash, '') or r.telefono <> coalesce(p_telefono, '') then
    return null;
  end if;
  if not exists (select 1 from public.tesserati t where t.id = r.tesserato_id and public.solo_cifre_tel(t.telefono) = r.telefono) then
    return null;
  end if;
  update registrazione.richieste set usata_il = now(), token_hash = null where id = r.id;
  return r.tesserato_id;
end $$;
revoke execute on function registrazione.consuma(uuid, text, text) from public, anon, authenticated;

-- ---------- 7. Riprendere un account "in attesa" con lo stesso numero ----------
-- Chi ha verificato l'e-mail dell'anagrafica prova di essere quel tesserato: un account
-- "in attesa" creato con il suo numero (anche da altri) diventa suo. La funzione server
-- ha già cambiato il PIN; qui si promuove a socio e si chiudono le sessioni aperte.
-- Gli account socio, direttivo e presidente NON si possono mai riprendere così.
create or replace function public.registrazione_riprendi(p_richiesta uuid, p_token text, p_utente uuid)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare tel text; ts uuid; nome_ts text;
begin
  select public.solo_cifre_tel(p.telefono) into tel from public.profili p where p.id = p_utente and p.ruolo = 'in_attesa';
  if tel is null or tel = '' then return 'non_valido'; end if;
  ts := registrazione.consuma(p_richiesta, encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex'), tel);
  if ts is null then return 'non_valido'; end if;
  select left(t.nome, 80) into nome_ts from public.tesserati t where t.id = ts;
  update public.profili set ruolo = 'socio', nome = coalesce(nullif(nome_ts, ''), nome) where id = p_utente;
  begin
    if to_regclass('auth.sessions') is not null then
      execute 'delete from auth.sessions where user_id = $1' using p_utente;
    end if;
  exception when insufficient_privilege then
    raise notice 'Sessioni non chiuse: permesso mancante su auth.sessions';
  end;
  return 'ok';
end $$;

-- ---------- 8. Registrazione manuale: solo limiti (l'account resta "in attesa") ----------
create or replace function public.registrazione_manuale_consentita(p_telefono text, p_ip_hash text)
returns text language plpgsql security definer set search_path = public as $$
declare tel text := public.solo_cifre_tel(p_telefono);
begin
  if tel !~ '^[0-9]{6,15}$' or length(coalesce(p_ip_hash, '')) < 16 then return 'dati_non_validi'; end if;
  perform pg_advisory_xact_lock(hashtext('auser.registrazione'), hashtext(tel));
  if (select count(*) from registrazione.richieste r where r.tipo = 'manuale' and r.telefono = tel and r.creata_il > now() - interval '1 day') >= 3
     or (select count(*) from registrazione.richieste r where r.tipo = 'manuale' and r.ip_hash = p_ip_hash and r.creata_il > now() - interval '1 hour') >= 5
     or (select count(*) from registrazione.richieste r where r.tipo = 'manuale' and r.creata_il > now() - interval '1 hour') >= 30 then
    return 'troppe_richieste';
  end if;
  insert into registrazione.richieste (tipo, telefono, ip_hash) values ('manuale', tel, p_ip_hash);
  return 'ok';
end $$;

-- ---------- 9. Nuovo profilo: "socio" solo con la prova OTP ----------
-- app_metadata (raw_app_meta_data) lo può scrivere solo chi usa la chiave service_role
-- (la funzione server): chi si registra da solo con le API di Auth può scrivere solo
-- user_metadata. Anche con app_metadata, la richiesta viene ricontrollata e consumata.
create or replace function public.nuovo_profilo() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  dominio constant text := '@soci.ausergratteri.app';  -- uguale a DOMINIO_FINTO in app.js
  tel text := '';
  meta jsonb := coalesce(new.raw_app_meta_data, '{}'::jsonb);
  ruolo_nuovo text := 'in_attesa';
  ts uuid;
  nome_ts text;
begin
  if lower(coalesce(new.email, '')) like '%' || dominio then
    tel := public.solo_cifre_tel(split_part(new.email, '@', 1));
  end if;
  -- Nessuno diventa presidente o direttivo registrandosi, nemmeno a database vuoto:
  -- il primo presidente lo nomina l'amministratore dal SQL Editor (operazioni/14).
  if tel <> '' and meta ? 'registrazione'
        and coalesce(meta->>'registrazione', '') ~ '^[0-9a-f-]{36}$'
        and not exists (select 1 from public.profili p where public.solo_cifre_tel(p.telefono) = tel) then
    ts := registrazione.consuma((meta->>'registrazione')::uuid, meta->>'registrazione_token', tel);
    if ts is not null then
      ruolo_nuovo := 'socio';
      select left(t.nome, 80) into nome_ts from public.tesserati t where t.id = ts;
    end if;
  end if;
  insert into public.profili (id, nome, telefono, ruolo)
  values (new.id, coalesce(nullif(nome_ts, ''), left(coalesce(new.raw_user_meta_data->>'nome', ''), 80)), tel, ruolo_nuovo);
  return new;
end $$;
revoke execute on function public.nuovo_profilo() from public, anon, authenticated;

-- ---------- 10. Permessi: solo la funzione server (service_role) ----------
do $$
declare f text;
begin
  foreach f in array array[
    'public.registrazione_avvia(text, text, text, text, text)',
    'public.registrazione_verifica(uuid, text)',
    'public.registrazione_gettone(uuid, text)',
    'public.registrazione_riprendi(uuid, text, uuid)',
    'public.registrazione_manuale_consentita(text, text)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    if exists (select 1 from pg_roles where rolname = 'service_role') then
      execute format('grant execute on function %s to service_role', f);
    end if;
  end loop;
end $$;
revoke execute on all functions in schema registrazione from public, anon, authenticated;

commit;
