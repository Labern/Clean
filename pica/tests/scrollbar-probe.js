// The scrollbar: it shows while he scrolls and gets out of the way after.
//
// It drives the real 'scroll' event rather than assigning scrollTop — the app
// ignores a programmatic scrollTop (verified in Chrome: 0 scroll events, value
// unchanged), so a probe written that way tests nothing and quietly passes.
window.__scrollbar = async function () {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await window.PICA_API.test.reset();
  await sleep(500);

  const c = document.querySelector('#canvas');
  const bar = document.querySelectorAll('.sbar.v')[0];
  const thumb = bar && bar.querySelector('.sthumb');
  const fail = [];
  if (!bar) return JSON.stringify({ ok: false, fail: ['no scrollbar in the DOM'] });

  // 1. it must cost no layout width — the paper and the title's cue-column
  //    alignment must not move when the bar shows
  if (c.offsetWidth - c.clientWidth !== 0) fail.push('bar is taking layout width');

  // 2. invisible at rest
  if (+getComputedStyle(bar).opacity !== 0) fail.push('visible while idle');

  // 3. a scroll brings it up
  c.dispatchEvent(new Event('scroll'));
  await sleep(200);
  const shown = bar.classList.contains('on');
  if (!shown) fail.push('did not appear on scroll');

  // 4. parked at the right edge of the canvas, proportional to the content
  const r = c.getBoundingClientRect(), t = thumb.getBoundingClientRect();
  const gap = r.right - t.right;
  if (gap < 2 || gap > 8) fail.push('thumb not at the right edge (gap ' + gap.toFixed(1) + ')');
  if (t.width < 3 || t.width > 10) fail.push('thumb width ' + t.width);
  if (c.scrollHeight > c.clientHeight && t.height >= r.height) fail.push('thumb not proportional');

  // 5. and it leaves
  await sleep(1400);
  if (bar.classList.contains('on')) fail.push('never faded out');
  if (+getComputedStyle(bar).opacity !== 0) fail.push('still visible after idle');

  return JSON.stringify({ ok: fail.length === 0, fail,
    thumb: { w: +t.width.toFixed(1), h: +t.height.toFixed(1), gap: +gap.toFixed(1) } });
};
