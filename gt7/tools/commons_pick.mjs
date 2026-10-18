// Commons search helper for cars whose Wikipedia lead image is the wrong variant.
//   node tools/commons_pick.mjs list  <sheet.html>    -> candidate contact sheet for PICKS
//   node tools/commons_pick.mjs fetch id=N ...         -> download candidate N for id at 960px
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
const HERE = path.dirname(fileURLToPath(import.meta.url));
const UA = 'GT7Companion/1.0 (https://labern.github.io/Clean/gt7/)';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
export const PICKS = {
  amggt3: 'Mercedes-AMG GT3 race car', caymangt4: 'Porsche Cayman GT4 Clubsport',
  escudo: 'Suzuki Escudo Pikes Peak Tajima', evo: 'Mitsubishi Lancer Evolution VI',
  f296gt3: 'Ferrari 296 GT3', gt3r992: 'Porsche 911 GT3 R 992', hakosuka: 'Nissan Skyline 2000GT-R KPGC10',
  huracangt3: 'Lamborghini Huracan GT3 Evo', impreza22b: 'Subaru Impreza 22B', r32: 'Nissan Skyline GT-R R32',
  r33: 'Nissan Skyline GT-R R33', r92cp: 'Nissan R92CP', supraa80: 'Toyota Supra JZA80',
  supragr4: 'Toyota GR Supra GT4', p4: 'Ferrari 330 P4', r34: 'Nissan Skyline GT-R R34 V-Spec',
};
async function search(q) {
  const u = `https://commons.wikimedia.org/w/api.php?action=query&format=json&generator=search&gsrnamespace=6&gsrlimit=10&gsrsearch=${encodeURIComponent(q + ' filetype:bitmap')}&prop=imageinfo&iiprop=url|size&iiurlwidth=960`;
  for (let i = 0; i < 5; i++) {
    const r = await fetch(u, { headers: { 'User-Agent': UA } });
    if (r.ok) { const d = await r.json(); return Object.values(d.query?.pages || {}).sort((a, b) => a.index - b.index); }
    await sleep(2000 * 2 ** i);
  }
  return [];
}
const [cmd, ...rest] = process.argv.slice(2);
const cache = path.join(HERE, '.osm-cache', 'commons.json');
const db = fs.existsSync(cache) ? JSON.parse(fs.readFileSync(cache, 'utf8')) : {};
if (cmd === 'list') {
  let html = '<body style="margin:0;width:1700px;font:13px sans-serif">';
  for (const [id, q] of Object.entries(PICKS)) {
    db[id] = db[id] || (await search(q)).map((p) => ({ title: p.title, thumb: p.imageinfo[0].thumburl, w: p.imageinfo[0].width, h: p.imageinfo[0].height }));
    await sleep(800);
    html += `<div style="white-space:nowrap"><b style="display:inline-block;width:90px">${id}</b>` +
      db[id].map((c, i) => `<span style="display:inline-block;width:158px;margin:1px;vertical-align:top"><img src="${c.thumb.replace('/960px-', '/330px-')}" style="width:158px;height:95px;object-fit:cover"><br>${i}</span>`).join('') + '</div>';
  }
  fs.mkdirSync(path.dirname(cache), { recursive: true });
  fs.writeFileSync(cache, JSON.stringify(db));
  fs.writeFileSync(rest[0], html);
} else if (cmd === 'fetch') {
  const credits = JSON.parse(fs.readFileSync(path.join(HERE, '..', 'data', 'credits.json'), 'utf8'));
  for (const kv of rest) {
    const [id, n] = kv.split('=');
    const c = db[id][+n];
    const r = await fetch(c.thumb, { headers: { 'User-Agent': UA } });
    const buf = Buffer.from(await r.arrayBuffer());
    fs.writeFileSync(path.join(HERE, '..', 'img', 'cars', `${id}.jpg`), buf);
    credits[id] = { article: null, file: c.title, page: `https://commons.wikimedia.org/wiki/${encodeURIComponent(c.title.replace(/ /g, '_'))}` };
    console.log(id, c.title, (buf.length / 1024) | 0, 'KB', r.status);
    await sleep(1000);
  }
  fs.writeFileSync(path.join(HERE, '..', 'data', 'credits.json'), JSON.stringify(credits, null, 1));
}
