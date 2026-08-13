// Import a script and report everything that would make it read wrong.
window.__convertProbe = async function (url, name) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const t0 = Date.now();
  await window.PICA_API.importUrl(url, name);
  for (let i = 0; i < 1200; i++) {
    const d = window.__pica && window.__pica.doc;
    if (d && d.elements.length > 1) break;
    await sleep(50);
  }
  const S = window.__pica, doc = S.doc, res = S.res, L = doc.layout;
  const els = doc.elements;
  const byId = new Map(els.map(e => [e.id, e]));
  const count = {};
  for (const e of els) count[e.type] = (count[e.type] || 0) + 1;

  const orphans = [];
  res.pages.forEach((pg, pi) => {
    const body = pg.lines.filter(l => l.kind !== 'pn' && l.kind !== 'rev' && l.kind !== 'more');
    const last = body[body.length - 1];
    if (!last) return;
    const el = byId.get(last.el);
    if (el && el.type === 'character') orphans.push('p' + (pi + 1) + ' ' + last.text.slice(0, 24));
  });

  const cueNoSpeech = [], speechNoCue = [];
  els.forEach((e, i) => {
    const nxt = els[i + 1], prv = els[i - 1];
    if (e.type === 'character' && (!nxt || (nxt.type !== 'dialogue' && nxt.type !== 'paren')))
      cueNoSpeech.push(i + ' ' + e.text.slice(0, 30));
    if (e.type === 'dialogue' && (!prv || (prv.type !== 'character' && prv.type !== 'paren' && prv.type !== 'dialogue')))
      speechNoCue.push(i + ' ' + e.text.slice(0, 30));
  });

  return JSON.stringify({
    ms: Date.now() - t0, title: doc.title, elements: els.length, pages: res.count,
    geometry: [L.pageW, L.charW, L.rowH, L.widths.action, L.cols.character].join('/'),
    types: count,
    orphanCues: orphans.length, orphanSample: orphans.slice(0, 4),
    cueWithNoSpeech: cueNoSpeech.length, cueSample: cueNoSpeech.slice(0, 6),
    speechWithNoCue: speechNoCue.length, speechSample: speechNoCue.slice(0, 6),
    hardBreaksInDialogue: els.filter(e => e.type === 'dialogue' && !e.dual && e.text.includes('\n')).length,
    generals: els.filter(e => e.type === 'general').slice(0, 6).map(e => e.text.slice(0, 44)),
    first: els.slice(0, 10).map(e => e.type + ' :: ' + e.text.slice(0, 46)),
  }, null, 1);
};

// The head of the document: title page entries, first elements, and where page 1 draws.
window.__headProbe = async function (url, name) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await window.PICA_API.importUrl(url, name);
  for (let i = 0; i < 1200; i++) {
    const d = window.__pica && window.__pica.doc;
    if (d && d.elements.length > 1) break;
    await sleep(50);
  }
  const S = window.__pica, doc = S.doc, res = S.res;
  const p1 = res.pages[0];
  return JSON.stringify({
    titlePageEntries: (doc.titlePage || []).map(t => 'row=' + t.row + ' x=' + (t.x == null ? '-' : t.x) + ' :: ' + JSON.stringify(t.text.slice(0, 40))),
    firstElements: doc.elements.slice(0, 12).map((e, i) => i + ' ' + e.type + (e.dual ? ' DUAL g=' + e.dual.g + ' r=' + e.dual.r : '') + (e.xOverride != null ? ' x=' + e.xOverride : '') + ' :: ' + JSON.stringify(e.text.slice(0, 46))),
    dualCount: doc.elements.filter(e => e.dual).length,
    page1Lines: p1.lines.slice(0, 16).map(l => 'y=' + Math.round(l.y) + ' x=' + Math.round(l.x) + ' ' + (l.kind || 'line') + ' :: ' + JSON.stringify(l.text.slice(0, 44))),
  }, null, 1);
};

// Dump the neighbourhood of specific element indexes.
window.__aroundProbe = async function (url, name, idxs) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await window.PICA_API.importUrl(url, name);
  for (let i = 0; i < 1200; i++) {
    const d = window.__pica && window.__pica.doc;
    if (d && d.elements.length > 1) break;
    await sleep(50);
  }
  const els = window.__pica.doc.elements;
  const out = [];
  for (const i of idxs) {
    for (let j = Math.max(0, i - 3); j <= Math.min(els.length - 1, i + 3); j++)
      out.push((j === i ? '>> ' : '   ') + j + ' ' + els[j].type + ' :: ' + JSON.stringify(els[j].text.slice(0, 60)));
    out.push('');
  }
  return JSON.stringify(out, null, 1);
};

// Every scene heading, to eyeball spacing.
window.__scenesProbe = async function (url, name) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await window.PICA_API.importUrl(url, name);
  for (let i = 0; i < 1200; i++) {
    const d = window.__pica && window.__pica.doc;
    if (d && d.elements.length > 1) break;
    await sleep(50);
  }
  const sc = window.__pica.doc.elements.filter(e => e.type === 'scene');
  return JSON.stringify({
    count: sc.length,
    doubleSpaced: sc.filter(e => /\s{2,}/.test(e.text)).length,
    sample: sc.slice(0, 8).map(e => JSON.stringify(e.text)),
  }, null, 1);
};

// What are the unclassified elements, and where do they sit?
window.__generalProbe = async function (url, name) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await window.PICA_API.importUrl(url, name);
  for (let i = 0; i < 1200; i++) {
    const d = window.__pica && window.__pica.doc;
    if (d && d.elements.length > 1) break;
    await sleep(50);
  }
  const S = window.__pica, els = S.doc.elements;
  const gen = els.map((e, i) => ({ e, i })).filter(x => x.e.type === 'general');
  // where does each land on the page?
  const xs = {};
  for (const pg of S.res.pages) for (const l of pg.lines) {
    const el = els.find(e => e.id === l.el);
    if (el && el.type === 'general') { const k = Math.round(l.x); xs[k] = (xs[k] || 0) + 1; }
  }
  return JSON.stringify({
    total: els.length, general: gen.length,
    xHistogram: Object.entries(xs).sort((a, b) => b[1] - a[1]).slice(0, 8).map(([x, n]) => 'x=' + x + ' ×' + n),
    lengths: { under10: gen.filter(g => g.e.text.length < 10).length,
               under30: gen.filter(g => g.e.text.length < 30).length,
               over60: gen.filter(g => g.e.text.length > 60).length },
    allCaps: gen.filter(g => g.e.text === g.e.text.toUpperCase() && /[A-Z]/.test(g.e.text)).length,
    sample: gen.slice(0, 14).map(g => g.i + ' :: ' + JSON.stringify(g.e.text.slice(0, 54))),
  }, null, 1);
};
window.__dbgProbe = async function (url, name) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await window.PICA_API.importUrl(url, name);
  for (let i = 0; i < 1200; i++) {
    const d = window.__pica && window.__pica.doc;
    if (d && d.elements.length > 1) break;
    await sleep(50);
  }
  return JSON.stringify(window.__pica.doc.__dbg || {}, null, 1);
};
window.__transProbe = async function (url, name) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await window.PICA_API.importUrl(url, name);
  for (let i = 0; i < 1200; i++) {
    const d = window.__pica && window.__pica.doc;
    if (d && d.elements.length > 1) break;
    await sleep(50);
  }
  const els = window.__pica.doc.elements;
  const tr = els.filter(e => e.type === 'transition');
  const counts = {};
  for (const e of tr) { const k = e.text.trim(); counts[k] = (counts[k] || 0) + 1; }
  return JSON.stringify({ total: tr.length,
    distinct: Object.entries(counts).sort((a,b)=>b[1]-a[1]).slice(0,12).map(([k,n])=>n+'× '+JSON.stringify(k)) }, null, 1);
};
window.__unplacedProbe = async function (url) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  window.__unplaced = [];
  await window.PICA_API.importUrl(url, 'x.pdf');
  for (let i = 0; i < 1200; i++) {
    const d = window.__pica && window.__pica.doc;
    if (d && d.elements.length > 1) break;
    await sleep(50);
  }
  const u = window.__unplaced;
  const byOff = {};
  for (const r of u) { const k = Math.round(r.off / 5) * 5; byOff[k] = (byOff[k] || 0) + 1; }
  return JSON.stringify({
    unplacedLines: u.length,
    offsetHistogram: Object.entries(byOff).sort((a, b) => b[1] - a[1]).slice(0, 10).map(([k, n]) => k + 'pt ×' + n),
    cues: u.filter(r => /^[A-Z][A-Z' .]{2,20}$/.test(r.t)).slice(0, 8),
  }, null, 1);
};
window.__colsProbe = async function (url) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await window.PICA_API.importUrl(url, 'x.pdf');
  for (let i = 0; i < 1200; i++) { const d = window.__pica && window.__pica.doc; if (d && d.elements.length > 1) break; await sleep(50); }
  return JSON.stringify(window.__cols || {}, null, 1);
};
window.__clusterProbe = async function (url, cx) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  window.__lineDump = [];
  await window.PICA_API.importUrl(url, 'x.pdf');
  for (let i = 0; i < 1200; i++) { const d = window.__pica && window.__pica.doc; if (d && d.elements.length > 1) break; await sleep(50); }
  const d = window.__lineDump || [];
  const near = d.filter(l => Math.abs(l.x - cx) <= 3);
  const prose = near.filter(l => l.t.length > 12 && /[a-z]{3}/.test(l.t));
  return JSON.stringify({ cols: window.__cols && window.__cols.cols, atX: near.length,
    proseShare: near.length ? +(prose.length / near.length).toFixed(2) : null,
    sample: near.slice(0, 10).map(l => l.t.slice(0, 56)) }, null, 1);
};
window.__junkProbe = async function (url) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await window.PICA_API.importUrl(url, 'x.pdf');
  for (let i = 0; i < 1200; i++) { const d = window.__pica && window.__pica.doc; if (d && d.elements.length > 1) break; await sleep(50); }
  const els = window.__pica.doc.elements;
  const isJunk = t => /^\(?\s*\d{0,3}\s*(CONTINUED|CONT'D|CONT’D)\s*[:.]?\s*(\(\d+\))?\s*\)?$/i.test(t)
    || /\b(revisions?|draft)\b/i.test(t) || /^\d{1,3}\.?$/.test(t);
  const junk = els.filter(e => isJunk(e.text.trim()));
  const byType = {};
  for (const e of junk) byType[e.type] = (byType[e.type] || 0) + 1;
  return JSON.stringify({ total: els.length, junk: junk.length, byType,
    sample: junk.slice(0, 12).map(e => e.type + ' :: ' + JSON.stringify(e.text.slice(0, 44))) }, null, 1);
};
// Where does a script stop being read correctly? Types per page.
window.__driftProbe = async function (url, name) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await window.PICA_API.importUrl(url, name);
  for (let i = 0; i < 2000; i++) { const d = window.__pica && window.__pica.doc; if (d && d.elements.length > 20) break; await sleep(50); }
  const S = window.__pica, els = S.doc.elements;
  const byId = new Map(els.map(e => [e.id, e]));
  const rows = [];
  S.res.pages.forEach((pg, i) => {
    const t = {};
    const xs = {};
    for (const l of pg.lines) {
      const el = byId.get(l.el); if (!el) continue;
      t[el.type] = (t[el.type] || 0) + 1;
    }
    rows.push({ p: i + 1, a: t.action || 0, d: t.dialogue || 0, c: t.character || 0, g: t.general || 0 });
  });
  // collapse to blocks of 10 pages
  const blocks = [];
  for (let i = 0; i < rows.length; i += 10) {
    const b = rows.slice(i, i + 10);
    blocks.push((i + 1) + '-' + (i + b.length) + ' a=' + b.reduce((s, r) => s + r.a, 0)
      + ' d=' + b.reduce((s, r) => s + r.d, 0) + ' c=' + b.reduce((s, r) => s + r.c, 0)
      + ' g=' + b.reduce((s, r) => s + r.g, 0));
  }
  return JSON.stringify({ read: S.doc.__read, blocks }, null, 1);
};
