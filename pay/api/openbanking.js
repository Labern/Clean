/* ---------------------------------------------------------------------
   Creates an open banking payment (TrueLayer Payments v3).

   The payer is redirected to their own bank, approves with their normal
   biometrics, and their bank executes a Faster Payment. No card network,
   so no interchange and no scheme fees — roughly 20p flat instead of a
   percentage with no ceiling.

   Zero npm dependencies. Node 18+ for global fetch and crypto.randomUUID.
   --------------------------------------------------------------------- */

import crypto from "node:crypto";
import { tlSignature, readKey } from "./_signing.js";

const MIN_MINOR = 100;         // £1 — below this the 20p fee stops being worth it
const MAX_MINOR = 10_000_000;  // £100,000

const HOSTS = {
  sandbox: {
    auth: "https://auth.truelayer-sandbox.com",
    api:  "https://api.truelayer-sandbox.com",
    hpp:  "https://payment.truelayer-sandbox.com/payments",
  },
  live: {
    auth: "https://auth.truelayer.com",
    api:  "https://api.truelayer.com",
    hpp:  "https://payment.truelayer.com/payments",
  },
};

const ALLOWED_ORIGIN = process.env.ALLOWED_ORIGIN || "*";

export default async function handler(req, res) {
  res.setHeader("Access-Control-Allow-Origin", ALLOWED_ORIGIN);
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  res.setHeader("Vary", "Origin");

  if (req.method === "OPTIONS") return res.status(204).end();
  if (req.method !== "POST") return res.status(405).json({ error: "POST only" });

  const env   = process.env.TL_ENV === "live" ? "live" : "sandbox";
  const hosts = HOSTS[env];

  const cfg = {
    clientId:     process.env.TL_CLIENT_ID,
    clientSecret: process.env.TL_CLIENT_SECRET,
    kid:          process.env.TL_KID,
    privateKey:   readKey(process.env.TL_PRIVATE_KEY),
    merchantId:   process.env.TL_MERCHANT_ACCOUNT_ID,
    sortCode:     process.env.TL_SORT_CODE,
    accountNo:    process.env.TL_ACCOUNT_NUMBER,
    accountName:  process.env.TL_ACCOUNT_NAME,
    returnUri:    process.env.TL_RETURN_URI,
  };

  for (const k of ["clientId", "clientSecret", "kid", "privateKey", "returnUri"]) {
    if (!cfg[k]) return res.status(500).json({ error: `TL config missing: ${k}` });
  }

  const body = typeof req.body === "string" ? safeJson(req.body) : (req.body || {});

  // Re-validate server-side. The browser's number is a suggestion, never a fact.
  const amount = Number(body.amount);
  if (!Number.isInteger(amount))  return res.status(400).json({ error: "amount must be integer minor units" });
  if (amount < MIN_MINOR)         return res.status(400).json({ error: `minimum is ${MIN_MINOR} minor units` });
  if (amount > MAX_MINOR)         return res.status(400).json({ error: `maximum is ${MAX_MINOR} minor units` });

  const reference = String(body.reference || "Payment").replace(/[^A-Za-z0-9 .-]/g, "").slice(0, 18);

  try {
    // --- 1. client_credentials token -----------------------------------
    const tokenRes = await fetch(`${hosts.auth}/connect/token`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type:    "client_credentials",
        client_id:     cfg.clientId,
        client_secret: cfg.clientSecret,
        scope:         "payments",
      }),
    });
    const token = await tokenRes.json();
    if (!tokenRes.ok || !token.access_token) {
      console.error("truelayer auth failed", token);
      return res.status(502).json({ error: "could not authenticate with TrueLayer" });
    }

    // --- 2. where the money lands --------------------------------------
    // external_account sends it bank-to-bank straight into your account and
    // never has TrueLayer hold it. merchant_account parks it with them first,
    // which is what you want if you need refunds or payout batching.
    const beneficiary = cfg.merchantId
      ? { type: "merchant_account", merchant_account_id: cfg.merchantId, reference }
      : {
          type: "external_account",
          account_holder_name: cfg.accountName,
          reference,
          account_identifier: {
            type: "sort_code_account_number",
            sort_code: cfg.sortCode,
            account_number: cfg.accountNo,
          },
        };

    if (beneficiary.type === "external_account" && !(cfg.sortCode && cfg.accountNo && cfg.accountName)) {
      return res.status(500).json({
        error: "set TL_MERCHANT_ACCOUNT_ID, or all of TL_SORT_CODE / TL_ACCOUNT_NUMBER / TL_ACCOUNT_NAME",
      });
    }

    // --- 3. create the payment, signed ---------------------------------
    // Serialise once: the bytes signed must be the bytes sent.
    const payload = JSON.stringify({
      amount_in_minor: amount,
      currency: "GBP",
      payment_method: {
        type: "bank_transfer",
        provider_selection: { type: "user_selected" },  // payer picks their bank
        beneficiary,
      },
      user: { id: crypto.randomUUID(), name: body.payerName || undefined },
    });

    const idempotencyKey = crypto.randomUUID();
    const signature = tlSignature({
      kid: cfg.kid,
      privateKey: cfg.privateKey,
      method: "POST",
      path: "/v3/payments",
      headers: { "Idempotency-Key": idempotencyKey },
      body: payload,
    });

    const payRes = await fetch(`${hosts.api}/v3/payments`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token.access_token}`,
        "Content-Type": "application/json",
        "Idempotency-Key": idempotencyKey,
        "Tl-Signature": signature,
      },
      body: payload,
    });

    const payment = await payRes.json();
    if (!payRes.ok || !payment.id || !payment.resource_token) {
      console.error("truelayer payment failed", payRes.status, payment);
      return res.status(502).json({
        error: payment?.detail || payment?.title || "TrueLayer rejected the payment",
      });
    }

    // --- 4. hand back the hosted payment page --------------------------
    const url = `${hosts.hpp}#payment_id=${payment.id}` +
                `&resource_token=${payment.resource_token}` +
                `&return_uri=${encodeURIComponent(cfg.returnUri)}`;

    return res.status(200).json({ url, payment_id: payment.id });
  } catch (err) {
    console.error("openbanking failed", err);
    return res.status(500).json({ error: "could not reach TrueLayer" });
  }
}

function safeJson(s) { try { return JSON.parse(s); } catch { return {}; } }
