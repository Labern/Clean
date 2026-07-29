// Does deleting a script leave the index, the sidebar, and the database — and stay gone?
// Everything goes through the app's own surfaces: no internals are reached into.
window.__deleteProbe = async function () {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const T = window.PICA_API.test;
  window.confirm = () => true;              // the dialog is not what is under test
  const index = () => JSON.parse(localStorage.getItem('pica.index') || '[]');
  const rows = () => [...document.querySelectorAll('#docList .doc-item')];
  const titles = () => rows().map(r => r.querySelector('.ttl').textContent.trim());

  // three scripts with real words in them, so nothing can call them empty
  const made = [];
  for (const name of ['ALPHA', 'BETA', 'GAMMA']) {
    const id = await T.reset();
    T.caret(0, 0);
    T.type('INT. ' + name + ' ROOM - DAY');
    made.push({ id, name });
    await sleep(250);
  }
  await sleep(500);

  const before = index();
  const target = before.find((d, i) => i === 1) || before[0];   // the middle one
  const idxBefore = before.map(d => d.id);
  const titlesBefore = titles();

  // right-click that row and choose Delete, exactly as he does
  const row = rows()[idxBefore.indexOf(target.id)];
  if (!row) return JSON.stringify({ error: 'target row not found', idxBefore, titlesBefore });
  row.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: 60, clientY: 140 }));
  await sleep(200);
  const menu = [...document.querySelectorAll('.pop *')];
  const del = menu.find(n => /^delete/i.test(n.textContent.trim()));
  if (!del) return JSON.stringify({ error: 'no Delete item', menu: menu.map(n => n.textContent.trim()).slice(0, 14) });
  del.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
  del.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
  await sleep(900);

  const afterIdx = index().map(d => d.id);
  const afterTitles = titles();

  // is it still in the database?
  const stillInDb = await new Promise(res => {
    const rq = indexedDB.open('pica');
    rq.onsuccess = () => {
      const db = rq.result;
      try {
        const tx = db.transaction('kv', 'readonly').objectStore('kv').getAllKeys();
        tx.onsuccess = () => res(tx.result.map(String).filter(k => k.startsWith('doc.')));
        tx.onerror = () => res(['<keys unreadable>']);
      } catch (e) { res(['<' + e + '>']); }
    };
    rq.onerror = () => res(['<db unopenable>']);
  });

  return JSON.stringify({
    deleted: target.id, deletedTitle: target.title,
    idxBefore, titlesBefore,
    idxAfter: afterIdx, titlesAfter: afterTitles,
    goneFromIndex: !afterIdx.includes(target.id),
    goneFromSidebar: afterTitles.length === titlesBefore.length - 1,
    dbDocKeys: stillInDb, stillInDb: stillInDb.includes('doc.' + target.id),
  }, null, 1);
};

// The way he actually deletes: the script that is open, then the next, then the rest.
window.__deleteAllProbe = async function () {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const T = window.PICA_API.test;
  window.confirm = () => true;
  const index = () => JSON.parse(localStorage.getItem('pica.index') || '[]');
  const rows = () => [...document.querySelectorAll('#docList .doc-item')];
  const log = [];

  for (const name of ['ALPHA', 'BETA', 'GAMMA']) {
    await T.reset(); T.caret(0, 0); T.type('INT. ' + name + ' - DAY'); await sleep(250);
  }
  await sleep(400);
  log.push('start: index=' + index().length + ' rows=' + rows().length + ' open=' + window.__pica.docId);

  for (let pass = 0; pass < 6; pass++) {
    const r = rows();
    if (!r.length) { log.push('pass ' + pass + ': no rows left'); break; }
    // always delete the row that is currently open, if it is showing
    const open = window.__pica.docId;
    const idx = index();
    const openRow = r[idx.findIndex(d => d.id === open)] || r[0];
    openRow.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: 60, clientY: 140 }));
    await sleep(150);
    const del = [...document.querySelectorAll('.pop *')].find(n => /^delete/i.test(n.textContent.trim()));
    if (!del) { log.push('pass ' + pass + ': no Delete item'); break; }
    del.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
    del.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
    await sleep(1200);                       // past the 700ms save debounce
    log.push('pass ' + pass + ': index=' + index().length + ' rows=' + rows().length
      + ' titles=[' + index().map(d => d.title).join(',') + ']');
  }
  // let every debounced write land, then look again
  await sleep(2000);
  log.push('settled: index=' + index().length + ' rows=' + rows().length
    + ' titles=[' + index().map(d => d.title).join(',') + ']');
  return JSON.stringify({ log }, null, 1);
};

// After an import settles: what does the sidebar say, is anything drawn, and is the
// title still on the cue axis?
window.__afterImportProbe = async function (url) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await window.PICA_API.importUrl(url, 'ThereWillBeBlood.pdf');
  for (let i = 0; i < 600; i++) {
    const d = window.__pica && window.__pica.doc;
    if (d && d.elements.length > 1) break;
    await sleep(50);
  }
  const snap = () => {
    const ix = JSON.parse(localStorage.getItem('pica.index') || '[]');
    const cur = ix.find(d => d.id === window.__pica.docId);
    return {
      resCount: window.__pica.res ? window.__pica.res.count : null,
      indexPages: cur ? cur.pages : null,
      indexTitle: cur ? cur.title : null,
      sidebar: [...document.querySelectorAll('#docList .doc-item')]
        .map(r => r.querySelector('.ttl').textContent.trim() + ' ' + r.querySelector('.pg').textContent.trim()),
      drawnPages: document.querySelectorAll('.pageWrap').length,
      drawnLines: document.querySelectorAll('#pages div[data-el]').length,
      titleOnAxis: window.PICA_API.test.titleDelta(),
      innerW: innerWidth, mobileBranch: matchMedia('(max-width: 880px)').matches,
      titleLeft: (document.getElementById('docTitle')||{style:{}}).style.left,
    };
  };
  const immediately = snap();
  await sleep(1500);
  const settled = snap();
  return JSON.stringify({ immediately, settled }, null, 1);
};

// The honest title check: compare the title's centre with where the character cues are
// actually DRAWN on the page, not with the same formula the code uses to place it.
window.__titleAxisProbe = async function (url) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  if (url) {
    await window.PICA_API.importUrl(url, 'ThereWillBeBlood.pdf');
    for (let i = 0; i < 600; i++) {
      const d = window.__pica && window.__pica.doc;
      if (d && d.elements.length > 1) break;
      await sleep(50);
    }
  }
  await sleep(600);
  const S = window.__pica;
  // scroll until some cues are on screen
  const c = document.getElementById('canvas');
  for (let pass = 0; pass < 30; pass++) {
    const cues = [...document.querySelectorAll('#pages div[data-el]')]
      .filter(d => { const el = S.doc.elements.find(e => e.id === d.dataset.el); return el && el.type === 'character' && !el.dual; });
    if (cues.length >= 3) {
      const t = document.getElementById('docTitle').getBoundingClientRect();
      const centres = cues.map(d => { const r = d.getBoundingClientRect(); return r.left + r.width / 2; });
      const mean = centres.reduce((a, b) => a + b, 0) / centres.length;
      return JSON.stringify({
        cuesSeen: cues.length,
        cueTexts: cues.slice(0, 4).map(d => d.textContent.trim()),
        drawnCueCentre: +mean.toFixed(1),
        titleCentre: +(t.left + t.width / 2).toFixed(1),
        offBy: +((t.left + t.width / 2) - mean).toFixed(1),
        spreadOfCueCentres: +(Math.max(...centres) - Math.min(...centres)).toFixed(1),
        formulaSaysOnAxis: window.PICA_API.test.titleDelta(),
      }, null, 1);
    }
    c.scrollTop += 700;
    await sleep(120);
  }
  return JSON.stringify({ error: 'never found 3 cues on screen' });
};

// What actually surrounds a transition in the imported script?
window.__cutToProbe = async function (url) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await window.PICA_API.importUrl(url, 'ThereWillBeBlood.pdf');
  for (let i = 0; i < 600; i++) {
    const d = window.__pica && window.__pica.doc;
    if (d && d.elements.length > 1) break;
    await sleep(50);
  }
  const els = window.__pica.doc.elements;
  const out = [];
  let found = 0;
  for (let i = 0; i < els.length && found < 4; i++) {
    if (!/^(CUT TO|DISSOLVE TO|LONG DISSOLVE TO)/i.test(els[i].text.trim())) continue;
    found++;
    for (let j = Math.max(0, i - 2); j <= Math.min(els.length - 1, i + 3); j++)
      out.push((j === i ? '>> ' : '   ') + j + ' ' + els[j].type +
        ' sb=' + (els[j].spaceBefore == null ? '-' : els[j].spaceBefore) +
        ' len=' + els[j].text.length + ' :: ' + JSON.stringify(els[j].text.slice(0, 44)));
    out.push('');
  }
  const empties = els.filter(e => !e.text.trim()).length;
  return JSON.stringify({ emptyElements: empties, around: out }, null, 1);
};
