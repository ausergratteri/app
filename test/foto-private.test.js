const test = require("node:test");
const assert = require("node:assert/strict");
const {firmaFoto} = require("../sicurezza.js");

test("foto: genera URL temporanei per più immagini", async () => {
  const foto = [
    {id: "1", percorso: "utente/a.jpg", url: "https://esempio.it/pubblica-a.jpg"},
    {id: "2", percorso: "utente/b.jpg", url: "https://esempio.it/pubblica-b.jpg"}
  ];

  const storage = {
    async createSignedUrls(paths, durata) {
      assert.deepEqual(paths, ["utente/a.jpg", "utente/b.jpg"]);
      assert.equal(durata, 3600);
      return {
        data: paths.map(path => ({
          path,
          signedUrl: "https://esempio.it/sign/" + path + "?token=test"
        })),
        error: null
      };
    }
  };

  const risultato = await firmaFoto(foto, storage);
  assert.equal(risultato.length, 2);
  assert.match(risultato[0].url, /\/sign\//);
  assert.match(risultato[1].url, /\/sign\//);
  assert.equal(foto[0].url, "https://esempio.it/pubblica-a.jpg");
});

test("foto: un errore non deve riutilizzare URL pubblici", async () => {
  const foto = [{percorso: "utente/a.jpg", url: "https://esempio.it/pubblica.jpg"}];
  const storage = {
    async createSignedUrls() {
      return {data: null, error: new Error("Accesso negato")};
    }
  };

  await assert.rejects(() => firmaFoto(foto, storage));
});

test("foto: un percorso mancante deve essere rifiutato", async () => {
  const storage = {
    async createSignedUrls() {
      throw new Error("Non dovrebbe essere chiamato");
    }
  };

  await assert.rejects(
    () => firmaFoto([{url: "https://esempio.it/pubblica.jpg"}], storage)
  );
});
