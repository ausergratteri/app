-- =====================================================================
--  AUSER GRATTERI – rollback di 20261121_permessi_foto_ruoli.sql
--  Riporta le regole sulle foto esattamente com'erano dopo 20261120_foto_private.sql.
--  Non tocca file né righe. Da usare solo se la correzione crea problemi:
--  riapre il difetto (un socio riportato in attesa può ancora cancellare le sue foto).
-- =====================================================================
begin;

-- Regole restrittive aggiunte dalla correzione
drop policy if exists foto_righe_solo_soci on public.foto;
drop policy if exists foto_righe_crea_proprie on public.foto;
drop policy if exists foto_righe_modifica_proprie on public.foto;
drop policy if exists foto_righe_elimina_proprie on public.foto;
drop policy if exists foto_archivi_solo_soci on storage.objects;
drop policy if exists foto_archivi_carica_propria on storage.objects;
drop policy if exists foto_archivi_modifica_propria on storage.objects;
drop policy if exists foto_archivi_elimina_propria on storage.objects;

-- Regole permissive come prima
drop policy if exists foto_righe_modifica on public.foto;
create policy foto_righe_modifica on public.foto for update
  using (user_id = auth.uid() or public.livello() >= 2)
  with check (user_id = auth.uid() or public.livello() >= 2);
drop policy if exists foto_righe_elimina on public.foto;
create policy foto_righe_elimina on public.foto for delete
  using (user_id = auth.uid() or public.livello() >= 2);
drop policy if exists foto_elimina on storage.objects;
create policy foto_elimina on storage.objects for delete to authenticated
  using (bucket_id = 'foto' and (public.livello() >= 2 or (storage.foldername(name))[1] = auth.uid()::text));
drop policy if exists foto_private_elimina on storage.objects;
create policy foto_private_elimina on storage.objects for delete to authenticated
  using (bucket_id = 'foto-private' and (public.livello() >= 2 or (storage.foldername(name))[1] = auth.uid()::text));

commit;

select schemaname || '.' || tablename as tabella, permissive as tipo, count(*) as regole
from pg_policies
where (schemaname = 'public' and tablename = 'foto') or (schemaname = 'storage' and tablename = 'objects')
group by 1, 2 order by 1, 2;
