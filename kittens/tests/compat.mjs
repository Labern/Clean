// node kittens/tests/compat.mjs — the "nothing is ever lost between versions" contract.
// Runs the real merge code from v1 (kittens/index.html) AND the shared core
// (kittens/shared/core.js) through every way an older version can meet newer data.
import fs from 'fs'; import path from 'path'; import { fileURLToPath } from 'url';
const dir = path.dirname(fileURLToPath(import.meta.url)), root = path.join(dir, '..');
const grab = (src, name) => { const i = src.indexOf('function ' + name + '('); let d = 0, j = src.indexOf('{', i);
  for (; j < src.length; j++) { if (src[j] === '{') d++; else if (src[j] === '}' && --d === 0) break; } return src.slice(i, j + 1); };
const strip = f => f.replace(/\/\/.*$/gm, '').replace(/\s+/g, ' ').trim();
const COLS = ['kittens', 'weights', 'events', 'foods', 'todos', 'shop', 'cams', 'care', 'photos', 'meta', 'msgs', 'costs', 'health', 'skills'];
const impls = {};
for (const [name, file] of [['v1', 'index.html'], ['core', 'shared/core.js']]) {
  const src = fs.readFileSync(path.join(root, file), 'utf8');
  impls[name] = { src: strip(grab(src, 'merge')) + strip(grab(src, 'mergeRec')), fn: new Function('COLS', grab(src, 'mergeRec') + '\n' + grab(src, 'merge') + '\nreturn merge;')(COLS) };
}
let pass = 0, fail = 0; const ok = (c, msg) => { if (c) pass++; else { fail++; console.log('  ✗ ' + msg); } };
ok(impls.v1.src === impls.core.src, 'v1 and shared/core.js merge code are identical (they must not drift)');
for (const [name, { fn: merge }] of Object.entries(impls)) {
  console.log(name);
  // 1. collections an older version doesn't know survive, either side
  let r = merge({ weights: {} }, { bond: { b1: { text: 'x', u: 5 } } }).out; ok(r.bond && r.bond.b1.text === 'x', 'unknown collection from remote kept');
  r = merge({ bond: { b1: { text: 'x', u: 5 } } }, { weights: {} }).out; ok(r.bond && r.bond.b1.text === 'x', 'unknown collection from local kept');
  r = merge({ v3settings: { a: { u: 1, z: 1 } } }, {}).out; ok(r.v3settings.a.z === 1, 'any future collection kept');
  // 2. fields a newer version appended survive an older version's newer edit — both directions
  const newRec = { k: 'penpen', g: 900, date: '2026-10-10', note: 'from weight app', photo: 'p1', guess: { lemon: 880 }, u: 10 };
  const oldEdit = { k: 'penpen', g: 905, date: '2026-10-10', u: 20 };            // stale older version, never saw note/photo
  r = merge({ weights: { w: newRec } }, { weights: { w: oldEdit } }).out.weights.w;
  ok(r.g === 905 && r.note === 'from weight app' && r.photo === 'p1' && r.guess.lemon === 880, 'remote older-version edit keeps appended fields');
  r = merge({ weights: { w: oldEdit } }, { weights: { w: newRec } });
  ok(r.out.weights.w.g === 905 && r.out.weights.w.note === 'from weight app', 'local older-version edit keeps remote appended fields');
  ok(r.changedA === true, 'pulling missing fields counts as a change (so it gets saved + republished)');
  // 3. deletes are whole, revives start clean
  r = merge({ weights: { w: newRec } }, { weights: { w: { del: true, u: 30 } } }).out.weights.w; ok(r.del === true && !r.note, 'newer delete wins whole');
  r = merge({ weights: { w: { del: true, u: 30 } } }, { weights: { w: { g: 1, u: 40 } } }).out.weights.w; ok(!r.del && r.g === 1, 'revive after delete is a live record');
  r = merge({ weights: { w: { del: true, u: 50 } } }, { weights: { w: newRec } }).out.weights.w; ok(r.del === true, 'older live copy cannot resurrect a newer delete');
  // 3b. a delete keeps the content inside the tombstone (the bin), through any merge
  const tomb = { del: true, u: 70, was: Object.assign({}, newRec) };
  r = merge({ weights: { w: newRec } }, { weights: { w: tomb } }).out.weights.w; ok(r.del && r.was && r.was.note === 'from weight app' && r.was.photo === 'p1', 'deleted record content survives in the bin');
  r = merge({ weights: { w: tomb } }, { weights: { w: newRec } }).out.weights.w; ok(r.del && r.was && r.was.g === 900, 'bin survives an older live copy arriving');
  // 4. explicit blanking (how a version removes a field) still works
  r = merge({ weights: { w: newRec } }, { weights: { w: Object.assign({}, newRec, { photo: null, u: 60 }) } }).out.weights.w; ok(r.photo === null && r.note === 'from weight app', 'explicit null clears a field');
  // 5. no-ops are no-ops
  r = merge({ weights: { w: newRec } }, { weights: { w: Object.assign({}, newRec) } }); ok(!r.changedA, 'identical records → no change');
  r = merge({ weights: { w: newRec } }, { weights: { w: { k: 'penpen', g: 1, u: 2 } } }); ok(!r.changedA && r.out.weights.w.g === 900 && r.out.weights.w.note, 'older remote can only add, never overwrite');
  // 6. nested + odd shapes
  r = merge({ meta: { rota: { Monam: 'lemon', u: 5 } } }, { meta: { rota: { Tueam: 'girl', u: 9 } } }).out.meta.rota; ok(r.Monam === 'lemon' && r.Tueam === 'girl', 'meta records union their keys');
  r = merge({ ver: 3, weights: {} }, { weights: {} }).out; ok(r.ver === 3, 'non-collection top-level values kept');
  ok(merge(null, { weights: { w: newRec } }).out.weights.w.g === 900, 'merging into nothing works');
}
console.log(`\n${pass} passed, ${fail} failed`); process.exit(fail ? 1 : 0);
