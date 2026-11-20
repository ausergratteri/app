-- =====================================================================
--  AUSER GRATTERI – controllo del test controllato R6 in produzione. SOLA LETTURA, un'unica SELECT.
--  Si esegue PRIMA del test, DOPO il primo accesso di prova e DOPO la pulizia.
--  Riguarda solo il tesserato INVENTATO con telefono 3009000007 e l'eventuale suo account di prova;
--  il resto sono conteggi (nessun nome, telefono o indirizzo a schermo).
-- =====================================================================
select misura, valore, prima, dopo_primo_accesso, dopo_pulizia from (values
  (1, 'account (auth.users)', (select count(*) from auth.users)::text, '3', '4', '3'),
  (2, 'profili per ruolo', (select string_agg(ruolo || '=' || n, ', ' order by ruolo) from (select ruolo, count(*) n from public.profili group by ruolo) x),
      'direttivo=1, presidente=1, socio=1', 'direttivo=1, presidente=1, socio=2', 'direttivo=1, presidente=1, socio=1'),
  (3, 'tesserato di prova 3009000007 presente', (select count(*) from public.tesserati where public.solo_cifre_tel(telefono) = '3009000007')::text, '0', '1', '0'),
  (4, 'tesserato di prova con e-mail', (select count(*) from public.tesserati where public.solo_cifre_tel(telefono) = '3009000007' and email <> '')::text, '0', '1', '0'),
  (5, 'account di prova (telefono 3009000007) e ruolo',
      coalesce((select string_agg(p.ruolo, ',') from public.profili p where public.solo_cifre_tel(p.telefono) = '3009000007'), 'nessuno'), 'nessuno', 'socio', 'nessuno'),
  (6, 'dati dell''account di prova (iscrizioni + foto)',
      (select count(*) from public.adesioni a join public.profili p on p.id = a.user_id where public.solo_cifre_tel(p.telefono) = '3009000007')
      + (select count(*) from public.foto f join public.profili p on p.id = f.user_id where public.solo_cifre_tel(p.telefono) = '3009000007') || '', '0', '0', '0'),
  (7, 'richieste OTP per 3009000007 (totali / verificate / usate / bloccate)',
      (select count(*) || ' / ' || count(*) filter (where verificata_il is not null) || ' / ' || count(*) filter (where usata_il is not null)
              || ' / ' || count(*) filter (where tentativi >= 5) from registrazione.richieste where telefono = '3009000007'), '0 / 0 / 0 / 0', '1 / 1 / 1 / 0', '0 / 0 / 0 / 0'),
  (8, 'tesserati (totale) / con e-mail', (select count(*) || ' / ' || count(*) filter (where email <> '') from public.tesserati), '38 / 0', '39 / 1', '38 / 0'),
  (9, 'iscrizioni / foto', (select count(*) from public.adesioni) || ' / ' || (select count(*) from public.foto), '21 / 204', '21 / 204', '21 / 204'),
  (10, 'account in attesa (estranei al test)', (select count(*) from public.profili where ruolo = 'in_attesa')::text, '0', '0', '0')
) v(ord, misura, valore, prima, dopo_primo_accesso, dopo_pulizia) order by ord;
-- Nota: rimuovendo il tesserato di prova ("Togli") le sue richieste OTP si cancellano a cascata
-- (registrazione.richieste.tesserato_id → tesserati ON DELETE CASCADE).
