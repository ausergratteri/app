// =====================================================================
//  AUSER GRATTERI – Edge Function "registrazione" (ingresso Deno)
//  Collega la logica (logica.ts) a Supabase, a Gmail e ai segreti della funzione.
//  Si pubblica con:  supabase functions deploy registrazione --no-verify-jwt
//  (la chiamano anche persone non ancora registrate: niente JWT; i controlli sono nella logica)
//
//  Segreti (Supabase → Edge Functions → Secrets; MAI nel repository o nel frontend):
//    REGISTRAZIONE_PEPE      almeno 32 caratteri casuali: chiave HMAC per codici e IP
//    GMAIL_UTENTE            indirizzo Gmail dell'associazione (mittente)
//    GMAIL_PASSWORD_APP      password per le app di Google (16 caratteri), non la password dell'account
//    EMAIL_CONSENTITE        (facoltativo) elenco separato da virgole: se presente, si scrive SOLO lì
//    ORIGINE_CONSENTITA      (facoltativo) es. https://ausergratteri.github.io
//    DIAGNOSI_SMTP           (facoltativo) "1": all'avvio prova connessione e accesso al server
//                            SMTP SENZA inviare nulla, e lo scrive nel registro
//    SMTP_HOST, SMTP_PORTA, SMTP_SICURO  (facoltativi, solo per prove) predefiniti smtp.gmail.com,
//                            465, TLS. SMTP_SICURO="0" = senza TLS e senza credenziali, ammesso SOLO
//                            verso localhost/127.0.0.1/::1 o il Mailpit locale (supabase_inbucket_… o "inbucket")
//    SMTP_IP_ATTESO          (obbligatorio con SMTP_SICURO="0") IP esatto del container Mailpit sulla
//                            rete Docker di prova: il nome deve risolversi SOLO a questo indirizzo
//  Forniti da Supabase: SUPABASE_URL e la chiave di servizio: SUPABASE_SECRET_KEYS["default"]
//  (chiavi nuove), altrimenti SUPABASE_SECRET_KEY o la legacy SUPABASE_SERVICE_ROLE_KEY (vedi
//  chiaveServizio in logica.ts). Nel registro solo il NOME della fonte usata, mai il valore.
// =====================================================================
import {createClient} from "jsr:@supabase/supabase-js@2.49.4";
import nodemailer from "npm:nodemailer@6.9.16";
import {lookup} from "node:dns/promises";
import {chiaveServizio, codiceDaByte, configSmtp, gestisci, ipDaIntestazioni, verificaIpSmtp, type Dip} from "./logica.ts";

const ambiente = (k: string) => Deno.env.get(k) ?? "";
const URL_PROGETTO = ambiente("SUPABASE_URL");
const {chiave: CHIAVE, fonte: FONTE_CHIAVE} = chiaveServizio(ambiente);
console.log(JSON.stringify({funzione: "registrazione", evento: "chiave_servizio", fonte: FONTE_CHIAVE}));
const PEPE = ambiente("REGISTRAZIONE_PEPE");
const ORIGINE = ambiente("ORIGINE_CONSENTITA") || "https://ausergratteri.github.io";
const CONSENTITE = ambiente("EMAIL_CONSENTITE").split(",").map(x => x.trim().toLowerCase()).filter(Boolean);
const DOMINIO = "soci.ausergratteri.app";   // uguale a DOMINIO_FINTO in app.js e in nuovo_profilo()
const MAX_CORPO = 4096;

const admin = createClient(URL_PROGETTO, CHIAVE, {auth: {persistSession: false, autoRefreshToken: false}});
// Tempi massimi brevi: un invio bloccato non deve tenere viva la funzione fino al limite.
const SMTP = configSmtp(ambiente);
// Configurazione rifiutata: nessun trasporto, nessuna connessione; la funzione risponde 503.
const opzioniPosta = (host: string, porta: number, sicuro: boolean) => ({
  host, port: porta, secure: sicuro,
  ...(sicuro ? {auth: {user: ambiente("GMAIL_UTENTE"), pass: ambiente("GMAIL_PASSWORD_APP")}} : {}),
  connectionTimeout: 10_000, greetingTimeout: 10_000, socketTimeout: 20_000
});
// Con TLS (produzione): trasporto creato subito, come prima; Nodemailer risolve e verifica il certificato.
const postaTls = SMTP.ok && SMTP.sicuro ? nodemailer.createTransport(opzioniPosta(SMTP.host, SMTP.porta, true)) : null;
// Senza TLS (solo prove): il nome si risolve con il resolver di sistema (come getent nel container) e
// TUTTI gli indirizzi devono essere l'IP atteso del Mailpit; la connessione va a quell'IP. Altrimenti
// errore, nessuna connessione. Esito tenuto in memoria; in caso di errore si riprova alla richiesta dopo.
type Trasporto = ReturnType<typeof nodemailer.createTransport>;
let postaLocale: Promise<Trasporto> | null = null;
function trasporto(): Promise<Trasporto | null> {
  if (!SMTP.ok) return Promise.resolve(null);
  if (SMTP.sicuro) return Promise.resolve(postaTls);
  const {host, porta, ipAtteso} = SMTP;
  postaLocale ??= lookup(host, {all: true, family: ipAtteso.includes(":") ? 6 : 4}).then(r => {
    if (!verificaIpSmtp(r.map(x => x.address), ipAtteso)) throw new Error("smtp_ip_non_atteso");
    return nodemailer.createTransport(opzioniPosta(ipAtteso, porta, false));
  }).catch(e => { postaLocale = null; throw e; });
  return postaLocale;
}
if (!SMTP.ok) console.log(JSON.stringify({funzione: "registrazione", evento: "configurazione_smtp_rifiutata", errore: SMTP.errore}));

const enc = new TextEncoder();
const esa = (b: ArrayBuffer) => [...new Uint8Array(b)].map(x => x.toString(16).padStart(2, "0")).join("");
const chiaveHmac = PEPE.length >= 32
  ? crypto.subtle.importKey("raw", enc.encode(PEPE), {name: "HMAC", hash: "SHA-256"}, false, ["sign"])
  : null;

const dip: Dip = {
  async rpc(funzione, argomenti) {
    const {data, error} = await admin.rpc(funzione, argomenti);
    if (error) throw new Error(`rpc ${funzione}: ${error.code ?? ""}`);   // senza argomenti né dettagli
    return Array.isArray(data) ? data : [{[funzione]: data}];
  },
  async creaUtente(u) {
    const {data, error} = await admin.auth.admin.createUser({...u, email_confirm: true});
    return error ? {errore: error.code || "errore"} : {id: data.user?.id};
  },
  async inviaEmail(m) {
    const t = await trasporto();
    if (!t) throw new Error("smtp_non_configurato");
    await t.sendMail({
      from: {name: "AUSER Gratteri", address: ambiente("GMAIL_UTENTE")},
      to: m.a, subject: m.oggetto, text: m.testo, html: m.html
    });
  },
  async hmac(t) { return esa(await crypto.subtle.sign("HMAC", await chiaveHmac!, enc.encode(t))); },
  async sha256(t) { return esa(await crypto.subtle.digest("SHA-256", enc.encode(t))); },
  codice: () => codiceDaByte(() => crypto.getRandomValues(new Uint32Array(1))[0]),
  dopo(p) {
    // deno-lint-ignore no-explicit-any
    const rt = (globalThis as any).EdgeRuntime;
    if (rt?.waitUntil) rt.waitUntil(p); else p.catch(() => {});
  },
  log(evento, dati) { console.log(JSON.stringify({funzione: "registrazione", evento, ...(dati || {})})); },
  emailConsentite: CONSENTITE.length ? CONSENTITE : null,
  dominio: DOMINIO
};

// Diagnosi facoltativa: connessione e accesso al server SMTP, nessun messaggio inviato
if (SMTP.ok && ambiente("DIAGNOSI_SMTP") === "1") {
  trasporto().then(t => t!.verify()).then(
    () => dip.log("smtp_verifica_ok", {sicuro: SMTP.ok && SMTP.sicuro}),
    (e: Error & {code?: string; responseCode?: number}) =>
      dip.log("smtp_verifica_fallita", {codice: String(e?.code || e?.responseCode || "").slice(0, 40), messaggio: String(e?.message || e).slice(0, 160)}));
}

const intestazioni = (origine: string | null) => ({
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  ...(origine === ORIGINE ? {
    "Access-Control-Allow-Origin": ORIGINE, "Vary": "Origin",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type, apikey, authorization, x-client-info"
  } : {})
});

Deno.serve(async req => {
  const origine = req.headers.get("origin");
  if (req.method === "OPTIONS") return new Response(null, {status: 204, headers: intestazioni(origine)});
  const h = intestazioni(origine);
  if (req.method !== "POST") return new Response('{"esito":"metodo_non_consentito"}', {status: 405, headers: h});
  if (!SMTP.ok || !URL_PROGETTO || !CHIAVE || !chiaveHmac || !ambiente("GMAIL_UTENTE") || !ambiente("GMAIL_PASSWORD_APP")) {
    dip.log("configurazione_incompleta");
    return new Response('{"esito":"non_disponibile"}', {status: 503, headers: h});
  }
  const testo = await req.text();
  if (testo.length > MAX_CORPO) return new Response('{"esito":"dati_non_validi"}', {status: 413, headers: h});
  let corpo: unknown = null;
  try { corpo = JSON.parse(testo); } catch { /* corpo non valido */ }
  const {ip, fonte} = ipDaIntestazioni(n => req.headers.get(n));
  if (fonte !== "cf-connecting-ip") dip.log("ip_da", {fonte});   // per controllare il proxy alla prima prova
  const r = await gestisci(corpo, ip, dip);
  return new Response(JSON.stringify(r.corpo), {status: r.stato, headers: h});
});
