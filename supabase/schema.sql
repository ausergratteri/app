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

-- Alla registrazione nasce il profilo. Il primissimo iscritto diventa presidente.
create or replace function public.nuovo_profilo() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profili (id, nome, telefono, ruolo)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nome', ''),
    coalesce(new.raw_user_meta_data->>'telefono', ''),
    case
      when not exists (select 1 from public.profili where ruolo = 'presidente') then 'presidente'
      when public.solo_cifre_tel(new.raw_user_meta_data->>'telefono') <> ''
           and exists (select 1 from public.tesserati t
                       where public.solo_cifre_tel(t.telefono) = public.solo_cifre_tel(new.raw_user_meta_data->>'telefono'))
        then 'socio'
      else 'in_attesa' end
  );
  return new;
end $$;

drop trigger if exists al_nuovo_utente on auth.users;
create trigger al_nuovo_utente after insert on auth.users
  for each row execute function public.nuovo_profilo();

-- Chi può cambiare i ruoli:
--  * il presidente può dare e togliere qualsiasi ruolo (tranne togliersi da solo);
--  * il direttivo può solo approvare (in_attesa ↔ socio);
--  * ognuno può cambiare il proprio nome, non il proprio ruolo.
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
  using (id = auth.uid() or public.livello() >= 2);
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
  using (user_id = auth.uid() or public.livello() >= 2);
drop policy if exists adesioni_crea on public.adesioni;
create policy adesioni_crea on public.adesioni for insert
  with check ((user_id = auth.uid() and public.livello() >= 1 and canale = 'App') or public.livello() >= 2);
drop policy if exists adesioni_modifica on public.adesioni;
create policy adesioni_modifica on public.adesioni for update
  using (user_id = auth.uid() or public.livello() >= 2)
  with check ((user_id = auth.uid() and canale = 'App') or public.livello() >= 2);
drop policy if exists adesioni_elimina on public.adesioni;
create policy adesioni_elimina on public.adesioni for delete
  using (user_id = auth.uid() or public.livello() >= 2);

-- Quante persone sono iscritte a ogni attività: lo vedono tutti i soci, senza i nomi
create or replace function public.conteggi()
returns table (attivita_id uuid, persone int)
language sql stable security definer set search_path = public as $$
  select a.attivita_id,
         sum((case when a.io then 1 else 0 end) + jsonb_array_length(a.acc))::int
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
alter table public.impostazioni add column if not exists tema_personalizzato jsonb not null default '{}'::jsonb;
alter table public.impostazioni enable row level security;
-- Leggibili anche prima dell'accesso, per mostrare logo e colori nella pagina di accesso
drop policy if exists impostazioni_leggi on public.impostazioni;
create policy impostazioni_leggi on public.impostazioni for select using (true);
drop policy if exists impostazioni_modifica on public.impostazioni;
create policy impostazioni_modifica on public.impostazioni for update using (public.livello() = 3);

-- ---------- Foto (logo, gite, bacheca e gallerie degli eventi) ----------
-- Ogni persona carica nella propria cartella; massimo 5 MB a foto (l'app le riduce prima).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('foto', 'foto', true, 5242880, array['image/jpeg','image/png','image/webp','image/gif','image/svg+xml'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists foto_leggi on storage.objects;
create policy foto_leggi on storage.objects for select to authenticated
  using (bucket_id = 'foto');
drop policy if exists foto_carica on storage.objects;
create policy foto_carica on storage.objects for insert to authenticated
  with check (bucket_id = 'foto' and public.livello() >= 1
              and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists foto_elimina on storage.objects;
create policy foto_elimina on storage.objects for delete to authenticated
  using (bucket_id = 'foto' and (public.livello() >= 2 or (storage.foldername(name))[1] = auth.uid()::text));

-- Le foto delle gallerie: le pubblicano i soci, il direttivo può toglierle
create table if not exists public.foto (
  id           uuid primary key default gen_random_uuid(),
  attivita_id  uuid not null,
  user_id      uuid default auth.uid() references public.profili(id) on delete set null,
  autore       text not null default '',
  url          text not null,
  percorso     text not null default '',
  didascalia   text not null default '',
  creato_il    timestamptz not null default now()
);
create index if not exists foto_per_attivita on public.foto (attivita_id, creato_il);
alter table public.foto enable row level security;
drop policy if exists foto_righe_leggi on public.foto;
create policy foto_righe_leggi on public.foto for select using (public.livello() >= 1);
drop policy if exists foto_righe_crea on public.foto;
create policy foto_righe_crea on public.foto for insert
  with check (public.livello() >= 1 and user_id = auth.uid());
drop policy if exists foto_righe_modifica on public.foto;
create policy foto_righe_modifica on public.foto for update
  using (user_id = auth.uid() or public.livello() >= 2);
drop policy if exists foto_righe_elimina on public.foto;
create policy foto_righe_elimina on public.foto for delete
  using (user_id = auth.uid() or public.livello() >= 2);

-- ---------- Nuovo PIN per chi l'ha dimenticato ----------
-- Il presidente lo può fare per tutti, il direttivo solo per i soci.
create extension if not exists pgcrypto with schema extensions;
create or replace function public.reimposta_pin(utente uuid, pin text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare liv int := public.livello(); r text;
begin
  select ruolo into r from public.profili where id = utente;
  if r is null then raise exception 'Utente non trovato'; end if;
  if length(pin) < 6 then raise exception 'Il PIN deve avere almeno 6 cifre'; end if;
  if not (liv = 3 or (liv = 2 and r in ('in_attesa','socio'))) then
    raise exception 'Non puoi cambiare il PIN di questa persona';
  end if;
  update auth.users set encrypted_password = extensions.crypt(pin, extensions.gen_salt('bf')) where id = utente;
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
