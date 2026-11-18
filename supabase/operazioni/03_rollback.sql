-- =====================================================================
--  AUSER GRATTERI – ROLLBACK della migrazione 20261118_sicurezza_accessi
--  Riporta funzioni, regole, trigger e vincoli com'erano su main (1951fbe).
--  ATTENZIONE: riapre le vulnerabilità corrette. Usarlo solo se l'app non funziona.
--  Parte B (facoltativa) ripristina "acc" dalle copie in backup_20261118.
-- =====================================================================
begin;

-- Nuovi trigger, vincoli e funzioni
drop trigger if exists prima_di_salvare_adesione on public.adesioni;
drop trigger if exists prima_di_salvare_foto on public.foto;
alter table public.adesioni drop constraint if exists adesioni_acc_valido;
alter table public.bacheca drop constraint if exists bacheca_link_web;
alter table public.impostazioni drop constraint if exists impostazioni_link_web;
drop function if exists public.controlla_adesione();
drop function if exists public.controlla_foto();
drop function if exists public.acc_valido(jsonb);

-- Funzioni com'erano
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

create or replace function public.controlla_ruolo() returns trigger
language plpgsql security definer set search_path = public as $$
declare liv int := public.livello();
begin
  if auth.uid() is null then return new; end if;
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

create or replace function public.conteggi()
returns table (attivita_id uuid, persone int)
language sql stable security definer set search_path = public as $$
  select a.attivita_id,
         sum((case when a.io then 1 else 0 end) + jsonb_array_length(a.acc))::int
  from public.adesioni a
  where public.livello() >= 1
  group by a.attivita_id;
$$;

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

-- Regole com'erano
drop policy if exists profili_modifica on public.profili;
create policy profili_modifica on public.profili for update
  using (id = auth.uid() or public.livello() >= 2);
drop policy if exists foto_righe_modifica on public.foto;
create policy foto_righe_modifica on public.foto for update
  using (user_id = auth.uid() or public.livello() >= 2);
drop policy if exists foto_leggi on storage.objects;
create policy foto_leggi on storage.objects for select to authenticated
  using (bucket_id = 'foto');

commit;

-- ---------- Parte B (facoltativa): ripristino degli accompagnatori ----------
-- La migrazione ha trasformato in [] gli "acc" che non erano liste. Se servono i
-- valori originali (sono quelli che bloccavano l'app), togliere i commenti:
-- update public.adesioni a set acc = b.acc
--   from backup_20261118.adesioni b
--  where a.id = b.id and a.acc is distinct from b.acc;
