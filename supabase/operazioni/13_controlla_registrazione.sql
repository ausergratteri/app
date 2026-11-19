-- =====================================================================
--  AUSER GRATTERI – controlli per la registrazione con OTP. SOLA LETTURA.
--  Solo numeri: nessun nome, telefono o indirizzo e-mail nei risultati.
--  Prima di 20261123_registrazione_otp.sql: quanti soci potranno ricevere il codice.
--  Dopo: le funzioni e le regole sono quelle attese.
-- =====================================================================
select 'tesserati' as voce, count(*)::text as valore from public.tesserati
union all select 'tesserati con e-mail valida', count(*)::text from public.tesserati
  where email ~* '^[^@\s"''<>]+@[^@\s"''<>]+\.[^@\s"''<>]{2,}$'
union all select 'tesserati senza e-mail (serviranno il direttivo)', count(*)::text from public.tesserati where coalesce(email, '') = ''
union all select 'e-mail usate da più tesserati (es. coppie)', count(*)::text from (
  select lower(email) from public.tesserati where email <> '' group by lower(email) having count(*) > 1) x
union all select 'tesserati con e-mail e senza account (potranno usare il codice)', count(*)::text from public.tesserati t
  where t.email <> '' and not exists (select 1 from public.profili p where public.solo_cifre_tel(p.telefono) = public.solo_cifre_tel(t.telefono))
union all select 'profili in attesa con il telefono di un tesserato', count(*)::text from public.profili p
  where p.ruolo = 'in_attesa' and exists (select 1 from public.tesserati t where public.solo_cifre_tel(t.telefono) = public.solo_cifre_tel(p.telefono))
union all select 'schema registrazione presente (dopo la migrazione)', (to_regnamespace('registrazione') is not null)::text
union all select 'funzioni di registrazione eseguibili da anon (deve essere 0)', count(*)::text from pg_proc p
  where p.proname like 'registrazione\_%' and has_function_privilege('anon', p.oid, 'execute')
union all select 'funzioni di registrazione eseguibili da authenticated (deve essere 0)', count(*)::text from pg_proc p
  where p.proname like 'registrazione\_%' and has_function_privilege('authenticated', p.oid, 'execute');
