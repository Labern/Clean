// The whole promise, with real screenplays: it downloads, IMPORTS, and SHOWS the script,
// and only then asks. Try again moves on. Cancel leaves nothing. Accept keeps one.
window.__flowProbe = async function (urls) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const T = window.PICA_API.test;
  const idx = () => JSON.parse(localStorage.getItem('pica.index') || '[]');
  const log = [];
  const bufs = {};
  for (const u of urls) bufs[u] = await (await fetch(u)).arrayBuffer();

  // a dead link first, then the real ones — exactly what the web gives you
  const cands = [{ url: 'dead://nothing', host: 'dead.test', label: '', score: 99 }]
    .concat(urls.map((u, i) => ({ url: u, host: 'archive' + i + '.test', label: '', score: 90 - i })));
  T.stubNet({
    candidates: async () => cands,
    bytes: async u => { if (u === 'dead://nothing') throw new Error('404'); return bufs[u].slice(0); },
  });

  const shown = () => ({
    bar: document.getElementById('trialBar').hidden === false,
    pages: document.querySelectorAll('.pageWrap').length,
    lines: document.querySelectorAll('#pages div[data-el]').length,
    title: (document.getElementById('tbTitle') || {}).textContent,
    meta: (document.getElementById('tbMeta') || {}).textContent,
    from: (document.getElementById('tbFrom') || {}).textContent,
    count: (document.getElementById('tbCount') || {}).textContent,
    docTitle: window.__pica.doc.title,
    inIndex: idx().length,
  });

  const before = idx().length;
  const openBefore = window.__pica.docId;

  // ── search: the dead link is skipped, the first live one is shown
  await T.find('Anything');
  await sleep(600);
  const first = shown();
  log.push('after search: bar=' + first.bar + ' pages=' + first.pages + ' linesDrawn=' + first.lines
    + ' doc="' + first.docTitle + '" indexHeld=' + (first.inIndex === before)
    + ' bar[' + first.title + ' · ' + first.meta + ' · ' + first.from + ' · ' + first.count + ']');
  const readableBeforeApproval = first.pages > 1 && first.lines > 0 && first.inIndex === before;

  // ── try again: the NEXT candidate, also shown, still nothing saved
  document.getElementById('tbAgain').click();
  await sleep(1400);
  const second = shown();
  log.push('after try again: doc="' + second.docTitle + '" pages=' + second.pages
    + ' indexHeld=' + (second.inIndex === before) + ' count=' + second.count);
  const movedOn = second.docTitle !== first.docTitle && second.inIndex === before;

  // ── cancel: back where he was, nothing left behind
  document.getElementById('tbCancel').click();
  await sleep(900);
  const cancelClean = idx().length === before && window.__pica.docId === openBefore
    && document.getElementById('trialBar').hidden === true;
  log.push('after cancel: index=' + idx().length + ' restored=' + (window.__pica.docId === openBefore));

  // ── search again and accept: exactly one, and it is the script he saw
  await T.find('Anything');
  await sleep(700);
  const trialTitle = window.__pica.doc.title, trialId = T.trialId();
  document.getElementById('tbAccept').click();
  await sleep(700);
  const after = idx();
  const kept = after.find(d => d.id === trialId);
  log.push('after accept: added=' + (after.length - before) + ' entry="' + (kept ? kept.title + ' · ' + kept.pages + 'p' : 'MISSING') + '"');
  const acceptedOk = after.length === before + 1 && !!kept && kept.title === trialTitle
    && document.getElementById('trialBar').hidden === true && !T.trialId();

  T.stubNet(null);
  return JSON.stringify({ readableBeforeApproval, movedOn, cancelClean, acceptedOk, log }, null, 1);
};

// Photograph the moment of decision: the script on screen, the bar above it.
window.__flowShot = async function (urls) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const T = window.PICA_API.test;
  const bufs = {};
  for (const u of urls) bufs[u] = await (await fetch(u)).arrayBuffer();
  T.stubNet({
    candidates: async () => urls.map((u, i) => ({ url: u, host: 'scriptarchive.example', label: '', score: 90 - i })),
    bytes: async u => bufs[u].slice(0),
  });
  await T.find('Pulp Fiction');
  await sleep(900);
  document.getElementById('canvas').scrollTop = 0;
  await sleep(400);
  return JSON.stringify({ clip: { x: 0, y: 0, width: innerWidth, height: Math.min(innerHeight, 1000) } });
};
