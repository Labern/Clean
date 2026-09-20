# Manager → Director (EY)

A one-page A4 PDF: ten steps for moving from Manager to Director inside EY,
built from public research on Big 4 grade structures, partner-promotion
practice, and sponsorship effects.

## Files
- `roadmap.html` — source. `__FONTS__` is a placeholder for the inlined
  webfont CSS; the file is not renderable until that substitution happens.
- `fonts-inline.css` — Inter / Instrument Serif / JetBrains Mono latin
  subsets, base64-inlined so the PDF renders identically offline.
- `roadmap.built.html` — generated: `roadmap.html` with fonts substituted in.
- `render.mjs` — headless Chromium → PDF + preview PNG.
- `EY-Manager-to-Director.pdf` — the deliverable. Exactly one A4 page.

## Rebuild
```sh
npm install playwright-core          # gitignored; browser comes from PLAYWRIGHT_BROWSERS_PATH
python3 -c "h=open('roadmap.html').read(); open('roadmap.built.html','w').write(h.replace('__FONTS__', open('fonts-inline.css').read()))"
node render.mjs
```

## Layout constraint
The page must stay at exactly one A4 sheet. `render.mjs` prints the live
measurements — keep `footerBottom` at or under 288.5mm (297mm page less the
8.5mm bottom padding). If it exceeds that, the PDF silently becomes two pages.
