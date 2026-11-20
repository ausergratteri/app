// Controlla che una cartella sia su un'immagine disco CIFRATA montata in /Volumes (hdiutil).
// Uso: node destinazione_cifrata.mjs <cartella>  → stampa il percorso reale ed esce con 0; altrimenti STOP ed esce con 1.
// Crea la cartella se manca e le dà permessi 700. Non legge né scrive altro.
import fs from "node:fs";
import path from "node:path";
import {execFileSync} from "node:child_process";

export function destinazioneCifrata(cartella) {
  // Prima il controllo, poi (solo se va bene) la creazione della cartella
  const assoluto = path.resolve(cartella);
  if (!assoluto.startsWith("/Volumes/")) return null;
  const montaggio = assoluto.split("/").slice(0, 3).join("/");
  const info = JSON.parse(execFileSync("sh", ["-c", "hdiutil info -plist | plutil -extract images json -o - -"]).toString() || "[]");
  const cifrata = info.some(i => (i["system-entities"] || []).some(e => e["mount-point"] === montaggio) && i["image-encrypted"] === true);
  if (!cifrata) return null;
  fs.mkdirSync(assoluto, {recursive: true});
  const dest = fs.realpathSync(assoluto);
  if (!dest.startsWith(montaggio + "/") && dest !== montaggio) return null;   // nessun collegamento che porti fuori
  fs.chmodSync(dest, 0o700);
  return dest;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const d = process.argv[2] ? destinazioneCifrata(process.argv[2]) : null;
  if (!d) { console.error(`STOP: ${process.argv[2] || "(nessuna cartella)"} non è su un'immagine disco cifrata montata in /Volumes`); process.exit(1); }
  console.log(d);
}
