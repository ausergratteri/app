// =====================================================================
//  AUSER GRATTERI – funzione server "registrazione" (logica)
//  Nessuna dipendenza da Deno o da Supabase: tutto ciò che tocca il mondo esterno
//  (database, creazione account, e-mail, crittografia) arriva da "Dip". Così la stessa
//  logica gira nella Edge Function (index.ts) e nei test locali (test/*.mjs).
//
//  Azioni (POST JSON {azione, ...}):
//   avvia     {nome, cognome, telefono}          → codice all'e-mail dell'ANAGRAFICA, se c'è
//   verifica  {richiesta, codice}                → gettone monouso per scegliere il PIN
//   completa  {richiesta, gettone, pin}          → account socio NUOVO (sostituisce un account in attesa senza dati)
//   manuale   {nome, cognome, telefono, pin}     → account "in attesa" per il direttivo
//
//  Regole di sicurezza:
//   * il destinatario dell'e-mail arriva SOLO dal database (anagrafica), mai dal client;
//   * le risposte di "avvia" e "manuale" sono identiche per tesserati e non (anti-enumerazione)
//     e l'e-mail parte dopo la risposta (stessi tempi);
//   * il codice, il gettone e il PIN non vengono mai scritti nei registri;
//   * al database arrivano solo impronte: HMAC del codice e dell'IP (con un segreto che
//     resta nella funzione) e SHA-256 del gettone; la prenotazione resta solo nella funzione;
//   * il PIN di un account esistente non viene mai cambiato da qui.
// =====================================================================

export const MESSAGGIO_AVVIO =
  "Se i dati corrispondono a un socio con un indirizzo e-mail registrato presso l'associazione, " +
  "riceverai un codice di 6 cifre. Il codice vale 15 minuti.";
export const MESSAGGIO_MANUALE =
  "Richiesta ricevuta. Il direttivo controllerà i tuoi dati e confermerà la registrazione.";

export type Riga = Record<string, unknown>;
export type Dip = {
  rpc: (funzione: string, argomenti: Record<string, unknown>) => Promise<Riga[]>;
  creaUtente: (u: {email: string; password: string; user_metadata?: Riga}) => Promise<{id?: string; errore?: string}>;
  inviaEmail: (m: {a: string; oggetto: string; testo: string; html: string}) => Promise<void>;
  hmac: (testo: string) => Promise<string>;     // esadecimale, con il segreto della funzione
  sha256: (testo: string) => Promise<string>;   // esadecimale
  codice: () => string;                         // 6 cifre casuali (crittografiche)
  dopo: (p: Promise<unknown>) => void;          // lavoro da finire dopo la risposta
  log: (evento: string, dati?: Riga) => void;   // MAI codici, gettoni, PIN, e-mail o telefoni
  emailConsentite: string[] | null;             // se impostato, si scrive SOLO a questi indirizzi
  dominio: string;                              // es. "soci.ausergratteri.app"
};
export type Risposta = {stato: number; corpo: Riga};

// Indirizzo IP del client per il limite "richieste per IP". Le intestazioni HTTP si possono
// falsificare: si preferisce quella che il proxy davanti alla funzione IMPOSTA (Cloudflare:
// cf-connecting-ip; poi x-real-ip) a x-forwarded-for, che il client può riempire.
// Il limite per IP è solo una difesa in più: i limiti per numero (3 all'ora), quelli globali
// (60 all'ora) e i 5 tentativi per codice NON dipendono dalle intestazioni.
const IP_VALIDO = /^[0-9a-fA-F:.]{3,45}$/;
export function ipDaIntestazioni(leggi: (nome: string) => string | null): {ip: string; fonte: string} {
  for (const nome of ["cf-connecting-ip", "x-real-ip"]) {
    const v = (leggi(nome) || "").trim();
    if (IP_VALIDO.test(v)) return {ip: v, fonte: nome};
  }
  const xff = (leggi("x-forwarded-for") || "").split(",")[0].trim();
  if (IP_VALIDO.test(xff)) return {ip: xff, fonte: "x-forwarded-for"};
  return {ip: "sconosciuto", fonte: "nessuna"};
}

// Chiave di servizio che Supabase fornisce alla funzione (mai scritta nei registri). Ordine:
//  1. SUPABASE_SECRET_KEYS: dizionario JSON delle chiavi nuove, voce "default" (sb_secret_…);
//  2. SUPABASE_SECRET_KEY: chiave singola (sb_secret_… o JWT), se presente;
//  3. SUPABASE_SERVICE_ROLE_KEY: chiave legacy (JWT), in dismissione.
// Valore mancante o malformato (JSON non valido, voce assente, formato sbagliato, chiave pubblica):
// si passa alla fonte successiva. Nessuna fonte valida → chiave vuota: la funzione risponde 503 e
// non tenta nulla. Restituisce anche la fonte usata (solo il nome, per il registro).
const SECRET_NUOVA = /^sb_secret_[A-Za-z0-9_-]{16,200}$/;
const JWT = /^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;
export type FonteChiave = "secret_keys_default" | "secret_key" | "service_role_legacy" | "assente";
export function chiaveServizio(leggi: (k: string) => string): {chiave: string; fonte: FonteChiave} {
  const dizionario = (leggi("SUPABASE_SECRET_KEYS") || "").trim();
  if (dizionario) {
    try {
      const d: unknown = JSON.parse(dizionario);
      const v = d && typeof d === "object" && !Array.isArray(d) ? (d as Record<string, unknown>)["default"] : undefined;
      if (typeof v === "string" && SECRET_NUOVA.test(v.trim())) return {chiave: v.trim(), fonte: "secret_keys_default"};
    } catch { /* dizionario malformato: fonte successiva */ }
  }
  const singola = (leggi("SUPABASE_SECRET_KEY") || "").trim();
  if (SECRET_NUOVA.test(singola) || JWT.test(singola)) return {chiave: singola, fonte: "secret_key"};
  const legacy = (leggi("SUPABASE_SERVICE_ROLE_KEY") || "").trim();
  if (JWT.test(legacy)) return {chiave: legacy, fonte: "service_role_legacy"};
  return {chiave: "", fonte: "assente"};
}

// Parametri SMTP dall'ambiente. Senza impostazioni: Gmail, 465, TLS (produzione invariata).
// SMTP_SICURO="0" esatto = niente TLS e NESSUNA credenziale, ammesso SOLO verso il computer locale
// o il servizio Mailpit dello stack Supabase locale (container "supabase_inbucket_<progetto>" o
// "supabase_mailpit_<progetto>"). Confronto esatto: "localhost.esempio.com", "127.0.0.1.nip.io",
// IP di rete o nomi corti come "mailpit" NON passano, tranne il nome esatto "inbucket" (alias Docker
// del Mailpit locale: Deno non risolve i nomi con trattini bassi). In più serve SMTP_IP_ATTESO: l'IP esatto del
// container Mailpit sulla rete Docker di prova (o 127.x / ::1 per il computer locale). Il nome viene
// risolto prima di connettersi e TUTTI gli indirizzi devono coincidere con quello atteso; la
// connessione va poi a quell'IP. Altrimenti la configurazione fallisce e nessuna connessione SMTP
// in chiaro viene tentata. Con TLS SMTP_IP_ATTESO è ignorato.
const HOST_LOCALI = new Set(["localhost", "127.0.0.1", "::1"]);
const MAILPIT_DOCKER = /^supabase_(inbucket|mailpit)_[a-z0-9_-]{1,40}$/;
const MAILPIT_ALIAS = "inbucket";   // confronto esatto, nessun prefisso o suffisso
// Solo loopback o reti private IPv4 (10/8, 172.16/12, 192.168/16): un IP pubblico non è mai ammesso.
export function indirizzoLocale(ip: string): boolean {
  if (ip === "::1" || /^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(ip) && ip.split(".").every(x => Number(x) <= 255)) return true;
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(ip);
  if (!m || m.slice(1).some(x => Number(x) > 255)) return false;
  const [a, b] = [Number(m[1]), Number(m[2])];
  return a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168);
}
export type ConfigSmtp =
  | {ok: true; host: string; porta: number; sicuro: true; conAccesso: true}
  | {ok: true; host: string; porta: number; sicuro: false; conAccesso: false; ipAtteso: string}
  | {ok: false; errore: "smtp_in_chiaro_non_consentito" | "smtp_ip_atteso_non_valido"};
export function configSmtp(leggi: (k: string) => string): ConfigSmtp {
  const host = (leggi("SMTP_HOST") || "").trim().toLowerCase() || "smtp.gmail.com";
  const p = Number((leggi("SMTP_PORTA") || "").trim());
  const porta = Number.isInteger(p) && p >= 1 && p <= 65535 ? p : 465;
  if ((leggi("SMTP_SICURO") || "").trim() !== "0") return {ok: true, host, porta, sicuro: true, conAccesso: true};
  if (!HOST_LOCALI.has(host) && host !== MAILPIT_ALIAS && !MAILPIT_DOCKER.test(host)) return {ok: false, errore: "smtp_in_chiaro_non_consentito"};
  const ipAtteso = (leggi("SMTP_IP_ATTESO") || "").trim();
  if (!indirizzoLocale(ipAtteso)) return {ok: false, errore: "smtp_ip_atteso_non_valido"};
  return {ok: true, host, porta, sicuro: false, conAccesso: false, ipAtteso};
}
// Esito della risoluzione DNS: ammesso solo se c'è almeno un indirizzo e TUTTI sono quello atteso.
export function verificaIpSmtp(risolti: string[], atteso: string): boolean {
  return risolti.length > 0 && risolti.every(ip => ip === atteso);
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const testo = (v: unknown, max: number): string | null =>
  typeof v === "string" && v.trim().length > 0 && v.length <= max ? v.trim() : null;
// Uguale a soloCifre() di app.js: l'indirizzo di accesso deve essere lo stesso che l'app calcola dal telefono
const soloCifre = (t: string): string => t.replace(/\D/g, "").replace(/^0039/, "").replace(/^39(?=3\d{8,9}$)/, "");
const pinValido = (p: unknown): p is string => typeof p === "string" && /^\d{6,12}$/.test(p);
const risposta = (stato: number, corpo: Riga): Risposta => ({stato, corpo});
const NON_VALIDA = () => risposta(400, {esito: "dati_non_validi"});
const TROPPE = () => risposta(429, {esito: "troppe_richieste"});

// Codice di 6 cifre da byte casuali, senza distorsioni (rifiuta i valori oltre il multiplo).
export function codiceDaByte(prendi: () => number): string {
  const limite = 4294000000; // multiplo di 1.000.000 sotto 2^32
  for (;;) { const n = prendi() >>> 0; if (n < limite) return String(n % 1000000).padStart(6, "0"); }
}

export function messaggioEmail(nome: string, codice: string): {oggetto: string; testo: string; html: string} {
  const n = (nome || "").replace(/[<>&"']/g, "").slice(0, 80);
  const testo =
    `Gentile ${n || "socio"},\n\n` +
    `il tuo codice per completare la registrazione all'app dell'AUSER Gratteri è:\n\n    ${codice}\n\n` +
    `Il codice vale 15 minuti e si può usare una sola volta.\n` +
    `Se non hai chiesto tu di registrarti, ignora questo messaggio: senza il codice nessuno può usare i tuoi dati.\n\n` +
    `AUSER Gratteri`;
  const html =
    `<p>Gentile ${n || "socio"},</p><p>il tuo codice per completare la registrazione all'app dell'AUSER Gratteri è:</p>` +
    `<p style="font-size:28px;font-weight:bold;letter-spacing:6px">${codice}</p>` +
    `<p>Il codice vale 15 minuti e si può usare una sola volta.</p>` +
    `<p>Se non hai chiesto tu di registrarti, ignora questo messaggio: senza il codice nessuno può usare i tuoi dati.</p><p>AUSER Gratteri</p>`;
  return {oggetto: "Il tuo codice per l'app AUSER Gratteri", testo, html};
}

export async function gestisci(corpo: unknown, ip: string, d: Dip): Promise<Risposta> {
  if (!corpo || typeof corpo !== "object") return NON_VALIDA();
  const c = corpo as Riga;
  try {
    switch (c.azione) {
      case "avvia": return await avvia(c, ip, d);
      case "verifica": return await verifica(c, d);
      case "completa": return await completa(c, d);
      case "manuale": return await manuale(c, ip, d);
      default: return NON_VALIDA();
    }
  } catch (e) {
    d.log("errore", {azione: String(c.azione).slice(0, 20), messaggio: String((e as Error)?.message || e).slice(0, 200)});
    return risposta(500, {esito: "errore"});
  }
}

async function avvia(c: Riga, ip: string, d: Dip): Promise<Risposta> {
  const nome = testo(c.nome, 80), cognome = testo(c.cognome, 80), tel = testo(c.telefono, 30);
  if (!nome || !cognome || !tel || soloCifre(tel).length < 6) return NON_VALIDA();
  const codice = d.codice();
  const [r] = await d.rpc("registrazione_avvia", {
    p_nome: nome, p_cognome: cognome, p_telefono: tel,
    p_ip_hash: await d.hmac("ip:" + ip), p_otp_hash: await d.hmac("otp:" + codice)
  });
  if (!r || r.esito === "dati_non_validi") return NON_VALIDA();
  if (r.esito === "troppe_richieste") { d.log("avvio", {esito: "troppe_richieste"}); return TROPPE(); }
  if (r.invia === true && typeof r.email === "string" && r.email) {
    const destinatario = r.email.trim();
    if (d.emailConsentite && !d.emailConsentite.includes(destinatario.toLowerCase())) {
      d.log("invio_non_consentito");               // modalità di prova: nessun messaggio ad altri
    } else {
      const m = messaggioEmail(String(r.nome || ""), codice);
      d.dopo(d.inviaEmail({a: destinatario, ...m}).then(
        () => d.log("invio_riuscito"),
        e => d.log("invio_fallito", {messaggio: String((e as Error)?.message || e).slice(0, 200)})));
    }
  }
  d.log("avvio", {esito: "ok"});
  return risposta(200, {esito: "ok", richiesta: r.richiesta, messaggio: MESSAGGIO_AVVIO});
}

async function verifica(c: Riga, d: Dip): Promise<Risposta> {
  const richiesta = typeof c.richiesta === "string" && UUID.test(c.richiesta) ? c.richiesta : null;
  const codice = typeof c.codice === "string" && /^\d{6}$/.test(c.codice.trim()) ? c.codice.trim() : null;
  if (!richiesta || !codice) return NON_VALIDA();
  const [r] = await d.rpc("registrazione_verifica", {p_richiesta: richiesta, p_otp_hash: await d.hmac("otp:" + codice)});
  const esito = String(r?.esito || "non_valido");
  d.log("verifica", {esito});
  switch (esito) {
    case "ok": return risposta(200, {esito: "ok", gettone: r.token});
    case "errato": return risposta(400, {esito: "errato", tentativi_rimasti: Number(r.tentativi_rimasti) || 0});
    case "scaduto": return risposta(410, {esito: "scaduto"});
    case "bloccato": return risposta(429, {esito: "bloccato"});
    default: return risposta(400, {esito: "non_valido"});
  }
}

async function completa(c: Riga, d: Dip): Promise<Risposta> {
  const richiesta = typeof c.richiesta === "string" && UUID.test(c.richiesta) ? c.richiesta : null;
  const gettone = typeof c.gettone === "string" && /^[0-9a-f]{64}$/.test(c.gettone) ? c.gettone : null;
  if (!richiesta || !gettone) return NON_VALIDA();
  if (!pinValido(c.pin)) return risposta(400, {esito: "pin_non_valido"});
  const fine = (stato: number, esito: string, log = esito) => { d.log("completa", {esito: log}); return risposta(stato, {esito}); };
  // 1. Prenotazione atomica: il gettone si consuma qui, una volta sola (al database solo l'impronta).
  const [g] = await d.rpc("registrazione_prenota", {p_richiesta: richiesta, p_token_hash: await d.sha256(gettone)});
  if (!g || g.esito === "non_valido") return fine(400, "non_valido");
  if (g.esito === "gia_registrato") return fine(409, "gia_registrato");
  if (g.esito === "serve_direttivo") return fine(409, "non_completabile", "serve_direttivo");
  if (g.esito !== "ok" || typeof g.prenotazione !== "string" || !/^[0-9a-f]{64}$/.test(g.prenotazione)
      || typeof g.telefono !== "string" || !/^\d{6,15}$/.test(g.telefono)) return fine(400, "non_valido");
  // Da qui il gettone è consumato: ogni errore chiede un nuovo codice e non promuove nessuno.
  // 2. Un account "in attesa" con lo stesso numero NON viene ripreso (il suo PIN e le sue sessioni
  //    potrebbero essere di altri): il database lo elimina solo se è ancora in attesa e senza dati.
  if (typeof g.account_in_attesa === "string" && UUID.test(g.account_in_attesa)) {
    const [e] = await d.rpc("registrazione_elimina_attesa", {p_richiesta: richiesta, p_prenotazione: g.prenotazione, p_utente: g.account_in_attesa});
    const ee = String(Object.values(e || {})[0] || "non_valido");
    if (ee === "serve_direttivo") return fine(409, "non_completabile", "serve_direttivo");
    if (ee !== "ok") return fine(409, "non_completabile", "attesa_non_eliminato");
  }
  // 3. Account NUOVO con il PIN scelto: il database lo crea "in attesa" (nessun app_metadata).
  const u = await d.creaUtente({
    email: `${soloCifre(g.telefono)}@${d.dominio}`,     // dal database (come lo calcola l'app all'accesso), non dal client
    password: c.pin,
    user_metadata: {nome: String(g.nome || "").slice(0, 80)}
  });
  if (u.errore || !u.id) return fine(409, "non_completabile");
  // 4. Conferma atomica: promuove SOLO questo account, creato dopo la prenotazione, una volta sola.
  const [r] = await d.rpc("registrazione_conferma", {p_richiesta: richiesta, p_prenotazione: g.prenotazione, p_utente: u.id});
  return String(Object.values(r || {})[0] || "") === "ok" ? fine(200, "ok", "creato") : fine(400, "non_valido", "creato_in_attesa");
}

async function manuale(c: Riga, ip: string, d: Dip): Promise<Risposta> {
  const nome = testo(c.nome, 80), cognome = testo(c.cognome, 80), tel = testo(c.telefono, 30);
  if (!nome || !cognome || !tel) return NON_VALIDA();
  const cifre = soloCifre(tel);
  if (!/^\d{6,15}$/.test(cifre)) return NON_VALIDA();
  if (!pinValido(c.pin)) return risposta(400, {esito: "pin_non_valido"});
  const [r] = await d.rpc("registrazione_manuale_consentita", {p_telefono: tel, p_ip_hash: await d.hmac("ip:" + ip)});
  const esito = String(Object.values(r || {})[0] || "");
  if (esito === "troppe_richieste") return TROPPE();
  if (esito !== "ok") return NON_VALIDA();
  // Nessun app_metadata: il database crea l'account "in attesa". Se il numero esiste già
  // non cambia nulla, e la risposta è la stessa (non si rivela chi è registrato).
  const u = await d.creaUtente({email: `${cifre}@${d.dominio}`, password: c.pin, user_metadata: {nome: `${nome} ${cognome}`.slice(0, 80)}});
  d.log("manuale", {esito: u.errore ? "non_creato" : "creato"});
  return risposta(200, {esito: "ricevuta", messaggio: MESSAGGIO_MANUALE});
}
