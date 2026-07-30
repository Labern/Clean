// The promise the feature makes: nothing reaches the library unless he accepts it.
// The network is stubbed with a local PDF so this tests the DECISION, not the internet.
window.__trialProbe = async function (pdfUrl) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const idx = () => JSON.parse(localStorage.getItem('pica.index') || '[]');
  const out = {};

  const buf = await (await fetch(pdfUrl)).arrayBuffer();
  // stand in for the web: one candidate, always the same local file
  window.PICA_API.test.stubNet({
    candidates: async () => ([{ url: pdfUrl, host: 'local.test', label: '', score: 99 }]),
    bytes: async () => buf.slice(0),   // pdf.js detaches the buffer it is given
  });

  const before = idx().length;
  const openBefore = window.__pica.docId;

  // ── 1. search, then CANCEL: the library must be untouched and the old script back
  await window.PICA_API.test.find('Some Like It Hot');
  await sleep(400);
  out.barShownWhileTrialling = document.getElementById('trialBar').hidden === false;
  out.trialIsOpen = !!window.__pica.trial;
  out.indexDuringTrial = idx().length;
  out.trialNotInIndex = !idx().some(d => d.id === window.PICA_API.test.trialId());
  document.getElementById('tbCancel').click();
  await sleep(700);
  out.afterCancel_index = idx().length;
  out.afterCancel_entries = idx().map(d => d.id.slice(0,6) + ':' + d.title);
  out.afterCancel_barHidden = document.getElementById('trialBar').hidden === true;
  out.afterCancel_backToPrevious = window.__pica.docId === openBefore;
  out.afterCancel_noTrial = !window.__pica.trial;

  // ── 2. search again, then ACCEPT: exactly one new entry, and it is the script
  await window.PICA_API.test.find('Some Like It Hot');
  await sleep(400);
  const trialId = window.PICA_API.test.trialId();
  document.getElementById('tbAccept').click();
  await sleep(600);
  const after = idx();
  out.afterAccept_added = after.length - before;
  out.trialIdWas = trialId;
  out.afterAccept_entries = after.map(d => d.id.slice(0,6) + ':' + d.title + ':' + d.pages);
  out.afterAccept_isTheScript = after.some(d => d.id === trialId);
  out.afterAccept_barHidden = document.getElementById('trialBar').hidden === true;
  out.afterAccept_pages = (after.find(d => d.id === trialId) || {}).pages;
  out.afterAccept_title = (after.find(d => d.id === trialId) || {}).title;
  return JSON.stringify(out, null, 1);
};
