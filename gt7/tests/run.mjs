// Data integrity for GT7 Endgame. Run: node gt7/tests/run.mjs
// Every cross-reference (track → car, car → track, step → car, grind → track)
// must resolve, every photo must exist, every lap must be ordered.
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { TRACKS, trackById } from '../data/tracks.js';
import { CARS, carById } from '../data/cars.js';
import { MAPS } from '../data/allmaps.js';
import { PHASES } from '../data/roadmap.js';
import { GRINDS } from '../data/grinds.js';
import { LESSONS } from '../data/academy.js';
import { CHAPTERS, TIMELINE } from '../data/heritage.js';
import { BASES } from '../data/wheel.js';
import { APEX, APEX_PARTS, apexUrl, apexForTrack } from '../data/apex.js';

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

console.log('beginners');
{
  const { BEGINNER } = await import('../data/beginners.js');
  ok(BEGINNER.chapters.length === 10, '10 beginner chapters');
  ok(new Set(BEGINNER.chapters.map((c) => c.id)).size === 10, 'chapter ids unique');
  BEGINNER.chapters.forEach((c) => ok(c.sections.length >= 2 && c.tips.length >= 3 && c.try, `chapter ${c.id} complete`));
  ok(BEGINNER.firstWeek.length === 7 && BEGINNER.glossary.length >= 25, 'first week + glossary');
}

console.log('accounts');
{
  const psn = await import('../app/psn-core.js');
  const fake = (routes) => async (url, opt = {}) => {
    const hit = Object.entries(routes).find(([k]) => url.includes(k));
    const body = hit ? hit[1] : null;
    return { status: body ? 200 : 404, headers: { get: (h) => (h === 'location' && body?.location) || null }, json: async () => body || {}, text: async () => JSON.stringify(body) };
  };
  const code = await psn.exchangeNpsso(fake({ '/authorize': { location: 'com.scee.psxandroid.scecompcall://redirect/?code=v3.ABC&cid=x' } }), 'x'.repeat(64));
  ok(code === 'v3.ABC', 'NPSSO → auth code parsed from the redirect');
  const sum = await psn.summary(fake({
    '/profile2': { profile: { onlineId: 'Lab3rn', avatarUrls: [{ avatarUrl: 'a.png' }], trophySummary: { level: 312 } } },
    '/users/me/trophyTitles': { trophyTitles: [{ trophyTitleName: 'Gran Turismo™ 7', npCommunicationId: 'NPWR1', npServiceName: 'trophy2', progress: 40, earnedTrophies: { gold: 2 }, definedTrophies: { gold: 9 } }] },
    '/users/me/npCommunicationIds/NPWR1': { trophies: [{ trophyId: 1, earned: true, trophyEarnedRate: '55.1' }, { trophyId: 2, earned: false, trophyEarnedRate: '33.0' }] },
    '/npCommunicationIds/NPWR1': { trophies: [{ trophyId: 1, trophyType: 'bronze', trophyName: 'International B', trophyDetail: 'Earn the International B licence' }, { trophyId: 2, trophyType: 'silver', trophyName: 'Fast', trophyDetail: 'Win a race' }] },
    '/gamelist/': { titles: [{ name: 'Gran Turismo 7', playDuration: 'PT412H30M', playCount: 300 }] },
  }), 'tok');
  ok(sum.profile?.onlineId === 'Lab3rn' && sum.profile.level === 312, 'PSN profile parsed');
  ok(sum.gt7?.trophies.length === 2 && sum.gt7.trophies[0].earned && sum.gt7.trophies[1].rate === 33, 'GT7 trophies merged with earned state and rarity');
  ok(Math.abs(sum.play?.hours - 412.5) < 1e-9, 'GT7 play time parsed');
  globalThis.window ??= {}; globalThis.localStorage ??= { getItem: () => null, setItem() {}, removeItem() {} };
  const C = await import('../app/connect.js');
  const s = { done: {}, psn: sum, gt: { DR: 'A', SR: 'S', stats: { total_credits: 12345678, license: 'IA', total_races: 40 } } };
  C.applyGT(s); C.applyPSN(s);
  ok(s.credits === 12345678 && s.creditsSource === 'gt7', 'GT7 credits replace typed credits');
  ok(s.done['lic-ib'] && s.done['lic-ia'] && !s.done['lic-s'], 'licence IA ticks IB + IA, not S');
  ok(s.done['sport-dr-b'] && s.done['sport-dr-a'] && s.done['sport-sr-s'] && s.done['sport-first'], 'DR A / SR S tick the Sport Mode steps');
  ok(C.nextTrophies(s)[0]?.name === 'Fast', 'next trophy = easiest unearned');
  const E = await import('../app/engine.js');
  const steps = E.nextSteps({ ...s, onboarded: true, owned: [], wish: [], prices: {}, focus: ['sport'], grind: { payouts: {}, minutes: {}, clean: true } }, 3);
  ok(steps.some((x) => x.kind === 'trophy'), 'trophy appears in the next moves');
  ok(!steps.some((x) => x.kind === 'connect'), 'no "connect" nag once connected');
}

console.log('telemetry protocol');
const proto = await import('../bridge/protocol.mjs');
{
  // Salsa20: eSTREAM 256-bit set 1, vector 0
  const k = Buffer.alloc(32); k[0] = 0x80;
  ok(proto.salsa20(k, Buffer.alloc(8), Buffer.alloc(64)).toString('hex').toUpperCase().startsWith('E3BE8FDD8BECA2E3EA8EF9475B29A6E7'), 'salsa20 matches the eSTREAM test vector');
  for (const type of ['A', 'B', '~']) {
    const pk = Buffer.alloc(proto.SIZE[type]);
    pk.writeUInt32LE(0x47375330, 0); pk.writeFloatLE(123.5, 0x04); pk.writeFloatLE(-50.25, 0x0C); pk.writeFloatLE(50, 0x4C);
    pk.writeInt16LE(3, 0x74); pk.writeInt32LE(83456, 0x7C); pk.writeInt16LE(1 | 8, 0x8E); pk[0x90] = 4 | (15 << 4); pk[0x91] = 255; pk[0x92] = 0; pk.writeInt32LE(3437, 0x124);
    if (pk.length >= 0x13C) pk.writeFloatLE(0.25, 0x128);
    const enc = proto.encrypt(pk, 0xC0FFEE, type);
    ok(enc.readUInt32LE(0) !== 0x47375330, `${type}: packet is actually encrypted`);
    const d = proto.decrypt(enc, type);
    ok(d, `${type}: decrypts with the right XOR`);
    const f = d && proto.parse(d);
    ok(f && Math.abs(f.v - 180) < 0.01 && f.gear === 4 && f.thr === 1 && f.lap === 3 && f.last === 83456 && f.car === 3437 && f.onTrack, `${type}: fields parse`);
    ok(f && Math.abs(f.x - 123.5) < 1e-3 && Math.abs(f.z + 50.25) < 1e-3, `${type}: position parses`);
    if (type === '~') ok(f && Math.abs(f.steer - 0.25) < 1e-6, '~: steering parses');
    ok(!proto.decrypt(enc, type === 'A' ? 'B' : 'A'), `${type}: wrong XOR is rejected`);
  }
}

console.log('beyond the apex');
{
  ok(new Set(APEX.map((a) => a.id)).size === APEX.length, 'apex ids unique');
  const parts = new Set(APEX_PARTS.map((p) => p.id));
  const lessonIds = new Set(LESSONS.map((l) => l.id));
  const widgets = new Set(['line', 'brake', 'weight', 'circle']);
  for (const a of APEX) {
    ok(parts.has(a.part), `${a.id}: part ${a.part} exists`);
    ok(/^\/[a-z_]+\/[a-z_]+\/\d\d$/.test(a.src) && apexUrl(a).startsWith('https://www.gran-turismo.com/us/gt7/apex/'), `${a.id}: official article url`);
    ok(a.idea.length >= 2 && a.points.length >= 2 && a.demos.length >= 1, `${a.id}: has idea, points, demos`);
    if (a.lesson) ok(lessonIds.has(a.lesson), `${a.id}: lesson ${a.lesson} exists`);
    if (a.widget) ok(widgets.has(a.widget), `${a.id}: widget ${a.widget} exists`);
    for (const d of a.demos) {
      const t = trackById[d.track];
      ok(t, `${a.id}: demo track ${d.track} exists`);
      ok(d.corners.length >= 1, `${a.id}/${d.track}: names at least one corner`);
      d.corners.forEach((i) => ok(t && t.corners[i], `${a.id}/${d.track}: corner index ${i} exists`));
      ok(d.title && d.watch && d.drill, `${a.id}/${d.track}: title, watch, drill`);
    }
  }
  ok(PHASES.some((p) => p.steps.some((s) => s.id === 'apex')), 'roadmap has the apex step');
  ok(apexForTrack('fuji').some(({ a }) => a.id === 'markers'), 'Fuji carries the manual\'s own braking-marker example');
}

console.log('lap alignment');
{
  globalThis.indexedDB ??= {};
  const L = await import('../app/laps.js');
  const lap = JSON.parse(fs.readFileSync(path.join(ROOT, 'data/demo-lap.json'), 'utf8'));
  const a = L.align(lap);
  ok(a && a.track.id === 'spa', 'demo lap (rotated + mirrored frame) is identified as Spa');
  ok(a && a.rms < 15, `alignment fit under 15 m (${a && a.rms.toFixed(1)} m)`);
  const back = a && a.Tinv([lap.pts[0][1], lap.pts[0][2]]);
  ok(back && Math.hypot(back[0] - a.map.pts[0][0] * a.map.mPerUnit, back[1] - a.map.pts[0][1] * a.map.mPerUnit) < 60, 'lap start maps back to near the start line');
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
