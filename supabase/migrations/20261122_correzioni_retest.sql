-- =====================================================================
--  AUSER GRATTERI – correzioni dal retest Strix del 19 novembre 2026
--  Da eseguire DOPO 20261121_permessi_foto_ruoli.sql. Si può rieseguire.
--  NON cancella file, foto, adesioni o altri dati: cambia regole e vincoli.
--
--  1. Adesioni (vuln-0007): chi è stato riportato "in attesa" (livello 0) non deve più
--     vedere, modificare o cancellare le proprie adesioni. Soci (livello 1): solo le
--     proprie, come prima. Direttivo e presidente: tutte, come prima.
--     Più regole RESTRITTIVE, come per le foto (20261121), contro regole troppo larghe.
--  2. Tema (vuln-0006): impostazioni.tema accetta solo i temi esistenti
--     (un valore come "constructor" bloccava l'app a tutti).
--  3. Bucket pubblico "foto" (vuln-0002): niente più SVG tra i tipi ammessi.
--     Gli SVG già caricati NON vengono toccati: la migrazione li conta e li segnala.
--
--  Prima di cambiare qualcosa controlla che su public.adesioni non ci siano regole
--  sconosciute: se ci sono si ferma, le elenca e non modifica nulla.
-- =====================================================================
begin;

-- ---------- 0. Controlli preliminari ----------
do $$
declare
  attese constant text[] := array[
    'adesioni_leggi', 'adesioni_crea', 'adesioni_modifica', 'adesioni_elimina',
    'adesioni_solo_soci', 'adesioni_solo_proprie'];
  sconosciute text;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.adesioni'::regclass) then
    raise exception 'RLS non attivo su public.adesioni: nessuna modifica fatta';
  end if;
  if not exists (select 1 from storage.buckets where id = 'foto') then
    raise exception 'Manca il bucket "foto": nessuna modifica fatta';
  end if;
  select string_agg(format('%s (%s, %s)', policyname, permissive, cmd), ', ' order by policyname)
    into sconosciute
  from pg_policies
  where schemaname = 'public' and tablename = 'adesioni' and policyname <> all (attese);
  if sconosciute is not null then
    raise exception 'Regole sconosciute su public.adesioni: %. Controllarle prima. Nessuna modifica fatta.', sconosciute;
  end if;
end $$;

-- ---------- 1. Adesioni: "le proprie" solo finché si è soci ----------
drop policy if exists adesioni_leggi on public.adesioni;
create policy adesioni_leggi on public.adesioni for select
  using (public.livello() >= 2 or (public.livello() >= 1 and user_id = auth.uid()));
drop policy if exists adesioni_modifica on public.adesioni;
create policy adesioni_modifica on public.adesioni for update
  using (public.livello() >= 2 or (public.livello() >= 1 and user_id = auth.uid()))
  with check ((public.livello() >= 1 and user_id = auth.uid() and canale = 'App') or public.livello() >= 2);
drop policy if exists adesioni_elimina on public.adesioni;
create policy adesioni_elimina on public.adesioni for delete
  using (public.livello() >= 2 or (public.livello() >= 1 and user_id = auth.uid()));
-- adesioni_crea (già con livello >= 1) resta com'è.

-- Regole RESTRITTIVE (valgono in AND con tutte le altre)
drop policy if exists adesioni_solo_soci on public.adesioni;
create policy adesioni_solo_soci on public.adesioni as restrictive for all to anon, authenticated
  using (public.livello() >= 1) with check (public.livello() >= 1);
drop policy if exists adesioni_solo_proprie on public.adesioni;
create policy adesioni_solo_proprie on public.adesioni as restrictive for all to anon, authenticated
  using (public.livello() >= 2 or user_id = auth.uid())
  with check (public.livello() >= 2 or user_id = auth.uid());

-- ---------- 2. Tema: solo i valori che l'app conosce ----------
-- Elenco uguale alle chiavi di TEMI in temi.js + "personalizzato" e "automatico"
-- (un test JavaScript controlla che i due elenchi coincidano).
alter table public.impostazioni drop constraint if exists impostazioni_tema_valido;
alter table public.impostazioni add constraint impostazioni_tema_valido check (tema in (
  'bianco', 'classico', 'natale', 'vecchia', 'carnevale', 'pasqua', 'primavera', 'estate',
  'sangiacomo', 'autunno', 'personalizzato', 'automatico')) not valid;
do $$
begin
  if exists (select 1 from public.impostazioni where tema not in (
      'bianco', 'classico', 'natale', 'vecchia', 'carnevale', 'pasqua', 'primavera', 'estate',
      'sangiacomo', 'autunno', 'personalizzato', 'automatico')) then
    raise notice 'impostazioni.tema contiene un valore non valido: il vincolo vale per le nuove scritture; correggere il valore e poi eseguire: alter table public.impostazioni validate constraint impostazioni_tema_valido;';
  else
    alter table public.impostazioni validate constraint impostazioni_tema_valido;
  end if;
end $$;

-- ---------- 3. Bucket pubblico "foto": niente SVG ----------
update storage.buckets
   set allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif']
 where id = 'foto';
do $$
declare n int;
begin
  select count(*) into n from storage.objects
   where bucket_id = 'foto'
     and (lower(name) like '%.svg' or coalesce(metadata->>'mimetype', '') = 'image/svg+xml');
  if n > 0 then
    raise notice '% file SVG già presenti nel bucket "foto": NON sono stati toccati. Controllarli (vedi operazioni/10_controlla_svg.sql).', n;
  end if;
end $$;

-- ---------- 4. Controllo finale ----------
do $$
begin
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'adesioni' and permissive = 'RESTRICTIVE') <> 2
     or (select count(*) from pg_policies where schemaname = 'public' and tablename = 'adesioni' and permissive = 'PERMISSIVE') <> 4
     or array_position((select allowed_mime_types from storage.buckets where id = 'foto'), 'image/svg+xml') is not null then
    raise exception 'Lo stato dopo la migrazione non è quello atteso: annullata';
  end if;
end $$;

commit;
