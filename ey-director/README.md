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
- `ey-mark.svg` — the EY mark (beam + wordmark), extracted from the inline
  masthead SVG on ey.com and reduced to the three shapes that form the logo.
  The source SVG carries no fills of its own (its classes are defined in the
  site's stylesheet), so they are set here: `.f` is the yellow beam (#FFE600),
  `.g` the wordmark, white on this dark ground. Inlined into the page, so it
  stays vector in the PDF.
- `render.mjs` — headless Chromium → PDF + preview PNG.
- `EY-Manager-to-Director.pdf` — the deliverable. Exactly one A4 page.

## Rebuild
```sh
npm install playwright-core          # gitignored; browser comes from PLAYWRIGHT_BROWSERS_PATH
python3 -c "h=open('roadmap.html').read(); open('roadmap.built.html','w').write(h.replace('__FONTS__', open('fonts-inline.css').read()))"
node render.mjs
```

## Trademark note
The EY mark is a registered trademark of EYGM Limited and is reproduced here
only to identify the employer this personal plan concerns. The masthead states
on its face that the document is a personal working document and not an EY
publication — it contains independent synthesis of public sources, including
revenue figures drawn from practitioner forums rather than from the firm, and
must never be able to read as official EY guidance. Keep that line on the page.

## Layout constraint
The page must stay at exactly one A4 sheet. `render.mjs` prints the live
measurements — keep `footerBottom` at or under 288.5mm (297mm page less the
8.5mm bottom padding). If it exceeds that, the PDF silently becomes two pages.
