/* ---------- Importazione dei tesserati dal gestionale AUSER (.xls) ----------
   Funzioni pure, senza DOM: le usa app.js nel browser e test/importa-xls.test.js
   con Node. La lettura del file avviene solo nel browser di chi importa.

   Regola d'oro: telefoni e numeri tessera NON vengono mai "aggiustati" in silenzio.
   - una cella di testo resta esattamente com'è;
   - una cella numerica si legge dal valore, non dal testo mostrato in Excel
     (con il formato "Generale" 393331234567 verrebbe mostrato come 3.93331E+11);
   - i formati a zeri (es. "000000") rimettono gli zeri iniziali, come in Excel;
   - decimali o numeri oltre 15 cifre sono già alterati nel file: errore, non correzione. */

const IMPORT_MAX_BYTE = 5 * 1024 * 1024;
const IMPORT_MAX_RIGHE = 5000;

// Intestazioni riconosciute (dopo normalizzazione), in ordine di preferenza
const CAMPI_IMPORT = {
  tessera: ["numero tessera", "n tessera", "nr tessera", "num tessera", "n tess", "tessera n", "tessera numero", "codice tessera", "tessera"],
  nominativo: ["nominativo", "cognome e nome", "cognome nome", "nome e cognome", "nome cognome", "denominazione", "socio"],
  cognome: ["cognome"],
  nome: ["nome"],
  telefono: ["cellulare", "cell", "telefono cellulare", "tel cellulare", "cellulare 1", "mobile", "telefono mobile",
             "telefono", "tel", "recapito telefonico", "telefono 1", "recapito"],
  email: ["email", "e mail", "mail", "indirizzo email", "indirizzo e mail", "posta elettronica", "email 1", "e mail 1"]
};
const ETICHETTE_IMPORT = {tessera: "Numero tessera", nominativo: "Nome e cognome (una colonna)", cognome: "Cognome", nome: "Nome", telefono: "Telefono", email: "Email"};

function normIntestazione(s) {
  return String(s ?? "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/[°º]/g, " ").replace(/[^a-z0-9]+/g, " ").trim();
}

// Valore di una cella come testo, senza alterarlo. Restituisce {testo, tipo, errore?}
function valoreCella(c, isDate) {
  if (!c || c.v === undefined || c.v === null) return {testo: "", tipo: "vuota"};
  if (c.t === "s" || c.t === "str") return {testo: String(c.v), tipo: "testo"};
  if (c.t === "n") {
    const v = c.v, z = String(c.z || "General");
    if (!Number.isFinite(v)) return {testo: "", tipo: "numero", errore: "numero non valido"};
    if (/^0+$/.test(z) && Number.isSafeInteger(v) && v >= 0) return {testo: String(v).padStart(z.length, "0"), tipo: "numero"};
    if (typeof isDate === "function" && isDate(z)) return {testo: String(c.w ?? v), tipo: "data"};
    if (!Number.isInteger(v)) return {testo: String(c.w ?? v), tipo: "numero", errore: "numero con decimali: controllare la cella nel file"};
    if (!Number.isSafeInteger(v)) return {testo: String(v), tipo: "numero", errore: "numero troppo lungo: alcune cifre sono già alterate nel file"};
    return {testo: v.toFixed(0), tipo: "numero"};
  }
  if (c.t === "b") return {testo: c.v ? "VERO" : "FALSO", tipo: "altro"};
  if (c.t === "e") return {testo: "", tipo: "errore", errore: "cella con errore di Excel"};
  return {testo: String(c.w ?? c.v), tipo: "altro"};
}

// Legge il file e restituisce il primo foglio con dati: intestazioni originali e righe.
function leggiXls(XLSX, dati) {
  const wb = XLSX.read(dati, {
    type: "array", raw: true, dense: true, cellNF: true, cellText: true, cellDates: false,
    cellFormula: false, cellHTML: false, cellStyles: false, bookVBA: false, sheetRows: IMPORT_MAX_RIGHE + 25
  });
  const isDate = XLSX.SSF && XLSX.SSF.is_date ? z => { try { return XLSX.SSF.is_date(z); } catch (e) { return false; } } : null;
  for (const nomeFoglio of wb.SheetNames) {
    const righe = (wb.Sheets[nomeFoglio] || {})["!data"] || [];
    // La riga di intestazione è la prima (tra le prime 20) con almeno due celle di testo
    let h = -1;
    for (let i = 0; i < Math.min(righe.length, 20); i++) {
      const r = righe[i] || [];
      if (r.filter(c => c && c.t === "s" && String(c.v).trim()).length >= 2) { h = i; break; }
    }
    if (h < 0) continue;
    const larghezza = Math.max(...righe.slice(h).map(r => (r || []).length));
    const intestazioni = Array.from({length: larghezza}, (_, j) => {
      const t = valoreCella((righe[h] || [])[j], isDate).testo.trim();
      return t || "Colonna " + (j + 1);
    });
    const corpo = [];
    for (let i = h + 1; i < righe.length; i++) {
      const celle = Array.from({length: larghezza}, (_, j) => valoreCella((righe[i] || [])[j], isDate));
      if (celle.every(c => c.testo.trim() === "")) continue;
      corpo.push({n: i + 1, celle});
    }
    return {foglio: nomeFoglio, fogli: wb.SheetNames.slice(), intestazioni, righe: corpo.slice(0, IMPORT_MAX_RIGHE), troncato: corpo.length > IMPORT_MAX_RIGHE};
  }
  return {foglio: "", fogli: wb.SheetNames.slice(), intestazioni: [], righe: [], troncato: false};
}

// Quale colonna del file corrisponde a ogni campo (indice o -1)
function mappaColonne(intestazioni) {
  const norm = intestazioni.map(normIntestazione), mappa = {}, usate = new Set();
  for (const [campo, sinonimi] of Object.entries(CAMPI_IMPORT)) {
    mappa[campo] = -1;
    for (const s of sinonimi) {
      const j = norm.findIndex((x, k) => x === s && !usate.has(k));
      if (j >= 0) { mappa[campo] = j; usate.add(j); break; }
    }
  }
  if (mappa.nominativo >= 0 && (mappa.nome >= 0 || mappa.cognome >= 0)) mappa.nominativo = -1;
  return mappa;
}

// Stessa normalizzazione di public.solo_cifre_tel() nel database: serve per i confronti
function telChiave(t) {
  const d = String(t ?? "").replace(/\D/g, "");
  if (d.length === 14 && d.startsWith("0039")) return d.slice(4);
  if (d.length === 12 && d.startsWith("39")) return d.slice(2);
  return d;
}
// Come soloCifre() di app.js: è il formato con cui l'app salva i telefoni
function telSalvato(t) {
  return String(t ?? "").replace(/\D/g, "").replace(/^0039/, "").replace(/^39(?=3\d{8,9}$)/, "");
}
const emailValida = e => /^[^@\s"'<>]+@[^@\s"'<>]+\.[^@\s"'<>]{2,}$/.test(e);

// Controlla ogni riga del file. Non modifica nulla.
function preparaRighe(lettura, mappa) {
  const prendi = (r, campo) => mappa[campo] >= 0 ? r.celle[mappa[campo]] : {testo: "", tipo: "vuota"};
  const righe = lettura.righe.map(r => {
    const errori = [], avvisi = [];
    const cNome = prendi(r, "nome"), cCogn = prendi(r, "cognome"), cNomin = prendi(r, "nominativo");
    const nome = (mappa.nominativo >= 0 ? cNomin.testo : [cNome.testo, cCogn.testo].map(s => s.trim()).filter(Boolean).join(" ")).trim().replace(/\s+/g, " ");
    const cTel = prendi(r, "telefono"), cMail = prendi(r, "email"), cTess = prendi(r, "tessera");
    for (const [c, etichetta] of [[cTel, "telefono"], [cTess, "numero tessera"], [cMail, "email"]]) if (c.errore) errori.push(etichetta + ": " + c.errore);
    const telOriginale = cTel.testo.trim();
    const telefono = telSalvato(telOriginale), chiave = telChiave(telOriginale);
    const email = cMail.testo.trim().toLowerCase();
    const tessera = cTess.testo.trim();
    if (!nome) errori.push("nome mancante");
    if (!telOriginale) errori.push("telefono mancante");
    else if (/[a-z]/i.test(telOriginale.replace(/^(tel|cell)\.?/i, ""))) errori.push("telefono con lettere: " + telOriginale);
    else if (telOriginale.split(/[\/;,|]|\s-\s|\se\s/).filter(p => p.replace(/\D/g, "").length >= 6).length > 1) errori.push("più numeri nella stessa cella: lasciarne uno nel file");
    else if (telefono.length < 6 || telefono.length > 13) errori.push("telefono di lunghezza non valida: " + telOriginale);
    else if (cTel.tipo === "numero" && /^[1-24-9]\d{7,9}$/.test(telefono)) avvisi.push("il gestionale potrebbe aver tolto lo zero iniziale (forse 0" + telefono + "): controllare");
    if (!email) avvisi.push("senza email: servirà l'approvazione del direttivo");
    else if (!emailValida(email)) errori.push("email non valida: " + email);
    if (!tessera) avvisi.push("senza numero tessera");
    return {n: r.n, nome, telOriginale, telefono, chiave, email, tessera, errori, avvisi};
  });
  // Duplicati nel file
  const per = (k) => { const m = new Map(); righe.forEach(r => { const v = r[k]; if (v) m.set(v, [...(m.get(v) || []), r.n]); }); return m; };
  const perTel = per("chiave"), perTess = per("tessera"), perMail = per("email");
  for (const r of righe) {
    const t = perTel.get(r.chiave); if (r.chiave && t && t.length > 1) r.errori.push("telefono ripetuto nelle righe " + t.join(", "));
    const s = perTess.get(r.tessera); if (r.tessera && s && s.length > 1) r.errori.push("numero tessera ripetuto nelle righe " + s.join(", "));
    const m = perMail.get(r.email); if (r.email && m && m.length > 1) r.avvisi.push("email usata anche nelle righe " + m.filter(x => x !== r.n).join(", ") + " (va bene per una famiglia)");
  }
  return righe;
}

// Confronta con l'anagrafica attuale. Nessuna sovrascrittura: produce solo l'elenco delle differenze.
function confrontaAnagrafica(righe, esistenti) {
  const perTel = new Map(), perTess = new Map();
  for (const e of esistenti || []) {
    const k = telChiave(e.telefono); if (k) perTel.set(k, [...(perTel.get(k) || []), e]);
    const s = String(e.numero_tessera || "").trim(); if (s) perTess.set(s, e);
  }
  const esito = {nuovi: [], uguali: [], diversi: [], errori: []};
  for (const r of righe) {
    const errori = [...r.errori];
    const trovati = r.chiave ? perTel.get(r.chiave) || [] : [];
    if (trovati.length > 1) errori.push("in anagrafica ci sono già più tesserati con questo telefono");
    const att = trovati[0];
    const altro = r.tessera ? perTess.get(r.tessera) : null;
    if (altro && (!att || altro.id !== att.id)) errori.push("numero tessera già assegnato a " + (altro.nome || "un altro tesserato"));
    if (errori.length) { esito.errori.push({...r, errori}); continue; }
    if (!att) { esito.nuovi.push(r); continue; }
    const campi = [["nome", "nome", r.nome], ["email", "email", r.email], ["numero_tessera", "numero tessera", r.tessera]];
    const diff = [];
    for (const [k, etichetta, nuovo] of campi) {
      const attuale = String(att[k] ?? "").trim();
      const uguale = k === "email" ? attuale.toLowerCase() === nuovo.toLowerCase() : attuale === nuovo;
      if (!uguale && nuovo !== "") diff.push({campo: k, etichetta, attuale, nuovo, vuoto: attuale === ""});
    }
    if (!diff.length) esito.uguali.push({...r, id: att.id});
    else esito.diversi.push({...r, id: att.id, attuali: {nome: att.nome ?? "", email: att.email ?? "", numero_tessera: att.numero_tessera ?? ""}, diff});
  }
  return esito;
}

// Cosa inviare al database, solo in base alle scelte esplicite di chi importa.
//  scelte.aggiorna: righe (numero di riga) per cui usare TUTTI i dati del file
//  scelte.completaVuoti: per le altre righe diverse, riempi solo i campi vuoti
function pianoImport(esito, scelte = {}) {
  const aggiorna = new Set(scelte.aggiorna || []);
  const nuovi = esito.nuovi.map(r => ({nome: r.nome, telefono: r.telefono, email: r.email, numero_tessera: r.tessera, riga: r.n}));
  const aggiornamenti = [];
  for (const r of esito.diversi) {
    const scelti = aggiorna.has(r.n) ? r.diff : scelte.completaVuoti ? r.diff.filter(d => d.vuoto) : [];
    if (!scelti.length) continue;
    const campi = {}; scelti.forEach(d => { campi[d.campo] = d.nuovo; });
    aggiornamenti.push({id: r.id, campi, attuali: r.attuali, riga: r.n});
  }
  return {nuovi, aggiornamenti};
}

// Report CSV (separatore ";" per Excel italiano). Le celle che iniziano con = + - @
// vengono neutralizzate, così aprendo il report non parte nessuna formula.
function csvReport(esito) {
  const cella = v => { let s = String(v ?? ""); if (/^[=+\-@\t\r]/.test(s)) s = "'" + s; return '"' + s.replace(/"/g, '""') + '"'; };
  const righe = [["Riga", "Esito", "Nome", "Telefono nel file", "Email", "Numero tessera", "Dettagli"]];
  const add = (lista, nomeEsito, det) => lista.forEach(r => righe.push([r.n, nomeEsito, r.nome, r.telOriginale, r.email, r.tessera, det(r)]));
  add(esito.errori, "Errore", r => r.errori.join(" | "));
  add(esito.diversi, "Diverso dall'anagrafica", r => r.diff.map(d => `${d.etichetta}: "${d.attuale}" → "${d.nuovo}"`).join(" | "));
  add(esito.nuovi, "Nuovo", r => r.avvisi.join(" | "));
  add(esito.uguali, "Già presente", r => r.avvisi.join(" | "));
  return "﻿" + righe.map(r => r.map(cella).join(";")).join("\r\n");
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {IMPORT_MAX_BYTE, IMPORT_MAX_RIGHE, CAMPI_IMPORT, ETICHETTE_IMPORT, normIntestazione, valoreCella, leggiXls,
    mappaColonne, telChiave, telSalvato, preparaRighe, confrontaAnagrafica, pianoImport, csvReport};
}
