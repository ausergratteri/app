"use strict";
/* =====================================================================
   Temi grafici dell'app Auser Gratteri
   Ogni tema definisce i colori della testata, i colori delle attività,
   lo sfondo chiaro e scuro, il carattere dei titoli e la decorazione.
   ===================================================================== */

const SIMBOLO_AUSER = "M40.9429 104.731C36.8911 100.803 35.4072 94.6152 36.8721 87.7637C38.7524 79.8467 43.6494 73.4795 47.4268 69.5303C60.7754 55.582 80.7534 45.2397 100.863 41.8721C106.038 41.0073 112.461 40.5171 118.49 40.5171C120.315 40.5171 122.083 40.5557 123.773 40.646C124 41.6787 124.319 43.4785 124.367 44.0078C127.625 75.3047 85.9082 97.1377 73.0469 103.086C63.5015 107.506 54.8335 109.196 47.7852 108.151C45.0361 107.647 42.7979 106.531 40.9429 104.731M37.9463 105.447L37.9463 105.454L37.9463 105.447ZM168.378 53.0142C165.194 49.2725 160.639 44.8203 151 40.1494C144.081 37.0332 136.219 34.6914 127.629 33.1748C124.574 27.2007 120.273 21.6714 114.848 16.7231C114.238 16.1812 113.615 15.665 112.996 15.1489L112.744 14.9424C97.6958 2.59375 78.3633 0 64.7979 0C62.5947 0 60.3496 .0712891 58.127 .206543C41.3589 1.24512 26.168 6.76807 14.207 16.1875C13.397 16.8198 12.5967 17.4585 11.8193 18.1357C7.41602 21.936 3.57715 26.2847 .396484 31.0459L0 31.6396L10.5264 39.2075L10.9614 38.6201C22.917 22.4521 42.3428 12.6904 65.6724 11.1357C68.0498 10.9683 70.2373 10.8906 72.3501 10.8906L73.2241 10.897C84.4209 11.0132 95.1538 13.1875 104.257 17.1748C112.338 20.7295 117.944 25.7876 120.935 32.2329C119.916 32.1299 118.89 32.0459 117.864 31.9751C115.486 31.8008 113.048 31.7104 110.615 31.7104C84.7891 31.7104 58.7334 41.2915 40.9106 57.3564C30.9072 66.3691 25.9102 78.292 27.2041 90.0605C27.4746 92.499 27.9971 94.873 28.7783 97.1699C32.707 106.035 43.9297 116.815 55.2461 118.777C56.7305 118.964 58.2432 119.061 59.7593 119.067L59.8623 119.067C63.1436 119.067 66.437 118.667 69.6533 117.887C83.2051 114.609 95.2603 106.551 105.496 99.2607C115.596 92.0664 123.409 82.7373 128.093 72.2666C129.81 68.4277 131.016 64.4531 131.661 60.4531C132.558 54.9434 132.187 47.459 130.758 41.4463C130.768 41.4526 130.78 41.4526 130.796 41.4526L131.535 41.5625C143.132 43.1943 153.648 46.8203 161.949 52.04C163.152 52.7881 163.897 53.311 165.12 54.1885C165.816 54.6914 166.133 54.9434 166.352 55.124L167.029 55.7109C168.062 56.6143 168.584 57.0464 169.143 57.0464C169.562 57.0464 170.017 56.7627 170.088 55.9561C170.056 55.7305 169.849 54.8657 168.378 53.0142";

const SCURO_NEUTRO = {bg: "#111315", surface: "#1B1E22", ink: "#EEF0F3", muted: "#A6ADB6", line: "#2C3138", soft: "#23272D"};

const TEMA_BASE = "bianco";

const TEMI = {
  bianco: {
    nome: "Classico bianco", descr: "Testata bianca, logo in primo piano",
    top: "#FFFFFF", topInk: "#14211A", topDark: "#18211C", topInkDark: "#EEF3EF",
    brand: "#1E7B3C", leaf: "#3AAA35", sun: "#F5B21A", sunInk: "#2B1D00", sky: "#2563A8", coral: "#D9472F",
    font: "Bricolage Grotesque", radius: 18, decor: "auser",
    light: {bg: "#F5F7F5", surface: "#FFFFFF", ink: "#14211A", muted: "#56635B", line: "#DCE3DD", soft: "#EBF1EC", accent: "#1E7B3C"},
    dark: {bg: "#0F1512", surface: "#18211C", ink: "#EEF3EF", muted: "#A3B0A7", line: "#2A362F", soft: "#213028", accent: "#7FD77A"}
  },
  classico: {
    nome: "Classico Auser", descr: "Il verde del logo, per tutto l'anno",
    top: "linear-gradient(160deg,#1E7B3C,#16602F)", topInk: "#FFFFFF",
    brand: "#1E7B3C", leaf: "#3AAA35", sun: "#F5B21A", sunInk: "#2B1D00", sky: "#2563A8", coral: "#D9472F",
    font: "Bricolage Grotesque", radius: 18, decor: "cerchi",
    light: {bg: "#F3F6F3", surface: "#FFFFFF", ink: "#14211A", muted: "#56635B", line: "#DCE3DD", soft: "#E8EFE9", accent: "#1E7B3C"},
    dark: {bg: "#0F1512", surface: "#18211C", ink: "#EEF3EF", muted: "#A3B0A7", line: "#2A362F", soft: "#213028", accent: "#7FD77A"}
  },
  natale: {
    nome: "Natale", descr: "Rosso, oro e neve",
    top: "linear-gradient(160deg,#B3202A,#7E141C)", topInk: "#FFFFFF",
    brand: "#A3192A", leaf: "#2F7D4A", sun: "#E5B53A", sunInk: "#2E2000", sky: "#2F7D4A", coral: "#C2410C",
    font: "Fraunces", radius: 18, decor: "neve", logo: "natale",
    light: {bg: "#FBF6F1", surface: "#FFFFFF", ink: "#2A1416", muted: "#6F5A5B", line: "#EBDCD6", soft: "#F5E9E3", accent: "#A3192A"},
    dark: {bg: "#170D0F", surface: "#24161A", ink: "#F7EDEE", muted: "#C3AFB1", line: "#3A262A", soft: "#2E1C20", accent: "#F08A8F"}
  },
  vecchia: {
    nome: "Capodanno · 'A Vecchia", descr: "La notte del 31 a Gratteri: fiaccole e stelle",
    top: "radial-gradient(120% 95% at 85% 115%,#7A3414 0%,#2A1B4A 48%,#120E26 100%)", topInk: "#FFF7EC",
    brand: "#3B2A7A", leaf: "#F28C28", sun: "#F2B33D", sunInk: "#2B1A00", sky: "#5B4BB3", coral: "#D9472F",
    font: "Fraunces", radius: 18, decor: "fiaccole", logo: "vecchia",
    light: {bg: "#F6F3EE", surface: "#FFFFFF", ink: "#1C1730", muted: "#615B73", line: "#E2DDD3", soft: "#EEE8DE", accent: "#3B2A7A"},
    dark: {bg: "#0E0B1A", surface: "#1A1530", ink: "#F4F0FA", muted: "#B3ABC7", line: "#2E2747", soft: "#251F3D", accent: "#F2B33D"}
  },
  carnevale: {
    nome: "Carnevale", descr: "Coriandoli e colori",
    top: "linear-gradient(135deg,#7B2CBF,#D6336C)", topInk: "#FFFFFF",
    brand: "#7B2CBF", leaf: "#FFD43B", sun: "#FF922B", sunInk: "#2E1500", sky: "#1C7ED6", coral: "#E03131",
    font: "Baloo 2", radius: 22, decor: "coriandoli", logo: "carnevale",
    light: {bg: "#FAF6FC", surface: "#FFFFFF", ink: "#221430", muted: "#665A72", line: "#E7DDEE", soft: "#F1E8F7", accent: "#7B2CBF"},
    dark: {bg: "#120C18", surface: "#1E1527", ink: "#F5EFFA", muted: "#B8A9C6", line: "#33263F", soft: "#2A1F35", accent: "#D0A6F5"}
  },
  pasqua: {
    nome: "Pasqua", descr: "Il viola della Settimana Santa e l'ulivo",
    top: "linear-gradient(160deg,#6B4C9A,#46306F)", topInk: "#FFFFFF",
    brand: "#5B3F8A", leaf: "#9DB86A", sun: "#F4C95D", sunInk: "#2B2000", sky: "#4E7034", coral: "#D9472F",
    font: "Fraunces", radius: 18, decor: "fiori", logo: "pasqua",
    light: {bg: "#F7F5F9", surface: "#FFFFFF", ink: "#1E1828", muted: "#615A6E", line: "#E3DDEA", soft: "#EEE8F4", accent: "#5B3F8A"},
    dark: {bg: "#110E16", surface: "#1C1724", ink: "#F3EFF8", muted: "#B1A8BF", line: "#2F283B", soft: "#262031", accent: "#C9B6E4"}
  },
  primavera: {
    nome: "Primavera", descr: "Fiori e verde nuovo",
    top: "linear-gradient(160deg,#2E8B57,#1E6B43)", topInk: "#FFFFFF",
    brand: "#1F7A4D", leaf: "#F28FB8", sun: "#F4C430", sunInk: "#2B2000", sky: "#7A5CC0", coral: "#D9472F",
    font: "Bricolage Grotesque", radius: 22, decor: "fiori", logo: "primavera",
    light: {bg: "#F4F8F4", surface: "#FFFFFF", ink: "#13241A", muted: "#56665C", line: "#DBE6DE", soft: "#E9F2EC", accent: "#1F7A4D"},
    dark: {bg: "#0F1512", surface: "#18211C", ink: "#EEF3EF", muted: "#A3B0A7", line: "#2A362F", soft: "#213028", accent: "#F5A8C9"}
  },
  estate: {
    nome: "Estate", descr: "Mare, sole e gite",
    top: "linear-gradient(160deg,#0B7FAB,#0A5C8A)", topInk: "#FFFFFF",
    brand: "#0A6E99", leaf: "#FFD166", sun: "#F59E0B", sunInk: "#2B1A00", sky: "#0E8F82", coral: "#E8553D",
    font: "Bricolage Grotesque", radius: 22, decor: "sole", logo: "estate",
    light: {bg: "#F2F8FB", surface: "#FFFFFF", ink: "#0F2230", muted: "#526775", line: "#D8E6EE", soft: "#E5F1F7", accent: "#0A6E99"},
    dark: {bg: "#0B141A", surface: "#142129", ink: "#EAF4F9", muted: "#9FB4C1", line: "#24363F", soft: "#1B2C35", accent: "#7CC7EA"}
  },
  sangiacomo: {
    nome: "San Giacomo", descr: "Il Patrono: rosso, oro e fuochi d'artificio",
    top: "linear-gradient(160deg,#8C1C24,#55101A)", topInk: "#FFFFFF",
    brand: "#8C1C24", leaf: "#D4A62A", sun: "#E9B949", sunInk: "#2B1D00", sky: "#2F4C7A", coral: "#C2410C",
    font: "Fraunces", radius: 18, decor: "fuochi", logo: "sangiacomo",
    light: {bg: "#FAF6F0", surface: "#FFFFFF", ink: "#2A1517", muted: "#6E5A55", line: "#EADDD2", soft: "#F4EAE0", accent: "#8C1C24"},
    dark: {bg: "#150D0E", surface: "#22161A", ink: "#F8EFEC", muted: "#C4AFAA", line: "#3A2629", soft: "#2D1D21", accent: "#E9C46A"}
  },
  autunno: {
    nome: "Autunno", descr: "Foglie, castagne e colori caldi",
    top: "linear-gradient(160deg,#A0522D,#6E3416)", topInk: "#FFFFFF",
    brand: "#93451C", leaf: "#F59F00", sun: "#F2A93B", sunInk: "#2B1800", sky: "#3D6B8C", coral: "#C92A2A",
    font: "Fraunces", radius: 18, decor: "foglie", logo: "autunno",
    light: {bg: "#FBF7F2", surface: "#FFFFFF", ink: "#2A1A10", muted: "#6E5B4E", line: "#ECDFD3", soft: "#F5EBE1", accent: "#93451C"},
    dark: {bg: "#15100C", surface: "#211913", ink: "#F7F0EA", muted: "#C1AE9F", line: "#3A2C22", soft: "#2D221A", accent: "#F5B04A"}
  }
};

const FONT_TITOLI = {
  "Bricolage Grotesque": "Moderno",
  "Fraunces": "Elegante",
  "Baloo 2": "Allegro",
  "Atkinson Hyperlegible": "Semplice e leggibile"
};
const DECORAZIONI = {nessuna: "Nessuna", cerchi: "Cerchi", auser: "Simbolo Auser", neve: "Neve", fiaccole: "Stelle e fiaccole", coriandoli: "Coriandoli", fiori: "Fiori", foglie: "Foglie", fuochi: "Fuochi d'artificio", sole: "Sole e onde"};
const LOGHI = {"": "Logo normale", natale: "Cappello di Natale", vecchia: "'A Vecchia sull'asinello", carnevale: "Maschera di Carnevale", pasqua: "Ramo d'ulivo", primavera: "Fiori di mandorlo", estate: "Limoni di Sicilia", autunno: "Foglie di castagno", sangiacomo: "Conchiglia e bordone"};

/* ---------- Calendario delle feste (tema automatico) ---------- */
function pasquaDi(anno) {
  const a = anno % 19, b = Math.floor(anno / 100), c = anno % 100, d = Math.floor(b / 4), e = b % 4;
  const f = Math.floor((b + 8) / 25), g = Math.floor((b - f + 1) / 3), h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4), k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7, m = Math.floor((a + 11 * h + 22 * l) / 451);
  const mese = Math.floor((h + l - 7 * m + 114) / 31), giorno = ((h + l - 7 * m + 114) % 31) + 1;
  return new Date(anno, mese - 1, giorno);
}
function temaDelGiorno(oggi = new Date()) {
  const g = new Date(oggi.getFullYear(), oggi.getMonth(), oggi.getDate());
  const m = g.getMonth() + 1, d = g.getDate();
  if ((m === 12 && d === 31) || (m === 1 && d <= 6)) return "vecchia";
  if (m === 12 && d >= 8) return "natale";
  const pasqua = pasquaDi(g.getFullYear()), giorno = 864e5;
  const ceneri = new Date(pasqua - 46 * giorno);
  if (g >= new Date(ceneri - 12 * giorno) && g < ceneri) return "carnevale";
  if (g >= new Date(pasqua - 7 * giorno) && g <= new Date(+pasqua + 1 * giorno)) return "pasqua";
  const md = m * 100 + d;
  if ((md >= 724 && md <= 726) || (md >= 905 && md <= 909)) return "sangiacomo";
  if (md >= 321 && md <= 620) return "primavera";
  if (md >= 621 && md <= 922) return "estate";
  if (md >= 923 && md <= 1130) return "autunno";
  return TEMA_BASE;
}

/* ---------- Colori ---------- */
function hexRgb(h) { h = String(h || "").replace("#", ""); if (h.length === 3) h = h.split("").map(x => x + x).join(""); const n = parseInt(h, 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }
function rgbHex(r, g, b) { return "#" + [r, g, b].map(x => Math.round(Math.max(0, Math.min(255, x))).toString(16).padStart(2, "0")).join(""); }
function mix(a, b, t) { const x = hexRgb(a), y = hexRgb(b); return rgbHex(x[0] + (y[0] - x[0]) * t, x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t); }
function luminanza(h) { return hexRgb(h).map(v => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }).reduce((s, v, i) => s + v * [0.2126, 0.7152, 0.0722][i], 0); }
function contrasto(a, b) { const x = luminanza(a), y = luminanza(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); }
const isHex = v => /^#[0-9a-fA-F]{6}$/.test(v || "");

/* Il tema personalizzato si salva in forma semplice e qui diventa un tema completo */
function daPersonalizzato(p) {
  const base = TEMI[TEMA_BASE];
  const c = k => isHex(p[k]) ? p[k] : null;
  const top1 = c("top1") || "#1E7B3C", top2 = c("top2") || top1;
  const bg = c("bg") || base.light.bg, surface = c("surface") || "#FFFFFF", ink = c("ink") || base.light.ink;
  const brand = c("brand") || base.brand, leaf = c("leaf") || base.leaf, sun = c("sun") || base.sun;
  return {
    nome: "Personalizzato",
    top: top1 === top2 ? top1 : `linear-gradient(160deg,${top1},${top2})`, topInk: c("topInk") || "#FFFFFF",
    brand, leaf, sun, sunInk: contrasto(sun, "#1A1A1A") > contrasto(sun, "#FFFFFF") ? "#1F1A10" : "#FFFFFF",
    sky: c("sky") || base.sky, coral: base.coral,
    font: FONT_TITOLI[p.font] ? p.font : base.font,
    radius: Math.max(4, Math.min(28, Number(p.radius) || 18)),
    decor: DECORAZIONI[p.decor] ? p.decor : "cerchi",
    logo: LOGHI[p.logo] !== undefined ? p.logo : "",
    modo: ["auto", "chiaro", "scuro"].includes(p.modo) ? p.modo : "auto",
    light: {bg, surface, ink, muted: mix(ink, bg, 0.42), line: mix(bg, ink, 0.12), soft: mix(bg, brand, 0.08), accent: brand},
    dark: {...SCURO_NEUTRO, soft: mix(SCURO_NEUTRO.surface, leaf, 0.08), accent: contrasto(leaf, SCURO_NEUTRO.bg) >= 4.5 ? leaf : mix(leaf, "#FFFFFF", 0.45)}
  };
}
function comePersonalizzato(t) {
  const g = String(t.top).match(/#[0-9a-fA-F]{6}/g) || [t.brand];
  return {top1: g[0], top2: g[g.length - 1], topInk: t.topInk, brand: t.brand, leaf: t.leaf, sun: t.sun, sky: t.sky,
    bg: t.light.bg, surface: t.light.surface, ink: t.light.ink, font: t.font, radius: t.radius, decor: t.decor, logo: t.logo || "", modo: t.modo || "auto"};
}

/* Quale tema mostrare con queste impostazioni */
function temaDa(cfg) {
  const scelto = cfg?.tema || TEMA_BASE;
  if (scelto === "personalizzato") return daPersonalizzato(cfg.tema_personalizzato || {});
  if (scelto === "automatico") return TEMI[temaDelGiorno()];
  return TEMI[scelto] || TEMI[TEMA_BASE];
}

/* ---------- Applicazione ---------- */
function cssTema(t) {
  const v = (o) => Object.entries(o).map(([k, x]) => `--${k}:${x};`).join("");
  const comuni = {top: t.top, "top-ink": t.topInk, brand: t.brand, leaf: t.leaf, sun: t.sun, "sun-ink": t.sunInk, sky: t.sky, coral: t.coral,
    r: t.radius + "px", "font-display": `"${t.font}", "Avenir Next", system-ui, sans-serif`,
    "sede-case": t.font === "Fraunces" ? "none" : "uppercase", "sede-spacing": t.font === "Fraunces" ? ".01em" : ".08em",
    "sede-style": t.font === "Fraunces" ? "italic" : "normal", "sede-size": t.font === "Fraunces" ? "18px" : "14px"};
  const chiaro = {bg: t.light.bg, surface: t.light.surface, ink: t.light.ink, muted: t.light.muted, line: t.light.line, soft: t.light.soft, "accent-text": t.light.accent};
  const d = t.dark || SCURO_NEUTRO;
  const scuro = {bg: d.bg, surface: d.surface, ink: d.ink, muted: d.muted, line: d.line, soft: d.soft, "accent-text": d.accent || t.leaf};
  if (t.topDark) { scuro.top = t.topDark; scuro["top-ink"] = t.topInkDark || d.ink; }
  return `:root{${v(comuni)}${v(chiaro)}color-scheme:light}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){${v(scuro)}color-scheme:dark}}
:root[data-theme="dark"]{${v(scuro)}color-scheme:dark}`;
}
function applicaTema(t) {
  let el = document.getElementById("stile-tema");
  if (!el) { el = document.createElement("style"); el.id = "stile-tema"; document.head.appendChild(el); }
  el.textContent = cssTema(t);
  const modo = t.modo || "auto";
  if (modo === "chiaro") document.documentElement.setAttribute("data-theme", "light");
  else if (modo === "scuro") document.documentElement.setAttribute("data-theme", "dark");
  else document.documentElement.removeAttribute("data-theme");
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta) meta.setAttribute("content", (String(t.top).match(/#[0-9a-fA-F]{6}/) || [t.brand])[0]);
}

/* ---------- Decorazioni della testata (SVG) ---------- */
function casuale(seme) { let a = seme >>> 0; return () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
function decoSvg(t, id = "d") {
  const R = casuale(7), W = 400, H = 260;
  let s = "";
  switch (t.decor) {
    case "cerchi":
      s = `<circle cx="365" cy="20" r="118" style="fill:var(--leaf)" opacity=".5"/><circle cx="300" cy="118" r="34" style="fill:var(--top-ink)" opacity=".1"/>`; break;
    case "auser":
      s = `<g transform="translate(232 -14) scale(1.05)" opacity=".16"><path style="fill:var(--leaf)" d="${SIMBOLO_AUSER}"/></g>`; break;
    case "neve":
      for (let i = 0; i < 46; i++) s += `<circle cx="${(R() * W).toFixed(1)}" cy="${(R() * H).toFixed(1)}" r="${(1.2 + R() * 3.2).toFixed(1)}" fill="#fff" opacity="${(0.25 + R() * 0.6).toFixed(2)}"/>`;
      s += `<path d="M0 248 Q 80 226 160 244 T 320 238 T 400 232 V260 H0Z" fill="#fff" opacity=".18"/>`; break;
    case "fiaccole": {
      for (let i = 0; i < 40; i++) s += `<circle cx="${(R() * W).toFixed(1)}" cy="${(R() * 150).toFixed(1)}" r="${(0.6 + R() * 1.3).toFixed(1)}" fill="#FFF7EC" opacity="${(0.35 + R() * 0.6).toFixed(2)}"/>`;
      s += `<path d="M300 28 a20 20 0 1 0 22 26 a15 15 0 1 1 -22 -26z" fill="#FFF3D6" opacity=".85"/>`;
      s += `<path d="M150 260 L235 150 L262 176 L300 120 L345 170 L400 140 V260Z" fill="#0B0818" opacity=".55"/>`;
      s += `<defs><radialGradient id="${id}f"><stop offset="0" stop-color="#FFD58A" stop-opacity=".95"/><stop offset=".35" stop-color="#F28C28" stop-opacity=".55"/><stop offset="1" stop-color="#F28C28" stop-opacity="0"/></radialGradient></defs>`;
      [[248, 182], [272, 198], [296, 186], [322, 204], [350, 192], [376, 210]].forEach(([x, y]) => { s += `<circle cx="${x}" cy="${y}" r="16" fill="url(#${id}f)"/><circle cx="${x}" cy="${y}" r="2.4" fill="#FFF1C9"/>`; });
      break; }
    case "coriandoli": {
      const col = ["var(--leaf)", "var(--sun)", "var(--sky)", "#ffffff"];
      for (let i = 0; i < 44; i++) s += `<rect x="${(R() * W).toFixed(1)}" y="${(R() * H).toFixed(1)}" width="${(4 + R() * 5).toFixed(1)}" height="${(7 + R() * 7).toFixed(1)}" rx="1.5" style="fill:${col[i % 4]}" opacity=".8" transform="rotate(${(R() * 180).toFixed(0)} ${(R() * W).toFixed(0)} ${(R() * H).toFixed(0)})"/>`;
      break; }
    case "fiori":
      [[350, 40, 1.4], [300, 120, .9], [385, 150, .7], [250, 30, .6]].forEach(([x, y, k]) => {
        let p = ""; for (let i = 0; i < 5; i++) p += `<ellipse cx="0" cy="-12" rx="7" ry="12" transform="rotate(${i * 72})" style="fill:var(--leaf)" opacity=".75"/>`;
        s += `<g transform="translate(${x} ${y}) scale(${k})">${p}<circle r="5" style="fill:var(--sun)"/></g>`; });
      break;
    case "foglie": {
      const col = ["var(--leaf)", "var(--sun)", "#E8590C", "#ffffff"];
      for (let i = 0; i < 22; i++) { const x = (R() * W).toFixed(0), y = (R() * H).toFixed(0), r = (R() * 360).toFixed(0), k = (0.6 + R() * 0.9).toFixed(2);
        s += `<path transform="translate(${x} ${y}) rotate(${r}) scale(${k})" d="M0 -14 C 8 -10 12 -2 10 6 C 6 12 -6 12 -10 6 C -12 -2 -8 -10 0 -14Z" style="fill:${col[i % 4]}" opacity="${i % 4 === 3 ? .25 : .7}"/>`; }
      break; }
    case "fuochi": {
      const scoppi = [[320, 52, 46, "var(--leaf)"], [380, 120, 30, "#ffffff"], [250, 30, 24, "var(--sun)"], [300, 170, 20, "var(--leaf)"]];
      scoppi.forEach(([x, y, r, col], n) => { for (let i = 0; i < 14; i++) { const a = i / 14 * Math.PI * 2 + n;
        s += `<line x1="${(x + Math.cos(a) * r * .35).toFixed(1)}" y1="${(y + Math.sin(a) * r * .35).toFixed(1)}" x2="${(x + Math.cos(a) * r).toFixed(1)}" y2="${(y + Math.sin(a) * r).toFixed(1)}" style="stroke:${col}" stroke-width="2.2" stroke-linecap="round" opacity=".8"/>`;
        s += `<circle cx="${(x + Math.cos(a) * r * 1.12).toFixed(1)}" cy="${(y + Math.sin(a) * r * 1.12).toFixed(1)}" r="1.6" style="fill:${col}" opacity=".9"/>`; } });
      for (let i = 0; i < 18; i++) s += `<circle cx="${(R() * W).toFixed(1)}" cy="${(R() * 140).toFixed(1)}" r="${(0.6 + R()).toFixed(1)}" fill="#fff" opacity="${(0.3 + R() * 0.5).toFixed(2)}"/>`;
      break; }
    case "sole": {
      let raggi = ""; for (let i = 0; i < 12; i++) raggi += `<rect x="-3" y="-118" width="6" height="26" rx="3" transform="rotate(${i * 30})"/>`;
      s = `<g transform="translate(350 40)" style="fill:var(--sun)" opacity=".85"><circle r="70"/>${raggi}</g>`;
      s += `<path d="M0 230 Q 50 214 100 230 T 200 230 T 300 230 T 400 230 V260 H0Z" fill="#fff" opacity=".16"/><path d="M0 244 Q 50 230 100 244 T 200 244 T 300 244 T 400 244 V260 H0Z" fill="#fff" opacity=".12"/>`;
      break; }
    default: s = "";
  }
  return `<svg class="deco" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMaxYMin slice" aria-hidden="true" focusable="false">${s}</svg>`;
}

/* ---------- Il logo Auser, con gli accessori delle feste ---------- */
const LOGO_AUSER = "<path fill=\"#3AAA35\" fill-rule=\"nonzero\" d=\"M40.9429 104.731C36.8911 100.803 35.4072 94.6152 36.8721 87.7637C38.7524 79.8467 43.6494 73.4795 47.4268 69.5303C60.7754 55.582 80.7534 45.2397 100.863 41.8721C106.038 41.0073 112.461 40.5171 118.49 40.5171C120.315 40.5171 122.083 40.5557 123.773 40.646C124 41.6787 124.319 43.4785 124.367 44.0078C127.625 75.3047 85.9082 97.1377 73.0469 103.086C63.5015 107.506 54.8335 109.196 47.7852 108.151C45.0361 107.647 42.7979 106.531 40.9429 104.731M37.9463 105.447L37.9463 105.454L37.9463 105.447ZM168.378 53.0142C165.194 49.2725 160.639 44.8203 151 40.1494C144.081 37.0332 136.219 34.6914 127.629 33.1748C124.574 27.2007 120.273 21.6714 114.848 16.7231C114.238 16.1812 113.615 15.665 112.996 15.1489L112.744 14.9424C97.6958 2.59375 78.3633 0 64.7979 0C62.5947 0 60.3496 .0712891 58.127 .206543C41.3589 1.24512 26.168 6.76807 14.207 16.1875C13.397 16.8198 12.5967 17.4585 11.8193 18.1357C7.41602 21.936 3.57715 26.2847 .396484 31.0459L0 31.6396L10.5264 39.2075L10.9614 38.6201C22.917 22.4521 42.3428 12.6904 65.6724 11.1357C68.0498 10.9683 70.2373 10.8906 72.3501 10.8906L73.2241 10.897C84.4209 11.0132 95.1538 13.1875 104.257 17.1748C112.338 20.7295 117.944 25.7876 120.935 32.2329C119.916 32.1299 118.89 32.0459 117.864 31.9751C115.486 31.8008 113.048 31.7104 110.615 31.7104C84.7891 31.7104 58.7334 41.2915 40.9106 57.3564C30.9072 66.3691 25.9102 78.292 27.2041 90.0605C27.4746 92.499 27.9971 94.873 28.7783 97.1699C32.707 106.035 43.9297 116.815 55.2461 118.777C56.7305 118.964 58.2432 119.061 59.7593 119.067L59.8623 119.067C63.1436 119.067 66.437 118.667 69.6533 117.887C83.2051 114.609 95.2603 106.551 105.496 99.2607C115.596 92.0664 123.409 82.7373 128.093 72.2666C129.81 68.4277 131.016 64.4531 131.661 60.4531C132.558 54.9434 132.187 47.459 130.758 41.4463C130.768 41.4526 130.78 41.4526 130.796 41.4526L131.535 41.5625C143.132 43.1943 153.648 46.8203 161.949 52.04C163.152 52.7881 163.897 53.311 165.12 54.1885C165.816 54.6914 166.133 54.9434 166.352 55.124L167.029 55.7109C168.062 56.6143 168.584 57.0464 169.143 57.0464C169.562 57.0464 170.017 56.7627 170.088 55.9561C170.056 55.7305 169.849 54.8657 168.378 53.0142\"/><path fill=\"#1D1D1B\" fill-rule=\"nonzero\" d=\"M183.659 91.8018C183.659 85.3633 179.269 78.4404 172.246 78.4404C165.22 78.4404 160.923 85.3633 160.923 91.8018C160.923 98.2412 165.22 105.267 172.246 105.267C179.269 105.267 183.659 98.2412 183.659 91.8018M195.759 115.81L182.291 115.81L182.291 111.415L182.098 111.415C179.172 115.216 174.098 117.364 169.12 117.364C155.074 117.364 147.071 104.59 147.071 91.6084C147.071 78.9248 155.168 66.3369 168.923 66.3369C173.9 66.3369 178.975 68.4854 182.291 72.3887L182.291 67.8984L195.759 67.8984L195.759 115.81Z\"/><path fill=\"#1D1D1B\" fill-rule=\"nonzero\" d=\"M217.999 67.8984L217.999 93.8535C217.999 99.3184 218.876 105.854 225.806 105.854C232.734 105.854 233.611 99.3184 233.611 93.8535L233.611 67.8984L247.264 67.8984L247.264 96.0986C247.264 110.048 240.051 117.364 225.806 117.364C211.56 117.364 204.34 110.048 204.34 96.0986L204.34 67.8984L217.999 67.8984Z\"/><path fill=\"#1D1D1B\" fill-rule=\"nonzero\" d=\"M280.438 79.2148C278.49 77.3633 275.948 75.8984 273.226 75.8984C270.974 75.8984 268.735 77.6533 268.735 80.002C268.735 83.5117 273.71 84.4854 278.587 86.6338C283.562 88.7822 288.438 92.0986 288.438 100.39C288.438 111.028 279.858 117.364 269.806 117.364C263.367 117.364 257.122 114.441 252.929 109.364L259.174 101.267C261.806 104.196 265.315 106.828 269.315 106.828C272.342 106.828 274.78 104.783 274.78 101.654C274.78 97.46 269.999 96.4863 265.219 94.4346C260.438 92.3896 255.664 89.5566 255.664 81.8467C255.664 72.8789 261.902 66.3438 270.877 66.3438C275.948 66.3438 282.387 67.8984 286.297 71.3174L280.438 79.2148Z\"/><path fill=\"#1D1D1B\" fill-rule=\"nonzero\" d=\"M324.543 85.5566C323.858 80.6797 320.736 75.8984 315.465 75.8984C310.001 75.8984 306.975 80.583 306.291 85.5566L324.543 85.5566ZM305.91 94.0479C305.91 100.093 308.245 106.925 315.368 106.925C319.858 106.925 322.685 104.196 324.543 100.39L337.124 102.435C333.808 111.996 325.42 117.364 315.368 117.364C300.529 117.364 291.458 106.828 291.458 92.292C291.458 77.75 299.175 66.3369 314.685 66.3369C330.388 66.3369 337.421 77.9502 337.421 92.3896L337.421 94.0479L305.91 94.0479Z\"/><path fill=\"#1D1D1B\" fill-rule=\"nonzero\" d=\"M356.44 72.8789L356.634 72.8789C359.369 68.6787 363.466 66.3369 368.544 66.3369C370.492 66.3369 372.44 66.8271 374.195 67.5107L372.544 80.1953C370.88 79.0215 368.931 78.4404 366.879 78.4404C357.415 78.4404 356.44 86.8281 356.44 94.2412L356.44 115.81L342.782 115.81L342.782 67.8984L356.44 67.8984L356.44 72.8789Z\"/>";
const ACCESSORI_LOGO = {"natale": "<g transform=\"translate(72 6) scale(1.15) translate(-72 -6)\"><g>\n<path d=\"M30 9 C 40 -26, 66 -46, 94 -44 C 112 -43, 124 -32, 128 -16 C 120 -24, 112 -26, 106 -22 C 106 -10, 102 0, 98 5 Z\" fill=\"#C8102E\"/>\n<path d=\"M94 -44 C 112 -43, 124 -32, 128 -16 C 120 -24, 112 -26, 106 -22 C 104 -32, 100 -40, 94 -44Z\" fill=\"#9E0B23\"/>\n<path d=\"M44 -14 C 56 -30, 70 -38, 84 -38\" fill=\"none\" stroke=\"#E2334D\" stroke-width=\"3\" stroke-linecap=\"round\" opacity=\".6\"/>\n<path d=\"M24 14 C 46 -6, 80 -10, 104 6\" fill=\"none\" stroke=\"#D9D9D9\" stroke-width=\"15\" stroke-linecap=\"round\"/>\n<path d=\"M24 12 C 46 -8, 80 -12, 104 4\" fill=\"none\" stroke=\"#FFFFFF\" stroke-width=\"13\" stroke-linecap=\"round\"/>\n<circle cx=\"128\" cy=\"-14\" r=\"9.5\" fill=\"#D9D9D9\"/><circle cx=\"127.4\" cy=\"-14.6\" r=\"8.6\" fill=\"#FFFFFF\"/>\n</g></g>", "vecchia": "<g transform=\"translate(72 6) scale(1.3) translate(-72 -6)\"><defs><radialGradient id=\"gv\"><stop offset=\"0\" stop-color=\"#FFE7A3\" stop-opacity=\".95\"/><stop offset=\".4\" stop-color=\"#F7A23B\" stop-opacity=\".45\"/><stop offset=\"1\" stop-color=\"#F28C28\" stop-opacity=\"0\"/></radialGradient></defs>\n<g>\n<!-- asinello -->\n<path d=\"M46 -10 C 44 -20, 56 -26, 72 -25 C 86 -24, 94 -22, 98 -18 L 106 -30 C 109 -34, 116 -33, 118 -28 L 121 -20 C 122 -17, 119 -15, 116 -16 L 110 -18 L 102 -8 C 98 -4, 92 -4, 88 -4 L 58 -4 C 52 -4, 47 -6, 46 -10 Z\" fill=\"#6E655C\"/>\n<path d=\"M107 -31 L 104 -46 C 104 -48, 107 -48, 108 -46 L 111 -33 Z\" fill=\"#6E655C\"/>\n<path d=\"M111 -32 L 112 -45 C 113 -47, 116 -46, 115 -44 L 114 -31 Z\" fill=\"#5A524A\"/>\n<path d=\"M116 -26 L 121 -20 C 122 -17, 119 -15, 116 -16 Z\" fill=\"#3E3832\"/>\n<circle cx=\"112\" cy=\"-27\" r=\"1.1\" fill=\"#1D1D1B\"/>\n<path d=\"M47 -14 C 42 -14, 40 -10, 41 -4\" fill=\"none\" stroke=\"#6E655C\" stroke-width=\"2.4\" stroke-linecap=\"round\"/>\n<path d=\"M54 -6 L 52 4 M 62 -5 L 63 4 M 86 -5 L 84 3 M 94 -6 L 97 2\" stroke=\"#5A524A\" stroke-width=\"4\" stroke-linecap=\"round\"/>\n<!-- la Vecchia avvolta nel lenzuolo bianco -->\n<path d=\"M58 -22 C 58 -38, 64 -56, 74 -58 C 84 -56, 88 -40, 88 -22 C 88 -16, 84 -10, 80 -8 C 74 -12, 66 -12, 60 -8 C 58 -12, 58 -16, 58 -22 Z\" fill=\"#FFFFFF\" stroke=\"#4A4540\" stroke-width=\"1.4\" stroke-linejoin=\"round\"/>\n<path d=\"M66 -40 C 68 -30, 68 -20, 66 -12 M 78 -42 C 79 -32, 80 -22, 80 -12\" fill=\"none\" stroke=\"#C9C3BC\" stroke-width=\"1.2\"/>\n<path d=\"M84 -40 C 90 -46, 94 -52, 96 -58\" fill=\"none\" stroke=\"#FFFFFF\" stroke-width=\"6\" stroke-linecap=\"round\"/>\n<path d=\"M84 -40 C 90 -46, 94 -52, 96 -58\" fill=\"none\" stroke=\"#4A4540\" stroke-width=\"1.4\" stroke-linecap=\"round\" stroke-dasharray=\"0 0\" opacity=\".0\"/>\n<!-- torcia di cera e malva, intrecciata -->\n<circle cx=\"100\" cy=\"-82\" r=\"20\" fill=\"url(#gv)\"/>\n<path d=\"M95 -50 L 99 -74 L 104 -73 L 99 -49 Z\" fill=\"#B07A3B\"/>\n<path d=\"M95.6 -53 L 103 -56 M 96.4 -58 L 103.6 -61 M 97.2 -63 L 104 -66 M 98 -68 L 104 -71\" stroke=\"#7A4A21\" stroke-width=\"1.3\"/>\n<path d=\"M101.5 -96 C 108 -88, 108 -80, 102 -75 C 96 -78, 95 -86, 101.5 -96 Z\" fill=\"#F28C28\"/>\n<path d=\"M101.6 -88 C 104.6 -84, 104.4 -80, 101.8 -78 C 99 -80, 99 -84, 101.6 -88 Z\" fill=\"#FFE29A\"/>\n<!-- fiaccole del corteo, lungo la coda dell'arco -->\n<circle cx=\"146\" cy=\"44\" r=\"7\" fill=\"url(#gv)\"/><circle cx=\"146\" cy=\"44\" r=\"1.6\" fill=\"#FFD27A\"/>\n<circle cx=\"162\" cy=\"52\" r=\"5.5\" fill=\"url(#gv)\"/><circle cx=\"162\" cy=\"52\" r=\"1.3\" fill=\"#FFD27A\"/>\n</g></g>", "carnevale": "<g transform=\"translate(72 6) scale(1.25) translate(-72 -6)\"><g transform=\"translate(66 -14) rotate(-6)\">\n<path d=\"M-34 -2 C -34 -14, -20 -18, -8 -12 C -3 -9, 3 -9, 8 -12 C 20 -18, 34 -14, 34 -2 C 34 10, 20 14, 8 6 C 3 3, -3 3, -8 6 C -20 14, -34 10, -34 -2 Z\" fill=\"#6A2C91\" stroke=\"#D4A62A\" stroke-width=\"2\"/>\n<path d=\"M-24 -3 C -20 -8, -13 -8, -10 -3 C -13 1, -20 1, -24 -3Z M24 -3 C 20 -8, 13 -8, 10 -3 C 13 1, 20 1, 24 -3Z\" fill=\"#FFFFFF\"/>\n<path d=\"M-34 -2 C -40 4, -44 10, -46 18 M 34 -2 C 40 4, 44 10, 46 18\" fill=\"none\" stroke=\"#D4A62A\" stroke-width=\"2\" stroke-linecap=\"round\"/>\n<path d=\"M26 -14 C 30 -32, 42 -40, 52 -42 C 46 -32, 38 -22, 28 -13 Z\" fill=\"#E8B4D8\" stroke=\"#6A2C91\" stroke-width=\"1\"/>\n<circle cx=\"0\" cy=\"-7\" r=\"2.2\" fill=\"#D4A62A\"/>\n</g></g>", "pasqua": "<g transform=\"translate(72 6) scale(1.35) translate(-72 -6)\"><g><path d=\"M22 10 C 50 -12, 86 -16, 118 0\" fill=\"none\" stroke=\"#6B5B3E\" stroke-width=\"2.4\" stroke-linecap=\"round\"/><ellipse cx=\"30\" cy=\"4\" rx=\"12\" ry=\"3.4\" transform=\"rotate(-52 30 4)\" fill=\"#7E9A47\"/><ellipse cx=\"44\" cy=\"-6\" rx=\"12\" ry=\"3.4\" transform=\"rotate(22 44 -6)\" fill=\"#5F7A32\"/><ellipse cx=\"56\" cy=\"-14\" rx=\"12\" ry=\"3.4\" transform=\"rotate(-40 56 -14)\" fill=\"#8DA35A\"/><ellipse cx=\"70\" cy=\"-14\" rx=\"12\" ry=\"3.4\" transform=\"rotate(30 70 -14)\" fill=\"#6B8E23\"/><ellipse cx=\"84\" cy=\"-16\" rx=\"12\" ry=\"3.4\" transform=\"rotate(-28 84 -16)\" fill=\"#7E9A47\"/><ellipse cx=\"98\" cy=\"-10\" rx=\"12\" ry=\"3.4\" transform=\"rotate(36 98 -10)\" fill=\"#5F7A32\"/><ellipse cx=\"110\" cy=\"-6\" rx=\"12\" ry=\"3.4\" transform=\"rotate(-20 110 -6)\" fill=\"#8DA35A\"/><ellipse cx=\"62\" cy=\"-4\" rx=\"4\" ry=\"5.2\" fill=\"#3B2F4A\"/><ellipse cx=\"92\" cy=\"-4\" rx=\"4\" ry=\"5.2\" fill=\"#3B2F4A\"/><ellipse cx=\"61\" cy=\"-5.6\" rx=\"1.2\" ry=\"1.6\" fill=\"#7A6A8A\"/></g></g>", "primavera": "<g transform=\"translate(72 6) scale(1.3) translate(-72 -6)\"><g><path d=\"M20 12 C 48 -14, 90 -18, 124 8\" fill=\"none\" stroke=\"#7A5A44\" stroke-width=\"2.4\" stroke-linecap=\"round\"/><ellipse cx=\"34\" cy=\"-11\" rx=\"5.6\" ry=\"9.0\" transform=\"rotate(0 34 -2)\" fill=\"#FFFFFF\" stroke=\"#E9A7C1\" stroke-width=\".8\"/><ellipse cx=\"34\" cy=\"-11\" rx=\"5.6\" ry=\"9.0\" transform=\"rotate(72 34 -2)\" fill=\"#FFFFFF\" stroke=\"#E9A7C1\" stroke-width=\".8\"/><ellipse cx=\"34\" cy=\"-11\" rx=\"5.6\" ry=\"9.0\" transform=\"rotate(144 34 -2)\" fill=\"#FFFFFF\" stroke=\"#E9A7C1\" stroke-width=\".8\"/><ellipse cx=\"34\" cy=\"-11\" rx=\"5.6\" ry=\"9.0\" transform=\"rotate(216 34 -2)\" fill=\"#FFFFFF\" stroke=\"#E9A7C1\" stroke-width=\".8\"/><ellipse cx=\"34\" cy=\"-11\" rx=\"5.6\" ry=\"9.0\" transform=\"rotate(288 34 -2)\" fill=\"#FFFFFF\" stroke=\"#E9A7C1\" stroke-width=\".8\"/><circle cx=\"34\" cy=\"-2\" r=\"2.9\" fill=\"#D9486F\"/><ellipse cx=\"64\" cy=\"-27\" rx=\"6.8\" ry=\"11.0\" transform=\"rotate(0 64 -16)\" fill=\"#FFFFFF\" stroke=\"#E9A7C1\" stroke-width=\".8\"/><ellipse cx=\"64\" cy=\"-27\" rx=\"6.8\" ry=\"11.0\" transform=\"rotate(72 64 -16)\" fill=\"#FFFFFF\" stroke=\"#E9A7C1\" stroke-width=\".8\"/><ellipse cx=\"64\" cy=\"-27\" rx=\"6.8\" ry=\"11.0\" transform=\"rotate(144 64 -16)\" fill=\"#FFFFFF\" stroke=\"#E9A7C1\" stroke-width=\".8\"/><ellipse cx=\"64\" cy=\"-27\" rx=\"6.8\" ry=\"11.0\" transform=\"rotate(216 64 -16)\" fill=\"#FFFFFF\" stroke=\"#E9A7C1\" stroke-width=\".8\"/><ellipse cx=\"64\" cy=\"-27\" rx=\"6.8\" ry=\"11.0\" transform=\"rotate(288 64 -16)\" fill=\"#FFFFFF\" stroke=\"#E9A7C1\" stroke-width=\".8\"/><circle cx=\"64\" cy=\"-16\" r=\"3.5\" fill=\"#D9486F\"/><ellipse cx=\"96\" cy=\"-19.5\" rx=\"5.9\" ry=\"9.5\" transform=\"rotate(0 96 -10)\" fill=\"#FFFFFF\" stroke=\"#E9A7C1\" stroke-width=\".8\"/><ellipse cx=\"96\" cy=\"-19.5\" rx=\"5.9\" ry=\"9.5\" transform=\"rotate(72 96 -10)\" fill=\"#FFFFFF\" stroke=\"#E9A7C1\" stroke-width=\".8\"/><ellipse cx=\"96\" cy=\"-19.5\" rx=\"5.9\" ry=\"9.5\" transform=\"rotate(144 96 -10)\" fill=\"#FFFFFF\" stroke=\"#E9A7C1\" stroke-width=\".8\"/><ellipse cx=\"96\" cy=\"-19.5\" rx=\"5.9\" ry=\"9.5\" transform=\"rotate(216 96 -10)\" fill=\"#FFFFFF\" stroke=\"#E9A7C1\" stroke-width=\".8\"/><ellipse cx=\"96\" cy=\"-19.5\" rx=\"5.9\" ry=\"9.5\" transform=\"rotate(288 96 -10)\" fill=\"#FFFFFF\" stroke=\"#E9A7C1\" stroke-width=\".8\"/><circle cx=\"96\" cy=\"-10\" r=\"3.0\" fill=\"#D9486F\"/><ellipse cx=\"120\" cy=\"-1\" rx=\"4.3\" ry=\"7.0\" transform=\"rotate(0 120 6)\" fill=\"#FFFFFF\" stroke=\"#E9A7C1\" stroke-width=\".8\"/><ellipse cx=\"120\" cy=\"-1\" rx=\"4.3\" ry=\"7.0\" transform=\"rotate(72 120 6)\" fill=\"#FFFFFF\" stroke=\"#E9A7C1\" stroke-width=\".8\"/><ellipse cx=\"120\" cy=\"-1\" rx=\"4.3\" ry=\"7.0\" transform=\"rotate(144 120 6)\" fill=\"#FFFFFF\" stroke=\"#E9A7C1\" stroke-width=\".8\"/><ellipse cx=\"120\" cy=\"-1\" rx=\"4.3\" ry=\"7.0\" transform=\"rotate(216 120 6)\" fill=\"#FFFFFF\" stroke=\"#E9A7C1\" stroke-width=\".8\"/><ellipse cx=\"120\" cy=\"-1\" rx=\"4.3\" ry=\"7.0\" transform=\"rotate(288 120 6)\" fill=\"#FFFFFF\" stroke=\"#E9A7C1\" stroke-width=\".8\"/><circle cx=\"120\" cy=\"6\" r=\"2.2\" fill=\"#D9486F\"/><ellipse cx=\"80\" cy=\"-22\" rx=\"3.4\" ry=\"5\" transform=\"rotate(20 80 -22)\" fill=\"#F4B6CC\"/><ellipse cx=\"48\" cy=\"-14\" rx=\"3\" ry=\"4.4\" transform=\"rotate(-30 48 -14)\" fill=\"#F4B6CC\"/><path d=\"M106 -2 q 6 -10 14 -10 q -4 8 -14 10z M50 2 q -4 -10 -12 -12 q 2 8 12 12z\" fill=\"#7FAF4E\"/></g></g>", "estate": "<g transform=\"translate(72 6) scale(1.3) translate(-72 -6)\"><g>\n<path d=\"M30 6 C 52 -14, 84 -18, 112 -4\" fill=\"none\" stroke=\"#5B4A33\" stroke-width=\"2.4\" stroke-linecap=\"round\"/>\n<path d=\"M44 -6 C 44 -22, 56 -30, 66 -30 C 62 -18, 54 -10, 44 -6Z\" fill=\"#2E7D32\"/><path d=\"M96 -12 C 100 -28, 112 -32, 120 -30 C 116 -18, 106 -12, 96 -12Z\" fill=\"#3E8E41\"/>\n<path d=\"M50 -10 C 54 -20, 58 -24, 64 -28\" fill=\"none\" stroke=\"#1B5E20\" stroke-width=\".9\"/><path d=\"M100 -14 C 106 -22, 112 -26, 118 -29\" fill=\"none\" stroke=\"#1B5E20\" stroke-width=\".9\"/>\n<g transform=\"translate(76 -26) rotate(-20)\"><ellipse rx=\"16\" ry=\"12\" fill=\"#F7D21E\"/><ellipse cx=\"-17\" rx=\"3\" ry=\"2.4\" fill=\"#E8C010\"/><ellipse cx=\"17\" rx=\"2.6\" ry=\"2\" fill=\"#E8C010\"/><ellipse cx=\"-5\" cy=\"-5\" rx=\"5\" ry=\"2.4\" fill=\"#FFF3A6\" opacity=\".8\"/></g>\n<g transform=\"translate(90 -4) rotate(25)\"><ellipse rx=\"13\" ry=\"10\" fill=\"#F2C811\"/><ellipse cx=\"-14\" rx=\"2.6\" ry=\"2\" fill=\"#E0B60C\"/><ellipse cx=\"-4\" cy=\"-4\" rx=\"4\" ry=\"2\" fill=\"#FFF3A6\" opacity=\".7\"/></g>\n</g></g>", "autunno": "<g transform=\"translate(72 6) scale(1.3) translate(-72 -6)\"><g><g transform=\"translate(44 -10) rotate(-58) scale(1.0)\"><path d=\"M0 -26 L3 -20 L5 -21 L6 -14 L8 -14 L8 -7 L10 -6 L8 2 L9 4 L5 10 L2 18 L0 22 L-2 18 L-5 10 L-9 4 L-8 2 L-10 -6 L-8 -7 L-8 -14 L-6 -14 L-5 -21 L-3 -20 Z\" fill=\"#D9480F\"/><path d=\"M0 -24 V22\" stroke=\"#7A3E12\" stroke-width=\"1\"/></g><g transform=\"translate(70 -20) rotate(-10) scale(1.05)\"><path d=\"M0 -26 L3 -20 L5 -21 L6 -14 L8 -14 L8 -7 L10 -6 L8 2 L9 4 L5 10 L2 18 L0 22 L-2 18 L-5 10 L-9 4 L-8 2 L-10 -6 L-8 -7 L-8 -14 L-6 -14 L-5 -21 L-3 -20 Z\" fill=\"#E8920C\"/><path d=\"M0 -24 V22\" stroke=\"#7A3E12\" stroke-width=\"1\"/></g><g transform=\"translate(100 -12) rotate(48) scale(0.95)\"><path d=\"M0 -26 L3 -20 L5 -21 L6 -14 L8 -14 L8 -7 L10 -6 L8 2 L9 4 L5 10 L2 18 L0 22 L-2 18 L-5 10 L-9 4 L-8 2 L-10 -6 L-8 -7 L-8 -14 L-6 -14 L-5 -21 L-3 -20 Z\" fill=\"#B5651D\"/><path d=\"M0 -24 V22\" stroke=\"#7A3E12\" stroke-width=\"1\"/></g><g transform=\"translate(84 -2)\"><path d=\"M-9 4 C -10 -6, -4 -12, 0 -13 C 4 -12, 10 -6, 9 4 C 6 8, -6 8, -9 4 Z\" fill=\"#6B3A1E\"/><path d=\"M-9 4 C -6 8, 6 8, 9 4 C 6 2, -6 2, -9 4Z\" fill=\"#D9B98C\"/><ellipse cx=\"-3\" cy=\"-6\" rx=\"2\" ry=\"3.4\" fill=\"#8C5530\" opacity=\".8\"/></g></g></g>", "sangiacomo": "<g transform=\"translate(72 6) scale(1.25) translate(-72 -6)\"><g>\n<path d=\"M36 12 L 118 -64\" stroke=\"#7A5230\" stroke-width=\"3.4\" stroke-linecap=\"round\"/>\n<path d=\"M112 -60 C 106 -54, 108 -46, 114 -44 C 120 -46, 122 -54, 116 -60 Z\" fill=\"#C88A3A\"/><path d=\"M113 -62 h4 v4 h-4z\" fill=\"#7A5230\"/>\n<g transform=\"translate(70 -18)\">\n<path d=\"M0 10 C -16 6, -30 -6, -26 -18 C -20 -28, -8 -32, 0 -32 C 8 -32, 20 -28, 26 -18 C 30 -6, 16 6, 0 10 Z\" fill=\"#E1B43C\" stroke=\"#A8851B\" stroke-width=\"1.6\"/>\n<path d=\"M0 10 L-20.8 -5.0\" stroke=\"#A8851B\" stroke-width=\"1.3\"/><path d=\"M0 10 L-15.4 -13.0\" stroke=\"#A8851B\" stroke-width=\"1.3\"/><path d=\"M0 10 L-8.2 -18.2\" stroke=\"#A8851B\" stroke-width=\"1.3\"/><path d=\"M0 10 L0.0 -20.0\" stroke=\"#A8851B\" stroke-width=\"1.3\"/><path d=\"M0 10 L8.2 -18.2\" stroke=\"#A8851B\" stroke-width=\"1.3\"/><path d=\"M0 10 L15.4 -13.0\" stroke=\"#A8851B\" stroke-width=\"1.3\"/><path d=\"M0 10 L20.8 -5.0\" stroke=\"#A8851B\" stroke-width=\"1.3\"/>\n<path d=\"M-8 8 L -12 16 L 12 16 L 8 8 Z\" fill=\"#E1B43C\" stroke=\"#A8851B\" stroke-width=\"1.4\"/>\n<path d=\"M-26 -18 C -14 -22, 14 -22, 26 -18\" fill=\"none\" stroke=\"#F6D77A\" stroke-width=\"1.2\" opacity=\".8\"/>\n</g></g></g>"};
function logoSvg(t) {
  const a = ACCESSORI_LOGO[t.logo || ""];
  return a ? `<svg class="logo-svg acc" viewBox="0 -128 374.2 247.07" role="img" aria-label="Auser">${LOGO_AUSER}${a}</svg>`
           : `<svg class="logo-svg" viewBox="0 0 374.2 119.07" role="img" aria-label="Auser">${LOGO_AUSER}</svg>`;
}
