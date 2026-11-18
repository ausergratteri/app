-- =====================================================================
--  AUSER GRATTERI – attivazione delle foto private (passo dopo la copia dei file)
--  Prima: migrations/20261120_foto_private.sql e "node supabase/operazioni/foto-private.js copia".
--
--  Passa al bucket "foto-private" SOLO le foto la cui copia privata è identica a
--  quella pubblica: stesso file, stessa dimensione e stessa impronta (eTag).
--  Le altre restano nel bucket pubblico e continuano a vedersi come prima.
--  NON cancella nessun file. Salva lo stato precedente in backup_20261120.foto_prima.
--  Si può rieseguire: le foto già attivate non vengono toccate.
--  Rollback: 05_rollback_foto_private.sql
-- =====================================================================
begin;

do $$ begin
  if not exists (select 1 from storage.buckets where id = 'foto-private' and public = false) then
    raise exception 'Manca il bucket privato "foto-private": eseguire prima la migrazione 20261120';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'foto' and column_name = 'bucket') then
    raise exception 'Manca la colonna public.foto.bucket: eseguire prima la migrazione 20261120';
  end if;
end $$;

-- ---------- 1. Copia dello stato attuale (una sola volta per foto) ----------
create schema if not exists backup_20261120;
revoke all on schema backup_20261120 from public;
create table if not exists backup_20261120.foto_prima (
  id         uuid primary key,
  bucket     text not null,
  url        text not null,
  percorso   text not null,
  salvata_il timestamptz not null default now()
);
insert into backup_20261120.foto_prima (id, bucket, url, percorso)
select id, bucket, url, percorso from public.foto where bucket = 'foto'
on conflict (id) do nothing;

-- ---------- 2. Confronto fra copia pubblica e copia privata ----------
drop table if exists pg_temp.verifica_copie;
create temp table verifica_copie as
select f.id,
       pub.name is not null as pubblica,
       pri.name is not null as privata,
       coalesce(pub.metadata->>'size', '') <> '' and pub.metadata->>'size' = pri.metadata->>'size' as stessa_dimensione,
       coalesce(pub.metadata->>'eTag', '') <> '' and pub.metadata->>'eTag' = pri.metadata->>'eTag' as stessa_impronta
from public.foto f
left join storage.objects pub on pub.bucket_id = 'foto'         and pub.name = f.percorso
left join storage.objects pri on pri.bucket_id = 'foto-private' and pri.name = f.percorso
where f.bucket = 'foto' and f.percorso <> '';

-- ---------- 3. Attivazione delle sole copie verificate ----------
update public.foto f set bucket = 'foto-private', url = ''
from verifica_copie v
where v.id = f.id and f.bucket = 'foto'
  and v.pubblica and v.privata and v.stessa_dimensione and v.stessa_impronta;

commit;

-- ---------- 4. Riepilogo (solo numeri, nessun dato personale) ----------
-- Dopo il commit, così il SQL Editor mostra questa tabella come risultato.
select 'foto nel bucket privato (totale)' as voce, count(*)::text as valore from public.foto where bucket = 'foto-private'
union all select 'foto ancora nel bucket pubblico', count(*)::text from public.foto where bucket = 'foto'
union all select 'non attivate: copia privata mancante', count(*)::text from verifica_copie v
  join public.foto f on f.id = v.id where f.bucket = 'foto' and not v.privata
union all select 'non attivate: copia pubblica mancante', count(*)::text from verifica_copie v
  join public.foto f on f.id = v.id where f.bucket = 'foto' and v.privata and not v.pubblica
union all select 'non attivate: copie diverse (dimensione o impronta)', count(*)::text from verifica_copie v
  join public.foto f on f.id = v.id where f.bucket = 'foto' and v.privata and v.pubblica
  and not (v.stessa_dimensione and v.stessa_impronta)
union all select 'foto senza percorso (non trasferibili)', count(*)::text from public.foto where bucket = 'foto' and percorso = ''
union all select 'righe salvate in backup_20261120.foto_prima', count(*)::text from backup_20261120.foto_prima;
