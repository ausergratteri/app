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
// I nomi salvati come semplice testo (["Rosa", "Pino"]) vengono conservati, così
// modificando l'iscrizione non si perdono.
function accSicuri(acc) {
  if (!Array.isArray(acc)) return [];
  return acc.map(a => typeof a === "string" ? {nome: a, rel: ""} : a)
    .filter(a => a && typeof a === "object" && !Array.isArray(a))
    .map(a => ({...a, nome: typeof a.nome === "string" ? a.nome : "", rel: typeof a.rel === "string" ? a.rel : ""}));
}

// Messaggio chiaro per gli errori dovuti alle regole del database ("" = nessuno specifico).
function messaggioErrore(m) {
  const s = String(m || "");
  if (/posti esauriti/i.test(s)) return "Posti esauriti: non ci si può più iscrivere.";
  if (/iscrizioni sono chiuse|assemblea è annullata/i.test(s)) return "Le iscrizioni sono chiuse.";
  if (/portare ospiti/i.test(s)) return "A questa attività non si possono portare familiari o amici.";
  if (/attività inesistente/i.test(s)) return "Questa attività non c'è più: riapri l'app.";
  if (/spostare l'iscrizione/i.test(s)) return "L'iscrizione non si può spostare: annullala e iscriviti all'altra attività.";
  if (/impostazioni_link_web/i.test(s)) return "Correggi i link dei social: devono iniziare con https://";
  if (/bacheca_link_web/i.test(s)) return "Il link deve iniziare con https://";
  if (/adesioni_acc_valido/i.test(s)) return "Controlla i familiari e gli amici: al massimo 12, ognuno con il nome.";
  if (/importare i tesserati/i.test(s)) return "Solo il presidente può importare i tesserati.";
  if (/cambiare il telefono/i.test(s)) return "Il numero di telefono può cambiarlo solo il presidente.";
  if (/nome di un'altra persona/i.test(s)) return "Il nome di un'altra persona può cambiarlo solo il presidente.";
  return "";
}

if (typeof module !== "undefined" && module.exports) module.exports = {linkSicuro, urlCss, percorsoDi, accSicuri, messaggioErrore};
