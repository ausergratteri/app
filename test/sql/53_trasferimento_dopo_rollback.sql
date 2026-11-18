call t.verifica('rollback: la foto trasferita torna pubblica con il suo URL originale', null, 'select 1',
  $c$(select bucket = 'foto' and url like '%/object/public/foto/00000000-0000-0000-0000-000000000003/1-gita.jpg'
      from public.foto where id = 'd0000000-0000-0000-0000-000000000001')$c$);
call t.verifica('rollback: la foto caricata dopo il passaggio resta privata (nessuna perdita)', null, 'select 1',
  $c$(select bucket from public.foto where id = 'd0000000-0000-0000-0000-000000000009') = 'foto-private'$c$);
call t.verifica('rollback: tutte le altre righe come prima del passaggio', null, 'select 1',
  $c$not exists (select 1 from public.foto f join prima_url p using (id) where f.url <> p.url)$c$);
call t.verifica('rollback: nessun file eliminato', null, 'select 1', $c$(select count(*) from storage.objects) = 9$c$);

\pset format unaligned
\pset tuples_only on
\pset fieldsep '|'
select case when ok then 'PASS' else 'FAIL' end, nome, dettaglio from t.esiti order by n;
