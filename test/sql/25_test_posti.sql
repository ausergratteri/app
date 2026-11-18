-- Posti disponibili: si contano TUTTE le persone dell'iscrizione (lui/lei + familiari
-- e amici), sia quando ci si iscrive sia quando si aggiungono persone modificando.
-- Va eseguito dopo 20_test_accessi.sql (riusa le procedure t.*).
-- Dati: g1 = 3 posti, Maria (S) iscritta da sola (1 persona). g5 = 1 posto, occupato.
truncate t.esiti;
\set P '''00000000-0000-0000-0000-000000000001'''
\set D '''00000000-0000-0000-0000-000000000002'''
\set S '''00000000-0000-0000-0000-000000000003'''
\set G1 '''a0000000-0000-0000-0000-000000000001'''
\set MARIA_G1 '''c0000000-0000-0000-0000-000000000002'''

-- ---------- Nuove iscrizioni ----------
-- Maria si cancella (posti liberi: 3) e si reiscrive portando 3 persone: 4 > 3
call t.prova('posti: nuova iscrizione di 4 persone su 3 posti liberi → negato', :S,
  $x$delete from public.adesioni where id = 'c0000000-0000-0000-0000-000000000002';
     insert into public.adesioni (attivita_id, user_id, nome, acc) values ('a0000000-0000-0000-0000-000000000001', auth.uid(), 'Maria',
       '[{"nome":"A","rel":"Familiare"},{"nome":"B","rel":"Familiare"},{"nome":"C","rel":"Amico"}]')$x$, 'negato');
call t.prova('posti: nuova iscrizione di 3 persone su 3 posti liberi → consentito', :S,
  $x$delete from public.adesioni where id = 'c0000000-0000-0000-0000-000000000002';
     insert into public.adesioni (attivita_id, user_id, nome, acc) values ('a0000000-0000-0000-0000-000000000001', auth.uid(), 'Maria',
       '[{"nome":"A","rel":"Familiare"},{"nome":"B","rel":"Familiare"}]')$x$, 'consentito');
call t.prova('posti: iscrizione solo di familiari (io = no) conta i familiari → negato oltre il limite', :S,
  $x$delete from public.adesioni where id = 'c0000000-0000-0000-0000-000000000002';
     insert into public.adesioni (attivita_id, user_id, nome, io, acc) values ('a0000000-0000-0000-0000-000000000001', auth.uid(), 'Maria', false,
       '[{"nome":"A"},{"nome":"B"},{"nome":"C"},{"nome":"D"}]')$x$, 'negato');
call t.prova('posti: attività al completo, iscrizione di una persona → negato', :S,
  $x$insert into public.adesioni (attivita_id, user_id, nome) values ('a0000000-0000-0000-0000-000000000005', auth.uid(), 'Maria')$x$, 'negato');
call t.verifica('posti: il messaggio dice quanti posti restano', :S,
  $x$do $d$ begin
       delete from public.adesioni where id = 'c0000000-0000-0000-0000-000000000002';
       insert into public.adesioni (attivita_id, user_id, nome, acc) values ('a0000000-0000-0000-0000-000000000001', auth.uid(), 'Maria',
         '[{"nome":"A"},{"nome":"B"},{"nome":"C"}]');
       raise exception 'nessun errore';
     exception when others then
       perform set_config('t.msg', sqlerrm, true);
     end $d$$x$,
  $c$current_setting('t.msg') like '%posti esauriti, restano 3 posti%'$c$);

-- ---------- Modifiche dell'iscrizione ----------
call t.prova('posti: modifica che porta l''iscrizione a 4 persone su 3 posti → negato', :S,
  $x$update public.adesioni set acc = '[{"nome":"A"},{"nome":"B"},{"nome":"C"}]' where id = 'c0000000-0000-0000-0000-000000000002'$x$, 'negato');
call t.prova('posti: modifica che porta l''iscrizione a 3 persone su 3 posti → consentito', :S,
  $x$update public.adesioni set acc = '[{"nome":"A"},{"nome":"B"}]' where id = 'c0000000-0000-0000-0000-000000000002'$x$, 'consentito');
call t.prova('posti: modifica che non aggiunge persone (solo note) → consentito', :S,
  $x$update public.adesioni set note = 'Arrivo in ritardo' where id = 'c0000000-0000-0000-0000-000000000002'$x$, 'consentito');
-- Attività già oltre il limite (il direttivo ha aggiunto persone): togliere è sempre permesso
call t.verifica('posti: in un''attività già piena si possono togliere persone', :S,
  $x$select set_config('request.jwt.claim.sub', '', true);
     update public.attivita set posti = 1 where id = 'a0000000-0000-0000-0000-000000000001';
     update public.adesioni set acc = '[{"nome":"A"},{"nome":"B"}]' where id = 'c0000000-0000-0000-0000-000000000002';
     select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
     update public.adesioni set acc = '[{"nome":"A"}]' where id = 'c0000000-0000-0000-0000-000000000002'$x$,
  $c$(select jsonb_array_length(acc) from public.adesioni where id = 'c0000000-0000-0000-0000-000000000002') = 1$c$);
call t.verifica('posti: in un''attività già piena non si possono aggiungere persone', :S,
  $x$select set_config('request.jwt.claim.sub', '', true);
     update public.attivita set posti = 1 where id = 'a0000000-0000-0000-0000-000000000001';
     select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
     do $d$ begin
       update public.adesioni set acc = '[{"nome":"A"}]' where id = 'c0000000-0000-0000-0000-000000000002';
     exception when others then null; end $d$$x$,
  $c$(select jsonb_array_length(acc) from public.adesioni where id = 'c0000000-0000-0000-0000-000000000002') = 0$c$);

-- ---------- Il direttivo resta libero di gestire i posti (come prima) ----------
call t.prova('posti: il direttivo aggiunge persone oltre il limite → consentito', :D,
  $x$insert into public.adesioni (attivita_id, user_id, nome, acc) values ('a0000000-0000-0000-0000-000000000001', null, 'Iscritto a mano',
       '[{"nome":"A"},{"nome":"B"},{"nome":"C"}]')$x$, 'consentito');
call t.prova('posti: attività senza limite di posti, molte persone → consentito', :S,
  $x$insert into public.adesioni (attivita_id, user_id, nome) values ('a0000000-0000-0000-0000-000000000003', auth.uid(), 'Maria')$x$, 'consentito');

\pset format unaligned
\pset tuples_only on
\pset fieldsep '|'
select case when ok then 'PASS' else 'FAIL' end, nome, dettaglio from t.esiti order by n;
\pset format aligned
\pset tuples_only off
