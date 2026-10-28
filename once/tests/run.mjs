// Once test suite: the engine against a zoo of real-world form shapes, then
// the packed extension end to end in Chromium (fill on sight, fill on click,
// hands off what you edited, email swap, setup handoff).
//   node once/tests/run.mjs
import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('playwright');
import { createServer } from 'node:http';
import { readFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ONCE = join(dirname(fileURLToPath(import.meta.url)), '..');
const P = { first: 'Ada', last: 'Lovelace', line1: '12 Ockham Road', line2: '', city: 'Ripley', county: 'Surrey',
  postcode: 'GU23 6AA', country: 'United Kingdom', emails: ['ada@example.com', 'ada@example.org'] };
const V = { first: 'Ada', last: 'Lovelace', name: 'Ada Lovelace', email: 'ada@example.com', line1: '12 Ockham Road',
  houseNo: '12', street: 'Ockham Road', city: 'Ripley', county: 'Surrey', postcode: 'GU23 6AA',
  fulladdress: '12 Ockham Road\nRipley\nSurrey\nGU23 6AA' };

let pass = 0, fail = 0;
const ok = (c, m) => { c ? pass++ : (fail++, console.log('  ✗ ' + m)); };

const srv = createServer((q, s) => {
  try {
    const f = join(ONCE, decodeURIComponent(q.url.split('?')[0]).replace(/\/$/, '/index.html'));
    const body = readFileSync(f);
    s.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript' }[extname(f)] || 'application/octet-stream' });
    s.end(body);
  } catch { s.writeHead(404); s.end(); }
}).listen(0);
const BASE = `http://localhost:${srv.address().port}`;

// what every [data-x] field holds vs what it should
const audit = (page, only) => page.evaluate(({ V, only }) => {
  only = only && (0, eval)(only);
  const out = [];
  const all = [...document.querySelectorAll('[data-x]'), ...document.querySelector('my-field').shadowRoot.querySelectorAll('[data-x]')];
  for (const el of all) {
    const form = el.closest('form,section') || el.getRootNode().host.closest('form');
    if (only && !only(form)) continue;
    const x = el.dataset.x, want = x in V ? V[x] : x;
    const got = el.tagName === 'SELECT' ? (x === 'GB' ? el.value : el.options[el.selectedIndex].text) : el.value;
    out.push({ id: form.id + ' ' + (el.name || el.id), want, got });
  }
  return out;
}, { V, only: only && only.toString() }).then(r => r);

function check(rows, label) {
  for (const r of rows) ok(r.got === r.want, `${label}: ${r.id} = ${JSON.stringify(r.got)}, want ${JSON.stringify(r.want)}`);
}

const browser = await chromium.launch();

// ---- 1. engine, as the bookmarklet runs it (fill everything, one tap)
{
  const page = await browser.newPage();
  await page.goto(BASE + '/tests/forms.html');
  const bm = readFileSync(join(ONCE, 'bookmarklet.min.js'), 'utf8').trim();
  await page.evaluate(`(${bm})(${JSON.stringify(P)})`);
  check(await audit(page), 'bookmarklet');
  const rs = await page.evaluate(() => window.reactState);
  ok(rs.firstname === 'Ada' && rs.emailaddress === 'ada@example.com', 'react: controlled inputs saw the change ' + JSON.stringify(rs));
  // second tap swaps the email everywhere
  await page.evaluate(`(${bm})(${JSON.stringify(P)})`);
  const emails = await page.$$eval('input[type=email],input[name=email],input[name=login]', els => els.map(e => e.value).filter(Boolean));
  ok(emails.length && emails.every(e => e === 'ada@example.org'), 'second tap swaps to the other email: ' + emails);
  ok(await page.$eval('[name=friend_email]', e => e.value === ''), "swap leaves someone else's email alone");
  await page.close();
}

// ---- 2. the bookmarklet as a real javascript: URL survives encoding
{
  const page = await browser.newPage();
  await page.goto(BASE + '/tests/forms.html');
  const bm = readFileSync(join(ONCE, 'bookmarklet.min.js'), 'utf8').trim();
  const url = 'javascript:' + encodeURIComponent(`(${bm})(${JSON.stringify(P)})`);
  await page.evaluate(u => { eval(decodeURIComponent(u.slice(11))); }, url);
  ok(await page.$eval('#gov [name=address-postcode]', e => e.value) === 'GU23 6AA', 'javascript: URL round-trips');
  await page.close();
}
await browser.close();

// ---- 3. the extension, end to end
{
  const ctx = await chromium.launchPersistentContext(mkdtempSync(join(tmpdir(), 'once-')), {
    headless: true, channel: 'chromium', args: [`--disable-extensions-except=${join(ONCE, 'extension')}`, `--load-extension=${join(ONCE, 'extension')}`],
  });
  let [sw] = ctx.serviceWorkers();
  if (!sw) sw = await ctx.waitForEvent('serviceworker');
  await sw.evaluate(p => chrome.storage.local.set({ profile: p }), P);

  const page = await ctx.newPage();
  await page.goto(BASE + '/tests/forms.html');
  await page.waitForTimeout(900);
  // on sight: every eager form is filled, the data-eager="no" ones are untouched
  check(await audit(page, f => f.dataset.eager !== 'no'), 'ext on-sight');
  const lazy = await page.$$eval('form[data-eager=no] [data-x]', els => els.map(e => e.value).join(''));
  ok(lazy === '', 'ext: nothing filled unprompted in non-eager forms: ' + lazy);

  // on click: the lone newsletter email fills when focused
  await page.click('[name=subscribe]');
  ok(await page.$eval('[name=subscribe]', e => e.value) === 'ada@example.com', 'ext: click fills a lone email');
  ok(await page.$eval('[name=friend_email]', e => e.value) === '', 'ext: never fills a friend');

  // the user clears a field → it stays cleared
  await page.fill('#gov [name=address-town]', '');
  await page.click('#gov [name=address-county]');
  await page.evaluate(() => document.body.appendChild(document.createElement('div')));
  await page.waitForTimeout(600);
  ok(await page.$eval('#gov [name=address-town]', e => e.value) === '', 'ext: a field you cleared is left cleared');

  // late-rendered form (SPA) fills on sight
  await page.evaluate(() => {
    const f = document.createElement('form'); f.id = 'late';
    f.innerHTML = '<input name="first_name"><input name="surname"><input name="postcode">';
    document.body.appendChild(f);
  });
  await page.waitForTimeout(800);
  ok(await page.$eval('#late [name=surname]', e => e.value) === 'Lovelace', 'ext: late SPA form fills on sight');

  // swap via the chip: the whole page moves and the site remembers
  await page.click('#signup [name=email]');
  await page.waitForTimeout(100);
  await page.locator('once-chip').click({ position: { x: 5, y: 5 } }).catch(e => ok(false, 'chip click ' + e.message));
  await page.waitForTimeout(300);
  ok(await page.$eval('#signup [name=email_confirm]', e => e.value) === 'ada@example.org', 'ext: chip swaps email + confirm');
  const sites = await sw.evaluate(() => chrome.storage.local.get('sites'));
  ok(sites.sites && sites.sites.localhost === 1, 'ext: site remembers the chosen email ' + JSON.stringify(sites));

  // a fresh visit to the same site uses the remembered email
  const p2 = await ctx.newPage();
  await p2.goto(BASE + '/tests/forms.html');
  await p2.waitForTimeout(900);
  ok(await p2.$eval('#login [name=login]', e => e.value) === 'ada@example.org', 'ext: login uses the email this site knows you by');

  // off on this site
  await sw.evaluate(() => chrome.storage.local.set({ off: ['localhost'] }));
  const p3 = await ctx.newPage();
  await p3.goto(BASE + '/tests/forms.html');
  await p3.waitForTimeout(900);
  ok(await p3.$eval('#gov [name=address-postcode]', e => e.value) === '', 'ext: off-on-this-site is respected');

  // the setup page hands your details to the extension (served at its real URL)
  await sw.evaluate(() => chrome.storage.local.clear());
  await ctx.route('https://labern.github.io/Clean/once/**', async r => {
    const path = new URL(r.request().url()).pathname.replace('/Clean/once/', '') || 'index.html';
    try { await r.fulfill({ body: readFileSync(join(ONCE, path)), contentType: path.endsWith('.html') ? 'text/html' : 'text/javascript' }); }
    catch { await r.fulfill({ status: 404 }); }
  });
  const link = 'https://labern.github.io/Clean/once/#p=' + Buffer.from(JSON.stringify(P)).toString('base64url');
  const sp = await ctx.newPage();
  await sp.goto(link);
  await sp.waitForTimeout(1200);
  ok(!sp.url().includes('#p='), 'setup: the private link wipes itself from the address bar');
  ok(await sp.$eval('#me [name=postcode]', e => e.value) === 'GU23 6AA', 'setup: link fills the details form');
  const stored = await sw.evaluate(() => chrome.storage.local.get('profile'));
  ok(stored.profile && stored.profile.emails[1] === 'ada@example.org', 'setup: details handed to the extension');
  ok(await sp.$eval('#me [name=first]', e => e.value) === 'Ada', "setup: extension doesn't fill the setup form itself");
  ok(/extension connected/i.test(await sp.textContent('#extStatus')), 'setup: page confirms the extension');
  await sp.reload(); await sp.waitForTimeout(1200);
  ok(await sp.$eval('#try [name=postcode]', e => e.value) === 'GU23 6AA', 'setup: demo form fills on sight');
  const href = await sp.$eval('#bmLink', a => a.href);
  ok(href.startsWith('javascript:') && href.includes('Lovelace'), 'setup: bookmark carries the profile');
  await ctx.close();
}

srv.close();
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
