// =====================================================================
//  AUSER GRATTERI – backup dei FILE di Storage di produzione (sola lettura su Supabase).
//  Uso (Terminale dell'amministratore, dalla cartella del repository):
//     read -s "AUSER_CHIAVE_SECRET?Chiave secret: " && export AUSER_CHIAVE_SECRET && echo
//     node supabase/operazioni/backup/backup_storage.mjs /Volumes/<immagine cifrata>/<cartella>
//     unset AUSER_CHIAVE_SECRET
//  - Progetto: SOLO quello di config.js (produzione). Destinazione: SOLO un'immagine disco cifrata montata.
//  - Elenca tutti i bucket e tutti i file (anche nelle sottocartelle), li scarica con la chiave secret,
//    li salva in <destinazione>/storage/<bucket>/<percorso> (permessi 600) e controlla per ognuno
//    dimensione e MD5 rispetto ai metadati (eTag). Scrive inventario-storage.json (percorsi, dimensioni, MD5).
//  - A schermo solo conteggi: nessun percorso, nessuna chiave. Non modifica nulla su Supabase.
//  Solo per i collaudi locali: AUSER_BASE_PROVA=http://127.0.0.1:<porta> (ammesso solo l'indirizzo locale).
// =====================================================================
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import {destinazioneCifrata} from "./destinazione_cifrata.mjs";

const stop = m => { console.log("STOP: " + m); process.exit(1); };
const radice = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../../..");
const destArg = process.argv[2] || stop("indicare la cartella di destinazione su un'immagine cifrata montata in /Volumes");
// 1. Destinazione cifrata (controllo con hdiutil)
const dest = destinazioneCifrata(destArg) || stop(`${destArg} non è su un'immagine disco cifrata montata in /Volumes`);

// 2. Progetto e chiave
const config = fs.readFileSync(path.join(radice, "config.js"), "utf8");
const urlProd = (config.match(/https:\/\/[a-z0-9]{20}\.supabase\.co/) || [])[0] || stop("URL di produzione non trovato in config.js");
const prova = process.env.AUSER_BASE_PROVA;
if (prova && !/^http:\/\/127\.0\.0\.1:\d+$/.test(prova)) stop("AUSER_BASE_PROVA ammesso solo verso 127.0.0.1");
const base = prova || urlProd;
const chiave = process.env.AUSER_CHIAVE_SECRET || "";
if (!prova && !/^sb_secret_/.test(chiave) && !/^eyJ/.test(chiave)) stop("manca la chiave secret (AUSER_CHIAVE_SECRET)");
if (/^sb_publishable_/.test(chiave)) stop("serve la chiave secret, non quella pubblica");
const h = extra => ({apikey: chiave, ...(chiave.startsWith("sb_secret_") ? {} : {Authorization: "Bearer " + chiave}), ...extra});
const pulisci = t => String(t).split(chiave).join("***").slice(0, 200);
const enc = p => p.split("/").map(encodeURIComponent).join("/");

async function json(url, opz = {}) {
  const r = await fetch(url, {...opz, headers: h(opz.headers)});
  if (!r.ok) stop(`HTTP ${r.status} su ${url.replace(base, "")}: ${pulisci(await r.text().catch(() => ""))}`);
  return r.json();
}
// Elenco ricorsivo: le voci senza id sono cartelle
async function elenca(bucket, prefisso = "") {
  const out = [];
  for (let offset = 0; ; offset += 1000) {
    const voci = await json(`${base}/storage/v1/object/list/${bucket}`, {method: "POST", headers: {"content-type": "application/json"},
      body: JSON.stringify({prefix: prefisso, limit: 1000, offset, sortBy: {column: "name", order: "asc"}})});
    for (const v of voci) {
      const nome = prefisso ? `${prefisso}/${v.name}` : v.name;
      if (v.id === null || v.id === undefined) out.push(...await elenca(bucket, nome));
      else out.push({nome, size: Number(v.metadata?.size ?? -1), etag: String(v.metadata?.eTag || "").replace(/"/g, "")});
    }
    if (voci.length < 1000) return out;
  }
}

const bucket = await json(`${base}/storage/v1/bucket`);
const inventario = [], problemi = {dimensione: 0, md5: 0, download: 0, senzaEtag: 0, percorsoNonSicuro: 0};
let byte = 0;
for (const b of bucket) {
  const file = await elenca(b.id);
  for (const f of file) {
    const locale = path.join(dest, "storage", b.id, f.nome);
    if (!locale.startsWith(path.join(dest, "storage", b.id) + path.sep)) { problemi.percorsoNonSicuro++; continue; }
    const r = await fetch(`${base}/storage/v1/object/authenticated/${b.id}/${enc(f.nome)}`, {headers: h()});
    if (!r.ok) { problemi.download++; await r.text().catch(() => ""); continue; }
    const dati = Buffer.from(await r.arrayBuffer());
    fs.mkdirSync(path.dirname(locale), {recursive: true, mode: 0o700});
    fs.writeFileSync(locale, dati, {mode: 0o600, flag: "wx"});
    const md5 = crypto.createHash("md5").update(dati).digest("hex");
    const sha256 = crypto.createHash("sha256").update(dati).digest("hex");
    if (f.size >= 0 && f.size !== dati.length) problemi.dimensione++;
    if (!f.etag) problemi.senzaEtag++;
    else if (/^[0-9a-f]{32}$/.test(f.etag) && f.etag !== md5) problemi.md5++;   // eTag multipart (con "-") non confrontabile
    byte += dati.length;
    inventario.push({bucket: b.id, pubblico: !!b.public, percorso: f.nome, byte: dati.length, md5, sha256, etag: f.etag});
  }
  console.log(`bucket ${b.public ? "pubblico" : "privato"} n.${bucket.indexOf(b) + 1}: ${file.length} file elencati`);
}
fs.writeFileSync(path.join(dest, "inventario-storage.json"), JSON.stringify({creato: new Date().toISOString(), bucket: bucket.map(b => ({id: b.id, pubblico: !!b.public})), file: inventario}, null, 1), {mode: 0o600});
const conta = inventario.reduce((m, f) => (m[f.bucket] = (m[f.bucket] || 0) + 1, m), {});
console.log("file salvati per bucket:", JSON.stringify(conta), "| byte totali:", byte);
console.log("problemi:", JSON.stringify(problemi));
if (Object.values(problemi).some(n => n > 0)) { console.log("ATTENZIONE: ci sono problemi: il backup dei file NON è completo"); process.exit(2); }
console.log("Fatto: tutti i file scaricati e controllati. Nessuna modifica a Supabase.");
