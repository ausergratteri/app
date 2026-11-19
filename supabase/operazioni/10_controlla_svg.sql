-- =====================================================================
--  AUSER GRATTERI – controllo degli SVG nel bucket pubblico "foto". SOLA LETTURA.
--  Da eseguire prima e dopo 20261122_correzioni_retest.sql.
--  Non mostra dati delle persone: solo percorsi tecnici e dove sono usati.
-- =====================================================================
-- Tipi ammessi dal bucket (dopo la migrazione: senza image/svg+xml)
select id, public, allowed_mime_types from storage.buckets where id in ('foto', 'foto-private') order by id;

-- File SVG presenti nel bucket pubblico e se sono usati come logo, copertina o immagine della bacheca
select o.name as percorso, o.created_at as caricato_il,
       exists (select 1 from public.impostazioni i where i.logo like '%' || o.name) as usato_come_logo,
       exists (select 1 from public.attivita a where a.immagine like '%' || o.name) as usato_come_copertina,
       exists (select 1 from public.bacheca b where b.immagine like '%' || o.name) as usato_in_bacheca
from storage.objects o
where o.bucket_id = 'foto'
  and (lower(o.name) like '%.svg' or coalesce(o.metadata->>'mimetype', '') = 'image/svg+xml')
order by o.created_at;
-- Se un SVG non è usato da nulla si può valutare di toglierlo dal pannello Storage
-- (con autorizzazione e dopo averne salvato una copia). Se è il logo, caricare prima
-- un logo PNG dalle impostazioni dell'app.

-- Tema attuale (deve essere uno dei valori ammessi dal vincolo impostazioni_tema_valido)
select tema from public.impostazioni;
