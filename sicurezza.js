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
  const restano = s.match(/restano (\d+) posti/i);
  if (restano && Number(restano[1]) > 0) return (restano[1] === "1" ? "Resta solo 1 posto" : `Restano solo ${restano[1]} posti`) + ": togli qualche familiare o amico e riprova.";
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
  if (/Solo il presidente può (cambiare l'e-mail|azzerare)/i.test(s)) return "Solo il presidente può farlo.";
  if (/E-mail non valida/i.test(s)) return "Controlla l'indirizzo e-mail.";
  if (/Ha già iscrizioni o foto/i.test(s)) return "Ha già iscrizioni o foto: non si può azzerare. Usa «Nuovo PIN».";
  if (/tuo primo accesso/i.test(s)) return "Non puoi azzerare il tuo primo accesso.";
  if (/primo accesso di un presidente/i.test(s)) return "Non si può azzerare il primo accesso di un presidente.";
  if (/(Tesserato|Utente) non trovato/i.test(s)) return "Non l'ho trovato: riapri l'app e riprova.";
  return "";
}


// Genera URL temporanei senza modificare i record originali.
// Se una firma fallisce, non si utilizzano gli URL pubblici.
async function firmaFoto(foto, storage, durata = 3600) {
  if (!Array.isArray(foto)) throw new Error("Elenco fotografie non valido");
  if (!foto.length) return [];

  const percorsi = foto.map(f => typeof f?.percorso === "string" ? f.percorso : "");
  if (percorsi.some(p => !p.trim())) {
    throw new Error("Fotografia senza percorso");
  }

  if (!storage || typeof storage.createSignedUrls !== "function") {
    throw new Error("Servizio Storage non disponibile");
  }

  const {data, error} = await storage.createSignedUrls(percorsi, durata);
  if (error) throw error;

  if (!Array.isArray(data) || data.length !== foto.length) {
    throw new Error("Risposta incompleta da Storage");
  }

  return foto.map((f, i) => {
    const elemento = data[i];
    if (elemento?.error || typeof elemento?.signedUrl !== "string" || !elemento.signedUrl) {
      throw new Error("Impossibile autorizzare una fotografia");
    }
    return {...f, url: elemento.signedUrl};
  });
}

// Bucket delle immagini: "foto" è pubblico (copertine, bacheca, logo),
// "foto-private" contiene le gallerie dei soci e si legge solo con URL firmati.
// ("var" e "function" così app.js li trova anche come window.*)
var BUCKET_PUBBLICO = "foto";
var BUCKET_GALLERIE = "foto-private";
var BUCKET_FOTO = [BUCKET_PUBBLICO, BUCKET_GALLERIE];
function bucketDi(f) { return (f && f.bucket) || BUCKET_PUBBLICO; }  // righe vecchie senza colonna "bucket"

// URL temporanei per le foto delle gallerie, anche se stanno in bucket diversi
// (durante il trasferimento alcune sono ancora nel bucket pubblico).
//  * una foto che non si riesce a firmare viene tolta, MAI mostrata con l'URL pubblico;
//  * se Storage non risponde affatto si lancia un errore (l'app mostra un avviso);
//  * "giaFirmate" (Map "bucket/percorso" → URL) evita di rifirmare foto ancora valide.
// Restituisce {foto, scartate}.
async function firmaGallerie(foto, storage, {durata = 3600, giaFirmate = null, blocco = 100} = {}) {
  if (!Array.isArray(foto)) throw new Error("Elenco fotografie non valido");
  if (!storage || typeof storage.from !== "function") throw new Error("Servizio Storage non disponibile");
  const chiave = f => bucketDi(f) + "/" + f.percorso;
  const valida = f => f && typeof f.percorso === "string" && f.percorso.trim() !== "" && BUCKET_FOTO.includes(bucketDi(f));
  const firmati = new Map();
  const daFirmare = {};
  for (const f of foto) {
    if (!valida(f)) continue;
    const k = chiave(f);
    if (giaFirmate && giaFirmate.has(k)) { firmati.set(k, giaFirmate.get(k)); continue; }
    (daFirmare[bucketDi(f)] ||= new Set()).add(f.percorso);
  }
  for (const [bucket, insieme] of Object.entries(daFirmare)) {
    const percorsi = [...insieme];
    for (let i = 0; i < percorsi.length; i += blocco) {
      const parte = percorsi.slice(i, i + blocco);
      const {data, error} = await storage.from(bucket).createSignedUrls(parte, durata);
      if (error) throw error;
      if (!Array.isArray(data)) throw new Error("Risposta incompleta da Storage");
      // Si abbina per percorso, non per posizione: l'ordine della risposta non è garantito
      for (const d of data) {
        const url = d && !d.error && (d.signedUrl || d.signedURL);
        if (typeof d?.path === "string" && parte.includes(d.path) && typeof url === "string" && /^https:\/\//.test(url)) {
          firmati.set(bucket + "/" + d.path, url);
        }
      }
    }
  }
  const out = [];
  let scartate = 0;
  for (const f of foto) {
    const url = valida(f) ? firmati.get(chiave(f)) : null;
    if (url) out.push({...f, url}); else scartate++;
  }
  return {foto: out, scartate};
}

if (typeof module !== "undefined" && module.exports) module.exports = {linkSicuro, urlCss, percorsoDi, accSicuri, messaggioErrore, firmaFoto, firmaGallerie, bucketDi, BUCKET_PUBBLICO, BUCKET_GALLERIE};
