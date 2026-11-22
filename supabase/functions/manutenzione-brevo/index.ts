// =====================================================================
//  AUSER GRATTERI – Edge Function "manutenzione-brevo" (cron interno, nessun dato dei soci)
//  Chiamata solo da Supabase Cron (operazioni/28_programma_manutenzione_brevo.sql) con l'intestazione
//  x-auser-cron = token in Vault ("auser_brevo_cron_token") uguale al segreto BREVO_CRON_TOKEN.
//  Azioni: "controllo" (verifica mensile che la chiave Brevo funzioni) e "promemoria" (e-mail al
//  presidente 20 giorni prima della scadenza della chiave). Segreti: BREVO_API_KEY, BREVO_MITTENTE,
//  BREVO_CRON_TOKEN — mai nel repository. Codice identico a quello pubblicato il 22/11/2026.
// =====================================================================
const encoder = new TextEncoder();
async function autorizzata(req: Request) {
  const atteso = Deno.env.get("BREVO_CRON_TOKEN");
  const ricevuto = req.headers.get("x-auser-cron");
  if (!atteso || !ricevuto) return false;
  const hash = (valore: string) => crypto.subtle.digest("SHA-256", encoder.encode(valore));
  const [a,b] = await Promise.all([hash(atteso),hash(ricevuto)]);
  const confronto = new Uint8Array(b);
  return new Uint8Array(a).reduce((diff, byte, i) => diff | (byte ^ confronto[i]), 0) === 0;
}
Deno.serve(async req => {
  if (req.method !== "POST") return new Response(null,{status:405});
  if (!await autorizzata(req)) return new Response(null,{status:401});
  const chiave = Deno.env.get("BREVO_API_KEY");
  const mittente = Deno.env.get("BREVO_MITTENTE");
  const corpo = await req.json().catch(() => null);
  if (!chiave || !mittente) return new Response(null,{status:503});
  const headers = {"api-key":chiave,"Content-Type":"application/json"};
  const signal = AbortSignal.timeout(10000);
  try {
    let esito: Response;
    if (corpo?.azione === "controllo") {
      esito = await fetch("https://api.brevo.com/v3/smtp/statistics/reports?days=1&limit=1",{headers,signal,redirect:"error"});
    } else if (corpo?.azione === "promemoria" && /^\d{4}-\d{2}-\d{2}$/.test(corpo.scadenza)) {
      esito = await fetch("https://api.brevo.com/v3/smtp/email",{
        method:"POST",headers,signal,redirect:"error",
        body:JSON.stringify({sender:{name:"AUSER Gratteri",email:mittente},to:[{email:mittente,removeTrackingPixel:true}],
          subject:"AUSER Gratteri: rinnovo chiave Brevo tra 20 giorni",
          textContent:"Presidente, la chiave Brevo per i codici di primo accesso scade il " + corpo.scadenza + ". Genera una nuova chiave con accesso limitato alle e-mail transazionali e aggiorna il segreto in Supabase. Dopo la verifica, aggiorna la data del promemoria."})
      });
    } else return new Response(null,{status:400});
    await esito.body?.cancel();
    console.log(JSON.stringify({azione:corpo.azione,stato_brevo:esito.status}));
    return new Response(null,{status:esito.ok?204:502});
  } catch { return new Response(null,{status:502}); }
});
