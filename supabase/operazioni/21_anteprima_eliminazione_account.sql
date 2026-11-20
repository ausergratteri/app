-- =====================================================================
--  AUSER GRATTERI – ANTEPRIMA dell'eliminazione degli account non presidente. SOLA LETTURA, un'unica SELECT.
--  Per ciascun ruolo (direttivo, socio, in_attesa) mostra cosa verrebbe CANCELLATO, cosa verrebbe STACCATO
--  (colonna messa a vuoto) e cosa resterebbe INVARIATO se si eliminasse l'account Auth.
--  In testa: i vincoli REALI del database verso auth.users e public.profili (azione in cancellazione).
--  Nessun nome, telefono o indirizzo: solo nomi tecnici e numeri.
-- =====================================================================
with
vincoli as (
  select c.conrelid::regclass::text as tabella, a.attname as colonna, c.confrelid::regclass::text as riferisce,
         case c.confdeltype when 'c' then 'CANCELLA (cascade)' when 'n' then 'METTE A VUOTO (set null)'
              when 'r' then 'IMPEDISCE (restrict)' when 'a' then 'IMPEDISCE (no action)' when 'd' then 'VALORE PREDEFINITO' end as azione
    from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any(c.conkey)
   where c.contype = 'f' and c.confrelid in ('auth.users'::regclass, 'public.profili'::regclass)),
acc as (select p.id, p.ruolo, p.telefono from public.profili p where p.ruolo <> 'presidente'),
conta(tab, col) as (values ('auth.identities', 'user_id'), ('auth.sessions', 'user_id'), ('auth.mfa_factors', 'user_id'),
                           ('auth.one_time_tokens', 'user_id'), ('auth.refresh_tokens', 'user_id')),
r(ord, sezione, voce, valore) as (
  select 10 + row_number() over (order by tabella, colonna), 'vincoli reali', tabella || '.' || colonna || ' → ' || riferisce, azione from vincoli
  union all
  select 100 + row_number() over (order by ruolo), 'ruolo: ' || ruolo, 'account con questo ruolo', count(*)::text from acc group by ruolo
  -- CANCELLATO a cascata
  union all select 200 + row_number() over (order by a.ruolo), 'ruolo: ' || a.ruolo, 'CANCELLATO: profilo', '1' from acc a
  union all select 210 + row_number() over (order by a.ruolo), 'ruolo: ' || a.ruolo, 'CANCELLATO: iscrizioni (adesioni)',
    (select count(*) from public.adesioni d where d.user_id = a.id)::text
    || ' (persone incluse: ' || (select coalesce(sum((case when d.io then 1 else 0 end) + (case when jsonb_typeof(d.acc) = 'array' then jsonb_array_length(d.acc) else 0 end)), 0) from public.adesioni d where d.user_id = a.id) || ')'
    from acc a
  union all select 220 + row_number() over (order by a.ruolo, c.tab), 'ruolo: ' || a.ruolo, 'CANCELLATO: ' || c.tab,
    coalesce((xpath('/row/n/text()', query_to_xml(format('select count(*) as n from %s where %I = %L', c.tab, c.col, a.id), false, true, '')))[1]::text, '?')
    from acc a, conta c where to_regclass(c.tab) is not null
      and exists (select 1 from information_schema.columns where table_schema || '.' || table_name = c.tab and column_name = c.col)
  -- STACCATO (set null): resta la riga, perde il collegamento
  union all select 300 + row_number() over (order by a.ruolo), 'ruolo: ' || a.ruolo, 'STACCATO (resta, senza autore): foto', (select count(*) from public.foto f where f.user_id = a.id)::text from acc a
  union all select 310 + row_number() over (order by a.ruolo), 'ruolo: ' || a.ruolo, 'STACCATO: importazioni eseguite', (select count(*) from public.importazioni i where i.eseguita_da = a.id)::text from acc a
  -- INVARIATO (nessun vincolo): da controllare a mano se serve
  union all select 400 + row_number() over (order by a.ruolo), 'ruolo: ' || a.ruolo, 'INVARIATO: file in Storage (proprietario o cartella)',
    (select count(*) from storage.objects o where o.owner = a.id or o.owner_id = a.id::text
       or (o.bucket_id in ('foto', 'foto-private') and (storage.foldername(o.name))[1] = a.id::text))::text from acc a
  union all select 410 + row_number() over (order by a.ruolo), 'ruolo: ' || a.ruolo, 'INVARIATO: voce in anagrafica (tesserato con quel telefono)',
    (select count(*) from public.tesserati t where public.solo_cifre_tel(t.telefono) = public.solo_cifre_tel(a.telefono) and public.solo_cifre_tel(a.telefono) <> '')::text from acc a
  -- Totali che non devono cambiare (a parte le righe "CANCELLATO" sopra)
  union all select 900, 'totali attuali', 'account / profili', (select count(*) from auth.users) || ' / ' || (select count(*) from public.profili)
  union all select 901, 'totali attuali', 'adesioni / foto / tesserati', (select count(*) from public.adesioni) || ' / ' || (select count(*) from public.foto) || ' / ' || (select count(*) from public.tesserati)
  union all select 902, 'totali attuali', 'attivita / assemblee / bacheca', (select count(*) from public.attivita) || ' / ' || (select count(*) from public.assemblee) || ' / ' || (select count(*) from public.bacheca)
)
select sezione, voce, valore from r order by ord;
