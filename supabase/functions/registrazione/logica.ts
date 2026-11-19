// =====================================================================
//  AUSER GRATTERI – funzione server "registrazione" (logica)
//  Nessuna dipendenza da Deno o da Supabase: tutto ciò che tocca il mondo esterno
//  (database, creazione account, e-mail, crittografia) arriva da "Dip". Così la stessa
//  logica gira nella Edge Function (index.ts) e nei test locali (test/*.mjs).
//
//  Azioni (POST JSON {azione, ...}):
//   avvia     {nome, cognome, telefono}          → codice all'e-mail dell'ANAGRAFICA, se c'è
//   verifica  {richiesta, codice}                → gettone monouso per scegliere il PIN
//   completa  {richiesta, gettone, pin}          → account socio (o ripresa di un account in attesa)
//   manuale   {nome, cognome, telefono, pin}     → account "in attesa" per il direttivo
//
//  Regole di sicurezza:
//   * il destinatario dell'e-mail arriva SOLO dal database (anagrafica), mai dal client;
//   * le risposte di "avvia" e "manuale" sono identiche per tesserati e non (anti-enumerazione)
//     e l'e-mail parte dopo la risposta (stessi tempi);
//   * il codice, il gettone e il PIN non vengono mai scritti nei registri;
//   * al database arrivano solo impronte: HMAC del codice e dell'IP (con un segreto che
//     resta nella funzione) e SHA-256 del gettone.
// =====================================================================

export const MESSAGGIO_AVVIO =
  "Se i dati corrispondono a un socio con un indirizzo e-mail registrato presso l'associazione, " +
  "riceverai un codice di 6 cifre. Il codice vale 10 minuti.";
export const MESSAGGIO_MANUALE =
  "Richiesta ricevuta. Il direttivo controllerà i tuoi dati e confermerà la registrazione.";

export type Riga = Record<string, unknown>;
export type Dip = {
  rpc: (funzione: string, argomenti: Record<string, unknown>) => Promise<Riga[]>;
  creaUtente: (u: {email: string; password: string; app_metadata?: Riga; user_metadata?: Riga}) => Promise<{id?: string; errore?: string}>;
  aggiornaPin: (id: string, pin: string) => Promise<{errore?: string}>;
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
    `Il codice vale 10 minuti e si può usare una sola volta.\n` +
    `Se non hai chiesto tu di registrarti, ignora questo messaggio: senza il codice nessuno può usare i tuoi dati.\n\n` +
    `AUSER Gratteri`;
  const html =
    `<p>Gentile ${n || "socio"},</p><p>il tuo codice per completare la registrazione all'app dell'AUSER Gratteri è:</p>` +
    `<p style="font-size:28px;font-weight:bold;letter-spacing:6px">${codice}</p>` +
    `<p>Il codice vale 10 minuti e si può usare una sola volta.</p>` +
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
  const [g] = await d.rpc("registrazione_gettone", {p_richiesta: richiesta, p_token: gettone});
  if (!g || g.esito === "non_valido") { d.log("completa", {esito: "non_valido"}); return risposta(400, {esito: "non_valido"}); }
  if (g.esito === "gia_registrato") { d.log("completa", {esito: "gia_registrato"}); return risposta(409, {esito: "gia_registrato"}); }
  if (g.esito !== "ok" || typeof g.telefono !== "string" || !/^\d{6,15}$/.test(g.telefono)) return risposta(400, {esito: "non_valido"});

  if (typeof g.account_in_attesa === "string" && UUID.test(g.account_in_attesa)) {
    // Account "in attesa" con lo stesso numero: prima il NUOVO PIN, poi la promozione.
    // Se la promozione fallisce, l'account resta in attesa ma con il PIN di chi ha verificato.
    const p = await d.aggiornaPin(g.account_in_attesa, c.pin);
    if (p.errore) { d.log("completa", {esito: "pin_non_aggiornato"}); return risposta(500, {esito: "errore"}); }
    const [r] = await d.rpc("registrazione_riprendi", {p_richiesta: richiesta, p_token: gettone, p_utente: g.account_in_attesa});
    const esito = String(Object.values(r || {})[0] || "non_valido");
    d.log("completa", {esito: esito === "ok" ? "ripreso" : "non_valido"});
    return esito === "ok" ? risposta(200, {esito: "ok"}) : risposta(400, {esito: "non_valido"});
  }

  const u = await d.creaUtente({
    email: `${soloCifre(g.telefono)}@${d.dominio}`,     // dal database (come lo calcola l'app all'accesso), non dal client
    password: c.pin,
    app_metadata: {registrazione: richiesta, registrazione_token: await d.sha256(gettone)},
    user_metadata: {nome: String(g.nome || "").slice(0, 80)}
  });
  if (u.errore || !u.id) { d.log("completa", {esito: "non_completabile"}); return risposta(409, {esito: "non_completabile"}); }
  d.log("completa", {esito: "creato"});
  return risposta(200, {esito: "ok"});
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
