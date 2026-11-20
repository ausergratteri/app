-- =====================================================================
--  AUSER GRATTERI – nomina del PRIMO presidente (solo su un database nuovo)
--  Dal 20261123 nessuno diventa presidente registrandosi. Su una installazione nuova:
--   1. la persona che sarà presidente si registra dall'app (Primo accesso → "chiedo al
--      direttivo"): il suo account nasce "in attesa";
--   2. l'amministratore esegue questo script nel SQL Editor, dopo aver scritto il suo
--      numero di telefono al posto di 3XXXXXXXXX (solo cifre, senza +39).
--  Si ferma se esiste già un presidente o se il numero non corrisponde a un solo account.
-- =====================================================================
begin;
do $$
declare
  numero constant text := '3XXXXXXXXX';   -- <-- numero della persona da nominare
  n int;
begin
  if exists (select 1 from public.profili where ruolo = 'presidente') then
    raise exception 'Esiste già un presidente: nessuna modifica fatta';
  end if;
  select count(*) into n from public.profili where public.solo_cifre_tel(telefono) = public.solo_cifre_tel(numero);
  if n <> 1 then
    raise exception 'Il numero corrisponde a % account (deve essere 1): nessuna modifica fatta', n;
  end if;
  update public.profili set ruolo = 'presidente' where public.solo_cifre_tel(telefono) = public.solo_cifre_tel(numero);
end $$;
commit;
select ruolo, count(*) from public.profili group by ruolo order by ruolo;
