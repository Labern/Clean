// ============================================================================
// REVIVE test suite — the contract: every claim the app makes on screen is
// measured here against a known ground truth.
//
//   node tests/run.mjs            (from restore/, or from tests/)
//
// The engine comes out of index.html itself, between the /*REVIVE-ENGINE-*/
// markers, so the browser and the suite can never drift apart.
//
// A NOTE ON METRICS. Stages that must be colour-faithful (fade recovery,
// blemish repair) are judged on RGB PSNR. The super-resolution stages are
// judged on the LUMINANCE plane, and that is not a dodge: the pipeline
// deliberately sharpens luma while carrying chroma smoothly, exactly as image
// codecs do. Measured in RGB, that correct behaviour scores badly, because the
// resampling errors of Y and of (B-Y) no longer cancel. Y is what the stage
// actually claims to improve, so Y is what it is graded on.
// ============================================================================
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { makePhoto, downscale, damage, fade, addNoise, psnr, psnrAt } from './fixtures.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const html = fs.readFileSync(path.join(here, '..', 'index.html'), 'utf8');
const block = html.match(/\/\*REVIVE-ENGINE-START\*\/[\s\S]*\/\*REVIVE-ENGINE-END\*\//);
if (!block) { console.error('FAIL: engine markers not found in index.html'); process.exit(1); }
const E = new Function(block[0] + '; return ReviveEngine;')();
const I = E._internal;

let pass = 0, fail = 0;
const ok = (name, cond, detail = '') => {
  console.log((cond ? '  ok   ' : 'FAIL   ') + name + (detail ? '  — ' + detail : ''));
  cond ? pass++ : fail++;
};
const head = s => console.log('\n\x1b[1m' + s + '\x1b[0m');
const near = (a, b, tol) => Math.abs(a - b) <= tol;

// ── fixtures, built once ────────────────────────────────────────────────────
const clean = makePhoto(640, 448);
const W = clean.width, H = clean.height;
const lo = downscale(clean, 2), lw = lo.width, lh = lo.height;
const { img: dmg, truth } = damage(lo, {});
const truthArea = truth.reduce((a, b) => a + b, 0) / truth.length;
const toY = img => {
  const n = img.width * img.height, Y = new Float32Array(n);
  for (let i = 0, p = 0; i < n; i++, p += 4)
    Y[i] = 0.2126 * I.S2L[img.data[p]] + 0.7152 * I.S2L[img.data[p + 1]] + 0.0722 * I.S2L[img.data[p + 2]];
  return Y;
};
const yPsnr = (a, b) => { let se = 0; for (let i = 0; i < a.length; i++) { const d = a[i] - b[i]; se += d * d; } return 10 * Math.log10(1 / (se / a.length)); };
const yPsnrAt = (a, b, sel) => { let se = 0, c = 0; for (let i = 0; i < a.length; i++) { if (!sel[i]) continue; const d = a[i] - b[i]; se += d * d; c++; } return 10 * Math.log10(1 / (se / c)); };

// ── 1. primitives ───────────────────────────────────────────────────────────
head('primitives');
{
  const n = 64, a = new Float32Array(n), out = new Float32Array(n);
  for (let i = 0; i < n; i++) a[i] = Math.sin(i * 0.7) * 3 + Math.cos(i * 0.21);
  let bad = 0;
  for (const rad of [1, 3, 7]) for (const isMax of [true, false]) {
    I.win1d(a, n, out, rad, isMax);
    for (let i = 0; i < n; i++) {
      let want = isMax ? -Infinity : Infinity;
      for (let j = Math.max(0, i - rad); j <= Math.min(n - 1, i + rad); j++)
        want = isMax ? Math.max(want, a[j]) : Math.min(want, a[j]);
      if (Math.abs(want - out[i]) > 1e-6) bad++;
    }
  }
  ok('sliding min/max matches brute force at every radius', bad === 0, bad + ' mismatches');
}
{
  const w = 40, h = 30, n = w * h, src = new Float32Array(n).fill(0.42);
  const dst = new Float32Array(n);
  I.boxBlur(src, dst, w, h, 3);
  let bad = 0; for (let i = 0; i < n; i++) if (Math.abs(dst[i] - 0.42) > 1e-5) bad++;
  ok('box blur preserves a constant field (edges included)', bad === 0, bad + ' pixels drifted');
}
{
  // A Gaussian must deliver the sigma it was asked for: back-projection
  // diverges if the assumed blur is wider than the real one. This caught a
  // three-box approximation that returned sigma 1.41 when asked for 0.8.
  const w = 129, h = 3, n = w * h;
  const src = new Float32Array(n); src[1 * w + 64] = 1;
  let worst = 0;
  for (const sigma of [0.6, 0.8, 1.2, 2.0]) {
    const dst = I.gauss(src, new Float32Array(n), w, h, sigma);
    let m0 = 0, m2 = 0;
    for (let x = 0; x < w; x++) { const v = dst[1 * w + x], d = x - 64; m0 += v; m2 += v * d * d; }
    const got = Math.sqrt(m2 / m0);
    worst = Math.max(worst, Math.abs(got - sigma) / sigma);
  }
  ok('gaussian delivers the sigma it was asked for', worst < 0.06, 'worst error ' + (worst * 100).toFixed(1) + '%');
}
{
  const src = new Float32Array(64 * 64).fill(0.3);
  const same = I.resample(src, 64, 64, 64, 64, 3);
  let bad = 0; for (let i = 0; i < same.length; i++) if (Math.abs(same[i] - 0.3) > 1e-6) bad++;
  const up = I.resample(src, 64, 64, 128, 128, 3);
  let bad2 = 0; for (let i = 0; i < up.length; i++) if (Math.abs(up[i] - 0.3) > 1e-4) bad2++;
  ok('lanczos weights sum to one (flat field survives resize)', bad === 0 && bad2 === 0, bad + '/' + bad2 + ' off');
}
{
  const w = 60, h = 40, n = w * h, I0 = new Float32Array(n);
  for (let i = 0; i < n; i++) I0[i] = (i % w) < 30 ? 0.2 : 0.8;   // a hard edge
  const q = I.guidedFilter(I0, I0, w, h, 4, 1e-6);
  let maxErr = 0;
  for (let y = 5; y < h - 5; y++) for (const x of [10, 45]) maxErr = Math.max(maxErr, Math.abs(q[y * w + x] - I0[y * w + x]));
  ok('guided filter leaves flat regions and hard edges alone', maxErr < 0.02, 'max drift ' + maxErr.toFixed(4));
}

// ── 2. estimators ───────────────────────────────────────────────────────────
head('estimators — what the app reads off the scan');
{
  const vals = [0, 2, 5, 10, 20].map(a => E.analyze(addNoise(lo, a)).noise);
  let mono = true; for (let i = 1; i < vals.length; i++) if (vals[i] <= vals[i - 1]) mono = false;
  ok('noise estimate rises monotonically with added noise', mono, vals.map(v => v.toFixed(4)).join(' '));
  ok('a clean scan reads as low noise', vals[0] < 0.002, vals[0].toFixed(5));
}
{
  const blurBy = (img, s) => {
    const n = img.width * img.height, out = new Uint8ClampedArray(n * 4);
    for (let c = 0; c < 3; c++) {
      const pl = new Float32Array(n);
      for (let i = 0; i < n; i++) pl[i] = img.data[i * 4 + c];
      const b = I.gauss(pl, new Float32Array(n), img.width, img.height, s);
      for (let i = 0; i < n; i++) out[i * 4 + c] = b[i];
    }
    for (let i = 0; i < n; i++) out[i * 4 + 3] = 255;
    return { width: img.width, height: img.height, data: out };
  };
  const s0 = E.analyze(lo).softness, s1 = E.analyze(blurBy(lo, 0.7)).softness, s2 = E.analyze(blurBy(lo, 1.4)).softness;
  ok('softness rises with blur', s0 < s1 && s1 < s2, [s0, s1, s2].map(v => v.toFixed(2)).join(' → '));
  ok('softness ignores contrast (a faded print is not a soft one)',
     near(E.analyze(fade(lo)).softness, s0, 0.08),
     E.analyze(fade(lo)).softness.toFixed(2) + ' vs ' + s0.toFixed(2));
  ok('softness ignores noise', near(E.analyze(addNoise(lo, 8)).softness, s0, 0.12));
}
{
  const a = E.analyze(lo), b = E.analyze(fade(lo));
  ok('fading is detected as a narrowed tonal range', b.range < a.range - 0.15,
     'clean ' + a.range.toFixed(2) + ' vs faded ' + b.range.toFixed(2));
  // Regression: dust pins pixels at pure black and white, which convinced a
  // naive percentile that a faded print already used its full range.
  const c = E.analyze(fade(damage(lo, {}).img));
  ok('dust does not spoil the fade reading', c.range < a.range,
     'faded+dusty ' + c.range.toFixed(2) + ' < clean ' + a.range.toFixed(2));
  ok('endpoints are a real measurement, not the 0–255 fallback',
     b.endpoints.l[0] > 8 && b.endpoints.l[1] < 248, JSON.stringify(b.endpoints.l));
}

// ── 3. blemish detection ────────────────────────────────────────────────────
head('blemish detection');
{
  const st = E.analyze(dmg);
  const det = I.detectDefects(toY(dmg), lw, lh, {
    len: 7, speck: 1, scratch: 0.85, k: 2.9 - 1.9 * 0.55,
    maxFrac: 0.04 + 0.16 * 0.55, sigma: Math.max(st.noise, 8e-4),
  });
  let tp = 0, fn = 0, area = 0, coreSum = 0, coreN = 0;
  for (let i = 0; i < lw * lh; i++) {
    if (det.mask[i] > 0.5) area++;
    if (truth[i]) { coreSum += det.mask[i]; coreN++; det.mask[i] > 0.5 ? tp++ : fn++; }
  }
  const recall = tp / (tp + fn);
  /* 0.78, not 0.9, and the difference is a deliberate trade rather than a
     slipped standard. Normalising the response by LOCAL contrast is what
     stops the detector flagging eyes, spectacles and the highlights in hair
     on a real photograph — see the clean-image test below, which is the one
     that matters. The cost is that damage lying on or beside a hard edge is
     no longer an outlier against its neighbourhood, so some of it is missed.
     On this fixture, whose damage sits mostly on flat synthetic fields, that
     shows up as recall. Tuning it back up to 0.9 was tried and it put the
     mask straight back onto the faces in a real scanned print. */
  ok('finds the damage (recall ≥ 0.78)', recall >= 0.78, recall.toFixed(3));
  // Regression: the mask used to be Gaussian-blurred after dilation, which
  // lowers the peak of every small blob — a dust speck came out at ~0.5 and
  // was only half repaired. Cores must stay saturated.
  ok('mask stays saturated over the damage (≥ 0.78)', coreSum / coreN >= 0.78, (coreSum / coreN).toFixed(3));
  // Generous on purpose: the mask is soft and feathered, so the flagged area
  // is always several times the true damage. The real guard is the cap below.
  ok('does not flag the whole photograph', area / (lw * lh) < 0.20,
     (area / (lw * lh) * 100).toFixed(1) + '% flagged vs ' + (truthArea * 100).toFixed(1) + '% real');
  // The cap that stops a lace collar or a bare tree reading as 40% damage.
  const wild = I.detectDefects(toY(dmg), lw, lh, {
    len: 7, speck: 1, scratch: 0.85, k: 0.001, maxFrac: 0.08, sigma: 1e-5,
  });
  let wa = 0; for (let i = 0; i < lw * lh; i++) if (wild.mask[i] > 0.5) wa++;
  ok('area cap holds even with an absurd threshold', wa / (lw * lh) < 0.22,
     (wa / (lw * lh) * 100).toFixed(1) + '%');
}

{
  /* THE test. An undamaged, detailed photograph must come back essentially
     untouched. This is the one that would have caught the worst bug in the
     project: the area cap was written as max(noiseThreshold, quantile), so
     whenever a scan was clean the quantile won and the detector flagged
     exactly maxFrac of EVERY image — and on a clean photograph the highest
     responses are not dust, they are eyes, spectacles, nostrils and the
     highlights in hair. It inpainted people's faces away, and every
     damage-based metric in this suite went UP while it did so, because the
     fixtures all had damage to find. */
  const st = E.analyze(lo);
  const det = I.detectDefects(toY(lo), lw, lh, {
    len: 7, speck: 1, scratch: 0.85, k: 2.9 - 1.9 * 0.55,
    maxFrac: 0.04 + 0.16 * 0.55, sigma: Math.max(st.noise, 8e-4),
  });
  let area = 0;
  for (let i = 0; i < lw * lh; i++) if (det.mask[i] > 0.5) area++;
  ok('a CLEAN photograph is left alone (< 1.5% flagged)', area / (lw * lh) < 0.015,
     (area / (lw * lh) * 100).toFixed(2) + '% flagged on undamaged input');
  // denoise off: smoothing is a deliberate lossy choice, not damage. What is
  // under test is whether the REPAIR stage leaves a clean photograph alone.
  const r = E.restoreSync(lo, { scale: 1, sharpen: 0, contrast: 0, grain: 0, exposure: 0, fade: 0, denoise: 0 });
  /* 31 dB, on a fixture built from hard-edged rectangles — the worst case
     there is for a morphological detector, since a corner is locally both
     thin and high-contrast. The residual 0.68% it still flags here is window
     corners. On a real scanned print the equivalent check is qualitative and
     was done by eye: faces, spectacles and hair must come through untouched. */
  ok('...and survives the full pipeline intact (≥ 31 dB)', psnr(r.data, lo.data) >= 31,
     psnr(r.data, lo.data).toFixed(1) + ' dB vs its own input');
}

// ── 4. repair ───────────────────────────────────────────────────────────────
head('repair');
{
  const Yc = toY(lo), Yd = toY(dmg);
  const before = yPsnrAt(Yd, Yc, truth);
  const r = E.restoreSync(dmg, { repair: 0.55, denoise: 0.2, fade: 0, sharpen: 0, contrast: 0, grain: 0, scale: 1 });
  const after = yPsnrAt(toY(r), Yc, truth);
  ok('damaged pixels come back (≥ +10 dB where the blemishes were)', after - before >= 10,
     before.toFixed(1) + ' dB → ' + after.toFixed(1) + ' dB');
  ok('the rest of the photograph is not harmed', psnr(r.data, lo.data) > psnr(dmg.data, lo.data),
     psnr(dmg.data, lo.data).toFixed(1) + ' → ' + psnr(r.data, lo.data).toFixed(1) + ' dB overall');
  // Feeding the inpainter a perfect mask shows its ceiling — if this drops,
  // the filling itself regressed rather than the detector.
  const tm = new Float32Array(lw * lh); for (let i = 0; i < truth.length; i++) tm[i] = truth[i];
  const ideal = yPsnrAt(I.inpaint(Yd, tm, lw, lh, null, 4), Yc, truth);
  ok('inpainting ceiling with a perfect mask ≥ 28 dB', ideal >= 28, ideal.toFixed(1) + ' dB');
}

// ── 5. resolution ───────────────────────────────────────────────────────────
head('resolution (luminance — see the note at the top)');
{
  const Yc = toY(clean), Yl = toY(lo);
  const base = I.resample(Yl, lw, lh, W, H, 3);
  const bpSharp = Float32Array.from(base);
  I.backProject(bpSharp, W, H, Yl, lw, lh, 6, 0.8, Math.max(0.15, E.analyze(lo).softness - 0.1));
  ok('back-projection does not damage an already-crisp scan',
     yPsnr(bpSharp, Yc) >= yPsnr(base, Yc) - 0.05,
     yPsnr(base, Yc).toFixed(2) + ' → ' + yPsnr(bpSharp, Yc).toFixed(2) + ' dB');

  // The case the app actually exists for: a soft scan of an old print.
  const soft = I.decimate(I.gauss(Yc, new Float32Array(W * H), W, H, 1.1), W, H, lw, lh);
  const softBase = I.resample(soft, lw, lh, W, H, 3);
  const softBp = Float32Array.from(softBase);
  I.backProject(softBp, W, H, soft, lw, lh, 8, 0.8, 0.9);
  ok('back-projection recovers real detail from a soft scan (≥ +1 dB)',
     yPsnr(softBp, Yc) - yPsnr(softBase, Yc) >= 1.0,
     yPsnr(softBase, Yc).toFixed(2) + ' → ' + yPsnr(softBp, Yc).toFixed(2) + ' dB');
}

// ── 6. the whole pipeline ───────────────────────────────────────────────────
head('the whole pipeline, on a scan that is faded, dusty, scratched and noisy');
{
  const degraded = addNoise(fade(dmg), 5);
  const st = E.analyze(degraded);
  const auto = E.autoSettings(st);
  const out = E.restoreSync(degraded, Object.assign({}, auto, { scale: 2 }));
  // a true do-nothing baseline: every stage off, including exposure
  const naive = E.restoreSync(degraded, { repair: 0, denoise: 0, fade: 0, exposure: 0, sharpen: 0, contrast: 0, grain: 0, scale: 2, backProject: 0 });
  const gain = psnr(out.data, clean.data) - psnr(naive.data, clean.data);
  ok('beats plain upscaling by ≥ 1.5 dB', gain >= 1.5,
     psnr(naive.data, clean.data).toFixed(2) + ' → ' + psnr(out.data, clean.data).toFixed(2) + ' dB  (+' + gain.toFixed(2) + ')');
  ok('output is the size it promised', out.width === W && out.height === H, out.width + '×' + out.height);
  let bad = 0; for (const v of out.data) if (!Number.isFinite(v)) bad++;
  ok('no non-finite pixels', bad === 0, bad + ' bad');
  const again = E.restoreSync(degraded, Object.assign({}, auto, { scale: 2 }));
  let diff = 0; for (let i = 0; i < out.data.length; i++) if (out.data[i] !== again.data[i]) diff++;
  ok('deterministic — same photo, same settings, identical bytes', diff === 0, diff + ' bytes differ');
  ok('auto settings react to the damage', auto.fade > 0.4 && auto.repair > 0,
     'fade ' + auto.fade.toFixed(2) + ', denoise ' + auto.denoise.toFixed(2) + ', sharpen ' + auto.sharpen.toFixed(2));
}

// ── 7. things users will actually do ────────────────────────────────────────
head('edge cases');
{
  const mk = (w, h, f) => {
    const d = new Uint8ClampedArray(w * h * 4);
    for (let i = 0; i < w * h; i++) { const [r, g, b, a] = f(i % w, (i / w) | 0); d[i * 4] = r; d[i * 4 + 1] = g; d[i * 4 + 2] = b; d[i * 4 + 3] = a; }
    return { width: w, height: h, data: d };
  };
  for (const [w, h] of [[1, 1], [2, 2], [1, 64], [64, 1], [7, 5]]) {
    let err = null, r = null;
    try { r = E.restoreSync(mk(w, h, (x, y) => [x * 9 % 255, y * 7 % 255, 120, 255]), { scale: 2 }); }
    catch (e) { err = e; }
    ok(`survives a ${w}×${h} image`, !err && r && r.data.length === r.width * r.height * 4,
       err ? err.message : r.width + '×' + r.height);
  }
  const mono = mk(80, 60, (x, y) => { const v = (x * 3 + y) % 255; return [v, v, v, 255]; });
  const ms = E.analyze(mono);
  ok('a black-and-white scan is recognised as monochrome', ms.monochrome, 'chroma ' + ms.chroma.toFixed(1));
  const mr = E.restoreSync(mono, { scale: 2 });
  let drift = 0;
  for (let i = 0; i < mr.width * mr.height; i++)
    drift = Math.max(drift, Math.abs(mr.data[i * 4] - mr.data[i * 4 + 1]), Math.abs(mr.data[i * 4 + 1] - mr.data[i * 4 + 2]));
  ok('monochrome stays neutral — no colour invented', drift <= 2, 'max channel spread ' + drift);

  const alpha = mk(40, 40, (x, y) => [200, 100, 50, x < 20 ? 0 : 255]);
  const ar = E.restoreSync(alpha, { scale: 1 });
  ok('transparency is carried through', ar.data[3] === 0 && ar.data[(39 * 40 + 39) * 4 + 3] === 255);

  const big = E.restoreSync(lo, { scale: 4, maxPixels: lw * lh * 4 });
  ok('the pixel cap reduces the enlargement instead of exhausting memory',
     big.width * big.height <= lw * lh * 4 + 4, big.width + '×' + big.height);
  const one = E.restoreSync(lo, { scale: 1 });
  ok('1× keeps the original dimensions', one.width === lw && one.height === lh);
}

console.log('\n' + (fail === 0 ? '\x1b[32m' : '\x1b[31m') + pass + ' passed, ' + fail + ' failed\x1b[0m');
process.exit(fail === 0 ? 0 : 1);
