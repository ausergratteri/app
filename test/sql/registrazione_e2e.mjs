// Prova completa della registrazione con OTP: la logica VERA della funzione server
// (supabase/functions/registrazione/logica.ts) collegata al database VERO (PostgreSQL
// usa e getta in Docker, senza rete), come la chiamerebbe la Edge Function con la chiave
// service role. Creazione account e invio e-mail sono simulati come l'API admin di Supabase:
// nessuna rete, nessun invio reale. Uso: node registrazione_e2e.mjs <container> <database>
import {execFileSync} from "node:child_process";
import crypto from "node:crypto";
import assert from "node:assert/strict";
import {gestisci} from "../../supabase/functions/registrazione/logica.ts";

const [CONTAINER, DB] = process.argv.slice(2);
const psql = (sql, ruolo = null) => execFileSync("docker", ["exec", "-i", "-e", "PGOPTIONS=-c client_min_messages=warning", CONTAINER,
  "psql", "-U", "postgres", "-d", DB, "-v", "ON_ERROR_STOP=1", "-q", "-X", "-At"],
  {input: (ruolo ? `set role ${ruolo};\n` : "") + sql, encoding: "utf8"}).trim();
const q = v => v === null || v === undefined ? "null" : `'${String(v).replace(/'/g, "''")}'`;
const PEPE = "pepe-e2e-0123456789-0123456789-abc";
const DOMINIO = "soci.ausergratteri.app";

function dipendenze() {
  const st = {email: [], log: [], pin: []};
  const d = {
    async rpc(f, a) {   // come supabase-js con la chiave service role: solo funzioni pubbliche
      const arg = Object.entries(a).map(([k, v]) => `${k} => ${q(v)}`).join(", ");
      const scalare = ["registrazione_elimina_attesa", "registrazione_conferma", "registrazione_manuale_consentita"].includes(f);
      const sql = scalare ? `select row_to_json(x) from (select public.${f}(${arg}) as ${f}) x;`
                          : `select row_to_json(x) from public.${f}(${arg}) x;`;
      return psql(sql, "service_role").split("\n").filter(Boolean).map(JSON.parse);
    },
    async creaUtente(u) {  // come auth.admin.createUser: e-mail unica, app_metadata solo da qui
      const id = crypto.randomUUID();
      try {
        psql(`insert into auth.users (id, email, encrypted_password, raw_user_meta_data, raw_app_meta_data) values
              (${q(id)}, ${q(u.email)}, ${q("impronta:" + crypto.createHash("sha256").update(u.password).digest("hex"))},
               ${q(JSON.stringify(u.user_metadata || {}))}::jsonb, ${q(JSON.stringify(u.app_metadata || {}))}::jsonb);`);
        return {id};
      } catch { return {errore: "email_exists"}; }
    },
    async inviaEmail(m) { st.email.push(m); },
    hmac: async t => crypto.createHmac("sha256", PEPE).update(t).digest("hex"),
    sha256: async t => crypto.createHash("sha256").update(t).digest("hex"),
    codice: () => String(crypto.randomInt(0, 1000000)).padStart(6, "0"),
    dopo: p => { st.ultimo = p; },
    log: (e, x) => st.log.push(JSON.stringify({e, ...(x || {})})),
    emailConsentite: null, dominio: DOMINIO
  };
  return {d, st};
}
const ruolo = tel => psql(`select ruolo from public.profili where telefono = ${q(tel)};`);
const codiceDa = m => m.testo.match(/\b(\d{6})\b/)[1];
let n = 0;
async function prova(nome, f) {
  try { await f(); console.log(`PASS|e2e: ${nome}`); n++; }
  catch (e) { console.log(`FAIL|e2e: ${nome}|${String(e.message).split("\n")[0].slice(0, 200)}`); }
}

// Dati: Giovanni (tesserato con e-mail, non registrato); Concetta (account "in attesa" creato da altri)
psql(`update public.tesserati set email = 'giovanni.bianchi@esempio.it' where nome = 'Giovanni Bianchi';
      insert into public.tesserati (nome, telefono, email) values ('Attesa Concetta', '3333333333', 'concetta@esempio.it');`);
// Per far girare più prove sullo stesso numero si azzerano i limiti tra una prova e l'altra
const azzeraLimiti = () => psql(`update registrazione.richieste set creata_il = creata_il - interval '2 hours';`);

await prova("percorso completo: codice all'e-mail dell'anagrafica → verifica → PIN → socio", async () => {
  const {d, st} = dipendenze();
  const a = await gestisci({azione: "avvia", nome: "Giovanni", cognome: "Bianchi", telefono: "+39 333 444 4444", email: "altro@esempio.com"}, "198.51.100.1", d);
  assert.equal(a.stato, 200); await st.ultimo;
  assert.equal(st.email.length, 1); assert.equal(st.email[0].a, "giovanni.bianchi@esempio.it");
  const v = await gestisci({azione: "verifica", richiesta: a.corpo.richiesta, codice: codiceDa(st.email[0])}, "198.51.100.1", d);
  assert.equal(v.corpo.esito, "ok");
  const c = await gestisci({azione: "completa", richiesta: a.corpo.richiesta, gettone: v.corpo.gettone, pin: "135790"}, "198.51.100.1", d);
  assert.deepEqual(c.corpo, {esito: "ok"});
  assert.equal(ruolo("3334444444"), "socio");
  assert.equal(psql(`select email from auth.users u join public.profili p on p.id = u.id where p.telefono = '3334444444';`), `3334444444@${DOMINIO}`);
  assert.equal(psql(`select nome from public.profili where telefono = '3334444444';`), "Giovanni Bianchi");
});

await prova("riuso del gettone dopo la registrazione → nessun secondo account", async () => {
  azzeraLimiti();
  const {d, st} = dipendenze();
  // Nuovo tesserato per avere un gettone valido, poi lo si usa due volte
  psql(`insert into public.tesserati (nome, telefono, email) values ('Neri Luca', '3335551111', 'luca@esempio.it');`);
  const a = await gestisci({azione: "avvia", nome: "Luca", cognome: "Neri", telefono: "3335551111"}, "198.51.100.2", d); await st.ultimo;
  const v = await gestisci({azione: "verifica", richiesta: a.corpo.richiesta, codice: codiceDa(st.email[0])}, "198.51.100.2", d);
  assert.equal((await gestisci({azione: "completa", richiesta: a.corpo.richiesta, gettone: v.corpo.gettone, pin: "111222"}, "198.51.100.2", d)).corpo.esito, "ok");
  const di_nuovo = await gestisci({azione: "completa", richiesta: a.corpo.richiesta, gettone: v.corpo.gettone, pin: "908172"}, "198.51.100.2", d);
  assert.notEqual(di_nuovo.corpo.esito, "ok");
  assert.equal(psql(`select count(*) from auth.users where email like '3335551111@%';`), "1");
  assert.equal(psql(`select encrypted_password from auth.users where email like '3335551111@%';`),
    "impronta:" + crypto.createHash("sha256").update("111222").digest("hex"), "il PIN tentato la seconda volta non sostituisce quello scelto");
});

await prova("codice sbagliato 5 volte → bloccato, anche con il codice giusto dopo", async () => {
  azzeraLimiti();
  const {d, st} = dipendenze();
  psql(`insert into public.tesserati (nome, telefono, email) values ('Gialli Rita', '3335552222', 'rita@esempio.it');`);
  const a = await gestisci({azione: "avvia", nome: "Rita", cognome: "Gialli", telefono: "3335552222"}, "198.51.100.3", d); await st.ultimo;
  const giusto = codiceDa(st.email[0]), sbagliato = giusto === "000000" ? "111111" : "000000";
  for (let i = 0; i < 5; i++) await gestisci({azione: "verifica", richiesta: a.corpo.richiesta, codice: sbagliato}, "198.51.100.3", d);
  const v = await gestisci({azione: "verifica", richiesta: a.corpo.richiesta, codice: giusto}, "198.51.100.3", d);
  assert.equal(v.corpo.esito, "bloccato");
  assert.equal(ruolo("3335552222"), "");
});

await prova("numero non tesserato: stessa risposta, nessuna e-mail, nessun codice valido", async () => {
  azzeraLimiti();
  const {d, st} = dipendenze();
  const a = await gestisci({azione: "avvia", nome: "Chiunque", cognome: "Prova", telefono: "3330001234"}, "198.51.100.4", d);
  assert.equal(a.stato, 200); assert.equal(a.corpo.messaggio.length > 0, true);
  assert.equal(st.email.length, 0);
  const v = await gestisci({azione: "verifica", richiesta: a.corpo.richiesta, codice: "123456"}, "198.51.100.4", d);
  assert.equal(v.corpo.esito, "errato");
});

await prova("aggirare: registrazione diretta con le API di Auth (solo user_metadata) → in attesa", async () => {
  psql(`insert into public.tesserati (nome, telefono, email) values ('Blu Marco', '3335553333', 'marco@esempio.it');
        insert into auth.users (id, email, raw_user_meta_data) values (gen_random_uuid(), '3335553333@${DOMINIO}',
          '{"nome": "Marco Blu", "registrazione": "x", "ruolo": "socio"}');`);
  assert.equal(ruolo("3335553333"), "in_attesa");
});

await prova("account 'in attesa' creato da altri con il numero del tesserato: dopo l'OTP viene sostituito da un account NUOVO socio", async () => {
  azzeraLimiti();
  const {d, st} = dipendenze();
  const a = await gestisci({azione: "avvia", nome: "Concetta", cognome: "Attesa", telefono: "3333333333"}, "198.51.100.5", d); await st.ultimo;
  assert.equal(st.email[0].a, "concetta@esempio.it");
  const v = await gestisci({azione: "verifica", richiesta: a.corpo.richiesta, codice: codiceDa(st.email[0])}, "198.51.100.5", d);
  const c = await gestisci({azione: "completa", richiesta: a.corpo.richiesta, gettone: v.corpo.gettone, pin: "975310"}, "198.51.100.5", d);
  assert.deepEqual(c.corpo, {esito: "ok"});
  assert.equal(psql(`select count(*) from auth.users where id = '00000000-0000-0000-0000-000000000004';`), "0", "vecchio account eliminato");
  assert.equal(ruolo("3333333333"), "socio");
  assert.equal(psql(`select u.encrypted_password from auth.users u join public.profili p on p.id = u.id where p.telefono = '3333333333';`),
    "impronta:" + crypto.createHash("sha256").update("975310").digest("hex"), "account nuovo con il PIN scelto");
});

await prova("account 'in attesa' con dati propri (ex socio): nessuna sostituzione, serve il direttivo", async () => {
  azzeraLimiti();
  const {d, st} = dipendenze();
  psql(`insert into public.tesserati (nome, telefono, email) values ('Viola Ada', '3335554444', 'ada@esempio.it');
        insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000004e1', '3335554444@${DOMINIO}');
        insert into public.adesioni (attivita_id, user_id, nome) values ((select id from public.attivita limit 1), '00000000-0000-0000-0000-0000000004e1', 'Ada');`);
  const a = await gestisci({azione: "avvia", nome: "Ada", cognome: "Viola", telefono: "3335554444"}, "198.51.100.9", d); await st.ultimo;
  const v = await gestisci({azione: "verifica", richiesta: a.corpo.richiesta, codice: codiceDa(st.email[0])}, "198.51.100.9", d);
  const c = await gestisci({azione: "completa", richiesta: a.corpo.richiesta, gettone: v.corpo.gettone, pin: "864200"}, "198.51.100.9", d);
  assert.deepEqual(c.corpo, {esito: "non_completabile"});
  assert.equal(psql(`select count(*) from auth.users where email like '3335554444@%';`), "1");
  assert.equal(psql(`select ruolo from public.profili where id = '00000000-0000-0000-0000-0000000004e1';`), "in_attesa");
  assert.equal(psql(`select count(*) from public.adesioni where user_id = '00000000-0000-0000-0000-0000000004e1';`), "1");
});

await prova("socio già registrato: nessun codice inviato (niente appropriazione dell'account)", async () => {
  azzeraLimiti();
  const {d, st} = dipendenze();
  psql(`update public.tesserati set email = 'maria@esempio.it' where nome = 'Maria Rossi';`);
  const a = await gestisci({azione: "avvia", nome: "Maria", cognome: "Rossi", telefono: "3331111111"}, "198.51.100.6", d);
  assert.equal(a.stato, 200); assert.equal(st.email.length, 0);
});

await prova("troppe richieste per lo stesso numero → 429", async () => {
  azzeraLimiti();
  const {d} = dipendenze();
  await gestisci({azione: "avvia", nome: "X", cognome: "Y", telefono: "3330005678"}, "198.51.100.7", d);
  assert.equal((await gestisci({azione: "avvia", nome: "X", cognome: "Y", telefono: "3330005678"}, "198.51.100.7", d)).stato, 429);
});

await prova("IP diverso a ogni richiesta (intestazioni falsificate): il limite per numero resta", async () => {
  azzeraLimiti();
  const {d} = dipendenze();
  await gestisci({azione: "avvia", nome: "X", cognome: "Y", telefono: "3330005679"}, "10.0.0.1", d);
  assert.equal((await gestisci({azione: "avvia", nome: "X", cognome: "Y", telefono: "3330005679"}, "10.0.0.2", d)).stato, 429);
  assert.equal((await gestisci({azione: "avvia", nome: "X", cognome: "Y", telefono: "3330005679"}, "172.16.0.9", d)).stato, 429);
});

await prova("richiesta manuale: account in attesa per il direttivo, anche per un tesserato senza e-mail", async () => {
  psql(`insert into public.tesserati (nome, telefono, email) values ('Verdi Anna', '3335550470', '');`);
  const {d} = dipendenze();
  const r = await gestisci({azione: "manuale", nome: "Anna", cognome: "Verdi", telefono: "3335550470", pin: "246802"}, "198.51.100.8", d);
  assert.equal(r.corpo.esito, "ricevuta");
  assert.equal(ruolo("3335550470"), "in_attesa");
});

await prova("nel database nessun codice, gettone, PIN o IP in chiaro", async () => {
  const dump = psql(`select coalesce(string_agg(r::text, '|'), '') from registrazione.richieste r;`);
  assert.ok(!/198\.51\.100/.test(dump), "nessun indirizzo IP");
  assert.ok(!/(135790|975310|246802|111222|908172|864200)/.test(dump), "nessun PIN");
  assert.ok(!/[^0-9a-f]\d{6}[^0-9a-f]/.test("|" + dump.replace(/\d{4}-\d{2}-\d{2}[ T][\d:.+]+/g, "") + "|"), "nessun codice di 6 cifre");
});

console.log(`(e2e: ${n} prove superate)`);
