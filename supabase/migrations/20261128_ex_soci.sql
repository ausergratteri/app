-- Gestione degli ex soci. Le foto e le iscrizioni rimangono collegate al profilo.
begin;

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

commit;
