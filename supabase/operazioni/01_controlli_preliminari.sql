-- =====================================================================
--  AUSER GRATTERI – controlli PRIMA della migrazione 20261118 (sola lettura)
--  Non modifica nulla. Eseguire nel SQL Editor e leggere ogni riga:
--  "ok" = nessun problema; altrimenti c'è il numero di righe da guardare.
-- =====================================================================
with acc_check as (
  select id, acc,
         case
           when jsonb_typeof(acc) <> 'array' then 'non è una lista'
           when jsonb_array_length(acc) > 12 then 'più di 12 accompagnatori'
           when exists (select 1 from jsonb_array_elements(acc) e
                        where jsonb_typeof(e) <> 'object'
                           or jsonb_typeof(coalesce(e->'nome', '""'::jsonb)) <> 'string'
                           or jsonb_typeof(coalesce(e->'rel', '""'::jsonb)) not in ('string','null'))
             then 'accompagnatore non valido'
         end as problema
  from public.adesioni
)
select '01 presidenti presenti (deve essere almeno 1)' as controllo,
       (select count(*) from public.profili where ruolo = 'presidente')::text as esito
union all
select '02 adesioni con acc NON lista (la migrazione le svuota)',
       coalesce(nullif((select count(*) from acc_check where problema = 'non è una lista'), 0)::text, 'ok')
union all
select '03 adesioni con >12 accompagnatori o elementi non validi (restano, ma non si potranno modificare)',
       coalesce(nullif((select count(*) from acc_check where problema in ('più di 12 accompagnatori','accompagnatore non valido')), 0)::text, 'ok')
union all
select '04 avvisi in bacheca con link non http/https (non si potranno modificare finché non si corregge il link)',
       coalesce(nullif((select count(*) from public.bacheca where link <> '' and link !~* '^https?://'), 0)::text, 'ok')
union all
select '05 impostazioni con social non http/https (BLOCCA anche il cambio di tema/logo: correggere PRIMA)',
       coalesce(nullif((select count(*) from public.impostazioni
                        where (facebook <> '' and facebook !~* '^https?://')
                           or (instagram <> '' and instagram !~* '^https?://')
                           or (whatsapp <> '' and whatsapp !~* '^https?://')), 0)::text, 'ok')
union all
select '06 foto con percorso fuori dalla cartella di chi le ha caricate (il file non verrà più cancellato dall''app)',
       coalesce(nullif((select count(*) from public.foto
                        where percorso <> '' and (user_id is null or split_part(percorso, '/', 1) <> user_id::text)), 0)::text, 'ok')
union all
select '07 soci con telefono che compare in più profili (possibili registrazioni con numero altrui)',
       coalesce(nullif((select count(*) from (select public.solo_cifre_tel(telefono) t from public.profili
                        where public.solo_cifre_tel(telefono) <> '' group by 1 having count(*) > 1) x), 0)::text, 'ok')
union all
select '08 profili "socio" il cui telefono nel profilo NON corrisponde all''email di accesso',
       coalesce(nullif((select count(*) from public.profili p join auth.users u on u.id = p.id
                        where p.ruolo = 'socio'
                          and public.solo_cifre_tel(p.telefono) <> public.solo_cifre_tel(split_part(u.email, '@', 1))), 0)::text, 'ok')
union all
select '09 account di accesso senza profilo (es. richieste rifiutate: il numero resta occupato)',
       coalesce(nullif((select count(*) from auth.users u where not exists (select 1 from public.profili p where p.id = u.id)), 0)::text, 'ok')
union all
select '10 il proprietario delle funzioni può chiudere le sessioni (auth.sessions)',
       case when to_regclass('auth.sessions') is null then 'tabella assente: le sessioni non verranno chiuse'
            when has_table_privilege(current_user, 'auth.sessions', 'DELETE') then 'ok'
            else 'NO: il PIN cambierà ma le sessioni aperte resteranno' end
union all
select '11 oggetti con lo stesso nome dei nuovi (trigger/funzioni/vincoli già presenti)',
       coalesce(nullif((select count(*) from pg_proc where proname in ('acc_valido','controlla_adesione','controlla_foto') and pronamespace = 'public'::regnamespace)
                     + (select count(*) from pg_trigger where tgname in ('prima_di_salvare_adesione','prima_di_salvare_foto'))
                     + (select count(*) from pg_constraint where conname in ('adesioni_acc_valido','bacheca_link_web','impostazioni_link_web')), 0)::text,
                'ok (prima esecuzione)')
union all
select '12 tesserati con lo stesso telefono (BLOCCA la migrazione 20261119: unire o correggere PRIMA)',
       coalesce(nullif((select count(*) from (select public.solo_cifre_tel(telefono) from public.tesserati
                        where public.solo_cifre_tel(telefono) <> '' group by 1 having count(*) > 1) x), 0)::text, 'ok')
union all
select '13 tesserati senza telefono (non verranno riconosciuti all''importazione)',
       coalesce(nullif((select count(*) from public.tesserati where public.solo_cifre_tel(telefono) = ''), 0)::text, 'ok');

-- Dettaglio delle righe da guardare (vuoto = niente da fare)
select 'adesione' as tipo, id::text, left(acc::text, 120) as valore from public.adesioni
 where case when jsonb_typeof(acc) <> 'array' then true
            when jsonb_array_length(acc) > 12 then true
            else exists (select 1 from jsonb_array_elements(acc) e
                         where jsonb_typeof(e) <> 'object'
                            or jsonb_typeof(coalesce(e->'nome', '""'::jsonb)) <> 'string'
                            or jsonb_typeof(coalesce(e->'rel', '""'::jsonb)) not in ('string','null')) end
union all
select 'bacheca', id::text, link from public.bacheca where link <> '' and link !~* '^https?://'
union all
select 'impostazioni', id::text, concat_ws(' | ', facebook, instagram, whatsapp) from public.impostazioni
 where (facebook <> '' and facebook !~* '^https?://') or (instagram <> '' and instagram !~* '^https?://') or (whatsapp <> '' and whatsapp !~* '^https?://')
union all
select 'profilo socio: telefono ≠ email', p.id::text, p.nome || ' · ' || p.telefono || ' · ' || u.email
  from public.profili p join auth.users u on u.id = p.id
 where p.ruolo = 'socio' and public.solo_cifre_tel(p.telefono) <> public.solo_cifre_tel(split_part(u.email, '@', 1))
union all
select 'tesserati con telefono doppio', string_agg(id::text, ', '), string_agg(nome || ' · ' || telefono, ' | ')
  from public.tesserati where public.solo_cifre_tel(telefono) <> ''
 group by public.solo_cifre_tel(telefono) having count(*) > 1;
