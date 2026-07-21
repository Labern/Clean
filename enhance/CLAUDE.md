# ENHANCE

Local mastering console: video → 4K (and beyond) + slo-mo, photos → graded &
upscaled, frame capture → highest-quality JPEGs. One page, three tabs:
FILM · PHOTO · FRAMES. Everything runs on this Mac — nothing leaves it.

## Architecture

- `server.js` — zero-dependency Node server on **localhost:2160** (the vertical
  resolution of 4K; `PORT` env overrides — used for test instances). Wraps native
  `ffmpeg`/`ffprobe` (Homebrew) + `sips` (HEIC). Streams uploads raw
  (`X-Filename` header, no multipart, no size cap), pushes ffmpeg progress over
  SSE, serves results Range-aware for inline preview/scrubbing.
- **Persistence**: jobs survive restarts — `work/jobs.json` plus a boot-time
  rescan of `work/uploads` and `work/output` that re-attaches orphaned masters
  (never-lose-progress). Restarting the server never kills a download link.
- `public/index.html` — the whole UI in one file. v4 style (the one he kept):
  **white, soft, round** — white cards, 20–24px radii, soft diffuse shadows,
  pill segmented controls, Avenir Next, sentence case, one soft indigo accent
  (#7a6ff0). Light by default always (he demanded white); dark set behind the
  `◐` toggle. History: v1 PARADOX terminal → v2 MONOGRAPH editorial → v3 VISOR
  viewfinder (rejected as "disgusting" — do not resurrect) → v4. He cares
  intensely about this surface; expect UI redirection and keep the JS wiring
  stable underneath (IDs/classes are the contract; endpoints never changed).

## Pipelines

**Film** (`/enhance`): slo-mo retime or frame-rate change *at source res* →
lanczos upscale (long edge → 1080/1440/2160/4320) → subtle unsharp → HEVC.
- Frame rate: source/24/30/60/120 — `smooth` = motion-compensated
  `minterpolate`, `fast` = resample.
- **Slo-mo** ½×/¼×/⅛×: smooth synthesises playbackFps×slowdown (capped 240)
  then `setpts` stretches; audio slowed pitch-true via `atempo=0.5` chain →
  AAC. Fast slo-mo = stretch only (steppy, instant).
- `turbo` = `hevc_videotoolbox` (Apple media engine), `max` = `libx265` crf 16.
- Progress math uses the *stretched* duration (`job.effDur`); ETA computed
  server-side and sent in SSE events.

**Photo** (`/enhance-image`): optional `normalize` auto-levels → `hqdn3d` →
lanczos 1×/2×/4× → a look → optional grain. JPEG q=1. Looks: natural, vivid,
crisp, **punch** (clarity via gblur+softlight blend), **film** (vintage curves
+ baked grain), **noir** (B&W, local contrast, vignette), **gold** (warm
colortemperature), **dream** (Orton glow: split/gblur/screen-blend).
Hold the preview to see the original (`/file?id&orig=1`).

**Frames** (`/frames/*`): `analyze` finds distinct moments — scene detection
(`select='gt(scene,0.3)'` + `showinfo` at 160px) deduped + evenly-spaced
fallback, thumbnails per moment; the grid is selectable. The scrubber plays
the *original* upload (Range requests) with a CAPTURE button. Download:
1 frame → `/frames/grab` (full-res `-q:v 1 -qmin 1` JPEG, `-ss` before `-i`);
N frames → `/frames/zip`, a **zero-dep store-mode ZIP writer** in server.js
(JPEGs don't recompress).

## Gotchas

- ffmpeg's `-progress` emits `out_time_us`/`out_time_ms` — **both are µs**.
- `unsharp` kernels: `(lx/2+ly/2)*2 ≤ 25` — big-radius "clarity" is impossible
  with unsharp; use gblur + `blend=softlight` instead (that's what punch does).
- `minterpolate` runs before scaling on purpose (interpolating at 4K is brutal).
- Portrait clips: the scale expression targets the **long edge** (portrait 4K
  = 2160×3840).
- VideoToolbox gets `-allow_sw 1` so odd formats fall back instead of failing.
- HEIC decodes via `sips` (ffmpeg can't read it); the decoded PNG is what the
  pipeline and hold-to-compare use.
- Never `pkill -f "node server.js"` broadly — a test instance and the live
  server match the same pattern. And `pkill -f "PORT=2161"` matches NOTHING
  (env vars aren't in the command line). **Kill by port**:
  `kill $(lsof -ti :2161)`. A spawned ffmpeg survives its parent dying and
  finishes the file; boot-rescan then re-attaches it.
- Frame grabs at ~duration decode zero frames — `grabFrame` clamps and walks
  back (t, t−0.5, t−1); the zip route skips failures instead of 500ing.

## Neural engine (the "true enhance" mode, added 2026-07-21)

Engine row on both tabs: **Classic** (lanczos etc.) / **Neural** =
**Real-ESRGAN** (realesrgan-ncnn-vulkan, official prebuilt, vendored at
`vendor/realesrgan/` — gitignored; installed by `./setup-neural.sh`, which the
sandbox can't run itself: download+execute of binaries is user-gated).
- Photo: SR at 4× (or exact factor), then the look chain; **1× neural = SR
  then downscale to original size** — pure detail gain, no upscale.
- Video: extract PNG frames → batch SR 4× to JPEG → re-encode with the
  standard chain (skip unsharp; ESRGAN is already crisp), audio mapped from
  the original. SSE progress has `phase`: extract / neural / encode.
- `/caps` reports `{neural}`; UI greys the Neural chips and shows the install
  hint until it's there. Server 503s neural requests when missing.

Context: he asked "does it actually ENHANCE anything?" — honest answer given:
lanczos adds no information; neural SR is the real fix, hence this mode.

## Working style

- To-do list via harness task tracking from the start of sizeable work.
- Delegate fan-out searches and noisy investigations to sub-agents.
- Verify by looking: run it, push real media through, `ffprobe` the output.
- He live-tests while you work — **check for running renders (pgrep ffmpeg)
  before restarting the server**, and mind that his browser holds page state.
