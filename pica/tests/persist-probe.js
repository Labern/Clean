// "Eating my inputs" can mean typing vanishes on reload — a write that was silently
// dropped. The search feature blocks writes for documents on trial; if that guard ever
// outlives the trial, everything typed afterwards is lost.
window.__persistProbe = async function (pdfUrl) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const T = window.PICA_API.test;
  const buf = await (await fetch(pdfUrl)).arrayBuffer();
  const out = {};
  const idx = () => JSON.parse(localStorage.getItem('pica.index') || '[]');
  const stored = async id => { try { return await window.__pica.constructor === undefined ? null : null; } catch { return null; } };

  const typeSome = async (text) => {
    T.caret(0, 0);
    T.type(text);
    await sleep(900);                       // past the 700ms save debounce
  };
  const savedText = id => (idx().find(d => d.id === id) || {}).title;

  // 1. plain document, no search involved
  await T.reset();
  await typeSome('INT. BASELINE - DAY');
  out.baseline = T.state()[0];

  // 2. search, ACCEPT, then keep writing in the accepted script
  T.stubNet({ candidates: async () => ([{ url: pdfUrl, host: 'h', label: '', score: 9 }]),
              bytes: async () => buf.slice(0) });
  await T.find('X');
  await sleep(900);
  document.getElementById('tbAccept').click();
  await sleep(700);
  const acceptedId = window.__pica.docId;
  await typeSome('AFTER ACCEPT ');
  out.afterAccept_inModel = T.state()[0].slice(0, 40);
  out.afterAccept_blockedFromSaving = window.__pica.docId === acceptedId &&
    !!(window.__picaTrialsHas ? window.__picaTrialsHas(acceptedId) : false);
  // did it actually reach storage?
  out.afterAccept_reachedStore = await new Promise(res => {
    const rq = indexedDB.open('pica');
    rq.onsuccess = () => {
      const db = rq.result;
      const g = db.transaction('kv', 'readonly').objectStore('kv').get('doc.' + acceptedId);
      g.onsuccess = () => res(!!g.result && JSON.stringify(g.result).includes('AFTER ACCEPT'));
      g.onerror = () => res('err');
    };
    rq.onerror = () => res('dberr');
  });

  // 3. search, CANCEL, then keep writing in whatever was restored
  await T.find('X');
  await sleep(900);
  document.getElementById('tbCancel').click();
  await sleep(800);
  const restoredId = window.__pica.docId;
  await typeSome('AFTER CANCEL ');
  out.afterCancel_reachedStore = await new Promise(res => {
    const rq = indexedDB.open('pica');
    rq.onsuccess = () => {
      const db = rq.result;
      const g = db.transaction('kv', 'readonly').objectStore('kv').get('doc.' + restoredId);
      g.onsuccess = () => res(!!g.result && JSON.stringify(g.result).includes('AFTER CANCEL'));
      g.onerror = () => res('err');
    };
    rq.onerror = () => res('dberr');
  });
  T.stubNet(null);
  return JSON.stringify(out, null, 1);
};

// After using the decision bar, do keystrokes reach the SCRIPT again?
window.__focusProbe = async function (pdfUrl) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const T = window.PICA_API.test;
  const buf = await (await fetch(pdfUrl)).arrayBuffer();
  const pages = document.getElementById('pages');
  const out = {};
  const typeReal = (str) => {           // a real keystroke, not the test API
    for (const ch of str) {
      pages.dispatchEvent(new KeyboardEvent('keydown', { key: ch, bubbles: true, cancelable: true }));
      const tgt = document.activeElement;
      (tgt || pages).dispatchEvent(new InputEvent('beforeinput',
        { inputType: 'insertText', data: ch, bubbles: true, cancelable: true }));
    }
  };
  T.stubNet({ candidates: async () => ([{ url: pdfUrl, host: 'h', label: '', score: 9 }]),
              bytes: async () => buf.slice(0) });

  for (const which of ['tbAccept', 'tbCancel', 'tbAgain']) {
    await T.find('X');
    await sleep(900);
    const before = T.state()[0];
    document.getElementById(which).click();
    await sleep(700);
    out[which + '_activeElement'] = (document.activeElement || {}).id || (document.activeElement || {}).tagName;
    // now try to write, the way a person would: just start typing
    const el0 = T.state()[0];
    typeReal('XYZ');
    await sleep(300);
    const after = T.state()[0];
    out[which + '_typingLands'] = after !== el0;
    if (which === 'tbAgain') { document.getElementById('tbCancel').click(); await sleep(600); }
  }
  T.stubNet(null);
  return JSON.stringify(out, null, 1);
};

// Do the app's OWN chrome buttons leave the writing surface unfocused too?
window.__chromeFocusProbe = async function () {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const T = window.PICA_API.test;
  const pages = document.getElementById('pages');
  await T.reset(); T.caret(0, 0); T.type('INT. ROOM - DAY'); T.esc();
  await sleep(300);
  const out = {};
  const typeReal = ch => {
    pages.dispatchEvent(new KeyboardEvent('keydown', { key: ch, bubbles: true, cancelable: true }));
    (document.activeElement || pages).dispatchEvent(new InputEvent('beforeinput',
      { inputType: 'insertText', data: ch, bubbles: true, cancelable: true }));
  };
  for (const id of ['zIn', 'zOut', 'railToggle', 'btnSb', 'btnAnnot']) {
    const b = document.getElementById(id);
    if (!b) { out[id] = 'missing'; continue; }
    pages.focus();
    const before = T.state()[0];
    b.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
    b.click();
    await sleep(250);
    typeReal('Q');
    await sleep(200);
    out[id] = { active: (document.activeElement || {}).id || (document.activeElement || {}).tagName,
                typingLands: T.state()[0] !== before };
    // undo any mode toggles
    if (id === 'btnSb' || id === 'btnAnnot') { b.click(); await sleep(200); }
    if (id === 'railToggle') { b.click(); await sleep(200); }
  }
  return JSON.stringify(out, null, 1);
};
