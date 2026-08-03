window.__crProbe = async function () {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const f = document.querySelector('iframe[aria-hidden]');
  if (!f) return JSON.stringify({ err: 'no card' });
  await sleep(500);
  const d = f.contentDocument;
  const card = d.querySelector('.card').getBoundingClientRect();
  const cr = d.getElementById('cr').getBoundingClientRect();
  const cs = d.defaultView.getComputedStyle(d.getElementById('cr'));
  return JSON.stringify({ cardRight: card.right, crRight: cr.right, crWidth: cr.width,
    position: cs.position, right: cs.right });
};
