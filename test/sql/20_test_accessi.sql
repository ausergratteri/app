-- Test degli accessi consentiti e negati. Ogni prova viene annullata alla fine,
-- quindi le prove non si influenzano a vicenda.
\set QUIET on
create schema t;
create table t.esiti (n serial, nome text, ok boolean, dettaglio text);

-- Esegue "comando" come quell'utente (null = anon) con le regole RLS attive.
-- atteso 'consentito': nessun errore e almeno una riga toccata/restituita.
-- atteso 'negato':     errore, oppure nessuna riga toccata (RLS filtra in silenzio).
create procedure t.prova(p_nome text, utente uuid, comando text, atteso text) language plpgsql as $$
declare righe bigint := 0; err text;
begin
  begin
    perform set_config('request.jwt.claim.sub', coalesce(utente::text, ''), true);
    execute case when utente is null then 'set local role anon' else 'set local role authenticated' end;
    execute comando;
    get diagnostics righe = row_count;
    raise exception using errcode = 'P0999', message = 'annulla';
  exception
    when sqlstate 'P0999' then null;
    when others then err := sqlerrm;
  end;
  insert into t.esiti (nome, ok, dettaglio) values (p_nome,
    case atteso when 'consentito' then err is null and righe > 0 else err is not null or righe = 0 end,
    coalesce('errore: ' || err, righe || ' righe'));
end $$;

-- Esegue "query" (che restituisce un numero) come quell'utente e confronta il risultato.
create procedure t.conta(p_nome text, utente uuid, query text, atteso bigint) language plpgsql as $$
declare n bigint; err text;
begin
  begin
    perform set_config('request.jwt.claim.sub', coalesce(utente::text, ''), true);
    execute case when utente is null then 'set local role anon' else 'set local role authenticated' end;
    execute query into n;
    raise exception using errcode = 'P0999', message = 'annulla';
  exception
    when sqlstate 'P0999' then null;
    when others then err := sqlerrm;
  end;
  insert into t.esiti (nome, ok, dettaglio) values (p_nome, err is null and n = atteso,
    coalesce('errore: ' || err, 'ottenuto ' || n || ', atteso ' || atteso));
end $$;

-- Esegue "comando" come amministratore (con auth.uid() = utente, o vuoto) e poi
-- verifica "condizione" nello stesso stato. Serve per registrazioni e PIN.
create procedure t.verifica(p_nome text, utente uuid, comando text, condizione text) language plpgsql as $$
declare esito boolean; err text;
begin
  begin
    perform set_config('request.jwt.claim.sub', coalesce(utente::text, ''), true);
    execute comando;
    execute 'select (' || condizione || ')' into esito;
    raise exception using errcode = 'P0999', message = 'annulla';
  exception
    when sqlstate 'P0999' then null;
    when others then err := sqlerrm;
  end;
  insert into t.esiti (nome, ok, dettaglio) values (p_nome, err is null and coalesce(esito, false),
    coalesce('errore: ' || err, 'condizione ' || coalesce(esito::text, 'null')));
end $$;

-- Persone e attività dei dati di prova
\set P '''00000000-0000-0000-0000-000000000001'''
\set D '''00000000-0000-0000-0000-000000000002'''
\set S '''00000000-0000-0000-0000-000000000003'''
\set A '''00000000-0000-0000-0000-000000000004'''

-- =====================================================================
-- 1. Registrazione dei soci
-- =====================================================================
call t.verifica('registrazione: il primo iscritto è presidente', null, 'select 1',
  $c$(select ruolo from public.profili where id = '00000000-0000-0000-0000-000000000001') = 'presidente'$c$);
call t.verifica('registrazione: tesserato con il suo numero entra come socio', null, 'select 1',
  $c$(select ruolo from public.profili where id = '00000000-0000-0000-0000-000000000003') = 'socio'$c$);
call t.verifica('registrazione: numero non tesserato resta in attesa', null, 'select 1',
  $c$(select ruolo from public.profili where id = '00000000-0000-0000-0000-000000000004') = 'in_attesa'$c$);
call t.verifica('registrazione: un nuovo tesserato entra ancora come socio', null,
  $x$insert into auth.users (id, email, raw_user_meta_data) values ('00000000-0000-0000-0000-0000000000a1', '3334444444@soci.ausergratteri.app', '{"nome":"Giovanni","telefono":"3334444444"}')$x$,
  $c$(select ruolo from public.profili where id = '00000000-0000-0000-0000-0000000000a1') = 'socio'$c$);
call t.verifica('registrazione: telefono di un tesserato solo nei metadata NON dà il ruolo socio', null,
  $x$insert into auth.users (id, email, raw_user_meta_data) values ('00000000-0000-0000-0000-0000000000a2', 'attaccante@example.com', '{"nome":"X","telefono":"3334444444"}')$x$,
  $c$(select ruolo from public.profili where id = '00000000-0000-0000-0000-0000000000a2') = 'in_attesa'$c$);
call t.verifica('registrazione: email interna con un numero e metadata con un altro: conta l''email', null,
  $x$insert into auth.users (id, email, raw_user_meta_data) values ('00000000-0000-0000-0000-0000000000a3', '3339999999@soci.ausergratteri.app', '{"nome":"X","telefono":"3334444444"}')$x$,
  $c$(select ruolo = 'in_attesa' and telefono = '3339999999' from public.profili where id = '00000000-0000-0000-0000-0000000000a3')$c$);
call t.verifica('registrazione: numero già usato da un profilo (con prefisso 39) NON dà il ruolo socio', null,
  $x$insert into auth.users (id, email, raw_user_meta_data) values ('00000000-0000-0000-0000-0000000000a4', '393331111111@soci.ausergratteri.app', '{"nome":"Doppione"}')$x$,
  $c$(select ruolo from public.profili where id = '00000000-0000-0000-0000-0000000000a4') = 'in_attesa'$c$);
call t.verifica('registrazione: se non c''è un presidente il nuovo iscritto lo diventa (avvio)', null,
  $x$update public.profili set ruolo = 'socio' where ruolo = 'presidente';
     insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a5', '3335555555@soci.ausergratteri.app')$x$,
  $c$(select ruolo from public.profili where id = '00000000-0000-0000-0000-0000000000a5') = 'presidente'$c$);
call t.verifica('registrazione: il nome viene troncato a 80 caratteri', null,
  $x$insert into auth.users (id, email, raw_user_meta_data) values ('00000000-0000-0000-0000-0000000000a6', '3336666666@soci.ausergratteri.app', jsonb_build_object('nome', repeat('x', 500)))$x$,
  $c$(select length(nome) from public.profili where id = '00000000-0000-0000-0000-0000000000a6') = 80$c$);

-- =====================================================================
-- 2. N1: "acc" non valido non deve bloccare l'app
-- =====================================================================
call t.prova('N1: socio salva acc oggetto {} → negato', :S,
  $x$insert into public.adesioni (attivita_id, user_id, nome, acc, canale) values ('a0000000-0000-0000-0000-000000000003', auth.uid(), 'Maria', '{}', 'App')$x$, 'negato');
call t.prova('N1: socio salva acc con numeri → negato', :S,
  $x$update public.adesioni set acc = '[1,2]' where id = 'c0000000-0000-0000-0000-000000000002'$x$, 'negato');
call t.prova('N1: socio salva acc con 13 persone → negato', :S,
  $x$update public.adesioni set acc = (select jsonb_agg(jsonb_build_object('nome', 'P' || i, 'rel', 'Amico')) from generate_series(1, 13) i) where id = 'c0000000-0000-0000-0000-000000000002'$x$, 'negato');
call t.prova('N1: socio salva acc con nome numerico → negato', :S,
  $x$update public.adesioni set acc = '[{"nome": 5}]' where id = 'c0000000-0000-0000-0000-000000000002'$x$, 'negato');
call t.prova('N1: socio aggiunge un familiare valido → consentito', :S,
  $x$update public.adesioni set acc = '[{"nome":"Rosa","rel":"Familiare"}]' where id = 'c0000000-0000-0000-0000-000000000002'$x$, 'consentito');
call t.prova('N1: conteggi() funziona per il socio', :S, $x$select * from public.conteggi()$x$, 'consentito');
call t.verifica('N1: nessuna adesione con acc non valido nel database', null, 'select 1',
  $c$not exists (select 1 from public.adesioni where jsonb_typeof(acc) <> 'array')$c$);

-- =====================================================================
-- 3. N2: chi è in attesa non elenca le foto
-- =====================================================================
call t.conta('N2: in attesa non vede i file del bucket', :A, $q$select count(*) from storage.objects where bucket_id = 'foto'$q$, 0);
call t.conta('N2: socio vede i file del bucket', :S, $q$select count(*) from storage.objects where bucket_id = 'foto'$q$, 2);
call t.conta('N2: anon non vede i file del bucket', null, $q$select count(*) from storage.objects$q$, 0);
call t.prova('N2: in attesa non carica file', :A,
  $x$insert into storage.objects (bucket_id, name) values ('foto', '00000000-0000-0000-0000-000000000004/x.jpg')$x$, 'negato');
call t.prova('N2: socio carica nella propria cartella → consentito', :S,
  $x$insert into storage.objects (bucket_id, name) values ('foto', '00000000-0000-0000-0000-000000000003/2-x.jpg')$x$, 'consentito');
call t.prova('N2: socio carica nella cartella di un altro → negato', :S,
  $x$insert into storage.objects (bucket_id, name) values ('foto', '00000000-0000-0000-0000-000000000001/logo2.png')$x$, 'negato');

-- =====================================================================
-- 4. Adesioni: regole dell'app anche sul database
-- =====================================================================
call t.prova('adesioni: socio si iscrive a gita aperta senza ospiti → consentito', :S,
  $x$insert into public.adesioni (attivita_id, user_id, nome, canale) values ('a0000000-0000-0000-0000-000000000003', auth.uid(), 'Maria', 'App')$x$, 'consentito');
call t.prova('adesioni: socio porta ospiti dove non sono ammessi → negato', :S,
  $x$insert into public.adesioni (attivita_id, user_id, nome, acc, canale) values ('a0000000-0000-0000-0000-000000000003', auth.uid(), 'Maria', '[{"nome":"Rosa","rel":"Familiare"}]', 'App')$x$, 'negato');
call t.prova('adesioni: socio si iscrive a gita chiusa → negato', :S,
  $x$insert into public.adesioni (attivita_id, user_id, nome, canale) values ('a0000000-0000-0000-0000-000000000002', auth.uid(), 'Maria', 'App')$x$, 'negato');
call t.prova('adesioni: socio si iscrive dopo la scadenza → negato', :S,
  $x$insert into public.adesioni (attivita_id, user_id, nome, canale) values ('a0000000-0000-0000-0000-000000000004', auth.uid(), 'Maria', 'App')$x$, 'negato');
call t.prova('adesioni: socio si iscrive a gita al completo → negato', :S,
  $x$insert into public.adesioni (attivita_id, user_id, nome, canale) values ('a0000000-0000-0000-0000-000000000005', auth.uid(), 'Maria', 'App')$x$, 'negato');
call t.prova('adesioni: socio conferma la presenza in assemblea → consentito', :S,
  $x$insert into public.adesioni (attivita_id, user_id, nome, canale) values ('b0000000-0000-0000-0000-000000000001', auth.uid(), 'Maria', 'App')$x$, 'consentito');
call t.prova('adesioni: socio si iscrive ad assemblea annullata → negato', :S,
  $x$insert into public.adesioni (attivita_id, user_id, nome, canale) values ('b0000000-0000-0000-0000-000000000002', auth.uid(), 'Maria', 'App')$x$, 'negato');
call t.prova('adesioni: socio si iscrive ad attività inesistente → negato', :S,
  $x$insert into public.adesioni (attivita_id, user_id, nome, canale) values (gen_random_uuid(), auth.uid(), 'Maria', 'App')$x$, 'negato');
call t.prova('adesioni: socio iscrive un''altra persona → negato', :S,
  $x$insert into public.adesioni (attivita_id, user_id, nome, canale) values ('a0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000004', 'Concetta', 'App')$x$, 'negato');
call t.prova('adesioni: socio sposta la sua iscrizione su una gita chiusa → negato', :S,
  $x$update public.adesioni set attivita_id = 'a0000000-0000-0000-0000-000000000002' where id = 'c0000000-0000-0000-0000-000000000002'$x$, 'negato');
call t.prova('adesioni: socio passa la sua iscrizione a un altro → negato', :S,
  $x$update public.adesioni set user_id = '00000000-0000-0000-0000-000000000004' where id = 'c0000000-0000-0000-0000-000000000002'$x$, 'negato');
call t.prova('adesioni: socio modifica le note della sua iscrizione → consentito', :S,
  $x$update public.adesioni set note = 'posto davanti' where id = 'c0000000-0000-0000-0000-000000000002'$x$, 'consentito');
call t.prova('adesioni: socio modifica l''iscrizione di un altro → negato', :S,
  $x$update public.adesioni set note = 'x' where id = 'c0000000-0000-0000-0000-000000000001'$x$, 'negato');
call t.prova('adesioni: socio annulla la sua iscrizione → consentito', :S,
  $x$delete from public.adesioni where id = 'c0000000-0000-0000-0000-000000000002'$x$, 'consentito');
call t.prova('adesioni: direttivo aggiunge a mano chi chiama al telefono (gita chiusa) → consentito', :D,
  $x$insert into public.adesioni (attivita_id, user_id, nome, canale) values ('a0000000-0000-0000-0000-000000000002', null, 'Nonna Pina', 'Telefono')$x$, 'consentito');
call t.prova('adesioni: in attesa non si iscrive → negato', :A,
  $x$insert into public.adesioni (attivita_id, user_id, nome, canale) values ('a0000000-0000-0000-0000-000000000001', auth.uid(), 'Concetta', 'App')$x$, 'negato');
call t.conta('adesioni: il socio vede solo la propria', :S, $q$select count(*) from public.adesioni$q$, 1);
call t.conta('adesioni: il direttivo vede anche quelle degli altri', :D,
  $q$select count(*) from public.adesioni where attivita_id in ('a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000005')$q$, 2);

-- =====================================================================
-- 5. Profili: ruolo, nome e telefono
-- =====================================================================
call t.prova('profili: socio cambia il proprio nome → consentito', :S,
  $x$update public.profili set nome = 'Maria R.' where id = auth.uid()$x$, 'consentito');
call t.prova('profili: socio cambia il proprio telefono → negato', :S,
  $x$update public.profili set telefono = '3334444444' where id = auth.uid()$x$, 'negato');
call t.prova('profili: socio si promuove → negato', :S,
  $x$update public.profili set ruolo = 'direttivo' where id = auth.uid()$x$, 'negato');
call t.prova('profili: in attesa si approva da solo → negato', :A,
  $x$update public.profili set ruolo = 'socio' where id = auth.uid()$x$, 'negato');
call t.prova('profili: direttivo approva chi è in attesa → consentito', :D,
  $x$update public.profili set ruolo = 'socio' where id = '00000000-0000-0000-0000-000000000004'$x$, 'consentito');
call t.prova('profili: direttivo promuove un socio a direttivo → negato', :D,
  $x$update public.profili set ruolo = 'direttivo' where id = '00000000-0000-0000-0000-000000000003'$x$, 'negato');
call t.prova('profili: direttivo cambia il nome del presidente → negato', :D,
  $x$update public.profili set nome = 'Finto' where id = '00000000-0000-0000-0000-000000000001'$x$, 'negato');
call t.prova('profili: direttivo cambia il telefono di un socio → negato', :D,
  $x$update public.profili set telefono = '3330000000' where id = '00000000-0000-0000-0000-000000000003'$x$, 'negato');
call t.prova('profili: presidente corregge il nome di un socio → consentito', :P,
  $x$update public.profili set nome = 'Maria Rossi (Gratteri)' where id = '00000000-0000-0000-0000-000000000003'$x$, 'consentito');
call t.prova('profili: presidente nomina un direttivo → consentito', :P,
  $x$update public.profili set ruolo = 'direttivo' where id = '00000000-0000-0000-0000-000000000003'$x$, 'consentito');
call t.prova('profili: presidente cambia il proprio ruolo → negato', :P,
  $x$update public.profili set ruolo = 'socio' where id = auth.uid()$x$, 'negato');
call t.prova('profili: direttivo rifiuta una richiesta in attesa → consentito', :D,
  $x$delete from public.profili where id = '00000000-0000-0000-0000-000000000004'$x$, 'consentito');
call t.prova('profili: direttivo elimina il presidente → negato', :D,
  $x$delete from public.profili where id = '00000000-0000-0000-0000-000000000001'$x$, 'negato');
call t.conta('profili: in attesa vede solo sé stesso', :A, $q$select count(*) from public.profili$q$, 1);
call t.prova('profili: anon non legge i profili → negato', null, $x$select * from public.profili$x$, 'negato');

-- =====================================================================
-- 6. Foto: percorso e proprietà (N3)
-- =====================================================================
call t.prova('foto: socio pubblica una foto della propria cartella → consentito', :S,
  $x$insert into public.foto (attivita_id, user_id, url, percorso) values ('a0000000-0000-0000-0000-000000000001', auth.uid(), 'https://x.supabase.co/a.jpg', '00000000-0000-0000-0000-000000000003/9-a.jpg')$x$, 'consentito');
call t.prova('foto: socio indica come percorso il logo del presidente → negato', :S,
  $x$insert into public.foto (attivita_id, user_id, url, percorso) values ('a0000000-0000-0000-0000-000000000001', auth.uid(), 'https://x.supabase.co/a.jpg', '00000000-0000-0000-0000-000000000001/logo.png')$x$, 'negato');
call t.prova('foto: socio usa ".." nel percorso → negato', :S,
  $x$insert into public.foto (attivita_id, user_id, url, percorso) values ('a0000000-0000-0000-0000-000000000001', auth.uid(), 'https://x.supabase.co/a.jpg', '00000000-0000-0000-0000-000000000003/../00000000-0000-0000-0000-000000000001/logo.png')$x$, 'negato');
call t.prova('foto: socio cambia il percorso di una sua foto verso un altro → negato', :S,
  $x$update public.foto set percorso = '00000000-0000-0000-0000-000000000001/logo.png' where id = 'd0000000-0000-0000-0000-000000000001'$x$, 'negato');
call t.prova('foto: socio passa la sua foto a un altro utente → negato', :S,
  $x$update public.foto set user_id = '00000000-0000-0000-0000-000000000002' where id = 'd0000000-0000-0000-0000-000000000001'$x$, 'negato');
call t.prova('foto: socio scrive la didascalia della sua foto → consentito', :S,
  $x$update public.foto set didascalia = 'Bella giornata' where id = 'd0000000-0000-0000-0000-000000000001'$x$, 'consentito');
call t.prova('foto: in attesa non vede le foto delle gite → negato', :A, $x$select * from public.foto$x$, 'negato');
call t.prova('foto: direttivo elimina un socio che ha foto (user_id diventa vuoto) → consentito', :D,
  $x$delete from public.profili where id = '00000000-0000-0000-0000-000000000003'$x$, 'consentito');

-- =====================================================================
-- 7. Nuovo PIN
-- =====================================================================
call t.prova('PIN: socio cambia il PIN di un altro → negato', :S,
  $x$select public.reimposta_pin('00000000-0000-0000-0000-000000000004', '123456')$x$, 'negato');
call t.prova('PIN: in attesa cambia il PIN di un altro → negato', :A,
  $x$select public.reimposta_pin('00000000-0000-0000-0000-000000000003', '123456')$x$, 'negato');
call t.prova('PIN: direttivo dà un nuovo PIN a un socio → consentito', :D,
  $x$select public.reimposta_pin('00000000-0000-0000-0000-000000000003', '123456')$x$, 'consentito');
call t.prova('PIN: direttivo cambia il PIN del presidente → negato', :D,
  $x$select public.reimposta_pin('00000000-0000-0000-0000-000000000001', '123456')$x$, 'negato');
call t.prova('PIN: PIN vuoto (null) → negato', :D,
  $x$select public.reimposta_pin('00000000-0000-0000-0000-000000000003', null)$x$, 'negato');
call t.prova('PIN: PIN di 5 cifre → negato', :D,
  $x$select public.reimposta_pin('00000000-0000-0000-0000-000000000003', '12345')$x$, 'negato');
call t.prova('PIN: presidente dà un nuovo PIN al direttivo → consentito', :P,
  $x$select public.reimposta_pin('00000000-0000-0000-0000-000000000002', '654321')$x$, 'consentito');
call t.verifica('PIN: dopo il cambio le sessioni aperte del socio sono chiuse', :D,
  $x$select public.reimposta_pin('00000000-0000-0000-0000-000000000003', '123456')$x$,
  $c$(select count(*) from auth.sessions where user_id = '00000000-0000-0000-0000-000000000003') = 0
     and (select count(*) from auth.sessions where user_id = '00000000-0000-0000-0000-000000000002') = 1$c$);

-- =====================================================================
-- 8. Link solo web
-- =====================================================================
call t.prova('link: direttivo pubblica in bacheca un link https → consentito', :D,
  $x$insert into public.bacheca (titolo, link) values ('Festa', 'https://www.instagram.com/p/abc')$x$, 'consentito');
call t.prova('link: direttivo pubblica in bacheca un link javascript: → negato', :D,
  $x$insert into public.bacheca (titolo, link) values ('Festa', 'javascript:alert(document.cookie)')$x$, 'negato');
call t.prova('link: socio pubblica in bacheca → negato', :S,
  $x$insert into public.bacheca (titolo, link) values ('Festa', 'https://x.it')$x$, 'negato');
call t.prova('link: presidente imposta Facebook https → consentito', :P,
  $x$update public.impostazioni set facebook = 'https://www.facebook.com/auser' where id = 1$x$, 'consentito');
call t.prova('link: presidente imposta Facebook javascript: → negato', :P,
  $x$update public.impostazioni set facebook = 'javascript:alert(1)' where id = 1$x$, 'negato');
call t.prova('link: direttivo cambia le impostazioni → negato', :D,
  $x$update public.impostazioni set motto = 'x' where id = 1$x$, 'negato');
call t.conta('impostazioni: anon le legge (pagina di accesso)', null, $q$select count(*) from public.impostazioni$q$, 1);

-- =====================================================================
-- 9. Lettura dei contenuti per ruolo (funzionamento attuale)
-- =====================================================================
call t.conta('attività: il socio le vede', :S, $q$select count(*) from public.attivita$q$, 5);
call t.conta('attività: chi è in attesa no', :A, $q$select count(*) from public.attivita$q$, 0);
call t.prova('attività: il socio non le crea → negato', :S,
  $x$insert into public.attivita (titolo, data) values ('x', current_date)$x$, 'negato');
call t.prova('attività: il direttivo le crea → consentito', :D,
  $x$insert into public.attivita (titolo, data) values ('Nuova gita', current_date + 10)$x$, 'consentito');
call t.conta('tesserati: il socio non li vede', :S, $q$select count(*) from public.tesserati$q$, 0);
call t.conta('tesserati: il direttivo li vede', :D, $q$select count(*) from public.tesserati$q$, 2);
call t.conta('sveglia(): funziona anche da anon', null, $q$select public.sveglia()$q$, 5);

-- ---------- Riepilogo ----------
\pset format unaligned
\pset tuples_only on
\pset fieldsep '|'
select case when ok then 'PASS' else 'FAIL' end, nome, dettaglio from t.esiti order by n;
