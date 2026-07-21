# ENHANCE

Local web app that masters video to 4K (and beyond) and makes photos look
higher quality. One PARADOX-styled page, two modes: VIDEO · IMAGE.
Everything runs on this Mac — nothing leaves it.

## Architecture

- `server.js` — zero-dependency Node server on **localhost:2160** (the vertical
  resolution of 4K). Wraps native `ffmpeg`/`ffprobe` (Homebrew). Streams uploads
  raw (`X-Filename` header, no multipart, no size cap), tracks jobs in memory,
  pushes ffmpeg progress over SSE, serves results Range-aware for inline preview.
- `public/index.html` — the whole UI in one file. PARADOX terminal aesthetic
  (see `~/Desktop/★★★★★/STYLE.md`), all colours as CSS tokens on `:root`.
- `work/` — gitignored scratch: `uploads/` and `output/`.

## Pipelines

**Video** (`/enhance`): optional denoise → frame-rate change *at source
resolution* (motion-compensated `minterpolate` for smooth, `fps` for fast) →
lanczos upscale (long edge → 1080/1440/2160/4320) → subtle `unsharp` →
HEVC. `turbo` = `hevc_videotoolbox` (Apple media engine), `max` = `libx265`
crf 16. Audio copied when mp4-safe, else AAC 256k. `-movflags +faststart`.

**Image** (`/enhance-image`, synchronous): HEIC decoded via `sips` (ffmpeg
can't read HEIC) → `hqdn3d` denoise → lanczos upscale 1×/2×/4× → a "look":
`natural` (CAS + slight vibrance), `vivid` (stronger colour/contrast),
`crisp` (detail only). Output JPEG q=1. Hold the preview to see the original
(`/file?id&orig=1`).

## Run

```sh
node server.js     # → http://localhost:2160
```

## Gotchas

- ffmpeg's `-progress` emits `out_time_us`/`out_time_ms` — **both are µs**.
- `minterpolate` runs before scaling on purpose (interpolating at 4K is brutal).
- Portrait clips: the scale expression targets the **long edge**, so portrait
  4K = 2160×3840, as it should be.
- VideoToolbox gets `-allow_sw 1` so odd formats fall back instead of failing.

## Planned

- **Slow-mo mode**: interpolate frames with `minterpolate` then stretch with
  `setpts` — the smooth-motion engine is already the hard part and it's built.

## Working style

- Delegate fan-out searches, independent parallel work, and noisy/large
  investigations to **sub-agents**; keep only findings in the main thread.
- Verify by looking: after changes, run the server, push a real file through,
  `ffprobe` the output — don't claim done on green code alone.
