-- =====================================================================
--  AUSER GRATTERI – impronte di integrità PRIMA e DOPO l'eliminazione degli account (22 e 23).
--  SOLA LETTURA, un'unica SELECT. Si esegue prima e dopo: i valori marcati "identico" non devono cambiare.
--  Solo numeri e impronte (12 caratteri): nessun nome, telefono o indirizzo.
-- =====================================================================
select misura, valore, atteso_dopo from (values
  (1,  'account (auth.users)',                        (select count(*) from auth.users)::text,                                           'prima − 2'),
  (2,  'profili per ruolo',                           (select string_agg(ruolo || '=' || n, ', ' order by ruolo) from (select ruolo, count(*) n from public.profili group by ruolo) x), 'presidente=1'),
  (3,  'iscrizioni totali',                           (select count(*) from public.adesioni)::text,                                      'identico'),
  (4,  'iscrizioni senza account (user_id vuoto)',    (select count(*) from public.adesioni where user_id is null)::text,                'prima + 2'),
  (5,  'persone iscritte in totale (posti occupati)', (select coalesce(sum((case when io then 1 else 0 end) + (case when jsonb_typeof(acc) = 'array' then jsonb_array_length(acc) else 0 end)), 0) from public.adesioni)::text, 'identico'),
  (6,  'impronta del CONTENUTO di tutte le iscrizioni (senza user_id)',
       (select left(md5(coalesce(string_agg(concat_ws('|', id, attivita_id, nome, io, acc::text, note, canale, creato_il), '#' order by id), '')), 12) from public.adesioni), 'identico'),
  (7,  'tesserati',                                   (select count(*) from public.tesserati)::text,                                     'identico'),
  (8,  'impronta COMPLETA dell''anagrafica (tutte le colonne)',
       (select left(md5(coalesce(string_agg(t::text, '#' order by t.id), '')), 12) from public.tesserati t), 'identico'),
  (9,  'foto (righe) / impronta completa',
       (select count(*) || ' / ' || left(md5(coalesce(string_agg(f::text, '#' order by f.id), '')), 12) from public.foto f), 'identico'),
  (10, 'attivita / assemblee / bacheca / impostazioni',
       (select count(*) from public.attivita) || ' / ' || (select count(*) from public.assemblee) || ' / ' || (select count(*) from public.bacheca) || ' / ' || (select count(*) from public.impostazioni), 'identico'),
  (11, 'file in Storage', (select count(*) from storage.objects)::text, 'identico')
) v(ord, misura, valore, atteso_dopo) order by ord;
