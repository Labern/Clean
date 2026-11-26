# Reader

A local shelf that reflows Labern's own PDFs into a readable page: highlighted
code blocks, a saved reading position per book, and "Open in VS Code" on every
example. No live site: it runs on the Mac only (`node reader.mjs`, port 4177).

## Rules
- **Clean is public. Book content never gets committed.** `library/` (PDFs,
  positions, extraction cache) and `examples/` are gitignored. Keep it that way,
  and never paste book text into code, tests, commits or chat.
- Zero dependencies. `reader.mjs` is plain Node; `index.html` is one file;
  PDF.js and highlight.js are vendored in `vendor/` so it works offline.
- Every colour is a token on `:root`; themes override tokens on `html[data-theme]`.
- The server is local only (binds 127.0.0.1, checks Host and Origin). Keep that
  check on any new endpoint: `/api/open` writes files and launches an editor.

## How it works
- `index.html` extracts text with PDF.js, groups it into lines, then blocks:
  headings (by font size), paragraphs, code (monospace font, or a distinct
  non-body font on indented code-shaped lines, since some books set code in a
  proportional face). The result is cached in `library/.cache/<book>.json`;
  bump `VERSION` in `index.html` when the extraction changes.
- Position = page + block index + fraction through the block, saved to
  `library/state.json` on scroll.

## Sub-agents
Use sub-agents for fan-out searches, independent parallel work, and noisy
investigations (for example comparing extraction output across several PDFs).

## Hit stop
Any animation with a moment of contact gets hit stop; honour Reduce Motion.
