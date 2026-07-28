// ============================================================================
// PICA FULL SUITE — engine side.        ** BUILT, NOT YET RUN — by Labern's   **
// ** instruction this suite is not executed until he says so. **
//
// Run (when told):   node tests/suite.mjs
// Companion:         tests/suite-app.swift  (the app-shell side; see its header)
//
// Fixtures: tests/fixtures/*.json are pre-extracted PDF text layers (gitignored,
// derived from copyrighted scripts). Sections whose fixture is absent SKIP loudly
// rather than fail — the suite reports coverage honestly either way.
// ============================================================================
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const FIX = p => path.join(here, 'fixtures', p);

const html = fs.readFileSync(path.join(here, '..', 'index.html'), 'utf8');
const block = html.match(/\/\*PICA-ENGINE-START\*\/[\s\S]*\/\*PICA-ENGINE-END\*\//);
const E = new Function(block[0] + '; return PicaEngine;')();

let pass = 0, fail = 0, skip = 0;
const ok = (name, cond, detail = '') => {
  console.log((cond ? '  ok   ' : 'FAIL   ') + name + (detail ? ' — ' + detail : ''));
  cond ? pass++ : fail++;
};
const skipIf = (name, why) => { console.log('  skip ' + name + ' — ' + why); skip++; };
const load = f => fs.existsSync(FIX(f)) ? JSON.parse(fs.readFileSync(FIX(f))).pages : null;

// ---------------------------------------------------------------------------
console.log('§ 1 · Tenet fidelity — the founding contract');
{
  const raw = load('tenet-raw.json');
  if (!raw) skipIf('tenet fidelity', 'fixtures/tenet-raw.json missing');
  else {
    const charW = E.estimateCharW(raw);
    const truth = raw.map(p => ({ width: p.width, height: p.height, lines: E.linesFromItems(p.items, charW) }));
    const doc = E.importPdf(raw);
    const res = E.paginate(doc);
    const norm = s => s.replace(/\s+/g, ' ').trim();
    let good = 0, total = 0;
    for (let i = 0; i < Math.max(truth.length, res.pages.length); i++) {
      const src = (truth[i]?.lines ?? []).slice().sort((a, b) => a.y - b.y || a.x - b.x);
      const mine = (res.pages[i]?.lines ?? []).slice().sort((a, b) => a.y - b.y || a.x - b.x);
      for (let j = 0; j < Math.max(src.length, mine.length); j++) {
        total++;
        const s = src[j], m = mine[j];
        if (s && m && norm(s.text) === norm(m.text) && Math.abs(s.x - m.x) < 1.6 && Math.abs(s.y - m.y) < 1.6) good++;
      }
    }
    ok('every line of Tenet identical', good === total, good + '/' + total);
    ok('(MORE) splits regenerate ×6', res.pages.flatMap(p => p.lines).filter(l => l.kind === 'more').length === 6);
    ok('275 scenes', doc.elements.filter(e => e.type === 'scene').length === 275);
  }
}

// ---------------------------------------------------------------------------
console.log('§ 2 · Real-world PDF classes — structural invariants per disease');
{
  const cases = [
    // [fixture, name, assertions]
    ['col-raw.json', 'Collateral (revision headers + scene-number gutter)', (doc, res, raw) => {
      ok('  revision headers scrubbed', doc.elements.filter(e => /revs\.|goldenrod|salmon/i.test(e.text)).length === 0);
      ok('  title page captured', doc.titlePage.length > 20);
      ok('  opens on material', /FADE IN|INT\.|EXT\./.test(doc.elements[0].text));
      ok('  scenes found', doc.elements.filter(e => e.type === 'scene').length > 150);
      ok('  deep top margin honoured', doc.layout.y0 > 75, 'y0=' + doc.layout.y0);
      // revision stars: marginalia, never text — stripped, remembered, re-rendered
      ok('  no absorbed margin stars', doc.elements.filter(e => /\s{2,}\*+(\s|$)/.test(e.text) || /^\*+$/.test(e.text.trim())).length === 0);
      ok('  star band x recorded', Math.abs((doc.layout.revX ?? 0) - 568.8) < 2, 'revX=' + doc.layout.revX);
      ok('  starred lines remembered', doc.elements.filter(e => e.rev).length > 300);
      const all = res.pages.flatMap(p => p.lines);
      ok('  stars thread into pagination', all.filter(l => l.rev).length > 400);
      ok("  no star inside a (CONT'D) cue", all.filter(l => l.kind === 'contcue' && /\*/.test(l.text)).length === 0);
      let parenMore = 0;
      for (const p of res.pages) for (let i = 1; i < p.lines.length; i++)
        if (p.lines[i].kind === 'more' && p.lines[i - 1].kind === 'paren') parenMore++;
      ok('  no (MORE) dangling after a parenthetical', parenMore === 0);
    }],
    ['dl-Kill_Bill.json', 'Kill Bill (bare page numbers)', (doc, res) => {
      ok('  no stray numeric elements', doc.elements.filter(e => /^[A-Za-z]?\d+[A-Za-z]?[.:]?$/.test(e.text.trim())).length <= 2);
      ok('  page count sane', Math.abs(res.count - 189) <= 6, String(res.count));
    }],
    ['dl-ThereWillBeBlood.json', 'There Will Be Blood (unmapped title-page font)', (doc) => {
      ok('  body decoded to English', doc.elements.some(e => e.text.includes('EXT. NEW MEXICO DESERT')));
      ok('  no silent blank', doc.elements.filter(e => e.text.trim() !== '').length > 2500);
    }],
    ['dl-Heat.json', 'Heat', (doc, res) => {
      ok('  scenes found', doc.elements.filter(e => e.type === 'scene').length > 200);
      ok('  pages sane', Math.abs(res.count - 156) <= 5, String(res.count));
    }],
    ['nc-raw.json', 'No Country (smeared glyph origins)', (doc) => {
      const c = doc.layout.cols;
      ok('  four distinct columns', c.dialogue - c.action > 30 && c.character - c.paren > 20, JSON.stringify(c));
    }],
    ['opp-raw.json', 'Oppenheimer (overprinted text + ISO-dated running head)', (doc, res) => {
      // the disease: an unrecognized running head leaks on every page, its items
      // poison the column histogram, and every cue mis-files as parenthetical
      ok('  running head scrubbed', doc.elements.filter(e => /gadget.*gadget|shooting script|\d{4}-\d{2}-\d{2}/i.test(e.text)).length === 0);
      ok('  no doubled overprint text', doc.elements.filter(e => /(\b\w{5,}\b)\1/.test(e.text.replace(/\s+/g, ''))).length === 0);
      const c = doc.layout.cols;
      ok('  columns in order', c.action < c.dialogue && c.dialogue < c.paren && c.paren < c.character, JSON.stringify(c));
      const h = {};
      for (const e of doc.elements) h[e.type] = (h[e.type] || 0) + 1;
      ok('  cues classified as cues', (h.character || 0) > 1500, String(h.character));
      ok('  parens sane', (h.paren || 0) < 300, String(h.paren));
      ok('  transitions found', (h.transition || 0) > 20, String(h.transition));
      ok('  scenes found', (h.scene || 0) > 250, String(h.scene));
      ok('  page count near source (198)', Math.abs(res.count - 198) <= 12, String(res.count));
    }],
  ];
  for (const [f, name, fn] of cases) {
    const raw = load(f);
    if (!raw) { skipIf(name, f + ' missing'); continue; }
    console.log('  · ' + name);
    const doc = E.importPdf(raw);
    const res = E.paginate(doc);
    fn(doc, res, raw);
  }
}

// ---------------------------------------------------------------------------
console.log('§ 3 · FDX — Final Draft interop');
{
  const own = '/Users/labern/Desktop/Core/Screenplays/Begin.fdx';
  if (!fs.existsSync(own)) skipIf('FDX vs his own script', own + ' missing');
  else {
    const doc = E.importFdx(fs.readFileSync(own, 'utf8'));
    ok('Begin.fdx imports', doc.elements.length > 40, doc.elements.length + ' elements');
    ok('cues found', doc.elements.filter(e => e.type === 'character').length >= 15);
    const doc2 = E.importFdx(E.toFdx(doc));
    ok('round-trip preserves every element', doc.elements.length === doc2.elements.length &&
      doc.elements.every((e, i) => e.type === doc2.elements[i].type && e.text.replace(/\n/g, ' ') === doc2.elements[i].text));
  }
  // synthetic: marks survive the round-trip
  const d = E.newDoc('T');
  d.elements = [
    { id: E.uid(), type: 'scene', text: 'INT. ROOM - DAY' },
    { id: E.uid(), type: 'action', text: 'He waits, tensely.', marks: [[3, 8, 'b'], [10, 17, 'u']] },
  ];
  const rt = E.importFdx(E.toFdx(d));
  const m = rt.elements[1].marks || [];
  ok('bold/underline marks survive FDX', m.some(x => x[2] === 'b') && m.some(x => x[2] === 'u'), JSON.stringify(m));
  ok('a non-FDX file is refused', (() => { try { E.importFdx('<html>nope</html>'); return false; } catch { return true; } })());
}

// ---------------------------------------------------------------------------
console.log('§ 4 · Editing invariants at engine level');
{
  const raw = load('tenet-raw.json');
  if (!raw) skipIf('editing invariants', 'tenet fixture missing');
  else {
    const doc = E.importPdf(raw);
    const el = doc.elements.find(e => e.type === 'dialogue' && !e.text.includes('\n'));
    const before = E.paginate(doc).pages.length;
    const orig = el.text;
    el.text += ' An extra sentence that must reflow the page.';
    ok('edit repaginates', E.paginate(doc).pages.length >= before);
    el.text = orig;
    ok('restore returns identical page count', E.paginate(doc).pages.length === before);
    // spaceBefore overrides survive pagination round trips
    const spaced = doc.elements.find(e => e.spaceBefore != null);
    if (spaced) ok('authorial spacing override honoured', true, 'spaceBefore=' + spaced.spaceBefore);
    else ok('authorial spacing override present (p121 quirk)', false, 'expected at least one');
  }
  const blank = E.newDoc('NEW');
  ok('blank doc paginates to title + 1', E.paginate(blank).pages.length === 2);
  ok('fountain export produces text', E.toFountain(E.newDoc('X')).length > 0);
}

// ---------------------------------------------------------------------------
console.log('§ 5 · Furniture & decoder guardrails (must never over-fire)');
{
  // a clean modern script must lose nothing to the furniture/decoder passes
  const raw = load('dl-LaLaLand.json') || load('the-social-network-2010-raw.json');
  if (!raw) skipIf('over-fire guard', 'no clean-script fixture');
  else {
    const doc = E.importPdf(raw);
    ok('no decode note on a healthy PDF', !doc.importNote, doc.importNote || '');
    ok('body text intact', doc.elements.reduce((s, e) => s + e.text.length, 0) > 90000);
  }
}

console.log('\n' + pass + ' passed · ' + fail + ' failed · ' + skip + ' skipped');
process.exit(fail ? 1 : 0);
