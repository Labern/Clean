# Post — iCloud Mail

A proper mail client for iCloud. Live (app only) at `labern.github.io/Clean/post/`;
the full thing (app + bridge, one origin) runs on a free Cloudflare Worker.

## Why it is built this way
- iCloud Mail is the one iCloud service Apple exposes over open standards:
  IMAP `imap.mail.me.com:993` (TLS) and SMTP `smtp.mail.me.com:587` (STARTTLS),
  signed in with an **app-specific password**. No reverse-engineered endpoints,
  so nothing here breaks when Apple changes icloud.com.
- Browsers cannot open TCP sockets, so `bridge/` is a **stateless** HTTP→IMAP/SMTP
  bridge. Every request carries Basic auth, opens a connection, does one job,
  logs out. Nothing is stored. Hosts are hard-coded to Apple's — it is not a
  general socket relay. Cloudflare Workers can do raw TLS via `cloudflare:sockets`.

## Files
- `index.html` — the whole app (single file, no build). Three panes ≥1100px,
  drawer + two panes ≥720px, iOS-style stacked navigation below (`body[data-view]`).
- `bridge/mime.js` — MIME parse/build, RFC 2047/2231, modified UTF-7. Works on
  *binary strings* (one char per byte) until the single, final charset decode.
- `bridge/protocol.js` — IMAP client (literals both directions, continuation,
  LITERAL+) and SMTP client, over an abstract socket.
- `bridge/api.js` — the HTTP API: mailboxes, list, sync, message, raw,
  attachment, flags, move, delete, search, send, draft, ping.
- `bridge/worker.js` (Cloudflare) / `bridge/node.mjs` (local; also serves the app).
- `tests/fake.mjs` — in-memory IMAP+SMTP server that derives ENVELOPE and
  BODYSTRUCTURE from real messages. `tests/run.mjs` (93 assertions: units + the
  bridge end to end over sockets), `tests/ui.mjs` (46: Chromium drives the app,
  desktop + iPhone light/dark; `--shots dir` saves screenshots).

## Commands
- `node post/tests/run.mjs` and `node post/tests/ui.mjs` — both must stay green.
- Local: `node post/bridge/node.mjs` → http://localhost:8787 (real iCloud).
- Deploy: `cd post && npx wrangler deploy` → open the workers.dev URL. The app
  detects a same-origin bridge via `GET api/ping` and hides the Bridge field.
  On GitHub Pages it asks for the bridge URL (or `?bridge=` in the link).

## Decisions that encode real bugs — don't "tidy"
- **windows-1252 is decoded by hand** (`CP1252` table in mime.js). Node's
  TextDecoder decodes `windows-1252`/`iso-8859-1` as raw latin-1, turning smart
  quotes and dashes into invisible C1 controls. A `us-ascii` label on bytes
  that are valid UTF-8 is decoded as UTF-8 (mislabelled mail is common).
- **Adjacent RFC 2047 words are joined at the byte level** before decoding —
  senders split one multibyte character across two words.
- **App-specific passwords are normalised** to `xxxx-xxxx-xxxx-xxxx` (both in
  the app and the bridge): people paste them with spaces or none.
- Email field is `type="text" inputmode="email"`: `type="email"` made the
  browser reject a bare `tim` before we could append `@icloud.com`.
- **iCloud SMTP does not file sent mail**: `send` APPENDs to Sent (`\Seen`) and
  marks the original `\Answered`, like Mail.app.
- Forwarding pulls the original attachments *and inline images* server-side
  (the forwarded body is plain text, so images would otherwise vanish).
- HTML mail renders in `<iframe sandbox="allow-same-origin allow-popups…">`
  with **no allow-scripts** and a CSP meta that blocks all remote loads until
  the user allows them (tracking pixels). Meta refresh and `<base>` are
  stripped. allow-same-origin is only so the parent can measure/zoom the doc.
- Previews: BODYSTRUCTURE picks the first text/plain (else text/html) part,
  then one partial `BODY.PEEK[part]<0.n>` per distinct path. Quoted lines are
  dropped from previews.
- Undo send = a local outbox (`post.outbox`) with a delay (default 10s), so a
  closed tab still sends on next open.
- Drafts are real IMAP drafts (APPEND `\Draft`, old version expunged) so they
  sync with Mail on iPhone/Mac; sending a draft deletes it.

## Not yet
Push (needs a persistent IDLE connection, i.e. a Durable Object), threading
(conversation view), rich-text compose, multiple accounts, Mail Drop (>20 MB).
