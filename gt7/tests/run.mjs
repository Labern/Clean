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
import { VIDEOS, VIDEO_KINDS } from '../data/videos.js';
import { SCENARIOS, runScenario } from '../app/scenarios.js';
import { SYSTEMS } from '../data/systems.js';
import { REFLAPS } from '../data/reflaps.js';
import * as P2 from '../app/gt7proto.js';
import { parseChapters, cornerMoments } from '../app/ytchapters.js';

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

console.log('videos');
{
  const kinds = new Set(VIDEO_KINDS.map(([k]) => k));
  for (const t of TRACKS) {
    const v = VIDEOS[t.id] || [];
    ok(v.length >= 8, `${t.id}: at least 8 videos (${v.length})`);
    ok(v.some((x) => x.kind === 'guide'), `${t.id}: has a track guide video`);
    ok(new Set(v.map((x) => x.id)).size === v.length, `${t.id}: videos deduped`);
    v.forEach((x) => ok(/^[\w-]{11}$/.test(x.id) && kinds.has(x.kind) && x.title, `${t.id}: video ${x.id} well-formed`));
  }
}

console.log('input simulator');
{
  for (const l of LESSONS) ok(SCENARIOS[l.id], `lesson ${l.id} has a simulator scenario`);
  for (const [id, sc] of Object.entries(SCENARIOS)) {
    const runs = runScenario(id);
    ok(runs.length === sc.variants.length && runs.length >= 2, `${id}: every variant simulates`);
    for (const { v, o } of runs) {
      let bad = 0, back = 0;
      for (let i = 0; i < o.N; i++) { if (![o.v[i], o.t[i], o.steer[i], o.thr[i], o.brk[i], o.fl[i]].every(Number.isFinite)) bad++; if (i && o.t[i] < o.t[i - 1]) back++; }
      ok(!bad, `${id}/${v.id}: no NaN in the run`);
      ok(!back, `${id}/${v.id}: time only moves forward`);
      ok(o.thr.every((x, i) => x >= 0 && x <= 1.0001 && !(x > 0.02 && o.brk[i] > 0.05)), `${id}/${v.id}: pedals in range, never both pressed`);
      ok(o.marks.length >= 2, `${id}/${v.id}: has turn-in/apex markers`);
    }
  }
  // the physics should agree with the lessons
  const T = (id, k) => { const o = runScenario(id)[k].o; return o.t[o.N - 1]; };
  ok(T('trail', 0) < T('trail', 1), 'trail braking beats brake-then-turn');
  ok(T('braking', 0) < T('braking', 1), 'the expert out-brakes the beginner');
  ok(T('wet', 0) < T('wet', 1), 'the wet is slower');
  ok(T('throttle', 0) < T('throttle', 1), 'progressive throttle beats a stab');
  ok(T('priority', 0) < T('priority', 1), 'exit-first wins before a long straight');
  const geo = runScenario('line')[1].o, ap = geo.marks.find((m) => m[1] === 'Apex')[0];
  let iPk = 0; for (let i = 0; i < geo.N; i++) if (Math.abs(geo.steer[i]) > Math.abs(geo.steer[iPk])) iPk = i;
  ok(Math.abs(geo.st[iPk] - ap) < 6, `geometric line: peak lock at the apex (${geo.st[iPk].toFixed(0)} vs ${ap.toFixed(0)} m)`);
}

console.log('race systems');
{
  const ids = new Set(SYSTEMS.map((x) => x.id));
  ok(ids.size === SYSTEMS.length && SYSTEMS.length >= 12, 'systems ids unique');
  for (const x of SYSTEMS) {
    ok(x.what.length >= 2 && x.how.length >= 3 && x.tips.length >= 2 && x.mistakes.length >= 2, `${x.id}: substantive`);
    (x.related || []).forEach((r) => ok(ids.has(r), `${x.id}: related ${r} exists`));
    ok(!/—/.test(JSON.stringify(x)), `${x.id}: no em dashes`);
  }
}

console.log('reference laps + track studio');
{
  for (const t of TRACKS) {
    const r = REFLAPS[t.id];
    ok(r, `${t.id}: has a reference lap`);
    if (!r) continue;
    ok(r.v.length === 500 && r.v.every((v) => v > 20 && v < 340), `${t.id}: speed trace sane`);
    ok(r.corners.length === t.corners.length, `${t.id}: reference stats for every corner`);
    r.corners.forEach((c, i) => ok(c.gear >= 1 && c.gear <= 6 && c.min > 20 && c.min <= c.entry + 1, `${t.id} corner ${i}: gear/min/entry consistent`));
    if (r.bench && t.country !== 'GT original') ok(Math.abs(r.lap / r.bench - 1) < 0.1, `${t.id}: reference lap within 10% of the Gr.3 benchmark (${r.lap}s vs ${r.bench}s)`);
  }
  const ch = parseChapters('Intro\n0:00 Intro\n1:12 Turn 1 La Source\n(2:05) - Eau Rouge / Raidillon\n10:01 Outro');
  ok(ch.length === 4 && ch[1][0] === 72 && ch[2][0] === 125, 'chapter timestamps parse');
  const m = cornerMoments(trackById.spa.corners[1], [{ id: 'x', channel: 'c' }], { x: { ch } });
  ok(m.length === 1 && m[0].sec === 125, 'chapters match corners by name');
}

console.log('direct telemetry (on-device protocol)');
{
  const proto = await import('../bridge/protocol.mjs');
  for (const type of ['A', 'B', '~']) {
    const plain = Buffer.alloc(proto.SIZE[type]); plain.writeUInt32LE(0x47375330, 0);
    for (let i = 4; i < plain.length; i++) plain[i] = (i * 37 + 11) & 255;
    plain.writeUInt32LE(0x47375330, 0);
    const a = proto.encrypt(Buffer.from(plain), 0xBEEF1234, type), b = P2.encrypt(new Uint8Array(plain), 0xBEEF1234, type);
    ok(Buffer.compare(a, Buffer.from(b)) === 0, `${type}: phone encryption matches the bridge byte for byte`);
    const d1 = proto.decrypt(a, type), d2 = P2.decrypt(new Uint8Array(a), type);
    ok(d1 && d2 && Buffer.compare(d1, Buffer.from(d2)) === 0, `${type}: phone decryption matches the bridge`);
    if (type === '~') { const f1 = proto.parse(d1), f2 = P2.parse(d2); ok(JSON.stringify(f1) === JSON.stringify(f2), '~: phone parser matches the bridge field for field'); }
  }
  // recorder: a lap closes on the counter tick and takes GT7's official time
  let saved = null; const rec = P2.createRecorder({ onLap: (l) => { saved = l; } });
  const base = { x: 0, y: 0, z: 0, v: 100, rpm: 5000, thr: 1, brk: 0, gear: 3, steer: 0, onTrack: true, paused: false, loading: false, car: 42, best: -1, last: -1 };
  const realNow = Date.now; let clock = 1e12; Date.now = () => clock;
  for (let i = 0; i < 400; i++) { clock += 16; rec({ ...base, lap: 1, x: i }); }
  for (let i = 0; i < 40; i++) { clock += 16; rec({ ...base, lap: 2, last: i > 25 ? 83456 : -1 }); }
  Date.now = realNow;
  ok(saved && saved.lap === 1 && saved.time === 83456 && saved.timeSource === 'gt7' && saved.pts.length > 100, 'recorder closes the lap with GT7\'s official time');
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

console.log('sector trainer (runs, compare, filing)');
{
  const { CE: INFO } = await import('../data/ce.js');
  for (const [tid, x] of Object.entries(INFO)) {
    ok(trackById[tid], `ce ${tid}: track exists`);
    ok(x.sections >= 4 && x.car && x.prize.gold > x.prize.bronze, `ce ${tid}: sections, car, prizes`);
  }
  // recorder: a run closes when GT7 teleports the car back to the start
  const runs = []; const rec = P2.createRecorder({ onRun: (r) => runs.push(r) });
  const base = { y: 0, rpm: 5000, thr: 1, brk: 0, gear: 3, steer: 0, onTrack: true, paused: false, loading: false, car: 7, best: -1, last: -1, lap: 0 };
  const realNow = Date.now; let clock = 2e12; Date.now = () => clock;
  for (let k = 0; k < 2; k++) for (let i = 0; i < 600; i++) { clock += 16; rec({ ...base, x: i * 0.8, z: 0, v: 160 }); }   // drive 480 m, reset, drive again
  rec.flush(); Date.now = realNow;
  ok(runs.length === 2, `recorder splits runs at the reset (${runs.length})`);
  ok(runs[0] && Math.abs(runs[0].dist - 479) < 5 && runs[0].cols.includes('d') && runs[0].start[0] < 5, 'run has distance, start point and cumulative-distance column');
  ok(runs[0] && Math.abs(runs[0].time - 9584) < 100, `run time measured (${runs[0]?.time} ms)`);

  const { compare } = await import('../app/compare.js');
  const { sampleSession } = await import('../app/cesample.js');
  const lap = JSON.parse(fs.readFileSync(path.join(ROOT, 'data/demo-lap.json'), 'utf8'));
  const { demo, attempts } = sampleSession(lap, 1e12);
  const self = compare(demo, demo);
  ok(Math.abs(self.total) < 1e-6 && self.ranked.every((c) => !c.tips.length), 'a run against itself: zero gap, no tips');
  const { autoGates } = await import('../app/ce.js'), [g0, g1] = autoGates(demo);
  const a0 = compare(attempts[0], demo, { from: g0, to: g1 });
  ok(a0.ranked[0].brake <= -24 && a0.ranked[0].brake >= -36, `30 m early braking is found at the right corner (${a0.ranked[0].brake} m)`);
  ok(a0.total > 0.05 && a0.complete, `early braking costs time (${a0.total.toFixed(3)} s)`);
  const a1 = compare(attempts[1], demo), c1 = a1.ranked[0];
  ok(Math.abs(Math.abs(c1.line) - 2.2) < 0.4 && c1.tips.some((t) => /of the demo's line/.test(t)), `running 2.2 m wide is measured (${c1.line} m)`);
  const a2 = compare(attempts[2], demo);
  ok(a2.corners.some((c) => c.brake >= 18 && c.brake <= 34), 'overshooting: the late braking point is found');
  ok(Math.abs(a0.minis.reduce((s, m) => s + m.lost, 0) - a0.total) < 0.01, 'mini-sectors add up to the total gap');

  const CE = await import('../app/ce.js');
  const db = new Map([demo, ...attempts].map((r) => [r.id, r])), get = async (id) => db.get(id);
  CE.setActive('spa', 3); CE.setMedals('spa', 3, { gold: 39800, silver: 40000, bronze: 41000 });
  ok(CE.match(demo)?.role === 'first', 'first run in an empty section becomes the demo');
  const d = await CE.file(demo, get);
  ok(d.role === 'demo' && CE.sec('spa', 3).gates[1] < demo.dist - 100, `gates trim the coast after the finish (${CE.sec('spa', 3).gates[1]} of ${demo.dist} m)`);
  const res = []; for (const a of attempts) res.push(await CE.file(a, get));
  ok(res.every((r) => r.role === 'attempt' && r.entry.complete), 'attempts are matched by their start point');
  ok(res.every((r) => r.entry.ms > d.entry.ms), 'every flawed attempt is slower than the demo');
  ok(res[0].entry.top?.n === a0.ranked[0].n && /earlier/.test(res[0].entry.top.tip), 'the post-attempt fix names the corner and the braking');
  const x = CE.sec('spa', 3), best = res.reduce((b, r) => (r.entry.ms < b.entry.ms ? r : b));
  ok(x.best.id === best.entry.id && x.best.medal === CE.medal(x, best.entry.ms), 'best attempt and its medal tracked');
  const id = CE.ideal(x);
  ok(id && id.ms <= x.best.ms, `theoretical best is no slower than the best attempt (${id?.ms} vs ${x.best.ms})`);
  CE.calibrate('spa', 3, res[0].entry.id, res[0].entry.raw + 1234);
  ok(CE.sec('spa', 3).offset === 1234 && CE.sec('spa', 3).runs.every((r) => r.ms === r.raw + 1234), 'calibrating one attempt shifts every time to GT7\'s clock');
  const far = { ...attempts[0], id: 'elsewhere', start: [attempts[0].start[0] + 500, attempts[0].start[1]] };
  ok(CE.match(far) === null, 'a run that starts somewhere else is not filed');
  await CE.useAsDemo('spa', 3, attempts[3], get);
  ok(CE.sec('spa', 3).demo === attempts[3].id && CE.sec('spa', 3).runs.length === 5, 'a different demo re-measures every run');
  ok(CE.summary('spa').next && CE.parseMs('1:02.345') === 62345 && CE.fmt(62345) === '1:02.345', 'summary + time parsing');
  const { nextSteps } = await import('../app/engine.js');
  const store = await import('../app/state.js');
  ok(nextSteps(store.get(), 5).some((st) => st.kind === 'ce'), 'the section in training is a next move');
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
