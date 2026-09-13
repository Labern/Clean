# REVIVE — photo restoration

Drop a scanned photograph in, get it back with the blemishes gone, the fading
corrected and the resolution increased. Single self-contained `index.html`,
live at `labern.github.io/Clean/restore/`. No build step, no dependencies, no
network calls, no model weights — the photo never leaves the device.

## Commands
- Open `index.html` directly in a browser. That is the whole app.
- `node tests/run.mjs` — 37 assertions, must stay green on every engine change.

## Shape
- `index.html` — the page and the UI only.
- `engine.js` — the whole compute core, still fenced in `/*REVIVE-ENGINE-*/`,
  `/*REVIVE-COLOUR-*/` and `/*REVIVE-FACE-*/` markers, pure JS over typed
  arrays with no DOM access. Loaded twice: by the page (for the pure helpers)
  and by `worker.js` via `importScripts`. The suite loads it directly, so
  browser and tests cannot drift.
- `worker.js` — every expensive stage. **This is not an optimisation.**
  Restoring a 12-megapixel scan is tens of seconds of dense array work; run on
  the main thread the tab stops repainting entirely — no progress bar, no
  spinner — which is indistinguishable from an app that does nothing, and is
  exactly how it was reported. With the worker, main-thread lag measured
  1–15ms throughout a 39-second restore. There is a main-thread fallback for
  `file://`, where a page is not permitted to start a worker at all.
- `tests/run.mjs`, `tests/fixtures.mjs` — the fixtures are *generated*, not
  checked in: a procedural "photograph", then known degradations (box
  downscale, dust, scratches, fade with a colour cast, noise). Because the
  ground truth is known exactly, every claim the UI makes is measurable.

## The interface
Deliberately one path: drop → it decides everything → original on top,
restored below → download. `autoSettings()` reads the scan and picks every
parameter, so the default flow asks the user for nothing. The sliders live
in a collapsed `<details>` for when the automatic reading is wrong.
"Show what it repaired" paints the damage mask over the original in pink —
the honest way to let someone check the tool did not eat their photograph.

## Pipeline, and why in this order
`decode → linear light → fade/cast → detect damage → inpaint → denoise →
upscale → back-project → shock sharpen → local contrast → grain → sRGB`

- **Linear light throughout.** Blurring, resizing and averaging gamma-encoded
  values darkens edges. Removing a raised black point is only physically
  correct in linear, because veiling flare is additive there.
- **Detail work happens on luminance only.** Chroma is smoothed hard and
  carried cheaply. That is how human vision and every image codec are built,
  and it is what keeps a 4× upscale inside a browser's memory budget.
- **Denoise before upscaling, sharpen after.** Sharpening first would amplify
  grain into the enlargement.

## Calibrated constants — do not "tidy" these
Each of these numbers was measured, and several encode a bug that cost real
debugging. The suite has a regression test for every one.

- **`gauss` must deliver the sigma it is asked for.** It originally used three
  box passes, which returned σ≈1.41 when asked for 0.8. Back-projection
  assumes a blur; feed it one wider than reality and the iteration
  over-sharpens every pass and diverges monotonically. It is now a true
  separable kernel below σ=4.
- **Back-projection uses the true adjoint** (`upBox` then the same blur), not
  bilinear. With the exact model it converges in one step and stays; with
  bilinear it degrades at high σ instead of degrading gracefully. The assumed
  blur is `max(0.15, softness - 0.1)`: a plain box-downscale measures ~0.5
  softness and wants σ 0.4, a genuinely soft scan measures ~1.0 and wants 0.9.
  Overshooting rings.
- **Tone endpoints are tail percentiles counted from each end.** The high
  endpoint search once accumulated to `total * (1 - p)`, which lands near the
  bottom, so `hi <= lo` fired every time and silently fell back to 0–255 —
  meaning fade recovery quietly did nothing.
- **Dust does not vote on the tone curve.** A few hundred specks pin ~2.5% of
  pixels at pure black and white, which convinces a percentile that a faded
  print already uses its full range. `analyze` despeckles (open-then-close)
  and only trusts pixels that survive unchanged.
- **Channel gains are anchored to luminance** (`LIM = 1.22`). Black points are
  per-channel and removed in full — that is the cast. Gains are not: stretching
  each channel to its own full range assumes the original used all of it, and
  when blue is the most compressed channel an unbounded gain manufactures a
  lurid blue sky out of a grey one.
- **Auto fade tops out at 0.75, not 1.0**, for the same reason.
- **The damage mask is `max(dilated, blurred)`, never the blur alone.**
  Blurring a small blob lowers its peak, so a dust speck came out with a mask
  of ~0.5 and got exactly half repaired.
- **The area cap is a histogram quantile, not a threshold search.** Walking the
  threshold up a fixed number of geometric steps fails when the noise estimate
  is absurdly low — it ran out of steps having flagged 69% of the frame.
  Reading the response at the `1 - maxFrac` quantile satisfies the cap by
  construction, in one pass.
- **Inpainting uses two different masks.** Confidence (hard, binary) decides
  what the fill may *read*; blend (soft) decides where it is *written*. Using
  `1 - mask` for both lets a half-flagged scratch shoulder contribute a third
  of its own broken value, the pyramid carries it to the coarse levels, and
  the scratch returns as a bright smear several times its width.
- **Noise is read off the flattest quarter of the image**, not the median — a
  photograph of a brick wall is detailed, not noisy.
- **Softness uses squared gradient energy.** Summed `|∇|` is conserved across a
  blurred step edge and reports a mush and a knife-edge alike.

## Known limits, stated plainly
- **No colourisation.** Inventing colour for a black-and-white photograph needs
  a learned model. The tone control offers neutralise / keep sepia / mono, and
  nothing more, because anything else would be fabrication.
- **Exemplar fill abstains on rigid repeating structure.** PatchMatch copies
  real texture into holes, which is right for fabric, foliage, skin and grain.
  Over a window grid or brickwork it can be confidently wrong, and a displaced
  window is far uglier than a soft patch — so each match is scored against
  local variance and a poor one stands down, leaving the smooth fill. The
  visible cost is faint soft traces where a scratch crossed a rigid pattern.
- **Large blotches, missing corners and torn-off areas** are out of scope. The
  detector looks for small blobs and thin lines, which is what dust, specks,
  scratches and creases are.
- **Stage-level progress only.** The generator yields between stages so the UI
  can paint; a single stage on a very large scan still blocks. A worker would
  fix it at the cost of the single-file, `file://`-openable property.

## Metrics note
Stages that must be colour-faithful (fade, repair) are judged on RGB PSNR.
The super-resolution stages are judged on the **luminance plane** — not a
dodge. The pipeline sharpens luma while carrying chroma smoothly; measured in
RGB that correct behaviour scores badly, because the resampling errors of Y
and of (B−Y) no longer cancel once Y is sharpened. Y is what the stage claims
to improve, so Y is what it is graded on. Texture transfer is not graded by
PSNR at all — a correctly copied texture offset by one pixel scores terribly
and looks right — which is why the exemplar stage was tuned by eye against
browser screenshots.

## Colourisation
Optional, opt-in, and the only part of the app that is not classical DSP.

- **Model:** DDColor (Du et al., ICCV 2023), the `tiny` ConvNeXt-T variant,
  Apache-2.0. Exported with the repo's own `scripts/export_onnx.py` at
  512×512, then dynamically quantised to int8 — 223 MB to 78 MB, visually
  indistinguishable on test images. Ships as `restore/colorize.onnx`.
  - It replaced Zhang/Isola/Efros SIGGRAPH-2017 (BSD-2), which worked but
    rendered everything in a muted wash. DDColor finds warm wood, skin and
    fabric where the older model saw only sepia. The older 43 MB blob is
    still in git history; nothing references it.
  - **Quantising needs `quant_pre_process` first.** The final conv uses
    spectral norm, so its weight is *computed* in the graph rather than stored,
    and `quantize_dynamic` fails with "Expected div_15 to be an initializer".
    Constant folding turns it into one.
  - **Its input is not the L plane.** DDColor expects the image rendered as
    neutral grey in sRGB — what `Lab(L,0,0)` looks like — as three identical
    channels in 0..1. Feeding it raw L does not crash, it just silently
    returns subtly wrong colour, so there is a test for it. Output a/b are
    already in Lab units.
- **Runtime:** onnxruntime-web 1.19.2, MIT, **vendored in `restore/ort/`** and
  loaded *on demand* — the page costs nothing until the button is pressed. It
  is deliberately not on a CDN: a CDN is one more thing that can be blocked,
  go down, or change what it serves under a version number, and the promise
  this page makes is that the link works.
  - `wasmPaths` must be an ABSOLUTE url (`new URL('ort/', location.href).href`).
    The runtime dynamically imports its own `.mjs`, and a bare relative path
    like `ort/` is not a valid module specifier — it fails at run time with
    "no available backend found", not at load.
  - `numThreads = 1` is
  mandatory: threads need cross-origin isolation (COOP/COEP) and GitHub Pages
  cannot send those headers. SIMD works without isolation and carries it.
  ~18s for a 4.4MP photograph.
- **Why it composes cleanly:** the network predicts only the two CHROMA
  channels, at 256×256, from lightness alone. That is exactly how the rest of
  the pipeline is built — detail on luminance, chroma carried smoothly — so
  the predicted a/b are upsampled and married to the full-resolution restored
  L. The model never sees or writes luminance, so **colourising cannot smear a
  face**, and there is a test asserting lightness is preserved to within 1 L*.
- **Colour strength** scales a/b in Lab, which changes chroma without touching
  lightness, so the restoration underneath is invariant to it.
- **Honesty:** the output is a plausible reading, not a record. Colour in a
  monochrome negative does not exist to be recovered, and the UI says so.

### Testing it
`tests/run.mjs` extracts the `/*REVIVE-COLOUR-*/` block the same way it
extracts the engine and checks the Lab round trip, neutrality at zero chroma,
and lightness invariance. It does **not** run the network — that needs a
browser. The browser path was verified with Playwright against the real
page with no network interception of any kind — model fetch, session creation,
inference and recombination all ran as shipped.

## Face restoration
Optional, opt-in, and the only thing here that can put a face back IN FOCUS.
Nothing classical can: the detail was never in the negative to recover, so it
has to come from a learned prior.

- **Models:** GFPGAN v1.4 (Wang et al., CVPR 2021, Apache-2.0) — a StyleGAN2
  face prior, which is why it works on prints that are genuinely degraded
  rather than merely soft — plus YuNet (OpenCV Zoo, Apache-2.0, 233KB) for
  detection and landmarks. GFPGAN is int8-quantised (340MB → 158MB) and
  **split across `models/face.onnx.partN`**, because 158MB exceeds GitHub's
  100MB per-file limit; the parts are concatenated back in memory.
- **Pipeline:** detect → align → restore → paste.
  - GFPGAN accepts nothing but a 512×512 face aligned to the FFHQ five-point
    template, so the real work is geometry. The similarity transform is
    closed-form (the 2-D least-squares case has an exact solution, no SVD) and
    excludes reflection by construction — a reflected solve would paste every
    face back mirrored. There are tests for the residual, the round trip and
    the determinant.
  - Paste-back is blended through a feathered oval, never stamped: a hard edge
    at the jawline looks worse than a soft face. Blend strength also scales
    with detection confidence, so a doubtful detection barely moves anything.
  - **Luminance only on near-neutral scans.** The model was trained on colour
    faces and will shift skin tone; on a black-and-white print any colour it
    invents is simply wrong.
- **Detection coverage.** One 640 pass over a 2500px group photo shrinks a head
  to ~35px and finds two faces out of five, so the image is tiled at close to
  native scale with a third overlap and merged with NMS. YuNet is still a
  frontal-ish detector: **profiles and turned-away heads are not found**, which
  is a model limit, not a bug — on the test classroom photograph most of the
  heads are in profile and 2 of 5 is the honest answer.
- **Cost:** ~34s for two faces including the model download, single-threaded.
- **Honesty:** the detail is reconstructed from a prior. It is a likeness, not
  a record, and the UI says so.

## Batch
Drop in one photograph or a hundred. More than one switches to a queue view:
each file is processed **one at a time**, with the live stage name, which file
is in hand, and a per-row download link as each finishes.

- **One at a time is deliberate.** A hundred 12-megapixel photographs cannot be
  held decoded in memory at once, so each result is encoded to a PNG blob the
  moment it is done and its pixel buffers are dropped — blobs are backed by
  disk, typed arrays are not. Holding decoded images is what makes a batch tool
  die around image forty. Processing in parallel would also make the progress
  meaningless and lock up the tab.
- **ZIP is written by hand**, stored (uncompressed), because PNG is already
  deflated and re-compressing would burn minutes to save nothing. It is built
  from Blob parts reading one file at a time, so the whole batch never sits in
  memory together. Verified with Python's `zipfile` at 6 and 40 entries.
- Face restoration and colourisation are opt-in checkboxes on the drop screen
  and apply to the whole batch; the models load once and are reused across
  every photograph. They also apply to a single photograph if ticked.
- Measured: 40 files in 83s (restore only); 6 larger files in 59s.

### Gotcha
`[hidden]` needs `!important` in this stylesheet. `.btn` sets `display:flex`,
which has identical specificity and comes later, so hiding a button silently
did nothing — the batch "Stop" button stayed visible after completion.


## Two bugs that both presented as "it does nothing"
Worth reading before touching the app shell, because neither threw an error
and neither showed up in any image-quality metric.

1. **A click handler bound to a function whose first parameter is a flag.**
   `btn.onclick = colourise` hands the click's MouseEvent to `colourise(silent)`.
   An event is truthy, so the model downloaded, ran to completion, and then
   suppressed every visible sign of itself: no button text, no note, no
   repainted canvas. The work happened perfectly and the page looked broken.
   It arrived the moment `silent` was added for batch mode. Handlers are now
   always wrapped in arrows, the flags only accept a literal `true`, and
   `tests/run.mjs` greps the page for bare bindings to flag-taking functions.

2. **The frozen tab.** Everything ran on the main thread, so nothing repainted
   during a long restore. Fixed by the worker above; the working screen also
   shows a running elapsed clock, which doubles as proof of life.
