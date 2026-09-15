#!/usr/bin/env node
/* ---------------------------------------------------------------------
   Proves the Tl-Signature implementation is correct before real money
   depends on it.

   Two checks:
     1. local  — sign, then verify with the matching public key. Catches
                 encoding mistakes (DER vs raw r||s) without a network call.
     2. remote — POST to TrueLayer's /v1/test-signature. 204 means they
                 accept the signature. This is the one that counts.

   Usage:
     node pay/tools/verify-signing.mjs            # local check only
     TL_KID=... TL_PRIVATE_KEY="$(cat ec512-private.pem)" \
       node pay/tools/verify-signing.mjs --remote
   --------------------------------------------------------------------- */

import crypto from "node:crypto";
import { tlSignature, readKey } from "../api/_signing.js";

const remote = process.argv.includes("--remote");
let failed = false;

const ok   = m => console.log(`  \x1b[32m✓\x1b[0m ${m}`);
const bad  = m => { failed = true; console.log(`  \x1b[31m✗\x1b[0m ${m}`); };

// ---- 1. local round trip -------------------------------------------------
console.log("\nlocal signature check");

const { privateKey, publicKey } = crypto.generateKeyPairSync("ec", {
  namedCurve: "secp521r1",
});

const body = JSON.stringify({ amount_in_minor: 999900, currency: "GBP" });
const idem = "619410b3-b00c-406e-bb1b-2982f97edb8b";

const sig = tlSignature({
  kid: "test-kid",
  privateKey: privateKey.export({ type: "sec1", format: "pem" }),
  method: "POST",
  path: "/v3/payments",
  headers: { "Idempotency-Key": idem },
  body,
});

const [headerB64, empty, sigB64] = sig.split(".");
empty === "" ? ok("detached form: header..signature")
             : bad(`payload segment should be empty, got "${empty}"`);

const jose = JSON.parse(Buffer.from(headerB64, "base64url").toString());
jose.alg === "ES512"     ? ok("alg is ES512")              : bad(`alg is ${jose.alg}`);
jose.tl_version === "2"  ? ok("tl_version is 2")           : bad(`tl_version is ${jose.tl_version}`);
jose.tl_headers === "Idempotency-Key"
  ? ok("tl_headers names the signed header")
  : bad(`tl_headers is ${jose.tl_headers}`);

const rawSig = Buffer.from(sigB64, "base64url");
rawSig.length === 132
  ? ok("signature is 132 bytes (raw r||s for P-521, not DER)")
  : bad(`signature is ${rawSig.length} bytes — expected 132; DER encoding leaks in around 137`);

// Rebuild the exact signing input and verify it.
let payload = `POST /v3/payments\nIdempotency-Key: ${idem}\n${body}`;
const signingInput = `${headerB64}.${Buffer.from(payload).toString("base64url")}`;
crypto.verify("sha512", Buffer.from(signingInput),
  { key: publicKey, dsaEncoding: "ieee-p1363" }, rawSig)
  ? ok("signature verifies against its own public key")
  : bad("signature does NOT verify — signing input is wrong");

// A changed body must break it, or the body isn't really covered.
crypto.verify("sha512", Buffer.from(`${headerB64}.${Buffer.from(payload.replace("999900","1")).toString("base64url")}`),
  { key: publicKey, dsaEncoding: "ieee-p1363" }, rawSig)
  ? bad("a tampered amount still verifies — the body is not being signed")
  : ok("tampering with the amount invalidates the signature");

// ---- 2. remote check -----------------------------------------------------
if (remote) {
  console.log("\nremote check against TrueLayer");
  const kid = process.env.TL_KID, key = readKey(process.env.TL_PRIVATE_KEY);
  if (!kid || !key) {
    bad("set TL_KID and TL_PRIVATE_KEY to run the remote check");
  } else {
    const testBody = JSON.stringify({ nonce: crypto.randomUUID() });
    const testIdem = crypto.randomUUID();
    const res = await fetch("https://api.truelayer-sandbox.com/v1/test-signature", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Idempotency-Key": testIdem,
        "Tl-Signature": tlSignature({
          kid, privateKey: key, method: "POST", path: "/v1/test-signature",
          headers: { "Idempotency-Key": testIdem }, body: testBody,
        }),
      },
      body: testBody,
    });
    res.status === 204
      ? ok("TrueLayer accepted the signature (204)")
      : bad(`TrueLayer returned ${res.status}: ${await res.text()}`);
  }
} else {
  console.log("\n  (run with --remote, TL_KID and TL_PRIVATE_KEY to check against TrueLayer)");
}

console.log(failed ? "\n\x1b[31mFAILED\x1b[0m\n" : "\n\x1b[32mall checks passed\x1b[0m\n");
process.exit(failed ? 1 : 0);
