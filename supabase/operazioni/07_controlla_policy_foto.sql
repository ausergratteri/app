-- =====================================================================
--  AUSER GRATTERI – controllo delle regole (policy RLS) sulle foto. SOLA LETTURA.
--  Da eseguire nel SQL Editor PRIMA e DOPO 20261121_permessi_foto_ruoli.sql.
--  Non mostra dati delle persone: solo nomi ed espressioni delle regole.
--
--  Prima della migrazione ci si aspettano esattamente queste regole PERMISSIVE:
--    public.foto      foto_righe_leggi, foto_righe_crea, foto_righe_modifica, foto_righe_elimina
--    storage.objects  foto_leggi, foto_carica, foto_elimina,
--                     foto_private_leggi, foto_private_carica, foto_private_elimina
--  Dopo la migrazione, in più, queste RESTRICTIVE:
--    public.foto      foto_righe_solo_soci, foto_righe_crea_proprie,
--                     foto_righe_modifica_proprie, foto_righe_elimina_proprie
--    storage.objects  foto_archivi_solo_soci, foto_archivi_carica_propria,
--                     foto_archivi_modifica_propria, foto_archivi_elimina_propria
--  Qualsiasi altra riga con atteso = 'NO' è una regola concorrente da esaminare:
--  la migrazione in quel caso si ferma senza cambiare nulla.
-- =====================================================================
select schemaname || '.' || tablename as tabella, policyname as regola, permissive as tipo, cmd as operazione,
       roles::text as ruoli,
       case when policyname in (
         'foto_righe_leggi','foto_righe_crea','foto_righe_modifica','foto_righe_elimina',
         'foto_righe_solo_soci','foto_righe_crea_proprie','foto_righe_modifica_proprie','foto_righe_elimina_proprie',
         'foto_leggi','foto_carica','foto_elimina','foto_private_leggi','foto_private_carica','foto_private_elimina',
         'foto_archivi_solo_soci','foto_archivi_carica_propria','foto_archivi_modifica_propria','foto_archivi_elimina_propria')
         then 'sì' else 'NO' end as atteso,
       qual as condizione_using, with_check as condizione_with_check
from pg_policies
where (schemaname = 'public' and tablename = 'foto') or (schemaname = 'storage' and tablename = 'objects')
order by atteso, tabella, tipo, regola;

-- RLS attivo sulle due tabelle (devono essere entrambe "true")
select c.oid::regclass::text as tabella, c.relrowsecurity as rls_attivo, c.relforcerowsecurity as rls_forzato
from pg_class c where c.oid in ('public.foto'::regclass, 'storage.objects'::regclass);

-- I due bucket (foto = pubblico, foto-private = privato)
select id, public from storage.buckets where id in ('foto', 'foto-private') order by id;

-- Le 204 foto non vengono toccate: contarle prima e dopo, il numero deve restare uguale
select bucket, count(*) as righe from public.foto group by bucket order by bucket;
