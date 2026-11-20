-- =====================================================================
--  AUSER GRATTERI – eliminazione dell'UNICO account con ruolo "socio" CONSERVANDO le sue iscrizioni.
--  ATTENZIONE: MODIFICA LA PRODUZIONE. Solo con l'autorizzazione esplicita del presidente, dopo il backup
--  verificato e dopo 21_anteprima_eliminazione_account.sql.
--  Perché serve lo "stacco": adesioni.user_id → profili è ON DELETE CASCADE, quindi eliminare l'account
--  cancellerebbe le iscrizioni. Qui, PRIMA di eliminare l'account, si mette a vuoto SOLO adesioni.user_id
--  delle sue iscrizioni: diventano come quelle che il direttivo aggiunge a mano (user_id vuoto), restano
--  visibili a direttivo e presidente e contano nei posti; il contenuto (id, attività, nome, persone,
--  accompagnatori, note, canale, data) NON cambia.
--  Tutto o niente (una transazione). Si ferma, senza cambiare nulla, se:
--    - gli account "socio" non sono esattamente 1;
--    - le sue iscrizioni non sono esattamente quelle attese (ISCRIZIONI_ATTESE, qui 2);
--    - ha foto, importazioni o file in Storage;
--    - dopo l'operazione il contenuto delle iscrizioni o l'anagrafica dei tesserati non sono IDENTICI a prima.
--  Non tocca il PIN di nessuno, l'anagrafica, le attività, le iscrizioni o le foto di altri.
-- =====================================================================
begin;
do $$
declare
  ISCRIZIONI_ATTESE constant int := 2;
  n int; u uuid; ids uuid[];
  contenuto_prima text; contenuto_dopo text; tess_prima text; tess_dopo text; tot_prima int;
begin
  select count(*) into n from public.profili where ruolo = 'socio';
  if n <> 1 then raise exception 'STOP: attesi esattamente 1 account socio, trovati %', n; end if;
  select id into u from public.profili where ruolo = 'socio';
  select array_agg(id order by id) into ids from public.adesioni where user_id = u;
  if coalesce(array_length(ids, 1), 0) <> ISCRIZIONI_ATTESE then
    raise exception 'STOP: attese % iscrizioni del socio, trovate %', ISCRIZIONI_ATTESE, coalesce(array_length(ids, 1), 0);
  end if;
  if exists (select 1 from public.foto where user_id = u) or exists (select 1 from public.importazioni where eseguita_da = u)
     or exists (select 1 from storage.objects o where o.owner = u or o.owner_id = u::text
                  or (o.bucket_id in ('foto', 'foto-private') and (storage.foldername(o.name))[1] = u::text)) then
    raise exception 'STOP: l''account socio ha foto, importazioni o file: procedura non prevista';
  end if;
  -- Impronte PRIMA: contenuto delle sue iscrizioni (tutte le colonne tranne user_id) e anagrafica completa
  select md5(string_agg(concat_ws('|', id, attivita_id, nome, io, acc::text, note, canale, creato_il), '#' order by id))
    into contenuto_prima from public.adesioni where id = any(ids);
  select md5(coalesce(string_agg(t::text, '#' order by t.id), '')) into tess_prima from public.tesserati t;
  select count(*) into tot_prima from public.adesioni;
  -- 1. Stacco: solo user_id delle sue iscrizioni (nessun trigger blocca: eseguito come amministratore)
  update public.adesioni set user_id = null where id = any(ids);
  -- 2. Eliminazione dell'account (profilo, identità, sessioni e token a cascata)
  delete from auth.users where id = u;
  -- 3. Verifiche DOPO, nella stessa transazione
  select md5(string_agg(concat_ws('|', id, attivita_id, nome, io, acc::text, note, canale, creato_il), '#' order by id))
    into contenuto_dopo from public.adesioni where id = any(ids) and user_id is null;
  select md5(coalesce(string_agg(t::text, '#' order by t.id), '')) into tess_dopo from public.tesserati t;
  if contenuto_dopo is distinct from contenuto_prima then raise exception 'STOP: il contenuto delle iscrizioni è cambiato'; end if;
  if tess_dopo is distinct from tess_prima then raise exception 'STOP: l''anagrafica dei tesserati è cambiata'; end if;
  if (select count(*) from public.adesioni) <> tot_prima then raise exception 'STOP: il numero totale di iscrizioni è cambiato'; end if;
  if exists (select 1 from public.profili where id = u) then raise exception 'STOP: profilo ancora presente'; end if;
  if (select count(*) from public.profili where ruolo = 'presidente') <> 1 then raise exception 'STOP: il presidente non risulta più unico'; end if;
  raise notice 'eliminato 1 account socio; % iscrizioni conservate (contenuto identico, impronta %), anagrafica identica (impronta %)',
    array_length(ids, 1), left(contenuto_prima, 12), left(tess_prima, 12);
end $$;
commit;
select (select count(*) from auth.users) as account,
       (select string_agg(ruolo || '=' || n, ', ' order by ruolo) from (select ruolo, count(*) n from public.profili group by ruolo) x) as profili,
       (select count(*) from public.adesioni) as adesioni, (select count(*) from public.adesioni where user_id is null) as adesioni_senza_account,
       (select count(*) from public.foto) as foto, (select count(*) from public.tesserati) as tesserati;
