"use strict";
/* =====================================================================
   Auser Gratteri – app soci
   Dati e accessi su Supabase; se config.js non è compilato l'app parte
   in "modalità prova" con dati di esempio che non vengono salvati.
   ===================================================================== */

const CFG = window.AUSER_CONFIG || {};
if (CFG.url) CFG.url = String(CFG.url).trim().replace(/\/rest\/v1\/?$/, "").replace(/\/+$/, "");
const CONFIGURATA = !!(CFG.url && CFG.chiave && !CFG.url.includes("INCOLLA"));
const DOMINIO_FINTO = "soci.ausergratteri.app"; // il telefono diventa un "indirizzo" interno: nessuna email viene inviata

const S = {
  live: CONFIGURATA, sb: null, sessione: null, profilo: null,
  myId: null, myName: "", realRole: "lettore", viewRole: "lettore",
  att: {}, ass: {}, ades: [], cont: {}, post: {}, cfg: {}, profili: [],
  foto: [], bvista: "avvisi", temaScelto: null, anno: {}, pagina: {},
  tab: "home", filtro: "tutte", loading: true, note: "", sheet: null, authTab: "entra"
};
const ROLES = {presidente: "Presidente", direttivo: "Direttivo", socio: "Socio", lettore: "In attesa"};
const RANK = {lettore: 0, socio: 1, direttivo: 2, presidente: 3};
const can = r => RANK[S.viewRole] >= RANK[r];
const TIPI = {gita: "Gita", evento: "Evento", assemblea: "Assemblea"};

/* ---------- Utilità ---------- */
const $ = s => document.querySelector(s);
const esc = v => String(v ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const todayISO = () => { const d = new Date(); return d.getFullYear() + "-" + String(d.getMonth()+1).padStart(2,"0") + "-" + String(d.getDate()).padStart(2,"0"); };
const asDate = iso => iso ? new Date(iso + "T12:00:00") : null;
const fmtLong = iso => { const d = asDate(iso); return d ? d.toLocaleDateString("it-IT", {weekday:"long", day:"numeric", month:"long"}) : ""; };
const fmtLongY = iso => { const d = asDate(iso); return d ? d.toLocaleDateString("it-IT", {weekday:"long", day:"numeric", month:"long", year:"numeric"}) : ""; };
const dayN = iso => { const d = asDate(iso); return d ? d.getDate() : "–"; };
const monS = iso => { const d = asDate(iso); return d ? d.toLocaleDateString("it-IT", {month:"short"}).replace(".", "") : ""; };
const fmtOra = o => o ? "ore " + o.replace(":", ".") : "";
const norm = n => String(n || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z ]/g, " ").split(/\s+/).filter(Boolean).sort().join(" ");
const soloCifre = t => String(t || "").replace(/\D/g, "").replace(/^0039/, "").replace(/^39(?=3\d{8,9}$)/, "");
const emailDaTel = t => soloCifre(t) + "@" + DOMINIO_FINTO;
const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : Date.now().toString(36) + Math.random().toString(36).slice(2));

function toast(msg) {
  const t = $("#toast"); t.innerHTML = '<div class="toast">' + esc(msg) + '</div>';
  clearTimeout(toast._t); toast._t = setTimeout(() => t.innerHTML = "", 3500);
}

/* =====================================================================
   Accesso ai dati: Supabase (vero) oppure memoria (prova)
   ===================================================================== */
const D = {}; // tabelle della modalità prova

const api = {
  async ins(tab, row) {
    if (S.live) { const {error} = await S.sb.from(tab).insert(row); if (error) throw error; }
    else { D[tab].push({id: uuid(), creato_il: new Date().toISOString(), ...row}); }
  },
  async upd(tab, id, patch) {
    if (S.live) { const {error} = await S.sb.from(tab).update(patch).eq("id", id); if (error) throw error; }
    else { const r = D[tab].find(x => x.id === id); if (r) Object.assign(r, patch); }
  },
  async del(tab, id) {
    if (S.live) { const {error} = await S.sb.from(tab).delete().eq("id", id); if (error) throw error; }
    else {
      D[tab] = D[tab].filter(x => x.id !== id);
      if (tab === "attivita" || tab === "assemblee") D.adesioni = D.adesioni.filter(a => a.attivita_id !== id);
    }
  },
  async rpc(fn, args) {
    if (S.live) { const {error} = await S.sb.rpc(fn, args); if (error) throw error; }
  },
  // Carica un'immagine nella cartella di chi la carica; le foto vengono ridotte a 1600 px
  async carica(file, riduci = true) {
    const blob = riduci ? await comprimi(file) : file;
    if (!S.live) return {url: URL.createObjectURL(blob), percorso: ""};
    const ext = blob.type === "image/jpeg" ? "jpg" : ((file.name.split(".").pop() || "img").toLowerCase().replace(/[^a-z0-9]/g, "") || "img");
    const percorso = `${S.myId}/${Date.now()}-${Math.random().toString(36).slice(2, 7)}.${ext}`;
    const {error} = await S.sb.storage.from("foto").upload(percorso, blob, {upsert: false, contentType: blob.type || file.type});
    if (error) throw error;
    return {url: S.sb.storage.from("foto").getPublicUrl(percorso).data.publicUrl, percorso};
  },
  async foto(file, riduci = true) { return (await api.carica(file, riduci)).url; },
  async togliFile(percorso) { if (S.live && percorso) { try { await S.sb.storage.from("foto").remove([percorso]); } catch (e) {} } }
};

async function comprimi(file, max = 1600, q = 0.82) {
  if (/svg|gif/.test(file.type)) return file;
  try {
    const bmp = await createImageBitmap(file, {imageOrientation: "from-image"});
    const k = Math.min(1, max / Math.max(bmp.width, bmp.height));
    const cv = document.createElement("canvas"); cv.width = Math.round(bmp.width * k); cv.height = Math.round(bmp.height * k);
    cv.getContext("2d").drawImage(bmp, 0, 0, cv.width, cv.height);
    return await new Promise(r => cv.toBlob(b => r(b || file), "image/jpeg", q));
  } catch (e) { return file; }
}

async function safe(fn, ok) {
  try { await fn(); await carica(); if (ok) toast(ok); return true; }
  catch (e) {
    const m = String(e && (e.message || e.details) || "");
    if (/row-level security|permission|Non puoi|Il direttivo|non può/i.test(m)) toast("Non hai il permesso per questa modifica.");
    else if (/duplicate key|una_adesione/i.test(m)) toast("Risulti già iscritto: modifica la tua iscrizione.");
    else if (/PIN/i.test(m)) toast(m);
    else toast("Non sono riuscito a salvare. Controlla la connessione e riprova.");
    console.error(e);
    return false;
  }
}

async function carica() {
  let att, ass, ades, post, imp, prof = [];
  if (S.live) {
    const q = t => S.sb.from(t).select("*");
    const r = await Promise.all([q("attivita"), q("assemblee"), q("adesioni"), q("bacheca"), q("impostazioni").eq("id", 1).maybeSingle(),
      S.sb.rpc("conteggi"), RANK[S.realRole] >= 2 ? q("profili").order("nome") : Promise.resolve({data: []}), q("foto").order("creato_il"),
      RANK[S.realRole] >= 2 ? q("tesserati").order("nome") : Promise.resolve({data: []})]);
    const err = r.find(x => x.error); if (err) throw err.error;
    [att, ass, ades, post, imp] = r.map(x => x.data);
    S.cont = {}; (r[5].data || []).forEach(c => S.cont[c.attivita_id] = c.persone);
    prof = r[6].data || []; S.foto = r[7].data || []; S.tesserati = r[8].data || [];
  } else {
    att = D.attivita; ass = D.assemblee; ades = D.adesioni; post = D.bacheca; imp = D.impostazioni[0]; prof = D.profili; S.foto = [...D.foto]; S.tesserati = [...(D.tesserati || [])];
    S.cont = {};
    ades.forEach(a => S.cont[a.attivita_id] = (S.cont[a.attivita_id] || 0) + (a.io ? 1 : 0) + (a.acc || []).length);
  }
  S.att = {}; (att || []).forEach(r => S.att[r.id] = r);
  S.ass = {}; (ass || []).forEach(r => S.ass[r.id] = r);
  S.ades = ades || [];
  S.post = {}; (post || []).forEach(r => S.post[r.id] = r);
  S.cfg = imp || {};
  S.profili = prof;
  S.loading = false; S.note = "";
  refresh();
}

/* ---------- Dati derivati ---------- */
const cfg = () => S.cfg || {};
function comeAttivita(a) {
  return {...a, tipo: "assemblea", titolo: "Assemblea " + (a.genere || "ordinaria") + " dei soci", data: a.prima_data, ora: a.prima_ora, ospiti: false, stato: a.stato === "annullata" ? "annullata" : "aperta"};
}
const attivita = () => Object.values(S.att).sort((a, b) => (a.data || "").localeCompare(b.data || ""));
const assemblee = () => Object.values(S.ass).map(comeAttivita).sort((a, b) => (a.data || "").localeCompare(b.data || ""));
const futuri = arr => { const t = todayISO(); return arr.filter(e => (e.data || "") >= t); };
const passati = arr => { const t = todayISO(); return arr.filter(e => (e.data || "") < t).reverse(); };
const trova = id => S.att[id] ? S.att[id] : S.ass[id] ? comeAttivita(S.ass[id]) : null;

function partecipanti(eid) {
  const out = S.ades.filter(a => a.attivita_id === eid).map(a => ({
    id: a.id, uid: a.user_id, fonte: a.user_id ? "app" : "man", nome: a.nome, io: a.io !== false,
    acc: a.acc || [], note: a.note || "", canale: a.canale || "App", quando: a.creato_il || ""
  })).sort((a, b) => (a.quando || "").localeCompare(b.quando || ""));
  const seen = {};
  out.forEach((p, i) => [...(p.io ? [p.nome] : []), ...p.acc.map(x => x.nome)].forEach(n => { const k = norm(n); if (k) (seen[k] ||= []).push({i, n}); }));
  out.forEach(p => p.dups = []);
  Object.values(seen).forEach(arr => { if (arr.length > 1) arr.forEach(({i, n}) => { if (!out[i].dups.includes(n)) out[i].dups.push(n); }); });
  return out;
}
const persone = p => (p.io ? 1 : 0) + (p.acc || []).length;
const totale = eid => S.cont[eid] || 0;
const mia = eid => S.myId ? S.ades.find(a => a.attivita_id === eid && a.user_id === S.myId) : null;
function aperta(e) {
  if (e.stato && e.stato !== "aperta") return false;
  if (e.scadenza && e.scadenza < todayISO()) return false;
  return true;
}

/* ---------- Grandezza del testo: normale, grande, molto grande ---------- */
const zoomOra = () => document.documentElement.classList.contains("bigger") ? 2 : document.documentElement.classList.contains("big") ? 1 : 0;
function impostaZoom(liv) {
  document.documentElement.classList.toggle("big", liv === 1);
  document.documentElement.classList.toggle("bigger", liv === 2);
}

/* ---------- Icone ---------- */
const I = {
  home:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 11l9-7 9 7"/><path d="M5 10v10h14V10"/><path d="M10 20v-6h4v6"/></svg>',
  bus:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="3" width="16" height="15" rx="3"/><path d="M4 11h16"/><path d="M7 18v3M17 18v3"/><circle cx="8" cy="14.5" r="1"/><circle cx="16" cy="14.5" r="1"/></svg>',
  people:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="8" r="3.2"/><path d="M3 20c0-3.3 2.7-6 6-6s6 2.7 6 6"/><circle cx="17" cy="9" r="2.6"/><path d="M16 14.2c2.8.3 5 2.6 5 5.8"/></svg>',
  mega:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 10v4h4l7 5V5L7 10H3z"/><path d="M18 8a5 5 0 0 1 0 8"/></svg>',
  key:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="15" r="4"/><path d="M11 12l9-9M17 6l3 3M14 9l2 2"/></svg>',
  fb:'<svg viewBox="0 0 24 24" fill="#1877F2"><path d="M24 12a12 12 0 1 0-13.9 11.9v-8.4H7.1V12h3V9.4c0-3 1.8-4.7 4.5-4.7 1.3 0 2.7.2 2.7.2v3h-1.5c-1.5 0-2 .9-2 1.9V12h3.4l-.5 3.5h-2.9v8.4A12 12 0 0 0 24 12z"/></svg>',
  ig:'<svg viewBox="0 0 24 24" fill="none" stroke="#D62976" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="5"/><circle cx="12" cy="12" r="4"/><circle cx="17.5" cy="6.5" r="1" fill="#D62976"/></svg>',
  wa:'<svg viewBox="0 0 24 24" fill="#25D366"><path d="M12 2a10 10 0 0 0-8.6 15.1L2 22l5-1.3A10 10 0 1 0 12 2zm5.3 14.1c-.2.6-1.3 1.2-1.8 1.2-.5.1-1 .2-3.3-.7-2.8-1.1-4.5-3.9-4.7-4.1-.1-.2-1.1-1.5-1.1-2.9s.7-2 1-2.3c.2-.3.5-.3.7-.3h.5c.2 0 .4 0 .6.5l.8 2c.1.2.1.4 0 .5l-.4.6-.4.4c-.1.1-.3.3-.1.6.2.3.8 1.3 1.7 2.1 1.2 1 2.1 1.4 2.4 1.5.3.1.5.1.6-.1l.9-1.1c.2-.3.4-.2.6-.1l1.9.9c.3.1.5.2.5.3.1.2.1.7-.1 1.4z"/></svg>'
};

/* =====================================================================
   Schermate
   ===================================================================== */
function refresh() { applyTheme(); render(); if (S.sheet && S.sheet.view) openView(S.sheet.kind, S.sheet.id, true); }

let temaAnteprima = null; // tema che il presidente sta provando, non ancora salvato
const temaOra = () => temaAnteprima || temaDa(cfg());
function applyTheme() { applicaTema(temaOra()); }

function testata(saluto, sotto, conRuolo) {
  const c = cfg();
  const conAcc = !c.logo && temaOra().logo;
  return `<header class="top${conAcc ? " con-acc" : ""}">${decoSvg(temaOra(), "h")}
    <div class="toprow">
      <div class="brand"><div class="logopill">${c.logo ? `<img alt="Auser" src="${esc(c.logo)}">` : logoSvg(temaOra())}<span class="sede">${esc(c.sede || "Gratteri")}</span></div></div>
      <button class="iconbtn zoom" data-act="big" aria-label="Grandezza del testo: ${["normale", "grande", "molto grande"][zoomOra()]}. Tocca per cambiarla"><span aria-hidden="true">A</span><span class="zd" aria-hidden="true">${[0, 1, 2].map(i => `<i class="${i <= zoomOra() ? "on" : ""}"></i>`).join("")}</span></button>
    </div>
    <div class="hello"><h1>${saluto}</h1><p>${esc(sotto)}</p>${conRuolo ? roleChip() : ""}</div>
  </header>`;
}

function render() {
  // Non ancora entrato
  if (S.live && !S.sessione) { $("#tabs").innerHTML = ""; $("#app").innerHTML = testata("Benvenuto in Auser", cfg().motto || "L'app dei soci.", false) + vAccesso(); return; }
  // Entrato ma non ancora approvato
  if (S.live && S.realRole === "lettore" && !S.loading) {
    $("#tabs").innerHTML = "";
    $("#app").innerHTML = testata("Ciao " + esc((S.myName || "").split(" ")[0]) + "!", "La tua richiesta è arrivata al direttivo.", false) +
      `<main><div class="box"><h3>In attesa di approvazione</h3><p style="margin:0">Il direttivo deve confermare che sei socio. Appena fatto, riapri l'app e trovi tutte le attività.</p>
      ${cfg().telefono ? `<p style="margin:0">Per fare prima chiama il <b>${esc(cfg().telefono)}</b>.</p>` : ""}
      <button class="btn ghost" data-act="ricarica">Ho già l'ok, riprova</button><button class="btn ghost" data-act="esci">Esci</button></div></main>`;
    return;
  }
  const nome = (S.myName || "").split(" ")[0];
  let body = "";
  if (S.tab === "home") body = vHome();
  if (S.tab === "attivita") body = vAttivita();
  if (S.tab === "assemblee") body = vAssemblee();
  if (S.tab === "bacheca") body = vBacheca();
  if (S.tab === "gestione") body = can("direttivo") ? vGestione() : vHome();
  $("#app").innerHTML = testata(nome ? "Ciao, " + esc(nome) + "!" : "Benvenuto in Auser", cfg().motto || "Le attività, le gite e le assemblee della nostra associazione.", true) + "<main>" + notes() + body + "</main>";
  const tabs = [["home","Home",I.home],["attivita","Gite",I.bus],["assemblee","Assemblee",I.people],["bacheca","Bacheca",I.mega]];
  if (can("direttivo")) tabs.push(["gestione","Gestione",I.key]);
  $("#tabs").innerHTML = barraAnteprima() + '<div class="wrap">' + tabs.map(([k,l,ic]) => `<button data-act="tab" data-v="${k}" ${S.tab===k?'aria-current="page"':""}>${ic}<span>${l}</span></button>`).join("") + "</div>";
}

function roleChip() {
  const multi = RANK[S.realRole] >= RANK.direttivo;
  return `<button class="rolechip" data-act="role" ${multi ? "" : "disabled"} aria-label="Ruolo: ${ROLES[S.viewRole]}${multi ? ". Tocca per vedere l'app come un altro ruolo" : ""}">
    ${I.people.replace("<svg", '<svg width="18" height="18"')} ${multi && S.viewRole !== S.realRole ? "Vista come: " : ""}${ROLES[S.viewRole]}${multi ? " ▾" : ""}</button>`;
}

function notes() {
  let h = "";
  if (S.loading) h += '<div class="banner">Carico le attività…</div>';
  if (S.note) h += '<div class="banner warn">' + esc(S.note) + "</div>";
  if (!S.live) h += '<div class="banner warn"><span><b>Modalità prova.</b> L\'app non è ancora collegata a Supabase: vedi dati di esempio e le modifiche non vengono salvate.</span></div>';
  if (S.viewRole !== S.realRole) h += '<div class="banner"><span>Stai vedendo l\'app come la vede il <b>' + esc(ROLES[S.viewRole].toLowerCase()) + "</b>. Tocca il ruolo in alto per tornare alla tua vista.</span></div>";
  return h;
}

/* ---------- Accesso e registrazione ---------- */
function vAccesso() {
  const e = S.authTab === "entra";
  return `<div class="auth">
    <div class="tabs2" role="group" aria-label="Accesso">
      <button class="chip" data-act="authtab" data-v="entra" aria-pressed="${e}">Entra</button>
      <button class="chip" data-act="authtab" data-v="registrati" aria-pressed="${!e}">Primo accesso</button>
    </div>
    <div class="box">
    ${e ? `<form id="fLogin">
        <label class="f">Numero di telefono<input type="tel" id="lTel" autocomplete="tel" inputmode="tel" required></label>
        <label class="f">PIN <span class="h">Le cifre che hai scelto alla registrazione</span><input type="password" id="lPin" inputmode="numeric" autocomplete="current-password" required></label>
        <p class="err" id="lErr" role="alert"></p>
        <button class="btn sun block" type="submit">Entra</button>
        <p class="meta" style="margin:0">Hai dimenticato il PIN? Chiedi al direttivo: te ne dà uno nuovo.</p>
      </form>` : `<form id="fReg">
        <label class="f">Nome e cognome<input type="text" id="rNome" autocomplete="name" required></label>
        <label class="f">Numero di telefono<input type="tel" id="rTel" autocomplete="tel" inputmode="tel" required></label>
        <label class="f">Scegli un PIN <span class="h">Almeno 6 cifre, facile da ricordare per te</span><input type="password" id="rPin" inputmode="numeric" autocomplete="new-password" minlength="6" required></label>
        <label class="f">Ripeti il PIN<input type="password" id="rPin2" inputmode="numeric" autocomplete="new-password" minlength="6" required></label>
        <p class="err" id="rErr" role="alert"></p>
        <button class="btn sun block" type="submit">Registrati</button>
        <p class="meta" style="margin:0">Se sei tesserato e usi il numero che hai dato all'Auser, entri subito. Altrimenti il direttivo conferma che sei socio. Il numero serve solo per entrare: non riceverai messaggi.</p>
      </form>`}
    </div></div>`;
}

async function entra(ev) {
  ev.preventDefault();
  const tel = soloCifre($("#lTel").value), pin = $("#lPin").value;
  if (tel.length < 6) { $("#lErr").textContent = "Controlla il numero di telefono."; return; }
  $("#lErr").textContent = "Entro…";
  const {error} = await S.sb.auth.signInWithPassword({email: emailDaTel(tel), password: pin});
  if (error) $("#lErr").textContent = "Numero o PIN non corretti. Se non ti sei mai registrato, scegli “Primo accesso”.";
}

async function registrati(ev) {
  ev.preventDefault();
  const nome = $("#rNome").value.trim(), tel = soloCifre($("#rTel").value), pin = $("#rPin").value;
  const out = m => $("#rErr").textContent = m;
  if (tel.length < 6) return out("Controlla il numero di telefono.");
  if (pin.length < 6) return out("Il PIN deve avere almeno 6 cifre.");
  if (pin !== $("#rPin2").value) return out("I due PIN non sono uguali.");
  out("Registro…");
  const {data, error} = await S.sb.auth.signUp({email: emailDaTel(tel), password: pin, options: {data: {nome, telefono: tel}}});
  if (error) return out(/registered|already/i.test(error.message) ? "Questo numero è già registrato: scegli “Entra”." : "Registrazione non riuscita: " + error.message);
  if (!data.session) return out("Registrazione ricevuta, ma Supabase chiede la conferma via email: il presidente deve disattivarla (vedi istruzioni).");
}

/* ---------- Card e pagine ---------- */
function card(e) {
  const tot = totale(e.id), m = mia(e.id);
  const posti = e.posti ? Number(e.posti) : 0;
  const pct = posti ? Math.min(100, Math.round(tot / posti * 100)) : 0;
  const stato = e.stato === "annullata" ? '<span class="pill no">Annullata</span>' : (!aperta(e) ? '<span class="pill">Iscrizioni chiuse</span>' : "");
  const mine = m ? '<span class="pill ok">✓ Iscritto' + ((m.acc || []).length ? " + " + m.acc.length : "") + "</span>" : "";
  return `<button class="card t-${e.tipo}" data-act="open" data-k="${e.tipo === "assemblea" ? "assemblea" : "evento"}" data-id="${e.id}">
    <div class="date"><b>${dayN(e.data)}</b><span>${monS(e.data)}</span></div>
    <div class="cbody">
      <div class="pills"><span class="pill ${e.tipo}">${TIPI[e.tipo] || "Attività"}</span>${stato}${mine}</div>
      <h3>${esc(e.titolo)}</h3>
      <div class="meta">${esc([fmtOra(e.ora), e.luogo].filter(Boolean).join(" · "))}</div>
      ${posti ? `<div class="bar ${tot >= posti ? "full" : ""}" role="img" aria-label="${tot} iscritti su ${posti} posti"><i style="width:${pct}%"></i></div><div class="meta">${tot} iscritti su ${posti} posti</div>` : (tot ? `<div class="meta">${tot} ${tot === 1 ? "persona iscritta" : "persone iscritte"}</div>` : "")}
    </div></button>`;
}

function hero(e) {
  const img = e.immagine, tot = totale(e.id);
  return `<button class="hero t-${e.tipo}" data-act="open" data-k="${e.tipo === "assemblea" ? "assemblea" : "evento"}" data-id="${e.id}">
    <div class="img ${img ? "photo" : ""}" ${img ? `style="background-image:url('${esc(img)}')"` : ""}><span class="count">${tot} ${tot === 1 ? "iscritto" : "iscritti"}</span></div>
    <div class="in"><div class="pills"><span class="pill ${e.tipo}">${TIPI[e.tipo]}</span>${mia(e.id) ? '<span class="pill ok">✓ Ci sei</span>' : ""}</div>
    <h3>${esc(e.titolo)}</h3>
    <div class="meta">${esc(fmtLong(e.data))}${e.ora ? ", " + esc(fmtOra(e.ora)) : ""}${e.luogo ? " · " + esc(e.luogo) : ""}</div></div></button>`;
}

function vHome() {
  const prossimi = futuri([...attivita(), ...assemblee()]).filter(e => e.stato !== "annullata").sort((a, b) => a.data.localeCompare(b.data));
  const first = prossimi[0];
  const posts = Object.values(S.post).sort((a, b) => (b.data || "").localeCompare(a.data || "")).slice(0, 2);
  const c = cfg();
  const soc = [["facebook","Facebook",I.fb],["instagram","Instagram",I.ig],["whatsapp","WhatsApp",I.wa]].filter(([k]) => c[k]);
  return `
  <section class="sec" aria-label="Prossimo appuntamento"><div class="sechead"><h2>Prossimo appuntamento</h2></div>
    ${first ? hero(first) : '<div class="empty">Nessun appuntamento in programma.</div>'}</section>
  ${prossimi.length > 1 ? `<section class="sec"><div class="sechead"><h2>In programma</h2><button class="link" data-act="tab" data-v="attivita">Vedi tutte</button></div>${prossimi.slice(1, 4).map(card).join("")}</section>` : ""}
  <section class="sec"><div class="sechead"><h2>Dalla bacheca</h2><button class="link" data-act="tab" data-v="bacheca">Apri bacheca</button></div>
    ${posts.length ? posts.map(postCard).join("") : '<div class="empty">Nessun avviso per ora.</div>'}</section>
  ${ultimeFoto()}
  ${soc.length ? `<section class="sec"><div class="sechead"><h2>Seguici</h2></div><div class="social">${soc.map(([k,l,ic]) => `<a class="sbtn" href="${esc(c[k])}" target="_blank" rel="noopener">${ic}${l}</a>`).join("")}</div></section>` : ""}
  <section class="sec"><div class="row"><button class="btn ghost" data-act="mio-pin">Cambia il mio PIN</button><button class="btn ghost" data-act="esci">Esci dall'app</button></div></section>`;
}

function vAttivita() {
  const f = S.filtro;
  const tipo = attivita().filter(e => f === "tutte" || e.tipo === f);
  const all = perAnnoScelto("att", tipo);
  const fut = futuri(all), pas = passati(all);
  return `<section class="sec">
    <div class="sechead"><h2>Gite ed eventi</h2>${can("direttivo") ? '<button class="btn sm" data-act="form-evento">+ Nuova</button>' : ""}</div>
    <div class="chips" role="group" aria-label="Filtra">${[["tutte","Tutte"],["gita","Gite"],["evento","Eventi"]].map(([k,l]) => `<button class="chip" data-act="filtro" data-v="${k}" aria-pressed="${f === k}">${l}</button>`).join("")}</div>
    ${filtroAnno("att", tipo)}
    ${fut.length ? fut.map(card).join("") : `<div class="empty">Nessuna attività in programma${S.anno.att && S.anno.att !== "tutti" ? " nel " + S.anno.att : ""}.</div>`}</section>
  ${perAnno(pas, "Già fatte", "att-pas")}`;
}

/* Filtro per anno: chip "Tutti", 2026, 2025… (chiave = sezione) */
function filtroAnno(chiave, lista) {
  const anni = [...new Set(lista.map(e => (e.data || "").slice(0, 4)).filter(Boolean))].sort().reverse();
  if (anni.length < 2) return "";
  const sel = S.anno[chiave] || "tutti";
  return `<div class="chips" role="group" aria-label="Anno">${["tutti", ...anni].map(a => `<button class="chip" data-act="anno" data-k="${chiave}" data-v="${a}" aria-pressed="${sel === a}">${a === "tutti" ? "Tutti gli anni" : a}</button>`).join("")}</div>`;
}
const perAnnoScelto = (chiave, lista) => { const a = S.anno[chiave] || "tutti"; return a === "tutti" ? lista : lista.filter(e => (e.data || "").startsWith(a)); };

/* Paginazione: N elementi per pagina, con pulsanti Precedenti / Successive */
function paginato(chiave, lista, perPagina, disegna) {
  const tot = Math.max(1, Math.ceil(lista.length / perPagina));
  const p = Math.min(Math.max(1, S.pagina[chiave] || 1), tot);
  const html = disegna(lista.slice((p - 1) * perPagina, p * perPagina));
  if (tot === 1) return html;
  return html + `<nav class="pager" aria-label="Pagine">
    <button class="btn ghost sm" data-act="pagina" data-k="${chiave}" data-v="${p - 1}" ${p === 1 ? "disabled" : ""}>‹ Precedenti</button>
    <span class="meta">Pagina ${p} di ${tot}</span>
    <button class="btn ghost sm" data-act="pagina" data-k="${chiave}" data-v="${p + 1}" ${p === tot ? "disabled" : ""}>Successive ›</button></nav>`;
}

/* Le attività passate, tutte, divise per anno (dal più recente) */
function perAnno(lista, titolo, chiave) {
  if (!lista.length) return "";
  const gruppi = pezzo => { let h = "", anno = "";
    pezzo.forEach(e => { const a = (e.data || "").slice(0, 4); if (a !== anno) { anno = a; h += `<h3 class="anno">${a}</h3>`; } h += card(e); }); return h; };
  return `<section class="sec" id="sez-${chiave}"><div class="sechead"><h2>${titolo}</h2><span class="meta">${lista.length}</span></div>
    ${paginato(chiave, lista, 8, gruppi)}</section>`;
}

function vAssemblee() {
  const tutte = assemblee(), all = perAnnoScelto("ass", tutte), fut = futuri(all), pas = passati(all);
  return `<section class="sec">
    <div class="sechead"><h2>Assemblee dei soci</h2>${can("presidente") ? '<button class="btn sm" data-act="form-assemblea">+ Convoca</button>' : ""}</div>
    ${filtroAnno("ass", tutte)}
    ${fut.length ? fut.map(card).join("") : '<div class="empty">Nessuna assemblea convocata.</div>'}</section>
  ${perAnno(pas, "Assemblee passate", "ass-pas")}`;
}

function postCard(p) {
  const lab = {avviso: "Avviso", facebook: "Facebook", instagram: "Instagram"}[p.tipo] || "Avviso";
  const d = p.data ? new Date(p.data).toLocaleDateString("it-IT", {day: "numeric", month: "long"}) : "";
  return `<article class="post">${p.immagine ? `<img src="${esc(p.immagine)}" alt="">` : ""}
    <div class="in"><div class="pills"><span class="pill ${p.tipo === "avviso" ? "warn" : ""}">${lab}</span><span class="pill">${esc(d)}</span></div>
    ${p.titolo ? `<h3>${esc(p.titolo)}</h3>` : ""}<p>${esc(p.testo)}</p>
    <div class="foot">${p.link ? `<a href="${esc(p.link)}" target="_blank" rel="noopener">Apri ${p.tipo === "instagram" ? "su Instagram" : p.tipo === "facebook" ? "su Facebook" : "il link"} →</a>` : "<span></span>"}
    ${can("direttivo") ? `<button class="btn ghost sm" data-act="form-post" data-id="${p.id}">Modifica</button>` : ""}</div></div></article>`;
}

function vBacheca() {
  const posts = Object.values(S.post).sort((a, b) => (b.data || "").localeCompare(a.data || ""));
  const g = S.bvista === "gallerie";
  return `<section class="sec"><div class="sechead"><h2>Bacheca</h2>${can("direttivo") && !g ? '<button class="btn sm" data-act="form-post">+ Pubblica</button>' : ""}</div>
    <div class="chips" role="group" aria-label="Mostra">
      <button class="chip" data-act="bvista" data-v="avvisi" aria-pressed="${!g}">Avvisi</button>
      <button class="chip" data-act="bvista" data-v="gallerie" aria-pressed="${g}">Gallerie foto${S.foto.length ? " · " + S.foto.length : ""}</button></div>
    ${g ? vGallerie() : posts.length ? `<div id="sez-avv">${paginato("avv", posts, 10, l => l.map(postCard).join(""))}</div>` : '<div class="empty">Nessun avviso pubblicato.</div>'}</section>`;
}

function vGestione() {
  const fut = futuri(attivita()).filter(e => e.stato !== "annullata");
  const iscr = fut.reduce((s, e) => s + totale(e.id), 0);
  const attesa = S.profili.filter(p => p.ruolo === "in_attesa");
  const Y = '<span class="yes">✓</span>', N = '<span class="nope">–</span>';
  const rows = [["Leggere attività e bacheca",Y,Y,Y],["Iscriversi con familiari e amici",Y,Y,Y],["Creare e modificare gite ed eventi",Y,Y,N],
    ["Gestire i partecipanti di tutti",Y,Y,N],["Pubblicare in bacheca",Y,Y,N],["Approvare i nuovi soci",Y,Y,N],["Convocare le assemblee",Y,N,N],
    ["Pubblicare foto nelle gallerie",Y,Y,Y],["Togliere le foto degli altri",Y,Y,N],["Nominare il direttivo",Y,N,N],["Eliminare attività",Y,N,N],["Tema, logo e social",Y,N,N]];
  return `
  <section class="sec"><div class="sechead"><h2>Riepilogo</h2></div>
    <div class="stats">
      <div class="stat"><b>${fut.length}</b><span>attività in programma</span></div>
      <div class="stat"><b>${iscr}</b><span>persone iscritte</span></div>
      <div class="stat"><b>${attesa.length}</b><span>soci da approvare</span></div>
    </div></section>
  <section class="sec"><div class="sechead"><h2>Crea</h2></div>
    <div class="row">
      <button class="btn sun" data-act="form-evento">+ Gita o evento</button>
      <button class="btn" data-act="form-post">+ Avviso in bacheca</button>
      ${can("presidente") ? '<button class="btn" data-act="form-assemblea">+ Convoca assemblea</button>' : ""}
      <button class="btn ghost" data-act="soci">Soci${attesa.length ? " (" + attesa.length + " nuovi)" : ""}</button>
      ${can("presidente") ? '<button class="btn ghost" data-act="temi">Tema dell\'app</button><button class="btn ghost" data-act="form-config">Logo, nome e social</button>' : ""}
    </div></section>
  <section class="sec"><div class="sechead"><h2>Partecipanti da controllare</h2></div>
    ${fut.length ? fut.map(card).join("") : '<div class="empty">Nessuna attività aperta.</div>'}</section>
  <section class="sec"><div class="sechead"><h2>Chi può fare cosa</h2></div>
    <div class="box" style="overflow-x:auto"><table class="perm"><thead><tr><th scope="col"></th><th scope="col">Presidente</th><th scope="col">Direttivo</th><th scope="col">Socio</th></tr></thead>
    <tbody>${rows.map(r => `<tr><td>${r[0]}</td><td>${r[1]}</td><td>${r[2]}</td><td>${r[3]}</td></tr>`).join("")}</tbody></table></div></section>`;
}

/* ---------- Fogli (finestre dal basso) ---------- */
function sheet(title, inner, opts = {}) {
  S.sheet = opts.state || null;
  $("#sheet").innerHTML = `<div class="scrim" data-act="scrim"><div class="sheet" role="dialog" aria-modal="true" aria-labelledby="shT">
    <div class="sheethead"><h2 id="shT">${esc(title)}</h2><button class="close" data-act="close">Chiudi</button></div>
    <div class="sheetbody">${inner}</div></div></div>`;
  document.body.style.overflow = "hidden";
}
function closeSheet() { $("#sheet").innerHTML = ""; S.sheet = null; document.body.style.overflow = ""; }
function nomeAnteprima() {
  const k = S.temaScelto;
  if (k === "__bozza") return "il tuo tema personalizzato";
  if (k === "automatico") return "Automatico";
  if (k === "personalizzato") return "il tuo tema";
  return (TEMI[k] || {}).nome || "un nuovo tema";
}
function barraAnteprima() {
  if (!temaAnteprima) return "";
  return `<div class="anteprima" role="region" aria-label="Prova del tema"><span>Stai provando <b>${esc(nomeAnteprima())}</b>: lo vedi solo tu.</span>
    <div class="row"><button class="btn sun sm" data-act="salva-tema">Usa questo tema</button><button class="btn ghost sm" data-act="annulla-tema">Annulla</button><button class="btn ghost sm" data-act="temi">Altri temi</button></div></div>`;
}

function openView(kind, id, keepScroll) {
  const sc = keepScroll ? $(".sheet")?.scrollTop : 0;
  if (kind === "soci") { sheet("Soci", vSoci(), {state: {view: true, kind: "soci"}}); }
  else if (kind === "temi") { sheet("Tema dell'app", vTemi(), {state: {view: true, kind: "temi"}}); }
  else if (kind === "galleria") { const e = trova(id); if (!e) return closeSheet(); sheet("Foto · " + e.titolo, vGalleria(e), {state: {view: true, kind, id}}); }
  else {
    const e = trova(id); if (!e) { closeSheet(); return; }
    sheet(e.titolo, kind === "evento" ? vEvento(e) : vAssemblea(e), {state: {view: true, kind, id}});
  }
  if (keepScroll && $(".sheet")) $(".sheet").scrollTop = sc;
}

function myBox(e) {
  const m = mia(e.id), isAss = e.tipo === "assemblea";
  if (e.stato === "annullata") return `<div class="box"><h3>Attività annullata</h3></div>`;
  if (m) {
    const n = persone({io: m.io !== false, acc: m.acc || []});
    return `<div class="box"><div class="pills"><span class="pill ok">✓ ${isAss ? "Presenza confermata" : "Sei iscritto"}</span></div>
      <div class="total">${n} ${n === 1 ? "persona" : "persone"}</div>
      ${(m.acc || []).length ? `<div class="meta">Con te: ${m.acc.map(a => esc(a.nome)).join(", ")}</div>` : ""}
      ${aperta(e) ? `<div class="row"><button class="btn ghost" data-act="form-adesione" data-id="${e.id}" data-mode="mia">Modifica</button><button class="btn danger" data-act="annulla-mia" data-id="${e.id}" data-ref="${m.id}">Non vengo più</button></div>` : '<div class="meta">Le iscrizioni sono chiuse: per cambiare qualcosa chiama il direttivo.</div>'}
    </div>`;
  }
  if (!aperta(e)) return `<div class="box"><h3>Iscrizioni chiuse</h3><p style="margin:0" class="meta">Per informazioni chiama il direttivo${cfg().telefono ? " al " + esc(cfg().telefono) : ""}.</p></div>`;
  const pieno = e.posti && totale(e.id) >= Number(e.posti);
  return `<button class="btn sun block" data-act="form-adesione" data-id="${e.id}" data-mode="mia" ${pieno ? "disabled" : ""}>${pieno ? "Posti esauriti" : isAss ? "Confermo la mia presenza" : "Partecipo"}</button>
    ${pieno ? '<div class="meta">Chiama il direttivo per la lista d\'attesa.</div>' : ""}`;
}

function gestionePartecipanti(e) {
  if (!can("direttivo")) return "";
  const ps = partecipanti(e.id), tot = ps.reduce((s, p) => s + persone(p), 0);
  const dup = ps.filter(p => p.dups.length);
  return `<div class="box"><h3>Partecipanti · ${tot}${e.posti ? " su " + esc(e.posti) : ""}</h3>
    ${dup.length ? `<div class="banner warn"><span><b>Possibili doppioni:</b> ${[...new Set(dup.flatMap(p => p.dups))].map(esc).join(", ")}. Controlla e togli il nome ripetuto.</span></div>` : ""}
    <div class="plist">${ps.length ? ps.map(p => `<div class="prow ${p.dups.length ? "dup" : ""}">
      <div class="who"><span class="n">${esc(p.nome)}${p.io ? "" : " <small>(non partecipa)</small>"}</span>
        ${p.acc.length ? `<small>Con: ${p.acc.map(a => esc(a.nome) + (a.rel ? " (" + esc(a.rel.toLowerCase()) + ")" : "")).join(", ")}</small>` : ""}
        ${p.note ? `<small>Nota: ${esc(p.note)}</small>` : ""}
        <span class="pills"><span class="pill">${esc(p.canale)}</span>${p.dups.length ? '<span class="pill warn">Doppione?</span>' : ""}</span></div>
      <span class="num">${persone(p)}</span>
      <button class="btn ghost sm" data-act="form-adesione" data-id="${e.id}" data-mode="altro" data-ref="${p.id}" aria-label="Modifica ${esc(p.nome)}">Modifica</button>
    </div>`).join("") : '<div class="empty">Ancora nessun iscritto.</div>'}</div>
    <div class="row"><button class="btn" data-act="form-adesione" data-id="${e.id}" data-mode="nuovo">+ Aggiungi partecipante</button>
    <button class="btn ghost" data-act="copia-lista" data-id="${e.id}">Copia elenco</button></div>
    <div class="meta">Aggiungi qui chi si iscrive su WhatsApp, al telefono o di persona.</div></div>`;
}

function vEvento(e) {
  return `${e.immagine ? `<img class="imgprev" style="max-height:420px;width:100%;object-fit:contain;background:var(--soft)" src="${esc(e.immagine)}" alt="Locandina: ${esc(e.titolo)}">` : ""}
  <div class="pills"><span class="pill ${e.tipo}">${TIPI[e.tipo]}</span>${e.stato === "annullata" ? '<span class="pill no">Annullata</span>' : !aperta(e) ? '<span class="pill">Iscrizioni chiuse</span>' : '<span class="pill ok">Iscrizioni aperte</span>'}</div>
  <div class="box"><dl class="kv">
    <dt>Quando</dt><dd>${esc(fmtLongY(e.data))}${e.ora ? ", " + esc(fmtOra(e.ora)) : ""}</dd>
    ${e.luogo ? `<dt>Dove</dt><dd>${esc(e.luogo)}</dd>` : ""}
    ${e.ritrovo ? `<dt>Ritrovo</dt><dd>${esc(e.ritrovo)}</dd>` : ""}
    ${e.costo ? `<dt>Quota</dt><dd>${esc(e.costo)}</dd>` : ""}
    ${e.posti ? `<dt>Posti</dt><dd>${totale(e.id)} su ${esc(e.posti)}</dd>` : ""}
    ${e.scadenza ? `<dt>Iscrizioni entro</dt><dd>${esc(fmtLong(e.scadenza))}</dd>` : ""}
  </dl></div>
  ${e.descrizione || e.programma ? `<div class="box">${e.descrizione ? `<p class="prog">${esc(e.descrizione)}</p>` : ""}${e.programma ? `<h3>Programma</h3><p class="prog">${esc(e.programma)}</p>` : ""}</div>` : ""}
  ${myBox(e)}
  ${boxFoto(e)}
  ${gestionePartecipanti(e)}
  ${can("direttivo") ? `<div class="row"><button class="btn ghost" data-act="form-evento" data-id="${e.id}">Modifica attività</button><button class="btn ghost" data-act="copia-evento" data-id="${e.id}">Copia annuncio per WhatsApp</button></div>` : ""}
  ${can("presidente") ? `<button class="btn danger" data-act="elimina" data-tab="attivita" data-id="${e.id}">Elimina attività</button>` : ""}`;
}

function vAssemblea(a) {
  const r = S.ass[a.id] || {};
  return `<div class="pills"><span class="pill assemblea">Assemblea ${esc(r.genere || "ordinaria")}</span>${r.stato === "annullata" ? '<span class="pill no">Annullata</span>' : ""}</div>
  <div class="box"><dl class="kv">
    <dt>Prima convocazione</dt><dd>${esc(fmtLongY(r.prima_data))}${r.prima_ora ? ", " + esc(fmtOra(r.prima_ora)) : ""}</dd>
    ${r.seconda_data ? `<dt>Seconda convocazione</dt><dd>${esc(fmtLongY(r.seconda_data))}${r.seconda_ora ? ", " + esc(fmtOra(r.seconda_ora)) : ""}</dd>` : ""}
    ${r.luogo ? `<dt>Luogo</dt><dd>${esc(r.luogo)}</dd>` : ""}
  </dl></div>
  ${(r.odg || []).length ? `<div class="box"><h3>Ordine del giorno</h3><ol class="odg">${r.odg.map(x => `<li>${esc(x)}</li>`).join("")}</ol></div>` : ""}
  ${r.note ? `<div class="box"><p class="prog">${esc(r.note)}</p></div>` : ""}
  ${myBox(a)}
  ${gestionePartecipanti(a)}
  ${can("direttivo") ? `<button class="btn ghost" data-act="copia-conv" data-id="${a.id}">Copia convocazione per WhatsApp</button>` : ""}
  ${can("presidente") ? `<div class="row"><button class="btn ghost" data-act="form-assemblea" data-id="${a.id}">Modifica</button><button class="btn danger" data-act="elimina" data-tab="assemblee" data-id="${a.id}">Elimina</button></div>` : ""}
  <p class="meta" style="margin:0">La convocazione ufficiale segue le modalità previste dallo statuto. Qui la trovi sempre a portata di mano.</p>`;
}

/* ---------- Soci e ruoli ---------- */
function vSoci() {
  const pres = can("presidente");
  const gruppi = [["in_attesa","Da approvare"],["direttivo","Direttivo"],["socio","Soci"],["presidente","Presidente"]];
  return gruppi.map(([r, t]) => {
    const ps = S.profili.filter(p => p.ruolo === r);
    if (!ps.length && r !== "in_attesa") return "";
    return `<div class="box"><h3>${t} · ${ps.length}</h3><div class="plist">${ps.length ? ps.map(p => `
      <div class="prow col"><div class="who"><span class="n">${esc(p.nome || "Senza nome")}</span><small>${esc(p.telefono)}</small></div>
      <div class="row">
        ${r === "in_attesa" ? `<button class="btn sm" data-act="ruolo" data-id="${p.id}" data-v="socio">Approva</button><button class="btn danger sm" data-act="rifiuta" data-id="${p.id}">Rifiuta</button>` : ""}
        ${pres && r === "socio" ? `<button class="btn ghost sm" data-act="ruolo" data-id="${p.id}" data-v="direttivo">Nel direttivo</button>` : ""}
        ${pres && r === "direttivo" ? `<button class="btn ghost sm" data-act="ruolo" data-id="${p.id}" data-v="socio">Togli dal direttivo</button>` : ""}
        ${r !== "presidente" && (pres || r !== "direttivo") ? `<button class="btn ghost sm" data-act="pin" data-id="${p.id}">Nuovo PIN</button>` : ""}
      </div></div>`).join("") : '<div class="empty">Nessuna richiesta.</div>'}</div></div>`;
  }).join("") + vTesserati() + `<p class="meta" style="margin:0">Chi non usa lo smartphone non serve registrarlo: lo aggiungi direttamente tra i partecipanti di ogni gita.</p>`;
}

/* Tesserati: chi si registra con uno di questi numeri entra subito come socio */
function vTesserati() {
  const registrati = new Set(S.profili.map(p => soloCifre(p.telefono)).filter(Boolean));
  const ts = [...(S.tesserati || [])].sort((a, b) => a.nome.localeCompare(b.nome));
  const dentro = ts.filter(t => registrati.has(soloCifre(t.telefono)));
  const fuori = ts.filter(t => !registrati.has(soloCifre(t.telefono)));
  const riga = t => `<div class="prow"><div class="who"><span class="n">${esc(t.nome)}</span><small>${esc(t.telefono || "senza telefono")}</small></div>
    <button class="btn ghost sm" data-act="togli-tesserato" data-id="${t.id}" aria-label="Togli ${esc(t.nome)} dall'elenco">Togli</button></div>`;
  return `<div class="box"><h3>Tesserati ${new Date().getFullYear()} · ${ts.length}</h3>
    <p class="meta" style="margin:0">Chi si registra con il numero che è in questo elenco entra subito come socio, senza aspettare l'approvazione.</p>
    <div class="stats" style="grid-template-columns:1fr 1fr"><div class="stat"><b>${dentro.length}</b><span>già nell'app</span></div><div class="stat"><b>${fuori.length}</b><span>da invitare</span></div></div>
    ${fuori.length ? `<details><summary class="link" style="display:inline-block">Chi non si è ancora registrato</summary><div class="plist" style="margin-top:8px">${fuori.map(riga).join("")}</div></details>` : ""}
    <form id="fTess" class="box" style="padding:12px">
      <b>Aggiungi un tesserato</b>
      <div class="two"><label class="f">Nome e cognome<input type="text" id="tsNome" required></label><label class="f">Telefono<input type="tel" id="tsTel" inputmode="tel"></label></div>
      <button class="btn sm" type="submit">Aggiungi</button></form></div>`;
}

function formPin(id) {
  const p = S.profili.find(x => x.id === id) || {};
  sheet("Nuovo PIN", `<form id="fPin"><p style="margin:0">Scegli un nuovo PIN per <b>${esc(p.nome)}</b> e diglielo a voce o per telefono.</p>
    <label class="f">Nuovo PIN <span class="h">Almeno 6 cifre</span><input type="text" id="pPin" inputmode="numeric" minlength="6" required></label>
    <button class="btn sun block" type="submit">Salva il PIN</button></form>`);
  $("#fPin").addEventListener("submit", async ev => {
    ev.preventDefault();
    if (await safe(() => api.rpc("reimposta_pin", {utente: id, pin: $("#pPin").value.trim()}), "PIN cambiato")) openView("soci");
  });
}

/* ---------- Ognuno può cambiare il proprio PIN ---------- */
function formMioPin() {
  sheet("Cambia il tuo PIN", `<form id="fMioPin">
    <label class="f">Nuovo PIN <span class="h">Almeno 6 cifre</span><input type="password" id="mp1" inputmode="numeric" autocomplete="new-password" minlength="6" required></label>
    <label class="f">Ripeti il nuovo PIN<input type="password" id="mp2" inputmode="numeric" autocomplete="new-password" minlength="6" required></label>
    <p class="err" id="mpErr" role="alert"></p>
    <button class="btn sun block" type="submit">Salva il nuovo PIN</button></form>`);
  $("#fMioPin").addEventListener("submit", async ev => {
    ev.preventDefault();
    const a = $("#mp1").value, b = $("#mp2").value, out = m => $("#mpErr").textContent = m;
    if (a.length < 6) return out("Il PIN deve avere almeno 6 cifre.");
    if (a !== b) return out("I due PIN non sono uguali.");
    if (!S.live) { toast("In modalità prova il PIN non si cambia davvero."); return closeSheet(); }
    out("Salvo…");
    const {error} = await S.sb.auth.updateUser({password: a});
    if (error) return out(/same|different/i.test(error.message) ? "È uguale a quello di prima: scegline uno diverso." : "Non sono riuscito a cambiarlo: " + error.message);
    closeSheet(); toast("PIN cambiato. Dalla prossima volta entra con quello nuovo.");
  });
}

/* ---------- Form adesione ---------- */
function formAdesione(eid, mode, ref) {
  const e = trova(eid); if (!e) return;
  const ospiti = e.tipo !== "assemblea" && e.ospiti !== false;
  let cur = {nome: "", io: true, acc: [], note: "", canale: "WhatsApp"}, id = null;
  if (mode === "mia") { const m = mia(eid); if (m) { cur = {...cur, ...m, acc: [...(m.acc || [])]}; id = m.id; } else cur.nome = S.myName; }
  if (mode === "altro") { const m = S.ades.find(a => a.id === ref) || {}; cur = {...cur, ...m, acc: [...(m.acc || [])]}; id = m.id; }
  const manuale = mode === "nuovo" || (mode === "altro" && !cur.user_id);
  const title = mode === "mia" ? (e.tipo === "assemblea" ? "Conferma presenza" : "La tua iscrizione") : mode === "nuovo" ? "Aggiungi partecipante" : "Modifica partecipante";
  sheet(title, `<form id="fA">
    <div class="meta">${esc(e.titolo)} · ${esc(fmtLong(e.data))}</div>
    <label class="f">${mode === "mia" ? "Il tuo nome e cognome" : "Nome e cognome del socio"}<input type="text" id="aNome" required autocomplete="name" value="${esc(cur.nome)}"></label>
    ${manuale ? `<label class="f">Come si è iscritto<select id="aCanale">${["WhatsApp","Telefono","Di persona","Altro"].map(c => `<option ${cur.canale === c ? "selected" : ""}>${c}</option>`).join("")}</select></label>` : ""}
    ${ospiti ? `<label class="check"><input type="checkbox" id="aIo" ${cur.io !== false ? "checked" : ""}> ${mode === "mia" ? "Partecipo anch'io" : "Partecipa anche il socio"}</label>
    <div class="f" style="display:flex;flex-direction:column;gap:8px"><b>Familiari o amici che vengono</b>
      <div class="stepper"><button type="button" data-act="acc-" aria-label="Uno in meno">−</button><output id="aN" aria-live="polite">${cur.acc.length}</output><button type="button" data-act="acc+" aria-label="Uno in più">+</button></div>
      <span class="meta">Scrivi il nome di ognuno: ci serve solo per non contare due volte la stessa persona.</span>
      <div id="aAcc" style="display:flex;flex-direction:column;gap:8px"></div></div>` : ""}
    <label class="f">Note <span class="h">Per esempio: posto davanti sul pullman, intolleranze</span><input type="text" id="aNote" value="${esc(cur.note)}"></label>
    <div class="total" id="aTot"></div>
    <button class="btn sun block" type="submit">${mode === "mia" ? "Conferma" : "Salva"}</button>
    ${mode === "altro" ? `<button class="btn danger block" type="button" data-act="rimuovi-part" data-id="${eid}" data-ref="${id}">Togli dall'elenco</button>` : ""}
  </form>`);
  const box = $("#aAcc");
  function tot() { const n = Number($("#aN")?.textContent || 0), io = $("#aIo") ? $("#aIo").checked : true, t = n + (io ? 1 : 0); $("#aTot").textContent = "Totale: " + t + " " + (t === 1 ? "persona" : "persone"); }
  function rows(n) {
    if (!box) return;
    const vals = [...box.querySelectorAll(".acc")].map(r => ({nome: r.querySelector("input").value, rel: r.querySelector("select").value}));
    const data = vals.length ? vals : cur.acc;
    let h = "";
    for (let i = 0; i < n; i++) {
      const a = data[i] || {nome: "", rel: "Familiare"};
      h += `<div class="acc"><input type="text" aria-label="Nome accompagnatore ${i + 1}" placeholder="Nome e cognome" value="${esc(a.nome)}" required>
      <select aria-label="Chi è"><option ${a.rel === "Familiare" ? "selected" : ""}>Familiare</option><option ${a.rel === "Amico" ? "selected" : ""}>Amico</option></select></div>`;
    }
    box.innerHTML = h; $("#aN").textContent = n; tot();
  }
  formAdesione.rows = rows;
  if (box) rows(cur.acc.length); else tot();
  $("#aIo")?.addEventListener("change", tot);
  $("#fA").addEventListener("submit", async ev => {
    ev.preventDefault();
    const nome = $("#aNome").value.trim(); if (!nome) return;
    const acc = box ? [...box.querySelectorAll(".acc")].map(r => ({nome: r.querySelector("input").value.trim(), rel: r.querySelector("select").value})).filter(a => a.nome) : [];
    const io = $("#aIo") ? $("#aIo").checked : true;
    if (!io && !acc.length) { toast("Indica almeno una persona che partecipa."); return; }
    const row = {nome, io, acc, note: $("#aNote").value.trim()};
    if (manuale) row.canale = $("#aCanale").value;
    let fn;
    if (id) fn = () => api.upd("adesioni", id, row);
    else if (mode === "mia") fn = () => api.ins("adesioni", {...row, attivita_id: eid, user_id: S.myId, canale: "App"});
    else fn = () => api.ins("adesioni", {...row, attivita_id: eid, user_id: null});
    if (await safe(fn, mode === "mia" ? "Iscrizione salvata. Grazie!" : "Partecipante salvato")) openView(e.tipo === "assemblea" ? "assemblea" : "evento", eid);
  });
}

/* ---------- Form attività ---------- */
let fotoNuova = null;
function campoFoto(url) {
  return `<div class="f" style="display:flex;flex-direction:column;gap:8px"><b>Foto</b>
    <img class="imgprev" id="imgP" alt="" ${url ? `src="${esc(url)}"` : "hidden"}>
    <input type="file" id="imgF" accept="image/*"><span class="meta" id="imgS"></span></div>`;
}
function bindFoto(riduci = true) {
  fotoNuova = null;
  $("#imgF")?.addEventListener("change", async () => {
    const file = $("#imgF").files[0]; if (!file) return;
    $("#imgS").textContent = "Carico la foto…";
    try { fotoNuova = await api.foto(file, riduci); $("#imgP").src = fotoNuova; $("#imgP").hidden = false; $("#imgS").textContent = "Foto pronta."; }
    catch (e) { $("#imgS").textContent = "Non sono riuscito a caricare la foto. Prova con un'immagine più piccola."; }
  });
}

function formEvento(id) {
  const e = id ? {...S.att[id]} : {tipo: "gita", stato: "aperta", ospiti: true};
  sheet(id ? "Modifica attività" : "Nuova gita o evento", `<form id="fE">
    <div class="chips" role="group" aria-label="Tipo">${["gita","evento"].map(t => `<button type="button" class="chip" data-act="tipo" data-v="${t}" aria-pressed="${e.tipo === t}">${TIPI[t]}</button>`).join("")}</div>
    <label class="f">Titolo<input type="text" id="eT" required value="${esc(e.titolo)}" placeholder="Gita a Cefalù"></label>
    <div class="two"><label class="f">Data<input type="date" id="eD" required value="${esc(e.data)}"></label><label class="f">Ora<input type="time" id="eO" value="${esc(e.ora)}"></label></div>
    <label class="f">Luogo<input type="text" id="eL" value="${esc(e.luogo)}"></label>
    <label class="f">Ritrovo <span class="h">Dove e quando ci si vede per partire</span><input type="text" id="eR" value="${esc(e.ritrovo)}"></label>
    <div class="two"><label class="f">Quota<input type="text" id="eC" value="${esc(e.costo)}" placeholder="25 € a persona"></label>
    <label class="f">Posti <span class="h">Vuoto = senza limite</span><input type="number" min="0" id="eP" value="${esc(e.posti)}"></label></div>
    <label class="f">Iscrizioni entro<input type="date" id="eS" value="${esc(e.scadenza)}"></label>
    <label class="f">Descrizione<textarea id="eDe">${esc(e.descrizione)}</textarea></label>
    <label class="f">Programma <span class="h">Una riga per orario</span><textarea id="ePr">${esc(e.programma)}</textarea></label>
    <label class="check"><input type="checkbox" id="eOs" ${e.ospiti !== false ? "checked" : ""}> I soci possono portare familiari e amici</label>
    <label class="f">Stato<select id="eSt">${[["aperta","Iscrizioni aperte"],["chiusa","Iscrizioni chiuse"],["annullata","Annullata"]].map(([k,l]) => `<option value="${k}" ${e.stato === k ? "selected" : ""}>${l}</option>`).join("")}</select></label>
    ${campoFoto(e.immagine)}
    <button class="btn sun block" type="submit">Salva</button></form>`);
  let tipo = e.tipo;
  $("#fE").addEventListener("click", ev => { const b = ev.target.closest('[data-act="tipo"]'); if (!b) return; tipo = b.dataset.v; $("#fE").querySelectorAll('[data-act="tipo"]').forEach(x => x.setAttribute("aria-pressed", x === b)); });
  bindFoto();
  $("#fE").addEventListener("submit", async ev => {
    ev.preventDefault();
    const row = {tipo, titolo: $("#eT").value.trim(), data: $("#eD").value, ora: $("#eO").value, luogo: $("#eL").value.trim(), ritrovo: $("#eR").value.trim(),
      costo: $("#eC").value.trim(), posti: $("#eP").value ? Number($("#eP").value) : null, scadenza: $("#eS").value || null,
      descrizione: $("#eDe").value.trim(), programma: $("#ePr").value.trim(), ospiti: $("#eOs").checked, stato: $("#eSt").value,
      immagine: fotoNuova || e.immagine || ""};
    const nid = id || uuid();
    if (await safe(() => id ? api.upd("attivita", id, row) : api.ins("attivita", {...row, id: nid}), "Attività salvata")) openView("evento", nid);
  });
}

/* ---------- Form assemblea ---------- */
function formAssemblea(id) {
  const a = id ? {...S.ass[id]} : {genere: "ordinaria", odg: ["Approvazione del bilancio", "Programma delle attività", "Varie ed eventuali"]};
  sheet(id ? "Modifica convocazione" : "Convoca l'assemblea", `<form id="fS">
    <label class="f">Tipo<select id="sG"><option value="ordinaria" ${a.genere === "ordinaria" ? "selected" : ""}>Ordinaria</option><option value="straordinaria" ${a.genere === "straordinaria" ? "selected" : ""}>Straordinaria</option></select></label>
    <div class="two"><label class="f">Prima convocazione<input type="date" id="s1d" required value="${esc(a.prima_data)}"></label><label class="f">Ora<input type="time" id="s1o" value="${esc(a.prima_ora)}"></label></div>
    <div class="two"><label class="f">Seconda convocazione<input type="date" id="s2d" value="${esc(a.seconda_data)}"></label><label class="f">Ora<input type="time" id="s2o" value="${esc(a.seconda_ora)}"></label></div>
    <label class="f">Luogo<input type="text" id="sL" required value="${esc(a.luogo)}" placeholder="Sede Auser, Gratteri"></label>
    <label class="f">Ordine del giorno <span class="h">Un punto per riga</span><textarea id="sO">${esc((a.odg || []).join("\n"))}</textarea></label>
    <label class="f">Note<textarea id="sN" placeholder="Per esempio: possono votare i soci in regola con la tessera.">${esc(a.note)}</textarea></label>
    <label class="f">Stato<select id="sSt"><option value="convocata" ${a.stato !== "annullata" ? "selected" : ""}>Convocata</option><option value="annullata" ${a.stato === "annullata" ? "selected" : ""}>Annullata</option></select></label>
    <button class="btn sun block" type="submit">Salva convocazione</button></form>`);
  $("#fS").addEventListener("submit", async ev => {
    ev.preventDefault();
    const row = {genere: $("#sG").value, prima_data: $("#s1d").value, prima_ora: $("#s1o").value, seconda_data: $("#s2d").value || null, seconda_ora: $("#s2o").value,
      luogo: $("#sL").value.trim(), odg: $("#sO").value.split("\n").map(s => s.trim()).filter(Boolean), note: $("#sN").value.trim(), stato: $("#sSt").value};
    const nid = id || uuid();
    if (await safe(() => id ? api.upd("assemblee", id, row) : api.ins("assemblee", {...row, id: nid}), "Convocazione salvata")) openView("assemblea", nid);
  });
}

/* ---------- Form bacheca ---------- */
function formPost(id) {
  const p = id ? {...S.post[id]} : {tipo: "avviso"};
  sheet(id ? "Modifica avviso" : "Pubblica in bacheca", `<form id="fP">
    <label class="f">Tipo<select id="pT"><option value="avviso" ${p.tipo === "avviso" ? "selected" : ""}>Avviso</option><option value="facebook" ${p.tipo === "facebook" ? "selected" : ""}>Post di Facebook</option><option value="instagram" ${p.tipo === "instagram" ? "selected" : ""}>Post di Instagram</option></select></label>
    <label class="f">Titolo<input type="text" id="pTi" value="${esc(p.titolo)}"></label>
    <label class="f">Testo<textarea id="pTe" required>${esc(p.testo)}</textarea></label>
    <label class="f">Link al post <span class="h">Su Facebook o Instagram tocca “Condividi” e poi “Copia link”</span><input type="url" id="pL" value="${esc(p.link)}" placeholder="https://www.instagram.com/p/…"></label>
    ${campoFoto(p.immagine)}
    <button class="btn sun block" type="submit">Pubblica</button>
    ${id ? `<button class="btn danger block" type="button" data-act="elimina" data-tab="bacheca" data-id="${id}">Elimina</button>` : ""}</form>`);
  bindFoto();
  $("#fP").addEventListener("submit", async ev => {
    ev.preventDefault();
    const row = {tipo: $("#pT").value, titolo: $("#pTi").value.trim(), testo: $("#pTe").value.trim(), link: $("#pL").value.trim(), immagine: fotoNuova || p.immagine || ""};
    if (await safe(() => id ? api.upd("bacheca", id, row) : api.ins("bacheca", {...row, data: new Date().toISOString()}), "Pubblicato in bacheca")) closeSheet();
  });
}

/* ---------- Impostazioni (presidente) ---------- */
function formConfig() {
  const c = {...cfg()};
  sheet("Logo, nome e social", `<form id="fC">
    <label class="f">Nome della sede<input type="text" id="cS" value="${esc(c.sede || "Gratteri")}"></label>
    <label class="f">Frase di benvenuto<input type="text" id="cM" value="${esc(c.motto)}"></label>
    <div class="f" style="display:flex;flex-direction:column;gap:8px"><b>Logo</b>
      <img class="imgprev" id="imgP" alt="" style="max-height:90px;object-fit:contain;align-self:flex-start;background:#fff;padding:8px" src="${esc(c.logo || "logo-auser.svg")}">
      <input type="file" id="imgF" accept="image/*"><span class="meta" id="imgS">${c.logo ? "" : "C’è già il logo Auser: caricane un altro solo se vuoi cambiarlo."}</span></div>
    <label class="f">Pagina Facebook<input type="url" id="cF" value="${esc(c.facebook)}" placeholder="https://www.facebook.com/…"></label>
    <label class="f">Profilo Instagram<input type="url" id="cI" value="${esc(c.instagram)}" placeholder="https://www.instagram.com/…"></label>
    <label class="f">Canale o gruppo WhatsApp<input type="url" id="cW" value="${esc(c.whatsapp)}" placeholder="https://whatsapp.com/channel/…"></label>
    <label class="f">Telefono del direttivo <span class="h">Lo vede chi non riesce a iscriversi dall'app</span><input type="tel" id="cT" value="${esc(c.telefono)}"></label>
    <button class="btn sun block" type="submit">Salva</button>
    <button class="btn ghost block" type="button" data-act="temi">Cambia il tema e i colori</button></form>`);
  bindFoto(false);
  $("#fC").addEventListener("submit", async ev => {
    ev.preventDefault();
    const row = {sede: $("#cS").value.trim(), motto: $("#cM").value.trim(), logo: fotoNuova || c.logo || "",
      facebook: $("#cF").value.trim(), instagram: $("#cI").value.trim(), whatsapp: $("#cW").value.trim(), telefono: $("#cT").value.trim()};
    if (await safe(() => api.upd("impostazioni", 1, row), "Impostazioni salvate")) closeSheet();
  });
}

/* ---------- Temi ---------- */
function temaPer(k) {
  if (k === "personalizzato") return daPersonalizzato(cfg().tema_personalizzato || {});
  if (k === "automatico") return TEMI[temaDelGiorno()];
  return TEMI[k] || TEMI[TEMA_BASE];
}
function vTemi() {
  const c = cfg(), scelto = S.temaScelto || c.tema || TEMA_BASE;
  const tile = (k, t, nome, descr) => `<button class="tile" data-act="tema" data-v="${k}" aria-pressed="${scelto === k}" style="--leaf:${t.leaf};--sun:${t.sun};--sky:${t.sky};--top-ink:${t.topInk}">
    <div class="tt" style="background:${t.top};color:${t.topInk};font-family:'${t.font}',system-ui,sans-serif">${decoSvg(t, "t" + k)}<span class="tlogo">${logoSvg(t)}</span><span>Ciao!</span></div>
    <div class="tb"><span class="dot" style="background:${t.brand}"></span><span class="dot" style="background:${t.sun}"></span><span class="dot" style="background:${t.sky}"></span><span class="tn">${esc(nome)}</span></div>
    <small>${esc(descr)}</small></button>`;
  const oggi = TEMI[temaDelGiorno()];
  const pers = c.tema_personalizzato && Object.keys(c.tema_personalizzato).length ? daPersonalizzato(c.tema_personalizzato) : null;
  return `<p class="meta" style="margin:0">Tocca un tema per provarlo, poi chiudi questa finestra per vederlo su tutta l'app. I soci lo vedranno solo quando premi “Usa questo tema”.</p>
    <div class="temi">
      ${tile("automatico", oggi, "Automatico", "Cambia da solo con le feste. Oggi: " + oggi.nome)}
      ${Object.entries(TEMI).map(([k, t]) => tile(k, t, t.nome, t.descr)).join("")}
      ${pers ? tile("personalizzato", pers, "Il tuo tema", "Creato da te") : ""}
    </div>
    <div class="box"><h3>Il tema automatico</h3><p class="meta" style="margin:0">Natale dall'8 al 30 dicembre, 'A Vecchia dal 31 dicembre al 6 gennaio, Carnevale nei giorni prima delle Ceneri, Pasqua dalla Domenica delle Palme a Pasquetta. Poi le stagioni: Primavera dal 21 marzo, Estate dal 21 giugno, Autunno dal 23 settembre fino a novembre. Nel resto dell'anno, Classico bianco.</p></div>
    <button class="btn ghost block" data-act="personalizza">Personalizza tutto…</button>
    <button class="btn sun block" data-act="salva-tema">Usa questo tema</button>`;
}

const CAMPI_COLORE = [["top1","Testata"],["top2","Testata, secondo colore della sfumatura"],["topInk","Scritte della testata"],["brand","Colore principale: pulsanti e titoli"],
  ["leaf","Dettagli e decorazioni"],["sun","Gite"],["sky","Eventi"],["bg","Sfondo"],["surface","Schede"],["ink","Testo"]];
function formPersonalizza() {
  const p = comePersonalizzato(temaOra());
  const base = temaAnteprima;
  sheet("Personalizza il tema", `<form id="fT">
    <p class="meta" style="margin:0">Ogni modifica si vede subito sull'app. Chiudi questa finestra per guardarla meglio: puoi salvare anche dalla barra in basso.</p>
    <div class="box">${CAMPI_COLORE.map(([k, l]) => `<label class="colrow" for="t-${k}">${l}<input type="color" id="t-${k}" data-k="${k}" value="${esc(p[k])}"></label>`).join("")}</div>
    <div class="box">
      <label class="f">Carattere dei titoli<select id="t-font" data-k="font">${Object.entries(FONT_TITOLI).map(([k, l]) => `<option value="${esc(k)}" ${p.font === k ? "selected" : ""}>${l}</option>`).join("")}</select></label>
      <label class="f">Logo<select id="t-logo" data-k="logo">${Object.entries(LOGHI).map(([k, l]) => `<option value="${k}" ${(p.logo || "") === k ? "selected" : ""}>${l}</option>`).join("")}</select></label>
      <label class="f">Decorazione della testata<select id="t-decor" data-k="decor">${Object.entries(DECORAZIONI).map(([k, l]) => `<option value="${k}" ${p.decor === k ? "selected" : ""}>${l}</option>`).join("")}</select></label>
      <label class="f">Angoli arrotondati <span class="h" id="t-rv">${p.radius} px</span><input type="range" min="4" max="28" step="1" id="t-radius" data-k="radius" value="${p.radius}"></label>
      <label class="f">Chiaro o scuro<select id="t-modo" data-k="modo"><option value="auto" ${p.modo === "auto" ? "selected" : ""}>Come il telefono</option><option value="chiaro" ${p.modo === "chiaro" ? "selected" : ""}>Sempre chiaro</option><option value="scuro" ${p.modo === "scuro" ? "selected" : ""}>Sempre scuro</option></select></label>
    </div>
    <div class="avvisi" id="t-avvisi" aria-live="polite"></div>
    <button class="btn sun block" type="submit">Salva e usa questo tema</button>
    <button class="btn ghost block" type="button" data-act="temi">Torna ai temi pronti</button></form>`);
  temaAnteprima = base;
  const leggi = () => { const o = {}; $("#fT").querySelectorAll("[data-k]").forEach(el => o[el.dataset.k] = el.type === "range" ? Number(el.value) : el.value); return o; };
  const aggiorna = (prima) => {
    const o = leggi();
    if (!prima) { temaAnteprima = daPersonalizzato(o); S.temaScelto = "__bozza"; S.persBozza = o; applyTheme(); render(); }
    $("#t-rv").textContent = o.radius + " px";
    const av = [];
    if (contrasto(o.topInk, o.top1) < 3 || contrasto(o.topInk, o.top2) < 3) av.push("Le scritte della testata si leggono poco su quel colore.");
    if (contrasto("#FFFFFF", o.brand) < 4.5) av.push("Il testo bianco sui pulsanti si legge poco: scegli un colore principale più scuro.");
    if (contrasto(o.ink, o.bg) < 4.5 || contrasto(o.ink, o.surface) < 4.5) av.push("Il testo si legge poco sullo sfondo o sulle schede.");
    $("#t-avvisi").innerHTML = av.map(x => `<div class="banner warn">${esc(x)}</div>`).join("");
  };
  $("#fT").addEventListener("input", () => aggiorna(false));
  aggiorna(true);
  $("#fT").addEventListener("submit", async ev => {
    ev.preventDefault();
    const o = leggi();
    if (await safe(() => api.upd("impostazioni", 1, {tema: "personalizzato", tema_personalizzato: o}), "Tema salvato: ora lo vedono tutti")) { temaAnteprima = null; S.temaScelto = null; closeSheet(); }
  });
}

/* ---------- Gallerie ---------- */
const fotoDi = eid => S.foto.filter(f => f.attivita_id === eid).sort((a, b) => (a.creato_il || "").localeCompare(b.creato_il || ""));
function thumb(f, eid, i) {
  return `<button class="thumb" data-act="foto" data-id="${eid}" data-i="${i}" aria-label="Apri foto ${i + 1}${f.didascalia ? ": " + esc(f.didascalia) : ""}"><img src="${esc(f.url)}" alt="" loading="lazy"></button>`;
}
function bottoneCarica(eid) {
  if (!can("socio")) return "";
  return `<label class="btn ghost block" style="cursor:pointer"><input type="file" accept="image/*" multiple class="sr" data-carica="${eid}">+ Aggiungi le tue foto</label>
    <span class="meta" id="up-${eid}" aria-live="polite"></span>`;
}
function boxFoto(e) {
  const fs = fotoDi(e.id);
  if (!fs.length && !can("socio")) return "";
  const passato = (e.data || "") <= todayISO();
  return `<div class="box"><div class="sechead"><h3>Foto${fs.length ? " · " + fs.length : ""}</h3>${fs.length > 9 ? `<button class="link" data-act="galleria" data-id="${e.id}">Vedi tutte</button>` : ""}</div>
    ${fs.length ? `<div class="grid3">${fs.slice(0, 9).map((f, i) => thumb(f, e.id, i)).join("")}</div>`
      : `<p class="meta" style="margin:0">${passato ? "Ancora nessuna foto. Eri presente? Condividi le tue!" : "Dopo l'evento qui trovi le foto dei partecipanti."}</p>`}
    ${bottoneCarica(e.id)}</div>`;
}
function vGalleria(e) {
  const fs = fotoDi(e.id);
  return `<div class="meta">${esc(fmtLongY(e.data))} · ${fs.length} foto</div>
    ${fs.length ? `<div class="grid3">${fs.map((f, i) => thumb(f, e.id, i)).join("")}</div>` : '<div class="empty">Ancora nessuna foto.</div>'}
    ${bottoneCarica(e.id)}
    <button class="btn ghost block" data-act="open" data-k="${e.tipo === "assemblea" ? "assemblea" : "evento"}" data-id="${e.id}">Vai alla pagina dell'evento</button>`;
}
function album(e) {
  const fs = fotoDi(e.id), n = Math.min(fs.length, 4);
  return `<button class="album" data-act="galleria" data-id="${e.id}"><div class="mosaic n${n}">${fs.slice(0, n).map(f => `<img src="${esc(f.url)}" alt="" loading="lazy">`).join("")}</div>
    <div class="in"><h3>${esc(e.titolo)}</h3><div class="meta">${esc(fmtLong(e.data))} · ${fs.length} foto</div></div></button>`;
}
function vGallerie() {
  const tutti = [...new Set(S.foto.map(f => f.attivita_id))].map(trova).filter(Boolean).sort((a, b) => (b.data || "").localeCompare(a.data || ""));
  if (!tutti.length) return '<div class="empty">Ancora nessuna foto. Si aggiungono dalla pagina di ogni gita o evento.</div>';
  const evs = perAnnoScelto("gal", tutti);
  return filtroAnno("gal", tutti) + `<div id="sez-gal">${paginato("gal", evs, 6, l => l.map(album).join(""))}</div>`;
}
function ultimeFoto() {
  const ult = [...S.foto].sort((a, b) => (b.creato_il || "").localeCompare(a.creato_il || "")).slice(0, 6);
  if (!ult.length) return "";
  return `<section class="sec"><div class="sechead"><h2>Ultime foto</h2><button class="link" data-act="gallerie">Tutte le gallerie</button></div>
    <div class="grid3">${ult.map(f => thumb(f, f.attivita_id, fotoDi(f.attivita_id).indexOf(f))).join("")}</div></section>`;
}
async function caricaFoto(eid, files) {
  const max = can("direttivo") ? 100 : 20;
  const lista = [...files].slice(0, max), out = () => $("#up-" + eid);
  let ok = 0;
  for (let i = 0; i < lista.length; i++) {
    if (out()) out().textContent = `Carico la foto ${i + 1} di ${lista.length}…`;
    try {
      const r = await api.carica(lista[i]);
      await api.ins("foto", {attivita_id: eid, user_id: S.myId, autore: S.myName, url: r.url, percorso: r.percorso, didascalia: ""});
      ok++;
    } catch (e) { console.error(e); }
  }
  try { await carica(); } catch (e) {}
  if (files.length > max) toast(`Puoi caricare fino a ${max} foto per volta: ne ho caricate ${ok}.`);
  else toast(ok === lista.length ? (ok === 1 ? "Foto pubblicata. Grazie!" : ok + " foto pubblicate. Grazie!") : `Pubblicate ${ok} foto su ${lista.length}: le altre non sono riuscite.`);
}

/* Visualizzatore a tutto schermo */
let LB = null;
function apriFoto(eid, i) { LB = {eid, i: Number(i) || 0}; disegnaLB(); }
function chiudiLB() { LB = null; $("#lightbox").innerHTML = ""; if (!$("#sheet").innerHTML) document.body.style.overflow = ""; }
function disegnaLB() {
  if (!LB) return;
  const fs = fotoDi(LB.eid); if (!fs.length) return chiudiLB();
  LB.i = (LB.i + fs.length) % fs.length;
  const f = fs[LB.i], e = trova(LB.eid);
  const puo = (f.user_id && f.user_id === S.myId) || can("direttivo");
  $("#lightbox").innerHTML = `<div class="lb" role="dialog" aria-modal="true" aria-label="Foto ${LB.i + 1} di ${fs.length}">
    <div class="lbtop"><span>${LB.i + 1} / ${fs.length}</span><button class="close" data-act="lb-chiudi">Chiudi</button></div>
    <div class="lbimg" id="lbimg">${fs.length > 1 ? '<button class="lbnav" data-act="lb-prev" aria-label="Foto precedente">‹</button>' : ""}
      <img src="${esc(f.url)}" alt="${esc(f.didascalia || "Foto: " + (e ? e.titolo : ""))}">
      ${fs.length > 1 ? '<button class="lbnav" data-act="lb-next" aria-label="Foto successiva">›</button>' : ""}</div>
    <div class="lbinfo"><b>${esc(e ? e.titolo : "")}</b>${f.didascalia ? `<p>${esc(f.didascalia)}</p>` : ""}<small>${f.autore ? "Foto di " + esc(f.autore) : ""}${fs.length > 1 ? " · scorri per le altre" : ""}</small>
      ${puo ? `<div class="row"><button class="btn ghost sm" data-act="lb-dida">${f.didascalia ? "Modifica didascalia" : "Aggiungi didascalia"}</button><button class="btn danger sm" data-act="lb-elimina" data-id="${f.id}">Elimina</button></div>
      <form id="fDida" hidden><input type="text" id="dida" value="${esc(f.didascalia)}" placeholder="Scrivi una didascalia" aria-label="Didascalia"><button class="btn sm" type="submit">Salva</button></form>` : ""}
    </div></div>`;
  document.body.style.overflow = "hidden";
  const box = $("#lbimg"); let x0 = null;
  box.addEventListener("touchstart", ev => { x0 = ev.touches[0].clientX; }, {passive: true});
  box.addEventListener("touchend", ev => { if (x0 === null) return; const dx = ev.changedTouches[0].clientX - x0; x0 = null; if (Math.abs(dx) > 50) { LB.i += dx < 0 ? 1 : -1; disegnaLB(); } });
  $("#fDida")?.addEventListener("submit", async ev => {
    ev.preventDefault();
    if (await safe(() => api.upd("foto", f.id, {didascalia: $("#dida").value.trim()}), "Didascalia salvata")) disegnaLB();
  });
}

/* ---------- Testi da copiare ---------- */
function testoEvento(e) {
  return [`*${e.titolo}*`, `📅 ${fmtLongY(e.data)}${e.ora ? ", " + fmtOra(e.ora) : ""}`, e.luogo ? `📍 ${e.luogo}` : "", e.ritrovo ? `🚏 Ritrovo: ${e.ritrovo}` : "",
    e.costo ? `💶 Quota: ${e.costo}` : "", e.scadenza ? `⏳ Iscrizioni entro ${fmtLong(e.scadenza)}` : "", "", e.descrizione || "",
    e.programma ? "\n*Programma*\n" + e.programma : "", "", "Per partecipare iscriviti dall'app Auser oppure rispondi a questo messaggio con nome e numero di persone.",
    location.href.startsWith("http") ? location.origin + location.pathname : "", "", `Auser ${cfg().sede || "Gratteri"}`]
    .filter((x, i, a) => x !== "" || a[i - 1] !== "").join("\n").trim();
}
function testoConv(id) {
  const a = S.ass[id], ora = o => o ? " alle ore " + o.replace(":", ".") : "", g = a.genere || "ordinaria";
  return [`*AUSER ${(cfg().sede || "Gratteri").toUpperCase()}*`, `*Convocazione dell'assemblea ${g} dei soci*`, "",
    `I soci sono convocati in assemblea ${g} presso ${a.luogo || "la sede"}, in prima convocazione ${fmtLongY(a.prima_data)}${ora(a.prima_ora)}` +
    (a.seconda_data ? ` e, in seconda convocazione, ${fmtLongY(a.seconda_data)}${ora(a.seconda_ora)}` : "") + ", per discutere il seguente", "",
    "*Ordine del giorno*", ...(a.odg || []).map((x, i) => `${i + 1}. ${x}`), a.note ? "\n" + a.note : "", "", "Il Presidente"].join("\n");
}
function testoLista(eid) {
  const e = trova(eid); let n = 0;
  const righe = partecipanti(eid).map(p => [...(p.io ? [p.nome] : []), ...p.acc.map(a => a.nome)].map(x => `${++n}. ${x}${x !== p.nome ? " (con " + p.nome + ")" : ""}`).join("\n"));
  return `${e.titolo} – ${fmtLong(e.data)}\nTotale: ${n} persone\n\n${righe.join("\n")}`;
}
async function copia(txt) {
  try { await navigator.clipboard.writeText(txt); toast("Copiato: ora incollalo su WhatsApp"); }
  catch (e) { sheet("Copia il testo", `<p class="meta" style="margin:0">Tieni premuto sul testo, scegli “Seleziona tutto” e poi “Copia”.</p><textarea style="min-height:320px" readonly>${esc(txt)}</textarea>`); }
}

function sceltaRuolo() {
  const opts = ["presidente", "direttivo", "socio"].filter(r => RANK[r] <= RANK[S.realRole]);
  sheet("Vedi l'app come…", `<p class="meta" style="margin:0">Cambia solo quello che vedi tu, per controllare come appare agli altri. I permessi veri restano i tuoi.</p>
    ${opts.map(r => `<button class="btn ${S.viewRole === r ? "" : "ghost"} block" data-act="setrole" data-v="${r}">${ROLES[r]}${r === S.realRole ? " (tu)" : ""}</button>`).join("")}`);
}

/* =====================================================================
   Tocchi e pulsanti
   ===================================================================== */
const vistaDi = id => trova(id)?.tipo === "assemblea" ? "assemblea" : "evento";
document.addEventListener("click", async ev => {
  const t = ev.target.closest("[data-act]"); if (!t) return;
  const a = t.dataset.act, id = t.dataset.id;
  const conferma = testo => { if (t.dataset.confirm === "1") return true; t.dataset.confirm = "1"; t.textContent = testo; return false; };
  switch (a) {
    case "scrim": if (ev.target === t) closeSheet(); return;
    case "close": return closeSheet();
    case "tab": S.tab = t.dataset.v; render(); window.scrollTo(0, 0); return;
    case "filtro": S.filtro = t.dataset.v; S.pagina["att-pas"] = 1; render(); return;
    case "anno": S.anno[t.dataset.k] = t.dataset.v; Object.keys(S.pagina).forEach(k => { if (k.startsWith(t.dataset.k)) S.pagina[k] = 1; }); render(); return;
    case "pagina": { const k = t.dataset.k; S.pagina[k] = Number(t.dataset.v); render();
      const sez = document.getElementById("sez-" + k); if (sez) sez.scrollIntoView({block: "start", behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth"}); return; }
    case "authtab": S.authTab = t.dataset.v; render(); return;
    case "open": return openView(t.dataset.k, id);
    case "big": { const liv = (zoomOra() + 1) % 3; impostaZoom(liv); try { localStorage.setItem("auser-zoom", String(liv)); } catch (e) {}
      toast(["Testo normale", "Testo grande", "Testo molto grande"][liv]); render(); return; }
    case "role": return sceltaRuolo();
    case "setrole": S.viewRole = t.dataset.v; if (S.tab === "gestione" && !can("direttivo")) S.tab = "home"; closeSheet(); render(); return;
    case "esci": if (S.live) await S.sb.auth.signOut(); return;
    case "ricarica": await caricaProfilo(); return;
    case "form-evento": return formEvento(id);
    case "form-assemblea": return formAssemblea(id);
    case "form-post": return formPost(id);
    case "form-config": return formConfig();
    case "form-adesione": return formAdesione(id, t.dataset.mode, t.dataset.ref);
    case "acc+": case "acc-": { const n = Number($("#aN").textContent) + (a === "acc+" ? 1 : -1); if (n >= 0 && n <= 12) formAdesione.rows(n); return; }
    case "annulla-mia": if (!conferma("Tocca di nuovo per confermare")) return;
      if (await safe(() => api.del("adesioni", t.dataset.ref), "Iscrizione annullata")) openView(vistaDi(id), id); return;
    case "rimuovi-part": if (!conferma("Tocca di nuovo per confermare")) return;
      if (await safe(() => api.del("adesioni", t.dataset.ref), "Tolto dall'elenco")) openView(vistaDi(id), id); return;
    case "elimina": if (!conferma("Tocca di nuovo per eliminare")) return;
      if (await safe(() => api.del(t.dataset.tab, id), "Eliminato")) closeSheet(); return;
    case "soci": return openView("soci");
    case "ruolo": if (await safe(() => api.upd("profili", id, {ruolo: t.dataset.v}), t.dataset.v === "direttivo" ? "Aggiunto al direttivo" : "Fatto")) openView("soci"); return;
    case "rifiuta": if (!conferma("Tocca di nuovo per rifiutare")) return;
      if (await safe(() => api.del("profili", id), "Richiesta rifiutata")) openView("soci"); return;
    case "pin": return formPin(id);
    case "mio-pin": return formMioPin();
    case "togli-tesserato": if (!conferma("Tocca di nuovo")) return;
      if (await safe(() => api.del("tesserati", id), "Tolto dall'elenco")) openView("soci", null, true); return;
    case "bvista": S.bvista = t.dataset.v; render(); return;
    case "gallerie": S.tab = "bacheca"; S.bvista = "gallerie"; render(); window.scrollTo(0, 0); return;
    case "galleria": return openView("galleria", id);
    case "foto": return apriFoto(id, t.dataset.i);
    case "lb-chiudi": return chiudiLB();
    case "lb-prev": LB.i--; return disegnaLB();
    case "lb-next": LB.i++; return disegnaLB();
    case "lb-dida": { const f = $("#fDida"); f.hidden = !f.hidden; if (!f.hidden) $("#dida").focus(); return; }
    case "lb-elimina": { if (!conferma("Tocca di nuovo per eliminare")) return;
      const f = S.foto.find(x => x.id === id); if (!f) return;
      if (await safe(async () => { await api.del("foto", id); await api.togliFile(f.percorso); }, "Foto eliminata")) disegnaLB(); return; }
    case "temi": return openView("temi");
    case "tema": S.temaScelto = t.dataset.v; temaAnteprima = temaPer(S.temaScelto); applyTheme(); render(); return openView("temi", null, true);
    case "personalizza": return formPersonalizza();
    case "salva-tema": { const k = S.temaScelto || cfg().tema || TEMA_BASE;
      const row = k === "__bozza" ? {tema: "personalizzato", tema_personalizzato: S.persBozza} : {tema: k};
      if (await safe(() => api.upd("impostazioni", 1, row), "Tema salvato: ora lo vedono tutti")) { temaAnteprima = null; S.temaScelto = null; closeSheet(); render(); } return; }
    case "annulla-tema": temaAnteprima = null; S.temaScelto = null; applyTheme(); render(); if (S.sheet && S.sheet.kind === "temi") openView("temi", null, true); return;
    case "copia-evento": return copia(testoEvento(trova(id)));
    case "copia-conv": return copia(testoConv(id));
    case "copia-lista": return copia(testoLista(id));
  }
});
document.addEventListener("submit", async ev => {
  if (ev.target.id === "fLogin") entra(ev);
  if (ev.target.id === "fReg") registrati(ev);
  if (ev.target.id === "fTess") {
    ev.preventDefault();
    const nome = $("#tsNome").value.trim(), telefono = soloCifre($("#tsTel").value);
    if (!nome) return;
    if (await safe(() => api.ins("tesserati", {nome, telefono, anno: new Date().getFullYear()}), "Tesserato aggiunto")) openView("soci", null, true);
  }
});
document.addEventListener("keydown", ev => {
  if (LB) { if (ev.key === "Escape") chiudiLB(); if (ev.key === "ArrowLeft") { LB.i--; disegnaLB(); } if (ev.key === "ArrowRight") { LB.i++; disegnaLB(); } return; }
  if (ev.key === "Escape" && $("#sheet").innerHTML) closeSheet();
});
document.addEventListener("change", ev => { const el = ev.target.closest("[data-carica]"); if (el && el.files.length) { caricaFoto(el.dataset.carica, el.files); el.value = ""; } });
document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible" && S.live && RANK[S.realRole] >= 1) carica().catch(() => {}); });

/* =====================================================================
   Avvio
   ===================================================================== */
async function caricaProfilo() {
  const u = S.sessione?.user; if (!u) return;
  S.myId = u.id;
  const {data, error} = await S.sb.from("profili").select("*").eq("id", u.id).maybeSingle();
  if (error) {
    S.loading = false; S.realRole = S.viewRole = "lettore";
    $("#tabs").innerHTML = "";
    $("#app").innerHTML = testata("Un attimo…", "Non riesco a leggere il tuo profilo.", false) + `<main><div class="box"><h3>Problema di collegamento</h3>
      <p style="margin:0">L'app non riesce a leggere i dati dal database. Riprova tra poco; se succede ancora, avvisa il presidente.</p>
      <p class="meta" style="margin:0">Dettaglio per il presidente: ${esc(error.message || error.code || "errore sconosciuto")}</p>
      <button class="btn ghost" data-act="ricarica">Riprova</button><button class="btn ghost" data-act="esci">Esci</button></div></main>`;
    return;
  }
  S.profilo = data;
  S.myName = data?.nome || u.user_metadata?.nome || "";
  const r = data?.ruolo;
  S.realRole = r === "presidente" ? "presidente" : r === "direttivo" ? "direttivo" : r === "socio" ? "socio" : "lettore";
  S.viewRole = S.realRole;
  if (RANK[S.realRole] >= 1) { S.loading = true; render(); try { await carica(); } catch (e) { S.loading = false; S.note = "Non riesco a leggere i dati. Controlla la connessione e riapri l'app."; render(); } }
  else { S.loading = false; render(); }
}

async function start() {
  try { impostaZoom(Number(localStorage.getItem("auser-zoom") || 0)); } catch (e) {}
  if (!S.live) return demoMode();
  if (!window.supabase) { S.live = false; demoMode(); S.note = "Non riesco a collegarmi al servizio dei dati: controlla la connessione e riapri l'app."; render(); return; }
  S.sb = window.supabase.createClient(CFG.url, CFG.chiave);
  const imp = await S.sb.from("impostazioni").select("*").eq("id", 1).maybeSingle();
  S.cfg = imp.data || {}; applyTheme();
  const {data} = await S.sb.auth.getSession();
  S.sessione = data.session;
  if (S.sessione) await caricaProfilo(); else { S.loading = false; render(); }
  S.sb.auth.onAuthStateChange((evento, sessione) => {
    const prima = S.sessione?.user?.id;
    S.sessione = sessione;
    if (!sessione) { S.realRole = S.viewRole = "lettore"; S.myId = null; S.tab = "home"; closeSheet(); render(); }
    else if (sessione.user.id !== prima) setTimeout(caricaProfilo, 0);
  });
}

/* Immagini disegnate per la modalità prova (non sono foto vere) */
function fotoFinta(pal, seme) {
  const cv = document.createElement("canvas"); cv.width = 900; cv.height = 675; const g = cv.getContext("2d");
  const cielo = g.createLinearGradient(0, 0, 0, 675); cielo.addColorStop(0, pal[0]); cielo.addColorStop(1, pal[1]); g.fillStyle = cielo; g.fillRect(0, 0, 900, 675);
  g.fillStyle = "rgba(255,255,255,.75)"; g.beginPath(); g.arc(160 + seme * 120, 170, 70, 0, 7); g.fill();
  [[.55, .35], [.68, .55], [.8, .8]].forEach(([y, a], k) => { g.fillStyle = pal[2]; g.globalAlpha = a; g.beginPath(); g.moveTo(0, 675);
    for (let x = 0; x <= 900; x += 30) g.lineTo(x, 675 * y + Math.sin(x / (90 + k * 40) + seme + k) * (40 - k * 8)); g.lineTo(900, 675); g.fill(); });
  g.globalAlpha = 1; return cv.toDataURL("image/jpeg", .8);
}

function demoMode() {
  const d = n => { const x = new Date(); x.setDate(x.getDate() + n); return x.toISOString().slice(0, 10); };
  S.myId = "io"; S.myName = "Presidente"; S.realRole = S.viewRole = "presidente";
  D.impostazioni = [{id: 1, sede: "Gratteri", motto: "", tema: "bianco", tema_personalizzato: {}, logo: "", facebook: "https://www.facebook.com/", instagram: "https://www.instagram.com/", whatsapp: "", telefono: "333 000 0000"}];
  D.attivita = [
    {id: "g1", tipo: "gita", titolo: "Gita a Cefalù e Santuario di Gibilmanna", data: d(18), ora: "08:00", luogo: "Cefalù", ritrovo: "Piazza Monumento, ore 7.45", costo: "25 € a persona, pranzo compreso", posti: 50, scadenza: d(12), descrizione: "Una giornata insieme tra il santuario e il centro storico di Cefalù.", programma: "8.00 partenza da Gratteri\n9.00 Santuario di Gibilmanna\n12.30 pranzo\n15.00 passeggiata a Cefalù\n18.30 rientro", ospiti: true, stato: "aperta", immagine: ""},
    {id: "p1", tipo: "gita", titolo: "Castagnata alla Pineta di Grattara", data: d(-20), ora: "10:00", luogo: "Pineta di Grattara", costo: "Offerta libera", descrizione: "Castagne, vino nuovo e musica sotto i pini.", ospiti: true, stato: "chiusa", immagine: ""},
    {id: "e1", tipo: "evento", titolo: "Tombolata di Natale", data: d(32), ora: "16:00", luogo: "Sede Auser", costo: "Ingresso libero", descrizione: "Tombola, dolci e auguri per tutti i soci e le famiglie.", ospiti: true, stato: "aperta", immagine: ""}];
  D.assemblee = [{id: "a1", genere: "ordinaria", prima_data: d(9), prima_ora: "08:00", seconda_data: d(10), seconda_ora: "17:00", luogo: "Sede Auser Gratteri", odg: ["Approvazione del bilancio", "Programma delle gite 2027", "Varie ed eventuali"], note: "", stato: "convocata"}];
  D.adesioni = [
    {id: "x1", attivita_id: "g1", user_id: "s1", nome: "Maria Rossi", io: true, acc: [{nome: "Giuseppe Rossi", rel: "Familiare"}], note: "", canale: "App", creato_il: "1"},
    {id: "x2", attivita_id: "g1", user_id: "s2", nome: "Salvatore Lo Bue", io: true, acc: [{nome: "Rosa Lo Bue", rel: "Familiare"}, {nome: "Anna Ferrara", rel: "Amico"}], note: "", canale: "App", creato_il: "2"},
    {id: "x3", attivita_id: "g1", user_id: null, nome: "Giuseppe Rossi", io: true, acc: [], note: "Ha scritto sul gruppo", canale: "WhatsApp", creato_il: "3"}];
  D.bacheca = [
    {id: "b1", tipo: "avviso", titolo: "Tesseramento 2027", testo: "Da lunedì in sede si rinnovano le tessere, dalle 10 alle 12.", link: "", immagine: "", data: new Date().toISOString()},
    {id: "b2", tipo: "instagram", titolo: "La festa d'autunno", testo: "Grazie a tutti per la bella giornata insieme!", link: "https://www.instagram.com/", immagine: "", data: new Date(Date.now() - 864e5 * 3).toISOString()}];
  D.foto = [["#F6B26B","#E06666","#6A994E"],["#9FC5E8","#F9CB9C","#38761D"],["#FFD966","#E69138","#274E13"],["#B4A7D6","#F4CCCC","#6AA84F"],["#A2C4C9","#FCE5CD","#3D85C6"]]
    .map((pal, i) => ({id: "f" + i, attivita_id: "p1", user_id: i % 2 ? "s1" : "io", autore: i % 2 ? "Maria Rossi" : "Presidente", url: fotoFinta(pal, i), percorso: "",
      didascalia: ["Si parte dalla piazza", "La pineta", "Castagne sul fuoco", "Tutti insieme", "Il rientro al tramonto"][i], creato_il: "2026-10-2" + i}));
  D.tesserati = [{id: "t1", nome: "Maria Rossi", telefono: "3331111111"}, {id: "t2", nome: "Giovanni Bianchi", telefono: "3334444444"}];
  D.profili = [
    {id: "io", nome: "Presidente", telefono: "3330000000", ruolo: "presidente"},
    {id: "s1", nome: "Maria Rossi", telefono: "3331111111", ruolo: "socio"},
    {id: "s2", nome: "Salvatore Lo Bue", telefono: "3332222222", ruolo: "direttivo"},
    {id: "s3", nome: "Concetta Spinella", telefono: "3333333333", ruolo: "in_attesa"}];
  carica();
}

start();
