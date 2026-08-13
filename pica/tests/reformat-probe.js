// Reformat must repair a script that is nearly right, and never make one worse.
window.__reformatProbe = async function (pdfUrl) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const T = window.PICA_API.test;
  const buf = await (await fetch(pdfUrl)).arrayBuffer();
  const out = {};
  T.stubNet({ candidates: async () => ([{ url: pdfUrl, host: 'h', label: '', score: 9 }]),
              bytes: async () => buf.slice(0) });
  await T.find('X');
  await sleep(1200);
  out.buttonPresent = !!document.getElementById('tbFix');
  const before = T.state().length;
  const tally = () => { const t = {}; for (const s of T.state()) { const k = s.slice(0, s.indexOf('|')); t[k] = (t[k]||0)+1; } return t; };
  out.before = tally();

  // rough it up the way a poor copy arrives: speech demoted to action, a slug lost,
  // a parenthetical sitting in an action element
  const els = window.__pica.doc.elements;
  let broke = 0;
  for (let i = 1; i < els.length; i++) {
    if (els[i].type === 'dialogue' && els[i-1].type === 'character' && broke < 120) { els[i].type = 'action'; broke++; }
    else if (els[i].type === 'scene' && broke < 160) { els[i].type = 'general'; broke++; }
    else if (els[i].type === 'paren' && broke < 200) { els[i].type = 'action'; broke++; }
  }
  out.damaged = tally();
  out.damagedScore = null;

  document.getElementById('tbFix').click();
  await sleep(900);
  out.after = tally();
  out.sameElementCount = T.state().length === before;
  out.noGeneralLeft = !out.after.general;
  out.barSaysSomething = (document.getElementById('tbFrom') || {}).textContent;
  // and running it on an already-good script must not damage it
  document.getElementById('tbFix').click();
  await sleep(700);
  out.idempotent = JSON.stringify(tally()) === JSON.stringify(out.after);
  document.getElementById('tbCancel').click();
  await sleep(600);
  T.stubNet(null);
  return JSON.stringify(out, null, 1);
};
