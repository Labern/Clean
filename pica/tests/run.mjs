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

// -- 7. the Oppenheimer mini-gate: ALWAYS runs when the fixture is present.
// Two real bugs hid in the built-but-unrun suite; the diseases this fixture
// carries (curly-apostrophe CONT'D, dual columns, running heads, typography)
// are checked on every single run from now on.
const oppPath = path.join(FIX, 'opp-raw.json');
if (fs.existsSync(oppPath)) {
  const opp = JSON.parse(fs.readFileSync(oppPath)).pages;
  const od = E.importPdf(opp);
  const ores = E.paginate(od);
  const dbl = /\(CONT['’]D\)\s*\(CONT['’]D\)/;
  check("opp: no doubled (CONT'D) in elements", od.elements.filter(e => dbl.test(e.text)).length === 0);
  check("opp: no doubled (CONT'D) in rendered lines", ores.pages.flatMap(p => p.lines).filter(l => dbl.test(l.text)).length === 0);
  check('opp: no welded dual columns', od.elements.filter(e => e.type !== 'character' && / {6,}/.test(e.text.replace(/\n/g, ' '))).length === 0);
  check('opp: cues classified as cues', od.elements.filter(e => e.type === 'character').length > 1700);
  check('opp: dual groups found', new Set(od.elements.filter(e => e.dual).map(e => e.dual.g)).size >= 40);
  check('opp: underline marks captured', od.elements.reduce((a, e) => a + (e.marks || []).filter(m => m[2] === 'u').length, 0) >= 30);
  check('opp: running head scrubbed', od.elements.filter(e => /gadget.*gadget|shooting script|\d{4}-\d{2}-\d{2}/i.test(e.text)).length === 0);
  check('opp: no overprint-doubled words', od.elements.filter(e => /(\b\w{5,}\b)\1/.test(e.text.replace(/\s+/g, ''))).length === 0);
  check('opp: dual cues typed as cues', od.elements.filter(e => e.dual && e.type === 'character').length >= 80);
  let oppPM = 0;
  for (const p of ores.pages) for (let i = 1; i < p.lines.length; i++)
    if (p.lines[i].kind === 'more' && p.lines[i - 1].kind === 'paren') oppPM++;
  check('opp: no (MORE) dangling after a parenthetical', oppPM === 0);
} else {
  console.log('  (opp-raw.json missing — Oppenheimer mini-gate skipped)');
}

// -- 8. the Collateral mini-gate: revision stars are marginalia, gutters strip
const colPath = path.join(FIX, 'col-raw.json');
if (fs.existsSync(colPath)) {
  const col = JSON.parse(fs.readFileSync(colPath)).pages;
  const cd = E.importPdf(col);
  const cres = E.paginate(cd);
  check('col: no absorbed margin stars', cd.elements.filter(e => /\s{2,}\*+(\s|$)/.test(e.text) || /^\*+$/.test(e.text.trim())).length === 0);
  check('col: star band recorded', Math.abs((cd.layout.revX ?? 0) - 568.8) < 2, 'revX=' + cd.layout.revX);
  check('col: starred lines remembered', cd.elements.filter(e => e.rev).length > 300);
  check('col: stars thread into pagination', cres.pages.flatMap(p => p.lines).filter(l => l.rev).length > 400);
  check("col: no star inside a (CONT'D) cue", cres.pages.flatMap(p => p.lines).filter(l => l.kind === 'contcue' && /\*/.test(l.text)).length === 0);
  check('col: revision headers scrubbed', cd.elements.filter(e => /revs\.|goldenrod|salmon/i.test(e.text)).length === 0);
  check('col: scene-number gutters stripped', cd.elements.filter(e => e.type === 'scene' && /\d[A-Z]?$/.test(e.text.trim()) && !/DAY|NIGHT|LATER|CONTINUOUS|MORNING|EVENING|DUSK|DAWN/.test(e.text)).length <= 1);
  check('col: underlines captured', cd.elements.reduce((a, e) => a + (e.marks || []).filter(m => m[2] === 'u').length, 0) >= 60);
} else {
  console.log('  (col-raw.json missing — Collateral mini-gate skipped)');
}

// -- 9. the Whiplash mini-gate: typography + right-margin-only scene numbers + duals
const whipPath = path.join(FIX, 'whip-raw.json');
if (fs.existsSync(whipPath)) {
  const whip = JSON.parse(fs.readFileSync(whipPath)).pages;
  const wd = E.importPdf(whip);
  const wb = wd.elements.reduce((a, e) => a + (e.marks || []).filter(m => m[2] === 'b').length, 0);
  const wi = wd.elements.reduce((a, e) => a + (e.marks || []).filter(m => m[2] === 'i').length, 0);
  const wu = wd.elements.reduce((a, e) => a + (e.marks || []).filter(m => m[2] === 'u').length, 0);
  check('whip: bold captured', wb >= 150, String(wb));
  check('whip: italic captured', wi >= 80, String(wi));
  check('whip: underline captured', wu >= 180, String(wu));
  check('whip: right-only scene numbers stripped (no CONTINUOUS72A)', wd.elements.filter(e => e.type === 'scene' && /[A-Z0-9]\d+[A-Z]?$/.test(e.text.trim()) && !/\d{4}$/.test(e.text.trim())).length === 0);
  check('whip: dual overlaps found', new Set(wd.elements.filter(e => e.dual).map(e => e.dual.g)).size >= 4);
  check('whip: no welded dual lines', wd.elements.filter(e => e.type !== 'character' && / {6,}/.test(e.text.replace(/\n/g, ' '))).length === 0);
} else {
  console.log('  (whip-raw.json missing — Whiplash mini-gate skipped)');
}

// -- 10. FD-exact typed geometry (Screenplay.fdxt is the reference)
{
  const nd = E.newDoc('GEOM');
  const L = nd.layout;
  check('FD geometry: paren width 25 (3.00"–5.50")', L.widths.paren === 25);
  check('FD geometry: action width 60 (1.5"–7.5")', L.widths.action === 60 && L.widths.scene === 60);
  check('FD geometry: cue at 3.50" width 37', L.cols.character === 252 && L.widths.character === 37);
  check('FD geometry: transition right edge 7.10"', L.transRight === 511.2);
  check('FD geometry: paren hang flag on typed docs', L.parenHang === 1);
  nd.elements = [
    { id: 'g1', type: 'scene', text: 'INT. A - DAY' },
    { id: 'g2', type: 'character', text: 'SAM' },
    { id: 'g3', type: 'paren', text: '(a parenthetical long enough to wrap onto another line)' },
    { id: 'g4', type: 'dialogue', text: 'Hello.' },
  ];
  const gres = E.paginate(nd);
  const pl = gres.pages[1].lines.filter(l => l.el === 'g3');
  check('FD geometry: paren wraps at 25', pl.length >= 2, String(pl.length));
  check('FD geometry: paren first line hangs 0.10" left', pl.length >= 2 && Math.abs(pl[0].x - (216 - 7.2)) < 0.01 && Math.abs(pl[1].x - 216) < 0.01, pl.map(l => l.x).join(','));
}

// -- 11. every import is conformed to Final Draft (There Will Be Blood came in
//        double-spaced at 69 characters to the line and read as a different script)
{
  // The row pitch is the smallest frequent gap the dominant gap is a multiple of:
  // a script made of one-line paragraphs makes the PARAGRAPH gap the commonest of
  // all, and a plain mode then reads the script as double-spaced. Synthetic page:
  // lines 12pt apart, paragraphs 24pt apart, paragraph gaps in the majority.
  const items = [];
  let y = 100;
  for (let p = 0; p < 30; p++) {
    items.push({ x: 108, y, w: 200, str: 'Body line one of paragraph ' + p });
    y += 12;
    items.push({ x: 108, y, w: 200, str: 'and its second line here.' });
    y += 24;                                       // paragraph gap = two pitches
  }
  const dbl = E.importPdf([{ width: 612, height: 792,
    items: items.map(i => ({ x: i.x, y: i.y, w: i.w, str: i.str })) }]);
  check('import: row pitch is the line gap, not the paragraph gap', dbl.layout.rowH === 12,
    'rowH=' + dbl.layout.rowH);

  // conformance, on the real fixture
  const conf = E.toFinalDraft(E.importPdf(raw));
  const fresh = E.newDoc('X').layout;
  check('import: conformed to FD page and type', conf.layout.pageW === 612 && conf.layout.charW === 7.2
    && conf.layout.rowH === 12, [conf.layout.pageW, conf.layout.charW, conf.layout.rowH].join('/'));
  check('import: conformed to FD columns', JSON.stringify(conf.layout.cols) === JSON.stringify(fresh.cols));
  check('import: conformed to FD widths', JSON.stringify(conf.layout.widths) === JSON.stringify(fresh.widths));
  check('import: conformed to FD transition edge', conf.layout.transRight === fresh.transRight);
  check('import: no source x survives to fight the columns',
    conf.elements.every(e => e.xOverride == null));
  check('import: source blank-row gaps give way to FD spacing',
    conf.elements.every(e => e.spaceBefore == null));
  // an import wraps exactly where a script typed in PICA wraps — the whole point
  const typedW = fresh.widths;
  check('import: wraps at the same measure as a typed script',
    conf.layout.widths.action === typedW.action && conf.layout.widths.dialogue === typedW.dialogue);
  // and nothing was lost conforming it
  const src = E.importPdf(raw);
  check('import: every element survives conforming', conf.elements.length === src.elements.length,
    conf.elements.length + ' vs ' + src.elements.length);
  check('import: emphasis survives conforming',
    conf.elements.filter(e => e.marks).length === src.elements.filter(e => e.marks).length);
  const words = e => e.text.replace(/\s+/g, ' ').trim();
  check('import: no word is lost when paragraphs reflow',
    conf.elements.every((e, i) => words(e) === words(src.elements[i])));
  // paragraph line breaks belong to the source's page, not to the script
  const dialogueBreaks = conf.elements.filter(e => e.type === 'dialogue' && !e.dual && e.text.includes('\n'));
  check('import: speeches flow rather than keeping the source\'s line breaks',
    dialogueBreaks.length === 0, dialogueBreaks.length + ' left');
}

console.log(failures ? `\n${failures} FAILURE(S)` : '\nall green — the page is the truth');
process.exit(failures ? 1 : 0);
