# Once — CLAUDE.md

Never type your name, email or address into a form again — on every site,
including ones never visited. Live at `https://labern.github.io/Clean/once/`.

## Shape
- `extension/engine.js` — THE engine. Classifies any field by meaning and fills it.
  Shared verbatim by the extension and the bookmarklet. Pure DOM, no deps.
- `extension/` — MV3 extension (Chrome/Edge/Brave/Arc, Firefox ≥121; Safari via
  `xcrun safari-web-extension-converter`). `content.js` runs on `<all_urls>`, all frames.
- `tools/bookmarklet.js` — bookmarklet entry; `tools/build.mjs` wraps the engine
  into it, minifies (terser) → `bookmarklet.min.js`, and zips `once-extension.zip`.
- `index.html` — setup + install page. Builds the bookmarklet client-side with the
  profile baked in. Profile lives in localStorage only.

## Privacy rule (hard)
The owner's real name/address/emails are NEVER committed. The repo and Pages are
public. Setup is a private link `…/once/#p=<base64url JSON>` (fragment never hits a
server; the page saves it to localStorage, wipes the hash, and hands it to the
extension via postMessage — content.js accepts that only on labern.github.io/Clean/once/).
Tests use a fake profile (Ada Lovelace).

## Engine rules
Signal order: autocomplete attr → type=email → name/id → label/aria/placeholder/title.
`SKIP` runs first on each tier (card, phone, company, search, friend/recipient…).
Resolution in `plan()`: username → email unless the form also has an email field
(then it's a signup handle: left alone); line1 ↔ street depends on a houseNo field.
Fill only empty, visible fields (honeypots: off-canvas, display:none, opacity 0).
Values via the prototype setter + input/change/blur so React/Vue register them.
`data-once-off` on any ancestor opts fields out (the setup form uses it).
Email swap/current only touch fields `classify()` calls email — a bug where a
saved-details form steered the bookmarklet to the 2nd email is regression-tested.

## Extension behaviour
On sight: a group (form, else document) with ≥2 strong keys, or password + email.
Otherwise: on focus. Never refills a field the user edited/cleared (`taken`).
Per-site email: chip `⇄` / popup / typing one by hand → `sites[host]`. Off per site.

## Commands
- Build: `node once/tools/build.mjs` (after any engine/bookmarklet change — commit outputs)
- Tests: `node once/tests/run.mjs` — Playwright, engine + packed extension end to end. Must stay green.
- Deploy: `once/tools/deploy.sh "message"` (gh-pages branch).
