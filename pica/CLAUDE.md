# PICA — a screenwriting instrument

A screenplay editor whose screen **is** the printed page. Imports a Final Draft PDF
(text-layer) and reproduces it **identically** — then makes it fully editable with the
complete Final Draft typing grammar. Live at `https://labern.github.io/Clean/pica/`.

## The play
`index.html` renders every wrapped line as an absolutely-positioned div at its true
pt coordinates on true-size pages — screen, print, and source PDF are one layout.
The pure engine (`/*PICA-ENGINE-START*/ … /*PICA-ENGINE-END*/` inside index.html)
does everything spatial: PDF line assembly, element classification (by x-column +
content), self-calibrating wrap widths (hard-break fallback per element), and a
Final Draft-faithful paginator — sentence-boundary splits, (MORE)/(CONT'D)
regeneration, slugline retraction, per-element `spaceBefore` overrides captured at
import. The UI treats contenteditable as a caret only: every `beforeinput` is
intercepted and applied to the model, never the DOM.

## THE CONTRACT — never break it
`node tests/run.mjs` must print **100.00%** (5,907/5,907 lines of Tenet identical
across 148 pages) before any engine change ships. Fixtures are pre-extracted in
`tests/fixtures/` (gitignored — copyrighted source); if absent, run.mjs re-downloads
and re-extracts (needs `npm i pdfjs-dist` inside tests/).

## Rules
- **Single self-contained index.html.** No build step, no framework. Only external
  refs: Google Fonts (Courier Prime) and pdfjs-dist from jsDelivr, lazy-loaded only
  when importing a PDF.
- **Storage is additive-only, never wiped** (pica.index / pica.doc.* / pica.snap.* /
  pica.ui in localStorage). Snapshots ring-buffer 5 deep. Sessions must survive every
  update — hydrate old docs as-is; evolve by optional fields only.
- **Engine changes**: edit inside the markers, run tests, keep 100%. The tests
  extract the engine from index.html itself — there is no second copy.
- Grammar map lives in the app (`?` overlay). Tab cycles → menu when options run
  out; Enter on empty → menu; ⌘1–8 direct; int./ext. auto-detects; SmartType feeds
  from the script itself.

## Deploy (gh-pages worktree ritual)
```bash
cd ~/Desktop/Clean
git worktree add /tmp/ghp gh-pages
mkdir -p /tmp/ghp/pica && cp pica/index.html /tmp/ghp/pica/
cd /tmp/ghp && git add -A && git commit -m "Deploy pica to Pages at /Clean/pica/" && git push
cd - && git worktree remove /tmp/ghp
```

## Future (parked by Labern)
- **Native ⌘-Tab macOS app**: wrap index.html as-is in a WKWebView shell (see memory
  `pica-native-wrapper-later`; hotkey-agent blueprint style + auto Developer-ID signing).
- FDX import (he has 6 .fdx files in ~/Desktop/Core/Screenplays), scene reordering,
  draft diffing, dual dialogue.

## Working style
Use sub-agents freely here: fan-out searches, PDF corpus analysis, cross-file
investigations — delegate the noisy work, keep conclusions in the main thread.
