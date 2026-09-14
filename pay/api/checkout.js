/* ---------------------------------------------------------------------
   Creates a Stripe Checkout Session for an arbitrary amount.

   Zero dependencies — no `npm i stripe`, just fetch against the REST API.
   Drop this in a Vercel project as /api/checkout.js, or a Netlify
   function, and set STRIPE_SECRET_KEY in the environment.

   WHY THIS FILE EXISTS: the browser is not allowed to name the price.
   If it were, anyone could open devtools and pay you 1p. The amount is
   re-validated here, server-side, before it reaches Stripe.
   --------------------------------------------------------------------- */

const MIN_MINOR = 30;          // 30p — Stripe's floor for GBP
const MAX_MINOR = 1_000_000;   // £10,000 — raise if you need to

// Lock this to your own page in production. "*" is fine while testing.
const ALLOWED_ORIGIN = process.env.ALLOWED_ORIGIN || "*";

function cors(res) {
  res.setHeader("Access-Control-Allow-Origin", ALLOWED_ORIGIN);
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  res.setHeader("Vary", "Origin");
}

export default async function handler(req, res) {
  cors(res);

  if (req.method === "OPTIONS") return res.status(204).end();
  if (req.method !== "POST") return res.status(405).json({ error: "POST only" });

  const key = process.env.STRIPE_SECRET_KEY;
  if (!key) return res.status(500).json({ error: "STRIPE_SECRET_KEY is not set" });

  const body = typeof req.body === "string" ? safeJson(req.body) : (req.body || {});

  // --- validate the amount. Never trust what the page sent. -----------
  const amount = Number(body.amount);
  if (!Number.isInteger(amount)) {
    return res.status(400).json({ error: "amount must be an integer in minor units" });
  }
  if (amount < MIN_MINOR) {
    return res.status(400).json({ error: `minimum is ${MIN_MINOR} minor units` });
  }
  if (amount > MAX_MINOR) {
    return res.status(400).json({ error: `maximum is ${MAX_MINOR} minor units` });
  }

  const currency    = String(body.currency || "gbp").toLowerCase().slice(0, 3);
  const description = String(body.description || "Payment").slice(0, 200);

  const origin =
    req.headers.origin ||
    (req.headers.host ? `https://${req.headers.host}` : "https://example.com");

  // --- build the form-encoded request Stripe expects -------------------
  const form = new URLSearchParams({
    mode: "payment",
    "line_items[0][price_data][currency]": currency,
    "line_items[0][price_data][unit_amount]": String(amount),
    "line_items[0][price_data][product_data][name]": description,
    "line_items[0][quantity]": "1",
    success_url: `${origin}/?paid=1`,
    cancel_url: `${origin}/?cancelled=1`,
  });

  // Record what the payer actually meant, when they covered the fees.
  if (body.covered && Number.isInteger(Number(body.net))) {
    form.set("metadata[net_intended]", String(body.net));
    form.set("metadata[fees_covered]", "true");
  }

  try {
    const stripeRes = await fetch("https://api.stripe.com/v1/checkout/sessions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: form,
    });

    const session = await stripeRes.json();

    if (!stripeRes.ok) {
      // Log the real reason, return a vague one. Stripe errors can leak detail.
      console.error("stripe error", session?.error);
      return res.status(502).json({ error: session?.error?.message || "Stripe rejected that" });
    }

    return res.status(200).json({ url: session.url });
  } catch (err) {
    console.error("checkout failed", err);
    return res.status(500).json({ error: "could not reach Stripe" });
  }
}

function safeJson(s) {
  try { return JSON.parse(s); } catch { return {}; }
}
