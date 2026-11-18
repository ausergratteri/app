-- Solo per il percorso "schema vecchio + migrazione": un'adesione con "acc" non lista,
-- come quella che oggi blocca conteggi() (N1). La migrazione deve ripararla.
insert into public.adesioni (attivita_id, user_id, nome, acc) values
  ('a0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000004', 'Concetta Attesa', '{"rotto": true}');
