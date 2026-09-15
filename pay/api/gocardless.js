/* ---------------------------------------------------------------------
   Creates a GoCardless Pay by Bank payment (one-off, open banking).

   The payer is sent to their own bank, approves in their banking app, and
   a Faster Payment is pushed to you. Confirmed in seconds, irreversible.

   Pay by Bank, NOT Direct Debit. They are different products with similar
   names and very different pricing: Direct Debit carries a +0.3% surcharge
   on the amount above £2,000 (that's what makes GoCardless's own calculator
   quote £28 on £10,000), while Pay by Bank is capped at £4. The scheme
   below is what selects the cheap one — don't "simplify" it away.

   Zero npm dependencies. Auth is a bearer token: no request signing, no
   key pairs. This is why it's the one to use.
   --------------------------------------------------------------------- */

import crypto from "node:crypto";

const MIN_MINOR = 100;          // £1
const MAX_MINOR = 10_000_000;   // £100,000

const HOSTS = {
  sandbox: "https://api-sandbox.gocardless.com",
  live:    "https://api.gocardless.com",
};

const GC_VERSION = "2015-07-06";
const ALLOWED_ORIGIN = process.env.ALLOWED_ORIGIN || "*";

export default async function handler(req, res) {
  res.setHeader("Access-Control-Allow-Origin", ALLOWED_ORIGIN);
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  res.setHeader("Vary", "Origin");

  if (req.method === "OPTIONS") return res.status(204).end();
  if (req.method !== "POST") return res.status(405).json({ error: "POST only" });

  const token = process.env.GC_ACCESS_TOKEN;
  if (!token) return res.status(500).json({ error: "GC_ACCESS_TOKEN is not set" });

  const api = HOSTS[process.env.GC_ENV === "live" ? "live" : "sandbox"];
  const redirectUri = process.env.GC_REDIRECT_URI;
  const exitUri     = process.env.GC_EXIT_URI || redirectUri;
  if (!redirectUri) return res.status(500).json({ error: "GC_REDIRECT_URI is not set" });

  const body = typeof req.body === "string" ? safeJson(req.body) : (req.body || {});

  // Re-validate here. Whatever the browser sent is a suggestion, not a fact.
  const amount = Number(body.amount);
  if (!Number.isInteger(amount)) return res.status(400).json({ error: "amount must be integer minor units" });
  if (amount < MIN_MINOR)        return res.status(400).json({ error: `minimum is ${MIN_MINOR} minor units` });
  if (amount > MAX_MINOR)        return res.status(400).json({ error: `maximum is ${MAX_MINOR} minor units` });

  const description = String(body.description || "Payment").slice(0, 100);

  const call = (path, payload) => fetch(`${api}${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "GoCardless-Version": GC_VERSION,
      "Content-Type": "application/json",
      "Idempotency-Key": crypto.randomUUID(),
    },
    body: JSON.stringify(payload),
  });

  try {
    // --- 1. the billing request: what is being collected ---------------
    const brRes = await call("/billing_requests", {
      billing_requests: {
        payment_request: {
          description,
          amount,                    // pence, integer
          currency: "GBP",
          scheme: "faster_payments", // Pay by Bank. NOT bacs (Direct Debit).
        },
      },
    });
    const br = await brRes.json();
    if (!brRes.ok || !br.billing_requests?.id) {
      console.error("gocardless billing_request failed", brRes.status, br);
      return res.status(502).json({ error: gcError(br) });
    }

    // --- 2. the flow: the hosted pages the payer walks through ---------
    const flowRes = await call("/billing_request_flows", {
      billing_request_flows: {
        redirect_uri: redirectUri,
        exit_uri: exitUri,
        links: { billing_request: br.billing_requests.id },
      },
    });
    const flow = await flowRes.json();
    if (!flowRes.ok || !flow.billing_request_flows?.authorisation_url) {
      console.error("gocardless flow failed", flowRes.status, flow);
      return res.status(502).json({ error: gcError(flow) });
    }

    return res.status(200).json({
      url: flow.billing_request_flows.authorisation_url,
      billing_request_id: br.billing_requests.id,
    });
  } catch (err) {
    console.error("gocardless failed", err);
    return res.status(500).json({ error: "could not reach GoCardless" });
  }
}

/* GoCardless nests the useful message a few levels down; surface it without
   leaking the whole error object to the browser. */
function gcError(payload) {
  const e = payload?.error;
  return e?.errors?.[0]?.message || e?.message || "GoCardless rejected that";
}

function safeJson(s) { try { return JSON.parse(s); } catch { return {}; } }
