-- =====================================================================
--  AUSER GRATTERI – pianificazione della manutenzione Brevo (Supabase Cron). MODIFICA LA PRODUZIONE.
--  Prerequisiti: funzione manutenzione-brevo, estensioni pg_cron e pg_net,
--  token "auser_brevo_cron_token" in Vault e lo stesso valore nel segreto BREVO_CRON_TOKEN.
--  Nessun segreto in questo file: il token si legge dal Vault al momento dell'esecuzione.
--  Gli orari di Supabase Cron sono UTC. Comandi identici a quelli attivi in produzione dal 22/11/2026.
--  A ogni rinnovo della chiave Brevo: aggiornare la scadenza e riprogrammare il promemoria.
-- =====================================================================
begin;

select cron.schedule('auser-brevo-controllo-mensile', '0 8 1 * *', $job$select net.http_post(url:='https://dylztksgeqnktoapsbim.supabase.co/functions/v1/manutenzione-brevo',headers:=jsonb_build_object('Content-Type','application/json','x-auser-cron',(select decrypted_secret from vault.decrypted_secrets where name='auser_brevo_cron_token')),body:='{"azione":"controllo"}'::jsonb,timeout_milliseconds:=15000)$job$);

select cron.schedule('auser-brevo-promemoria-2027', '0 8 2 11 *', $job$select net.http_post(url:='https://dylztksgeqnktoapsbim.supabase.co/functions/v1/manutenzione-brevo',headers:=jsonb_build_object('Content-Type','application/json','x-auser-cron',(select decrypted_secret from vault.decrypted_secrets where name='auser_brevo_cron_token')),body:='{"azione":"promemoria","scadenza":"2027-11-22"}'::jsonb,timeout_milliseconds:=15000) where (now() at time zone 'Europe/Rome')::date = date '2027-11-02'$job$);

commit;
