-- Prova del trasferimento delle foto (06_attiva_foto_private.sql e 05_rollback_foto_private.sql).
-- Dati: cinque foto nel bucket pubblico in situazioni diverse e una copertina.
truncate t.esiti;
-- r1: copia privata identica → da attivare
update storage.objects set metadata = '{"size": 100, "eTag": "\"aaa\""}'
 where bucket_id = 'foto' and name = '00000000-0000-0000-0000-000000000003/1-gita.jpg';
insert into storage.objects (bucket_id, name, metadata) values
  ('foto-private', '00000000-0000-0000-0000-000000000003/1-gita.jpg', '{"size": 100, "eTag": "\"aaa\""}'),
-- r2: copia privata DIVERSA → non attivare
  ('foto',         '00000000-0000-0000-0000-000000000003/2-diversa.jpg', '{"size": 200, "eTag": "\"bbb\""}'),
  ('foto-private', '00000000-0000-0000-0000-000000000003/2-diversa.jpg', '{"size": 200, "eTag": "\"ccc\""}'),
-- r3: nessuna copia privata → non attivare
  ('foto',         '00000000-0000-0000-0000-000000000003/3-sola-pubblica.jpg', '{"size": 300, "eTag": "\"ddd\""}'),
-- r4: copia pubblica mancante → non attivare
  ('foto-private', '00000000-0000-0000-0000-000000000003/4-sola-privata.jpg', '{"size": 400, "eTag": "\"eee\""}'),
-- copertina di un'attività nel bucket pubblico: non è una foto di galleria
  ('foto',         '00000000-0000-0000-0000-000000000001/copertina.jpg', '{"size": 500, "eTag": "\"fff\""}');
update public.attivita set immagine = 'https://x.supabase.co/storage/v1/object/public/foto/00000000-0000-0000-0000-000000000001/copertina.jpg'
 where id = 'a0000000-0000-0000-0000-000000000001';
update public.attivita set immagine = 'locandine/2026-11-11-san-martino.jpg'
 where id = 'a0000000-0000-0000-0000-000000000003';
insert into public.foto (id, attivita_id, user_id, autore, url, percorso) values
  ('d0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 'M',
   'https://x.supabase.co/storage/v1/object/public/foto/00000000-0000-0000-0000-000000000003/2-diversa.jpg', '00000000-0000-0000-0000-000000000003/2-diversa.jpg'),
  ('d0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 'M',
   'https://x.supabase.co/storage/v1/object/public/foto/00000000-0000-0000-0000-000000000003/3-sola-pubblica.jpg', '00000000-0000-0000-0000-000000000003/3-sola-pubblica.jpg'),
  ('d0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 'M',
   'https://x.supabase.co/storage/v1/object/public/foto/00000000-0000-0000-0000-000000000003/4-sola-privata.jpg', '00000000-0000-0000-0000-000000000003/4-sola-privata.jpg'),
  ('d0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001', null, 'Vecchia', 'https://esempio.it/vecchia.jpg', '');
create temp table prima_copertine as select id, immagine from public.attivita;
create temp table prima_url as select id, url from public.foto;
