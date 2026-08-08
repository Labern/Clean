// Does any page end with a character cue, its dialogue stranded on the next page?
window.__orphanProbe = async function (url) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await window.PICA_API.importUrl(url, 'Jackie-Brown.pdf');
  for (let i = 0; i < 900; i++) {
    const d = window.__pica && window.__pica.doc;
    if (d && d.elements.length > 1) break;
    await sleep(50);
  }
  const S = window.__pica, doc = S.doc, res = S.res;
  const byId = new Map(doc.elements.map(e => [e.id, e]));
  const bad = [];
  res.pages.forEach((pg, pi) => {
    const body = pg.lines.filter(l => l.kind !== 'pn' && l.kind !== 'more' && l.kind !== 'rev');
    if (!body.length) return;
    const last = body[body.length - 1];
    const el = byId.get(last.el);
    if (!el || el.type !== 'character') return;
    const next = res.pages[pi + 1];
    const nextFirst = next && next.lines.filter(l => l.kind !== 'pn' && l.kind !== 'rev')[0];
    bad.push({
      page: pi + 1,
      cue: last.text,
      cueKind: last.kind,
      nextPageStartsWith: nextFirst ? (nextFirst.kind + ':' + nextFirst.text.slice(0, 42)) : '(none)',
      // what the model says follows this cue
      modelAfter: (() => {
        const i = doc.elements.findIndex(e => e.id === el.id);
        return doc.elements.slice(i, i + 3).map(e => e.type + ':' + e.text.slice(0, 34));
      })(),
    });
  });
  return JSON.stringify({ pages: res.count, orphanCues: bad.length, cases: bad.slice(0, 6) }, null, 1);
};

// Find one speech by text and report exactly how it is typed and paginated.
window.__findSpeech = async function (url, needle) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await window.PICA_API.importUrl(url, 'Jackie-Brown.pdf');
  for (let i = 0; i < 900; i++) {
    const d = window.__pica && window.__pica.doc;
    if (d && d.elements.length > 1) break;
    await sleep(50);
  }
  const S = window.__pica, doc = S.doc, res = S.res;
  const idx = doc.elements.findIndex(e => e.text.indexOf(needle) >= 0);
  if (idx < 0) return JSON.stringify({ error: 'not found' });
  const around = doc.elements.slice(Math.max(0, idx - 3), idx + 5)
    .map((e, i) => (Math.max(0, idx - 3) + i) + ' ' + e.type + ' :: ' + JSON.stringify(e.text.slice(0, 70)));
  // which page(s) each of those elements lands on, and where in the page
  const ids = new Set(doc.elements.slice(Math.max(0, idx - 3), idx + 5).map(e => e.id));
  const placed = [];
  res.pages.forEach((pg, pi) => {
    pg.lines.forEach(l => {
      if (!ids.has(l.el)) return;
      placed.push('p' + (pi + 1) + ' y=' + Math.round(l.y) + ' x=' + Math.round(l.x) +
        ' kind=' + (l.kind || 'line') + ' :: ' + JSON.stringify(l.text.slice(0, 48)));
    });
  });
  return JSON.stringify({ around, placed: placed.slice(0, 24) }, null, 1);
};
