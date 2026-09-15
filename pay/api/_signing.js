/* ---------------------------------------------------------------------
   TrueLayer request signing (JWS v2, ES512, detached payload).

   Every POST to the Payments API must carry a Tl-Signature header. The
   signature covers the verb, the path, a named subset of headers, and the
   exact body bytes — so the body you sign must be the byte-identical string
   you send. Serialise once, sign that string, send that string.

   Spec: github.com/TrueLayer/truelayer-signing/blob/main/request-signing-v2.md
   --------------------------------------------------------------------- */

import crypto from "node:crypto";

const b64u = input => Buffer.from(input).toString("base64url");

/**
 * @param {object}  o
 * @param {string}  o.kid         signing key UUID from the TrueLayer console
 * @param {string}  o.privateKey  PEM, EC P-521 (secp521r1) — ES512 needs P-521
 * @param {string}  o.method      "POST"
 * @param {string}  o.path        absolute path, no trailing slash, no query
 * @param {object}  o.headers     headers to sign, in the order they're listed
 * @param {string}  o.body        the exact serialised body being sent
 */
export function tlSignature({ kid, privateKey, method, path, headers = {}, body = "" }) {
  const jose = {
    alg: "ES512",
    kid,
    tl_version: "2",
    tl_headers: Object.keys(headers).join(","),
  };

  // "<VERB> <path>\n" then "<Name>: <value>\n" per signed header, then body.
  let payload = `${method.toUpperCase()} ${path}\n`;
  for (const [name, value] of Object.entries(headers)) {
    payload += `${name}: ${value}\n`;
  }
  payload += body;

  const header = b64u(JSON.stringify(jose));
  const signingInput = `${header}.${b64u(payload)}`;

  // JWS wants the raw r||s pair (132 bytes for P-521), not ASN.1 DER — which
  // is what Node emits unless you ask for ieee-p1363. Getting this wrong
  // produces a signature that verifies nowhere and a very unhelpful 401.
  const signature = crypto.sign("sha512", Buffer.from(signingInput), {
    key: privateKey,
    dsaEncoding: "ieee-p1363",
  });

  // Detached: the payload segment is omitted, leaving the double dot.
  return `${header}..${b64u(signature)}`;
}

/** Normalises a PEM pasted into an env var, where newlines arrive escaped. */
export function readKey(raw) {
  if (!raw) return null;
  return raw.includes("\\n") ? raw.replace(/\\n/g, "\n") : raw;
}
