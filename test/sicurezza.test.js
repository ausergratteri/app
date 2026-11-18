// Test locali delle funzioni di sicurezza lato browser: node --test test/
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const {linkSicuro, urlCss, percorsoDi, accSicuri, messaggioErrore} = require("../sicurezza.js");

const radice = path.join(__dirname, "..");

test("linkSicuro: accetta i link web", () => {
  assert.equal(linkSicuro("https://www.facebook.com/auser"), "https://www.facebook.com/auser");
  assert.equal(linkSicuro("  http://esempio.it/a?b=1 "), "http://esempio.it/a?b=1");
  assert.equal(linkSicuro("https://whatsapp.com/channel/abc"), "https://whatsapp.com/channel/abc");
});

test("linkSicuro: rifiuta schemi pericolosi e testo non valido", () => {
  for (const u of ["javascript:alert(1)", " JavaScript:alert(1)", "java\nscript:alert(1)", "data:text/html,<script>alert(1)</script>",
    "vbscript:msgbox(1)", "file:///etc/passwd", "//evil.example/x", "/relativo", "non un link", "", null, undefined]) {
    assert.equal(linkSicuro(u), "", String(u));
  }
});

test("urlCss: non si può uscire da url('…')", () => {
  const brutto = "x.jpg');background:red;x:url('y";
  const r = urlCss(brutto);
  assert.ok(!/['"();\s]/.test(r), r);
  assert.equal(urlCss("https://x.supabase.co/storage/v1/object/public/foto/a/1-b.jpg"),
    "https://x.supabase.co/storage/v1/object/public/foto/a/1-b.jpg");
  assert.equal(urlCss("a b\nc"), "a%20b%0Ac");
});

test("percorsoDi: solo file nella cartella di chi ha caricato", () => {
  const u = "11111111-1111-1111-1111-111111111111";
  assert.equal(percorsoDi(u + "/1700000000-abcde.jpg", u), true);
  assert.equal(percorsoDi("22222222-2222-2222-2222-222222222222/logo.png", u), false);
  assert.equal(percorsoDi(u + "/../altro/logo.png", u), false);
  assert.equal(percorsoDi(u + "/sotto/cartella.png", u), false);
  assert.equal(percorsoDi(u + "/", u), false);
  assert.equal(percorsoDi(u + "/a.jpg", null), false);
  assert.equal(percorsoDi("", u), false);
});

test("accSicuri: dati rovinati non bloccano l'app", () => {
  assert.deepEqual(accSicuri({}), []);
  assert.deepEqual(accSicuri("x"), []);
  assert.deepEqual(accSicuri(null), []);
  assert.deepEqual(accSicuri([1, null, [], {nome: 5, rel: 7}]), [{nome: "", rel: ""}]);
  assert.deepEqual(accSicuri([{nome: "Rosa", rel: "Familiare"}]), [{nome: "Rosa", rel: "Familiare"}]);
});

test("accSicuri: i nomi salvati come testo non si perdono", () => {
  assert.deepEqual(accSicuri(["Rosa", "Pino"]), [{nome: "Rosa", rel: ""}, {nome: "Pino", rel: ""}]);
});

test("messaggioErrore: le regole del database danno messaggi chiari", () => {
  assert.match(messaggioErrore("Non puoi iscriverti: posti esauriti"), /Posti esauriti/);
  assert.match(messaggioErrore("Non puoi iscriverti: le iscrizioni sono chiuse"), /chiuse/);
  assert.match(messaggioErrore("Non puoi iscriverti: l'assemblea è annullata"), /chiuse/);
  assert.match(messaggioErrore("Non puoi portare ospiti a questa attività"), /familiari o amici/);
  assert.match(messaggioErrore('new row for relation "impostazioni" violates check constraint "impostazioni_link_web"'), /social/);
  assert.match(messaggioErrore('new row for relation "bacheca" violates check constraint "bacheca_link_web"'), /https/);
  assert.match(messaggioErrore('new row for relation "adesioni" violates check constraint "adesioni_acc_valido"'), /12/);
  assert.match(messaggioErrore("Non puoi cambiare il nome di un'altra persona"), /presidente/);
  assert.equal(messaggioErrore("new row violates row-level security policy"), "");
  assert.equal(messaggioErrore(undefined), "");
});

test("app.js senza sicurezza.js (vecchio index.html in cache): versioni prudenti, nessun errore", () => {
  const js = fs.readFileSync(path.join(radice, "app.js"), "utf8");
  const inizio = js.indexOf('if (typeof window.linkSicuro !== "function")');
  const fine = js.indexOf("\n", js.indexOf('if (typeof window.messaggioErrore !== "function")'));
  assert.ok(inizio > 0 && fine > inizio, "blocco di riserva mancante");
  const finestra = {};
  vm.runInNewContext(js.slice(inizio, fine), {window: finestra});
  assert.equal(finestra.linkSicuro("javascript:alert(1)"), "");
  assert.equal(finestra.percorsoDi("a/b.jpg", "a"), false);
  assert.equal(finestra.accSicuri({}).length, 0);  // array di un altro contesto vm: si confronta la lunghezza
  assert.equal(finestra.accSicuri([{nome: "Rosa"}, 3]).length, 1);
  assert.equal(finestra.messaggioErrore("x"), "");
  assert.ok(!/['()]/.test(finestra.urlCss("x.jpg');background:red")));
  // con sicurezza.js caricato il blocco non sostituisce nulla
  const gia = {linkSicuro, urlCss, percorsoDi, accSicuri, messaggioErrore};
  vm.runInNewContext(js.slice(inizio, fine), {window: gia});
  assert.equal(gia.linkSicuro, linkSicuro);
});

test("index.html: CSP presente e sicurezza.js caricato prima di app.js", () => {
  const html = fs.readFileSync(path.join(radice, "index.html"), "utf8");
  assert.match(html, /http-equiv="Content-Security-Policy"/);
  assert.match(html, /object-src 'none'/);
  assert.ok(!/script-src[^;]*'unsafe-inline'/.test(html), "gli script inline non devono essere ammessi");
  const s = html.indexOf('src="sicurezza.js?v='), a = html.indexOf('src="app.js?v=');
  assert.ok(s > -1 && a > s, "sicurezza.js e app.js con versione, nell'ordine giusto");
});

test("app.js: i link e gli sfondi passano dai controlli", () => {
  const js = fs.readFileSync(path.join(radice, "app.js"), "utf8");
  assert.ok(!/href="\$\{esc\(c\[k\]\)\}"/.test(js), "link social senza linkSicuro");
  assert.ok(!/href="\$\{esc\(p\.link\)\}"/.test(js), "link bacheca senza linkSicuro");
  assert.ok(!/url\('\$\{esc\(img\)\}'\)/.test(js), "sfondo senza urlCss");
  assert.match(js, /percorsoDi\(f\.percorso, f\.user_id\)/);
  assert.match(js, /accSicuri\(a\.acc\)/);
  assert.match(js, /messaggioErrore\(m\)/);
});
