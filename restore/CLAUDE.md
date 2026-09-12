# REVIVE — photo restoration

Drop a scanned photograph in, get it back with the blemishes gone, the fading
corrected and the resolution increased. Single self-contained `index.html`,
live at `labern.github.io/Clean/restore/`. No build step, no dependencies, no
network calls, no model weights — the photo never leaves the device.

## Commands
- Open `index.html` directly in a browser. That is the whole app.
- `node tests/run.mjs` — 37 assertions, must stay green on every engine change.

## Shape
- `index.html` — everything. The DSP core is fenced between
  `/*REVIVE-ENGINE-START*/` and `/*REVIVE-ENGINE-END*/`, is pure JS over typed
  arrays with no DOM access, and is pulled out of the HTML by the test suite
  with `new Function` (the same trick `pica/` uses). Browser and tests
  therefore run the identical source and cannot drift.
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
