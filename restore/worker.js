/* ============================================================================
   REVIVE worker — every expensive stage runs here, never on the main thread.

   Restoring a 12-megapixel scan is tens of seconds of dense typed-array work.
   Run on the main thread it blocks every repaint, so the progress bar never
   moves, the spinner never spins and the tab looks frozen — indistinguishable
   from an app that does nothing at all. Here, the page stays live and the
   progress bar actually reports progress.

   Pixel buffers are passed by TRANSFER, not copy: a 12MP RGBA image is 48MB,
   and structured-cloning that twice per photograph would cost more than some
   of the filters do.
   ========================================================================== */
/* global ReviveEngine, ReviveColour, ReviveFace, ort */
importScripts('engine.js');

let ortReady = null, colourSession = null, faceSession = null, detSession = null;
let knownRot = null;   // which way up this photograph is, once we know

const post = (type, payload, transfer) => self.postMessage(Object.assign({ type }, payload), transfer || []);

function loadOrt(base) {
  if (ortReady) return ortReady;
  ortReady = (async () => {
    importScripts(base + 'ort.min.js');
    ort.env.wasm.wasmPaths = base;
    /* Threads need cross-origin isolation, which GitHub Pages cannot send. */
    ort.env.wasm.numThreads = 1;
    ort.env.logLevel = 'error';
  })();
  return ortReady;
}

async function fetchParts(paths, total, onProgress) {
  const bufs = [];
  let done = 0;
  for (const p of paths) {
    const res = await fetch(p);
    if (!res.ok) throw new Error('could not fetch ' + p + ' (' + res.status + ')');
    const reader = res.body && res.body.getReader();
    if (!reader) {
      const a = new Uint8Array(await res.arrayBuffer());
      bufs.push(a); done += a.length; onProgress(done / total);
      continue;
    }
    const chunks = [];
    let got = 0;
    for (;;) {
      const { done: d, value } = await reader.read();
      if (d) break;
      chunks.push(value); got += value.length;
      onProgress((done + got) / total);
    }
    const a = new Uint8Array(got);
    let o = 0; for (const c of chunks) { a.set(c, o); o += c.length; }
    bufs.push(a); done += got;
  }
  let size = 0; for (const b of bufs) size += b.length;
  const all = new Uint8Array(size);
  let o = 0; for (const b of bufs) { all.set(b, o); o += b.length; }
  return all;
}

/* ── restore ─────────────────────────────────────────────────────────────── */
function doRestore(msg) {
  const img = { width: msg.width, height: msg.height, data: new Uint8ClampedArray(msg.data) };
  const stats = ReviveEngine.analyze(img);
  const opts = msg.opts || ReviveEngine.autoSettings(stats);
  const it = ReviveEngine.restore(img, opts, stats);
  let step = it.next();
  while (!step.done) {
    post('progress', { stage: step.value.stage, p: step.value.p });
    step = it.next();
  }
  const r = step.value;
  return { result: r, stats, opts };
}

/* ── faces ───────────────────────────────────────────────────────────────── */
function subImage(img, sx, sy, sw, sh) {
  const d = new Uint8ClampedArray(sw * sh * 4);
  for (let y = 0; y < sh; y++) {
    const row = ((sy + y) * img.width + sx) * 4;
    d.set(img.data.subarray(row, row + sw * 4), y * sw * 4);
  }
  return { width: sw, height: sh, data: d };
}
async function runDetector(img, rot, rect) {
  const F = ReviveFace, N = F.NET;
  const input = F.detectorInput(img, rot, rect);
  const out = await detSession.run({ [detSession.inputNames[0]]: new ort.Tensor('float32', input, [1, 3, N, N]) });
  const named = {};
  for (const k of Object.keys(out)) named[k] = out[k].data;
  return F.decodeDetections(named, 0.5).map(d => F.mapDetection(d, rot, rect));
}

async function detectFaces(img) {
  const F = ReviveFace, N = F.NET;
  const whole = { x: 0, y: 0, w: img.width, h: img.height };

  /* Which way up is this photograph? YuNet only finds upright faces, and a
     sideways scan yields literally nothing — so try all four right angles on
     the whole frame first and keep whichever the detector believes most.
     Four cheap passes settle the orientation before any expensive tiling. */
  let best = { rot: 0, dets: [], score: -1 };
  for (let rot = 0; rot < 4; rot++) {
    post('progress', { stage: 'Checking orientation (' + (rot + 1) + '/4)', p: 0.10 + 0.03 * rot });
    const dets = await runDetector(img, rot, whole);
    const score = dets.reduce((s, d) => s + d.score, 0);
    if (score > best.score) best = { rot, dets, score };
  }
  const rot = best.rot;
  knownRot = rot;
  const all = best.dets.slice();

  /* Now tile, at the orientation that works, so small faces are not lost to
     the detector's fixed 640 input. */
  const TILE = Math.round(N * 1.4);
  const views = [];
  if (img.width > TILE * 1.2 || img.height > TILE * 1.2) {
    const cols = Math.max(1, Math.ceil(img.width / TILE));
    const rows = Math.max(1, Math.ceil(img.height / TILE));
    const tw = Math.min(img.width, Math.ceil(img.width / cols * 1.34));
    const th = Math.min(img.height, Math.ceil(img.height / rows * 1.34));
    for (let c = 0; c < cols; c++) for (let r = 0; r < rows; r++) {
      views.push({
        x: cols > 1 ? Math.round(c * (img.width - tw) / (cols - 1)) : 0,
        y: rows > 1 ? Math.round(r * (img.height - th) / (rows - 1)) : 0,
        w: tw, h: th,
      });
    }
  }
  for (let i = 0; i < views.length; i++) {
    post('progress', { stage: 'Looking for faces (' + (i + 1) + '/' + views.length + ')', p: 0.22 + 0.08 * (i / views.length) });
    for (const d of await runDetector(img, rot, views[i])) all.push(d);
  }
  return F.nms(all, 0.35).sort((a, b) => b.w * b.h - a.w * a.h);
}
async function doFaces(msg) {
  await loadOrt(msg.ortBase);
  if (!detSession) {
    post('progress', { stage: 'Loading the face detector', p: 0.02 });
    const d = await fetchParts([msg.detPath], msg.detSize, () => {});
    detSession = await ort.InferenceSession.create(d, { executionProviders: ['wasm'] });
  }
  if (!faceSession) {
    const bytes = await fetchParts(msg.parts, msg.totalSize,
      f => post('progress', { stage: 'Downloading the face model — ' + Math.round(f * 100) + '%', p: 0.02 + 0.06 * f }));
    post('progress', { stage: 'Starting the face model', p: 0.09 });
    faceSession = await ort.InferenceSession.create(bytes, { executionProviders: ['wasm'] });
  }
  const work = { width: msg.width, height: msg.height, data: new Uint8ClampedArray(msg.data) };
  const faces = await detectFaces(work);
  if (!faces.length) return { data: work.data, count: 0 };
  const F = ReviveFace, mask = F.faceMask(512), n512 = 512 * 512;
  const rgba = new Uint8ClampedArray(n512 * 4);
  const limit = Math.min(faces.length, 12);
  for (let i = 0; i < limit; i++) {
    post('progress', { stage: 'Restoring face ' + (i + 1) + ' of ' + limit, p: 0.3 + 0.68 * (i / limit) });
    const f = faces[i];
    const M = F.similarity(f.pts, F.TPL);
    if (!M) continue;
    const x = F.cropAligned(work, M, 512);
    if (!x) continue;
    const out = await faceSession.run({ [faceSession.inputNames[0]]: new ort.Tensor('float32', x, [1, 3, 512, 512]) });
    const y = out[faceSession.outputNames[0]].data;
    for (let p = 0; p < n512; p++) {
      rgba[p * 4] = (y[p] + 1) * 127.5;
      rgba[p * 4 + 1] = (y[n512 + p] + 1) * 127.5;
      rgba[p * 4 + 2] = (y[2 * n512 + p] + 1) * 127.5;
      rgba[p * 4 + 3] = 255;
    }
    const strength = Math.max(0.45, Math.min(1, (f.score - 0.5) / 0.35));
    F.pasteBack(work, rgba, M, 512, mask, strength, msg.lumaOnly);
  }
  return { data: work.data, count: limit };
}

/* ── colour ──────────────────────────────────────────────────────────────── */
/* Four cheap detector passes to settle which way up the photograph is. Worth
   it even when the user never asked for faces: a colourisation model fed a
   sideways scene returns a blue wash. */
async function findOrientation(img, msg) {
  if (knownRot !== null) return knownRot;
  if (!msg.detPath) return 0;
  try {
    if (!detSession) {
      const d = await fetchParts([msg.detPath], msg.detSize || 232589, () => {});
      detSession = await ort.InferenceSession.create(d, { executionProviders: ['wasm'] });
    }
    const whole = { x: 0, y: 0, w: img.width, h: img.height };
    let best = { rot: 0, score: -1 };
    for (let rot = 0; rot < 4; rot++) {
      post('progress', { stage: 'Checking orientation (' + (rot + 1) + '/4)', p: 0.62 + 0.02 * rot });
      const dets = await runDetector(img, rot, whole);
      const score = dets.reduce((s, d) => s + d.score, 0);
      if (score > best.score) best = { rot, score };
    }
    knownRot = best.score > 0 ? best.rot : 0;
  } catch (e) { knownRot = 0; }
  return knownRot;
}

async function doColour(msg) {
  await loadOrt(msg.ortBase);
  if (!colourSession) {
    const bytes = await fetchParts([msg.path], msg.size,
      f => post('progress', { stage: 'Downloading the colour model — ' + Math.round(f * 100) + '%', p: 0.05 + 0.5 * f }));
    post('progress', { stage: 'Starting the colour model', p: 0.6 });
    colourSession = await ort.InferenceSession.create(bytes, { executionProviders: ['wasm'] });
  }
  const I = ReviveEngine._internal;
  const w = msg.width, h = msg.height, n = w * h;
  const data = new Uint8ClampedArray(msg.data);
  const L = ReviveColour.lightness(data, n, I.S2L);
  const rot = await findOrientation({ width: w, height: h, data }, msg);
  post('progress', { stage: 'Reading the colour of this scene', p: 0.72 });
  const S = ReviveColour.SIZE;
  /* Upright for the model, back again for the picture. */
  const small = ReviveColour.uprightL(L, w, h, rot, S);
  const x = ReviveColour.greyInput(small, S, I.linearToByte);
  const out = await colourSession.run({ [colourSession.inputNames[0]]: new ort.Tensor('float32', x, [1, 3, S, S]) });
  const ab = out[colourSession.outputNames[0]].data;
  post('progress', { stage: 'Laying the colour in', p: 0.9 });
  const aS = new Float32Array(S * S), bS = new Float32Array(S * S);
  aS.set(ab.subarray(0, S * S)); bS.set(ab.subarray(S * S, 2 * S * S));
  return {
    L,
    a: ReviveColour.abToFull(aS, S, w, h, rot),
    b: ReviveColour.abToFull(bS, S, w, h, rot),
    data,
  };
}

self.onmessage = async ev => {
  const msg = ev.data;
  try {
    if (msg.type === 'restore') {
      knownRot = null;
      const { result, stats, opts } = doRestore(msg);
      post('done', {
        id: msg.id, width: result.width, height: result.height,
        data: result.data.buffer, mask: result.mask ? result.mask.buffer : null,
        maskWidth: result.maskWidth, maskHeight: result.maskHeight,
        damageFraction: result.damageFraction, scale: result.scale, stats, opts,
      }, result.mask ? [result.data.buffer, result.mask.buffer] : [result.data.buffer]);
    } else if (msg.type === 'faces') {
      const r = await doFaces(msg);
      post('done', { id: msg.id, data: r.data.buffer, count: r.count }, [r.data.buffer]);
    } else if (msg.type === 'colour') {
      const r = await doColour(msg);
      post('done', { id: msg.id, L: r.L.buffer, a: r.a.buffer, b: r.b.buffer },
        [r.L.buffer, r.a.buffer, r.b.buffer]);
    }
  } catch (e) {
    post('failed', { id: msg.id, message: (e && e.message) ? e.message : String(e) });
  }
};
