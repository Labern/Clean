// Vendor one photo per car from its Wikipedia lead image (Wikimedia Commons).
//   node gt7/tools/fetch_images.mjs [id ...]
// Writes img/cars/<id>.jpg and data/credits.json (file page + licence trail).
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { CARS } from '../data/cars.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(HERE, '..', 'img', 'cars');
const CREDITS = path.join(HERE, '..', 'data', 'credits.json');
const UA = 'GT7Companion/1.0 (https://labern.github.io/Clean/gt7/)';
const W = 960;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function get(url, kind = 'json') {
  for (let i = 0; i < 6; i++) {
    const res = await fetch(url, { headers: { 'User-Agent': UA } });
    if (res.status === 429 || res.status >= 500) { await sleep(2000 * 2 ** i); continue; }
    if (!res.ok) return null;
    return kind === 'json' ? res.json() : Buffer.from(await res.arrayBuffer());
  }
  return null;
}

const credits = fs.existsSync(CREDITS) ? JSON.parse(fs.readFileSync(CREDITS, 'utf8')) : {};
fs.mkdirSync(OUT, { recursive: true });
const want = process.argv.slice(2);
for (const car of CARS) {
  if (want.length && !want.includes(car.id)) continue;
  const dest = path.join(OUT, `${car.id}.jpg`);
  if (!want.length && fs.existsSync(dest)) continue;
  let done = false;
  for (const title of car.wiki) {
    const s = await get(`https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(title.replace(/ /g, '_'))}`);
    await sleep(1200);
    if (!s || !s.originalimage || s.type === 'disambiguation') continue;
    const orig = s.originalimage;
    let url = orig.source.split('?')[0];
    if (/\.svg$/i.test(url)) continue;
    if (orig.width > W) {
      // .../commons/a/ab/File.jpg -> .../commons/thumb/a/ab/File.jpg/960px-File.jpg
      const m = url.match(/^(https:\/\/[^/]+\/wikipedia\/[^/]+)\/(?:thumb\/)?([0-9a-f]\/[0-9a-f]{2})\/([^/]+)/);
      if (m) url = `https://thumb.wikimedia.org/wikipedia/commons/thumb/${m[2]}/${m[3]}/${W}px-${m[3]}`;
    } else {
      url = url.replace('upload.wikimedia.org', 'thumb.wikimedia.org');
    }
    const buf = await get(url, 'bin');
    await sleep(1200);
    if (!buf || buf.length < 5000) { console.log(`  ${car.id}: image fetch failed ${url}`); continue; }
    fs.writeFileSync(dest, buf);
    const file = decodeURIComponent(orig.source.split('?')[0].split('/').pop());
    credits[car.id] = { article: s.title, file: `File:${file}`, page: `https://commons.wikimedia.org/wiki/File:${encodeURIComponent(file)}` };
    console.log(`${car.id}: ${s.title} -> ${(buf.length / 1024) | 0} KB`);
    done = true;
    break;
  }
  if (!done) console.log(`${car.id}: NO IMAGE (${car.wiki.join(' | ')})`);
}
fs.writeFileSync(CREDITS, JSON.stringify(credits, null, 1));
