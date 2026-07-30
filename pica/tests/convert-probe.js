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
