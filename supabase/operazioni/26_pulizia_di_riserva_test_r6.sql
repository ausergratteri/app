-- =====================================================================
--  AUSER GRATTERI – pulizia DI RISERVA del test R6 (solo se i pulsanti dell'app non bastano).
--  ATTENZIONE: MODIFICA LA PRODUZIONE. Solo con l'autorizzazione esplicita del presidente.
--  Tocca SOLO il numero inventato 3009000007: l'eventuale account di prova (in attesa o socio, senza dati)
--  e il tesserato di prova "PROVA RILASCIO" (con le sue richieste OTP, a cascata).
--  Tutto o niente: si ferma, senza cambiare nulla, se trova più di un account o un ruolo diverso, dati
--  collegati, un tesserato con un altro nome o più tesserati, oppure se alla fine i totali non sono 3 account
--  e 38 tesserati senza e-mail.
-- =====================================================================
begin;
do $$
declare n_acc int; u uuid; r text; n_t int; nome_t text; n_acc_rimossi int := 0; n_t_rimossi int := 0;
begin
  select count(*) into n_acc from public.profili where public.solo_cifre_tel(telefono) = '3009000007';
  if n_acc > 1 then raise exception 'STOP: più di un account con il numero di prova'; end if;
  if n_acc = 1 then
    select id, ruolo into u, r from public.profili where public.solo_cifre_tel(telefono) = '3009000007';
    if r not in ('in_attesa', 'socio') then raise exception 'STOP: ruolo inatteso per l''account di prova: %', r; end if;
    if exists (select 1 from public.adesioni where user_id = u) or exists (select 1 from public.foto where user_id = u)
       or exists (select 1 from public.importazioni where eseguita_da = u)
       or exists (select 1 from storage.objects o where o.owner = u or o.owner_id = u::text
                    or (o.bucket_id in ('foto', 'foto-private') and (storage.foldername(o.name))[1] = u::text)) then
      raise exception 'STOP: l''account di prova ha dati';
    end if;
    delete from auth.users where id = u;
    n_acc_rimossi := 1;
  end if;
  select count(*), max(nome) into n_t, nome_t from public.tesserati where public.solo_cifre_tel(telefono) = '3009000007';
  if n_t > 1 then raise exception 'STOP: più di un tesserato con il numero di prova'; end if;
  if n_t = 1 then
    if nome_t <> 'PROVA RILASCIO' then raise exception 'STOP: il tesserato con il numero di prova ha un altro nome'; end if;
    delete from public.tesserati where public.solo_cifre_tel(telefono) = '3009000007';   -- richieste OTP a cascata
    n_t_rimossi := 1;
  end if;
  -- Eventuali richieste OTP del numero di prova non collegate al tesserato (es. nome scritto diversamente)
  delete from registrazione.richieste where telefono = '3009000007';
  if (select count(*) from auth.users) <> 3 then raise exception 'STOP: alla fine gli account non sono 3'; end if;
  if (select count(*) from public.tesserati) <> 38 or (select count(*) from public.tesserati where email <> '') <> 0 then
    raise exception 'STOP: alla fine i tesserati non sono 38 senza e-mail';
  end if;
  if exists (select 1 from registrazione.richieste where telefono = '3009000007') then raise exception 'STOP: restano richieste del numero di prova'; end if;
  raise notice 'pulizia di riserva: account di prova rimossi %, tesserati di prova rimossi %', n_acc_rimossi, n_t_rimossi;
end $$;
commit;
-- Dopo: 25_controllo_test_r6.sql → colonna "dopo_pulizia".
