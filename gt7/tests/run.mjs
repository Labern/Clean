// Data integrity for GT7 Endgame. Run: node gt7/tests/run.mjs
// Every cross-reference (track → car, car → track, step → car, grind → track)
// must resolve, every photo must exist, every lap must be ordered.
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { TRACKS, trackById } from '../data/tracks.js';
import { CARS, carById } from '../data/cars.js';
import { MAPS } from '../data/maps.js';
import { PHASES } from '../data/roadmap.js';
import { GRINDS } from '../data/grinds.js';
import { LESSONS } from '../data/academy.js';
import { CHAPTERS, TIMELINE } from '../data/heritage.js';
import { BASES } from '../data/wheel.js';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
let pass = 0, fail = 0;
const ok = (cond, msg) => { if (cond) pass++; else { fail++; console.log('  ✗ ' + msg); } };
const sec = (t) => { const m = String(t).replace(/^~/, '').match(/^(?:(\d+):)?(\d+(?:\.\d+)?)$/); return m ? (+(m[1] || 0)) * 60 + +m[2] : NaN; };
const NO_PHOTO = new Set(['escudo']); // no usable free photo; the UI draws a placeholder

console.log('tracks');
ok(new Set(TRACKS.map((t) => t.id)).size === TRACKS.length, 'track ids unique');
for (const t of TRACKS) {
  ok(carById[t.car], `${t.id}: recommended car ${t.car} exists`);
  t.alt.forEach((c) => ok(carById[c], `${t.id}: alt car ${c} exists`));
  if (t.map) {
    ok(MAPS[t.map], `${t.id}: map ${t.map} exists`);
    if (MAPS[t.map]) ok(Math.abs(MAPS[t.map].km - t.km) / t.km < 0.03, `${t.id}: map length ${MAPS[t.map].km} within 3% of ${t.km}`);
  }
  ok(t.sectors[0].from === 0 && t.sectors.at(-1).to === 1, `${t.id}: sectors span 0..1`);
  t.sectors.forEach((s, i) => i && ok(s.from === t.sectors[i - 1].to, `${t.id}: sector ${i + 1} contiguous`));
  ok(t.corners.length >= 3, `${t.id}: at least 3 corners`);
  t.corners.forEach((c, i) => {
    ok(c.at >= 0 && c.at < 1, `${t.id} ${c.n}: at in [0,1)`);
    if (i) ok(c.at > t.corners[i - 1].at, `${t.id} ${c.n}: corners in lap order`);
    ok(c.line && c.mistake && c.brake && c.gear != null, `${t.id} ${c.n}: has line, mistake, brake, gear`);
  });
  ok(t.corners.some((c) => c.key), `${t.id}: has a key corner`);
  for (const [k, v] of Object.entries(t.laps)) {
    const s = v.map(sec);
    ok(s.every((x) => !Number.isNaN(x)), `${t.id} ${k}: lap times parse`);
    ok(s[0] < s[1] && s[1] < s[2], `${t.id} ${k}: alien < fast < solid`);
  }
}

console.log('cars');
ok(new Set(CARS.map((c) => c.id)).size === CARS.length, 'car ids unique');
for (const c of CARS) {
  ok(['race', 'hyper', 'legend', 'heritage'].includes(c.tier), `${c.id}: tier valid`);
  ok(typeof c.price === 'number' && c.price > 0, `${c.id}: price`);
  c.bestAt.forEach((t) => ok(trackById[t], `${c.id}: bestAt ${t} exists`));
  if (!NO_PHOTO.has(c.id)) ok(fs.existsSync(path.join(ROOT, 'img/cars', c.id + '.jpg')), `${c.id}: photo exists`);
}

console.log('roadmap, grinds, academy, heritage, wheel');
const steps = PHASES.flatMap((p) => p.steps);
ok(new Set(steps.map((s) => s.id)).size === steps.length, 'step ids unique');
steps.forEach((s) => s.car && ok(carById[s.car], `step ${s.id}: car ${s.car} exists`));
GRINDS.forEach((g) => { g.track && ok(trackById[g.track], `grind ${g.id}: track exists`); ok(carById[g.car], `grind ${g.id}: car exists`); });
ok(new Set(LESSONS.map((l) => l.id)).size === LESSONS.length, 'lesson ids unique');
LESSONS.forEach((l) => ok(!l.widget || ['line', 'brake', 'weight', 'circle'].includes(l.widget), `lesson ${l.id}: widget known`));
CHAPTERS.forEach((ch) => (ch.cars || []).forEach((id) => ok(carById[id], `chapter ${ch.id}: car ${id} exists`)));
ok(TIMELINE.every((e, i) => !i || e.year >= TIMELINE[i - 1].year), 'timeline in order');
ok(BASES.length >= 4, 'wheel bases listed');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
