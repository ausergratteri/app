-- =====================================================================
--  AUSER GRATTERI – consenso alle foto (GDPR, art. 6.1.a e art. 7)
--  Da eseguire DOPO 20261125_strumenti_presidente.sql. Si può rieseguire. Non tocca i dati esistenti.
--
--  1. Ogni socio dice nell'app se acconsente a comparire nelle foto della galleria riservata.
--     La risposta sta nel suo profilo (consenso_foto: null = non ha ancora risposto) e OGNI scelta
--     resta nello storico public.consensi_foto con la data: è la prova del consenso e delle revoche.
--     Il consenso lo imposta SOLO il socio per sé, con imposta_consenso_foto(); nessun altro
--     (nemmeno direttivo o presidente) può cambiarlo, e non si può aggirare lo storico.
--  2. Chi carica una foto dichiara di avere il consenso delle persone riconoscibili (per i minori,
--     dei genitori): la dichiarazione resta registrata sulla foto (consenso_dichiarato). Le foto già
--     presenti restano con "false" (caricate prima di questa regola).
-- =====================================================================
begin;

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

commit;
