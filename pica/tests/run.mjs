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
  // emphasis survives — but a style covering a whole element type is the source's
  // typeface, not emphasis (Jackie Brown sets every speech bold), and is dropped
  check('import: emphasis survives conforming',
    conf.elements.filter(e => e.marks).length === src.elements.filter(e => e.marks).length);
  {
    // a document whose every speech is bold arrives with plain speeches
    const faux = JSON.parse(JSON.stringify(src));
    for (const e of faux.elements)
      if (e.type === 'dialogue' && e.text.length) e.marks = [[0, e.text.length, 'b']];
    const flat = E.toFinalDraft(faux);
    check('import: a whole-type style is the source\'s face, not emphasis',
      flat.elements.every(e => e.type !== 'dialogue' || !(e.marks || []).some(m => m[2] === 'b')));
    check('import: exceptional emphasis is not swept up with it',
      E.toFinalDraft((() => {
        const one = JSON.parse(JSON.stringify(src));
        const d = one.elements.find(e => e.type === 'dialogue' && e.text.length > 8);
        d.marks = [[0, 4, 'b']];
        return one;
      })()).elements.some(e => (e.marks || []).some(m => m[2] === 'b')));
  }
  const words = e => e.text.replace(/\s+/g, ' ').trim();
  check('import: no word is lost when paragraphs reflow',
    conf.elements.every((e, i) => words(e) === words(src.elements[i])));
  // paragraph line breaks belong to the source's page, not to the script
  const dialogueBreaks = conf.elements.filter(e => e.type === 'dialogue' && !e.dual && e.text.includes('\n'));
  check('import: speeches flow rather than keeping the source\'s line breaks',
    dialogueBreaks.length === 0, dialogueBreaks.length + ' left');
}

// -- 12. titles taken from a filename read as titles
{
  const cases = [
    ['ThereWillBeBlood.pdf', 'THERE WILL BE BLOOD'],
    ['Jackie-Brown.pdf', 'JACKIE BROWN'],
    ['there_will_be_blood.pdf', 'THERE WILL BE BLOOD'],
    ['TENET.pdf', 'TENET'],
    ['The Master.pdf', 'THE MASTER'],
  ];
  // the helper lives in the UI half of index.html, not the engine block
  const src = html.match(/function titleFromFilename[\s\S]*?\n}/);
  const titleFromFilename = src ? new Function(src[0] + '; return titleFromFilename;')() : null;
  check('title: filename helper present', !!titleFromFilename);
  if (titleFromFilename)
    for (const [file, want] of cases)
      check('title: ' + file + ' → ' + want, titleFromFilename(file, 'pdf') === want,
        titleFromFilename(file, 'pdf'));
}

// -- 13. cue vs parenthetical: the two columns are 0.5" apart, and a source only has to
//        drift for a line to be assigned to the wrong one. Jackie Brown's "ORDELL
//        (CONT'D)" became a parenthetical — wrong indent, and invisible to the
//        paginator's speech rules, so it sat alone at the foot of a page with its speech
//        overleaf. There Will Be Blood made the opposite mistake with "(beat)".
{
  const rowH = 12, y0 = 76.5, charW = 7.2;
  const line = (x, row, str) => ({ x, y: y0 + row * rowH, w: str.length * charW, str });
  // three pages of ordinary geometry, so the importer measures FD's columns…
  const pages = [];
  for (let p = 0; p < 3; p++) {
    const items = [];
    let r = 0;
    items.push(line(108, r++, 'INT. OFFICE ' + p + ' - DAY'));
    r++;
    items.push(line(108, r++, 'Someone crosses the room and picks up the telephone.'));
    r++;
    items.push(line(252, r++, 'SAM'));
    items.push(line(180, r++, 'A line of dialogue goes here.'));
    r++;
    items.push(line(252, r++, 'ALEX'));
    items.push(line(216, r++, '(quietly)'));
    items.push(line(180, r++, 'Another line of dialogue.'));
    r++;
    // …then the two mistakes, each planted on the WRONG column:
    // a cue sitting on the parenthetical column
    items.push(line(216, r++, 'ORDELL (CONT’D)'));
    items.push(line(180, r++, 'The speech that belongs to it.'));
    r++;
    // a parenthetical sitting on the character column
    items.push(line(252, r++, 'SAM'));
    items.push(line(252, r++, '(beat)'));
    items.push(line(180, r++, 'And the line after the beat.'));
    pages.push({ width: 612, height: 792, items });
  }
  const d = E.importPdf(pages);
  const find = t => d.elements.find(e => e.text.trim() === t);
  const cue = find('ORDELL (CONT’D)');
  const beat = find('(beat)');
  check('cue/paren: a cue on the parenthetical column is still a cue',
    !!cue && cue.type === 'character', cue ? cue.type : 'not found');
  check('cue/paren: a parenthetical on the cue column is still a parenthetical',
    !!beat && beat.type === 'paren', beat ? beat.type : 'not found');
  check('cue/paren: ordinary cues and parentheticals are untouched',
    (find('SAM') || {}).type === 'character' && (find('(quietly)') || {}).type === 'paren');

  // and the invariant it protects: a page must never end on a character cue, its
  // speech stranded overleaf
  const orphans = [];
  for (const doc of [d, E.importPdf(raw)]) {
    const res = E.paginate({ ...doc, titlePage: [] });
    const byId = new Map(doc.elements.map(e => [e.id, e]));
    res.pages.forEach((pg, pi) => {
      const body = pg.lines.filter(l => l.kind !== 'pn' && l.kind !== 'rev' && l.kind !== 'more');
      const last = body[body.length - 1];
      if (!last) return;
      const el = byId.get(last.el);
      if (el && el.type === 'character') orphans.push('p' + (pi + 1) + ':' + last.text.slice(0, 20));
    });
  }
  check('cue/paren: no page ends on a character cue', orphans.length === 0, orphans.slice(0, 3).join(' '));
}

// -- 14. a script whose speech columns are COLLAPSED into one. Some Like It Hot (1958)
//        sets cue, parenthetical and dialogue all flush at 1.78" — the only indent on the
//        page besides action. Read by column, all 1,051 speech lines a page get one type:
//        it imported as 3,754 character cues out of 4,781 elements, and zero scene
//        headings, because its slugs begin with an inline scene number.
{
  const rowH = 12, y0 = 76.5, charW = 7.2;
  const A = 32, S2 = 128;                       // the two columns this format has
  const line = (x, row, str) => ({ x, y: y0 + row * rowH, w: str.length * charW, str });
  const pages = [];
  for (let p = 0; p < 4; p++) {
    const items = []; let r = 0;
    // slug numbered inline at the action margin, mirrored on the right
    items.push(line(A, r++, (p + 1) + '.      INT.  OFFICE - DAY.                    ' + (p + 1) + '.'));
    r++;
    items.push(line(A, r++, 'Someone crosses the room and answers the telephone.'));
    r++;
    items.push(line(S2, r++, 'JOE'));           // cue, parenthetical and dialogue…
    items.push(line(S2, r++, '(looking up)'));  // …all on the SAME column
    items.push(line(S2, r++, 'Anything today?'));
    r++;
    items.push(line(S2, r++, "NELLIE'S VOICE"));
    items.push(line(S2, r++, "Oh, it's you! You got a lot of nerve -"));
    r++;
    items.push(line(A, r++, 'He shuts the door quickly, starts to move on.'));
    r++;
    items.push(line(74, r++, 'DISSOLVE TO:'));  // transitions sit between the columns
    pages.push({ width: 612, height: 792, items });
  }
  const d = E.importPdf(pages);
  const typeOf = t => (d.elements.find(e => e.text.trim() === t) || {}).type;
  check('collapsed columns: the cue is a cue', typeOf('JOE') === 'character', typeOf('JOE'));
  check('collapsed columns: the parenthetical is a parenthetical',
    typeOf('(looking up)') === 'paren', typeOf('(looking up)'));
  check('collapsed columns: the speech is dialogue',
    typeOf('Anything today?') === 'dialogue', typeOf('Anything today?'));
  check('collapsed columns: a cue with an apostrophe is still a cue',
    typeOf("NELLIE'S VOICE") === 'character', typeOf("NELLIE'S VOICE"));
  check('collapsed columns: action stays action',
    typeOf('He shuts the door quickly, starts to move on.') === 'action');
  check('collapsed columns: the transition survives a wider tolerance',
    typeOf('DISSOLVE TO:') === 'transition', typeOf('DISSOLVE TO:'));
  // an inline scene number must not stop a slug being a slug, and must not stay in it
  const scenes = d.elements.filter(e => e.type === 'scene');
  check('collapsed columns: inline-numbered slugs are scene headings', scenes.length === 4,
    scenes.length + ' found');
  check('collapsed columns: the scene number is lifted off the slug',
    scenes.every(e => /^INT\./.test(e.text.trim())), (scenes[0] || {}).text);
  // nothing may be left unclassified, and no page may end on a cue
  check('collapsed columns: nothing falls through to general',
    d.elements.filter(e => e.type === 'general').length === 0);
  // and a normally-columned script is untouched by any of it
  const t = E.importPdf(raw);
  check('collapsed columns: a four-column script is unaffected',
    t.elements.filter(e => e.type === 'character').length > 400
    && t.elements.filter(e => e.type === 'dialogue').length > 400);
}

// -- 15. the rest of what Some Like It Hot exposed
{
  const rowH = 12, y0 = 76.5, charW = 7.2;
  const A = 32, S2 = 128;
  const line = (x, row, str) => ({ x, y: y0 + row * rowH, w: str.length * charW, str });

  // (a) a slug numbered on BOTH sides with no INT/EXT at all is still a slug, and the
  //     mirrored number must not survive to wrap onto a line of its own
  // (b) title matter at the top of page one belongs on the title page
  // (c) a parenthetical that runs onto a second line must not swallow the cue above it
  // (d) a cue is always followed by what was said, even when that line is typed at the
  //     action margin
  const pages = [];
  for (let p = 0; p < 3; p++) {
    const items = []; let r = 0;
    if (p === 0) {
      items.push(line(A, r++, '"A TITLE IN QUOTES"'));
      r++;
      items.push(line(A, r++, 'Screenplay by'));
      items.push(line(A, r++, 'Someone Entirely'));
      r++;
      items.push(line(A, r++, 'November 12, 1958'));
      r++;
    }
    items.push(line(A, r++, (p + 1) + '.      CITY AT NIGHT.                       ' + (p + 1) + '.'));
    r++;
    items.push(line(A, r++, 'A hearse proceeds at a dignified pace.'));
    r++;
    items.push(line(S2, r++, 'JOE'));
    items.push(line(S2, r++, '(points to the cord running across'));   // paren over two lines
    items.push(line(S2, r++, 'the back of the berth)'));
    items.push(line(A, r++, 'Then pull the emergency brake!'));        // speech at the action margin
    r++;
    items.push(line(A, r++, 'OMITTED'));                               // signage, not a cue
    r++;
    items.push(line(A, r++, 'She exits. He turns furiously.'));
    pages.push({ width: 612, height: 792, items });
  }
  const d = E.importPdf(pages);
  const typeOf = t => (d.elements.find(e => e.text.trim().startsWith(t)) || {}).type;

  check('some: a mirrored-numbered slug with no INT/EXT is a scene',
    typeOf('CITY AT NIGHT') === 'scene', typeOf('CITY AT NIGHT'));
  check('some: the mirrored number is gone from the slug',
    !d.elements.some(e => /^\d+\.$/.test(e.text.trim())));
  check('some: title matter moves to the title page',
    (d.titlePage || []).some(t2 => /A TITLE IN QUOTES/.test(t2.text)), JSON.stringify((d.titlePage || []).map(x => x.text)));
  check('some: the quotes are not part of the title', d.title === 'A TITLE IN QUOTES', d.title);
  check('some: the title matter is out of the script',
    !d.elements.some(e => /Screenplay by/.test(e.text)));
  check('some: a two-line parenthetical is a parenthetical',
    typeOf('(points to the cord') === 'paren', typeOf('(points to the cord'));
  check('some: the cue above it survives as a cue', typeOf('JOE') === 'character', typeOf('JOE'));
  check('some: speech typed at the action margin is still speech',
    typeOf('Then pull the emergency') === 'dialogue', typeOf('Then pull the emergency'));
  check('some: signage is not mistaken for a cue', typeOf('OMITTED') !== 'character', typeOf('OMITTED'));
  check('some: nothing is left unclassified',
    d.elements.filter(e => e.type === 'general').length === 0);
  // a slug arrives from a typewriter with two spaces after the stop; FD sets one
  check('some: slugs are single-spaced',
    d.elements.filter(e => e.type === 'scene').every(e => !/\s{2,}/.test(e.text)),
    JSON.stringify(d.elements.filter(e => e.type === 'scene').map(e => e.text)));
  // a two-column title line becomes two entries, and the right-hand one must END inside
  // the right margin rather than run off the sheet ("November 12, 195")
  const tpE = d.titlePage || [];
  const right = tpE.find(t2 => /November/.test(t2.text));
  check('some: the two-column title line is split in two',
    !!right && tpE.some(t2 => /A TITLE IN QUOTES/.test(t2.text)));
  check('some: the right-hand title column ends inside the margin',
    !!right && right.x + right.text.length * 7.2 <= 612 - 72 + 0.5,
    right ? (right.x + right.text.length * 7.2).toFixed(1) : 'missing');
  check('some: blank lines inside the title block survive',
    new Set(tpE.map(t2 => t2.row)).size >= 4);

  // (e) dual dialogue must survive CONFORMING: its two columns ARE its xOverride, and
  //     dropping them stacks both speeches on one x so they print through each other.
  //     The fidelity gate never saw this — it tests the extractor, before conformance.
  const whipPath = path.join(FIX, 'whip-raw.json');
  if (fs.existsSync(whipPath)) {
    const wd2 = E.toFinalDraft(E.importPdf(JSON.parse(fs.readFileSync(whipPath, 'utf8')).pages));
    const groups = new Map();
    for (const e of wd2.elements) if (e.dual) {
      if (!groups.has(e.dual.g)) groups.set(e.dual.g, []);
      groups.get(e.dual.g).push(e);
    }
    const twoColumned = [...groups.values()]
      .filter(g => new Set(g.map(e => e.xOverride)).size >= 2).length;
    check('some: dual dialogue keeps its two columns through conforming',
      groups.size > 0 && twoColumned === groups.size, twoColumned + ' of ' + groups.size);
    check('some: every dual element still has an x on the page',
      wd2.elements.filter(e => e.dual).every(e => e.xOverride > 0 && e.xOverride < 612));
  }
}

// -- 16. a SCAN does not sit still. There Will Be Blood's columns are at 94/174/252 on its
//        early pages and 102/184/263 by page 70, then back again — the sheet moved under
//        the glass. At a fixed tolerance 664 lines, whole speeches included, matched no
//        column at all. Each page's own offset is measured and taken out first.
{
  const rowH = 12, y0 = 76.5, charW = 7.2;
  const line = (x, row, str) => ({ x, y: y0 + row * rowH, w: str.length * charW, str });
  const build = drift => {
    const pages = [];
    for (let p = 0; p < 12; p++) {
      const d = drift ? p : 0;                   // the sheet creeps, a point a page
      const items = []; let r = 0;
      items.push(line(108 + d, r++, 'INT. OFFICE ' + p + ' - DAY'));
      r++;
      items.push(line(108 + d, r++, 'Someone crosses the room and answers the telephone.'));
      r++;
      items.push(line(252 + d, r++, 'JOE'));
      items.push(line(216 + d, r++, '(quietly)'));
      items.push(line(180 + d, r++, 'Anything today at all?'));
      r++;
      items.push(line(252 + d, r++, 'NELLIE'));
      items.push(line(180 + d, r++, 'Nothing whatever, I am afraid.'));
      r++;
      items.push(line(400 + d, r++, 'CUT TO:'));
      pages.push({ width: 612, height: 792, items });
    }
    return E.importPdf(pages);
  };
  const still = build(false), wandering = build(true);
  const tally = d => {
    const t = {};
    for (const e of d.elements) t[e.type] = (t[e.type] || 0) + 1;
    return t;
  };
  const a = tally(still), b = tally(wandering);
  check('scan: a still page and a wandering one classify the same',
    JSON.stringify(a) === JSON.stringify(b), JSON.stringify(a) + ' vs ' + JSON.stringify(b));
  check('scan: nothing is left unclassified when the sheet moves',
    (b.general || 0) === 0, String(b.general || 0));
  check('scan: the cues survive the drift', (b.character || 0) === 24, String(b.character || 0));
  // a shouted line ending in a colon is a transition wherever the scan put it
  check('scan: transitions survive the drift', (b.transition || 0) === 12, String(b.transition || 0));
  // and a lone cue must never be left at the foot of a page
  const lone = E.newDoc('L');
  lone.elements = [];
  for (let i = 0; i < 52; i++) lone.elements.push({ id: 'a' + i, type: 'action', text: 'A line of action ' + i + '.' });
  lone.elements.push({ id: 'cue', type: 'character', text: 'SAM' });
  lone.elements.push({ id: 'dlg', type: 'dialogue', text: 'At last.' });
  const lres = E.paginate({ ...lone, titlePage: [] });
  const endsOnCue = lres.pages.some(pg => {
    const body = pg.lines.filter(l => l.kind !== 'pn' && l.kind !== 'rev' && l.kind !== 'more');
    const last = body[body.length - 1];
    return last && last.el === 'cue';
  });
  check('scan: a lone cue is never the last thing on a page', !endsOnCue);
}

// -- 17. the search reads what it downloads and prefers a cleaner copy. The web has
//        several copies of most scripts and they are not equally good — one a clean
//        export, the next a photocopy read by a machine.
{
  const src = /function scoreImport\(doc\)\{[\s\S]*?\n\}/.exec(html);
  const scoreImport = src ? new Function(src[0] + '; return scoreImport;')() : null;
  check('quality: the judge is present', !!scoreImport);
  if (scoreImport) {
    const good = E.toFinalDraft(E.importPdf(raw));
    const gq = scoreImport(good);
    check('quality: a clean export reads as clean', gq.score >= 88, gq.score + ' ' + gq.notes.join(','));

    // the same script with a tenth of its lines unplaced, as a bad scan arrives
    const rough = JSON.parse(JSON.stringify(good));
    for (let i = 0; i < rough.elements.length; i += 10) rough.elements[i].type = 'general';
    const rq = scoreImport(rough);
    check('quality: a rough copy scores below a clean one', rq.score < gq.score,
      rq.score + ' vs ' + gq.score);
    check('quality: and says what is wrong with it', rq.notes.some(n => /unplaced/.test(n)),
      rq.notes.join(','));

    // a copy with no scene headings at all is not a screenplay
    const headless = JSON.parse(JSON.stringify(good));
    for (const e of headless.elements) if (e.type === 'scene') e.type = 'action';
    check('quality: a copy with no scene headings is marked down',
      scoreImport(headless).score < gq.score - 30, String(scoreImport(headless).score));

    // and a stub is not a script
    const stub = { elements: good.elements.slice(0, 40) };
    check('quality: a stub is marked down', scoreImport(stub).score < 80, String(scoreImport(stub).score));
  }
}

// -- 18. a script assembled from pages typed at different times has more than one tab stop
//        for the same thing. There Will Be Blood's cues are at 3.5" for most of the film and
//        about 4.05" for a stretch of it — whole conversations came back unclassified.
{
  const rowH = 12, y0 = 76.5, charW = 7.2;
  const line = (x, row, str) => ({ x, y: y0 + row * rowH, w: str.length * charW, str });
  const pages = [];
  for (let p = 0; p < 14; p++) {
    // the last third of the script was retyped with the cue tab 40pt further in
    const cue = p >= 9 ? 292 : 252;
    const items = []; let r = 0;
    items.push(line(108, r++, 'INT. OFFICE ' + p + ' - DAY'));
    r++;
    items.push(line(108, r++, 'Someone crosses the room and answers the telephone.'));
    r++;
    items.push(line(cue, r++, 'HENRY'));
    items.push(line(180, r++, 'Did you mention my name at all?'));
    r++;
    items.push(line(cue, r++, 'DANIEL'));
    items.push(line(180, r++, 'I did not, and I do not intend to.'));
    pages.push({ width: 612, height: 792, items });
  }
  const d = E.importPdf(pages);
  const t = {};
  for (const e of d.elements) t[e.type] = (t[e.type] || 0) + 1;
  check('tab stops: a second tab stop for the cue is still the cue', (t.character || 0) === 28,
    JSON.stringify(t));
  check('tab stops: nothing is left unclassified by it', !(t.general > 0), String(t.general || 0));
  // and a column that is genuinely something else is NOT swallowed
  const far = [];
  for (let p = 0; p < 6; p++) {
    const items = []; let r = 0;
    items.push(line(108, r++, 'INT. ROOM - DAY'));
    r++;
    items.push(line(108, r++, 'She waits by the window for a long time.'));
    r++;
    items.push(line(252, r++, 'SAM'));
    items.push(line(180, r++, 'Nothing at all today?'));
    r++;
    items.push(line(432, r++, 'CUT TO:'));
    far.push({ width: 612, height: 792, items });
  }
  const fd2 = E.importPdf(far);
  const t2 = {};
  for (const e of fd2.elements) t2[e.type] = (t2[e.type] || 0) + 1;
  check('tab stops: a transition margin is not mistaken for a cue tab',
    (t2.transition || 0) === 6 && (t2.character || 0) === 6, JSON.stringify(t2));
}

// -- 19. a numbered list is structure, not a paragraph that happened to wrap. Kill Bill
//        opens on its table of contents, and flowing it turned the chapters into prose.
{
  const rowH = 12, y0 = 76.5, charW = 7.2;
  const line = (x, row, str) => ({ x, y: y0 + row * rowH, w: str.length * charW, str });
  const pages = [];
  for (let p = 0; p < 4; p++) {
    const items = []; let r = 0;
    items.push(line(108, r++, 'INT. ROOM ' + p + ' - DAY'));
    r++;
    items.push(line(108, r++, '1. The Bride'));
    items.push(line(108, r++, '2. The Comatose Bride'));
    items.push(line(108, r++, '3. The Man From Okinawa'));
    r++;
    items.push(line(108, r++, 'She waits by the window for a very long time indeed.'));
    r++;
    items.push(line(252, r++, 'SAM'));
    items.push(line(180, r++, 'Nothing at all today?'));
    pages.push({ width: 612, height: 792, items });
  }
  const d = E.toFinalDraft(E.importPdf(pages));
  const list = d.elements.find(e => /The Comatose Bride/.test(e.text));
  check('list: a numbered list keeps its line breaks', !!list && list.text.split('\n').length >= 3,
    list ? JSON.stringify(list.text) : 'not found');
  check('list: ordinary prose still flows',
    d.elements.some(e => /waits by the window/.test(e.text) && !e.text.includes('\n')));
}

// -- 20. Reformat: repair a copy that is nearly right, from its own shape alone, and never
//        make one worse.
{
  const src2 = /function reformatDoc\(doc\)\{[\s\S]*?\n\}/.exec(html);
  const reformatDoc = src2 ? new Function('E', src2[0] + '; return reformatDoc;')(E) : null;
  check('reformat: the repair pass is present', !!reformatDoc);
  if (reformatDoc) {
    const good = E.toFinalDraft(E.importPdf(raw));
    const tally = d => { const t = {}; for (const e of d.elements) t[e.type] = (t[e.type] || 0) + 1; return t; };
    const wanted = tally(good);

    // rough it up the way a poor copy arrives
    const rough = JSON.parse(JSON.stringify(good));
    let broke = 0;
    for (let i = 1; i < rough.elements.length; i++) {
      const e = rough.elements[i], p = rough.elements[i - 1];
      if (e.type === 'dialogue' && p.type === 'character' && broke < 200) { e.type = 'action'; broke++; }
      else if (e.type === 'paren' && broke < 260) { e.type = 'action'; broke++; }
      else if (e.type === 'scene' && broke < 300) { e.type = 'general'; broke++; }
    }
    check('reformat: something was actually broken', broke > 100, String(broke));
    const fixed = reformatDoc(rough);
    const got = tally(fixed);
    check('reformat: speech under a cue is speech again',
      Math.abs((got.dialogue || 0) - (wanted.dialogue || 0)) <= 5,
      (got.dialogue || 0) + ' vs ' + (wanted.dialogue || 0));
    check('reformat: sluglines are sluglines again',
      Math.abs((got.scene || 0) - (wanted.scene || 0)) <= 2, (got.scene || 0) + ' vs ' + (wanted.scene || 0));
    check('reformat: nothing is left unclassified', !got.general, String(got.general || 0));
    check('reformat: no element is lost', fixed.elements.length === good.elements.length);
    // and it is safe to run twice
    const twice = tally(reformatDoc(JSON.parse(JSON.stringify(fixed))));
    check('reformat: running it again changes nothing', JSON.stringify(twice) === JSON.stringify(got));
    // running it on a good copy must not damage it
    const onGood = tally(reformatDoc(JSON.parse(JSON.stringify(good))));
    check('reformat: a good copy is left alone',
      Math.abs((onGood.dialogue || 0) - (wanted.dialogue || 0)) <= 5
      && Math.abs((onGood.scene || 0) - (wanted.scene || 0)) <= 2,
      JSON.stringify(onGood));
  }
}

// -- 21. a MARGIN is not a column. Memento prints its scene numbers, CONTINUEDs and a
//        revision stamp at x=72 — more lines than its parenthetical column has — so the
//        gutter won a column slot, and being leftmost it took ACTION's place: every column
//        was read one across and the whole script's action came back as dialogue.
{
  const rowH = 12, y0 = 76.5, charW = 7.2;
  const line = (x, row, str) => ({ x, y: y0 + row * rowH, w: str.length * charW, str });
  const pages = [];
  for (let p = 0; p < 12; p++) {
    const items = []; let r = 0;
    // a gutter: scene number and a revision stamp, well left of the action margin
    items.push(line(72, r, String(p + 1)));
    items.push(line(110, r++, 'INT. DERELICT HOUSE - DAY'));
    items.push(line(72, r++, 'MEMENTO Pink Revisions - 9/7/99'));
    r++;
    items.push(line(110, r++, 'A polaroid photograph, clasped between finger and thumb.'));
    items.push(line(110, r++, 'The image in the photo starts to fade as we super titles.'));
    r++;
    items.push(line(260, r++, 'LEONARD'));
    items.push(line(215, r++, '(quietly)'));
    items.push(line(185, r++, 'I have to remember this one thing.'));
    r++;
    items.push(line(72, r++, 'CONTINUED:'));
    pages.push({ width: 612, height: 792, items });
  }
  const d = E.importPdf(pages);
  const t = {};
  for (const e of d.elements) t[e.type] = (t[e.type] || 0) + 1;
  check('margin: action is action, not dialogue', (t.action || 0) >= 12, JSON.stringify(t));
  check('margin: dialogue is dialogue, not a parenthetical', (t.dialogue || 0) >= 12, String(t.dialogue || 0));
  check('margin: the cues are still cues', (t.character || 0) === 12, String(t.character || 0));
  check('margin: the parentheticals are still parentheticals', (t.paren || 0) === 12, String(t.paren || 0));
}

// -- 22. CONTINUEDs, revision stamps and page numbers are printing apparatus, not writing —
//        wherever on the page they land. Memento carried 183 of them into the script as
//        scene headings, transitions and action.
{
  const rowH = 12, y0 = 76.5, charW = 7.2;
  const line = (x, row, str) => ({ x, y: y0 + row * rowH, w: str.length * charW, str });
  const pages = [];
  for (let p = 0; p < 10; p++) {
    const items = []; let r = 0;
    items.push(line(110, r++, 'INT. MOTEL ROOM - DAY'));
    items.push(line(72,  r++, (p + 1) + '    CONTINUED:'));         // numbered, mid-page
    items.push(line(72,  r++, (p + 1) + ' CONTINUED: (2)'));        // and counted
    items.push(line(72,  r++, 'MEMENTO Pink Revisions - 9/7/99'));  // a revision stamp
    items.push(line(520, r++, String(40 + p) + '.'));               // a page number
    r++;
    items.push(line(110, r++, 'He turns the photograph over in his hands.'));
    r++;
    items.push(line(260, r++, 'LEONARD'));
    items.push(line(185, r++, 'I have to remember this.'));
    pages.push({ width: 612, height: 792, items });
  }
  const d = E.importPdf(pages);
  const has = re => d.elements.filter(e => re.test(e.text)).length;
  check('apparatus: no CONTINUED reaches the script', has(/CONTINUED/i) === 0, String(has(/CONTINUED/i)));
  check('apparatus: no revision stamp reaches the script', has(/Revisions/i) === 0, String(has(/Revisions/i)));
  check('apparatus: no bare page number reaches the script',
    d.elements.filter(e => /^\d{1,3}\.?$/.test(e.text.trim())).length === 0);
  check('apparatus: the writing itself is all there',
    has(/turns the photograph/) === 10 && has(/remember this/) === 10 && has(/MOTEL ROOM/) === 10);
  // and (MORE) is NOT apparatus — it is how a split speech is recognised
  check('apparatus: (MORE) survives, because pagination needs it',
    E.paginate(E.importPdf(raw)).pages.flatMap(p2 => p2.lines).filter(l => l.kind === 'more').length === 6);
}

console.log(failures ? `\n${failures} FAILURE(S)` : '\nall green — the page is the truth');
process.exit(failures ? 1 : 0);
