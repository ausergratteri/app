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
--  Completamento (19/11/2026): il gettone si consuma UNA volta con una prenotazione atomica;
--  un eventuale account "in attesa" senza dati viene sostituito da un account NUOVO (mai
--  cambiato il PIN di un account esistente); la promozione a socio è atomica e legata alla
--  prenotazione e all'account appena creato.
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
alter table registrazione.richieste add column if not exists prenotazione_hash text;  -- SHA-256, mai in chiaro
alter table registrazione.richieste add column if not exists prenotata_il timestamptz;
alter table registrazione.richieste enable row level security;   -- nessuna regola: nessun accesso via API
revoke all on registrazione.richieste from public, anon, authenticated;

-- Funzioni sostituite dalla prenotazione/conferma (19/11/2026): rimosse se presenti
drop function if exists public.registrazione_gettone(uuid, text);
drop function if exists public.registrazione_riprendi(uuid, text, uuid);
drop function if exists registrazione.consuma(uuid, text, text);

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

-- ---------- 5. Prenotazione: consuma il gettone UNA volta ----------
-- FOR UPDATE mette in fila le richieste simultanee: la seconda trova token_hash già cancellato.
-- Qui non si tocca nessun account. Restituisce il telefono della richiesta (l'indirizzo di
-- accesso si ricava da lì, non da ciò che manda il client) e una prenotazione casuale valida
-- 2 minuti, di cui il database conserva solo l'impronta. Un account "in attesa" con dati propri
-- (ex socio riportato in attesa) non viene mai toccato: serve il direttivo.
create or replace function registrazione.ha_dati(u uuid) returns boolean
language sql stable security definer set search_path = public, storage as $$
  select exists (select 1 from public.adesioni where user_id = u)
      or exists (select 1 from public.foto where user_id = u)
      or exists (select 1 from public.importazioni where eseguita_da = u)
      or exists (select 1 from storage.objects o
                  where o.owner = u or o.owner_id = u::text
                     or (o.bucket_id in ('foto', 'foto-private') and (storage.foldername(o.name))[1] = u::text));
$$;
revoke execute on function registrazione.ha_dati(uuid) from public, anon, authenticated;

create or replace function public.registrazione_prenota(p_richiesta uuid, p_token_hash text)
returns table (esito text, prenotazione text, telefono text, nome text, account_in_attesa uuid)
language plpgsql security definer set search_path = public, extensions as $$
declare r registrazione.richieste; t public.tesserati; attesa uuid; pren text;
begin
  select * into r from registrazione.richieste where id = p_richiesta and tipo = 'otp' for update;
  if not found or r.verificata_il is null or r.usata_il is not null or r.token_hash is null
     or now() > r.token_scade_il or r.tesserato_id is null
     or coalesce(p_token_hash, '') !~ '^[0-9a-f]{64}$' or r.token_hash <> p_token_hash then
    return query select 'non_valido', null::text, null::text, null::text, null::uuid; return;
  end if;
  update registrazione.richieste set token_hash = null where id = r.id;   -- consumato da qui
  select * into t from public.tesserati where id = r.tesserato_id;
  if not found or public.solo_cifre_tel(t.telefono) <> r.telefono then
    return query select 'non_valido', null::text, null::text, null::text, null::uuid; return;
  end if;
  if exists (select 1 from public.profili p where public.solo_cifre_tel(p.telefono) = r.telefono and p.ruolo <> 'in_attesa') then
    return query select 'gia_registrato', null::text, null::text, null::text, null::uuid; return;
  end if;
  select p.id into attesa from public.profili p
   where public.solo_cifre_tel(p.telefono) = r.telefono and p.ruolo = 'in_attesa' limit 1;
  if attesa is not null and registrazione.ha_dati(attesa) then
    return query select 'serve_direttivo', null::text, null::text, null::text, null::uuid; return;
  end if;
  pren := encode(extensions.gen_random_bytes(32), 'hex');
  update registrazione.richieste
     set prenotazione_hash = encode(extensions.digest(pren, 'sha256'), 'hex'), prenotata_il = now()
   where id = r.id;
  return query select 'ok', pren, r.telefono, left(t.nome, 80), attesa;
end $$;

-- ---------- 6. Eliminazione dell'account "in attesa" da sostituire ----------
-- Solo se, nella stessa transazione, la prenotazione è valida, l'account è ancora "in attesa"
-- (FOR UPDATE: un'approvazione simultanea del direttivo vince) e non ha dati. Il PIN di un
-- account esistente non viene mai cambiato: si crea un account NUOVO, così le vecchie sessioni
-- e i vecchi token (legati al vecchio id) non diventano mai "socio". Sessioni e token di
-- rinnovo si cancellano a cascata.
create or replace function public.registrazione_elimina_attesa(p_richiesta uuid, p_prenotazione text, p_utente uuid)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare r registrazione.richieste;
begin
  select * into r from registrazione.richieste where id = p_richiesta and tipo = 'otp' for update;
  if not found or r.usata_il is not null or r.prenotazione_hash is null
     or now() > r.prenotata_il + interval '2 minutes'
     or r.prenotazione_hash <> encode(extensions.digest(coalesce(p_prenotazione, ''), 'sha256'), 'hex') then
    return 'non_valido';
  end if;
  perform 1 from public.profili p
    where p.id = p_utente and p.ruolo = 'in_attesa' and public.solo_cifre_tel(p.telefono) = r.telefono
    for update;
  if not found then return 'non_valido'; end if;
  if registrazione.ha_dati(p_utente) then return 'serve_direttivo'; end if;
  delete from auth.users where id = p_utente;
  return 'ok';
end $$;

-- ---------- 7. Conferma: unico punto in cui una registrazione OTP diventa "socio" ----------
-- Promuove SOLO l'account creato DOPO la prenotazione, una volta sola (FOR UPDATE).
create or replace function public.registrazione_conferma(p_richiesta uuid, p_prenotazione text, p_utente uuid)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare r registrazione.richieste; tel text; creato timestamptz; nome_ts text;
begin
  select * into r from registrazione.richieste where id = p_richiesta and tipo = 'otp' for update;
  if not found or r.usata_il is not null or r.prenotazione_hash is null
     or now() > r.prenotata_il + interval '2 minutes'
     or r.prenotazione_hash <> encode(extensions.digest(coalesce(p_prenotazione, ''), 'sha256'), 'hex') then
    return 'non_valido';
  end if;
  select public.solo_cifre_tel(p.telefono), u.created_at into tel, creato
    from public.profili p join auth.users u on u.id = p.id
   where p.id = p_utente and p.ruolo = 'in_attesa' for update of p;
  if tel is null or tel <> r.telefono or creato < r.prenotata_il then return 'non_valido'; end if;
  select left(t.nome, 80) into nome_ts from public.tesserati t
   where t.id = r.tesserato_id and public.solo_cifre_tel(t.telefono) = r.telefono;
  if not found then return 'non_valido'; end if;
  update registrazione.richieste set usata_il = now(), prenotazione_hash = null where id = r.id;
  update public.profili set ruolo = 'socio', nome = coalesce(nullif(nome_ts, ''), nome) where id = p_utente;
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
-- app_metadata non conta più: GoTrue lo scrive DOPO l'inserimento, quindi il trigger non lo
-- vedrebbe; la promozione avviene solo in registrazione_conferma.
create or replace function public.nuovo_profilo() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  dominio constant text := '@soci.ausergratteri.app';  -- uguale a DOMINIO_FINTO in app.js
  tel text := '';
begin
  if lower(coalesce(new.email, '')) like '%' || dominio then
    tel := public.solo_cifre_tel(split_part(new.email, '@', 1));
  end if;
  -- Ogni nuovo account nasce "in attesa", anche con app_metadata. Diventa "socio" solo con
  -- registrazione_conferma (funzione server, dopo il codice OTP) o con l'approvazione del
  -- direttivo. Nessuno diventa presidente o direttivo registrandosi, nemmeno a database
  -- vuoto: il primo presidente lo nomina l'amministratore dal SQL Editor (operazioni/14).
  insert into public.profili (id, nome, telefono, ruolo)
  values (new.id, left(coalesce(new.raw_user_meta_data->>'nome', ''), 80), tel, 'in_attesa');
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
    'public.registrazione_prenota(uuid, text)',
    'public.registrazione_elimina_attesa(uuid, text, uuid)',
    'public.registrazione_conferma(uuid, text, uuid)',
    'public.registrazione_manuale_consentita(text, text)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    if exists (select 1 from pg_roles where rolname = 'service_role') then
      execute format('grant execute on function %s to service_role', f);
    end if;
  end loop;
end $$;
revoke execute on all functions in schema registrazione from public, anon, authenticated;

commit;
