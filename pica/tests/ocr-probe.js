// Import a picture-only scan: the recogniser's reading stands in for the Mac's.
window.__ocrProbe = async function (pdfUrl, ocrUrl, name) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const layer = await (await fetch(ocrUrl)).json();
  const byPage = new Map(layer.map(p => [p.page, p]));
  let asked = null;
  window.PICA_API.test.stubOcr(async pages => { asked = pages.slice(); return pages.map(n => byPage.get(n)).filter(Boolean); });
  await window.PICA_API.importUrl(pdfUrl, name);
  for (let i = 0; i < 6000; i++) { const d = window.__pica && window.__pica.doc; if (d && d.elements.length > 20) break; await sleep(50); }
  const S = window.__pica, doc = S.doc, els = doc.elements;
  const toastTxt = (document.getElementById('toast')||{}).textContent;
  const count = {};
  for (const e of els) count[e.type] = (count[e.type] || 0) + 1;
  const isJunk = t => /^\(?\s*\d{0,3}\s*(CONTINUED|CONT'D|CONT’D)\s*[:.]?\s*(\(\d+\))?\s*\)?$/i.test(t)
    || /\b(revisions?|draft)\b/i.test(t) || /^\d{1,3}\.?$/.test(t);
  const cueNoSpeech = [], speechNoCue = [];
  els.forEach((e, i) => {
    const nxt = els[i + 1], prv = els[i - 1];
    if (e.type === 'character' && (!nxt || (nxt.type !== 'dialogue' && nxt.type !== 'paren'))) cueNoSpeech.push(i + ' ' + e.text.slice(0, 26));
    if (e.type === 'dialogue' && (!prv || (prv.type !== 'character' && prv.type !== 'paren' && prv.type !== 'dialogue'))) speechNoCue.push(i + ' ' + e.text.slice(0, 26));
  });
  return JSON.stringify({
    toast: toastTxt, read: doc.__read,
    askedPages: asked ? asked.length : 0, title: doc.title, pages: S.res.count, elements: els.length,
    types: count,
    junk: els.filter(e => isJunk(e.text.trim())).length,
    innerDoubleSpace: els.filter(e => /\S {2,4}\S/.test(e.text)).length,
    dsSample: els.filter(e => /\S {2,4}\S/.test(e.text)).slice(0,5).map(e => JSON.stringify(e.text.slice(0,50))),
    junkSample: els.filter(e => isJunk(e.text.trim())).slice(0, 6).map(e => e.type + ' :: ' + e.text.slice(0, 30)),
    general: els.filter(e => e.type === 'general').length,
    generalSample: els.filter(e => e.type === 'general').slice(0, 26).map(e => JSON.stringify(e.text.slice(0, 46))),
    generalX: (() => { const xs={}; const gen=new Set(els.filter(e=>e.type==='general').map(e=>e.id));
      for (const pg of S.res.pages) for (const l of pg.lines) if (gen.has(l.el)) { const k=Math.round(l.x/5)*5; xs[k]=(xs[k]||0)+1; }
      return Object.entries(xs).sort((a,b)=>b[1]-a[1]).slice(0,10).map(([x,n])=>x+'×'+n); })(),
    cueWithNoSpeech: cueNoSpeech.length, cueSample: cueNoSpeech.slice(0, 5),
    speechWithNoCue: speechNoCue.length, speechSample: speechNoCue.slice(0, 5),
    first: els.slice(0, 14).map(e => e.type + ' :: ' + e.text.slice(0, 44)),
  }, null, 1);
};
window.__ocrAround = async function (pdfUrl, ocrUrl, name, idxs) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const layer = await (await fetch(ocrUrl)).json();
  const byPage = new Map(layer.map(p => [p.page, p]));
  window.PICA_API.test.stubOcr(async pages => pages.map(n => byPage.get(n)).filter(Boolean));
  await window.PICA_API.importUrl(pdfUrl, name);
  for (let i = 0; i < 6000; i++) { const d = window.__pica && window.__pica.doc; if (d && d.elements.length > 20) break; await sleep(50); }
  const els = window.__pica.doc.elements, out = [];
  for (const i of idxs) {
    for (let j = Math.max(0, i - 2); j <= Math.min(els.length - 1, i + 2); j++)
      out.push((j === i ? '>> ' : '   ') + j + ' ' + els[j].type + ' :: ' + JSON.stringify(els[j].text.slice(0, 70)));
    out.push('');
  }
  return JSON.stringify(out, null, 1);
};
window.__ocrWatch = async function (pdfUrl, ocrUrl, name) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const layer = await (await fetch(ocrUrl)).json();
  const byPage = new Map(layer.map(p => [p.page, p]));
  window.PICA_API.test.stubOcr(async pages => pages.map(n => byPage.get(n)).filter(Boolean));
  const errs = [];
  window.addEventListener('error', e => errs.push(String(e.message)));
  window.addEventListener('unhandledrejection', e => errs.push('rej: ' + String(e.reason && e.reason.message || e.reason)));
  window.PICA_API.importUrl(pdfUrl, name);
  const seen = [];
  for (let i = 0; i < 160; i++) {
    await sleep(500);
    const n = document.getElementById('importLog');
    const t = n ? n.textContent : '(gone)';
    if (!seen.length || seen[seen.length - 1].t !== t) seen.push({ at: i * 0.5, t, toast: (document.getElementById('toast')||{}).textContent });
    if (window.__pica.doc.elements.length > 20) break;
  }
  return JSON.stringify({ errs, log: seen.slice(-12), els: window.__pica.doc.elements.length }, null, 1);
};
