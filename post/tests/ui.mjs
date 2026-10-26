// node post/tests/ui.mjs [--shots dir] — drives the real app in Chromium
// against the fake iCloud, through the real bridge.

import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('playwright'); // pre-installed globally, not a dependency
import { FakeICloud } from './fake.mjs';
import { createServer, makeOpen } from '../bridge/node.mjs';
import { utf8ToBin } from '../bridge/mime.js';

const shots = process.argv.includes('--shots') ? process.argv[process.argv.indexOf('--shots') + 1] : null;
let pass = 0, fail = 0;
const ok = (v, name) => { v ? pass++ : fail++; if (!v) console.log(`✗ ${name}`); };
const crlf = (s) => utf8ToBin(s.replace(/\r?\n/g, '\r\n'));

const fake = await new FakeICloud().start();
const now = Date.now();
const people = [['Craig Federighi', 'craig@apple.com'], ['Jony', 'jony@lovefrom.com'], ['Eddy Cue', 'eddy@apple.com'], ['Lisa Jackson', 'lisa@apple.com'], ['Phil', 'phil@apple.com']];
const subjects = ['Keynote run-through moved to 3pm', 'Re: the new hinge', 'Dinner Thursday?', 'Q4 numbers — first look', 'Photos from the weekend', 'Your boarding pass', 'Contract signed ✍️', 'Quick question about the build'];
for (let i = 0; i < 60; i++) {
  const [n, e] = people[i % people.length];
  fake.add('INBOX', crlf(`From: ${n} <${e}>
To: Tim <tim@icloud.com>
Subject: ${subjects[i % subjects.length]}
Date: ${new Date(now - (60 - i) * 3.7 * 3600000).toUTCString()}
Message-ID: <ui${i}@apple.com>
Content-Type: text/plain; charset=utf-8

Hi Tim,

Following up on this — let me know what you think when you get a minute. Message ${i}.

https://example.com/doc/${i}

> Earlier message quoted here
>> and deeper still
`), i % 4 ? ['\\Seen'] : []);
}
fake.add('INBOX', crlf(`From: Apple <news@insideapple.apple.com>
To: tim@icloud.com
Subject: Introducing something new
Date: ${new Date(now - 600000).toUTCString()}
List-Unsubscribe: <https://apple.com/unsub>
Content-Type: text/html; charset=utf-8

<html><body><table width="640" style="width:640px"><tr><td><h1 style="font-family:sans-serif">Hello.</h1><p>Big news inside.</p><img src="https://example.com/track.gif" width="1" height="1"></td></tr></table></body></html>
`));
fake.add('Archive', crlf('From: Old <old@x.com>\r\nSubject: Archived thing\r\nDate: Mon, 1 Jan 2024 10:00:00 +0000\r\n\r\nold'), ['\\Seen']);

const server = createServer({ open: makeOpen({ insecure: true }), insecure: true, imap: { host: '127.0.0.1', port: fake.imapPort, tls: 'implicit' }, smtp: { host: '127.0.0.1', port: fake.smtpPort, tls: 'starttls' } });
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const url = `http://127.0.0.1:${server.address().port}/`;

const browser = await chromium.launch();
const errors = [];
try {
  // ---------- desktop ----------
  const ctx = await browser.newContext({ viewport: { width: 1360, height: 860 } });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error' && !/Content Security Policy|track\.gif|Failed to load resource/.test(m.text())) errors.push(m.text()); });
  await page.goto(url);
  await page.waitForSelector('#setup:not([hidden])');
  ok(await page.isHidden('#bridgeWrap'), 'same-origin bridge detected, no bridge field');
  await page.fill('[name=email]', 'tim@icloud.com');
  await page.fill('[name=password]', 'wrong-pass-word-xxxx');
  await page.click('#signIn');
  await page.waitForFunction(() => document.querySelector('#setupErr').textContent.length > 0);
  ok(/app-specific password/.test(await page.textContent('#setupErr')), 'wrong password explained');
  await page.fill('[name=password]', 'abcd efgh ijkl mnop'); // spaces as Apple displays them
  await page.fill('[name=name]', 'Tim Cook');
  await page.click('#signIn');
  await page.waitForSelector('.row');
  ok((await page.$$('.row')).length === 50, 'first page of 50');
  ok((await page.textContent('.row .who')).includes('Apple'), 'newest first');
  ok(/Inbox/.test(await page.textContent('#boxlist')) && /Archive/.test(await page.textContent('#boxlist')), 'mailboxes listed');
  ok((await page.textContent('.box.on .c')) === '16', 'unread count badge');
  if (shots) await page.screenshot({ path: `${shots}/desktop-inbox.png` });

  // newsletter: remote content blocked, scaled to fit
  await page.click('.row >> nth=0');
  await page.waitForSelector('.frame');
  ok(await page.isVisible('.banner'), 'remote content banner');
  const frame = page.frameLocator('.frame');
  ok((await frame.locator('h1').textContent()) === 'Hello.', 'html body rendered in sandbox');
  ok(await page.isVisible('.unsub'), 'unsubscribe link');
  await page.waitForTimeout(150);
  if (shots) await page.screenshot({ path: `${shots}/desktop-newsletter.png` });

  // plain text with quotes; opening marks read on the server
  const unreadRow = page.locator('.row.unread').first();
  const uid = +(await unreadRow.getAttribute('data-uid'));
  await unreadRow.click();
  await page.waitForSelector('.body-text');
  ok((await page.$$('.body-text .q .q')).length === 1, 'nested quote levels');
  ok(await page.isVisible('.body-text a[href^="https://example.com"]'), 'links linkified');
  await page.waitForTimeout(200);
  ok(fake.boxes.get('INBOX').msgs.find((m) => m.uid === uid).flags.has('\\Seen'), 'read persisted to server');
  ok((await page.textContent('.box.on .c')) === '14', 'unread count drops (newsletter + this one)');
  if (shots) await page.screenshot({ path: `${shots}/desktop-message.png` });

  // keyboard: flag, then j moves down, e archives
  await page.keyboard.press('s');
  await page.waitForTimeout(250);
  ok(fake.boxes.get('INBOX').msgs.find((m) => m.uid === uid).flags.has('\\Flagged'), 'S flags on server');
  ok(await page.isVisible(`.row[data-uid="${uid}"].flagged`), 'flag shown in list');
  await page.keyboard.press('e');
  await page.waitForTimeout(400);
  ok(!fake.boxes.get('INBOX').msgs.some((m) => m.uid === uid), 'E archives');
  ok(fake.boxes.get('Archive').msgs.length === 2, 'landed in Archive');
  ok(await page.isVisible('.row.sel'), 'next message selected after archive');

  // search
  await page.fill('#q', 'boarding');
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => document.querySelector('#searchCount').textContent.includes('result') && !document.querySelector('#searchCount').textContent.includes('Searching'));
  const hits = await page.$$eval('.row .subj span:first-child', (els) => els.map((e) => e.textContent));
  ok(hits.length > 0 && hits.every((h) => h === 'Your boarding pass'), 'search results');
  await page.click('#searchDone');
  ok((await page.$$('.row')).length >= 49, 'search cleared, list back');

  // infinite scroll
  await page.$eval('#listScroll', (s) => (s.scrollTop = s.scrollHeight));
  await page.waitForFunction(() => document.querySelectorAll('.row').length > 55);
  ok(true, 'scrolling loads the next page');

  // reply with autocomplete + undo send, then real send
  await page.click('.row >> nth=2');
  await page.waitForSelector('.body-text');
  await page.keyboard.press('r');
  await page.waitForSelector('#compose:not([hidden])');
  ok((await page.inputValue('#cSubject')).startsWith('Re: '), 'reply subject');
  ok((await page.inputValue('#cbody')).includes('wrote:\n\n> Hi Tim'), 'reply quotes original');
  await page.click('#cCcBtn');
  await page.type('#cCc', 'jon');
  await page.waitForSelector('.sugg li');
  ok((await page.textContent('.sugg li')).includes('jony@lovefrom.com'), 'autocomplete from correspondents');
  await page.keyboard.press('Enter');
  ok((await page.inputValue('#cCc')).includes('Jony <jony@lovefrom.com>'), 'suggestion inserted');
  await page.focus('#cbody');
  await page.keyboard.press('Home');
  await page.keyboard.type('Sounds good — see you there.');
  if (shots) await page.screenshot({ path: `${shots}/desktop-compose.png` });
  await page.keyboard.press('Control+Enter');
  await page.waitForSelector('#toast >> text=Undo');
  await page.click('#toast button');
  await page.waitForSelector('#compose:not([hidden])');
  ok((await page.inputValue('#cbody')).startsWith('Sounds good'), 'undo send restores the draft');
  ok(fake.sent.length === 0, 'nothing sent after undo');
  await page.evaluate(() => { S.prefs.undo = 0; });
  await page.click('#cSend');
  await page.waitForFunction(() => document.querySelector('#toast')?.textContent.includes('Sent'), null, { timeout: 8000 });
  ok(fake.sent.length === 1, 'sent over SMTP');
  ok(fake.sent[0].rcpts.includes('jony@lovefrom.com'), 'cc recipient');
  ok(/In-Reply-To: <ui\d+@apple\.com>/.test(fake.sent[0].data), 'threading headers');
  ok(fake.boxes.get('Sent Messages').msgs.length === 1, 'copy filed in Sent');

  // draft save → appears in Drafts → reopen → send deletes it
  await page.keyboard.press('c');
  await page.fill('#cTo', 'eddy@apple.com');
  await page.fill('#cSubject', 'Draft idea');
  await page.fill('#cbody', 'Half-finished thought');
  await page.click('#cCancel');
  await page.click('.veil .opt[data-id="save"]');
  await page.waitForFunction(() => document.querySelector('#toast')?.textContent.includes('Draft saved'));
  ok(fake.boxes.get('Drafts').msgs.length === 1, 'draft stored on server');
  await page.click('.box[data-path="Drafts"]');
  await page.waitForSelector('.row');
  ok((await page.textContent('.row .who')).includes('eddy@apple.com'), 'drafts list shows recipient');
  await page.click('.row');
  await page.waitForSelector('#compose:not([hidden])');
  ok((await page.inputValue('#cbody')).includes('Half-finished thought'), 'draft reopens in compose');
  await page.click('#cSend');
  await page.waitForFunction(() => document.querySelector('#toast')?.textContent.includes('Sent'), null, { timeout: 8000 });
  ok(fake.boxes.get('Drafts').msgs.length === 0, 'sending a draft removes it');

  // delete from Archive → Trash
  await page.click('.box[data-path="Archive"]');
  await page.waitForSelector('.row');
  await page.click('.row');
  await page.keyboard.press('Backspace');
  await page.waitForTimeout(400);
  ok(fake.boxes.get('Deleted Messages').msgs.length === 1, 'delete → Trash');
  ok(errors.length === 0, 'no page errors: ' + errors.join(' | '));
  await ctx.close();

  // ---------- iPhone ----------
  for (const scheme of ['light', 'dark']) {
    const m = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, colorScheme: scheme });
    const p = await m.newPage();
    p.on('pageerror', (e) => errors.push(e.message));
    await p.goto(url);
    await p.fill('[name=email]', 'tim');
    await p.fill('[name=password]', 'abcd-efgh-ijkl-mnop');
    if (shots && scheme === 'light') await p.screenshot({ path: `${shots}/phone-setup.png` });
    await p.click('#signIn');
    await p.waitForSelector('.row');
    await p.waitForTimeout(400);
    ok(await p.evaluate(() => document.body.dataset.view === 'list'), `phone opens on list (${scheme})`);
    const vw = await p.evaluate(() => document.documentElement.scrollWidth);
    ok(vw <= 390, `no horizontal overflow (${scheme})`);
    if (shots) await p.screenshot({ path: `${shots}/phone-inbox-${scheme}.png` });
    await p.locator('.row').nth(2).click();
    await p.waitForSelector('.body-text');
    await p.waitForTimeout(400);
    ok(await p.evaluate(() => document.body.dataset.view === 'msg'), 'tapping opens message view');
    if (shots) await p.screenshot({ path: `${shots}/phone-message-${scheme}.png` });
    await p.click('#toList');
    await p.waitForTimeout(400);
    await p.click('#toBoxes');
    await p.waitForTimeout(400);
    if (shots) await p.screenshot({ path: `${shots}/phone-mailboxes-${scheme}.png` });
    ok(await p.isVisible('#boxlist .box'), 'mailboxes view');
    await m.close();
  }
  ok(errors.length === 0, 'no page errors on phone: ' + errors.join(' | '));
} finally {
  await browser.close();
  server.close();
  fake.stop();
}
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
