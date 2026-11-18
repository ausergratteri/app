-- =====================================================================
--  AUSER GRATTERI – correzioni di sicurezza (18 novembre 2026)
--  Per un database GIÀ creato con schema.sql: incolla tutto in
--  "SQL Editor" → "New query" → "Run". Si può rieseguire senza danni.
--  Le installazioni nuove non ne hanno bisogno: schema.sql è già aggiornato.
-- =====================================================================
begin;

-- ---------- 1. Registrazione: il telefono viene dall'indirizzo di accesso ----------
-- Prima il ruolo "socio" dipendeva dal telefono scritto nei metadata, che chi si
-- registra sceglie liberamente. Ora il telefono si ricava dall'email interna
-- (<cifre>@soci.ausergratteri.app), che in auth.users è unica: un numero vale
-- un solo account. Un numero già usato da un profilo non promuove più nessuno.
-- Un lucchetto impedisce che due registrazioni simultanee creino due presidenti.
create or replace function public.nuovo_profilo() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  dominio constant text := '@soci.ausergratteri.app';  -- uguale a DOMINIO_FINTO in app.js
  tel text := '';
begin
  perform pg_advisory_xact_lock(hashtext('auser.primo_presidente'));
  if lower(coalesce(new.email, '')) like '%' || dominio then
    tel := public.solo_cifre_tel(split_part(new.email, '@', 1));
  end if;
  insert into public.profili (id, nome, telefono, ruolo)
  values (
    new.id,
    left(coalesce(new.raw_user_meta_data->>'nome', ''), 80),
    tel,
    case
      when not exists (select 1 from public.profili where ruolo = 'presidente') then 'presidente'
      when tel <> ''
           and exists (select 1 from public.tesserati t where public.solo_cifre_tel(t.telefono) = tel)
           and not exists (select 1 from public.profili p where public.solo_cifre_tel(p.telefono) = tel)
        then 'socio'
      else 'in_attesa' end
  );
  return new;
end $$;

-- ---------- 2. Profili: oltre al ruolo, protetti anche nome e telefono ----------
--  * il telefono e la data di iscrizione li cambia solo il presidente;
--  * il nome di un'altra persona lo cambia solo il presidente;
--  * ognuno può ancora cambiare il proprio nome.
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

drop policy if exists profili_modifica on public.profili;
create policy profili_modifica on public.profili for update
  using (id = auth.uid() or public.livello() >= 2)
  with check (id = auth.uid() or public.livello() >= 2);

-- ---------- 3. Adesioni: "acc" sempre una lista valida (N1) ----------
-- Un "acc" che non è una lista faceva fallire conteggi() e bloccava l'app a tutti.
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

-- Le righe già rotte (acc non lista) tornano a lista vuota
update public.adesioni set acc = '[]'::jsonb where jsonb_typeof(acc) is distinct from 'array';

alter table public.adesioni drop constraint if exists adesioni_acc_valido;
alter table public.adesioni add constraint adesioni_acc_valido check (public.acc_valido(acc)) not valid;
do $$ begin
  alter table public.adesioni validate constraint adesioni_acc_valido;
exception when check_violation then
  raise notice 'Alcune adesioni hanno accompagnatori non validi: restano, ma non si possono salvare finché non vengono corretti.';
end $$;

-- conteggi() non si blocca più nemmeno con dati vecchi
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

-- ---------- 4. Adesioni: le regole dell'app valgono anche sul database ----------
-- Il socio (non il direttivo) può iscriversi o modificare solo se l'attività esiste
-- ed è aperta, entro la scadenza, con posti liberi per TUTTE le persone che porta
-- (anche quando ne aggiunge modificando) e senza ospiti dove non sono ammessi.
-- Non può spostare l'iscrizione. Le iscrizioni simultanee passano una alla volta.
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

-- ---------- 5. Link: solo indirizzi web (http/https) ----------
-- "not valid": i dati già presenti non vengono controllati, quelli nuovi sì.
alter table public.bacheca drop constraint if exists bacheca_link_web;
alter table public.bacheca add constraint bacheca_link_web
  check (link = '' or link ~* '^https?://') not valid;
alter table public.impostazioni drop constraint if exists impostazioni_link_web;
alter table public.impostazioni add constraint impostazioni_link_web
  check ((facebook = '' or facebook ~* '^https?://')
     and (instagram = '' or instagram ~* '^https?://')
     and (whatsapp = '' or whatsapp ~* '^https?://')) not valid;

-- ---------- 6. Foto: chi è in attesa non vede più l'elenco dei file (N2) ----------
drop policy if exists foto_leggi on storage.objects;
create policy foto_leggi on storage.objects for select to authenticated
  using (bucket_id = 'foto' and public.livello() >= 1);

-- ---------- 7. Foto: "percorso" deve stare nella cartella di chi ha caricato (N3) ----------
-- Così eliminando una foto non si può far cancellare il file di un'altra persona.
create or replace function public.controlla_foto() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
  -- Si controlla solo quando il percorso viene scritto: se cambia solo user_id
  -- (per esempio diventa vuoto perché il profilo è stato eliminato) va bene così.
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

drop policy if exists foto_righe_modifica on public.foto;
create policy foto_righe_modifica on public.foto for update
  using (user_id = auth.uid() or public.livello() >= 2)
  with check (user_id = auth.uid() or public.livello() >= 2);

-- ---------- 8. Nuovo PIN: controlli prima di tutto, PIN nullo rifiutato, sessioni chiuse ----------
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

-- ---------- 9. Permessi delle nuove funzioni ----------
-- Le funzioni dei trigger non servono a nessuno direttamente; acc_valido serve a chi
-- salva un'adesione (il vincolo la esegue con i permessi di chi scrive).
revoke execute on function public.acc_valido(jsonb) from public, anon;
grant execute on function public.acc_valido(jsonb) to authenticated;
revoke execute on function public.controlla_adesione() from public, anon, authenticated;
revoke execute on function public.controlla_foto() from public, anon, authenticated;

commit;
