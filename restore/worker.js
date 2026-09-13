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
async function detectFaces(img) {
  const F = ReviveFace, N = F.NET, all = [];
  const views = [{ x: 0, y: 0, w: img.width, h: img.height }];
  /* Tile at close to native scale: one 640 pass over a 2500px group photo
     shrinks a head to ~35px and finds two faces out of five. */
  const TILE = Math.round(N * 1.4);
  if (img.width > TILE * 1.2 || img.height > TILE * 1.2) {
    const cols = Math.max(1, Math.ceil(img.width / TILE));
    const rows = Math.max(1, Math.ceil(img.height / TILE));
    const tw = Math.min(img.width, Math.ceil(img.width / cols * 1.34));
    const th = Math.min(img.height, Math.ceil(img.height / rows * 1.34));
    for (let c = 0; c < cols; c++) for (let r = 0; r < rows; r++) {
      const x = cols > 1 ? Math.round(c * (img.width - tw) / (cols - 1)) : 0;
      const y = rows > 1 ? Math.round(r * (img.height - th) / (rows - 1)) : 0;
      views.push({ x, y, w: tw, h: th });
    }
  }
  for (let i = 0; i < views.length; i++) {
    const v = views[i];
    post('progress', { stage: 'Looking for faces (' + (i + 1) + '/' + views.length + ')', p: 0.1 + 0.2 * (i / views.length) });
    const view = (v.w === img.width && v.h === img.height) ? img : subImage(img, v.x, v.y, v.w, v.h);
    const input = F.detectorInput(view);
    const out = await detSession.run({ [detSession.inputNames[0]]: new ort.Tensor('float32', input, [1, 3, N, N]) });
    const named = {};
    for (const k of Object.keys(out)) named[k] = out[k].data;
    const kx = v.w / N, ky = v.h / N;
    for (const d of F.decodeDetections(named, 0.5)) {
      d.x = d.x * kx + v.x; d.y = d.y * ky + v.y; d.w *= kx; d.h *= ky;
      d.pts = d.pts.map(p => [p[0] * kx + v.x, p[1] * ky + v.y]);
      all.push(d);
    }
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
async function doColour(msg) {
  await loadOrt(msg.ortBase);
  if (!colourSession) {
    const bytes = await fetchParts([msg.path], msg.size,
      f => post('progress', { stage: 'Downloading the colour model — ' + Math.round(f * 100) + '%', p: 0.05 + 0.5 * f }));
    post('progress', { stage: 'Starting the colour model', p: 0.6 });
    colourSession = await ort.InferenceSession.create(bytes, { executionProviders: ['wasm'] });
  }
  post('progress', { stage: 'Reading the colour of this scene', p: 0.7 });
  const I = ReviveEngine._internal;
  const w = msg.width, h = msg.height, n = w * h;
  const data = new Uint8ClampedArray(msg.data);
  const L = ReviveColour.lightness(data, n, I.S2L);
  const S = ReviveColour.SIZE;
  const small = I.resample(L, w, h, S, S, 3);
  const x = ReviveColour.greyInput(small, S, I.linearToByte);
  const out = await colourSession.run({ [colourSession.inputNames[0]]: new ort.Tensor('float32', x, [1, 3, S, S]) });
  const ab = out[colourSession.outputNames[0]].data;
  post('progress', { stage: 'Laying the colour in', p: 0.9 });
  const aS = new Float32Array(S * S), bS = new Float32Array(S * S);
  aS.set(ab.subarray(0, S * S)); bS.set(ab.subarray(S * S, 2 * S * S));
  return {
    L, a: I.resample(aS, S, S, w, h, 3), b: I.resample(bS, S, S, w, h, 3),
    data,
  };
}

self.onmessage = async ev => {
  const msg = ev.data;
  try {
    if (msg.type === 'restore') {
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
