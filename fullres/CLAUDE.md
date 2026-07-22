# FullRes — CLAUDE.md

## What this is
Send photos & videos over WhatsApp at **original quality** — zero compression.
One self-contained `index.html` (no build, no deps, no backend), live at
`https://labern.github.io/Clean/fullres/`.

**The play:** WhatsApp recompresses everything sent as a photo/video (even "HD"),
but never touches files sent as *documents* (up to 2 GB). This page re-wraps the
picked file (`application/octet-stream`) before `navigator.share`, so WhatsApp's
share extension treats it as a document and the recipient gets the exact original
bytes. Nothing ever uploads anywhere — the file goes straight from the page into
WhatsApp, E2E encrypted.

## The one knob
`WRAP_STRATEGY` at the top of the inline `<script>`:
- `'octet'` — keep filename, MIME `application/octet-stream` (current setting)
- `'octet+ext'` — also append `.wa` to the filename (fallback if octet alone gets sniffed as media)
- `'none'` — pass through untouched (baseline; WhatsApp will compress)

Test any strategy against the LIVE url without redeploying: `?wrap=none|octet|octet+ext`
(a violet ribbon shows when the override is active).

Related levers, commented in the code:
- The `accept` attribute lists `image/heic`/`image/heif` explicitly so iOS hands
  over raw HEIC instead of transcoding to JPEG. If transcoding is ever observed,
  the fallback is removing `accept` entirely.
- No `title`/`text` in the share payload on purpose — extra text can push
  WhatsApp into its media/caption flow. `buildSharePayload()` is the v2 hook
  for an optional caption.
- Never read the picked file's bytes (no `arrayBuffer`/`FileReader`) — the
  `new File([f],…)` wrap is lazy (no copy), which is what makes 2 GB videos fine.

## Device verification matrix (Phase 2 — fill this in)
For each cell: device × file × `?wrap=` → record (a) picked-state readout shows
original type/size, (b) which WhatsApp flow opens (contact picker = document ✓,
caption/media screen = strategy failed ✗), (c) bubble type on receipt,
(d) byte-identical: AirDrop original + received to the Mac, `shasum -a 256` both.

| Device | File | wrap=none | wrap=octet | wrap=octet+ext |
|---|---|---|---|---|
| iPhone Safari | HEIC photo | | | |
| iPhone Safari | JPG | | | |
| iPhone Safari | MOV (HEVC) | | | |
| iPhone Safari | MP4 | | | |
| Android Chrome | (same four) | | | |

Exit criterion: least-invasive strategy giving document bubble + identical hash
for all four types → hard-code into `WRAP_STRATEGY`, note results here, redeploy.

## Deploy
Pages serves from the hand-curated `gh-pages` branch (no CI). From `master`:
```bash
git worktree add /tmp/ghp gh-pages
cp fullres/index.html /tmp/ghp/fullres/   # mkdir -p first time
cd /tmp/ghp && git add -A && git commit -m "Deploy FullRes to Pages at /Clean/fullres/" && git push
cd - && git worktree remove /tmp/ghp
```
Commit source (this folder incl. this file) to `master`; only `index.html` goes to `gh-pages`.

## Testing
`tests/` (if added later): Node `.mjs` run directly, per house convention. The QR
encoder (inline Nayuki qrcodegen port, byte mode, ECC M, v1–6) was verified by
decoding its SVG output with jsQR — re-run that check after any edit to `qrToSvg`.

## v2 hooks (parked, designed-for)
- Optional caption → `buildSharePayload()` (note: iOS drops `text` when `files` present; likely lands as "copy caption, paste in WhatsApp").
- Client-side enhance → a `processing` state between `picked` and `sharing`.
- Desktop→phone handoff via storage → mounts on the unsupported/QR screen.
- Multi-file → flip `multiple` on the input; share already takes an array.

## Working style
- Keep it ONE self-contained file; all colours via `:root` tokens (`.theme-light` overrides).
- Delegate fan-out work to sub-agents: broad searches, multi-file investigations,
  independent parallel tasks (e.g. researching WhatsApp behaviour changes while
  building UI). Keep the main thread for decisions and edits.
