// Privacy (GDPR): nessuna risorsa da terzi caricata dall'app, informativa raggiungibile
// da accesso, registrazione e home, avviso spam sul codice. Nessuna rete.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {avviaApp} = require("./ambiente-app.js");

const radice = path.join(__dirname, "..");
const leggi = f => fs.readFileSync(path.join(radice, f), "utf8");

test("index.html: nessuna risorsa da Google Fonts o da CDN, CSP solo 'self' per script e font", () => {
  const html = leggi("index.html");
  for (const host of ["fonts.googleapis.com", "fonts.gstatic.com", "cdn.jsdelivr.net", "unpkg.com", "cdnjs"]) {
    assert.ok(!html.includes(host), `riferimento a ${host}`);
  }
  const csp = html.match(/http-equiv="Content-Security-Policy" content="([^"]+)"/)[1];
  assert.match(csp, /script-src 'self';/);
  assert.match(csp, /font-src 'self';/);
  assert.ok(!/style-src[^;]*https:/.test(csp), "nessun foglio di stile esterno");
  for (const m of html.matchAll(/(?:src|href)="([^"]+)"/g)) {
    assert.ok(!/^https?:/.test(m[1]), `risorsa esterna: ${m[1]}`);
    const file = m[1].split("?")[0];
    assert.ok(fs.existsSync(path.join(radice, file)), `file mancante: ${file}`);
  }
});

test("font locali: ogni file indicato in fonts.css esiste, licenze OFL presenti", () => {
  const css = leggi("vendor/fonts/fonts.css");
  const file = [...css.matchAll(/url\(([^)]+)\)/g)].map(m => m[1]);
  assert.ok(file.length >= 16);
  for (const f of new Set(file)) assert.ok(fs.existsSync(path.join(radice, "vendor/fonts", f)), f);
  assert.ok(!/https?:\/\//.test(css.replace(/\/\*.*?\*\//gs, "")), "nessun URL esterno nel CSS dei font");
  for (const l of ["atkinsonhyperlegible", "baloo2", "bricolagegrotesque", "fraunces"]) {
    assert.match(fs.readFileSync(path.join(radice, `vendor/fonts/OFL-${l}.txt`), "utf8"), /SIL Open Font License/);
  }
});

test("supabase-js locale: versione fissata 2.49.4 con licenza", () => {
  const js = leggi("vendor/supabase-js-2.49.4/supabase.js");
  assert.ok(js.length > 100000);
  assert.match(leggi("vendor/supabase-js-2.49.4/LICENSE"), /MIT License/);
});

test("privacy.html: pagina statica senza script né risorse esterne, con i contenuti essenziali", () => {
  const p = leggi("privacy.html");
  assert.match(p, /script-src 'none'/);
  assert.ok(!/<script/i.test(p), "nessuno script");
  for (const m of p.matchAll(/(?:src|href)="([^"]+)"/g)) assert.ok(!/^https?:/.test(m[1]), `risorsa esterna: ${m[1]}`);
  for (const t of ["titolare del trattamento", "Supabase", "GitHub", "Google", "Garante", "conserviamo", "diritti", "minori"]) {
    assert.ok(p.toLowerCase().includes(t.toLowerCase()), t);
  }
});

test("app: informativa raggiungibile da accesso e registrazione, avviso spam al passo del codice", async () => {
  const a = await avviaApp({utente: null});
  assert.ok(a.html().includes('href="privacy.html"'), "link nella schermata di accesso");
  a.S.authTab = "registrati"; a.esegui("render()");
  assert.match(a.html(), /Proseguendo confermi di aver letto l'<a href="privacy.html"/);
  a.ctx.fetch = async () => ({status: 200, async json() { return {esito: "ok", richiesta: "11111111-2222-4333-8444-555555555555", messaggio: "Se i dati corrispondono…"}; }});
  await a.esegui('regAvvia("Giovanni", "Bianchi", "3334444444")');
  assert.match(a.html(), /cartella <b>Spam<\/b>/);
});
