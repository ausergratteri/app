-- =====================================================================
--  AUSER GRATTERI – rollback delle foto private (annulla 06_attiva_foto_private.sql)
--  Solo in caso di problemi. NON cancella file.
--
--  Parte A (sempre): le foto trasferite tornano al bucket pubblico con il loro URL
--  originale, ma solo se il file pubblico esiste ancora. Se anche una sola copia
--  pubblica manca, non cambia nulla e lo dice: prima vanno riportati i file con
--  "node supabase/operazioni/foto-private.js riporta-pubbliche".
--
--  Le foto caricate DOPO il passaggio (solo nel bucket privato) restano private:
--  la nuova app le mostra comunque. Servono le parti B e C solo se si torna alla
--  vecchia app (che usa gli URL pubblici) o si vuole togliere del tutto il bucket privato.
-- =====================================================================
begin;

do $$
declare mancanti int;
begin
  if to_regclass('backup_20261120.foto_prima') is null then
    raise exception 'Manca backup_20261120.foto_prima: 06_attiva_foto_private.sql non è mai stato eseguito';
  end if;
  select count(*) into mancanti
  from public.foto f join backup_20261120.foto_prima b on b.id = f.id
  where f.bucket = 'foto-private'
    and not exists (select 1 from storage.objects o where o.bucket_id = 'foto' and o.name = f.percorso);
  if mancanti > 0 then
    raise exception '% foto trasferite non hanno più la copia pubblica: riportarle prima con foto-private.js riporta-pubbliche. Nessuna modifica fatta.', mancanti;
  end if;
end $$;

update public.foto f set bucket = b.bucket, url = b.url
from backup_20261120.foto_prima b
where b.id = f.id and f.bucket = 'foto-private';

commit;

select 'foto nel bucket pubblico' as voce, count(*)::text as valore from public.foto where bucket = 'foto'
union all select 'foto ancora nel bucket privato (caricate dopo il passaggio)', count(*)::text from public.foto where bucket = 'foto-private';

-- ---------------------------------------------------------------------
-- Parte B (facoltativa) – solo per tornare alla VECCHIA app.
-- Prima: "node supabase/operazioni/foto-private.js riporta-pubbliche" (copia nel
-- bucket pubblico le foto che esistono solo in quello privato). Poi:
--
-- begin;
-- update public.foto f
--    set bucket = 'foto',
--        url = 'https://dylztksgeqnktoapsbim.supabase.co/storage/v1/object/public/foto/' || f.percorso
--  where f.bucket = 'foto-private'
--    and exists (select 1 from storage.objects o where o.bucket_id = 'foto' and o.name = f.percorso);
-- commit;
--
-- ---------------------------------------------------------------------
-- Parte C (facoltativa) – togliere la struttura della migrazione 20261120.
-- Solo quando NESSUNA foto è più nel bucket privato (Parte A + B eseguite) e con la
-- vecchia app di nuovo pubblicata. Il bucket "foto-private" resta: si svuota e si
-- elimina dal pannello Storage, dopo aver controllato che non serva più.
--
-- begin;
-- do $$ begin
--   if exists (select 1 from public.foto where bucket = 'foto-private') then
--     raise exception 'Ci sono ancora foto nel bucket privato';
--   end if;
-- end $$;
-- drop policy if exists foto_private_leggi on storage.objects;
-- drop policy if exists foto_private_carica on storage.objects;
-- drop policy if exists foto_private_elimina on storage.objects;
-- alter table public.foto drop constraint if exists foto_privata_senza_url;
-- alter table public.foto drop constraint if exists foto_bucket_valido;
-- create or replace function public.controlla_foto() returns trigger
-- language plpgsql security definer set search_path = public as $f$
-- begin
--   if auth.uid() is null then return new; end if;
--   if coalesce(new.percorso, '') <> ''
--      and (tg_op = 'INSERT' or new.percorso is distinct from old.percorso)
--      and (new.user_id is null
--           or split_part(new.percorso, '/', 1) <> new.user_id::text
--           or new.percorso like '%..%') then
--     raise exception 'Non puoi usare questo percorso per la foto';
--   end if;
--   return new;
-- end $f$;
-- alter table public.foto drop column if exists bucket;
-- commit;
