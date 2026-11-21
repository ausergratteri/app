-- Verifica il passaggio a ex socio con le autorizzazioni reali dei tre ruoli.
begin;
\set P '''00000000-0000-0000-0000-000000000001'''
\set D '''00000000-0000-0000-0000-000000000002'''
\set S '''00000000-0000-0000-0000-000000000003'''

set local role authenticated;
set local request.jwt.claim.sub = :D;
do $$
begin
  begin
    perform public.imposta_ex_socio('00000000-0000-0000-0000-000000000003', true);
    raise exception 'Il direttivo ha sospeso un socio';
  exception when raise_exception then
    if sqlerrm <> 'Solo il presidente può gestire gli ex soci' then raise; end if;
  end;
end $$;

set local request.jwt.claim.sub = :P;
select public.imposta_ex_socio(:S, true) as ignorato \gset
select public.imposta_ex_socio(:S, true) as ignorato \gset

set local request.jwt.claim.sub = :S;
do $$
begin
  if public.livello() <> 0 or exists (select 1 from public.foto)
     or exists (select 1 from public.adesioni) then
    raise exception 'Un ex socio conserva accesso ai dati riservati';
  end if;
end $$;

set local request.jwt.claim.sub = :D;
do $$
begin
  if not exists (select 1 from public.foto
    where user_id = '00000000-0000-0000-0000-000000000003' and autore = 'ex socio') then
    raise exception 'Foto mancante o attribuzione non aggiornata';
  end if;
end $$;
-- Lo stesso dato è leggibile da un socio normale senza accesso al profilo dell'autore.
reset role;
set local request.jwt.claim.sub = '';
update public.profili set ruolo = 'socio' where id = :D;
set local role authenticated;
set local request.jwt.claim.sub = :D;
do $$
begin
  if not exists (select 1 from public.foto
     where id = 'd0000000-0000-0000-0000-000000000001' and autore = 'ex socio')
     or exists (select 1 from public.profili where id = '00000000-0000-0000-0000-000000000003') then
    raise exception 'Attribuzione anonima mancante o profilo leggibile dal socio';
  end if;
end $$;

reset role;
do $$
begin
  if exists (select 1 from auth.sessions where user_id = '00000000-0000-0000-0000-000000000003')
     or not exists (select 1 from public.adesioni where user_id = '00000000-0000-0000-0000-000000000003') then
    raise exception 'Sessioni ancora presenti o iscrizione persa';
  end if;
end $$;

set local role authenticated;
set local request.jwt.claim.sub = :P;
select public.imposta_ex_socio(:S, false) as ignorato \gset
set local request.jwt.claim.sub = :S;
do $$
begin
  if public.livello() <> 1 or not exists (select 1 from public.foto
    where id = 'd0000000-0000-0000-0000-000000000001' and autore = 'Maria Rossi') then
    raise exception 'Accesso o attribuzione non ripristinati';
  end if;
end $$;

rollback;
\echo PASS: revoca, etichetta, conservazione e riattivazione ex soci
