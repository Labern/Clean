// Photograph the studio card as the app actually opens it.
window.__cardShot = async function () {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const f = document.querySelector('iframe[aria-hidden]');
  const out = { present: !!f };
  out.stillThere = !!document.querySelector('iframe[aria-hidden]');
  out.clip = { x: 0, y: 0, width: 900, height: 620 };
  return JSON.stringify(out);
};
// and prove it removes itself
window.__cardGone = async function () {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const seenAtStart = !!document.querySelector('iframe[aria-hidden]');
  await sleep(3200);
  return JSON.stringify({ seenAtStart, gone: !document.querySelector('iframe[aria-hidden]'),
    overlaysLeft: document.querySelectorAll('iframe[aria-hidden]').length });
};
