-- =====================================================================
--  AUSER GRATTERI – eliminazione dell'UNICO account con ruolo "direttivo", SOLO se non ha dati.
--  ATTENZIONE: MODIFICA LA PRODUZIONE. Da eseguire solo dopo l'autorizzazione esplicita del presidente,
--  dopo il backup verificato e dopo 21_anteprima_eliminazione_account.sql.
--  Tutto o niente (una transazione): si ferma, senza cancellare nulla, se
--    - gli account "direttivo" non sono esattamente 1;
--    - l'account ha iscrizioni, foto, importazioni o file in Storage (stessi criteri di registrazione.ha_dati);
--  Cancella: l'account Auth e, a cascata, profilo, identità, sessioni e token. Non tocca l'anagrafica
--  (tesserati), le attività, le iscrizioni o le foto di altri.
--  Dopo: la persona rifà il primo accesso con il codice (serve l'e-mail in anagrafica) e nasce "socio";
--  il presidente la rimette nel direttivo dall'app ("Nel direttivo").
--  Alternativa più prudente, dopo il rilascio: pulsante "Azzera primo accesso" (stessi controlli nel database).
-- =====================================================================
begin;
do $$
declare n int; u uuid; dati boolean;
begin
  select count(*) into n from public.profili where ruolo = 'direttivo';
  if n <> 1 then raise exception 'STOP: attesi esattamente 1 account direttivo, trovati %', n; end if;
  select id into u from public.profili where ruolo = 'direttivo';
  dati := exists (select 1 from public.adesioni where user_id = u)
       or exists (select 1 from public.foto where user_id = u)
       or exists (select 1 from public.importazioni where eseguita_da = u)
       or exists (select 1 from storage.objects o where o.owner = u or o.owner_id = u::text
                    or (o.bucket_id in ('foto', 'foto-private') and (storage.foldername(o.name))[1] = u::text));
  if dati then raise exception 'STOP: l''account direttivo ha dati (iscrizioni, foto, importazioni o file): non si elimina'; end if;
  delete from auth.users where id = u;
  if (select count(*) from public.profili where ruolo = 'direttivo') <> 0 then raise exception 'STOP: profilo ancora presente'; end if;
  if (select count(*) from public.profili where ruolo = 'presidente') <> 1 then raise exception 'STOP: il presidente non risulta più unico'; end if;
  raise notice 'eliminato 1 account direttivo senza dati';
end $$;
commit;
select (select count(*) from auth.users) as account,
       (select string_agg(ruolo || '=' || n, ', ' order by ruolo) from (select ruolo, count(*) n from public.profili group by ruolo) x) as profili,
       (select count(*) from public.adesioni) as adesioni, (select count(*) from public.foto) as foto, (select count(*) from public.tesserati) as tesserati;
-- Atteso in produzione (da B-0): 2 | presidente=1, socio=1 | 21 | 204 | 38
