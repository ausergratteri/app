-- =====================================================================
--  AUSER GRATTERI – permessi sulle fotografie in base al ruolo
--  Da eseguire DOPO 20261120_foto_private.sql. Si può rieseguire.
--  NON tocca file né righe: cambia soltanto le regole (policy RLS).
--
--  Regola:
--   * presidente e direttivo (livello >= 2): vedono e cancellano tutte le foto;
--   * socio (livello 1): vede le foto, carica nella propria cartella e cancella
--     (o modifica) soltanto le foto che ha caricato lui;
--   * in attesa, espulso, profilo eliminato, anon (livello 0): niente, né vedere
--     né caricare né modificare né cancellare.
--  "Espulso" non è un ruolo a parte: è chi è stato riportato "in attesa" o il cui
--  profilo è stato eliminato. In entrambi i casi livello() vale 0.
--
--  Cosa cambia rispetto a prima:
--   1. Le regole "le proprie foto" (modifica ed eliminazione delle righe, eliminazione
--      dei file in "foto" e "foto-private") ora richiedono anche livello >= 1:
--      prima un socio riportato in attesa poteva ancora cancellare o modificare
--      le foto caricate quando era socio.
--   2. Regole RESTRITTIVE in più: valgono insieme (AND) a tutte le altre, quindi
--      anche se un giorno qualcuno aggiunge dal pannello una regola troppo larga,
--      chi è in attesa resta fuori e un socio non tocca le foto degli altri.
--  Nessun permesso viene allargato.
--
--  Prima di cambiare qualcosa controlla che sulle due tabelle non ci siano regole
--  sconosciute (per esempio create a mano dal pannello): se ci sono si ferma, le
--  elenca e non modifica nulla. Vedi operazioni/07_controlla_policy_foto.sql.
-- =====================================================================
begin;

-- ---------- 0. Controlli preliminari ----------
do $$
declare
  attese_foto constant text[] := array[
    'foto_righe_leggi', 'foto_righe_crea', 'foto_righe_modifica', 'foto_righe_elimina',
    'foto_righe_solo_soci', 'foto_righe_crea_proprie', 'foto_righe_modifica_proprie', 'foto_righe_elimina_proprie'];
  attese_storage constant text[] := array[
    'foto_leggi', 'foto_carica', 'foto_elimina',
    'foto_private_leggi', 'foto_private_carica', 'foto_private_elimina',
    'foto_archivi_solo_soci', 'foto_archivi_carica_propria', 'foto_archivi_modifica_propria', 'foto_archivi_elimina_propria'];
  sconosciute text;
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'foto' and column_name = 'bucket') then
    raise exception 'Manca la colonna public.foto.bucket: eseguire prima 20261120_foto_private.sql';
  end if;
  if not exists (select 1 from storage.buckets where id = 'foto-private' and public = false) then
    raise exception 'Manca il bucket privato "foto-private": eseguire prima 20261120_foto_private.sql';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.foto'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'storage.objects'::regclass) then
    raise exception 'RLS non attivo su public.foto o storage.objects: nessuna modifica fatta';
  end if;

  select string_agg(format('%s.%s (%s, %s)', schemaname, policyname, permissive, cmd), ', ' order by schemaname, policyname)
    into sconosciute
  from pg_policies
  where (schemaname = 'public' and tablename = 'foto' and policyname <> all (attese_foto))
     or (schemaname = 'storage' and tablename = 'objects' and policyname <> all (attese_storage));
  if sconosciute is not null then
    raise exception 'Regole sconosciute su public.foto o storage.objects: %. Controllarle prima (07_controlla_policy_foto.sql). Nessuna modifica fatta.', sconosciute;
  end if;
end $$;

-- ---------- 1. public.foto: "le proprie" solo finché si è soci ----------
drop policy if exists foto_righe_modifica on public.foto;
create policy foto_righe_modifica on public.foto for update
  using (public.livello() >= 2 or (public.livello() >= 1 and user_id = auth.uid()))
  with check (public.livello() >= 2 or (public.livello() >= 1 and user_id = auth.uid()));
drop policy if exists foto_righe_elimina on public.foto;
create policy foto_righe_elimina on public.foto for delete
  using (public.livello() >= 2 or (public.livello() >= 1 and user_id = auth.uid()));
-- foto_righe_leggi (livello >= 1) e foto_righe_crea (livello >= 1, user_id proprio) restano come sono.

-- ---------- 2. public.foto: regole restrittive (si sommano in AND a tutte le altre) ----------
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

-- ---------- 3. storage.objects: eliminare i propri file solo finché si è soci ----------
drop policy if exists foto_elimina on storage.objects;
create policy foto_elimina on storage.objects for delete to authenticated
  using (bucket_id = 'foto' and (public.livello() >= 2
         or (public.livello() >= 1 and (storage.foldername(name))[1] = auth.uid()::text)));
drop policy if exists foto_private_elimina on storage.objects;
create policy foto_private_elimina on storage.objects for delete to authenticated
  using (bucket_id = 'foto-private' and (public.livello() >= 2
         or (public.livello() >= 1 and (storage.foldername(name))[1] = auth.uid()::text)));
-- Le regole di lettura e caricamento dei due bucket restano come sono.

-- ---------- 4. storage.objects: regole restrittive, solo per i due bucket delle foto ----------
-- "case" fa sì che per gli altri bucket (oggi non ce ne sono) queste regole non contino.
-- I file del bucket pubblico "foto" restano raggiungibili con il loro URL pubblico:
-- quello non passa da RLS (vedi SICUREZZA_INTERVENTI_2026.md, rischi residui).
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
-- Nessuna regola permissiva di modifica (update) per i file: un file caricato non si
-- sovrascrive, come prima. Le regole restrittive qui sopra non aggiungono permessi.

-- ---------- 5. Controllo finale ----------
do $$
begin
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'foto' and permissive = 'RESTRICTIVE') <> 4
     or (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects' and permissive = 'RESTRICTIVE') <> 4
     or (select count(*) from pg_policies where schemaname = 'public' and tablename = 'foto' and permissive = 'PERMISSIVE') <> 4
     or (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects' and permissive = 'PERMISSIVE') <> 6 then
    raise exception 'Le regole non sono quelle attese dopo la migrazione: annullata';
  end if;
end $$;

commit;
