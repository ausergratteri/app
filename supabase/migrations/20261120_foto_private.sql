-- =====================================================================
--  AUSER GRATTERI – foto delle gallerie in un bucket privato
--  Da eseguire DOPO 20261118_sicurezza_accessi.sql e 20261119_importa_tesserati.sql.
--  Si può rieseguire. NON sposta file e NON cambia le righe esistenti:
--  prepara soltanto il bucket "foto-private", le sue regole e la colonna "bucket".
--  Il trasferimento dei 204 file è un passaggio separato (vedi operazioni/README.md).
-- =====================================================================
begin;

-- ---------- 1. Bucket privato per le gallerie dei soci ----------
-- Niente SVG (può contenere codice); stesso limite di 5 MB del bucket pubblico.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('foto-private', 'foto-private', false, 5242880, array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- ---------- 2. Regole del bucket privato ----------
-- Leggere (e quindi ottenere un URL temporaneo): solo i soci, non chi è in attesa né anon.
drop policy if exists foto_private_leggi on storage.objects;
create policy foto_private_leggi on storage.objects for select to authenticated
  using (bucket_id = 'foto-private' and public.livello() >= 1);
-- Caricare: solo i soci, solo nella propria cartella.
drop policy if exists foto_private_carica on storage.objects;
create policy foto_private_carica on storage.objects for insert to authenticated
  with check (bucket_id = 'foto-private' and public.livello() >= 1
              and (storage.foldername(name))[1] = auth.uid()::text);
-- Togliere: i propri file; il direttivo anche quelli degli altri.
drop policy if exists foto_private_elimina on storage.objects;
create policy foto_private_elimina on storage.objects for delete to authenticated
  using (bucket_id = 'foto-private' and (public.livello() >= 2 or (storage.foldername(name))[1] = auth.uid()::text));
-- Nessuna regola di modifica (update): un file caricato non si sovrascrive.

-- ---------- 3. In quale bucket sta ogni foto ----------
-- Le righe esistenti restano nel bucket pubblico "foto" finché non vengono trasferite.
-- Una foto privata non ha URL pubblico (url = '') e ha sempre un percorso.
alter table public.foto add column if not exists bucket text not null default 'foto';
alter table public.foto drop constraint if exists foto_bucket_valido;
alter table public.foto add constraint foto_bucket_valido check (bucket in ('foto', 'foto-private'));
alter table public.foto drop constraint if exists foto_privata_senza_url;
alter table public.foto add constraint foto_privata_senza_url
  check (bucket <> 'foto-private' or (url = '' and percorso <> ''));

-- ---------- 4. Il bucket di una foto lo cambia solo l'amministratore ----------
create or replace function public.controlla_foto() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
  if tg_op = 'UPDATE' and new.bucket is distinct from old.bucket then
    raise exception 'Non puoi spostare la foto in un altro archivio';
  end if;
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
revoke execute on function public.controlla_foto() from public, anon, authenticated;

commit;
