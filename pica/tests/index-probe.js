// The right-clicked row is marked, and the list animates into its new shape.
window.__indexProbe = async function () {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const T = window.PICA_API.test;
  window.confirm = () => true;
  for (const n of ['ONE', 'TWO', 'THREE']) { await T.reset(); T.caret(0,0); T.type('INT. ' + n + ' - DAY'); await sleep(200); }
  await sleep(400);
  const rows = () => [...document.querySelectorAll('#docList .doc-item')];
  const out = {};
  out.rowsHaveIds = rows().every(r => !!r.dataset.doc);

  // right-click the second row: it should mark itself, and only it
  const r2 = rows()[1];
  r2.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: 60, clientY: 140 }));
  await sleep(120);
  out.markedWhileOpen = document.querySelectorAll('#docList .doc-item.menuing').length;
  out.markedIsTheOneClicked = r2.classList.contains('menuing');

  // choosing Delete: the survivors should be mid-animation right after the rebuild
  const del = [...document.querySelectorAll('.pop *')].find(n => /^delete/i.test(n.textContent.trim()));
  del.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
  del.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
  await sleep(30);
  out.animatingAfterDelete = rows().filter(r => r.getAnimations && r.getAnimations().length).length;
  await sleep(500);
  out.markedAfterClose = document.querySelectorAll('#docList .doc-item.menuing').length;
  out.animationsFinished = rows().every(r => !r.getAnimations || r.getAnimations().every(a => a.playState !== 'running'));
  out.rowsLeft = rows().length;
  return JSON.stringify(out, null, 1);
};
