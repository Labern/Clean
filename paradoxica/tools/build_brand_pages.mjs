// Gives every logo and slide on paradoxica.uk/brand/ its own real URL:
//   /brand/<id>/   and   /brand/slide-NN/
// Each is a copy of brand/index.html whose <!--meta--> block names that item (title,
// canonical, Open Graph), so the link previews properly wherever it is pasted. The page
// script reads the path and opens that item's preview. Also renders a 1200×630 share card
// per mark (brand/og/<id>.png, white on black).  Run after build_brand.mjs:
//   node paradoxica/tools/build_brand_pages.mjs
import fs from 'node:fs'; import path from 'node:path'; import { createRequire } from 'node:module';
const require = createRequire(import.meta.url); const { chromium } = require('playwright');
const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
const B = path.join(ROOT, 'paradoxica/site/brand'), O = 'https://paradoxica.uk';
const tpl = fs.readFileSync(path.join(B, 'index.html'), 'utf8');
const marks = JSON.parse(fs.readFileSync(path.join(B, 'marks.json'), 'utf8'));
const esc = s => s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
const deckGround = n => n <= 12 ? 'Black' : n <= 23 ? 'White' : n <= 25 ? 'Lavender' : n <= 36 ? 'Purple' : 'Deep purple';

const items = [
  ...marks.map(m => ({ slug: m.id, title: `${m.name} · ★★★★★ × PARADOX`,
    desc: `${m.group} mark. Vector SVG and 4096 px PNG, white or black ink.`, image: `${O}/brand/og/${m.id}.png` })),
  ...Array.from({ length: 47 }, (_, i) => { const n = String(i + 1).padStart(2, '0');
    return { slug: `slide-${n}`, title: `Slide ${n} · ${deckGround(i + 1)} · ★★★★★ × PARADOX`,
      desc: 'From the Logo Variations deck. Vector SVG and 3840 × 2160 PNG.', image: `${O}/logos/png/logo-${n}.png` }; }),
];

// clear old item folders (keep svg/ png/ og/)
for (const d of fs.readdirSync(B)) if (/^(slide-\d\d|[a-z0-9-]+)$/.test(d) && !['svg', 'png', 'og'].includes(d)
  && fs.statSync(path.join(B, d)).isDirectory()) fs.rmSync(path.join(B, d), { recursive: true });

for (const it of items) {
  const url = `${O}/brand/${it.slug}/`;
  const meta = `<!--meta-->
<title>${esc(it.title)}</title>
<meta name="description" content="${esc(it.desc)}">
<link rel="canonical" href="${url}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="★★★★★ × PARADOX">
<meta property="og:title" content="${esc(it.title)}">
<meta property="og:description" content="${esc(it.desc)}">
<meta property="og:url" content="${url}">
<meta property="og:image" content="${it.image}">
<meta name="twitter:card" content="summary_large_image">
<!--/meta-->`;
  const html = tpl.replace(/<!--meta-->[\s\S]*?<!--\/meta-->/, meta);
  if (html === tpl) throw new Error('meta block missing from brand/index.html');
  fs.mkdirSync(path.join(B, it.slug), { recursive: true });
  fs.writeFileSync(path.join(B, it.slug, 'index.html'), html);
}

// share cards for the marks
fs.mkdirSync(path.join(B, 'og'), { recursive: true });
const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1200, height: 630 } });
for (const m of marks) {
  const svg = fs.readFileSync(path.join(B, 'svg', `paradox-${m.id}-white.svg`), 'utf8')
    .replace(/ width="[^"]+" height="[^"]+"/, ' style="max-width:880px;max-height:470px;width:auto;height:auto;display:block"');
  await p.setContent(`<body style="margin:0;width:1200px;height:630px;background:#000;display:flex;align-items:center;justify-content:center">${svg}</body>`);
  await p.screenshot({ path: path.join(B, 'og', `${m.id}.png`) });
}
await b.close();
console.log(`${items.length} pages, ${marks.length} share cards`);
