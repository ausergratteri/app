const test = require("node:test");
const assert = require("node:assert/strict");
const {firmaGallerie, messaggioErrore, bucketDi} = require("../sicurezza.js");

// Storage finto: firma i percorsi esistenti, risponde in ordine inverso, registra le chiamate
function storageFinto({esistenti = null, errore = null, nonHttps = false} = {}) {
  const chiamate = [];
  return {
    chiamate,
    from(bucket) {
      return {
        async createSignedUrls(percorsi, durata) {
          chiamate.push({bucket, percorsi: [...percorsi], durata});
          if (errore) return {data: null, error: errore};
          return {data: percorsi.map(p => (!esistenti || esistenti.has(bucket + "/" + p))
            ? {path: p, error: null, signedUrl: `${nonHttps ? "http" : "https"}://x.supabase.co/sign/${bucket}/${p}?t=1`}
            : {path: p, error: "Object not found", signedUrl: null}).reverse(), error: null};
        }
      };
    }
  };
}
const foto = (id, percorso, bucket) => ({id, percorso, url: `https://x.supabase.co/object/public/foto/${percorso}`, ...(bucket ? {bucket} : {})});

test("gallerie: ogni foto firmata nel suo bucket, abbinata per percorso", async () => {
  const st = storageFinto();
  const r = await firmaGallerie([foto("1", "u/a.jpg"), foto("2", "u/b.jpg", "foto-private"), foto("3", "u/c.jpg", "foto")], st);
  assert.equal(r.scartate, 0);
  assert.deepEqual(r.foto.map(f => f.url), [
    "https://x.supabase.co/sign/foto/u/a.jpg?t=1",
    "https://x.supabase.co/sign/foto-private/u/b.jpg?t=1",
    "https://x.supabase.co/sign/foto/u/c.jpg?t=1"]);
  assert.deepEqual(st.chiamate.map(c => c.bucket).sort(), ["foto", "foto-private"]);
  assert.ok(st.chiamate.every(c => c.durata === 3600));
});

test("gallerie: foto non firmabili tolte, mai mostrate con l'URL pubblico", async () => {
  const st = storageFinto({esistenti: new Set(["foto/u/a.jpg"])});
  const r = await firmaGallerie([foto("1", "u/a.jpg"), foto("2", "u/manca.jpg"), foto("3", ""), foto("4", "u/x.jpg", "altro-bucket")], st);
  assert.deepEqual(r.foto.map(f => f.id), ["1"]);
  assert.equal(r.scartate, 3);
  assert.ok(r.foto.every(f => !f.url.includes("/public/")));
  // Il bucket sconosciuto non viene nemmeno interrogato
  assert.ok(st.chiamate.every(c => c.bucket !== "altro-bucket"));
});

test("gallerie: Storage che non risponde → errore (l'app mostra l'avviso)", async () => {
  await assert.rejects(() => firmaGallerie([foto("1", "u/a.jpg")], storageFinto({errore: new Error("giù")})));
  await assert.rejects(() => firmaGallerie([foto("1", "u/a.jpg")], null));
  await assert.rejects(() => firmaGallerie("non una lista", storageFinto()));
});

test("gallerie: URL non https rifiutati", async () => {
  const r = await firmaGallerie([foto("1", "u/a.jpg")], storageFinto({nonHttps: true}));
  assert.equal(r.foto.length, 0);
  assert.equal(r.scartate, 1);
});

test("gallerie: molte foto firmate a blocchi, percorsi ripetuti una volta sola", async () => {
  const st = storageFinto();
  const tante = Array.from({length: 204}, (_, i) => foto(String(i), `u/${i}.jpg`, "foto-private"));
  tante.push(foto("doppia", "u/0.jpg", "foto-private"));
  const r = await firmaGallerie(tante, st);
  assert.equal(r.foto.length, 205);
  assert.deepEqual(st.chiamate.map(c => c.percorsi.length), [100, 100, 4]);
});

test("gallerie: URL ancora validi riusati, si firmano solo le foto nuove", async () => {
  const st = storageFinto();
  const gia = new Map([["foto-private/u/a.jpg", "https://x.supabase.co/sign/foto-private/u/a.jpg?t=vecchio"]]);
  const r = await firmaGallerie([foto("1", "u/a.jpg", "foto-private"), foto("2", "u/b.jpg", "foto-private")], st, {giaFirmate: gia});
  assert.equal(r.foto[0].url, "https://x.supabase.co/sign/foto-private/u/a.jpg?t=vecchio");
  assert.deepEqual(st.chiamate.flatMap(c => c.percorsi), ["u/b.jpg"]);
  // Stesso percorso ma in un altro bucket: non si confonde
  const r2 = await firmaGallerie([foto("3", "u/a.jpg", "foto")], storageFinto(), {giaFirmate: gia});
  assert.match(r2.foto[0].url, /sign\/foto\/u\/a\.jpg/);
});

test("gallerie: i dati originali non vengono modificati", async () => {
  const originali = [foto("1", "u/a.jpg")];
  const copia = JSON.stringify(originali);
  await firmaGallerie(originali, storageFinto());
  assert.equal(JSON.stringify(originali), copia);
});

test("bucketDi: righe senza colonna bucket stanno nel bucket pubblico", () => {
  assert.equal(bucketDi({}), "foto");
  assert.equal(bucketDi({bucket: "foto-private"}), "foto-private");
  assert.equal(bucketDi(null), "foto");
});

test("messaggi: posti esauriti con il numero di posti rimasti", () => {
  assert.equal(messaggioErrore("Non puoi iscriverti: posti esauriti, restano 2 posti"), "Restano solo 2 posti: togli qualche familiare o amico e riprova.");
  assert.equal(messaggioErrore("Non puoi iscriverti: posti esauriti, restano 1 posti"), "Resta solo 1 posto: togli qualche familiare o amico e riprova.");
  assert.equal(messaggioErrore("Non puoi iscriverti: posti esauriti, restano 0 posti"), "Posti esauriti: non ci si può più iscrivere.");
  assert.equal(messaggioErrore("Non puoi iscriverti: posti esauriti"), "Posti esauriti: non ci si può più iscrivere.");
});
