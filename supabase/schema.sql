-- =====================================================================
--  AUSER GRATTERI – database dell'app soci
--  Da incollare UNA VOLTA in Supabase: menu "SQL Editor" → "New query"
--  → incolla tutto → "Run".
-- =====================================================================

-- ---------- Profili e ruoli ----------
-- ruolo: 'in_attesa' (appena registrato), 'socio', 'direttivo', 'presidente'
create table if not exists public.profili (
  id          uuid primary key references auth.users(id) on delete cascade,
  nome        text not null default '',
  telefono    text not null default '',
  ruolo       text not null default 'in_attesa'
              check (ruolo in ('in_attesa','socio','direttivo','presidente')),
  creato_il   timestamptz not null default now()
);

-- Il numero di telefono ridotto alle sole cifre, senza prefisso +39
create or replace function public.solo_cifre_tel(t text) returns text
language sql immutable as $$
  select case
    when length(d) = 14 and d like '0039%' then substr(d, 5)
    when length(d) = 12 and d like '39%' then substr(d, 3)
    else d end
  from (select regexp_replace(coalesce(t, ''), '\D', '', 'g') as d) x;
$$;

-- Elenco dei tesserati dell'anno (solo nome e telefono).
-- Chi si registra con un numero di questo elenco entra subito come socio, senza attendere.
create table if not exists public.tesserati (
  id         uuid primary key default gen_random_uuid(),
  nome       text not null,
  telefono   text not null default '',
  anno       int  not null default extract(year from now())::int,
  creato_il  timestamptz not null default now()
);
create index if not exists tesserati_per_telefono on public.tesserati (public.solo_cifre_tel(telefono));

-- Livello numerico del ruolo di chi sta usando l'app (0 = nessun accesso)
create or replace function public.livello() returns int
language sql stable security definer set search_path = public as $$
  select coalesce((
    select case ruolo when 'presidente' then 3 when 'direttivo' then 2 when 'socio' then 1 else 0 end
    from public.profili where id = auth.uid()
  ), 0);
$$;

-- Alla registrazione nasce il profilo (vedi migrations/20261123_registrazione_otp.sql).
-- Il telefono si ricava dall'email interna (<cifre>@soci.ausergratteri.app), unica in auth.users.
-- "socio" SOLO con la prova OTP della funzione server "registrazione"; altrimenti "in attesa".
-- Nessuno diventa presidente registrandosi: il primo presidente si nomina dal SQL Editor
-- (operazioni/14_nomina_primo_presidente.sql).
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


drop trigger if exists al_nuovo_utente on auth.users;
create trigger al_nuovo_utente after insert on auth.users
  for each row execute function public.nuovo_profilo();

-- Chi può cambiare i ruoli:
--  * il presidente può dare e togliere qualsiasi ruolo (tranne togliersi da solo);
--  * il direttivo può solo approvare (in_attesa ↔ socio);
--  * ognuno può cambiare il proprio nome, non il proprio ruolo;
--  * il telefono, la data di iscrizione e il nome degli altri li cambia solo il presidente.
create or replace function public.controlla_ruolo() returns trigger
language plpgsql security definer set search_path = public as $$
declare liv int := public.livello();
begin
  if auth.uid() is null then return new; end if;  -- modifiche dal pannello Supabase
  if new.ruolo is distinct from old.ruolo then
    if liv = 3 then
      if old.id = auth.uid() then raise exception 'Il presidente non può cambiare il proprio ruolo'; end if;
    elsif liv = 2 then
      if not (old.ruolo in ('in_attesa','socio') and new.ruolo in ('in_attesa','socio')) then
        raise exception 'Il direttivo può solo approvare i soci';
      end if;
    else
      raise exception 'Non puoi cambiare i ruoli';
    end if;
  end if;
  if liv < 3 and (new.telefono is distinct from old.telefono or new.creato_il is distinct from old.creato_il) then
    raise exception 'Non puoi cambiare il telefono';
  end if;
  if liv < 3 and old.id <> auth.uid() and new.nome is distinct from old.nome then
    raise exception 'Non puoi cambiare il nome di un''altra persona';
  end if;
  new.id := old.id;
  return new;
end $$;

drop trigger if exists prima_di_cambiare_profilo on public.profili;
create trigger prima_di_cambiare_profilo before update on public.profili
  for each row execute function public.controlla_ruolo();

alter table public.profili enable row level security;
drop policy if exists profili_leggi on public.profili;
create policy profili_leggi on public.profili for select
  using (id = auth.uid() or public.livello() >= 2);
drop policy if exists profili_modifica on public.profili;
create policy profili_modifica on public.profili for update
  using (id = auth.uid() or public.livello() >= 2)
  with check (id = auth.uid() or public.livello() >= 2);
drop policy if exists profili_elimina on public.profili;
create policy profili_elimina on public.profili for delete
  using (public.livello() >= 2 and id <> auth.uid() and ruolo in ('in_attesa','socio'));

-- ---------- Gite ed eventi ----------
create table if not exists public.attivita (
  id          uuid primary key default gen_random_uuid(),
  tipo        text not null default 'gita' check (tipo in ('gita','evento')),
  titolo      text not null,
  data        date not null,
  ora         text not null default '',
  luogo       text not null default '',
  ritrovo     text not null default '',
  costo       text not null default '',
  posti       int,
  scadenza    date,
  descrizione text not null default '',
  programma   text not null default '',
  ospiti      boolean not null default true,
  stato       text not null default 'aperta' check (stato in ('aperta','chiusa','annullata')),
  immagine    text not null default '',
  creato_il   timestamptz not null default now()
);
alter table public.attivita enable row level security;
drop policy if exists attivita_leggi on public.attivita;
create policy attivita_leggi on public.attivita for select using (public.livello() >= 1);
drop policy if exists attivita_crea on public.attivita;
create policy attivita_crea on public.attivita for insert with check (public.livello() >= 2);
drop policy if exists attivita_modifica on public.attivita;
create policy attivita_modifica on public.attivita for update using (public.livello() >= 2);
drop policy if exists attivita_elimina on public.attivita;
create policy attivita_elimina on public.attivita for delete using (public.livello() = 3);

-- ---------- Assemblee ----------
create table if not exists public.assemblee (
  id            uuid primary key default gen_random_uuid(),
  genere        text not null default 'ordinaria' check (genere in ('ordinaria','straordinaria')),
  prima_data    date not null,
  prima_ora     text not null default '',
  seconda_data  date,
  seconda_ora   text not null default '',
  luogo         text not null default '',
  odg           text[] not null default '{}',
  note          text not null default '',
  stato         text not null default 'convocata' check (stato in ('convocata','annullata')),
  creato_il     timestamptz not null default now()
);
alter table public.assemblee enable row level security;
drop policy if exists assemblee_leggi on public.assemblee;
create policy assemblee_leggi on public.assemblee for select using (public.livello() >= 1);
drop policy if exists assemblee_scrivi on public.assemblee;
create policy assemblee_scrivi on public.assemblee for all
  using (public.livello() = 3) with check (public.livello() = 3);

-- ---------- Adesioni (gite, eventi e presenze alle assemblee) ----------
-- user_id vuoto = iscritto a mano dal direttivo (WhatsApp, telefono, di persona)
create table if not exists public.adesioni (
  id           uuid primary key default gen_random_uuid(),
  attivita_id  uuid not null,
  user_id      uuid references public.profili(id) on delete cascade,
  nome         text not null,
  io           boolean not null default true,
  acc          jsonb not null default '[]'::jsonb,   -- [{ "nome": "...", "rel": "Familiare" }]
  note         text not null default '',
  canale       text not null default 'App',
  creato_il    timestamptz not null default now()
);
create unique index if not exists una_adesione_a_testa
  on public.adesioni (attivita_id, user_id) where user_id is not null;
create index if not exists adesioni_per_attivita on public.adesioni (attivita_id);

-- "acc" deve essere sempre una lista di al massimo 12 persone {nome, rel}:
-- un valore diverso faceva fallire conteggi() e bloccava l'app a tutti.
create or replace function public.acc_valido(j jsonb) returns boolean
language sql immutable set search_path = '' as $$
  select case
    when j is null or jsonb_typeof(j) <> 'array' then false
    when jsonb_array_length(j) > 12 then false
    else not exists (
      select 1 from jsonb_array_elements(j) e
      where jsonb_typeof(e) <> 'object'
         or jsonb_typeof(coalesce(e->'nome', '""'::jsonb)) <> 'string'
         or jsonb_typeof(coalesce(e->'rel',  '""'::jsonb)) not in ('string','null'))
  end;
$$;
alter table public.adesioni drop constraint if exists adesioni_acc_valido;
alter table public.adesioni add constraint adesioni_acc_valido check (public.acc_valido(acc)) not valid;

-- Togliendo un'attività o un'assemblea si tolgono anche le sue adesioni
create or replace function public.pulisci_adesioni() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from public.adesioni where attivita_id = old.id;
  if to_regclass('public.foto') is not null then
    execute 'delete from public.foto where attivita_id = $1' using old.id;
  end if;
  return old;
end $$;
drop trigger if exists via_adesioni_attivita on public.attivita;
create trigger via_adesioni_attivita after delete on public.attivita
  for each row execute function public.pulisci_adesioni();
drop trigger if exists via_adesioni_assemblee on public.assemblee;
create trigger via_adesioni_assemblee after delete on public.assemblee
  for each row execute function public.pulisci_adesioni();

alter table public.adesioni enable row level security;
-- Il socio vede solo la propria adesione; direttivo e presidente vedono tutto
drop policy if exists adesioni_leggi on public.adesioni;
create policy adesioni_leggi on public.adesioni for select
  using (public.livello() >= 2 or (public.livello() >= 1 and user_id = auth.uid()));
drop policy if exists adesioni_crea on public.adesioni;
create policy adesioni_crea on public.adesioni for insert
  with check ((user_id = auth.uid() and public.livello() >= 1 and canale = 'App') or public.livello() >= 2);
drop policy if exists adesioni_modifica on public.adesioni;
create policy adesioni_modifica on public.adesioni for update
  using (public.livello() >= 2 or (public.livello() >= 1 and user_id = auth.uid()))
  with check ((public.livello() >= 1 and user_id = auth.uid() and canale = 'App') or public.livello() >= 2);
drop policy if exists adesioni_elimina on public.adesioni;
create policy adesioni_elimina on public.adesioni for delete
  using (public.livello() >= 2 or (public.livello() >= 1 and user_id = auth.uid()));
-- Regole RESTRITTIVE (in AND con tutte le altre): chi è in attesa non tocca le adesioni,
-- un socio solo le sue (vedi migrations/20261122_correzioni_retest.sql)
drop policy if exists adesioni_solo_soci on public.adesioni;
create policy adesioni_solo_soci on public.adesioni as restrictive for all to anon, authenticated
  using (public.livello() >= 1) with check (public.livello() >= 1);
drop policy if exists adesioni_solo_proprie on public.adesioni;
create policy adesioni_solo_proprie on public.adesioni as restrictive for all to anon, authenticated
  using (public.livello() >= 2 or user_id = auth.uid())
  with check (public.livello() >= 2 or user_id = auth.uid());

-- Le regole dell'app valgono anche sul database. Il socio (non il direttivo) può
-- iscriversi o modificare solo se l'attività esiste ed è aperta, entro la scadenza,
-- con posti liberi per TUTTE le persone che porta (anche quando ne aggiunge modificando)
-- e senza ospiti dove non sono ammessi. Non può spostare l'iscrizione su un'altra
-- attività o persona. Le iscrizioni simultanee alla stessa attività passano una alla volta.
create or replace function public.controlla_adesione() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  liv int := public.livello();
  att public.attivita;
  ass public.assemblee;
  n_acc int := case when jsonb_typeof(new.acc) = 'array' then jsonb_array_length(new.acc) else 0 end;
  nuove int;      -- persone di questa iscrizione (lui/lei + familiari e amici)
  vecchie int := 0;
  occupati int;   -- persone delle ALTRE iscrizioni alla stessa attività
begin
  if auth.uid() is null or liv >= 2 then return new; end if;
  if tg_op = 'UPDATE' and (new.attivita_id is distinct from old.attivita_id or new.user_id is distinct from old.user_id) then
    raise exception 'Non puoi spostare l''iscrizione';
  end if;
  select * into att from public.attivita where id = new.attivita_id;
  if found then
    if att.stato <> 'aperta' or (att.scadenza is not null and att.scadenza < (now() at time zone 'Europe/Rome')::date) then
      raise exception 'Non puoi iscriverti: le iscrizioni sono chiuse';
    end if;
    if not att.ospiti and n_acc > 0 then
      raise exception 'Non puoi portare ospiti a questa attività';
    end if;
    if coalesce(att.posti, 0) > 0 then
      nuove := (case when new.io then 1 else 0 end) + n_acc;
      if tg_op = 'UPDATE' then
        vecchie := (case when old.io then 1 else 0 end)
                 + (case when jsonb_typeof(old.acc) = 'array' then jsonb_array_length(old.acc) else 0 end);
      end if;
      -- Si controlla quando si aggiungono persone: una nuova iscrizione o una modifica
      -- che porta più persone. Togliere persone è sempre permesso.
      if tg_op = 'INSERT' or nuove > vecchie then
        -- Iscrizioni simultanee alla stessa attività passano una alla volta: la seconda
        -- aspetta che la prima finisca e poi conta anche le sue persone.
        perform pg_advisory_xact_lock(hashtext('auser.posti'), hashtext(new.attivita_id::text));
        select coalesce(sum((case when a.io then 1 else 0 end)
                            + (case when jsonb_typeof(a.acc) = 'array' then jsonb_array_length(a.acc) else 0 end)), 0)
          into occupati from public.adesioni a
         where a.attivita_id = new.attivita_id and (tg_op = 'INSERT' or a.id <> old.id);
        if occupati + nuove > att.posti then
          raise exception 'Non puoi iscriverti: posti esauriti, restano % posti', greatest(att.posti - occupati, 0);
        end if;
      end if;
    end if;
    return new;
  end if;
  select * into ass from public.assemblee where id = new.attivita_id;
  if found then
    if ass.stato = 'annullata' then raise exception 'Non puoi iscriverti: l''assemblea è annullata'; end if;
    if n_acc > 0 then raise exception 'Non puoi portare ospiti a questa attività'; end if;
    return new;
  end if;
  raise exception 'Non puoi iscriverti: attività inesistente';
end $$;
drop trigger if exists prima_di_salvare_adesione on public.adesioni;
create trigger prima_di_salvare_adesione before insert or update on public.adesioni
  for each row execute function public.controlla_adesione();

-- Quante persone sono iscritte a ogni attività: lo vedono tutti i soci, senza i nomi
create or replace function public.conteggi()
returns table (attivita_id uuid, persone int)
language sql stable security definer set search_path = public as $$
  select a.attivita_id,
         sum((case when a.io then 1 else 0 end)
             + (case when jsonb_typeof(a.acc) = 'array' then jsonb_array_length(a.acc) else 0 end))::int
  from public.adesioni a
  where public.livello() >= 1
  group by a.attivita_id;
$$;

-- ---------- Tesserati: li vedono e modificano solo direttivo e presidente ----------
alter table public.tesserati enable row level security;
drop policy if exists tesserati_tutto on public.tesserati;
create policy tesserati_tutto on public.tesserati for all
  using (public.livello() >= 2) with check (public.livello() >= 2);

-- ---------- Bacheca ----------
create table if not exists public.bacheca (
  id         uuid primary key default gen_random_uuid(),
  tipo       text not null default 'avviso' check (tipo in ('avviso','facebook','instagram')),
  titolo     text not null default '',
  testo      text not null default '',
  link       text not null default '',
  immagine   text not null default '',
  data       timestamptz not null default now()
);
alter table public.bacheca enable row level security;
drop policy if exists bacheca_leggi on public.bacheca;
create policy bacheca_leggi on public.bacheca for select using (public.livello() >= 1);
drop policy if exists bacheca_scrivi on public.bacheca;
create policy bacheca_scrivi on public.bacheca for all
  using (public.livello() >= 2) with check (public.livello() >= 2);
-- Solo indirizzi web: niente "javascript:" o simili
alter table public.bacheca drop constraint if exists bacheca_link_web;
alter table public.bacheca add constraint bacheca_link_web
  check (link = '' or link ~* '^https?://') not valid;

-- ---------- Impostazioni (una sola riga) ----------
create table if not exists public.impostazioni (
  id         int primary key default 1 check (id = 1),
  sede       text not null default 'Gratteri',
  motto      text not null default 'Le attività, le gite e le assemblee della nostra associazione.',
  colore     text not null default '#1E7B3C',
  accento    text not null default '#F5B21A',
  logo       text not null default '',
  facebook   text not null default '',
  instagram  text not null default '',
  whatsapp   text not null default '',
  telefono   text not null default ''
);
insert into public.impostazioni (id) values (1) on conflict (id) do nothing;
-- Tema grafico scelto dal presidente (vale anche se il database è già stato creato)
alter table public.impostazioni add column if not exists tema text not null default 'bianco';
-- Solo i temi che l'app conosce (chiavi di TEMI in temi.js + personalizzato e automatico)
alter table public.impostazioni drop constraint if exists impostazioni_tema_valido;
alter table public.impostazioni add constraint impostazioni_tema_valido check (tema in (
  'bianco', 'classico', 'natale', 'vecchia', 'carnevale', 'pasqua', 'primavera', 'estate',
  'sangiacomo', 'autunno', 'personalizzato', 'automatico')) not valid;
alter table public.impostazioni add column if not exists tema_personalizzato jsonb not null default '{}'::jsonb;
alter table public.impostazioni enable row level security;
-- Leggibili anche prima dell'accesso, per mostrare logo e colori nella pagina di accesso
drop policy if exists impostazioni_leggi on public.impostazioni;
create policy impostazioni_leggi on public.impostazioni for select using (true);
drop policy if exists impostazioni_modifica on public.impostazioni;
create policy impostazioni_modifica on public.impostazioni for update using (public.livello() = 3);
alter table public.impostazioni drop constraint if exists impostazioni_link_web;
alter table public.impostazioni add constraint impostazioni_link_web
  check ((facebook = '' or facebook ~* '^https?://')
     and (instagram = '' or instagram ~* '^https?://')
     and (whatsapp = '' or whatsapp ~* '^https?://')) not valid;

-- ---------- Foto (logo, gite, bacheca e gallerie degli eventi) ----------
-- Ogni persona carica nella propria cartella; massimo 5 MB a foto (l'app le riduce prima).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('foto', 'foto', true, 5242880, array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists foto_leggi on storage.objects;
-- L'elenco dei file lo vedono solo i soci, non chi è ancora in attesa
create policy foto_leggi on storage.objects for select to authenticated
  using (bucket_id = 'foto' and public.livello() >= 1);
drop policy if exists foto_carica on storage.objects;
create policy foto_carica on storage.objects for insert to authenticated
  with check (bucket_id = 'foto' and public.livello() >= 1
              and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists foto_elimina on storage.objects;
create policy foto_elimina on storage.objects for delete to authenticated
  using (bucket_id = 'foto' and (public.livello() >= 2
         or (public.livello() >= 1 and (storage.foldername(name))[1] = auth.uid()::text)));

-- Bucket privato per le gallerie dei soci: si legge solo con URL temporanei firmati,
-- che può ottenere solo chi è socio. Niente SVG; nessuna regola di sovrascrittura.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('foto-private', 'foto-private', false, 5242880, array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists foto_private_leggi on storage.objects;
create policy foto_private_leggi on storage.objects for select to authenticated
  using (bucket_id = 'foto-private' and public.livello() >= 1);
drop policy if exists foto_private_carica on storage.objects;
create policy foto_private_carica on storage.objects for insert to authenticated
  with check (bucket_id = 'foto-private' and public.livello() >= 1
              and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists foto_private_elimina on storage.objects;
create policy foto_private_elimina on storage.objects for delete to authenticated
  using (bucket_id = 'foto-private' and (public.livello() >= 2
         or (public.livello() >= 1 and (storage.foldername(name))[1] = auth.uid()::text)));

-- Regole RESTRITTIVE sui due bucket delle foto (vedi migrations/20261121_permessi_foto_ruoli.sql):
-- valgono in AND con tutte le altre, così una regola troppo larga aggiunta in futuro
-- non fa entrare chi è in attesa e non lascia a un socio i file degli altri.
drop policy if exists foto_archivi_solo_soci on storage.objects;
create policy foto_archivi_solo_soci on storage.objects as restrictive for all to anon, authenticated
  using (case when bucket_id in ('foto', 'foto-private') then public.livello() >= 1 else true end)
  with check (case when bucket_id in ('foto', 'foto-private') then public.livello() >= 1 else true end);
drop policy if exists foto_archivi_carica_propria on storage.objects;
create policy foto_archivi_carica_propria on storage.objects as restrictive for insert to anon, authenticated
  with check (case when bucket_id in ('foto', 'foto-private')
                   then (storage.foldername(name))[1] = auth.uid()::text else true end);
drop policy if exists foto_archivi_modifica_propria on storage.objects;
create policy foto_archivi_modifica_propria on storage.objects as restrictive for update to anon, authenticated
  using (case when bucket_id in ('foto', 'foto-private')
              then public.livello() >= 2 or (storage.foldername(name))[1] = auth.uid()::text else true end)
  with check (case when bucket_id in ('foto', 'foto-private')
              then public.livello() >= 2 or (storage.foldername(name))[1] = auth.uid()::text else true end);
drop policy if exists foto_archivi_elimina_propria on storage.objects;
create policy foto_archivi_elimina_propria on storage.objects as restrictive for delete to anon, authenticated
  using (case when bucket_id in ('foto', 'foto-private')
              then public.livello() >= 2 or (storage.foldername(name))[1] = auth.uid()::text else true end);

-- Le foto delle gallerie: le pubblicano i soci, il direttivo può toglierle
create table if not exists public.foto (
  id           uuid primary key default gen_random_uuid(),
  attivita_id  uuid not null,
  user_id      uuid default auth.uid() references public.profili(id) on delete set null,
  autore       text not null default '',
  url          text not null,
  percorso     text not null default '',
  didascalia   text not null default '',
  creato_il    timestamptz not null default now(),
  bucket       text not null default 'foto'   -- 'foto' (pubblico) o 'foto-private'
);
alter table public.foto add column if not exists bucket text not null default 'foto';
alter table public.foto drop constraint if exists foto_bucket_valido;
alter table public.foto add constraint foto_bucket_valido check (bucket in ('foto', 'foto-private'));
-- Una foto privata non ha URL pubblico e ha sempre un percorso
alter table public.foto drop constraint if exists foto_privata_senza_url;
alter table public.foto add constraint foto_privata_senza_url
  check (bucket <> 'foto-private' or (url = '' and percorso <> ''));
create index if not exists foto_per_attivita on public.foto (attivita_id, creato_il);
alter table public.foto enable row level security;
drop policy if exists foto_righe_leggi on public.foto;
create policy foto_righe_leggi on public.foto for select using (public.livello() >= 1);
drop policy if exists foto_righe_crea on public.foto;
create policy foto_righe_crea on public.foto for insert
  with check (public.livello() >= 1 and user_id = auth.uid());
drop policy if exists foto_righe_modifica on public.foto;
create policy foto_righe_modifica on public.foto for update
  using (public.livello() >= 2 or (public.livello() >= 1 and user_id = auth.uid()))
  with check (public.livello() >= 2 or (public.livello() >= 1 and user_id = auth.uid()));
-- Regole RESTRITTIVE (in AND con tutte le altre): solo i soci, e un socio solo sulle sue foto
drop policy if exists foto_righe_solo_soci on public.foto;
create policy foto_righe_solo_soci on public.foto as restrictive for all to anon, authenticated
  using (public.livello() >= 1) with check (public.livello() >= 1);
drop policy if exists foto_righe_crea_proprie on public.foto;
create policy foto_righe_crea_proprie on public.foto as restrictive for insert to anon, authenticated
  with check (user_id = auth.uid());
drop policy if exists foto_righe_modifica_proprie on public.foto;
create policy foto_righe_modifica_proprie on public.foto as restrictive for update to anon, authenticated
  using (public.livello() >= 2 or user_id = auth.uid())
  with check (public.livello() >= 2 or user_id = auth.uid());
drop policy if exists foto_righe_elimina_proprie on public.foto;
create policy foto_righe_elimina_proprie on public.foto as restrictive for delete to anon, authenticated
  using (public.livello() >= 2 or user_id = auth.uid());

-- "percorso" deve stare nella cartella di chi ha caricato la foto: così eliminando
-- una foto non si può far cancellare il file di un'altra persona.
-- Si controlla solo quando il percorso viene scritto: se cambia solo user_id
-- (per esempio diventa vuoto perché il profilo è stato eliminato) va bene così.
create or replace function public.controlla_foto() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
  if tg_op = 'UPDATE' and new.bucket is distinct from old.bucket then
    raise exception 'Non puoi spostare la foto in un altro archivio';
  end if;
  if coalesce(new.percorso, '') <> ''
     and (tg_op = 'INSERT' or new.percorso is distinct from old.percorso)
     and (new.user_id is null
          or split_part(new.percorso, '/', 1) <> new.user_id::text
          or new.percorso like '%..%') then
    raise exception 'Non puoi usare questo percorso per la foto';
  end if;
  return new;
end $$;
drop trigger if exists prima_di_salvare_foto on public.foto;
create trigger prima_di_salvare_foto before insert or update on public.foto
  for each row execute function public.controlla_foto();
drop policy if exists foto_righe_elimina on public.foto;
create policy foto_righe_elimina on public.foto for delete
  using (public.livello() >= 2 or (public.livello() >= 1 and user_id = auth.uid()));

-- ---------- Nuovo PIN per chi l'ha dimenticato ----------
-- Il presidente lo può fare per tutti, il direttivo solo per i soci.
create extension if not exists pgcrypto with schema extensions;
create or replace function public.reimposta_pin(utente uuid, pin text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare liv int := public.livello(); r text;
begin
  if liv < 2 then raise exception 'Non puoi cambiare il PIN di questa persona'; end if;
  if pin is null or length(pin) < 6 then raise exception 'Il PIN deve avere almeno 6 cifre'; end if;
  select ruolo into r from public.profili where id = utente;
  if r is null then raise exception 'Utente non trovato'; end if;
  if not (liv = 3 or (liv = 2 and r in ('in_attesa','socio'))) then
    raise exception 'Non puoi cambiare il PIN di questa persona';
  end if;
  update auth.users set encrypted_password = extensions.crypt(pin, extensions.gen_salt('bf')) where id = utente;
  -- Chi aveva l'app aperta con il vecchio PIN deve rientrare
  begin
    if to_regclass('auth.sessions') is not null then
      execute 'delete from auth.sessions where user_id = $1' using utente;
    end if;
  exception when insufficient_privilege then
    raise notice 'Sessioni non chiuse: permesso mancante su auth.sessions';
  end;
end $$;

-- ---------- Funzione per tenere sveglio il progetto gratuito ----------
-- La chiama ogni 3 giorni GitHub (file .github/workflows/sveglia.yml)
create or replace function public.sveglia() returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from public.attivita;
$$;
grant execute on function public.sveglia() to anon;

-- ---------- Accesso dell'app alle tabelle (Data API) ----------
-- Dal 2026 i nuovi progetti Supabase non aprono più da soli le tabelle all'app:
-- qui le apriamo esplicitamente. Chi vede e modifica cosa resta deciso dalle regole qui sopra (RLS).
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on
  public.profili, public.attivita, public.assemblee, public.adesioni, public.bacheca, public.foto
  to authenticated;
grant select, update on public.impostazioni to authenticated;
grant select on public.impostazioni to anon;
grant select, insert, update, delete on public.tesserati to authenticated;
grant execute on function public.solo_cifre_tel(text) to authenticated;
grant execute on function public.livello() to authenticated;
grant execute on function public.conteggi() to authenticated;
grant execute on function public.reimposta_pin(uuid, text) to authenticated;
grant execute on function public.sveglia() to anon, authenticated;
-- Le funzioni dei trigger non servono a nessuno direttamente; acc_valido serve a chi
-- salva un'adesione (il vincolo la esegue con i permessi di chi scrive).
revoke execute on function public.acc_valido(jsonb) from public, anon;
grant execute on function public.acc_valido(jsonb) to authenticated;
revoke execute on function public.controlla_adesione() from public, anon, authenticated;
revoke execute on function public.controlla_foto() from public, anon, authenticated;

-- ---------- Importazione dei tesserati dal gestionale (vedi migrations/20261119_importa_tesserati.sql) ----------

-- ---------- 1. Nuovi dati dei tesserati ----------
alter table public.tesserati add column if not exists email          text not null default '';
alter table public.tesserati add column if not exists numero_tessera text not null default '';
alter table public.tesserati add column if not exists origine        text not null default 'manuale';
alter table public.tesserati add column if not exists aggiornato_il  timestamptz;

alter table public.tesserati drop constraint if exists tesserati_email_valida;
alter table public.tesserati add constraint tesserati_email_valida
  check (email = '' or email ~* '^[^@\s"''<>]+@[^@\s"''<>]+\.[^@\s"''<>]{2,}$') not valid;

-- ---------- 2. Il telefono identifica il tesserato; il numero tessera è unico ----------
do $$ begin
  if exists (select 1 from public.tesserati where public.solo_cifre_tel(telefono) <> ''
             group by public.solo_cifre_tel(telefono) having count(*) > 1) then
    raise exception 'Ci sono tesserati con lo stesso telefono: correggerli prima (controllo 12 in 01_controlli_preliminari.sql)';
  end if;
  if exists (select 1 from public.tesserati where numero_tessera <> '' group by numero_tessera having count(*) > 1) then
    raise exception 'Ci sono tesserati con lo stesso numero tessera: correggerli prima (controllo 13)';
  end if;
end $$;
create unique index if not exists tesserati_telefono_unico on public.tesserati (public.solo_cifre_tel(telefono))
  where public.solo_cifre_tel(telefono) <> '';
create unique index if not exists tesserati_tessera_unica on public.tesserati (numero_tessera)
  where numero_tessera <> '';

-- ---------- 3. Registro delle importazioni ----------
create table if not exists public.importazioni (
  id           uuid primary key default gen_random_uuid(),
  eseguita_da  uuid references public.profili(id) on delete set null,
  eseguita_il  timestamptz not null default now(),
  file         text not null default '',
  righe_file   int  not null default 0,
  inseriti     int  not null default 0,
  aggiornati   int  not null default 0,
  saltati      int  not null default 0
);
alter table public.importazioni enable row level security;
drop policy if exists importazioni_leggi on public.importazioni;
create policy importazioni_leggi on public.importazioni for select using (public.livello() >= 2);
grant select on public.importazioni to authenticated;

-- ---------- 4. Importazione (solo presidente): tutto o niente, solo ciò che è stato confermato ----------
--  nuovi:         [{nome, telefono, email, numero_tessera}]
--  aggiornamenti: [{id, campi: {nome?, email?, numero_tessera?}, attuali: {nome, email, numero_tessera}}]
--  Un nuovo tesserato con un telefono già presente viene saltato (mai sovrascritto).
--  Un aggiornamento si applica solo se il tesserato è ancora come nell'anteprima.
--  Il telefono non si cambia con l'importazione: è l'identificativo.
create or replace function public.importa_tesserati(nuovi jsonb, aggiornamenti jsonb, file text default '', righe_file int default 0)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r jsonb; c jsonb; a jsonb; t public.tesserati;
  tel text; n_ins int := 0; n_agg int := 0; n_salt int := 0;
begin
  -- Solo il presidente: il controllo è qui nel database, non solo nell'app
  if public.livello() < 3 then raise exception 'Non puoi importare i tesserati: solo il presidente'; end if;
  if jsonb_typeof(nuovi) is distinct from 'array' or jsonb_typeof(aggiornamenti) is distinct from 'array' then
    raise exception 'Dati di importazione non validi';
  end if;
  if jsonb_array_length(nuovi) + jsonb_array_length(aggiornamenti) > 5000 then
    raise exception 'Troppe righe in una sola importazione (massimo 5000)';
  end if;

  for r in select * from jsonb_array_elements(nuovi) loop
    tel := regexp_replace(coalesce(r->>'telefono', ''), '\D', '', 'g');
    if btrim(coalesce(r->>'nome', '')) = '' or length(tel) < 6 or length(tel) > 13 then
      raise exception 'Riga non valida: nome o telefono mancante';
    end if;
    if exists (select 1 from public.tesserati x where public.solo_cifre_tel(x.telefono) = public.solo_cifre_tel(tel)) then
      n_salt := n_salt + 1; continue;
    end if;
    insert into public.tesserati (nome, telefono, email, numero_tessera, origine, aggiornato_il)
    values (left(btrim(r->>'nome'), 120), tel, lower(btrim(coalesce(r->>'email', ''))),
            left(btrim(coalesce(r->>'numero_tessera', '')), 40), 'import', now());
    n_ins := n_ins + 1;
  end loop;

  for r in select * from jsonb_array_elements(aggiornamenti) loop
    c := coalesce(r->'campi', '{}'::jsonb); a := coalesce(r->'attuali', '{}'::jsonb);
    select * into t from public.tesserati where id = (r->>'id')::uuid for update;
    if not found
       or t.nome is distinct from coalesce(a->>'nome', '')
       or t.email is distinct from coalesce(a->>'email', '')
       or t.numero_tessera is distinct from coalesce(a->>'numero_tessera', '') then
      n_salt := n_salt + 1; continue;
    end if;
    update public.tesserati set
      nome           = case when c ? 'nome' and btrim(c->>'nome') <> '' then left(btrim(c->>'nome'), 120) else nome end,
      email          = case when c ? 'email' then lower(btrim(c->>'email')) else email end,
      numero_tessera = case when c ? 'numero_tessera' then left(btrim(c->>'numero_tessera'), 40) else numero_tessera end,
      aggiornato_il  = now()
    where id = t.id;
    n_agg := n_agg + 1;
  end loop;

  insert into public.importazioni (eseguita_da, file, righe_file, inseriti, aggiornati, saltati)
  values (auth.uid(), left(coalesce(file, ''), 120), greatest(coalesce(righe_file, 0), 0), n_ins, n_agg, n_salt);
  return jsonb_build_object('inseriti', n_ins, 'aggiornati', n_agg, 'saltati', n_salt);
end $$;
revoke execute on function public.importa_tesserati(jsonb, jsonb, text, int) from public, anon;
grant execute on function public.importa_tesserati(jsonb, jsonb, text, int) to authenticated;

-- =====================================================================
--  Registrazione sicura con codice OTP via e-mail (vedi migrations/20261123_registrazione_otp.sql)
-- =====================================================================
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
  values ('otp', tel, t.id, case when t.id is not null then p_otp_hash end, now() + interval '15 minutes', p_ip_hash)
  returning id into nuova;
  return query select nuova, 'ok', t.id is not null, t.email, t.nome;
end $$;

-- ---------- 4. Verifica del codice: 5 tentativi, 15 minuti, una sola volta ----------
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

-- ---------- Minimo privilegio sulle tabelle dell'app (vedi migrations/20261124_minimo_privilegio_tabelle.sql) ----------
-- I progetti Supabase concedono per impostazione predefinita ad anon e authenticated anche
-- TRUNCATE (che ignora la RLS), REFERENCES e TRIGGER sulle nuove tabelle di public. L'app non li
-- usa: ai client restano solo i permessi concessi esplicitamente sopra, sempre filtrati dalla RLS.
-- service_role, il proprietario delle tabelle, le funzioni e i trigger esistenti non cambiano.
revoke truncate, references, trigger on
  public.profili, public.attivita, public.assemblee, public.adesioni, public.bacheca,
  public.foto, public.tesserati, public.impostazioni, public.importazioni
  from anon, authenticated;
-- Anche per le tabelle che il ruolo postgres creerà in futuro in public (es. dal pannello).
alter default privileges for role postgres in schema public
  revoke truncate, references, trigger on tables from anon, authenticated;

-- ---------- Strumenti del presidente (vedi migrations/20261125_strumenti_presidente.sql) ----------
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


-- ---------- Consenso alle foto (vedi migrations/20261126_consenso_foto.sql) ----------

-- ---------- 1. Consenso del socio ----------
alter table public.profili add column if not exists consenso_foto boolean;        -- null = non ancora risposto
alter table public.profili add column if not exists consenso_foto_il timestamptz;  -- data dell'ultima scelta

create table if not exists public.consensi_foto (
  id       bigint generated always as identity primary key,
  user_id  uuid not null references public.profili(id) on delete cascade,
  consenso boolean not null,
  il       timestamptz not null default now()
);
create index if not exists consensi_foto_per_utente on public.consensi_foto (user_id, il);
alter table public.consensi_foto enable row level security;
revoke all on public.consensi_foto from anon, authenticated;
grant select on public.consensi_foto to authenticated;
drop policy if exists consensi_foto_leggi on public.consensi_foto;
create policy consensi_foto_leggi on public.consensi_foto for select
  using (user_id = auth.uid() or public.livello() >= 2);

-- Il consenso si cambia solo con la funzione qui sotto (che scrive anche lo storico)
create or replace function public.blocca_consenso_diretto() returns trigger
language plpgsql set search_path = public as $$
begin
  if (new.consenso_foto is distinct from old.consenso_foto or new.consenso_foto_il is distinct from old.consenso_foto_il)
     and coalesce(current_setting('auser.consenso_foto', true), '') <> '1' then
    raise exception 'Il consenso alle foto lo cambia solo la persona interessata, dalla sua app';
  end if;
  return new;
end $$;
revoke execute on function public.blocca_consenso_diretto() from public, anon, authenticated;
drop trigger if exists prima_di_cambiare_consenso on public.profili;
create trigger prima_di_cambiare_consenso before update on public.profili
  for each row execute function public.blocca_consenso_diretto();

create or replace function public.imposta_consenso_foto(p_consenso boolean) returns text
language plpgsql security definer set search_path = public as $$
declare u uuid := auth.uid();
begin
  if u is null or p_consenso is null then raise exception 'Dati non validi'; end if;
  if not exists (select 1 from public.profili where id = u) then raise exception 'Profilo non trovato'; end if;
  perform set_config('auser.consenso_foto', '1', true);
  update public.profili set consenso_foto = p_consenso, consenso_foto_il = now() where id = u;
  perform set_config('auser.consenso_foto', '', true);
  insert into public.consensi_foto (user_id, consenso) values (u, p_consenso);
  return 'ok';
end $$;
revoke execute on function public.imposta_consenso_foto(boolean) from public, anon;
grant execute on function public.imposta_consenso_foto(boolean) to authenticated;

-- ---------- 2. Dichiarazione di chi carica la foto ----------
alter table public.foto add column if not exists consenso_dichiarato boolean not null default false;

-- Minimo privilegio anche sulla tabella nuova (come 20261124)
revoke truncate, references, trigger on public.consensi_foto from anon, authenticated;


-- ---------- Gestione ex soci ----------

alter table public.profili add column if not exists ex_socio_dal timestamptz;

create or replace function public.livello() returns int
language sql stable security definer set search_path = public as $$
  select coalesce((
    select case ruolo when 'presidente' then 3 when 'direttivo' then 2 when 'socio' then 1 else 0 end
    from public.profili where id = auth.uid() and ex_socio_dal is null
  ), 0);
$$;

-- Il passaggio avviene tramite la funzione amministrativa, anche per il presidente.
create or replace function public.proteggi_stato_ex_socio() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.ex_socio_dal is distinct from old.ex_socio_dal
     and current_user in ('anon', 'authenticated') then
    raise exception 'Usa la gestione degli ex soci per cambiare lo stato';
  end if;
  return new;
end $$;
revoke execute on function public.proteggi_stato_ex_socio() from public, anon, authenticated;
drop trigger if exists proteggi_stato_ex_socio on public.profili;
create trigger proteggi_stato_ex_socio before update on public.profili
  for each row execute function public.proteggi_stato_ex_socio();

drop policy if exists ex_socio_profilo_sola_lettura on public.profili;
create policy ex_socio_profilo_sola_lettura on public.profili as restrictive for update to authenticated
  using (ex_socio_dal is null or public.livello() = 3)
  with check (ex_socio_dal is null or public.livello() = 3);
drop policy if exists ex_socio_profilo_conservato on public.profili;
create policy ex_socio_profilo_conservato on public.profili as restrictive for delete to authenticated
  using (ex_socio_dal is null);

-- Scrive l'etichetta nella riga stessa: anche le SELECT dirette ricevono solo «ex socio».
-- Il collegamento al profilo rimane disponibile alla gestione Soci, protetta da RLS.
create or replace function public.etichetta_foto_ex_socio() returns trigger
language plpgsql security definer set search_path = '' as $$
declare fine_tesseramento timestamptz;
begin
  if new.user_id is null then return new; end if;
  select ex_socio_dal into fine_tesseramento from public.profili
    where id = new.user_id for share;
  if fine_tesseramento is not null then new.autore := 'ex socio'; end if;
  return new;
end $$;
revoke execute on function public.etichetta_foto_ex_socio() from public, anon, authenticated;
drop trigger if exists etichetta_foto_ex_socio on public.foto;
create trigger etichetta_foto_ex_socio before insert or update on public.foto
  for each row execute function public.etichetta_foto_ex_socio();

create or replace function public.imposta_ex_socio(p_utente uuid, p_ex_socio boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare profilo public.profili;
begin
  if public.livello() <> 3 then raise exception 'Solo il presidente può gestire gli ex soci'; end if;
  if p_utente is null or p_ex_socio is null or p_utente = auth.uid() then
    raise exception 'Seleziona un altro socio';
  end if;
  select * into profilo from public.profili where id = p_utente for update;
  if not found or profilo.ruolo not in ('socio', 'direttivo') then
    raise exception 'Seleziona un socio o un componente del direttivo';
  end if;
  if p_ex_socio = (profilo.ex_socio_dal is not null) then return; end if;

  if p_ex_socio then
    update public.profili set ex_socio_dal = now() where id = p_utente;
    update public.foto set autore = 'ex socio' where user_id = p_utente;
    delete from auth.sessions where user_id = p_utente;
  else
    -- Il rinnovo restituisce l'accesso di socio. Il direttivo si assegna separatamente.
    delete from auth.sessions where user_id = p_utente;
    update public.profili set ex_socio_dal = null, ruolo = 'socio' where id = p_utente;
    update public.foto set autore = profilo.nome where user_id = p_utente and autore = 'ex socio';
  end if;
end $$;
revoke execute on function public.imposta_ex_socio(uuid, boolean) from public, anon;
grant execute on function public.imposta_ex_socio(uuid, boolean) to authenticated;

