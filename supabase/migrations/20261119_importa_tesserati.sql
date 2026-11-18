-- =====================================================================
--  AUSER GRATTERI – importazione dei tesserati dal gestionale (.xls)
--  Da eseguire DOPO 20261118_sicurezza_accessi.sql. Si può rieseguire.
--  Prima: supabase/operazioni/01_controlli_preliminari.sql (controlli 12 e 13).
-- =====================================================================
begin;

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

commit;
