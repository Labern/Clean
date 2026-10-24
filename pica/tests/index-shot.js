// Right-click a script in the index and photograph the rail.
window.__indexShot = async function () {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const T = window.PICA_API.test;
  await T.reset();
  for (const name of ['THE HATEFUL EIGHT', 'MEMENTO', 'PULP FICTION']) {
    const id = await T.reset();
    const d = window.__pica.doc; d.title = name;
    window.PICA_API.save();
    await sleep(140);
  }
  await sleep(300);
  const rows = [...document.querySelectorAll('.doc-item')];
  const target = rows[1] || rows[0];
  target.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: 120, clientY: 200 }));
  await sleep(250);
  const rail = document.querySelector('#rail') || document.querySelector('.rail') || target.closest('aside') || target.parentElement;
  const r = rail.getBoundingClientRect();
  return JSON.stringify({ rows: rows.length, marked: document.querySelectorAll('.doc-item.menuing').length,
    clip: { x: Math.max(0, r.left - 4), y: Math.max(0, r.top - 4), width: Math.min(520, r.width + 8), height: Math.min(520, r.height + 8) } });
};
