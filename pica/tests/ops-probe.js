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

// Where does text actually start on the page? A histogram of line-start x values.
window.__colProbe = async function (url, pageNo) {
  const mod = await import('https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/legacy/build/pdf.min.mjs');
  mod.GlobalWorkerOptions.workerSrc = 'https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/legacy/build/pdf.worker.min.mjs';
  const pdf = await mod.getDocument({ url }).promise;
  const hist = {}, samples = {};
  const from = pageNo || 5, to = Math.min(from + 5, pdf.numPages);
  let vpw = 0, vph = 0;
  for (let p = from; p <= to; p++) {
    const page = await pdf.getPage(p);
    const vp = page.getViewport({ scale: 1 });
    vpw = vp.width; vph = vp.height;
    const tc = await page.getTextContent();
    // group items into lines by y, then take each line's leftmost x
    const rows = new Map();
    for (const it of tc.items) {
      if (!it.str || !it.str.trim()) continue;
      const y = Math.round(vp.height - it.transform[5]);
      if (!rows.has(y)) rows.set(y, []);
      rows.get(y).push(it);
    }
    for (const [y, its] of rows) {
      its.sort((a, b) => a.transform[4] - b.transform[4]);
      const x = Math.round(its[0].transform[4]);
      hist[x] = (hist[x] || 0) + 1;
      if (!samples[x]) samples[x] = its.map(i => i.str).join('').slice(0, 46);
    }
  }
  const top = Object.entries(hist).sort((a, b) => b[1] - a[1]).slice(0, 14)
    .map(([x, n]) => x + ' ×' + n + '  ' + JSON.stringify(samples[x]));
  return JSON.stringify({ viewport: [vpw, vph], pagesScanned: [from, to], topColumns: top }, null, 1);
};

// Histogram every text item's x across many pages — each showText is one whole line here.
window.__xProbe = async function (url, fromP, toP) {
  const mod = await import('https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/legacy/build/pdf.min.mjs');
  mod.GlobalWorkerOptions.workerSrc = 'https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/legacy/build/pdf.worker.min.mjs';
  const pdf = await mod.getDocument({ url }).promise;
  const hist = {}, sample = {};
  const a = fromP || 10, b = Math.min(toP || 30, pdf.numPages);
  for (let p = a; p <= b; p++) {
    const page = await pdf.getPage(p);
    const tc = await page.getTextContent();
    for (const it of tc.items) {
      if (!it.str || !it.str.trim()) continue;
      const x = Math.round(it.transform[4]);
      hist[x] = (hist[x] || 0) + 1;
      if (!sample[x]) sample[x] = it.str.slice(0, 40);
    }
  }
  const top = Object.entries(hist).sort((a2, b2) => b2[1] - a2[1]).slice(0, 12)
    .map(([x, n]) => 'x=' + x + ' ×' + n + '  ' + JSON.stringify(sample[x]));
  return JSON.stringify({ pages: [a, b], distinctX: Object.keys(hist).length, top }, null, 1);
};

// Show the TITLE page (hidden by default), so it can be looked at.
window.__titleShot = async function (url, name) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await window.PICA_API.importUrl(url, name || 'x.pdf');
  for (let i = 0; i < 900; i++) {
    const d = window.__pica && window.__pica.doc;
    if (d && d.elements.length > 1) break;
    await sleep(50);
  }
  if (!window.PICA_API.titleShown()) window.PICA_API.toggleTitlePage();
  await sleep(500);
  window.PICA_API.preparePrint();
  await sleep(1200);
  const pe = document.querySelectorAll('.pageWrap')[0];
  if (!pe) return JSON.stringify({ error: 'no page' });
  pe.scrollIntoView(); await sleep(350);
  const b = pe.getBoundingClientRect();
  return JSON.stringify({ clip: { x: b.left + scrollX, y: b.top + scrollY, width: b.width, height: b.height } });
};

// Import and photograph the ordinary reading view, scrolled to a page.
window.__viewShot = async function (url, pageNo) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await window.PICA_API.importUrl(url, 'x.pdf');
  for (let i = 0; i < 900; i++) {
    const d = window.__pica && window.__pica.doc;
    if (d && d.elements.length > 1) break;
    await sleep(50);
  }
  await sleep(500);
  const c = document.getElementById('canvas');
  const total = window.__pica.res.count || 1;
  c.scrollTop = Math.max(0, (c.scrollHeight * (pageNo - 1)) / total);
  await sleep(900);
  return JSON.stringify({ clip: { x: 0, y: 0, width: innerWidth, height: Math.min(innerHeight, 1000) },
    scrolled: Math.round(c.scrollTop), pages: total });
};

// After a normal import: is anything actually laid out?
window.__layoutProbe = async function (url) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await window.PICA_API.importUrl(url, 'x.pdf');
  for (let i = 0; i < 900; i++) {
    const d = window.__pica && window.__pica.doc;
    if (d && d.elements.length > 1) break;
    await sleep(50);
  }
  const snap = () => {
    const c = document.getElementById('canvas');
    const wraps = document.querySelectorAll('.pageWrap');
    const w0 = wraps[0];
    return {
      pages: window.__pica.res ? window.__pica.res.count : null,
      wraps: wraps.length,
      firstWrap: w0 ? [Math.round(w0.getBoundingClientRect().width), Math.round(w0.getBoundingClientRect().height)] : null,
      canvasScrollH: c.scrollHeight, canvasClientH: c.clientHeight, canvasClientW: c.clientWidth,
      linesDrawn: document.querySelectorAll('#pages div[data-el]').length,
      k: window.__pica.k, zoom: window.__pica.zoom,
      pagesElChildren: document.getElementById('pages').children.length,
      trialBarHidden: document.getElementById('trialBar').hidden,
    };
  };
  const now = snap();
  await sleep(1200);
  const later = snap();
  // does a resize/rerender fix it?
  window.dispatchEvent(new Event('resize'));
  await sleep(600);
  const afterResize = snap();
  return JSON.stringify({ now, later, afterResize }, null, 1);
};

window.__wrapProbe = async function (url) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await window.PICA_API.importUrl(url, 'x.pdf');
  for (let i = 0; i < 900; i++) {
    const d = window.__pica && window.__pica.doc;
    if (d && d.elements.length > 1) break;
    await sleep(50);
  }
  await sleep(800);
  const pages = document.getElementById('pages');
  const w = pages.querySelector('.pageWrap');
  const cs = w ? getComputedStyle(w) : null;
  const canvas = document.getElementById('canvas');
  const ccs = getComputedStyle(canvas);
  return JSON.stringify({
    layout: { pageW: window.__pica.doc.layout.pageW, pageH: window.__pica.doc.layout.pageH, k: window.__pica.k },
    wrapInline: w ? w.getAttribute('style') : null,
    wrapRect: w ? [Math.round(w.getBoundingClientRect().width), Math.round(w.getBoundingClientRect().height)] : null,
    wrapDisplay: cs ? cs.display : null,
    wrapVisibility: cs ? cs.visibility : null,
    pagesRect: [Math.round(pages.getBoundingClientRect().width), Math.round(pages.getBoundingClientRect().height)],
    pagesDisplay: getComputedStyle(pages).display,
    canvasRect: [Math.round(canvas.getBoundingClientRect().width), Math.round(canvas.getBoundingClientRect().height)],
    canvasDisplay: ccs.display, canvasOverflow: ccs.overflow,
    bodyClass: document.body.className,
    canvasHidden: canvas.hidden,
  }, null, 1);
};

// Per-page: where do LINES start? (leftmost item per baseline.) A scan can sit each page
// in a slightly different place.
window.__pageOffsetProbe = async function (url, from, to) {
  const mod = await import('https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/legacy/build/pdf.min.mjs');
  mod.GlobalWorkerOptions.workerSrc = 'https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/legacy/build/pdf.worker.min.mjs';
  const pdf = await mod.getDocument({ url }).promise;
  const out = [];
  for (let p = from; p <= Math.min(to, pdf.numPages); p++) {
    const page = await pdf.getPage(p);
    const vp = page.getViewport({ scale: 1 });
    const tc = await page.getTextContent();
    const rows = new Map();
    for (const it of tc.items) {
      if (!it.str || !it.str.trim()) continue;
      const y = Math.round(vp.height - it.transform[5]);
      const x = it.transform[4];
      if (!rows.has(y) || x < rows.get(y)) rows.set(y, x);
    }
    const xs = [...rows.values()].map(Math.round).sort((a, b) => a - b);
    const hist = {};
    for (const x of xs) hist[x] = (hist[x] || 0) + 1;
    const top = Object.entries(hist).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([x, n]) => x + '×' + n);
    out.push('p' + p + ' lines=' + xs.length + ' min=' + xs[0] + ' top=[' + top.join(' ') + ']');
  }
  return JSON.stringify(out, null, 1);
};

// Does a page's x offset depend on WHERE you are down it? (A photocopy can be rotated.)
window.__skewProbe = async function (url, from, to) {
  const mod = await import('https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/legacy/build/pdf.min.mjs');
  mod.GlobalWorkerOptions.workerSrc = 'https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/legacy/build/pdf.worker.min.mjs';
  const pdf = await mod.getDocument({ url }).promise;
  const out = [];
  for (let p = from; p <= Math.min(to, pdf.numPages); p++) {
    const page = await pdf.getPage(p);
    const vp = page.getViewport({ scale: 1 });
    const tc = await page.getTextContent();
    const rows = new Map();
    for (const it of tc.items) {
      if (!it.str || !it.str.trim()) continue;
      const y = Math.round(vp.height - it.transform[5]);
      const x = it.transform[4];
      if (!rows.has(y) || x < rows.get(y)) rows.set(y, x);
    }
    // for each line, distance to the nearest of the document's columns
    const cols = [94, 174, 212, 252];
    const pts = [...rows.entries()].map(([y, x]) => {
      let d = Infinity;
      for (const c of cols) if (Math.abs(x - c) < Math.abs(d)) d = x - c;
      return { y, d };
    }).filter(p2 => Math.abs(p2.d) < 40).sort((a, b) => a.y - b.y);
    if (pts.length < 6) continue;
    const top = pts.slice(0, Math.floor(pts.length / 3));
    const bot = pts.slice(-Math.floor(pts.length / 3));
    const mean = a => a.reduce((s, q) => s + q.d, 0) / a.length;
    out.push('p' + p + ' lines=' + pts.length
      + ' topThird=' + mean(top).toFixed(1) + ' bottomThird=' + mean(bot).toFixed(1)
      + ' skew=' + (mean(bot) - mean(top)).toFixed(1));
  }
  return JSON.stringify(out, null, 1);
};

// Per page, per column: how far off is each one? If the error grows with x, the sheet was
// scaled (a photocopy enlarged), not merely shifted — and a shift alone cannot fix it.
window.__scaleProbe = async function (url, from, to) {
  const mod = await import('https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/legacy/build/pdf.min.mjs');
  mod.GlobalWorkerOptions.workerSrc = 'https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/legacy/build/pdf.worker.min.mjs';
  const pdf = await mod.getDocument({ url }).promise;
  const cols = [94, 174, 252];
  const out = [];
  for (let p = from; p <= Math.min(to, pdf.numPages); p++) {
    const page = await pdf.getPage(p);
    const vp = page.getViewport({ scale: 1 });
    const tc = await page.getTextContent();
    const rows = new Map();
    for (const it of tc.items) {
      if (!it.str || !it.str.trim()) continue;
      const y = Math.round(vp.height - it.transform[5]);
      const x = it.transform[4];
      if (!rows.has(y) || x < rows.get(y)) rows.set(y, x);
    }
    const per = cols.map(() => []);
    for (const x of rows.values()) {
      let bi = -1, bd = 25;
      cols.forEach((c, i) => { if (Math.abs(x - c) < bd) { bd = Math.abs(x - c); bi = i; } });
      if (bi >= 0) per[bi].push(x - cols[bi]);
    }
    const mean = a => a.length ? (a.reduce((s, v) => s + v, 0) / a.length) : null;
    const m = per.map(mean);
    if (m.filter(v => v != null).length < 3) continue;
    out.push('p' + p + '  @94:' + m[0].toFixed(1) + '  @174:' + m[1].toFixed(1)
      + '  @252:' + m[2].toFixed(1) + '   spread=' + (m[2] - m[0]).toFixed(1));
  }
  return JSON.stringify(out, null, 1);
};
