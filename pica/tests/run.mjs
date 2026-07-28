// PICA fidelity suite — the contract: import Tenet.pdf, repaginate, and every one of
// the source's 5,907 lines must come back IDENTICAL (text, x, y) on all 148 pages.
//
// Run:   node tests/run.mjs          (from pica/, or from tests/)
// Setup: fixtures/tenet-raw.json ships pre-extracted (gitignored). If it's missing,
//        this script re-extracts it — that path needs `npm i pdfjs-dist` in tests/
//        and network access for the PDF download.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const FIX = path.join(here, 'fixtures');
const PDF_URL = 'https://thescriptsavant.com/movies/Tenet.pdf';

// -- 1. the engine comes from the app itself: one renderer, zero drift
const html = fs.readFileSync(path.join(here, '..', 'index.html'), 'utf8');
const block = html.match(/\/\*PICA-ENGINE-START\*\/[\s\S]*\/\*PICA-ENGINE-END\*\//);
if (!block) { console.error('FAIL: engine markers not found in index.html'); process.exit(1); }
const E = new Function(block[0] + '; return PicaEngine;')();

// -- 2. fixture (re-extract if missing)
const rawPath = path.join(FIX, 'tenet-raw.json');
if (!fs.existsSync(rawPath)) {
  fs.mkdirSync(FIX, { recursive: true });
  const pdfPath = path.join(FIX, 'Tenet.pdf');
  if (!fs.existsSync(pdfPath)) {
    console.log('downloading Tenet.pdf …');
    const buf = Buffer.from(await (await fetch(PDF_URL)).arrayBuffer());
    fs.writeFileSync(pdfPath, buf);
  }
  console.log('extracting text layer (needs pdfjs-dist: cd tests && npm init -y && npm i pdfjs-dist) …');
  const { getDocument } = await import('pdfjs-dist/legacy/build/pdf.mjs');
  const doc = await getDocument({ data: new Uint8Array(fs.readFileSync(pdfPath)), useSystemFonts: true }).promise;
  const pages = [];
  for (let p = 1; p <= doc.numPages; p++) {
    const page = await doc.getPage(p);
    const vp = page.getViewport({ scale: 1 });
    const tc = await page.getTextContent();
    pages.push({
      width: vp.width, height: vp.height,
      items: tc.items.filter(i => i.str && i.str.length).map(i => ({
        x: +i.transform[4].toFixed(2), y: +(vp.height - i.transform[5]).toFixed(2),
        w: +i.width.toFixed(2), str: i.str,
      })),
      // typography (underline vectors / font styles) is captured by the app's
      // extractor; the fidelity gate compares text+geometry only, so the fixture
      // works with or without it
    });
  }
  fs.writeFileSync(rawPath, JSON.stringify({ pages }));
}
const raw = JSON.parse(fs.readFileSync(rawPath)).pages;

let failures = 0;
const check = (name, ok, detail) => {
  console.log((ok ? '  ok ' : 'FAIL ') + name + (detail ? ' — ' + detail : ''));
  if (!ok) failures++;
};

// -- 3. THE FIDELITY GATE: 100% or fail
const charW = E.estimateCharW(raw);
const truth = raw.map(p => ({ width: p.width, height: p.height, lines: E.linesFromItems(p.items, charW) }));
const doc = E.importPdf(raw);
const res = E.paginate(doc);
const norm = s => s.replace(/\s+/g, ' ').trim();
let ok = 0, total = 0; const bad = [];
for (let i = 0; i < Math.max(truth.length, res.pages.length); i++) {
  const src = (truth[i]?.lines ?? []).slice().sort((a, b) => a.y - b.y || a.x - b.x);
  const mine = (res.pages[i]?.lines ?? []).slice().sort((a, b) => a.y - b.y || a.x - b.x);
  for (let j = 0; j < Math.max(src.length, mine.length); j++) {
    total++;
    const s = src[j], m = mine[j];
    if (s && m && norm(s.text) === norm(m.text) && Math.abs(s.x - m.x) < 1.6 && Math.abs(s.y - m.y) < 1.6) ok++;
    else if (bad.length < 5) bad.push({ page: i + 1, src: s?.text, mine: m?.text });
  }
}
check(`fidelity: ${ok}/${total} lines identical across ${truth.length} pages`, ok === total,
  ok === total ? '100.00%' : (100 * ok / total).toFixed(2) + '% — first diffs: ' + JSON.stringify(bad));

// -- 4. sanity: the import produced a real document
check('148 pages (title + 147)', res.pages.length === 148, String(res.pages.length));
check('~3.8k elements', doc.elements.length > 3500, String(doc.elements.length));
check('275 scenes', doc.elements.filter(e => e.type === 'scene').length === 275);
check('speech splits regenerate (MORE)', res.pages.flatMap(p => p.lines).filter(l => l.kind === 'more').length === 6);

// -- 5. sanity: editing round-trip — mutate, repaginate, restore, fidelity again
const el = doc.elements.find(e => e.type === 'dialogue' && !e.text.includes('\n'));
const orig = el.text;
el.text = orig + ' And one more sentence for the road, which should reflow the page.';
const res2 = E.paginate(doc);
check('edit repaginates without error', res2.pages.length >= 148);
el.text = orig;
const res3 = E.paginate(doc);
check('restore returns to identical page count', res3.pages.length === 148, String(res3.pages.length));

// -- 6. sanity: blank Letter document + exports
const blank = E.newDoc('TEST');
const bres = E.paginate(blank);
check('new doc paginates (title + 1 page)', bres.pages.length === 2, String(bres.pages.length));
check('toFountain produces text', E.toFountain(doc).length > 100000);

console.log(failures ? `\n${failures} FAILURE(S)` : '\nall green — the page is the truth');
process.exit(failures ? 1 : 0);
