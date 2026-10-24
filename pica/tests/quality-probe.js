// Given a rough copy and a clean one, which does it show?
window.__qualityProbe = async function (roughUrl, cleanUrl) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const T = window.PICA_API.test;
  const idx = () => JSON.parse(localStorage.getItem('pica.index') || '[]');
  const rough = await (await fetch(roughUrl)).arrayBuffer();
  const clean = await (await fetch(cleanUrl)).arrayBuffer();
  const out = {};

  // the rough copy is offered FIRST — it should not be what he ends up looking at
  T.stubNet({
    candidates: async () => ([
      { url: roughUrl, host: 'rough.example', label: '', score: 99 },
      { url: cleanUrl, host: 'clean.example', label: '', score: 50 },
    ]),
    bytes: async u => (u === roughUrl ? rough : clean).slice(0),
  });
  const before = idx().length;
  await T.find('Something');
  await sleep(1200);
  out.showing = window.__pica.doc.title;
  out.from = document.getElementById('tbFrom').textContent;
  out.meta = document.getElementById('tbMeta').textContent;
  out.indexHeld = idx().length === before;

  // only the rough one exists: it is still offered, with what is wrong with it stated
  T.stubNet({
    candidates: async () => ([{ url: roughUrl, host: 'rough.example', label: '', score: 99 }]),
    bytes: async () => rough.slice(0),
  });
  document.getElementById('tbCancel').click();
  await sleep(700);
  await T.find('Something');
  await sleep(1200);
  out.onlyRough_showing = window.__pica.doc.title;
  out.onlyRough_from = document.getElementById('tbFrom').textContent;
  out.onlyRough_barShown = document.getElementById('trialBar').hidden === false;
  document.getElementById('tbCancel').click();
  await sleep(600);
  T.stubNet(null);
  return JSON.stringify(out, null, 1);
};
