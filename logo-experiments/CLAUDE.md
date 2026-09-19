# Logo Experiments

A single-page presenter for the ★★★★★ × PARADOX marks, live at
`labern.github.io/Clean/logo-experiments/` (to be linked from `/logos`).
Every variation, on any ground, anywhere on the page.

## What it does
- **18 marks**, extracted from Labern's two Keynote decks in `~/Desktop/Logo_Variations/`
  (`LOGO_VARIATIONS.pdf`, `Trademarks.pdf`). Bottom-left: three colour dots
  (black / white / violet `#594992` — the deck's own purple), then `‹ NAME nn/18 ›`.
  Clicking the counter opens the index sheet of every mark.
- **Layouts** (bottom-right): CENTRE · LEFT THIRD · RIGHT THIRD · REPEAT.
  REPEAT is deliberately **one row at full viewport height** that runs off both
  edges — not a grid (he corrected this explicitly).
- **MOVE**: drag the mark anywhere, the corner grip spins and scales it, `− ×n +`
  repeats it along its own rotated axis. The whole state lives in the URL hash
  (`#id/palette/move/x,y,scale,rot,n,spacing`) so any experiment is shareable.
  **On touch, no button is needed** — a finger drag on any mark enters move mode
  by itself, seeded from whatever is already on screen (`seedT()`), so the
  arrangement never jumps. A mouse still uses the button, so a stray click can't
  rearrange the page. The threshold is 6px, so a tap does nothing.
- **SHARE**: redraws the current composition onto a canvas (same positions,
  rotations and ground, ~2600px on the long edge) and hands it to
  `navigator.share()` with the link — on a phone that is the native sheet, so
  WhatsApp is one tap away and Labern gets both the picture and the exact
  arrangement. Desktop without file-share support falls back to downloading the
  PNG and opening `wa.me` with the text. The drawing is primed on `pointerdown`,
  because iOS only hands over the share sheet inside the gesture that asked for
  it — awaiting a canvas first would lose the activation.
- A **footer** under the controls (border above it) explains the whole thing in
  two sentences and links back to `/logos`.
- **Hover a mark** → `SVG` / `PNG` buttons (PNG renders at 4096px on the long
  edge, transparent ground, in the current ink colour).
- Keys: `← →` mark · `↑ ↓` layout · `C` colour · `M` move · `G` index · `F`
  fullscreen · `R` replay · `Esc` out. Swipe works on touch.

## Crispness is the only priority
His words. Nothing is ever rasterised into the page — `logos.js` holds pure
vector outlines, and the marks are `<img src="data:image/svg+xml,…">` so they
stay sharp at any size **and** right-click → Save Image works natively.
Page weight (~510 kB) is explicitly not a concern.

## Adding or changing marks
Everything comes from `tools/build_logos.py`; never hand-edit `logos.js`.

```bash
python3 tools/build_logos.py     # ~14s, walks every page of both decks
```

- It walks **all** pages, so new slides are picked up with no code change.
- The decks print each mark three times (black / white / violet). Pages are
  de-duplicated by a loose silhouette fingerprint — byte-exact hashing fails,
  because each ground thresholds slightly differently.
- Section dividers (a lone corner ★), explanatory slides (>20 characters of
  text) and solid colour plates (ink filling >55% of its own box) are skipped.
- Labels are read from the PDF's text: form from the aspect ratio, script from
  whether the page contains katakana, ™ vs ® from which glyphs are actually
  drawn (the ™ pages also carry a hidden ®, so ™ wins when both appear).
- Pages whose art is a pasted bitmap carry no text, so they are named by hand in
  `OVERRIDES` — add a line there if a new one appears unlabelled.

## How the artwork survives
- Vector pages keep their exact PDF geometry (mutool `-O text=path`). Their glyph
  outlines live in `<defs>` as `<symbol>`s that `<use>` points at, so **defs must
  not be stripped** — only the page's clip rectangles go.
- Bitmap pages are traced by potrace at 6× upsample and dropped back at the
  identical transform. Keynote stores such art as an opaque plate plus a
  greyscale soft mask holding the alpha: the **mask** is the silhouette, so that
  is what gets traced and the plate is discarded.
- The ink bounding box comes from a 216 dpi render. The outermost pixel row can
  be a partly-covered page edge that renders bright, so the render is inset 3px
  before measuring — without that, every box swallows the whole page.

## Gotchas
- `ax` per mark is the optical axis of its *upper cluster* (the stars), not the
  centre of its box. The plumb line and the caption hang off that, so the chrome
  lines up with what the eye reads as the mark's spine.
- Cinema mode fades the chrome to `.16` rather than `0` — at `0` with
  `pointer-events:none` the controls became an invisible dead zone.
- `[hidden]` needs `!important` here: the move controls are a `.grp` flex box.
- `.tile { touch-action:none }` is unconditional, not scoped to move mode — the
  browser would otherwise consume the very drag that is supposed to start it.
- Swiping on a **mark** moves it; swiping on the **ground** changes mark. That
  split is deliberate, and why `pending` is only armed when a tile is hit.
- `fromHash()` must actively *leave* move mode when the link has no arrangement,
  or a plain link opened in a live session stays stuck in it.
- Bitmap traces upsample the **continuous** alpha ramp and threshold after, never
  before: thresholding first bakes the source pixel grid's stair-steps into the
  outline, and nothing downstream can remove them. It also traces smaller.
