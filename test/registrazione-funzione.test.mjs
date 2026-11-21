// Test della funzione server "registrazione" (supabase/functions/registrazione/logica.ts)
// con database, e-mail e account SIMULATI: nessuna rete, nessun invio reale.
import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import {gestisci, chiaveServizio, codiceDaByte, configSmtp, indirizzoLocale, verificaIpSmtp, messaggioEmail, ipDaIntestazioni, MESSAGGIO_AVVIO, MESSAGGIO_MANUALE} from "../supabase/functions/registrazione/logica.ts";
import fs from "node:fs";

const RICHIESTA = "11111111-2222-4333-8444-555555555555";
const GETTONE = "a".repeat(64);
const PEPE = "pepe-di-prova-solo-per-i-test-0123456789";
const hmac = t => crypto.createHmac("sha256", PEPE).update(t).digest("hex");
const sha = t => crypto.createHash("sha256").update(t).digest("hex");

// Dipendenze finte: registrano tutto; "risposte" decide cosa restituisce il database
function finte({risposte = {}, consentite = null, codice = "482913", creaErrore = null, pinErrore = null} = {}) {
  const st = {rpc: [], creati: [], pin: [], email: [], log: [], dopo: [], ordine: []};
  const d = {
    async rpc(f, a) { st.rpc.push({f, a}); st.ordine.push("rpc:" + f); const r = risposte[f]; return typeof r === "function" ? r(a) : (r || []); },
    async creaUtente(u) { st.creati.push(u); st.ordine.push("crea"); return creaErrore ? {errore: creaErrore} : {id: "99999999-2222-4333-8444-555555555555"}; },
    async aggiornaPin(id, pin) { st.pin.push({id, pin}); st.ordine.push("pin"); return pinErrore ? {errore: pinErrore} : {}; },
    async inviaEmail(m) { st.email.push(m); },
    hmac: async t => hmac(t),
    sha256: async t => sha(t),
    codice: () => codice,
    dopo: p => { st.dopo.push(p); },
    log: (evento, dati) => st.log.push(JSON.stringify({evento, ...(dati || {})})),
    emailConsentite: consentite,
    dominio: "soci.ausergratteri.app"
  };
  return {d, st};
}
const avviaRisposta = (invia, email = "giovanni@esempio.it") => ({registrazione_avvia: [{richiesta: RICHIESTA, esito: "ok", invia, email: invia ? email : null, nome: invia ? "Bianchi Giovanni" : null}]});
const DATI = {azione: "avvia", nome: "Giovanni", cognome: "Bianchi", telefono: "333 444 4444"};
const segreti = (st, ...valori) => st.log.join("\n").match(new RegExp(valori.map(v => v.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|"), "g"));

// ---------- avvia ----------
test("avvia: al database arrivano solo impronte HMAC (codice e IP), mai il codice", async () => {
  const {d, st} = finte({risposte: avviaRisposta(true)});
  await gestisci(DATI, "203.0.113.7", d);
  const a = st.rpc[0].a;
  assert.equal(a.p_otp_hash, hmac("otp:482913"));
  assert.equal(a.p_ip_hash, hmac("ip:203.0.113.7"));
  assert.ok(!JSON.stringify(st.rpc).includes("482913") && !JSON.stringify(st.rpc).includes("203.0.113.7"));
});

test("avvia: l'e-mail va all'indirizzo dell'ANAGRAFICA, anche se il client ne manda un altro", async () => {
  const {d, st} = finte({risposte: avviaRisposta(true)});
  const r = await gestisci({...DATI, email: "attaccante@esempio.com", a: "attaccante@esempio.com"}, "1.2.3.4", d);
  await Promise.all(st.dopo);
  assert.equal(r.stato, 200);
  assert.equal(st.email.length, 1);
  assert.equal(st.email[0].a, "giovanni@esempio.it");
  assert.match(st.email[0].testo, /482913/);
  assert.match(st.email[0].testo, /15 minuti/);
});

test("avvia: risposta IDENTICA per tesserato riconosciuto e non (anti-enumerazione)", async () => {
  const si = finte({risposte: avviaRisposta(true)}), no = finte({risposte: avviaRisposta(false)});
  const r1 = await gestisci(DATI, "1.2.3.4", si.d), r2 = await gestisci(DATI, "1.2.3.4", no.d);
  assert.deepEqual(r1, r2);
  assert.deepEqual(r1.corpo, {esito: "ok", richiesta: RICHIESTA, messaggio: MESSAGGIO_AVVIO});
  assert.equal(no.st.email.length, 0);
  // Il log non dice se il numero era di un tesserato
  assert.deepEqual(si.st.log.filter(x => !x.includes("invio")), no.st.log);
});

test("avvia: l'invio parte DOPO la risposta (stessi tempi per tesserati e non)", async () => {
  let sblocca; const lento = new Promise(r => { sblocca = r; });
  const {d, st} = finte({risposte: avviaRisposta(true)});
  d.inviaEmail = async m => { st.email.push(m); await lento; };
  const r = await gestisci(DATI, "1.2.3.4", d);
  assert.equal(r.stato, 200, "risposta senza aspettare l'invio");
  assert.equal(st.dopo.length, 1);
  sblocca(); await Promise.all(st.dopo);
});

test("avvia: in modalità di prova si scrive SOLO agli indirizzi consentiti", async () => {
  const fuori = finte({risposte: avviaRisposta(true, "socio@esempio.it"), consentite: ["mia.email@esempio.it"]});
  const r = await gestisci(DATI, "1.2.3.4", fuori.d);
  assert.equal(fuori.st.email.length, 0);
  assert.equal(r.stato, 200);
  assert.ok(fuori.st.log.some(x => x.includes("invio_non_consentito")));
  const dentro = finte({risposte: avviaRisposta(true, "Mia.Email@esempio.it"), consentite: ["mia.email@esempio.it"]});
  await gestisci(DATI, "1.2.3.4", dentro.d); await Promise.all(dentro.st.dopo);
  assert.equal(dentro.st.email.length, 1);
});

test("avvia: troppe richieste → 429 uguale per tutti, nessun invio", async () => {
  const {d, st} = finte({risposte: {registrazione_avvia: [{richiesta: null, esito: "troppe_richieste", invia: false}]}});
  const r = await gestisci(DATI, "1.2.3.4", d);
  assert.deepEqual(r, {stato: 429, corpo: {esito: "troppe_richieste"}});
  assert.equal(st.email.length, 0);
});

test("avvia: dati mancanti o troppo lunghi → 400 senza toccare il database", async () => {
  for (const c of [{...DATI, nome: ""}, {...DATI, cognome: undefined}, {...DATI, telefono: "12"}, {...DATI, nome: "x".repeat(81)}, {...DATI, telefono: 3334444444}]) {
    const {d, st} = finte();
    assert.equal((await gestisci(c, "1.2.3.4", d)).stato, 400);
    assert.equal(st.rpc.length, 0);
  }
});

test("avvia: invio fallito → registrato senza dettagli personali", async () => {
  const {d, st} = finte({risposte: avviaRisposta(true)});
  d.inviaEmail = async () => { throw new Error("SMTP 535 autenticazione rifiutata"); };
  await gestisci(DATI, "1.2.3.4", d); await Promise.all(st.dopo);
  assert.ok(st.log.some(x => x.includes("invio_fallito")));
  assert.equal(segreti(st, "482913", "giovanni@esempio.it", "3334444444", "333 444 4444", "1.2.3.4"), null);
});

// ---------- verifica ----------
const verifica = r => ({registrazione_verifica: [r]});
test("verifica: codice giusto → gettone; al database arriva solo l'HMAC del codice", async () => {
  const {d, st} = finte({risposte: verifica({esito: "ok", token: GETTONE, tentativi_rimasti: 4})});
  const r = await gestisci({azione: "verifica", richiesta: RICHIESTA, codice: "482913"}, "1.2.3.4", d);
  assert.deepEqual(r, {stato: 200, corpo: {esito: "ok", gettone: GETTONE}});
  assert.equal(st.rpc[0].a.p_otp_hash, hmac("otp:482913"));
  assert.equal(segreti(st, "482913", GETTONE), null);
});
test("verifica: errato, scaduto, bloccato, riutilizzato → esiti distinti senza gettone", async () => {
  const casi = [
    [{esito: "errato", tentativi_rimasti: 3}, 400, {esito: "errato", tentativi_rimasti: 3}],
    [{esito: "scaduto"}, 410, {esito: "scaduto"}],
    [{esito: "bloccato"}, 429, {esito: "bloccato"}],
    [{esito: "non_valido"}, 400, {esito: "non_valido"}]];
  for (const [db, stato, corpo] of casi) {
    const {d} = finte({risposte: verifica(db)});
    assert.deepEqual(await gestisci({azione: "verifica", richiesta: RICHIESTA, codice: "000000"}, "1.2.3.4", d), {stato, corpo});
  }
});
test("verifica: codice non di 6 cifre o richiesta non valida → 400 senza consumare tentativi", async () => {
  for (const c of [{codice: "12345"}, {codice: "1234567"}, {codice: "abcdef"}, {codice: 482913}, {richiesta: "x' or 1=1 --"}]) {
    const {d, st} = finte();
    assert.equal((await gestisci({azione: "verifica", richiesta: RICHIESTA, codice: "482913", ...c}, "1.2.3.4", d)).stato, 400);
    assert.equal(st.rpc.length, 0);
  }
});

// ---------- completa: prenotazione atomica → (eliminazione account in attesa) → account NUOVO → conferma ----------
const PREN = "c".repeat(64);
const NUOVO = "99999999-2222-4333-8444-555555555555";
const ATTESA = "77777777-2222-4333-8444-555555555555";
const prenotaOk = (extra = {}) => ({registrazione_prenota: [{esito: "ok", prenotazione: PREN, telefono: "3334444444", nome: "Bianchi Giovanni", account_in_attesa: null, ...extra}]});
const confermaOk = {registrazione_conferma: [{registrazione_conferma: "ok"}]};
const COMPLETA = {azione: "completa", richiesta: RICHIESTA, gettone: GETTONE, pin: "135790"};
const nessunSegreto = st => {
  assert.equal(segreti(st, "135790", GETTONE, PREN, "3334444444"), null, "nessun PIN, gettone, prenotazione o telefono nei registri");
  const args = JSON.stringify(st.rpc);
  assert.ok(!args.includes(GETTONE) && !args.includes("135790"), "al database né il gettone in chiaro né il PIN");
};

test("completa: nuovo account → prenota (solo impronta), crea senza app_metadata, conferma quell'account", async () => {
  const {d, st} = finte({risposte: {...prenotaOk(), ...confermaOk}});
  const r = await gestisci({...COMPLETA, telefono: "3330000000", email: "x@y.it"}, "1.2.3.4", d);
  assert.deepEqual(r, {stato: 200, corpo: {esito: "ok"}});
  assert.deepEqual(st.ordine, ["rpc:registrazione_prenota", "crea", "rpc:registrazione_conferma"]);
  assert.deepEqual(st.rpc[0].a, {p_richiesta: RICHIESTA, p_token_hash: sha(GETTONE)});
  const u = st.creati[0];
  assert.equal(u.email, "3334444444@soci.ausergratteri.app", "indirizzo dal telefono del DATABASE");
  assert.equal(u.password, "135790");
  assert.equal(u.app_metadata, undefined);
  assert.deepEqual(st.rpc[1].a, {p_richiesta: RICHIESTA, p_prenotazione: PREN, p_utente: NUOVO});
  assert.equal(st.pin.length, 0);
  nessunSegreto(st);
});
test("completa: account in attesa → eliminato dal database e sostituito; il suo PIN non si cambia mai", async () => {
  const {d, st} = finte({risposte: {...prenotaOk({account_in_attesa: ATTESA}), registrazione_elimina_attesa: [{registrazione_elimina_attesa: "ok"}], ...confermaOk}});
  assert.deepEqual(await gestisci(COMPLETA, "1.2.3.4", d), {stato: 200, corpo: {esito: "ok"}});
  assert.deepEqual(st.ordine, ["rpc:registrazione_prenota", "rpc:registrazione_elimina_attesa", "crea", "rpc:registrazione_conferma"]);
  assert.deepEqual(st.rpc[1].a, {p_richiesta: RICHIESTA, p_prenotazione: PREN, p_utente: ATTESA});
  assert.equal(st.rpc[2].a.p_utente, NUOVO, "si conferma l'account NUOVO, non quello in attesa");
  assert.equal(st.pin.length, 0);
  nessunSegreto(st);
});
test("completa: PIN non valido → 400 senza toccare database o account", async () => {
  for (const pin of ["12345", "1234567890123", "abcdef", "", 135790]) {
    const {d, st} = finte({risposte: prenotaOk()});
    assert.deepEqual(await gestisci({...COMPLETA, pin}, "1.2.3.4", d), {stato: 400, corpo: {esito: "pin_non_valido"}});
    assert.equal(st.rpc.length + st.creati.length + st.pin.length, 0);
  }
});
test("completa: prenotazione rifiutata (scaduto, riusato, errato, già socio, ex socio con dati) → nessun altro passo", async () => {
  for (const [esito, stato, corpo] of [["non_valido", 400, "non_valido"], ["gia_registrato", 409, "gia_registrato"], ["serve_direttivo", 409, "non_completabile"], ["strano", 400, "non_valido"]]) {
    const {d, st} = finte({risposte: {registrazione_prenota: [{esito}]}});
    assert.deepEqual(await gestisci(COMPLETA, "1.2.3.4", d), {stato, corpo: {esito: corpo}}, esito);
    assert.deepEqual(st.ordine, ["rpc:registrazione_prenota"], esito);
    assert.equal(st.creati.length + st.pin.length, 0);
  }
  const vuoto = finte({risposte: {}});
  assert.equal((await gestisci(COMPLETA, "1.2.3.4", vuoto.d)).stato, 400);
});
test("completa: prenotazione 'ok' ma malformata → 400, nessun account", async () => {
  for (const extra of [{prenotazione: "corta"}, {prenotazione: null}, {telefono: "abc"}, {telefono: null}]) {
    const {d, st} = finte({risposte: prenotaOk(extra)});
    assert.equal((await gestisci(COMPLETA, "1.2.3.4", d)).stato, 400, JSON.stringify(extra));
    assert.equal(st.creati.length, 0);
  }
});
test("completa: eliminazione dell'account in attesa rifiutata o con dati → 409, nessun account nuovo", async () => {
  for (const [esito, log] of [["non_valido", "attesa_non_eliminato"], ["serve_direttivo", "serve_direttivo"], [undefined, "attesa_non_eliminato"]]) {
    const {d, st} = finte({risposte: {...prenotaOk({account_in_attesa: ATTESA}), registrazione_elimina_attesa: esito ? [{registrazione_elimina_attesa: esito}] : []}});
    assert.deepEqual(await gestisci(COMPLETA, "1.2.3.4", d), {stato: 409, corpo: {esito: "non_completabile"}});
    assert.equal(st.creati.length + st.pin.length, 0);
    assert.ok(!st.ordine.includes("rpc:registrazione_conferma"));
    assert.ok(st.log.some(l => l.includes(log)), log);
  }
});
test("completa: creazione dell'account fallita → 409, nessuna conferma", async () => {
  const {d, st} = finte({risposte: prenotaOk(), creaErrore: "email_exists"});
  assert.deepEqual(await gestisci(COMPLETA, "1.2.3.4", d), {stato: 409, corpo: {esito: "non_completabile"}});
  assert.ok(!st.ordine.includes("rpc:registrazione_conferma"));
});
test("completa: conferma rifiutata → 400 (l'account resta in attesa, senza privilegi)", async () => {
  for (const r of [[{registrazione_conferma: "non_valido"}], [], [{}]]) {
    const {d, st} = finte({risposte: {...prenotaOk(), registrazione_conferma: r}});
    assert.deepEqual(await gestisci(COMPLETA, "1.2.3.4", d), {stato: 400, corpo: {esito: "non_valido"}});
    assert.ok(st.log.some(l => l.includes("creato_in_attesa")));
  }
});
test("completa: errore del database a ogni passo → 500 e nessun passo successivo", async () => {
  const guasto = () => { throw new Error("rpc: XX000"); };
  const casi = [
    [{registrazione_prenota: guasto}, ["rpc:registrazione_prenota"]],
    [{...prenotaOk({account_in_attesa: ATTESA}), registrazione_elimina_attesa: guasto}, ["rpc:registrazione_prenota", "rpc:registrazione_elimina_attesa"]],
    [{...prenotaOk(), registrazione_conferma: guasto}, ["rpc:registrazione_prenota", "crea", "rpc:registrazione_conferma"]]];
  for (const [risposte, ordine] of casi) {
    const {d, st} = finte({risposte});
    assert.equal((await gestisci(COMPLETA, "1.2.3.4", d)).stato, 500);
    assert.deepEqual(st.ordine, ordine);
    assert.equal(st.pin.length, 0);
    nessunSegreto(st);
  }
});
test("completa: la migrazione e lo schema usano prenotazione/eliminazione/conferma atomiche, solo per service_role", () => {
  for (const nome of ["../supabase/migrations/20261123_registrazione_otp.sql", "../supabase/schema.sql"]) {
    const sql = fs.readFileSync(new URL(nome, import.meta.url), "utf8");
    const corpo = f => { const i = sql.indexOf(`function ${f}(`); assert.ok(i >= 0, f + " in " + nome); return sql.slice(i, sql.indexOf("end $$;", i)); };
    for (const f of ["public.registrazione_prenota", "public.registrazione_elimina_attesa", "public.registrazione_conferma"]) {
      assert.match(corpo(f), /from registrazione\.richieste where id = p_richiesta and tipo = 'otp' for update;/, f);
      assert.ok(sql.includes(`'${f}(`), f + " nell'elenco dei permessi solo service_role");
    }
    assert.match(corpo("public.registrazione_prenota"), /set token_hash = null where id = r\.id;   -- consumato da qui/);
    assert.match(corpo("public.registrazione_elimina_attesa"), /p\.ruolo = 'in_attesa'[\s\S]*for update;[\s\S]*ha_dati\(p_utente\)[\s\S]*delete from auth\.users where id = p_utente;/);
    assert.match(corpo("public.registrazione_conferma"), /creato < r\.prenotata_il/);
    const hd = sql.slice(sql.indexOf("function registrazione.ha_dati("), sql.indexOf("$$;", sql.indexOf("function registrazione.ha_dati(")));
    for (const t of ["public.adesioni", "public.foto", "public.importazioni", "storage.objects", "storage.foldername"]) assert.ok(hd.includes(t), t);
    assert.match(sql, /revoke execute on function registrazione\.ha_dati\(uuid\) from public, anon, authenticated;/);
    const np = corpo("public.nuovo_profilo");
    assert.ok(!/raw_app_meta_data|consuma\(|'socio'/.test(np) && /, tel, 'in_attesa'\);/.test(np), "nuovo_profilo: sempre in attesa");
    assert.ok(!/create or replace function (public\.registrazione_gettone|public\.registrazione_riprendi|registrazione\.consuma)\b/.test(sql), "funzioni vecchie assenti");
  }
});

// ---------- manuale ----------
const MANUALE = {azione: "manuale", nome: "Anna", cognome: "Verdi", telefono: "+39 333 555 0470", pin: "246802"};
test("manuale: account senza app_metadata (resta in attesa), risposta uguale anche se il numero esiste già", async () => {
  const ok = finte({risposte: {registrazione_manuale_consentita: [{x: "ok"}]}});
  const esiste = finte({risposte: {registrazione_manuale_consentita: [{x: "ok"}]}, creaErrore: "email_exists"});
  const r1 = await gestisci(MANUALE, "1.2.3.4", ok.d), r2 = await gestisci(MANUALE, "1.2.3.4", esiste.d);
  assert.deepEqual(r1, r2);
  assert.deepEqual(r1.corpo, {esito: "ricevuta", messaggio: MESSAGGIO_MANUALE});
  assert.equal(ok.st.creati[0].email, "3335550470@soci.ausergratteri.app");
  assert.equal(ok.st.creati[0].app_metadata, undefined, "nessuna prova OTP: il database lo crea in attesa");
  assert.equal(segreti(ok.st, "246802", "3335550470"), null);
});
test("manuale: troppe richieste → 429; PIN non valido → 400", async () => {
  const {d} = finte({risposte: {registrazione_manuale_consentita: [{x: "troppe_richieste"}]}});
  assert.equal((await gestisci(MANUALE, "1.2.3.4", d)).stato, 429);
  const p = finte();
  assert.equal((await gestisci({...MANUALE, pin: "123"}, "1.2.3.4", p.d)).stato, 400);
  assert.equal(p.st.rpc.length, 0);
});

// ---------- generale ----------
test("azione sconosciuta o corpo non valido → 400", async () => {
  for (const c of [null, "testo", 5, {}, {azione: "elimina"}, {azione: "__proto__"}]) {
    const {d} = finte();
    assert.equal((await gestisci(c, "1.2.3.4", d)).stato, 400);
  }
});
test("errore del database → 500 generico, senza dettagli nella risposta", async () => {
  const {d, st} = finte({risposte: {registrazione_avvia: () => { throw new Error("rpc registrazione_avvia: 42501"); }}});
  const r = await gestisci(DATI, "1.2.3.4", d);
  assert.deepEqual(r, {stato: 500, corpo: {esito: "errore"}});
  assert.ok(st.log.some(x => x.includes("42501")));
});
test("codice OTP: sempre 6 cifre, senza distorsioni dai valori alti", () => {
  const visti = new Set();
  for (let i = 0; i < 2000; i++) { const c = codiceDaByte(() => crypto.randomBytes(4).readUInt32BE()); assert.match(c, /^\d{6}$/); visti.add(c); }
  assert.ok(visti.size > 1990, "codici quasi tutti diversi");
  const seq = [4294967295, 4294000000, 7]; let i = 0;
  assert.equal(codiceDaByte(() => seq[i++]), "000007", "i valori oltre il limite vengono scartati");
});
test("messaggio e-mail: nome dell'anagrafica senza HTML, codice e scadenza presenti", () => {
  const m = messaggioEmail("<script>x</script>Rossi", "123456");
  assert.ok(!m.html.includes("<script>"));
  assert.match(m.testo, /123456/); assert.match(m.html, /123456/); assert.match(m.testo, /15 minuti/);
});

// ---------- IP del client ----------
const intest = o => n => o[n] ?? null;
test("IP: si preferisce l'intestazione impostata dal proxy (cf-connecting-ip) a x-forwarded-for", () => {
  assert.deepEqual(ipDaIntestazioni(intest({"cf-connecting-ip": "203.0.113.9", "x-forwarded-for": "1.1.1.1, 203.0.113.9"})), {ip: "203.0.113.9", fonte: "cf-connecting-ip"});
  assert.deepEqual(ipDaIntestazioni(intest({"x-real-ip": "198.51.100.4", "x-forwarded-for": "1.1.1.1"})), {ip: "198.51.100.4", fonte: "x-real-ip"});
  assert.deepEqual(ipDaIntestazioni(intest({"x-forwarded-for": "2001:db8::1, 10.0.0.1"})), {ip: "2001:db8::1", fonte: "x-forwarded-for"});
});
test("IP: valori non validi o iniettati non vengono usati", () => {
  assert.deepEqual(ipDaIntestazioni(intest({"cf-connecting-ip": "1.2.3.4'; drop table x;--", "x-forwarded-for": "<script>"})), {ip: "sconosciuto", fonte: "nessuna"});
  assert.deepEqual(ipDaIntestazioni(intest({})), {ip: "sconosciuto", fonte: "nessuna"});
  assert.equal(ipDaIntestazioni(intest({"x-real-ip": "x".repeat(100)})).fonte, "nessuna");
});
test("IP falsificato a ogni richiesta: il limite per numero resta (deciso dal database, non dall'IP)", async () => {
  // Il database conta per numero di telefono: qui la seconda richiesta, con un IP diverso, è comunque respinta
  let n = 0;
  const {d} = finte({risposte: {registrazione_avvia: () => [n++ === 0 ? {richiesta: RICHIESTA, esito: "ok", invia: false} : {richiesta: null, esito: "troppe_richieste", invia: false}]}});
  assert.equal((await gestisci(DATI, "1.1.1.1", d)).stato, 200);
  assert.equal((await gestisci(DATI, "9.9.9.9", d)).stato, 429);
});

// ---------------------------------------------------------------------------
// Configurazione SMTP: TLS predefinito; in chiaro (SMTP_SICURO="0") solo verso host locali o il
// Mailpit dello stack Supabase locale, e mai con credenziali.
const amb = o => k => o[k] ?? "";

test("SMTP: senza impostazioni resta Gmail, 465, TLS con credenziali (produzione invariata)", () => {
  assert.deepEqual(configSmtp(amb({})), {ok: true, host: "smtp.gmail.com", porta: 465, sicuro: true, conAccesso: true});
});

test("SMTP: con TLS SMTP_IP_ATTESO è ignorato e il risultato resta identico", () => {
  assert.deepEqual(configSmtp(amb({SMTP_IP_ATTESO: "172.18.0.5"})),
    {ok: true, host: "smtp.gmail.com", porta: 465, sicuro: true, conAccesso: true});
  const c = configSmtp(amb({SMTP_HOST: "smtp.gmail.com", SMTP_PORTA: "465", SMTP_SICURO: "1", SMTP_IP_ATTESO: "8.8.8.8"}));
  assert.deepEqual(c, {ok: true, host: "smtp.gmail.com", porta: 465, sicuro: true, conAccesso: true});
  assert.ok(!("ipAtteso" in c));
});

test("SMTP: in chiaro ammesso verso localhost, 127.0.0.1, ::1 con IP atteso locale, senza credenziali", () => {
  for (const [h, ip] of [["localhost", "127.0.0.1"], ["127.0.0.1", "127.0.0.1"], ["::1", "::1"], ["LOCALHOST", "127.0.0.1"], [" localhost ", " 127.0.0.1 "]]) {
    const c = configSmtp(amb({SMTP_HOST: h, SMTP_PORTA: "1025", SMTP_SICURO: "0", SMTP_IP_ATTESO: ip}));
    assert.equal(c.ok, true, h);
    assert.equal(c.sicuro, false, h);
    assert.equal(c.conAccesso, false, h);
    assert.equal(c.porta, 1025, h);
    assert.equal(c.ipAtteso, ip.trim(), h);
  }
});

test("SMTP: in chiaro ammesso verso il Mailpit dello stack Supabase locale con il suo IP esatto", () => {
  for (const h of ["supabase_inbucket_auser-otp-prova-locale", "supabase_mailpit_auser_otp"]) {
    assert.deepEqual(configSmtp(amb({SMTP_HOST: h, SMTP_PORTA: "1025", SMTP_SICURO: "0", SMTP_IP_ATTESO: "172.18.0.7"})),
      {ok: true, host: h, porta: 1025, sicuro: false, conAccesso: false, ipAtteso: "172.18.0.7"});
  }
});

test("SMTP: in chiaro senza IP atteso valido e locale la configurazione fallisce", () => {
  const h = "supabase_inbucket_auser-otp-prova-locale";
  for (const ip of [undefined, "", " ", "abc", "172.18.0", "172.18.0.256", "8.8.8.8", "0.0.0.0", "172.32.0.1",
    "172.15.255.1", "192.169.0.1", "11.0.0.1", "::", "::ffff:127.0.0.1", "fe80::1", "172.18.0.7,172.18.0.8", "localhost", h]) {
    const c = configSmtp(amb({SMTP_HOST: h, SMTP_PORTA: "1025", SMTP_SICURO: "0", ...(ip === undefined ? {} : {SMTP_IP_ATTESO: ip})}));
    assert.deepEqual(c, {ok: false, errore: "smtp_ip_atteso_non_valido"}, JSON.stringify(ip));
  }
});

test("SMTP: host non ammesso fallisce anche con IP atteso valido", () => {
  const c = configSmtp(amb({SMTP_HOST: "mail.esempio.it", SMTP_PORTA: "25", SMTP_SICURO: "0", SMTP_IP_ATTESO: "172.18.0.7"}));
  assert.deepEqual(c, {ok: false, errore: "smtp_in_chiaro_non_consentito"});
});

test("SMTP: alias esatto \"inbucket\" ammesso solo con IP atteso valido", () => {
  assert.deepEqual(configSmtp(amb({SMTP_HOST: "inbucket", SMTP_PORTA: "1025", SMTP_SICURO: "0", SMTP_IP_ATTESO: "172.18.0.7"})),
    {ok: true, host: "inbucket", porta: 1025, sicuro: false, conAccesso: false, ipAtteso: "172.18.0.7"});
  assert.equal(configSmtp(amb({SMTP_HOST: " INBUCKET ", SMTP_SICURO: "0", SMTP_IP_ATTESO: "172.18.0.7"})).ok, true);
  for (const ip of ["", "8.8.8.8", "0.0.0.0"])
    assert.deepEqual(configSmtp(amb({SMTP_HOST: "inbucket", SMTP_SICURO: "0", SMTP_IP_ATTESO: ip})),
      {ok: false, errore: "smtp_ip_atteso_non_valido"}, ip);
  for (const h of ["inbucket.esempio.com", "inbucket1", "x-inbucket", "inbucket.", "inbucket:1025", "in bucket"])
    assert.deepEqual(configSmtp(amb({SMTP_HOST: h, SMTP_SICURO: "0", SMTP_IP_ATTESO: "172.18.0.7"})),
      {ok: false, errore: "smtp_in_chiaro_non_consentito"}, h);
});

test("SMTP: indirizzoLocale accetta solo loopback e reti private IPv4", () => {
  for (const ip of ["127.0.0.1", "127.1.2.3", "::1", "10.0.0.1", "10.255.255.255", "172.16.0.1", "172.31.255.254", "192.168.0.1"])
    assert.equal(indirizzoLocale(ip), true, ip);
  for (const ip of ["", "8.8.8.8", "0.0.0.0", "172.15.0.1", "172.32.0.1", "192.167.1.1", "169.254.1.1", "127.0.0.256",
    "10.0.0", "10.0.0.1.5", " 10.0.0.1", "::", "fe80::1", "::ffff:10.0.0.1", "localhost", "010.0.0.1x"])
    assert.equal(indirizzoLocale(ip), false, JSON.stringify(ip));
});

test("SMTP: verificaIpSmtp vuole almeno un indirizzo e tutti uguali a quello atteso", () => {
  assert.equal(verificaIpSmtp(["172.18.0.7"], "172.18.0.7"), true);
  assert.equal(verificaIpSmtp(["172.18.0.7", "172.18.0.7"], "172.18.0.7"), true);
  assert.equal(verificaIpSmtp([], "172.18.0.7"), false);
  assert.equal(verificaIpSmtp(["172.18.0.8"], "172.18.0.7"), false);
  assert.equal(verificaIpSmtp(["172.18.0.7", "93.184.216.34"], "172.18.0.7"), false);
  assert.equal(verificaIpSmtp(["93.184.216.34", "172.18.0.7"], "172.18.0.7"), false);
  assert.equal(verificaIpSmtp(["172.18.0.70"], "172.18.0.7"), false);
});

test("SMTP: in chiaro verso qualsiasi altro host la configurazione fallisce", () => {
  const rifiutati = ["", "smtp.gmail.com", "mail.esempio.it", "localhost.esempio.com", "127.0.0.1.nip.io",
    "supabase_inbucket_x.esempio.com", "supabase_inbucket_", "10.0.0.5", "192.168.1.10",
    "host.docker.internal", "127.0.0.2", "mailpit", "[::1]", "localhost:1025"];
  for (const h of rifiutati) {
    const c = configSmtp(amb({SMTP_HOST: h, SMTP_PORTA: "25", SMTP_SICURO: "0", SMTP_IP_ATTESO: "172.18.0.7"}));
    assert.deepEqual(c, {ok: false, errore: "smtp_in_chiaro_non_consentito"}, JSON.stringify(h));
    assert.ok(!JSON.stringify(c).includes("25") && !("host" in c), "l'esito rifiutato non contiene host né porta");
  }
});

test("SMTP: solo \"0\" esatto toglie il TLS; altri valori lo mantengono", () => {
  for (const v of ["", "false", "no", " 0x", "00", "1"]) {
    const c = configSmtp(amb({SMTP_HOST: "mail.esempio.it", SMTP_SICURO: v}));
    assert.equal(c.ok, true, JSON.stringify(v));
    assert.equal(c.sicuro, true, JSON.stringify(v));
    assert.equal(c.conAccesso, true, JSON.stringify(v));
  }
});

test("SMTP: porta non valida torna a 465", () => {
  for (const p of ["abc", "0", "70000", "1.5", "-1", ""]) {
    assert.equal(configSmtp(amb({SMTP_PORTA: p})).porta, 465, JSON.stringify(p));
  }
  assert.equal(configSmtp(amb({SMTP_PORTA: "587"})).porta, 587);
});

test("SMTP: index.ts crea il trasporto solo con configurazione valida, verifica l'IP senza TLS e risponde 503 altrimenti", () => {
  const src = fs.readFileSync(new URL("../supabase/functions/registrazione/index.ts", import.meta.url), "utf8");
  assert.match(src, /const SMTP = configSmtp\(ambiente\);/);
  assert.match(src, /const postaTls = SMTP\.ok && SMTP\.sicuro \? nodemailer\.createTransport\(opzioniPosta\(SMTP\.host, SMTP\.porta, true\)\) : null;/,
    "con TLS: trasporto verso l'host configurato, come prima");
  assert.equal((src.match(/createTransport\(/g) || []).length, 2, "solo il trasporto TLS e quello locale verificato");
  assert.match(src, /\.\.\.\(sicuro \? \{auth:/, "credenziali solo con TLS");
  assert.match(src, /if \(!SMTP\.ok\) return Promise\.resolve\(null\);/);
  assert.match(src, /lookup\(host, \{all: true, family:/, "senza TLS il nome viene risolto prima");
  assert.match(src, /if \(!verificaIpSmtp\(r\.map\(x => x\.address\), ipAtteso\)\) throw new Error\("smtp_ip_non_atteso"\);/);
  assert.match(src, /nodemailer\.createTransport\(opzioniPosta\(ipAtteso, porta, false\)\)/, "connessione all'IP verificato, non al nome");
  assert.match(src, /if \(SMTP\.ok && ambiente\("DIAGNOSI_SMTP"\) === "1"\)/);
  assert.match(src, /if \(!SMTP\.ok \|\| !URL_PROGETTO/);
  assert.match(src, /const t = await trasporto\(\);\s*if \(!t\) throw new Error\("smtp_non_configurato"\);/);
  assert.ok(!/host:\s*"smtp\.gmail\.com"/.test(src), "nessun host scritto direttamente nel trasporto");
  assert.ok(!/log\([^)]*ipAtteso/.test(src) && !/log\([^)]*address/.test(src), "nessun IP nei registri");
});

// ---------- Chiave di servizio fornita da Supabase alla funzione ----------
const SEGRETA = "sb_secret_" + "A1b2C3d4E5f6G7h8I9j0kL";
const LEGACY = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.firmaFintaDiProva_123";
const PUBBLICA = "sb_publishable_" + "A1b2C3d4E5f6G7h8I9j0kL";
const ambienteChiavi = o => k => o[k] ?? "";
test("chiave: si usa SUPABASE_SECRET_KEYS['default'] anche se c'è la legacy", () => {
  assert.deepEqual(chiaveServizio(ambienteChiavi({SUPABASE_SECRET_KEYS: JSON.stringify({default: SEGRETA, altra: "sb_secret_zzzzzzzzzzzzzzzzzzzz"}), SUPABASE_SERVICE_ROLE_KEY: LEGACY})),
    {chiave: SEGRETA, fonte: "secret_keys_default"});
  assert.equal(chiaveServizio(ambienteChiavi({SUPABASE_SECRET_KEYS: "  " + JSON.stringify({default: " " + SEGRETA + " "}) + "\n"})).chiave, SEGRETA, "spazi tolti");
});
test("chiave: dizionario mancante o malformato → si passa alla legacy (mai un'eccezione)", () => {
  for (const v of ["", "non-json", "{", "null", "[]", JSON.stringify([SEGRETA]), JSON.stringify({}), JSON.stringify({default: 123}),
    JSON.stringify({default: ""}), JSON.stringify({default: PUBBLICA}), JSON.stringify({default: "sb_secret_corta"}),
    JSON.stringify({default: "sb_secret_" + "x".repeat(300)}), JSON.stringify({Default: SEGRETA}), JSON.stringify({default: SEGRETA + " altro"})]) {
    assert.deepEqual(chiaveServizio(ambienteChiavi({SUPABASE_SECRET_KEYS: v, SUPABASE_SERVICE_ROLE_KEY: LEGACY})),
      {chiave: LEGACY, fonte: "service_role_legacy"}, JSON.stringify(v));
  }
});
test("chiave: SUPABASE_SECRET_KEY singola se valida, prima della legacy", () => {
  assert.deepEqual(chiaveServizio(ambienteChiavi({SUPABASE_SECRET_KEY: SEGRETA, SUPABASE_SERVICE_ROLE_KEY: LEGACY})), {chiave: SEGRETA, fonte: "secret_key"});
  assert.deepEqual(chiaveServizio(ambienteChiavi({SUPABASE_SECRET_KEY: PUBBLICA, SUPABASE_SERVICE_ROLE_KEY: LEGACY})), {chiave: LEGACY, fonte: "service_role_legacy"});
});
test("chiave: nessuna fonte valida → chiave vuota (la funzione risponde 503)", () => {
  for (const o of [{}, {SUPABASE_SERVICE_ROLE_KEY: "non-jwt"}, {SUPABASE_SERVICE_ROLE_KEY: PUBBLICA}, {SUPABASE_SECRET_KEYS: "{}", SUPABASE_SECRET_KEY: "x"},
    {SUPABASE_SECRET_KEYS: JSON.stringify({default: PUBBLICA})}, {SUPABASE_SERVICE_ROLE_KEY: "eyJ.solo-due"}]) {
    assert.deepEqual(chiaveServizio(ambienteChiavi(o)), {chiave: "", fonte: "assente"}, JSON.stringify(o));
  }
});
test("chiave: index.ts usa chiaveServizio, registra solo la fonte e risponde 503 senza chiave", () => {
  const src = fs.readFileSync(new URL("../supabase/functions/registrazione/index.ts", import.meta.url), "utf8");
  assert.match(src, /const \{chiave: CHIAVE, fonte: FONTE_CHIAVE\} = chiaveServizio\(ambiente\);/);
  assert.match(src, /evento: "chiave_servizio", fonte: FONTE_CHIAVE\}/);
  assert.ok(!/ambiente\("SUPABASE_(SECRET_KEY|SERVICE_ROLE_KEY|SECRET_KEYS)"\)/.test(src), "nessuna lettura diretta delle chiavi in index.ts");
  const righeLog = src.split("\n").filter(r => /\blog\(/.test(r));
  assert.ok(righeLog.length > 0 && righeLog.every(r => !/(^|[^_A-Za-z])CHIAVE\b/.test(r) && !/\bambiente\("SUPABASE_/.test(r)), "la chiave non finisce nei registri");
  assert.match(src, /if \(!SMTP\.ok \|\| !URL_PROGETTO \|\| !CHIAVE \|\|/);
});
