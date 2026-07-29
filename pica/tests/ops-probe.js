// What ink is actually on a page? Loads a PDF with the same pdf.js the app uses and
// reports every path segment it draws, in page space, so a missed underline can be
// measured rather than guessed at.
window.__opsProbe = async function (url, pageNo) {
  const mod = await import('https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/legacy/build/pdf.min.mjs');
  mod.GlobalWorkerOptions.workerSrc = 'https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/legacy/build/pdf.worker.min.mjs';
  const pdf = await mod.getDocument({ url }).promise;
  const page = await pdf.getPage(pageNo);
  const vp = page.getViewport({ scale: 1 });
  const ol = await page.getOperatorList();
  const OPS = mod.OPS;
  const INK = new Set([OPS.fill, OPS.eoFill, OPS.stroke, OPS.fillStroke, OPS.eoFillStroke,
    OPS.closeStroke, OPS.closeFillStroke, OPS.closeEOFillStroke].filter(x => x != null));

  const names = {};
  for (const k of Object.keys(OPS)) names[OPS[k]] = k;
  const counts = {};
  for (const fn of ol.fnArray) counts[names[fn] || fn] = (counts[names[fn] || fn] || 0) + 1;

  // every path segment, transformed, with no filtering at all
  const segs = [];
  let ctm = [1, 0, 0, 1, 0, 0]; const stack = [];
  const mul = (m, n) => [m[0]*n[0]+m[2]*n[1], m[1]*n[0]+m[3]*n[1], m[0]*n[2]+m[2]*n[3],
    m[1]*n[2]+m[3]*n[3], m[0]*n[4]+m[2]*n[5]+m[4], m[1]*n[4]+m[3]*n[5]+m[5]];
  let pathsSeen = 0, pathsInked = 0;
  for (let i = 0; i < ol.fnArray.length; i++) {
    const fn = ol.fnArray[i];
    if (fn === OPS.save) stack.push(ctm.slice());
    else if (fn === OPS.restore) ctm = stack.pop() || [1, 0, 0, 1, 0, 0];
    else if (fn === OPS.transform) ctm = mul(ctm, ol.argsArray[i]);
    else if (fn === OPS.constructPath) {
      pathsSeen++;
      const inked = INK.has(ol.fnArray[i + 1]);
      const nextOp = names[ol.fnArray[i + 1]] || String(ol.fnArray[i + 1]);
      if (inked) pathsInked++;
      const [ops, co] = ol.argsArray[i];
      let ci = 0, cur = null;
      const seg = (x1, y1, x2, y2, how) => {
        const tx1 = ctm[0]*x1 + ctm[2]*y1 + ctm[4], ty1 = ctm[1]*x1 + ctm[3]*y1 + ctm[5];
        const tx2 = ctm[0]*x2 + ctm[2]*y2 + ctm[4], ty2 = ctm[1]*x2 + ctm[3]*y2 + ctm[5];
        segs.push({ how, inked, nextOp,
          dx: +(tx2 - tx1).toFixed(2), dy: +(ty2 - ty1).toFixed(2),
          x: +Math.min(tx1, tx2).toFixed(1), y: +(vp.height - Math.max(ty1, ty2)).toFixed(1) });
      };
      for (const op of ops) {
        if (op === OPS.moveTo) { cur = [co[ci], co[ci + 1]]; ci += 2; }
        else if (op === OPS.lineTo) { if (cur) seg(cur[0], cur[1], co[ci], co[ci + 1], 'lineTo'); cur = [co[ci], co[ci + 1]]; ci += 2; }
        else if (op === OPS.rectangle) { seg(co[ci], co[ci + 1], co[ci] + co[ci + 2], co[ci + 1] + co[ci + 3], 'rect'); ci += 4; }
        else if (op === OPS.curveTo) ci += 6;
        else if (op === OPS.curveTo2 || op === OPS.curveTo3) ci += 4;
      }
    }
  }
  const tc = await page.getTextContent();
  const fonts = {};
  for (const it of tc.items) if (it.str && it.str.trim()) fonts[it.fontName] = (fonts[it.fontName] || 0) + 1;
  const fontNames = {};
  for (const fn of Object.keys(fonts)) {
    try { const f = page.commonObjs.get(fn); fontNames[fn] = (f && f.name) || '?'; } catch { fontNames[fn] = 'unavailable'; }
  }
  return JSON.stringify({
    viewport: [vp.width, vp.height],
    pathsSeen, pathsInked,
    opCounts: Object.fromEntries(Object.entries(counts).filter(([k, v]) => v > 0).slice(0, 24)),
    segs: segs.slice(0, 40),
    horizontals: segs.filter(s => Math.abs(s.dy) < 4 && Math.abs(s.dx) > 8).slice(0, 20),
    fonts: fontNames,
    sampleText: tc.items.filter(i => i.str.trim()).slice(0, 6).map(i => i.fontName + ' | ' + i.str.slice(0, 40)),
  }, null, 1);
};

// Does raster underline detection actually find the rules on one scanned page?
window.__rasterProbe = async function (url, pageNo, scale) {
  const mod = await import('https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/legacy/build/pdf.min.mjs');
  mod.GlobalWorkerOptions.workerSrc = 'https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/legacy/build/pdf.worker.min.mjs';
  const pdf = await mod.getDocument({ url }).promise;
  const page = await pdf.getPage(pageNo);
  const vp = page.getViewport({ scale: 1 });
  const RS = scale || 2;
  const t0 = Date.now();
  const cv = document.createElement('canvas');
  const w = Math.ceil(vp.width * RS), h = Math.ceil(vp.height * RS);
  cv.width = w; cv.height = h;
  const ctx = cv.getContext('2d', { willReadFrequently: true });
  ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, w, h);
  let renderErr = null;
  try { await page.render({ canvasContext: ctx, viewport: page.getViewport({ scale: RS }) }).promise; }
  catch (e) { renderErr = String(e && (e.message || e)); }
  const tRender = Date.now() - t0;
  const t1 = Date.now();
  const px = ctx.getImageData(0, 0, w, h).data;
  // is anything at all drawn?
  let dark = 0;
  for (let i = 0; i < px.length; i += 4) if (px[i] + px[i+1] + px[i+2] < 450) dark++;
  const minLen = Math.round(10 * RS), maxLen = Math.round(vp.width * 0.85 * RS);
  const runs = [];
  for (let y = 0; y < h; y++) {
    let start = -1; const row = y * w;
    for (let x = 0; x <= w; x++) {
      const i = (row + x) * 4;
      const d = x < w && (px[i] + px[i+1] + px[i+2]) < 450;
      if (d) { if (start < 0) start = x; }
      else if (start >= 0) { const len = x - start; if (len >= minLen && len <= maxLen) runs.push({ y, x1: start, x2: x }); start = -1; }
    }
  }
  const bands = [];
  for (const r of runs) {
    const b = bands.find(b => b.y2 >= r.y - 1 && r.x1 < b.x2 && r.x2 > b.x1);
    if (b) { b.y2 = r.y; b.x1 = Math.min(b.x1, r.x1); b.x2 = Math.max(b.x2, r.x2); }
    else bands.push({ y1: r.y, y2: r.y, x1: r.x1, x2: r.x2 });
  }
  const maxThick = Math.round(3 * RS);
  const thin = bands.filter(b => b.y2 - b.y1 <= maxThick);
  const tScan = Date.now() - t1;
  return JSON.stringify({
    renderErr, tRender, tScan, canvas: [w, h], darkPixels: dark,
    runs: runs.length, bands: bands.length, thinBands: thin.length,
    found: thin.slice(0, 14).map(b => ({ x1: +(b.x1/RS).toFixed(1), x2: +(b.x2/RS).toFixed(1),
      y: +(b.y1/RS).toFixed(1), th: b.y2 - b.y1 })),
  }, null, 1);
};

// The real import path, end to end, in a browser that actually renders.
window.__importProbe = async function (url, _p, _s) {
  const t0 = Date.now();
  await window.PICA_API.importUrl(url, 'ThereWillBeBlood.pdf');
  for (let i = 0; i < 600; i++) {
    const d = window.__pica && window.__pica.doc;
    if (d && d.elements.length > 1) break;
    await new Promise(r => setTimeout(r, 50));
  }
  const S = window.__pica, doc = S.doc, L = doc.layout;
  const kinds = {};
  for (const e of doc.elements) for (const m of e.marks || []) {
    const k = e.type + ':' + m[2]; kinds[k] = (kinds[k] || 0) + 1;
  }
  const uSample = doc.elements.filter(e => (e.marks || []).some(m => m[2] === 'u'))
    .slice(0, 8).map(e => e.type + ' | ' + e.text.slice(0, 46));
  return JSON.stringify({
    ms: Date.now() - t0, title: doc.title, elements: doc.elements.length, pages: S.res.count,
    geom: [L.pageW, L.charW, L.rowH, L.widths.action].join('/'),
    markKinds: kinds, underlined: uSample,
  }, null, 1);
};

// Import, then hand back the clip rect of one page so the runner can photograph it.
window.__shootProbe = async function (url, pageNo) {
  await window.PICA_API.importUrl(url, 'ThereWillBeBlood.pdf');
  for (let i = 0; i < 600; i++) {
    const d = window.__pica && window.__pica.doc;
    if (d && d.elements.length > 1) break;
    await new Promise(r => setTimeout(r, 50));
  }
  window.PICA_API.preparePrint();
  await new Promise(r => setTimeout(r, 900));
  const wraps = document.querySelectorAll('.pageWrap');
  const pe = wraps[pageNo - 1];
  if (!pe) return JSON.stringify({ error: 'no page', count: wraps.length });
  pe.scrollIntoView();
  await new Promise(r => setTimeout(r, 350));
  const b = pe.getBoundingClientRect();
  return JSON.stringify({ clip: { x: b.left + scrollX, y: b.top + scrollY, width: b.width, height: b.height },
    pages: wraps.length });
};
