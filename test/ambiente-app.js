// Ambiente di prova per caricare l'app VERA (index.html → config, temi, sicurezza,
// importa-xls, app.js) in Node, con un DOM minimo e un finto Supabase in memoria.
// Nessuna rete: il finto client registra ogni richiesta, così i test possono
// controllare quale bucket viene usato, quando si firmano gli URL, ecc.
// Non è un file di test (non finisce con .test.js): lo usano gli altri test.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const RADICE = path.join(__dirname, "..");
const BASE = "https://finto.supabase.co";

function elemento() {
  const el = {
    innerHTML: "", textContent: "", value: "", hidden: false, checked: false, disabled: false, files: [],
    style: {setProperty() {}, removeProperty() {}},
    dataset: {},
    classList: {toggle() {}, add() {}, remove() {}, contains() { return false; }},
    addEventListener() {}, removeEventListener() {}, setAttribute() {}, removeAttribute() {}, getAttribute() { return null; },
    querySelector() { return elemento(); }, querySelectorAll() { return []; },
    focus() {}, blur() {}, click() {}, appendChild() {}, remove() {}, closest() { return null; }, scrollIntoView() {}, scrollTo() {}
  };
  return el;
}

function documentoFinto() {
  const perSelettore = new Map();
  const doc = {
    visibilityState: "visible",
    body: elemento(), documentElement: elemento(), head: elemento(),
    querySelector(sel) { if (!perSelettore.has(sel)) perSelettore.set(sel, elemento()); return perSelettore.get(sel); },
    querySelectorAll() { return []; },
    getElementById(id) { return doc.querySelector("#" + id); },
    createElement() { return elemento(); },
    addEventListener() {}, removeEventListener() {}
  };
  return doc;
}

const copia = x => JSON.parse(JSON.stringify(x));

// ---------- Finto Supabase ----------
function supabaseFinto(dati) {
  const st = {
    sessione: null,
    ascoltatori: [],
    tabelle: copia(dati.tabelle),
    profili: dati.profili,                 // id → {ruolo, nome}
    oggetti: {foto: new Set(dati.fileFoto || []), "foto-private": new Set(dati.filePrivati || [])},
    richieste: [],                         // registro di tutto ciò che l'app chiede
    pausa: null,                           // se è una Promise, le letture di tabelle la aspettano
    pausaFirma: null,                      // idem per createSignedUrls
    pausaProfilo: null,                    // idem per la lettura del proprio profilo
    firmaRotta: false,                     // createSignedUrls risponde con errore
    firmaMancante: new Set(),              // percorsi che non si riescono a firmare
    inserimentoRotto: false,               // insert su "foto" fallisce
    contatoreFirme: 0
  };
  const emetti = (evento, sessione) => st.ascoltatori.forEach(cb => cb(evento, sessione));
  const ruolo = () => st.sessione ? (st.profili[st.sessione.user.id] || {}).ruolo : null;
  const livello = () => ({presidente: 3, direttivo: 2, socio: 1})[ruolo()] || 0;

  function query(tabella) {
    const q = {filtri: [], singolo: false, operazione: "select", riga: null};
    const istantanea = copia(st.tabelle[tabella] || []);
    const pausa = tabella === "profili" && st.pausaProfilo ? st.pausaProfilo : st.pausa;
    const risolvi = async () => {
      if (pausa) await pausa;
      st.richieste.push({tipo: "tabella", tabella, operazione: q.operazione, riga: q.riga});
      if (q.operazione === "insert") {
        if (tabella === "foto" && st.inserimentoRotto) return {data: null, error: {message: "errore di prova"}};
        st.tabelle[tabella] = [...(st.tabelle[tabella] || []), {id: "nuova-" + st.richieste.length, creato_il: new Date().toISOString(), ...q.riga}];
        return {data: null, error: null};
      }
      if (q.operazione === "delete") {
        st.tabelle[tabella] = (st.tabelle[tabella] || []).filter(r => !q.filtri.every(([c, v]) => r[c] === v));
        return {data: null, error: null};
      }
      if (q.operazione === "update") {
        (st.tabelle[tabella] || []).filter(r => q.filtri.every(([c, v]) => r[c] === v)).forEach(r => Object.assign(r, q.riga));
        return {data: null, error: null};
      }
      // Letture con le stesse regole del database: tesserati e profili solo dal direttivo,
      // tutto il resto solo dai soci (tranne impostazioni, pubbliche).
      let righe = istantanea.filter(r => q.filtri.every(([c, v]) => r[c] === v));
      if (tabella === "profili" && livello() < 2) righe = righe.filter(r => st.sessione && r.id === st.sessione.user.id);
      else if (tabella === "tesserati" && livello() < 2) righe = [];
      else if (tabella !== "impostazioni" && tabella !== "profili" && livello() < 1) righe = [];
      if (tabella === "profili") righe = righe.map(r => ({...r, ...(st.profili[r.id] || {})}));
      return {data: q.singolo ? (righe[0] || null) : righe, error: null};
    };
    Object.assign(q, {
      select() { return q; }, order() { return q; },
      eq(c, v) { q.filtri.push([c, v]); return q; },
      maybeSingle() { q.singolo = true; return q; },
      insert(riga) { q.operazione = "insert"; q.riga = riga; return q; },
      update(riga) { q.operazione = "update"; q.riga = riga; return q; },
      delete() { q.operazione = "delete"; return q; },
      then(ok, ko) { return risolvi().then(ok, ko); }
    });
    return q;
  }

  function bucket(nome) {
    return {
      async upload(percorso, blob, opz) {
        st.richieste.push({tipo: "upload", bucket: nome, percorso, opz});
        if (!st.sessione || livello() < 1 || percorso.split("/")[0] !== st.sessione.user.id) return {data: null, error: {message: "row-level security"}};
        st.oggetti[nome].add(percorso);
        return {data: {path: percorso}, error: null};
      },
      getPublicUrl(percorso) {
        st.richieste.push({tipo: "publicUrl", bucket: nome, percorso});
        return {data: {publicUrl: `${BASE}/storage/v1/object/public/${nome}/${percorso}`}};
      },
      async remove(percorsi) {
        st.richieste.push({tipo: "remove", bucket: nome, percorsi});
        percorsi.forEach(p => st.oggetti[nome].delete(p));
        return {data: [], error: null};
      },
      async createSignedUrls(percorsi, durata) {
        if (st.pausaFirma) await st.pausaFirma;
        st.contatoreFirme++;
        st.richieste.push({tipo: "firma", bucket: nome, percorsi: [...percorsi], durata});
        if (st.firmaRotta) return {data: null, error: {message: "Storage non disponibile"}};
        if (!st.sessione || livello() < 1) return {data: null, error: {message: "non autorizzato"}};
        // Risposta in ordine INVERSO: l'app deve abbinare per percorso
        const data = percorsi.map(p => st.oggetti[nome].has(p) && !st.firmaMancante.has(p)
          ? {path: p, error: null, signedURL: `/object/sign/${nome}/${p}?token=t${st.contatoreFirme}`,
             signedUrl: `${BASE}/storage/v1/object/sign/${nome}/${p}?token=t${st.contatoreFirme}`}
          : {path: p, error: "Object not found", signedURL: null, signedUrl: null}).reverse();
        return {data, error: null};
      }
    };
  }

  const client = {
    auth: {
      async getSession() { return {data: {session: st.sessione}}; },
      onAuthStateChange(cb) { st.ascoltatori.push(cb); return {data: {subscription: {unsubscribe() {}}}}; },
      async signOut() { st.sessione = null; emetti("SIGNED_OUT", null); return {error: null}; }
    },
    from: query,
    async rpc(fn, args) {
      if (st.pausa) await st.pausa;
      st.richieste.push({tipo: "rpc", fn, args});
      if (fn === "conteggi") return {data: [], error: null};
      return {data: null, error: null};
    },
    storage: {from: bucket}
  };
  // Comandi per i test
  const comandi = {
    entra(id) { st.sessione = {user: {id, user_metadata: {}}}; emetti("SIGNED_IN", st.sessione); },
    esci() { return client.auth.signOut(); }
  };
  return {client, st, comandi};
}

// ---------- Dati di prova (finti, nessun dato reale) ----------
const U = {pres: "00000000-0000-0000-0000-0000000000p1", soc: "00000000-0000-0000-0000-0000000000s1", soc2: "00000000-0000-0000-0000-0000000000s2", att: "00000000-0000-0000-0000-0000000000w1"};
function datiProva() {
  const futuro = new Date(Date.now() + 10 * 864e5).toISOString().slice(0, 10);
  const passato = new Date(Date.now() - 10 * 864e5).toISOString().slice(0, 10);
  return {
    profili: {
      [U.pres]: {ruolo: "presidente", nome: "Presidente Prova"},
      [U.soc]: {ruolo: "socio", nome: "Socia Prova"},
      [U.soc2]: {ruolo: "socio", nome: "Socio Due"},
      [U.att]: {ruolo: "in_attesa", nome: "In Attesa"}
    },
    tabelle: {
      profili: [{id: U.pres, telefono: "3330000001"}, {id: U.soc, telefono: "3330000002"}, {id: U.soc2, telefono: "3330000003"}, {id: U.att, telefono: "3330000004"}],
      attivita: [
        {id: "g-futura", tipo: "gita", titolo: "Gita futura", data: futuro, stato: "aperta", ospiti: true, posti: null,
         immagine: `${BASE}/storage/v1/object/public/foto/${U.pres}/copertina.jpg`},
        {id: "g-locandina", tipo: "evento", titolo: "Festa con locandina", data: futuro, stato: "aperta", ospiti: true, immagine: "locandine/2026-11-11-san-martino.jpg"},
        {id: "g-passata", tipo: "gita", titolo: "Gita passata", data: passato, stato: "chiusa", ospiti: true, immagine: ""}
      ],
      assemblee: [], adesioni: [], bacheca: [],
      impostazioni: [{id: 1, sede: "Gratteri", logo: "", tema: "bianco", facebook: "", instagram: "", whatsapp: ""}],
      tesserati: [{id: "t1", nome: "Tesserata Finta", telefono: "3339999999"}],
      foto: [
        // Foto vecchia, ancora nel bucket pubblico (prima del trasferimento)
        {id: "f-pub", attivita_id: "g-passata", user_id: U.soc, autore: "S", percorso: `${U.soc}/1-vecchia.jpg`, bucket: "foto",
         url: `${BASE}/storage/v1/object/public/foto/${U.soc}/1-vecchia.jpg`, creato_il: "2026-10-01T10:00:00Z"},
        // Foto già nel bucket privato
        {id: "f-priv", attivita_id: "g-passata", user_id: U.soc, autore: "S", percorso: `${U.soc}/2-privata.jpg`, bucket: "foto-private",
         url: "", creato_il: "2026-10-02T10:00:00Z"},
        // Riga senza colonna bucket (database non ancora migrato)
        {id: "f-senza", attivita_id: "g-passata", user_id: U.pres, autore: "P", percorso: `${U.pres}/3-senza.jpg`,
         url: `${BASE}/storage/v1/object/public/foto/${U.pres}/3-senza.jpg`, creato_il: "2026-10-03T10:00:00Z"}
      ]
    },
    fileFoto: [`${U.pres}/copertina.jpg`, `${U.soc}/1-vecchia.jpg`, `${U.pres}/3-senza.jpg`],
    filePrivati: [`${U.soc}/2-privata.jpg`]
  };
}

// Carica l'app come nel browser. "utente" = sessione già aperta all'avvio (o null).
async function avviaApp({utente = null, dati = datiProva()} = {}) {
  const sb = supabaseFinto(dati);
  if (utente) sb.st.sessione = {user: {id: utente, user_metadata: {}}};
  const errori = [];
  const intervalli = [];
  const ctx = {
    console: {log() {}, info() {}, warn() {}, error: (...a) => errori.push(a.map(String).join(" "))},
    setTimeout: (f, ms) => { const t = setTimeout(f, Math.min(ms || 0, 5)); t.unref?.(); return t; },
    clearTimeout,
    setInterval: (f, ms) => { intervalli.push({f, ms}); return intervalli.length; },
    clearInterval() {},
    URL, Blob: class {}, Date, Promise, JSON, Math, Intl,
    localStorage: {getItem() { return null; }, setItem() {}, removeItem() {}},
    navigator: {clipboard: {writeText: async () => {}}},
    matchMedia: () => ({matches: false, addEventListener() {}}),
    requestAnimationFrame: f => f(),
    scrollTo() {},
    document: documentoFinto(),
    AUSER_CONFIG: {url: BASE, chiave: "sb_publishable_finto"},
    supabase: {createClient: () => sb.client}
  };
  ctx.window = ctx;
  vm.createContext(ctx);
  for (const f of ["temi.js", "sicurezza.js", "importa-xls.js", "app.js"]) {
    vm.runInContext(fs.readFileSync(path.join(RADICE, f), "utf8"), ctx, {filename: f});
  }
  const app = {
    sb, ctx, errori, intervalli,
    S: vm.runInContext("S", ctx),
    esegui: codice => vm.runInContext(codice, ctx),
    html: () => ctx.document.querySelector("#app").innerHTML,
    attendi: async (condizione, ms = 2000) => {
      const fine = Date.now() + ms;
      while (!condizione()) {
        if (Date.now() > fine) throw new Error("Tempo scaduto in attesa di una condizione");
        await new Promise(r => setTimeout(r, 2));
      }
    },
    calma: () => new Promise(r => setTimeout(r, 20))   // lascia finire le richieste in corso
  };
  await app.attendi(() => app.S.loading === false || app.S.realRole !== "lettore");
  await app.calma();
  return app;
}

function cancello() { let apri; const p = new Promise(r => { apri = r; }); return {p, apri}; }

module.exports = {avviaApp, datiProva, cancello, U, BASE};
