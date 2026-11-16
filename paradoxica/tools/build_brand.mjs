// Builds paradoxica/site/brand/: every mark as a centred SVG (white + black ink) and a
// 4096px transparent PNG of each, plus brand/marks.json for the page.
// Sources: logo-experiments/logos.js (vector, traced from Labern's LOGO_VARIATIONS.pdf and
// Trademarks.pdf) + the bracket-less stacked ™ (brackets removed at his request, 2026-11-16).
// Artwork is never redrawn: only the canvas (viewBox) is set — centred on the mark's body,
// with any ™/® hanging in the margin so left and right space match.
//   node paradoxica/tools/build_brand.mjs
import fs from 'node:fs'; import path from 'node:path'; import { createRequire } from 'node:module';
const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
const OUT = path.join(ROOT, 'paradoxica/site/brand');
const require = createRequire(import.meta.url); const { chromium } = require('playwright');
globalThis.window = {}; require(path.join(ROOT, 'logo-experiments/logos.js'));

const NAMES = {               // id → [group, display name]
  'horizontal-paradox': ['Horizontal', 'PARADOX'],
  'horizontal-kana': ['Horizontal', 'パラドックス'],
  'bracket-paradox': ['Stacked', 'Bracket · PARADOX'],
  'bracket-paradox-tm': ['Stacked', 'Bracket · PARADOX ™'],
  'bracket-paradox-r': ['Stacked', 'Bracket · PARADOX ®'],
  'stacked-tm-no-brackets': ['Stacked', 'PARADOX ™'],
  'stacked-kana': ['Stacked', 'パラドックス · tall'],
  'stacked-kana-2': ['Stacked', 'パラドックス'],
  'vertical-paradox': ['Vertical', 'PARADOX · rotated'],
  'vertical-paradox-2': ['Vertical', 'PARADOX · rotated, bold'],
  'vertical-paradox-tm': ['Vertical', 'PARADOX · rotated ™'],
  'vertical-paradox-r': ['Vertical', 'PARADOX · rotated ®'],
  'vertical-paradox-stacked': ['Vertical', 'P·A·R·A·D·O·X'],
  'vertical-paradox-stacked-tm': ['Vertical', 'P·A·R·A·D·O·X ™'],
  'vertical-paradox-stacked-r': ['Vertical', 'P·A·R·A·D·O·X ®'],
  'vertical-kana': ['Vertical', 'パラドックス · compact'],
  'vertical-kana-2': ['Vertical', 'パラドックス · spaced'],
  'vertical-kana-3': ['Vertical', 'パラドックス · small'],
};
const ORDER = Object.keys(NAMES);

const raw = {};
for (const l of window.LOGOS) if (NAMES[l.id])
  raw[l.id] = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="${l.vb}">${l.d}</svg>`;
raw['stacked-tm-no-brackets'] = fs.readFileSync(path.join(ROOT, 'paradoxica/tools/paradox-stacked-tm-no-brackets.src.svg'), 'utf8');

fs.mkdirSync(path.join(OUT, 'svg'), { recursive: true }); fs.mkdirSync(path.join(OUT, 'png'), { recursive: true });
const b = await chromium.launch(); const page = await b.newPage({ viewport: { width: 1200, height: 1200 } });
const marks = [];
for (const id of ORDER) {
  await page.setContent(`<body style="margin:0">${raw[id].replace('<svg ', '<svg id="m" style="width:1000px;height:1000px" ')}</body>`);
  const r = await page.evaluate(() => {
    const s = document.getElementById('m'); const inv = s.getScreenCTM().inverse();
    const U = (x, y) => { const p = s.createSVGPoint(); p.x = x; p.y = y; return p.matrixTransform(inv); };
    const leaves = [...s.querySelectorAll('path,use,text')].filter(e => !e.closest('defs')).map(e => {
      const c = e.getBoundingClientRect(); const a = U(c.left, c.top), z = U(c.right, c.bottom);
      return { L: a.x, T: a.y, R: z.x, B: z.y };
    }).filter(q => q.R - q.L > 0 && q.B - q.T > 0)
      // the source decks carry stray glyphs outside their own viewBox (never visible): ignore
      .filter(q => { const v = s.viewBox.baseVal; return q.R > v.x && q.L < v.x + v.width && q.B > v.y && q.T < v.y + v.height; });
    // ™ / ® = leaves that sit wholly to the right of everything else.
    // …and are much smaller than the letters (the last letter of a word is also "rightmost").
    const hs = leaves.map(q => q.B - q.T).sort((p, q) => p - q); const med = hs[Math.floor(hs.length / 2)];
    leaves.sort((p, q) => q.L - p.L); let k = 0;
    while (k < 3 && k < leaves.length - 1 && (leaves[k].B - leaves[k].T) < 0.55 * med &&
           leaves[k].L >= Math.max(...leaves.slice(k + 1).map(q => q.R)) - 0.5) k++;
    const ext = (a) => ({ L: Math.min(...a.map(q => q.L)), T: Math.min(...a.map(q => q.T)), R: Math.max(...a.map(q => q.R)), B: Math.max(...a.map(q => q.B)) });
    return { all: ext(leaves), body: ext(leaves.slice(k)), hang: k };
  });
  const { all, body } = r; const W = all.R - all.L, H = all.B - all.T;
  const pad = 0.05 * Math.max(W, H); const cx = (body.L + body.R) / 2;
  const half = Math.max(cx - all.L, all.R - cx) + pad;
  const vb = [cx - half, all.T - pad, 2 * half, H + 2 * pad].map(v => +v.toFixed(3));
  // keep the source's own viewBox as a clip, so nothing that was outside it can show
  const ov = raw[id].match(/viewBox=["']([^"']+)["']/)[1].trim().split(/[\s,]+/).map(Number);
  const inner = `<svg x="${ov[0]}" y="${ov[1]}" width="${ov[2]}" height="${ov[3]}" viewBox="${ov.join(' ')}" overflow="hidden">`
    + raw[id].replace(/^<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '') + `</svg>`;
  for (const [ink, hex] of [['white', '#ffffff'], ['black', '#000000']]) {
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="${vb.join(' ')}" width="${vb[2]}" height="${vb[3]}" fill="${hex}" color="${hex}" role="img" aria-label="${NAMES[id][1]}"><title>${NAMES[id][1]}</title>${inner}</svg>`;
    fs.writeFileSync(path.join(OUT, 'svg', `paradox-${id}-${ink}.svg`), svg);
    const long = 4096, sc = long / Math.max(vb[2], vb[3]);
    const w = Math.round(vb[2] * sc), h = Math.round(vb[3] * sc);
    const p2 = await b.newPage({ viewport: { width: Math.ceil(w / 4), height: Math.ceil(h / 4) }, deviceScaleFactor: 4 });
    await p2.setContent(`<body style="margin:0;background:transparent">${svg.replace(/ width="[^"]+" height="[^"]+"/, ` width="${w / 4}" height="${h / 4}" style="display:block"`)}</body>`);
    await p2.screenshot({ path: path.join(OUT, 'png', `paradox-${id}-${ink}.png`), omitBackground: true });
    await p2.close();
  }
  marks.push({ id, group: NAMES[id][0], name: NAMES[id][1], w: vb[2], h: vb[3], hang: r.hang });
  console.log(id, vb.join(' '), r.hang ? `(™/® hang: ${r.hang})` : '');
}
await b.close();
fs.writeFileSync(path.join(OUT, 'marks.json'), JSON.stringify(marks));
