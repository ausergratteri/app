#!/usr/bin/env node
/* =====================================================================
   AUSER GRATTERI – trasferimento delle foto delle gallerie nel bucket privato
   Lavora con l'API di Supabase (Storage + REST). Non serve installare nulla: Node 18+.

   La chiave "secret" (service role) si inserisce SOLO nel proprio Terminale, senza
   mostrarla e senza salvarla nella cronologia:
       export SUPABASE_URL=https://dylztksgeqnktoapsbim.supabase.co
       read -s "SUPABASE_SERVICE_ROLE_KEY?Chiave secret: " && export SUPABASE_SERVICE_ROLE_KEY && echo
   Alla fine:  unset SUPABASE_SERVICE_ROLE_KEY

   Comandi (il registro CSV va in una cartella cifrata, per esempio il disco "Backup AUSER"):
     node supabase/operazioni/foto-private.js piano    --uscita DIR   solo lettura
     node supabase/operazioni/foto-private.js copia    --uscita DIR   copia foto → foto-private e verifica (SHA-256)
     node supabase/operazioni/foto-private.js verifica --uscita DIR   solo lettura: confronta le due copie
     node supabase/operazioni/foto-private.js riporta-pubbliche --uscita DIR
                                                       rollback: ricopia nel bucket pubblico le foto che ci mancano
     node supabase/operazioni/foto-private.js elimina-pubbliche --uscita DIR --conferma ELIMINA-COPIE-PUBBLICHE
                                                       ULTIMO passo, dopo settimane di verifiche: toglie le copie pubbliche

   Lo script non cambia MAI le righe del database: il passaggio delle righe al bucket privato
   lo fa 06_attiva_foto_private.sql, il ritorno 05_rollback_foto_private.sql.
   Non scrive mai la chiave nei messaggi. Il registro contiene solo id e percorsi tecnici
   (<id utente>/<data>-<codice>.jpg), dimensioni e impronte: nessun nome.
   ===================================================================== */
"use strict";
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const PUBBLICO = "foto", PRIVATO = "foto-private";
const CONFERMA_ELIMINA = "ELIMINA-COPIE-PUBBLICHE";

const sha256 = byte => crypto.createHash("sha256").update(byte).digest("hex");
const TIPI = {jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", webp: "image/webp", gif: "image/gif"};
const tipoDa = percorso => TIPI[(percorso.split(".").pop() || "").toLowerCase()] || "application/octet-stream";

// ---------- Accesso a Supabase (fetch iniettabile per i test) ----------
function creaClient({url, chiave, fetch: f = globalThis.fetch}) {
  if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(String(url || "").replace(/\/+$/, ""))) {
    throw new Error("SUPABASE_URL non valido: deve essere https://<progetto>.supabase.co");
  }
  if (!chiave || chiave.length < 20) throw new Error("Manca la chiave SUPABASE_SERVICE_ROLE_KEY");
  if (/^sb_publishable_/.test(chiave) || /"role"\s*:\s*"anon"/.test(decodificaJwt(chiave))) {
    throw new Error("Serve la chiave secret (service role), non quella pubblica dell'app");
  }
  const base = url.replace(/\/+$/, "");
  const h = extra => ({
    apikey: chiave,
    ...(!chiave.startsWith("sb_secret_") ? {Authorization: "Bearer " + chiave} : {}),
    ...extra
  });
  const enc = p => p.split("/").map(encodeURIComponent).join("/");
  // Messaggi d'errore senza intestazioni né chiave
  const errore = async (cosa, r) => new Error(`${cosa}: HTTP ${r.status} ${(await r.text().catch(() => "")).slice(0, 200).split(chiave).join("***")}`);

  return {
    async righe(tabella, colonne) {
      const out = [];
      for (let da = 0; ; da += 1000) {
        const r = await f(`${base}/rest/v1/${tabella}?select=${colonne}&order=id&offset=${da}&limit=1000`, {headers: h()});
        if (!r.ok) throw await errore(`lettura ${tabella}`, r);
        const parte = await r.json();
        out.push(...parte);
        if (parte.length < 1000) return out;
      }
    },
    async scarica(bucket, percorso) {
      const r = await f(`${base}/storage/v1/object/authenticated/${bucket}/${enc(percorso)}`, {headers: h()});
      if (r.status === 404 || r.status === 400) { await r.text().catch(() => ""); return null; }
      if (!r.ok) throw await errore(`download ${bucket}`, r);
      return {byte: Buffer.from(await r.arrayBuffer()), tipo: r.headers.get("content-type") || tipoDa(percorso)};
    },
    // "ok" se caricato, "esiste" se c'era già (non si sovrascrive mai)
    async carica(bucket, percorso, byte, tipo) {
      const r = await f(`${base}/storage/v1/object/${bucket}/${enc(percorso)}`, {
        method: "POST", body: byte, headers: h({"content-type": tipo, "x-upsert": "false", "cache-control": "3600"})
      });
      if (r.ok) { await r.text().catch(() => ""); return "ok"; }
      const testo = await r.text().catch(() => "");
      if (r.status === 409 || /Duplicate|already exists/i.test(testo)) return "esiste";
      throw new Error(`upload ${bucket}: HTTP ${r.status} ${testo.slice(0, 200).split(chiave).join("***")}`);
    },
    async elimina(bucket, percorsi) {
      const r = await f(`${base}/storage/v1/object/${bucket}`, {
        method: "DELETE", body: JSON.stringify({prefixes: percorsi}), headers: h({"content-type": "application/json"})
      });
      if (!r.ok) throw await errore(`eliminazione ${bucket}`, r);
      await r.text().catch(() => "");
    }
  };
}

function decodificaJwt(k) {
  const p = String(k).split(".");
  if (p.length !== 3) return "";
  try { return Buffer.from(p[1], "base64url").toString("utf8"); } catch (e) { return ""; }
}

// Percorsi del bucket pubblico usati da copertine, bacheca e logo: non si toccano mai
async function percorsiProtetti(sb) {
  const prefisso = /\/storage\/v1\/object\/public\/foto\/(.+)$/;
  const valori = [
    ...(await sb.righe("attivita", "id,immagine")).map(r => r.immagine),
    ...(await sb.righe("bacheca", "id,immagine")).map(r => r.immagine),
    ...(await sb.righe("impostazioni", "id,logo")).map(r => r.logo)
  ];
  return new Set(valori.map(v => (String(v || "").match(prefisso) || [])[1]).filter(Boolean).map(decodeURIComponent));
}

const righeFoto = async sb => (await sb.righe("foto", "id,percorso,bucket,user_id"))
  .map(r => ({...r, bucket: r.bucket || PUBBLICO}));

// ---------- Comandi ----------
async function piano(sb, log) {
  const righe = await righeFoto(sb), protetti = await percorsiProtetti(sb);
  const conta = {};
  righe.forEach(r => conta[r.bucket] = (conta[r.bucket] || 0) + 1);
  const senzaPercorso = righe.filter(r => !r.percorso).length;
  const visti = new Set(), doppi = new Set();
  righe.forEach(r => { if (r.percorso) { if (visti.has(r.percorso)) doppi.add(r.percorso); visti.add(r.percorso); } });
  const fuoriCartella = righe.filter(r => r.percorso && r.user_id && r.percorso.split("/")[0] !== r.user_id).length;
  const copertineInGalleria = righe.filter(r => protetti.has(r.percorso)).length;
  const esito = {
    righe: righe.length, nel_bucket_pubblico: conta[PUBBLICO] || 0, nel_bucket_privato: conta[PRIVATO] || 0,
    da_copiare: righe.filter(r => r.bucket === PUBBLICO && r.percorso).length,
    senza_percorso: senzaPercorso, percorsi_ripetuti: doppi.size, fuori_cartella: fuoriCartella,
    copertine_bacheca_logo_nel_bucket: protetti.size, copertine_usate_anche_in_galleria: copertineInGalleria
  };
  Object.entries(esito).forEach(([k, v]) => log(`${k.replace(/_/g, " ")}: ${v}`));
  return esito;
}

async function copia(sb, log, {da = PUBBLICO, a = PRIVATO, soloSenzaCopia = false} = {}) {
  const righe = (await righeFoto(sb)).filter(r => r.percorso && (soloSenzaCopia ? r.bucket === PRIVATO : r.bucket === PUBBLICO));
  const registro = [];
  let n = 0;
  for (const r of righe) {
    n++;
    const voce = {id: r.id, percorso: r.percorso, byte: "", sha256: "", esito: ""};
    try {
      const sorgente = await sb.scarica(da, r.percorso);
      if (soloSenzaCopia && await sb.scarica(a, r.percorso)) { voce.esito = "gia-presente"; registro.push(voce); continue; }
      if (!sorgente) { voce.esito = `manca-in-${da}`; registro.push(voce); continue; }
      voce.byte = sorgente.byte.length; voce.sha256 = sha256(sorgente.byte);
      const stato = await sb.carica(a, r.percorso, sorgente.byte, sorgente.tipo);
      const destinazione = await sb.scarica(a, r.percorso);
      const uguale = destinazione && sha256(destinazione.byte) === voce.sha256;
      voce.esito = uguale ? (stato === "esiste" ? "gia-presente-identica" : "copiata-verificata")
                          : (stato === "esiste" ? "DIVERSA-gia-presente" : "VERIFICA-FALLITA");
    } catch (e) {
      voce.esito = "ERRORE: " + String(e.message || e).slice(0, 120);
    }
    registro.push(voce);
    if (n % 20 === 0) log(`… ${n} di ${righe.length}`);
  }
  riassumi(registro, log);
  return registro;
}

async function verifica(sb, log) {
  const righe = (await righeFoto(sb)).filter(r => r.percorso);
  const registro = [];
  for (const r of righe) {
    const voce = {id: r.id, percorso: r.percorso, byte: "", sha256: "", esito: ""};
    try {
      const pub = await sb.scarica(PUBBLICO, r.percorso), pri = await sb.scarica(PRIVATO, r.percorso);
      const attiva = r.bucket === PRIVATO ? "riga-privata" : "riga-pubblica";
      if (pri) { voce.byte = pri.byte.length; voce.sha256 = sha256(pri.byte); }
      if (!pri && r.bucket === PRIVATO) voce.esito = `${attiva}: MANCA-COPIA-PRIVATA`;
      else if (!pri) voce.esito = `${attiva}: da-copiare`;
      else if (!pub) voce.esito = `${attiva}: solo-privata`;
      else voce.esito = sha256(pub.byte) === voce.sha256 ? `${attiva}: copie-identiche` : `${attiva}: COPIE-DIVERSE`;
    } catch (e) { voce.esito = "ERRORE: " + String(e.message || e).slice(0, 120); }
    registro.push(voce);
  }
  riassumi(registro, log);
  return registro;
}

async function eliminaPubbliche(sb, log, {conferma} = {}) {
  if (conferma !== CONFERMA_ELIMINA) {
    throw new Error(`Per eliminare le copie pubbliche serve --conferma ${CONFERMA_ELIMINA}`);
  }
  const protetti = await percorsiProtetti(sb);
  const righe = (await righeFoto(sb)).filter(r => r.bucket === PRIVATO && r.percorso);
  const registro = [], daTogliere = [];
  for (const r of righe) {
    const voce = {id: r.id, percorso: r.percorso, byte: "", sha256: "", esito: ""};
    try {
      if (protetti.has(r.percorso)) { voce.esito = "protetta-copertina-bacheca-logo"; registro.push(voce); continue; }
      const pub = await sb.scarica(PUBBLICO, r.percorso), pri = await sb.scarica(PRIVATO, r.percorso);
      if (!pub) voce.esito = "gia-assente";
      else if (!pri) voce.esito = "TENUTA: manca la copia privata";
      else if (sha256(pub.byte) !== sha256(pri.byte)) voce.esito = "TENUTA: copie diverse";
      else { voce.byte = pri.byte.length; voce.sha256 = sha256(pri.byte); voce.esito = "da-togliere"; daTogliere.push(voce); }
    } catch (e) { voce.esito = "ERRORE: " + String(e.message || e).slice(0, 120); }
    registro.push(voce);
  }
  for (let i = 0; i < daTogliere.length; i += 50) {
    const parte = daTogliere.slice(i, i + 50);
    await sb.elimina(PUBBLICO, parte.map(v => v.percorso));
    for (const v of parte) {
      const ancoraPrivata = await sb.scarica(PRIVATO, v.percorso);
      v.esito = ancoraPrivata && sha256(ancoraPrivata.byte) === v.sha256 ? "tolta-copia-pubblica" : "ATTENZIONE: verificare copia privata";
    }
  }
  riassumi(registro, log);
  return registro;
}

function riassumi(registro, log) {
  const conta = {};
  registro.forEach(v => { const k = v.esito.startsWith("ERRORE") ? "ERRORE" : v.esito; conta[k] = (conta[k] || 0) + 1; });
  log(`totale: ${registro.length}`);
  Object.entries(conta).sort().forEach(([k, n]) => log(`  ${k}: ${n}`));
}

function csv(registro) {
  const q = v => `"${String(v ?? "").replace(/"/g, '""')}"`;
  return ["id,percorso,byte,sha256,esito", ...registro.map(v => [v.id, v.percorso, v.byte, v.sha256, v.esito].map(q).join(","))].join("\n") + "\n";
}

const problemi = registro => registro.filter(v => /^(ERRORE|DIVERSA|VERIFICA|manca|TENUTA|ATTENZIONE)|MANCA|DIVERSE/.test(v.esito)).length;

// ---------- Riga di comando ----------
async function principale(argv = process.argv.slice(2), env = process.env, log = console.log) {
  const comando = argv[0];
  const opz = k => { const i = argv.indexOf("--" + k); return i > 0 ? argv[i + 1] : undefined; };
  const comandi = ["piano", "copia", "verifica", "riporta-pubbliche", "elimina-pubbliche"];
  if (!comandi.includes(comando)) {
    log(`Uso: node supabase/operazioni/foto-private.js <${comandi.join("|")}> --uscita DIR`);
    return 2;
  }
  const uscita = opz("uscita");
  if (comando !== "piano" && (!uscita || !fs.existsSync(uscita) || !fs.statSync(uscita).isDirectory())) {
    log("Indica con --uscita una cartella esistente (meglio nel disco cifrato) per il registro CSV");
    return 2;
  }
  const sb = creaClient({url: env.SUPABASE_URL, chiave: env.SUPABASE_SERVICE_ROLE_KEY});
  let registro;
  if (comando === "piano") { await piano(sb, log); return 0; }
  if (comando === "copia") registro = await copia(sb, log);
  if (comando === "verifica") registro = await verifica(sb, log);
  if (comando === "riporta-pubbliche") registro = await copia(sb, log, {da: PRIVATO, a: PUBBLICO, soloSenzaCopia: true});
  if (comando === "elimina-pubbliche") registro = await eliminaPubbliche(sb, log, {conferma: opz("conferma")});
  const file = path.join(uscita, `foto-private-${comando}-${new Date().toISOString().replace(/[:.]/g, "-")}.csv`);
  fs.writeFileSync(file, csv(registro), {mode: 0o600});
  log(`registro: ${file}`);
  const p = problemi(registro);
  log(p ? `ATTENZIONE: ${p} righe da controllare nel registro` : "nessun problema");
  return p ? 1 : 0;
}

if (require.main === module) {
  principale().then(c => { process.exitCode = c; }, e => { console.error("Errore:", e.message); process.exitCode = 1; });
}

module.exports = {creaClient, piano, copia, verifica, eliminaPubbliche, percorsiProtetti, csv, principale, CONFERMA_ELIMINA};
