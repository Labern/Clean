# Project Knowledge — ENHANCE
> Durable, non-obvious knowledge, preserved across compaction. Read at session start.
> Append-merged by the `knowledge` skill — add, refine, supersede; never delete.
> Architecture/pipelines/gotchas live in `CLAUDE.md` — this file holds session
> state and knowledge that doesn't belong there.

## What this project is / current state
Local mastering console (video → 4K/slo-mo, photos, frame capture, neural SR)
at `~/Desktop/Clean/.claude/worktrees/enhance/enhance/`, branch
`worktree-enhance`, PR https://github.com/Labern/Clean/pull/3 (draft).
Live server: `node server.js` on **localhost:2160**, serving UI v4.

**As of 2026-07-21 late session:**
- Everything through the neural engine is DONE, tested, live, pushed.
- **Before/after compare mode is CODE-COMPLETE but NOT yet tested or pushed.**
  Server route `/compare` + client button are written; remaining steps:
  `node --check server.js` → boot PORT=2161 → test compare on a classic master
  AND a slo-mo master (retime alignment) → safe-restart live :2160 → update
  CLAUDE.md → commit/push. The last applied edit removed the bogus cancel
  affordance from the compare status line.

## How it works (non-obvious, beyond CLAUDE.md)
- **Compare mode**: original is naively upscaled to the master's resolution
  (that's what a display does — this is the *honest* comparison), hstack'd
  right of the master, capped H≤2160 and total width ≤8100 (VideoToolbox
  limit ~8192). Slo-mo masters get the original side retimed with
  `setpts=ratio*PTS` where ratio = outDur/srcDur (works on resurrected jobs
  with no opts). Labels: **brew ffmpeg has NO drawtext** (no freetype) — the
  browser renders "ORIGINAL"/"ENHANCED" PNGs via canvas and POSTs them as
  data URLs; server overlays them scaled to H/12. Output
  `work/output/<id>-compare.mp4`, served via `/file|/download?id&compare=1`,
  persisted as `job.compare`, orphan-restored at boot (skip pattern
  `compare.mp4` in the output rescan, like `frame-`).
- Neural engine measured ~4–5 fps SR on his GPU (60s@30fps ≈ 6 min neural
  phase). Photo 1× neural = SR 4× then lanczos back to original size.

## Constraints & invariants
- UI is **v4: white/soft/round, Avenir Next, pill controls** — the one he
  kept. v3 VISOR was rejected violently ("DISGUSTING") — never resurrect.
  UI history: PARADOX → MONOGRAPH → VISOR → v4 (all in git).
- JS wiring (element IDs, endpoints) is the stable contract across UI
  rewrites; server never restarted for pure-HTML changes (read per request).
- Port 2160 = live, 2161 = test instance (`PORT=2161 node server.js`).

## Gotchas & fixes (session-level; more in CLAUDE.md)
- `pkill -f "PORT=2161"` matches NOTHING (env not in cmdline) and
  `pkill -f "node server.js"` kills BOTH instances (took the live server down
  mid-user-render once — survived because ffmpeg children outlive the parent
  and boot-rescan re-attaches finished files). **Always `kill $(lsof -ti :PORT)`**
  and `pgrep -f "ffmpeg.*work/uploads"` first — he live-tests constantly and
  may have a render going.
- unsharp kernel budget `(lx/2+ly/2)*2 ≤ 25` → big-radius clarity is done via
  gblur+softlight blend (punch/noir looks).
- Frame grab at ~duration decodes zero frames → clamp + walk back (t, −0.5, −1).
- Setup scripts written by the Write tool have no +x bit; and the sandbox
  classifier blocks download+execute of binaries — user runs `setup-neural.sh`
  himself (via `!` prefix in session; needs full path, shell cwd ≠ project).

## Commands & workflow
```sh
node server.js                                  # live, :2160
PORT=2161 node server.js                        # test instance
kill $(lsof -ti :2161)                          # kill test safely
pgrep -f "ffmpeg.*work/uploads"                 # is he rendering right now?
# test media
ffmpeg -f lavfi -i testsrc2=size=640x360:rate=24:duration=4 \
  -f lavfi -i sine=frequency=440:duration=4 -c:v libx264 -pix_fmt yuv420p \
  -c:a aac -shortest -y test.mov
```
Test flow used throughout: curl upload → curl enhance → poll `/file?id` for
200 → download → `ffprobe -show_entries stream=width,height,avg_frame_rate`.

## Project-specific decisions (& why)
- Comparison rendered at master resolution with naive-upscaled original —
  chosen over side-at-source-res because it's the honest proof (answers his
  "they look identical" challenge on equal footing).
- Neural = Real-ESRGAN ncnn-vulkan official prebuilt, vendored not brewed
  (no formula exists); gitignored; graceful 503 + greyed chips until present.
- Zip is store-mode (JPEGs don't recompress) — hand-rolled, zero deps.
- His five masters from tonight (incl. 5eea7753a6ca-4K120, 184MB) are in
  `work/output/` — treat as user data, never clean.

---
## Changelog
- 2026-07-21 — Initial capture: v1→v4 UI history, neural engine, compare-mode
  state (code-complete/untested), process-management traps, test workflow.
