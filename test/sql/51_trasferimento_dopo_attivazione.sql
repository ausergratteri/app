-- Dopo 06_attiva_foto_private.sql (eseguito DUE volte: deve essere ripetibile)
call t.verifica('trasferimento: attivata solo la foto con copia privata identica', null, 'select 1',
  $c$(select array_agg(id order by id) from public.foto where bucket = 'foto-private') = array['d0000000-0000-0000-0000-000000000001'::uuid]$c$);
call t.verifica('trasferimento: la foto attivata non ha più URL pubblico', null, 'select 1',
  $c$(select url from public.foto where id = 'd0000000-0000-0000-0000-000000000001') = ''$c$);
call t.verifica('trasferimento: copia diversa, sola pubblica, sola privata e senza percorso restano invariate', null, 'select 1',
  $c$not exists (select 1 from public.foto f join prima_url p using (id)
                 where f.id <> 'd0000000-0000-0000-0000-000000000001' and (f.url <> p.url or f.bucket <> 'foto'))$c$);
call t.verifica('trasferimento: copertine (bucket e locandine nel sito) non toccate', null, 'select 1',
  $c$not exists (select 1 from public.attivita a join prima_copertine p using (id) where a.immagine is distinct from p.immagine)$c$);
call t.verifica('trasferimento: nessun file eliminato', null, 'select 1',
  $c$(select count(*) from storage.objects) = 8$c$);
call t.verifica('trasferimento: stato precedente salvato una volta per foto', null, 'select 1',
  $c$(select count(*) from backup_20261120.foto_prima) = 5
     and (select url from backup_20261120.foto_prima where id = 'd0000000-0000-0000-0000-000000000001') like '%/object/public/foto/%'$c$);
call t.verifica('trasferimento: lo schema di backup non è leggibile dai ruoli dell''app', null, 'select 1',
  $c$not has_schema_privilege('authenticated', 'backup_20261120', 'usage') and not has_schema_privilege('anon', 'backup_20261120', 'usage')$c$);
-- Dopo il passaggio un socio carica una nuova foto solo nel bucket privato
insert into storage.objects (bucket_id, name, metadata) values
  ('foto-private', '00000000-0000-0000-0000-000000000003/9-nuova.jpg', '{"size": 900, "eTag": "\"999\""}');
insert into public.foto (id, attivita_id, user_id, autore, url, percorso, bucket) values
  ('d0000000-0000-0000-0000-000000000009', 'a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 'M', '',
   '00000000-0000-0000-0000-000000000003/9-nuova.jpg', 'foto-private');
-- Prova del blocco: la copia pubblica di una foto trasferita è sparita → il rollback non deve fare nulla
create temp table oggetto_tolto as select * from storage.objects
 where bucket_id = 'foto' and name = '00000000-0000-0000-0000-000000000003/1-gita.jpg';
delete from storage.objects where bucket_id = 'foto' and name = '00000000-0000-0000-0000-000000000003/1-gita.jpg';
\echo '(prova del blocco: l''errore seguente del rollback è ATTESO)'
\set ON_ERROR_STOP 0
