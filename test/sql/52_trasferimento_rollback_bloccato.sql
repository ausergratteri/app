\set ON_ERROR_STOP 1
call t.verifica('rollback: senza copia pubblica non cambia nulla', null, 'select 1',
  $c$(select bucket from public.foto where id = 'd0000000-0000-0000-0000-000000000001') = 'foto-private'$c$);
insert into storage.objects select * from oggetto_tolto;
