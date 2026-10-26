// Render docs/install.html → docs/GT7-Endgame-Install.pdf (Chromium print).
const { chromium } = require('playwright');
const path = require('path');
(async () => {
  const b = await chromium.launch(), p = await b.newPage();
  await p.goto('file://' + path.resolve(__dirname, '../docs/install.html'), { waitUntil: 'networkidle' });
  await p.evaluate(() => document.fonts.ready);
  await p.pdf({ path: path.resolve(__dirname, '../docs/GT7-Endgame-Install.pdf'), format: 'A4', printBackground: true, preferCSSPageSize: true });
  await b.close();
})();
