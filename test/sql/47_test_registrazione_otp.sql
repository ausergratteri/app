-- Registrazione con codice OTP via e-mail (migrazione 20261123_registrazione_otp.sql).
-- Va eseguito dopo 20_test_accessi.sql (riusa t.esiti). Ogni prova è annullata alla fine.
-- La funzione server calcola l'HMAC del codice: qui lo simula t.h() (SHA-256 del codice).
-- Completamento come la funzione server: prenotazione (consuma il gettone una volta) →
-- eventuale eliminazione dell'account "in attesa" senza dati → account NUOVO (insert in
-- auth.users, nasce "in attesa") → conferma. I metadati dell'account non contano più.
truncate t.esiti;
do $$ begin perform set_config('request.jwt.claim.sub', '', false); end $$;

create function t.h(codice text) returns text language sql as $$ select encode(extensions.digest(codice, 'sha256'), 'hex') $$;
create function t.ok(nome text, ok boolean, dettaglio text default '') returns void language sql as $$
  insert into t.esiti (nome, ok, dettaglio) values (nome, coalesce(ok, false), coalesce(dettaglio, ''));
$$;

-- Dati: Giovanni Bianchi (tesserato, 3334444444, non registrato) con e-mail in anagrafica;
-- Anna Verdi (tesserata senza e-mail); Concetta Attesa (A, account "in attesa") ora tesserata.
update public.tesserati set email = 'giovanni.bianchi@esempio.it' where nome = 'Giovanni Bianchi';
insert into public.tesserati (nome, telefono, email) values
  ('Verdi Anna', '3335550470', ''),
  ('ATTESA CONCETTA', '3333333333', 'concetta@esempio.it');

-- Ogni prova: un blocco annullato alla fine; l'esito si registra dopo l'annullamento.
create procedure t.caso(p_nome text, corpo text) language plpgsql as $$
declare esito boolean; dettaglio text;
begin
  begin
    execute 'create temp table if not exists esito_caso (ok boolean, det text) on commit drop';
    execute corpo;
    select e.ok, e.det into esito, dettaglio from esito_caso e limit 1;
    raise exception using errcode = 'P0999', message = 'annulla';
  exception
    when sqlstate 'P0999' then null;
    when others then esito := false; dettaglio := 'errore: ' || sqlerrm;
  end;
  perform t.ok(p_nome, esito, dettaglio);
end $$;
-- Dentro un caso: registra la condizione
create function t.vale(ok boolean, det text default '') returns void language plpgsql as $$
begin insert into esito_caso values (ok, det); end $$;
-- Simula la funzione server: avvia → (codice) → richiesta
create function t.avvia(nome text, cognome text, tel text, codice text default '123456', ip text default 'ip-di-prova-00000000')
returns table (richiesta uuid, esito text, invia boolean, email text, nome_anagrafica text)
language sql as $$ select * from public.registrazione_avvia(nome, cognome, tel, t.h(ip), t.h(codice)) $$;

-- ---------- Permessi: solo la funzione server ----------
call t.caso('permessi: anon e utenti non eseguono le funzioni di registrazione; service_role sì', $c$
  select t.vale(
    not has_function_privilege('anon', 'public.registrazione_avvia(text,text,text,text,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.registrazione_avvia(text,text,text,text,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.registrazione_verifica(uuid,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.registrazione_prenota(uuid,text)', 'execute')
    and not has_function_privilege('anon', 'public.registrazione_prenota(uuid,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.registrazione_elimina_attesa(uuid,text,uuid)', 'execute')
    and not has_function_privilege('anon', 'public.registrazione_elimina_attesa(uuid,text,uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.registrazione_conferma(uuid,text,uuid)', 'execute')
    and not has_function_privilege('anon', 'public.registrazione_conferma(uuid,text,uuid)', 'execute')
    and not has_function_privilege('authenticated', 'registrazione.ha_dati(uuid)', 'execute')
    and has_function_privilege('service_role', 'public.registrazione_prenota(uuid,text)', 'execute')
    and has_function_privilege('service_role', 'public.registrazione_elimina_attesa(uuid,text,uuid)', 'execute')
    and has_function_privilege('service_role', 'public.registrazione_conferma(uuid,text,uuid)', 'execute')
    and not has_function_privilege('anon', 'public.registrazione_manuale_consentita(text,text)', 'execute')
    and has_function_privilege('service_role', 'public.registrazione_avvia(text,text,text,text,text)', 'execute')
    and has_function_privilege('service_role', 'public.registrazione_verifica(uuid,text)', 'execute')
    and not has_schema_privilege('anon', 'registrazione', 'usage')
    and not has_schema_privilege('authenticated', 'registrazione', 'usage'))$c$);
call t.prova('permessi: un socio non chiama registrazione_avvia → negato', '00000000-0000-0000-0000-000000000003',
  $x$select * from public.registrazione_avvia('Giovanni', 'Bianchi', '3334444444', repeat('a', 64), repeat('b', 64))$x$, 'negato');
call t.prova('permessi: anon non chiama registrazione_verifica → negato', null,
  $x$select * from public.registrazione_verifica(gen_random_uuid(), repeat('b', 64))$x$, 'negato');
call t.prova('permessi: anon non legge le richieste → negato', null, $x$select * from registrazione.richieste$x$, 'negato');
call t.prova('permessi: anon non legge i tesserati → negato', null, $x$select * from public.tesserati$x$, 'negato');
call t.conta('permessi: un socio non vede i tesserati', '00000000-0000-0000-0000-000000000003',
  $q$select count(*) from public.tesserati$q$, 0);

-- ---------- Corrispondenza con l'anagrafica ----------
call t.caso('nomi: ordine, maiuscole, accenti e apostrofi non contano', $c$
  select t.vale(registrazione.nomi_corrispondono('ROSSI MARIA GRAZIA', 'Maria', 'Rossi')
    and registrazione.nomi_corrispondono('D''Angelo Niccolò', 'niccolo', 'd angelo')
    and registrazione.nomi_corrispondono('Bianchi Giovanni', ' Giovanni ', 'BIANCHI'))$c$);
call t.caso('nomi: nome sbagliato, parziale o vuoto non corrispondono', $c$
  select t.vale(not registrazione.nomi_corrispondono('Bianchi Giovanni', 'Mario', 'Bianchi')
    and not registrazione.nomi_corrispondono('Bianchi Giovanni', 'Gio', 'Bianchi')
    and not registrazione.nomi_corrispondono('Bianchi Giovanni', '', 'Bianchi')
    and not registrazione.nomi_corrispondono('Bianchi Giovanni', 'Giovanni', ''))$c$);

-- ---------- Avvio ----------
call t.caso('avvio: tesserato riconosciuto con e-mail in anagrafica → si invia il codice a QUELLA e-mail', $c$
  select t.vale(invia and esito = 'ok' and email = 'giovanni.bianchi@esempio.it' and richiesta is not null, coalesce(email, '-'))
  from t.avvia('Giovanni', 'Bianchi', '+39 333 444 4444')$c$);
call t.caso('avvio: il codice non è salvato in chiaro (solo l''impronta)', $c$
  select t.avvia('Giovanni', 'Bianchi', '3334444444', '482913');
  select t.vale(not exists (select 1 from registrazione.richieste r where r::text like '%482913%')
                and exists (select 1 from registrazione.richieste where otp_hash = t.h('482913')))$c$);
call t.caso('avvio: nome che non corrisponde → nessun invio, stessa risposta', $c$
  select t.vale(not invia and esito = 'ok' and richiesta is not null and email is null) from t.avvia('Mario', 'Bianchi', '3334444444')$c$);
call t.caso('avvio: numero non tesserato → nessun invio, stessa risposta', $c$
  select t.vale(not invia and esito = 'ok' and richiesta is not null and email is null) from t.avvia('Mario', 'Neri', '3330009999')$c$);
call t.caso('avvio: tesserata senza e-mail → nessun invio (servirà il direttivo)', $c$
  select t.vale(not invia and esito = 'ok' and richiesta is not null) from t.avvia('Anna', 'Verdi', '3335550470')$c$);
call t.caso('avvio: numero di un socio già registrato → nessun invio (niente appropriazioni)', $c$
  update public.tesserati set email = 'maria@esempio.it' where nome = 'Maria Rossi';
  select t.vale(not invia and esito = 'ok') from t.avvia('Maria', 'Rossi', '3331111111')$c$);
call t.caso('avvio: numero con account "in attesa" e tesserato con e-mail → si invia (si potrà riprendere)', $c$
  select t.vale(invia and email = 'concetta@esempio.it') from t.avvia('Concetta', 'Attesa', '3333333333')$c$);
call t.caso('avvio: dati non validi (telefono, impronte) → rifiutati', $c$
  select t.vale((select esito from public.registrazione_avvia('A', 'B', 'abc', t.h('ip-di-prova-00000000'), t.h('1'))) = 'dati_non_validi'
    and (select esito from public.registrazione_avvia('A', 'B', '3334444444', t.h('ip-di-prova-00000000'), '123456')) = 'dati_non_validi'
    and (select esito from public.registrazione_avvia(repeat('x', 81), 'B', '3334444444', t.h('ip-di-prova-00000000'), t.h('1'))) = 'dati_non_validi')$c$);

-- ---------- Limiti di frequenza (uguali per tesserati e non) ----------
call t.caso('limiti: una seconda richiesta entro 60 secondi → troppe richieste', $c$
  select t.avvia('Giovanni', 'Bianchi', '3334444444');
  select t.vale(esito = 'troppe_richieste' and richiesta is null) from t.avvia('Giovanni', 'Bianchi', '3334444444')$c$);
call t.caso('limiti: al massimo 3 codici all''ora per numero', $c$
  insert into registrazione.richieste (telefono, ip_hash, creata_il) select '3334444444', 'x', now() - interval '10 minutes' from generate_series(1, 3);
  select t.vale(esito = 'troppe_richieste') from t.avvia('Giovanni', 'Bianchi', '3334444444')$c$);
call t.caso('limiti: al massimo 10 richieste all''ora dallo stesso indirizzo IP (anche per numeri diversi)', $c$
  insert into registrazione.richieste (telefono, ip_hash, creata_il) select '33300000' || g, t.h('ip-di-prova-00000000'), now() - interval '5 minutes' from generate_series(10, 19) g;
  select t.vale(esito = 'troppe_richieste') from t.avvia('Giovanni', 'Bianchi', '3334444444')$c$);
call t.caso('limiti: IP falsificato a ogni richiesta non aggira il limite per numero', $c$
  select t.avvia('Giovanni', 'Bianchi', '3334444444', '111111', 'ip-falso-1-000000000');
  select t.vale(esito = 'troppe_richieste') from t.avvia('Giovanni', 'Bianchi', '3334444444', '111111', 'ip-falso-2-000000000')$c$);
call t.caso('limiti: al massimo 60 richieste all''ora in totale (anche con IP e numeri sempre diversi)', $c$
  insert into registrazione.richieste (telefono, ip_hash, creata_il) select '3339' || lpad(g::text, 6, '0'), t.h('ip' || g), now() - interval '20 minutes' from generate_series(1, 60) g;
  select t.vale(esito = 'troppe_richieste') from t.avvia('Giovanni', 'Bianchi', '3334444444', '111111', 'ip-mai-visto-0000000')$c$);
call t.caso('limiti: anche un numero non tesserato riceve lo stesso "troppe richieste"', $c$
  select t.avvia('Mario', 'Neri', '3330009999');
  select t.vale(esito = 'troppe_richieste') from t.avvia('Mario', 'Neri', '3330009999')$c$);

-- ---------- Verifica del codice ----------
call t.caso('verifica: codice errato → errato, restano 4 tentativi', $c$
  select t.vale(v.esito = 'errato' and v.token is null and v.tentativi_rimasti = 4, v.esito)
  from t.avvia('Giovanni', 'Bianchi', '3334444444', '111111') a, public.registrazione_verifica(a.richiesta, t.h('222222')) v$c$);
call t.caso('verifica: dopo 5 errori bloccata, anche con il codice giusto', $c$
  create temp table r1 on commit drop as select richiesta from t.avvia('Giovanni', 'Bianchi', '3334444444', '111111');
  select public.registrazione_verifica((select richiesta from r1), t.h('00000' || g)) from generate_series(1, 5) g;
  select t.vale(v.esito = 'bloccato' and v.token is null, v.esito) from public.registrazione_verifica((select richiesta from r1), t.h('111111')) v$c$);
call t.caso('verifica: codice rifiutato dopo la scadenza', $c$
  create temp table r1 on commit drop as select richiesta from t.avvia('Giovanni', 'Bianchi', '3334444444', '111111');
  update registrazione.richieste set otp_scade_il = now() - interval '1 second' where id = (select richiesta from r1);
  select t.vale(v.esito = 'scaduto' and v.token is null) from public.registrazione_verifica((select richiesta from r1), t.h('111111')) v$c$);
call t.caso('verifica: codice giusto → gettone monouso; il gettone non è salvato in chiaro', $c$
  create temp table r1 on commit drop as select richiesta from t.avvia('Giovanni', 'Bianchi', '3334444444', '111111');
  create temp table v1 on commit drop as select * from public.registrazione_verifica((select richiesta from r1), t.h('111111'));
  select t.vale((select esito from v1) = 'ok' and (select token from v1) ~ '^[0-9a-f]{64}$'
    and (select token_hash from registrazione.richieste where id = (select richiesta from r1)) = t.h((select token from v1))
    and (select otp_hash from registrazione.richieste where id = (select richiesta from r1)) is null)$c$);
call t.caso('verifica: lo stesso codice non si può riusare', $c$
  create temp table r1 on commit drop as select richiesta from t.avvia('Giovanni', 'Bianchi', '3334444444', '111111');
  select public.registrazione_verifica((select richiesta from r1), t.h('111111'));
  select t.vale(v.esito = 'non_valido' and v.token is null) from public.registrazione_verifica((select richiesta from r1), t.h('111111')) v$c$);
call t.caso('verifica: per un numero non tesserato ogni codice è "errato" (come per un codice sbagliato)', $c$
  select t.vale(v.esito = 'errato' and v.tentativi_rimasti = 4)
  from t.avvia('Mario', 'Neri', '3330009999', '111111') a, public.registrazione_verifica(a.richiesta, t.h('111111')) v$c$);
call t.caso('verifica: una nuova richiesta annulla il codice precedente', $c$
  create temp table r1 on commit drop as select richiesta from t.avvia('Giovanni', 'Bianchi', '3334444444', '111111');
  update registrazione.richieste set creata_il = now() - interval '2 minutes' where id = (select richiesta from r1);
  select t.avvia('Giovanni', 'Bianchi', '3334444444', '333333');
  select t.vale(v.esito = 'errato') from public.registrazione_verifica((select richiesta from r1), t.h('111111')) v$c$);
call t.caso('verifica: richiesta inesistente → non valida', $c$
  select t.vale(esito = 'non_valido') from public.registrazione_verifica(gen_random_uuid(), t.h('111111'))$c$);

-- ---------- Completamento: prenotazione → (eliminazione account in attesa) → account NUOVO → conferma ----------
-- Ogni funzione che modifica si chiama in un comando e i suoi effetti si controllano nel comando
-- SUCCESSIVO (update esito_caso ...): dentro uno stesso comando le sotto-interrogazioni non vedono
-- le modifiche fatte dalle funzioni chiamate.
create procedure t.verificato(tel text, nome text, cognome text) language plpgsql as $$   -- percorso vero: avvio + verifica
declare r uuid; tok text;
begin
  select richiesta into r from t.avvia(nome, cognome, tel, '777777');
  select token into tok from public.registrazione_verifica(r, t.h('777777'));
  perform set_config('t.r', r::text, true); perform set_config('t.g', tok, true);
end $$;
create procedure t.verificata(tel text) language plpgsql as $$   -- richiesta già verificata, senza i limiti dell'avvio
declare r uuid; tok text := encode(extensions.gen_random_bytes(32), 'hex');
begin
  insert into registrazione.richieste (tipo, telefono, tesserato_id, verificata_il, token_hash, token_scade_il, ip_hash)
  select 'otp', tel, x.id, now(), t.h(tok), now() + interval '15 minutes', 'prova'
    from public.tesserati x where public.solo_cifre_tel(x.telefono) = tel limit 1 returning id into r;
  perform set_config('t.r', r::text, true); perform set_config('t.g', tok, true); perform set_config('t.p', '', true);
end $$;
create function t.prenota(gettone text default null) returns text language plpgsql as $$   -- prenotazione in t.p
declare e text; p text;
begin
  select x.esito, x.prenotazione into e, p
    from public.registrazione_prenota(current_setting('t.r')::uuid, t.h(coalesce(gettone, current_setting('t.g')))) x;
  perform set_config('t.p', coalesce(p, ''), true); return e;
end $$;
create function t.elimina(u uuid) returns text language sql as $$
  select public.registrazione_elimina_attesa(current_setting('t.r')::uuid, current_setting('t.p'), u) $$;
create function t.conferma(u uuid) returns text language sql as $$
  select public.registrazione_conferma(current_setting('t.r')::uuid, current_setting('t.p'), u) $$;
create function t.account(u uuid, tel text, creato timestamptz default now()) returns void language sql as $$
  insert into auth.users (id, email, created_at) values (u, tel || '@soci.ausergratteri.app', creato) $$;
-- Account "in attesa" SENZA dati, dedicato al caso (i dati di prova possono dare dati a …0004)
create procedure t.attesa(u uuid, tel text) language plpgsql as $$
begin
  insert into public.tesserati (nome, telefono, email) values ('Prova Attesa ' || right(tel, 4), tel, '');
  insert into auth.users (id, email, created_at) values (u, tel || '@soci.ausergratteri.app', now() - interval '1 minute');
end $$;

-- Prenotazione
call t.caso('prenota: gettone vero (da verifica) → ok, telefono e nome dall''anagrafica; gettone consumato, prenotazione solo come impronta', $c$
  call t.verificato('3334444444', 'Giovanni', 'Bianchi');
  select t.vale(t.prenota() = 'ok');
  update esito_caso set ok = ok and current_setting('t.p') ~ '^[0-9a-f]{64}$'
    and (select token_hash is null and prenotazione_hash = t.h(current_setting('t.p')) and prenotata_il is not null
         from registrazione.richieste where id = current_setting('t.r')::uuid)
    and not exists (select 1 from registrazione.richieste r where r::text like '%' || current_setting('t.p') || '%')$c$);
call t.caso('prenota: restituisce telefono e nome, nessun account in attesa', $c$
  call t.verificato('3334444444', 'Giovanni', 'Bianchi');
  select t.vale(esito = 'ok' and telefono = '3334444444' and nome = 'Giovanni Bianchi' and account_in_attesa is null)
  from public.registrazione_prenota(current_setting('t.r')::uuid, t.h(current_setting('t.g')))$c$);
call t.caso('prenota: una seconda volta con lo stesso gettone → non valido', $c$
  call t.verificata('3334444444');
  select t.prenota();
  select t.vale(t.prenota() = 'non_valido')$c$);
call t.caso('prenota: gettone sbagliato o malformato → non valido, il gettone vero resta utilizzabile', $c$
  call t.verificata('3334444444');
  select t.vale(t.prenota(repeat('0', 64)) = 'non_valido');
  update esito_caso set ok = ok and (select esito from public.registrazione_prenota(current_setting('t.r')::uuid, 'non-esadecimale')) = 'non_valido';
  update esito_caso set ok = ok and t.prenota() = 'ok'$c$);
call t.caso('prenota: gettone scaduto o richiesta non verificata → non valido', $c$
  call t.verificata('3334444444');
  update registrazione.richieste set token_scade_il = now() - interval '1 second' where id = current_setting('t.r')::uuid;
  select t.vale(t.prenota() = 'non_valido');
  create temp table r1 on commit drop as select richiesta from t.avvia('Giovanni', 'Bianchi', '3334444444', '111111');
  update esito_caso set ok = ok and (select esito from public.registrazione_prenota((select richiesta from r1), t.h('qualsiasi'))) = 'non_valido'$c$);
call t.caso('prenota: numero di un socio già registrato → gia_registrato', $c$
  call t.verificata('3331111111');
  select t.vale(t.prenota() = 'gia_registrato')$c$);
call t.caso('prenota: account in attesa con adesione, riga foto o file → serve_direttivo (nulla viene toccato)', $c$
  call t.attesa('00000000-0000-0000-0000-0000000004a1', '3336661001');
  insert into public.adesioni (attivita_id, user_id, nome) values ((select id from public.attivita limit 1), '00000000-0000-0000-0000-0000000004a1', 'Prova');
  call t.verificata('3336661001'); select t.vale(t.prenota() = 'serve_direttivo');
  delete from public.adesioni where user_id = '00000000-0000-0000-0000-0000000004a1';
  insert into public.foto (attivita_id, user_id, url) values ((select id from public.attivita limit 1), '00000000-0000-0000-0000-0000000004a1', 'x');
  call t.verificata('3336661001'); update esito_caso set ok = ok and t.prenota() = 'serve_direttivo';
  delete from public.foto where user_id = '00000000-0000-0000-0000-0000000004a1';
  insert into storage.objects (bucket_id, name) values ('foto-private', '00000000-0000-0000-0000-0000000004a1/a.png');
  call t.verificata('3336661001'); update esito_caso set ok = ok and t.prenota() = 'serve_direttivo';
  delete from storage.objects where name = '00000000-0000-0000-0000-0000000004a1/a.png';
  insert into storage.objects (bucket_id, name, owner_id) values ('altro', 'b.png', '00000000-0000-0000-0000-0000000004a1');
  call t.verificata('3336661001'); update esito_caso set ok = ok and t.prenota() = 'serve_direttivo';
  update esito_caso set ok = ok and exists (select 1 from auth.users where id = '00000000-0000-0000-0000-0000000004a1')$c$);

-- Eliminazione dell'account in attesa
call t.caso('elimina: account in attesa senza dati → eliminato con le sue sessioni', $c$
  call t.attesa('00000000-0000-0000-0000-0000000004a2', '3336661002');
  insert into auth.sessions (user_id) values ('00000000-0000-0000-0000-0000000004a2');
  call t.verificata('3336661002');
  select t.vale(t.prenota() = 'ok');
  update esito_caso set ok = ok and t.elimina('00000000-0000-0000-0000-0000000004a2') = 'ok';
  update esito_caso set ok = ok
    and not exists (select 1 from auth.users where id = '00000000-0000-0000-0000-0000000004a2')
    and not exists (select 1 from public.profili where id = '00000000-0000-0000-0000-0000000004a2')
    and not exists (select 1 from auth.sessions where user_id = '00000000-0000-0000-0000-0000000004a2')$c$);
call t.caso('elimina: mai un socio, direttivo, presidente o un account di un altro numero', $c$
  call t.attesa('00000000-0000-0000-0000-0000000004a3', '3336661003');
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000482', '3338887777@soci.ausergratteri.app');
  call t.verificata('3336661003');
  select t.vale(t.prenota() = 'ok');
  update esito_caso set ok = ok and t.elimina('00000000-0000-0000-0000-000000000003') = 'non_valido';
  update esito_caso set ok = ok and t.elimina('00000000-0000-0000-0000-000000000002') = 'non_valido';
  update esito_caso set ok = ok and t.elimina('00000000-0000-0000-0000-000000000001') = 'non_valido';
  update esito_caso set ok = ok and t.elimina('00000000-0000-0000-0000-000000000482') = 'non_valido';
  update esito_caso set ok = ok and (select count(*) from auth.users where id in ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002',
         '00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000482')) = 4$c$);
call t.caso('elimina: prenotazione sbagliata o scaduta → non valido, account intatto', $c$
  call t.attesa('00000000-0000-0000-0000-0000000004a4', '3336661004');
  call t.verificata('3336661004');
  select t.vale(t.prenota() = 'ok');
  update esito_caso set ok = ok and public.registrazione_elimina_attesa(current_setting('t.r')::uuid, repeat('0', 64), '00000000-0000-0000-0000-0000000004a4') = 'non_valido';
  update registrazione.richieste set prenotata_il = now() - interval '3 minutes' where id = current_setting('t.r')::uuid;
  update esito_caso set ok = ok and t.elimina('00000000-0000-0000-0000-0000000004a4') = 'non_valido';
  update esito_caso set ok = ok and exists (select 1 from auth.users where id = '00000000-0000-0000-0000-0000000004a4')$c$);
call t.caso('elimina: dati comparsi dopo la prenotazione → serve_direttivo, account e dati intatti', $c$
  call t.attesa('00000000-0000-0000-0000-0000000004a5', '3336661005');
  call t.verificata('3336661005');
  select t.vale(t.prenota() = 'ok');
  insert into public.adesioni (attivita_id, user_id, nome) values ((select id from public.attivita limit 1), '00000000-0000-0000-0000-0000000004a5', 'Prova');
  update esito_caso set ok = ok and t.elimina('00000000-0000-0000-0000-0000000004a5') = 'serve_direttivo';
  update esito_caso set ok = ok
    and exists (select 1 from auth.users where id = '00000000-0000-0000-0000-0000000004a5')
    and exists (select 1 from public.adesioni where user_id = '00000000-0000-0000-0000-0000000004a5')$c$);

-- Conferma
call t.caso('conferma: account NUOVO creato dopo la prenotazione → socio, nome dell''anagrafica; richiesta usata', $c$
  call t.verificato('3334444444', 'Giovanni', 'Bianchi');
  select t.vale(t.prenota() = 'ok');
  select t.account('00000000-0000-0000-0000-000000000471', '3334444444');
  update esito_caso set ok = ok and t.conferma('00000000-0000-0000-0000-000000000471') = 'ok';
  update esito_caso set ok = ok
    and (select ruolo = 'socio' and nome = 'Giovanni Bianchi' from public.profili where id = '00000000-0000-0000-0000-000000000471')
    and (select usata_il is not null and prenotazione_hash is null and token_hash is null from registrazione.richieste where id = current_setting('t.r')::uuid)$c$);
call t.caso('conferma: una seconda volta → non valido', $c$
  call t.verificata('3334444444'); select t.prenota();
  select t.account('00000000-0000-0000-0000-000000000471', '3334444444'); select t.conferma('00000000-0000-0000-0000-000000000471');
  update public.profili set ruolo = 'in_attesa' where id = '00000000-0000-0000-0000-000000000471';
  select t.vale(t.conferma('00000000-0000-0000-0000-000000000471') = 'non_valido')$c$);
call t.caso('conferma: account creato PRIMA della prenotazione (vecchio PIN, vecchie sessioni) → non valido, resta in attesa', $c$
  select t.account('00000000-0000-0000-0000-000000000472', '3334444444', now() - interval '1 minute');
  call t.verificata('3334444444');
  select t.vale(t.prenota() = 'ok');
  update esito_caso set ok = ok and t.conferma('00000000-0000-0000-0000-000000000472') = 'non_valido';
  update esito_caso set ok = ok and (select ruolo from public.profili where id = '00000000-0000-0000-0000-000000000472') = 'in_attesa'$c$);
call t.caso('conferma: prenotazione sbagliata o scaduta, account di un altro numero o già socio → non valido', $c$
  call t.verificata('3334444444');
  select t.vale(t.prenota() = 'ok');
  select t.account('00000000-0000-0000-0000-000000000473', '3334444444');
  select t.account('00000000-0000-0000-0000-000000000474', '3338887777');
  update esito_caso set ok = ok and public.registrazione_conferma(current_setting('t.r')::uuid, repeat('0', 64), '00000000-0000-0000-0000-000000000473') = 'non_valido';
  update esito_caso set ok = ok and t.conferma('00000000-0000-0000-0000-000000000474') = 'non_valido';
  update esito_caso set ok = ok and t.conferma('00000000-0000-0000-0000-000000000003') = 'non_valido';
  update registrazione.richieste set prenotata_il = now() - interval '3 minutes' where id = current_setting('t.r')::uuid;
  update esito_caso set ok = ok and t.conferma('00000000-0000-0000-0000-000000000473') = 'non_valido';
  update esito_caso set ok = ok and (select ruolo from public.profili where id = '00000000-0000-0000-0000-000000000473') = 'in_attesa'
    and (select ruolo from public.profili where id = '00000000-0000-0000-0000-000000000003') = 'socio'$c$);
call t.caso('percorso: account in attesa creato da altri → eliminato e sostituito da un account NUOVO socio', $c$
  call t.attesa('00000000-0000-0000-0000-0000000004a6', '3336661006');
  call t.verificata('3336661006');
  select t.vale(t.prenota() = 'ok');
  update esito_caso set ok = ok and t.elimina('00000000-0000-0000-0000-0000000004a6') = 'ok';
  select t.account('00000000-0000-0000-0000-000000000475', '3336661006');
  update esito_caso set ok = ok and t.conferma('00000000-0000-0000-0000-000000000475') = 'ok';
  update esito_caso set ok = ok
    and (select ruolo from public.profili where id = '00000000-0000-0000-0000-000000000475') = 'socio'
    and not exists (select 1 from auth.users where id = '00000000-0000-0000-0000-0000000004a6')$c$);

-- Nuovo profilo: sempre "in attesa", i metadati non contano più
call t.caso('aggirare: account con app_metadata della prova OTP → in attesa, richiesta NON consumata', $c$
  call t.verificata('3334444444');
  insert into auth.users (id, email, raw_app_meta_data) values ('00000000-0000-0000-0000-000000000476', '3334444444@soci.ausergratteri.app',
    jsonb_build_object('registrazione', current_setting('t.r'), 'registrazione_token', t.h(current_setting('t.g'))));
  select t.vale((select ruolo from public.profili where id = '00000000-0000-0000-0000-000000000476') = 'in_attesa'
    and (select token_hash is not null and usata_il is null from registrazione.richieste where id = current_setting('t.r')::uuid))$c$);
call t.caso('aggirare: registrazione diretta di un tesserato (solo user_metadata) → in attesa', $c$
  insert into auth.users (id, email, raw_user_meta_data) values ('00000000-0000-0000-0000-000000000477', '3334444444@soci.ausergratteri.app',
    '{"nome": "Giovanni", "ruolo": "socio"}');
  select t.vale(ruolo = 'in_attesa', ruolo) from public.profili where id = '00000000-0000-0000-0000-000000000477'$c$);
call t.caso('aggirare: metadati con un identificativo malformato → in attesa, nessun errore', $c$
  insert into auth.users (id, email, raw_app_meta_data) values ('00000000-0000-0000-0000-000000000481', '3334444444@soci.ausergratteri.app',
    '{"registrazione": "non-un-uuid''; drop table x;--", "registrazione_token": "x"}');
  select t.vale(ruolo = 'in_attesa') from public.profili where id = '00000000-0000-0000-0000-000000000481'$c$);

-- ---------- Registrazione manuale (resta in attesa) ----------
call t.caso('manuale: consentita, poi al massimo 3 al giorno per numero', $c$
  select t.vale(public.registrazione_manuale_consentita('3336660001', t.h('ip-di-prova-00000000')) = 'ok');
  select public.registrazione_manuale_consentita('3336660001', t.h('ip-di-prova-00000000')) from generate_series(1, 2);
  update esito_caso set ok = ok and public.registrazione_manuale_consentita('3336660001', t.h('ip-di-prova-00000000')) = 'troppe_richieste'$c$);
call t.caso('manuale: l''account creato senza OTP resta in attesa anche per un tesserato', $c$
  insert into auth.users (id, email, raw_user_meta_data) values ('00000000-0000-0000-0000-000000000483', '3335550470@soci.ausergratteri.app', '{"nome":"Anna Verdi"}');
  select t.vale(ruolo = 'in_attesa') from public.profili where id = '00000000-0000-0000-0000-000000000483'$c$);

-- ---------- Nessun segreto in chiaro ----------
call t.caso('segreti: la tabella delle richieste ha solo impronte (64 caratteri esadecimali)', $c$
  call t.verificato('3334444444', 'Giovanni', 'Bianchi');
  select t.vale(t.prenota() = 'ok');
  update esito_caso set ok = ok and not exists (select 1 from registrazione.richieste r where r::text like '%777777%' or r::text like '%' || current_setting('t.g') || '%'
    or r::text like '%' || current_setting('t.p') || '%')$c$);

\pset format unaligned
\pset tuples_only on
\pset fieldsep '|'
select case when ok then 'PASS' else 'FAIL' end, nome, dettaglio from t.esiti order by n;
\pset format aligned
\pset tuples_only off
