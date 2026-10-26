// node post/tests/run.mjs — unit tests for MIME/IMAP parsing, then the whole
// bridge end to end over real sockets against a fake iCloud.

import { FakeICloud } from './fake.mjs';
import { createServer, makeOpen } from '../bridge/node.mjs';
import {
  parseMime, extractContent, decodeWords, parseStructured, parseAddresses, buildMessage, qpDecode,
  mutf7Decode, mutf7Encode, utf8ToBin, header, encodeWord,
} from '../bridge/mime.js';
import { tokenize, fetchMap } from '../bridge/protocol.js';
import { htmlToText } from '../bridge/api.js';

let pass = 0, fail = 0;
const eq = (a, b, name) => {
  const ok = JSON.stringify(a) === JSON.stringify(b);
  ok ? pass++ : fail++;
  if (!ok) console.log(`✗ ${name}\n    got      ${JSON.stringify(a)}\n    expected ${JSON.stringify(b)}`);
};
const ok = (v, name) => eq(!!v, true, name);
const crlf = (s) => s.replace(/\r?\n/g, '\r\n');
const bin = utf8ToBin;

// ---- headers ------------------------------------------------------------------
// One "é" split across two base64 words (bytes C3 | A9): must decode as é.
eq(decodeWords('=?UTF-8?B?Y2Fmw6k=?= =?UTF-8?B?w6k=?='), 'caféé', 'adjacent encoded words concatenate');
eq(decodeWords('=?UTF-8?B?Y2Fmww==?= =?UTF-8?B?qQ==?='), 'café', 'multibyte char split across words');
eq(decodeWords('=?iso-8859-1?Q?Caf=E9_cr=E8me?= and more'), 'Café crème and more', 'Q encoding + trailing text');
eq(decodeWords('Re: =?UTF-8?Q?=F0=9F=8E=89?= party'), 'Re: 🎉 party', 'emoji in Q word');
eq(decodeWords('=?utf-8*en?Q?hi?='), 'hi', 'RFC 2231 language tag on word');
eq(decodeWords(encodeWord('Réunion — 東京 🎌 '.repeat(4))), 'Réunion — 東京 🎌 '.repeat(4), 'encodeWord round-trips long unicode');
eq(parseStructured(`attachment; filename*0*=utf-8''%E6%9D%B1; filename*1*=%E4%BA%AC.pdf`).params.filename, '東京.pdf', 'RFC 2231 continuation filename');
eq(parseStructured('text/plain; charset="UTF-8"; format=flowed').params, { charset: 'UTF-8', format: 'flowed' }, 'quoted params');
eq(parseStructured('attachment; filename="=?UTF-8?B?w6l0w6kuanBn?="').params.filename, 'été.jpg', 'RFC 2047 inside filename (Gmail/Outlook)');
eq(parseStructured('application/pdf; name="a;b.pdf"').params.name, 'a;b.pdf', 'semicolon inside quotes');
eq(parseAddresses('"Cook, Tim" <tim@apple.com>, jony@lovefrom.com, =?UTF-8?B?w4lsb2RpZQ==?= <e@x.fr>'),
  [{ name: 'Cook, Tim', email: 'tim@apple.com' }, { name: '', email: 'jony@lovefrom.com' }, { name: 'Élodie', email: 'e@x.fr' }], 'address list with comma in name');
eq(parseAddresses('undisclosed-recipients:;'), [], 'empty group');
eq(parseAddresses('Team: a@x.com, b@x.com;'), [{ name: '', email: 'a@x.com' }, { name: '', email: 'b@x.com' }], 'group syntax');
eq(mutf7Decode('Receipts &AMk-t&AOk-'), 'Receipts Été', 'modified UTF-7 decode');
eq(mutf7Encode('Été & co'), '&AMk-t&AOk- &- co', 'modified UTF-7 encode');
eq(mutf7Decode(mutf7Encode('日本語/Ünïcødé')), '日本語/Ünïcødé', 'mUTF-7 round trip');
eq(qpDecode('caf=C3=A9 soft=\r\nbreak'), bin('café softbreak'), 'quoted-printable');

// ---- IMAP tokenizer -----------------------------------------------------------
{
  const t = tokenize('* 12 FETCH (UID 99 FLAGS (\\Seen $Junk) BODY[1]<0> \0 ENVELOPE ("Mon" NIL (("A \\"B\\"" NIL "a" "x.com")) NIL))', ['hello\r\nworld']);
  const f = fetchMap(t[3]);
  eq([t[0], t[1], t[2]], ['*', '12', 'FETCH'], 'untagged prefix');
  eq(f.UID, '99', 'uid');
  eq(f.FLAGS, ['\\Seen', '$Junk'], 'flags list');
  eq(f['BODY[1]<0>'], 'hello\r\nworld', 'literal in place');
  eq(f.ENVELOPE[2][0][0], 'A "B"', 'escaped quote');
  eq(f.ENVELOPE[1], null, 'NIL');
  eq(tokenize('* OK [PERMANENTFLAGS (\\Seen \\*)] Limited')[2], '[PERMANENTFLAGS (\\Seen \\*)]', 'bracketed resp code atom');
  eq(tokenize('* 1 FETCH (BODY[HEADER.FIELDS (DATE FROM)] "x")')[3][0], 'BODY[HEADER.FIELDS (DATE FROM)]', 'section with spaces');
}

// ---- MIME bodies ----------------------------------------------------------------
const alt = crlf(`From: "Craig" <craig@apple.com>
To: tim@icloud.com
Subject: =?UTF-8?Q?Caf=C3=A9?= tomorrow
Date: Mon, 26 Oct 2026 09:00:00 +0000
Message-ID: <alt-1@apple.com>
MIME-Version: 1.0
Content-Type: multipart/alternative; boundary="b1"

preamble is ignored
--b1
Content-Type: text/plain; charset=utf-8
Content-Transfer-Encoding: quoted-printable

Lunch at the caf=C3=A9?
> old quoted line
--b1
Content-Type: text/html; charset=utf-8
Content-Transfer-Encoding: base64

${btoa(bin('<html><head><style>p{color:red}</style></head><body><p>Lunch at the café?</p></body></html>'))}
--b1--
epilogue too
`);
{
  const r = parseMime(alt);
  eq(header(r.headers, 'subject'), 'Café tomorrow', 'subject decodes');
  eq(r.children.map((c) => c.path), ['1', '2'], 'IMAP part numbers');
  const c = extractContent(r);
  ok(c.html.includes('Lunch at the café?'), 'alternative picks html, decoded base64 utf-8');
  eq(c.text, '', 'no stray text from the unpicked alternative');
  eq(c.attachments, [], 'no attachments');
  eq(htmlToText(c.html).replace(/\s+/g, ' ').trim(), 'Lunch at the café?', 'html → text strips style');
}

// Apple Mail: plain text, an inline photo in the middle, then more text, plus a PDF.
const png = atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');
const appleMixed = crlf(`From: Tim <tim@icloud.com>
To: craig@apple.com
Subject: Photos
Content-Type: multipart/mixed; boundary="Apple-Mail=_A"

--Apple-Mail=_A
Content-Type: text/plain; charset=us-ascii

Look at this:
--Apple-Mail=_A
Content-Type: image/png; name="dot.png"
Content-Disposition: inline; filename="dot.png"
Content-Transfer-Encoding: base64

${btoa(png)}
--Apple-Mail=_A
Content-Type: text/plain; charset=us-ascii

Nice, right?
--Apple-Mail=_A
Content-Type: application/pdf; name="=?UTF-8?B?UmVjZWlwdCDDqXTDqS5wZGY=?="
Content-Disposition: attachment;
	filename*=utf-8''Receipt%20%C3%A9t%C3%A9.pdf
Content-Transfer-Encoding: base64

JVBERi0xLjQK
--Apple-Mail=_A--
`);
{
  const c = extractContent(parseMime(appleMixed));
  ok(c.html && c.html.indexOf('Look at this') < c.html.indexOf('data:image/png') && c.html.indexOf('data:image/png') < c.html.indexOf('Nice, right'), 'inline image kept in place between text parts');
  eq(c.attachments.map((a) => [a.part, a.filename, a.type]), [['4', 'Receipt été.pdf', 'application/pdf']], 'attachment with RFC 2231 name, correct part id');
}

// HTML referencing a cid: image inside multipart/related; the image is not an attachment.
const related = crlf(`Subject: Newsletter
Content-Type: multipart/related; boundary=r

--r
Content-Type: text/html; charset=utf-8

<img src="cid:logo@x"><p>Hi</p>
--r
Content-Type: image/png
Content-ID: <logo@x>
Content-Transfer-Encoding: base64

${btoa(png)}
--r
Content-Type: image/png
Content-ID: <unused@x>
Content-Transfer-Encoding: base64

${btoa(png)}
--r--
`);
{
  const c = extractContent(parseMime(related));
  ok(c.html.includes('src="data:image/png;base64,'), 'cid: rewritten to data URI');
  eq(c.attachments.map((a) => a.cid), ['unused@x'], 'only the unreferenced cid image remains an attachment');
}

// Single-part, windows-1252, LF line endings, no MIME-Version.
{
  const r = parseMime('Subject: old\nContent-Type: text/plain; charset=windows-1252\n\nna\x96ve \x93quotes\x94\n');
  eq(extractContent(r).text, 'na–ve “quotes”\n', 'legacy charset + bare LF');
  eq(r.path, '1', 'non-multipart message is part 1');
}
// Raw 8-bit UTF-8 in headers (no RFC 2047), which some senders do.
eq(header(parseMime(bin('Subject: Grüße aus Köln\r\n\r\nx')).headers, 'subject'), 'Grüße aus Köln', 'raw UTF-8 header');
eq(header(parseMime('Subject: \x93Hi\x94 \x80\r\n\r\nx').headers, 'subject'), '“Hi” €', 'raw cp1252 header');
eq(extractContent(parseMime(bin('Content-Type: text/plain; charset=us-ascii\r\n\r\nmislabelled ü'))).text, 'mislabelled ü', 'us-ascii label on UTF-8 body');

// ---- building -------------------------------------------------------------------
{
  const { raw, messageId } = buildMessage({
    from: { name: 'Tim Cook', email: 'tim@icloud.com' }, to: [{ name: 'Renée, Fleming', email: 'r@x.com' }], cc: [],
    subject: 'Réunion 🎉', text: '.leading dot\nline two é\n' + 'x'.repeat(200), inReplyTo: '<a@b>', references: '<a@b>',
    attachments: [{ filename: 'été.txt', type: 'text/plain', data: bin('hello') }],
  });
  const r = parseMime(raw);
  eq(header(r.headers, 'subject'), 'Réunion 🎉', 'built subject round-trips');
  eq(parseAddresses(r.headers.get('to')[0]), [{ name: 'Renée, Fleming', email: 'r@x.com' }], 'built To with comma quoted');
  const c = extractContent(r);
  eq(c.text, '.leading dot\r\nline two é\r\n' + 'x'.repeat(200), 'built body round-trips through QP (long line soft-wrapped)');
  eq(c.attachments[0].filename, 'été.txt', 'built attachment filename');
  ok(raw.split('\r\n').every((l) => l.length <= 998), 'no line over 998 octets');
  ok(/^<[0-9a-f]{24}@icloud\.com>$/.test(messageId), 'message-id on sender domain');
}

// ---- end to end -----------------------------------------------------------------
const fake = await new FakeICloud().start();
const now = Date.now();
for (let i = 1; i <= 120; i++) {
  fake.add('INBOX', crlf(`From: Sender ${i} <s${i}@example.com>
To: tim@icloud.com
Subject: Message number ${i}
Date: ${new Date(now - (121 - i) * 60000).toUTCString()}
Message-ID: <m${i}@example.com>
Content-Type: text/plain; charset=utf-8

Body of message ${i}.
> quoted reply text should not reach the preview
`), i % 3 ? ['\\Seen'] : []);
}
fake.add('INBOX', alt);
fake.add('INBOX', appleMixed, ['\\Seen']);
fake.add('INBOX', related);

const server = createServer({ open: makeOpen({ insecure: true }), insecure: true, imap: { host: '127.0.0.1', port: fake.imapPort, tls: 'implicit' }, smtp: { host: '127.0.0.1', port: fake.smtpPort, tls: 'starttls' } });
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}`;
const auth = 'Basic ' + btoa(`${fake.user}:${fake.pass}`);
const call = async (name, body, a = auth) => {
  const r = await fetch(`${base}/api/${name}`, { method: 'POST', headers: { Authorization: a, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const type = r.headers.get('content-type') || '';
  return { status: r.status, headers: r.headers, body: type.includes('json') ? await r.json() : new Uint8Array(await r.arrayBuffer()) };
};

try {
  const bad = await call('mailboxes', {}, 'Basic ' + btoa(`${fake.user}:wrong-password`));
  eq(bad.status, 401, 'wrong password → 401');
  ok(/app-specific password/.test(bad.body.error), 'auth error explains app-specific passwords');
  eq((await call('mailboxes', {}, '')).status, 401, 'no credentials → 401');

  const mb = (await call('mailboxes', {})).body.mailboxes;
  const by = Object.fromEntries(mb.map((b) => [b.special || b.name, b]));
  eq(['inbox', 'sent', 'trash', 'drafts', 'junk', 'archive'].every((k) => by[k]), true, 'special-use roles detected');
  eq(by.inbox.total, 123, 'inbox total');
  eq(by.inbox.unseen, 42, 'inbox unseen');
  ok(mb.some((b) => b.name === 'Receipts Été' && b.path === 'Receipts &AMk-t&AOk-'), 'non-ASCII mailbox decoded, raw path kept');

  const p1 = (await call('list', { mailbox: 'INBOX', count: 50 })).body;
  eq(p1.messages.length, 50, 'first page size');
  eq(p1.messages[0].subject, 'Newsletter', 'newest first');
  eq(p1.messages[1].attachments, true, 'attachment flag from BODYSTRUCTURE');
  eq(p1.messages[2].subject, 'Café tomorrow', 'envelope subject decoded');
  eq(p1.messages[2].preview, 'Lunch at the café?', 'preview from text/plain QP part, quotes stripped');
  eq(p1.messages[3].preview, 'Body of message 120.', 'preview plain single part');
  eq(p1.messages[3].from, [{ name: 'Sender 120', email: 's120@example.com' }], 'envelope from');
  eq(p1.messages[0].preview, 'Hi', 'preview from html-only message');
  const p2 = (await call('list', { mailbox: 'INBOX', end: p1.end, count: 50 })).body;
  const p3 = (await call('list', { mailbox: 'INBOX', end: p2.end, count: 50 })).body;
  eq(p2.messages.length + p3.messages.length, 73, 'paging covers the rest');
  eq(p3.end, 0, 'last page ends at 0');
  eq(new Set([...p1.messages, ...p2.messages, ...p3.messages].map((m) => m.uid)).size, 123, 'no duplicates across pages');

  const unreadUid = p1.messages.find((m) => !m.flags.includes('\\Seen')).uid;
  const msg = (await call('message', { mailbox: 'INBOX', uid: unreadUid })).body;
  ok(msg.flags.includes('\\Seen'), 'opening marks seen');
  ok(fake.boxes.get('INBOX').msgs.find((m) => m.uid === unreadUid).flags.has('\\Seen'), 'seen persisted on server');

  const mixedUid = p1.messages[1].uid;
  const m2 = (await call('message', { mailbox: 'INBOX', uid: mixedUid })).body;
  eq(m2.attachments[0].filename, 'Receipt été.pdf', 'message API lists attachment');
  const att = await call('attachment', { mailbox: 'INBOX', uid: mixedUid, part: m2.attachments[0].part });
  eq(new TextDecoder().decode(att.body), '%PDF-1.4\n', 'attachment bytes decoded');
  ok(att.headers.get('content-disposition').includes("UTF-8''Receipt%20%C3%A9t%C3%A9.pdf"), 'attachment filename header');

  await call('flags', { mailbox: 'INBOX', uids: [mixedUid], add: ['\\Flagged'], remove: ['\\Seen'] });
  const fl = fake.boxes.get('INBOX').msgs.find((m) => m.uid === mixedUid).flags;
  eq([fl.has('\\Flagged'), fl.has('\\Seen')], [true, false], 'flag + mark unread');

  const s1 = (await call('search', { mailbox: 'INBOX', query: 'café' })).body;
  eq(s1.messages.map((m) => m.subject), ['Café tomorrow'], 'UTF-8 search via literal + continuation');
  const s2 = (await call('search', { mailbox: 'INBOX', query: 'from:s7@ "number 7"' })).body;
  eq(s2.messages.map((m) => m.subject), ['Message number 7'], 'field + phrase search');
  eq((await call('search', { mailbox: 'INBOX', query: 'is:flagged' })).body.messages.length, 1, 'is:flagged');

  const lastUid = p1.messages[0].uid;
  const mv = await call('move', { mailbox: 'INBOX', uids: [lastUid], to: 'Archive' });
  eq(mv.body, { ok: true }, 'move ok');
  eq(fake.boxes.get('Archive').msgs.length, 1, 'moved to Archive');

  const del = (await call('delete', { mailbox: 'INBOX', uids: [p1.messages[3].uid] })).body;
  eq(del.moved, 'Deleted Messages', 'delete goes to Trash');
  const tUid = fake.boxes.get('Deleted Messages').msgs[0].uid;
  const del2 = (await call('delete', { mailbox: 'Deleted Messages', uids: [tUid] })).body;
  eq([del2.expunged, fake.boxes.get('Deleted Messages').msgs.length], [true, 0], 'delete from Trash expunges');

  // sync: new mail arrives, flags change elsewhere
  const before = (await call('mailboxes', {})).body.mailboxes.find((b) => b.special === 'inbox').uidnext;
  fake.add('INBOX', crlf('From: New <n@x.com>\nSubject: Fresh\nDate: ' + new Date().toUTCString() + '\n\nhello'));
  const sy = (await call('sync', { mailbox: 'INBOX', since: before, uids: [mixedUid] })).body;
  eq(sy.messages.map((m) => m.subject), ['Fresh'], 'sync returns only new mail');
  ok(sy.flags[mixedUid].includes('\\Flagged'), 'sync returns current flags');
  eq((await call('sync', { mailbox: 'INBOX', since: before + 1 })).body.messages, [], 'sync with nothing new');

  // send: reply with attachment + forwarded attachments, filed in Sent, original marked answered
  const sendRes = await call('send', {
    fromName: 'Tim Cook', to: [{ name: 'Craig', email: 'craig@apple.com' }], cc: [], bcc: [{ name: '', email: 'secret@x.com' }],
    subject: 'Re: Café tomorrow', text: '.yes\n\nOn Monday, Craig wrote:\n> Lunch?', inReplyTo: '<alt-1@apple.com>', references: '<alt-1@apple.com>',
    replyTo: { mailbox: 'INBOX', uid: p1.messages[2].uid },
    attachments: [{ filename: 'notes.txt', type: 'text/plain', data: btoa('hi') }],
    forward: { mailbox: 'INBOX', uid: mixedUid },
  });
  eq(sendRes.status, 200, 'send ok');
  const out = fake.sent[0];
  eq(out.rcpts, ['craig@apple.com', 'secret@x.com'], 'bcc is a recipient');
  ok(!/secret@x\.com/.test(out.data), 'bcc not in headers');
  eq(out.from, fake.user, 'envelope from is the account');
  const parsed = extractContent(parseMime(out.data));
  ok(parsed.text.startsWith('.yes'), 'dot-stuffing undone by server: leading dot intact');
  eq(parsed.attachments.map((a) => a.filename), ['notes.txt', 'dot.png', 'Receipt été.pdf'], 'own + forwarded attachments');
  eq(sendRes.body.saved, 'Sent Messages', 'filed in Sent');
  ok(fake.boxes.get('Sent Messages').msgs[0].flags.has('\\Seen'), 'Sent copy is \\Seen');
  ok(fake.boxes.get('INBOX').msgs.find((m) => m.uid === p1.messages[2].uid).flags.has('\\Answered'), 'original marked answered');

  const badSend = await call('send', { to: [], text: 'x' });
  eq(badSend.status, 400, 'send with no recipients → 400');

  const ping = await fetch(`${base}/api/ping`);
  eq((await ping.json()).ok, true, 'ping');
  const page = await fetch(`${base}/`);
  eq(page.status, 200, 'serves the app');
  eq((await fetch(`${base}/bridge/api.js`)).status, 404, 'does not serve source');
} finally {
  server.close();
  fake.stop();
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
