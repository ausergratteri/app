-- =====================================================================
--  AUSER GRATTERI – dipendenze degli account (tutti tranne il presidente). SOLA LETTURA, un'unica SELECT.
--  Serve a sapere, PRIMA di un eventuale "Azzera primo accesso" (4b), se un account ha dati che
--  l'azzeramento cancellerebbe o che lo impedirebbero. Nessun nome, telefono o indirizzo: solo ruolo,
--  data di creazione e conteggi. Stessi criteri di registrazione.ha_dati (20261123): iscrizioni, foto,
--  importazioni eseguite, file in Storage (proprietario o cartella con l'id dell'utente).
-- =====================================================================
select p.ruolo,
       to_char(u.created_at, 'YYYY-MM-DD') as creato_il,
       (select count(*) from public.adesioni a where a.user_id = p.id) as iscrizioni,
       (select count(*) from public.foto f where f.user_id = p.id) as foto_righe,
       (select count(*) from storage.objects o
         where o.owner = p.id or o.owner_id = p.id::text
            or (o.bucket_id in ('foto', 'foto-private') and (storage.foldername(o.name))[1] = p.id::text)) as file_storage,
       (select count(*) from public.importazioni i where i.eseguita_da = p.id) as importazioni,
       (select count(*) from auth.sessions s where s.user_id = p.id) as sessioni,
       exists (select 1 from public.tesserati t where public.solo_cifre_tel(t.telefono) = public.solo_cifre_tel(p.telefono)
                                                  and public.solo_cifre_tel(p.telefono) <> '') as tra_i_tesserati,
       exists (select 1 from public.tesserati t where public.solo_cifre_tel(t.telefono) = public.solo_cifre_tel(p.telefono)
                                                  and public.solo_cifre_tel(p.telefono) <> '' and t.email <> '') as tesserato_con_email,
       not (exists (select 1 from public.adesioni a where a.user_id = p.id)
            or exists (select 1 from public.foto f where f.user_id = p.id)
            or exists (select 1 from public.importazioni i where i.eseguita_da = p.id)
            or exists (select 1 from storage.objects o where o.owner = p.id or o.owner_id = p.id::text
                         or (o.bucket_id in ('foto', 'foto-private') and (storage.foldername(o.name))[1] = p.id::text))) as azzerabile_con_4b
  from public.profili p join auth.users u on u.id = p.id
 where p.ruolo <> 'presidente'
 order by p.ruolo, u.created_at;
