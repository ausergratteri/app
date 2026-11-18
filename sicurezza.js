/* ---------- Controlli di sicurezza sui dati mostrati nell'app ----------
   Funzioni piccole e senza dipendenze: le usa app.js nel browser e
   test/sicurezza.test.js con Node. */

// Solo link web (http/https). "javascript:", "data:" e simili diventano "".
function linkSicuro(u) {
  const s = String(u ?? "").trim();
  if (!s) return "";
  try {
    const x = new URL(s);
    return x.protocol === "https:" || x.protocol === "http:" ? x.href : "";
  } catch (e) { return ""; }
}

// Indirizzo da mettere dentro url('…') in uno stile: i caratteri che potrebbero
// chiudere url() o la stringa vengono codificati, così non si esce dal CSS.
function urlCss(u) {
  return String(u ?? "").replace(/['"()\\\s<>;{}]/g, c => "%" + c.charCodeAt(0).toString(16).padStart(2, "0").toUpperCase());
}

// Il file sta nella cartella di chi ha caricato la foto? (es. "<user_id>/123-abc.jpg")
function percorsoDi(percorso, userId) {
  const p = String(percorso || ""), u = String(userId || "");
  if (!u || !p.startsWith(u + "/")) return false;
  const resto = p.slice(u.length + 1);
  return resto !== "" && !resto.includes("/") && !resto.includes("..");
}

// Accompagnatori: sempre una lista di {nome, rel} testuali, anche con dati vecchi o rovinati.
function accSicuri(acc) {
  if (!Array.isArray(acc)) return [];
  return acc.filter(a => a && typeof a === "object" && !Array.isArray(a))
    .map(a => ({...a, nome: typeof a.nome === "string" ? a.nome : "", rel: typeof a.rel === "string" ? a.rel : ""}));
}

if (typeof module !== "undefined" && module.exports) module.exports = {linkSicuro, urlCss, percorsoDi, accSicuri};
