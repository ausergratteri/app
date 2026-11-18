-- Dati di prova. Si inseriscono come amministratore (auth.uid() vuoto),
-- come fa Supabase Auth alla registrazione.
-- Persone:  P presidente · D direttivo · S socio (tesserata) · A in attesa
insert into public.tesserati (nome, telefono) values ('Maria Rossi', '333 111 1111'), ('Giovanni Bianchi', '3334444444');

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000001', '3330000000@soci.ausergratteri.app', '{"nome":"Presidente","telefono":"3330000000"}'),
  ('00000000-0000-0000-0000-000000000002', '3332222222@soci.ausergratteri.app', '{"nome":"Salvo Direttivo","telefono":"3332222222"}'),
  ('00000000-0000-0000-0000-000000000003', '3331111111@soci.ausergratteri.app', '{"nome":"Maria Rossi","telefono":"333 111 1111"}'),
  ('00000000-0000-0000-0000-000000000004', '3333333333@soci.ausergratteri.app', '{"nome":"Concetta Attesa","telefono":"3333333333"}');
update public.profili set ruolo = 'direttivo' where id = '00000000-0000-0000-0000-000000000002';

insert into auth.sessions (user_id) values
  ('00000000-0000-0000-0000-000000000002'), ('00000000-0000-0000-0000-000000000003'), ('00000000-0000-0000-0000-000000000003');

-- Attività: g1 aperta (3 posti), g2 chiusa, g3 senza ospiti, g4 scaduta, g5 al completo (1 posto)
insert into public.attivita (id, titolo, data, posti, scadenza, ospiti, stato) values
  ('a0000000-0000-0000-0000-000000000001', 'Gita aperta',   current_date + 30, 3,    null,             true,  'aperta'),
  ('a0000000-0000-0000-0000-000000000002', 'Gita chiusa',   current_date + 30, null, null,             true,  'chiusa'),
  ('a0000000-0000-0000-0000-000000000003', 'Senza ospiti',  current_date + 30, null, null,             false, 'aperta'),
  ('a0000000-0000-0000-0000-000000000004', 'Scaduta',       current_date + 30, null, current_date - 2, true,  'aperta'),
  ('a0000000-0000-0000-0000-000000000005', 'Al completo',   current_date + 30, 1,    null,             true,  'aperta');
insert into public.assemblee (id, prima_data, stato) values
  ('b0000000-0000-0000-0000-000000000001', current_date + 20, 'convocata'),
  ('b0000000-0000-0000-0000-000000000002', current_date + 20, 'annullata');

-- Il direttivo occupa l'unico posto di g5; Maria è iscritta a g1
insert into public.adesioni (id, attivita_id, user_id, nome, acc) values
  ('c0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000002', 'Salvo Direttivo', '[]'),
  ('c0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 'Maria Rossi', '[]');

-- Un file del presidente (il logo) e una foto di Maria
insert into storage.objects (bucket_id, name, owner) values
  ('foto', '00000000-0000-0000-0000-000000000001/logo.png', '00000000-0000-0000-0000-000000000001'),
  ('foto', '00000000-0000-0000-0000-000000000003/1-gita.jpg', '00000000-0000-0000-0000-000000000003');
insert into public.foto (id, attivita_id, user_id, autore, url, percorso) values
  ('d0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 'Maria Rossi',
   'https://x.supabase.co/storage/v1/object/public/foto/00000000-0000-0000-0000-000000000003/1-gita.jpg',
   '00000000-0000-0000-0000-000000000003/1-gita.jpg');
