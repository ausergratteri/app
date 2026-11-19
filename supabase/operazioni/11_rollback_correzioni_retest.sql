-- =====================================================================
--  AUSER GRATTERI – rollback di 20261122_correzioni_retest.sql
--  Riporta regole e vincoli come dopo 20261121. Non tocca file né dati.
--  Riapre i difetti: adesioni modificabili da chi è "in attesa", tema non controllato,
--  SVG ammessi nel bucket pubblico.
-- =====================================================================
begin;

drop policy if exists adesioni_solo_soci on public.adesioni;
drop policy if exists adesioni_solo_proprie on public.adesioni;
drop policy if exists adesioni_leggi on public.adesioni;
create policy adesioni_leggi on public.adesioni for select
  using (user_id = auth.uid() or public.livello() >= 2);
drop policy if exists adesioni_modifica on public.adesioni;
create policy adesioni_modifica on public.adesioni for update
  using (user_id = auth.uid() or public.livello() >= 2)
  with check ((user_id = auth.uid() and canale = 'App') or public.livello() >= 2);
drop policy if exists adesioni_elimina on public.adesioni;
create policy adesioni_elimina on public.adesioni for delete
  using (user_id = auth.uid() or public.livello() >= 2);

alter table public.impostazioni drop constraint if exists impostazioni_tema_valido;

update storage.buckets
   set allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif','image/svg+xml']
 where id = 'foto';

commit;
