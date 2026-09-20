import { chromium } from 'playwright-core';
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args:['--no-sandbox','--font-render-hinting=none','--force-color-profile=srgb'] });
const p = await b.newPage({ viewport: { width: 794, height: 1123 }, deviceScaleFactor: 3 });
await p.goto('file://' + process.cwd() + '/roadmap.built.html', { waitUntil: 'load' });
await p.evaluate(() => document.fonts.ready);
const m = await p.evaluate(() => {
  const mm = 96/25.4;
  const pg = document.querySelector('.page');
  const last = document.querySelector('footer');
  const r = last.getBoundingClientRect();
  return {
    bodyScroll: (document.body.scrollHeight/mm).toFixed(2),
    pageH: (pg.getBoundingClientRect().height/mm).toFixed(2),
    footerBottom: (r.bottom/mm).toFixed(2),
    gridH: (document.querySelector('.grid').getBoundingClientRect().height/mm).toFixed(2),
    stepHs: [...document.querySelectorAll('.step')].map(s=>(s.getBoundingClientRect().height/mm).toFixed(1)),
  };
});
console.log(JSON.stringify(m,null,1));
await p.pdf({ path: 'EY-Manager-to-Director.pdf', printBackground: true, preferCSSPageSize: true });
await p.screenshot({ path: 'preview.png', fullPage: false });
await b.close();
