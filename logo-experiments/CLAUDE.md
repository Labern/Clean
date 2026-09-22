# Logo Experiments

A single-page presenter for the ★★★★★ × PARADOX marks, live at
`labern.github.io/Clean/logo-experiments/` (to be linked from `/logos`).
Every variation, on any ground, anywhere on the page.

## What it does
There are no modes. One mark (or several copies of it) sits on the page and is
**always draggable** — mouse or finger, at any time. The circle at its corner
spins and scales it. Nothing else is chrome on the artwork: no frame, no
selection box.

The controls are one quiet bar and nothing else — **no explanatory text**; the
thing has to be obvious. Left to right: **colour** (three dots — black, white,
the deck's violet `#594992`), **variation** (`‹ ›` plus **ALL 18**, which says
what it opens), **number** (`− ×n +`, copies spread along the mark's own rotated
axis), **RESET**, **SAVE**, **SHARE**, **HIDE**, and a link to `/logos`.

- **SAVE** writes what is on screen right now to a PNG (~2600px on the long
  edge): the ground and the marks exactly as arranged, none of the chrome.
- **ALL 18** fills the screen with every variation, each presented on its own
  with its name, and a CLOSE in the corner. It replaces the view rather than
  crowding it.
- While the corner circle is held, a hairline box shows the mark's bounds to
  size against. It appears on grab and goes on release, and never shows for a
  plain drag.
- **The circle clears itself away** once you have sized something, so it is not
  sitting on the artwork. It comes back on hover, while dragging, and on a
  **double click** on the mark (Labern's call: "double click to bring back
  circle is fine").
- **Zoom** runs past the edge of the window on purpose. Sizing from the circle
  alone is a trap — scale the mark beyond the viewport and the circle goes with
  it — so zoom also lives on the **wheel** and on a **two-finger pinch** (both
  scale about the pointer, so what you aim at stays put), and on `− 140% +` in
  the bar, which cannot be scrolled off screen. Clicking the percentage is the
  way home: back to 100% and back to the middle, from however far out.

Everything holds its place: changing colour or variation keeps the position,
scale, rotation and count; the controls have fixed-width fields so stepping
through marks or counts never shifts them; and the dock's height is cached, so
HIDE UI doesn't resize or move the artwork.

- **HIDE** strips the screen for a screenshot; a tap that isn't a drag (or
  `H`/`Esc`) brings it back.
- **Hover a mark** → `SVG` / `PNG` (4096px on the long edge, transparent ground).
- **SHARE** redraws the composition onto a canvas (same positions, rotations and
  ground, ~2600px) and hands it to `navigator.share()` with the link — on a phone
  that's the native sheet, so WhatsApp is one tap and Labern gets the picture and
  the exact arrangement. Desktop without file-share falls back to downloading the
  PNG and opening `wa.me`. The drawing is primed on `pointerdown`, because iOS
  only grants the share sheet inside the gesture that asked for it.
- The whole state is the URL hash (`#id/palette/x,y,scale,rot,n`), so any
  arrangement reopens exactly as it was.
- Keys: `← →` variation · `↑ ↓` number · `C` colour · `R` reset · `H` hide ·
  `G` index · `F` fullscreen · `Esc` out.

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
- `[hidden]` needs `!important` here: the bar's groups are flex boxes.
- **No instructions on screen.** Labern's standing verdict: "delete the text that
  explains how it works. It should be obvious." The logo being shown is the
  point; everything else earns its pixels or goes.
- **Toggle the grip and the sizing box with `display`, never a transitioned
  `opacity`.** Both were written that way first and both stuck at their old
  computed value indefinitely after the class changed — with the cascade
  verified correct, the shorthand parsed correctly (`opacity 0.18s
  cubic-bezier(...)`), and `getAnimations()` empty. Snapping is better for
  these anyway; don't spend another hour on it.
- `HIDE` must never be a one-way door. `moved` is reset on a capture-phase
  `pointerdown` on the window, because a click on empty ground never reaches
  the `#field` handler and the flag would otherwise stay `true` from the last
  drag forever — which is exactly how HIDE became unrecoverable once.
- The index grid needs `grid-template-rows: minmax(0,1fr) auto`: a plain `1fr`
  will not shrink below the image's intrinsic size, so every mark overflowed
  its cell and they printed on top of each other.
- The mark's height leaves ~92px of the free area spare so the corner handle,
  which hangs 44px past the artwork, stays clear of the bar.
- **Never auto-hide the controls.** An earlier build faded them to 16% opacity
  when idle; Labern's verdict was "the UI is awful, I can't see it". HIDE UI is
  the only thing that removes them, and only when asked.
- The entrance animation is applied through a `.in` class given out on first
  build and to genuinely new copies only. Replaying it on every colour or
  variation change flickered the thing being worked on.
- Drag listeners for `pointermove`/`pointerup` live on the **window**, not on
  `#field`: mid-drag the pointer leaves the element, and pointer capture can be
  refused. Note that Claude-in-Chrome's `left_click_drag` dispatches *only*
  `pointermove` — no down or up — so it cannot exercise this path; test drags by
  dispatching PointerEvents instead.
- `.tile { touch-action:none }` is unconditional, not scoped to move mode — the
  browser would otherwise consume the very drag that is supposed to start it.
- Swiping on a **mark** moves it; swiping on the **ground** changes mark. That
  split is deliberate, and why `pending` is only armed when a tile is hit.
- `fromHash()` must actively *leave* move mode when the link has no arrangement,
  or a plain link opened in a live session stays stuck in it.
- Bitmap traces upsample the **continuous** alpha ramp and threshold after, never
  before: thresholding first bakes the source pixel grid's stair-steps into the
  outline, and nothing downstream can remove them. It also traces smaller.
