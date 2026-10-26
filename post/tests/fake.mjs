// An in-memory IMAP + SMTP server that behaves like iCloud closely enough to
// drive the bridge end to end: literals both ways, continuation requests,
// sequence and UID sets, partial fetches, MOVE, APPEND, SEARCH.

import net from 'node:net';
import { parseMime, parseHeaders, rawHeader, header, extractContent, u8ToBin, binToU8 } from '../bridge/mime.js';

const q = (s) => s == null ? 'NIL' : /[^\x20-\x7e]|["\\]/.test(s) ? `{${s.length}}\r\n${s}` : `"${s}"`;

function envAddr(raw) {
  if (!raw) return 'NIL';
  const items = raw.split(/,(?=(?:[^"]*"[^"]*")*[^"]*$)/).map((t) => t.trim()).filter(Boolean);
  return '(' + items.map((t) => {
    const m = /^(.*?)\s*<([^>]+)>$/.exec(t);
    const name = m ? m[1].replace(/^"|"$/g, '') || null : null;
    const [mb, host] = (m ? m[2] : t).split('@');
    return `(${q(name)} NIL ${q(mb)} ${q(host)})`;
  }).join('') + ')';
}
function envelope(raw) {
  const i = raw.search(/\r?\n\r?\n/);
  const h = parseHeaders(i < 0 ? raw : raw.slice(0, i));
  const g = (k) => rawHeader(h, k) || null;
  const from = g('from');
  return `(${q(g('date'))} ${q(g('subject'))} ${envAddr(from)} ${envAddr(g('sender') || from)} ${envAddr(g('reply-to') || from)} ${envAddr(g('to'))} ${envAddr(g('cc'))} ${envAddr(g('bcc'))} ${q(g('in-reply-to'))} ${q(g('message-id'))})`;
}
function bodystructure(n) {
  const params = (o) => { const e = Object.entries(o); return e.length ? '(' + e.map(([k, v]) => `${q(k)} ${q(v)}`).join(' ') + ')' : 'NIL'; };
  if (n.children) return '(' + n.children.map(bodystructure).join('') + ` ${q(n.subtype)} ${params({ boundary: n.params.boundary })} NIL NIL NIL)`;
  const disp = n.disposition ? `(${q(n.disposition)} ${n.filename ? params({ filename: n.filename }) : 'NIL'})` : 'NIL';
  const base = `${q(n.type)} ${q(n.subtype)} ${params(n.params)} ${q(n.cid ? `<${n.cid}>` : null)} NIL ${q(n.encoding || '7bit')} ${n.body.length}`;
  if (n.type === 'text') return `(${base} ${n.body.split('\n').length} NIL ${disp} NIL NIL)`;
  return `(${base} NIL ${disp} NIL NIL)`;
}
function section(raw, path) {
  if (!path) return raw;
  const find = (n) => n.path === path && !n.children ? n : (n.children || []).map(find).find(Boolean);
  return find(parseMime(raw))?.body ?? '';
}

export class FakeICloud {
  constructor() {
    this.user = 'tim@icloud.com';
    this.pass = 'abcd-efgh-ijkl-mnop';
    this.boxes = new Map();
    for (const [name, use] of [['INBOX'], ['Sent Messages', '\\Sent'], ['Deleted Messages', '\\Trash'], ['Drafts', '\\Drafts'], ['Junk', '\\Junk'], ['Archive', '\\Archive'], ['Receipts &AMk-t&AOk-']])
      this.boxes.set(name, { use, uidvalidity: 1700000000, uidnext: 1, msgs: [] });
    this.sent = [];
    this.log = [];
  }
  add(box, raw, flags = [], date = new Date()) {
    const b = this.boxes.get(box);
    b.msgs.push({ uid: b.uidnext++, raw, flags: new Set(flags), date });
  }

  async start() {
    this.imapServer = net.createServer((s) => this.imapSession(s));
    this.smtpServer = net.createServer((s) => this.smtpSession(s));
    await new Promise((r) => this.imapServer.listen(0, '127.0.0.1', r));
    await new Promise((r) => this.smtpServer.listen(0, '127.0.0.1', r));
    this.imapPort = this.imapServer.address().port;
    this.smtpPort = this.smtpServer.address().port;
    return this;
  }
  stop() { this.imapServer.close(); this.smtpServer.close(); }

  imapSession(sock) {
    let buf = '', need = 0, pending = '', lits = [], authed = false, cur = null, ro = false;
    const send = (s) => sock.write(binToU8(s + '\r\n'));
    sock.on('error', () => {});
    send('* OK [CAPABILITY IMAP4rev1 IDLE MOVE UIDPLUS SPECIAL-USE] fake iCloud ready');
    sock.on('data', (d) => {
      buf += u8ToBin(new Uint8Array(d));
      for (;;) {
        if (need) {
          if (buf.length < need) return;
          lits.push(buf.slice(0, need)); pending += '\0'; buf = buf.slice(need); need = 0;
        }
        const i = buf.indexOf('\r\n');
        if (i < 0) return;
        const line = buf.slice(0, i); buf = buf.slice(i + 2);
        const m = /\{(\d+)(\+?)\}$/.exec(line);
        if (m) { pending += line.slice(0, m.index); need = +m[1]; if (!m[2]) send('+ go ahead'); continue; }
        const full = pending + line, L = lits;
        pending = ''; lits = [];
        try { exec(full, L); } catch (e) { const tag = full.split(' ')[0]; send(`${tag} BAD ${e.message}`); }
      }
    });

    const exec = (line, L) => {
      this.log.push(line);
      let li = 0;
      const args = [];
      for (const m of line.matchAll(/"((?:[^"\\]|\\.)*)"|\0|\([^)]*\)|\S+/g)) args.push(m[0] === '\0' ? L[li++] : m[1] !== undefined ? m[1].replace(/\\(.)/g, '$1') : m[0]);
      const [tag, cmd0, ...rest] = args;
      let cmd = cmd0.toUpperCase(), uid = false;
      if (cmd === 'UID') { uid = true; cmd = rest.shift().toUpperCase(); }
      const ok = (t = 'done') => send(`${tag} OK ${t}`);
      if (cmd === 'CAPABILITY') { send('* CAPABILITY IMAP4rev1 IDLE MOVE UIDPLUS SPECIAL-USE'); return ok(); }
      if (cmd === 'LOGOUT') { send('* BYE'); ok(); sock.end(); return; }
      if (cmd === 'LOGIN') {
        if (rest[0] === this.user && rest[1] === this.pass) { authed = true; return ok('[CAPABILITY IMAP4rev1 IDLE MOVE UIDPLUS SPECIAL-USE] LOGIN completed'); }
        return send(`${tag} NO [AUTHENTICATIONFAILED] Authentication failed`);
      }
      if (!authed) return send(`${tag} BAD not authenticated`);
      if (cmd === 'LIST') {
        for (const [name, b] of this.boxes) send(`* LIST (\\HasNoChildren${b.use ? ' ' + b.use : ''}) "/" ${q(name)}`);
        return ok();
      }
      if (cmd === 'STATUS') {
        const b = this.boxes.get(rest[0]);
        if (!b) return send(`${tag} NO no such mailbox`);
        send(`* STATUS ${q(rest[0])} (MESSAGES ${b.msgs.length} UNSEEN ${b.msgs.filter((m) => !m.flags.has('\\Seen')).length} UIDNEXT ${b.uidnext})`);
        return ok();
      }
      if (cmd === 'SELECT' || cmd === 'EXAMINE') {
        cur = this.boxes.get(rest[0]);
        if (!cur) return send(`${tag} NO no such mailbox`);
        ro = cmd === 'EXAMINE';
        send(`* ${cur.msgs.length} EXISTS`); send('* 0 RECENT');
        send(`* OK [UIDVALIDITY ${cur.uidvalidity}] UIDs valid`); send(`* OK [UIDNEXT ${cur.uidnext}] next`);
        return ok(ro ? '[READ-ONLY] done' : '[READ-WRITE] done');
      }
      if (cmd === 'APPEND') {
        const b = this.boxes.get(rest[0]);
        const flags = rest.length > 2 ? rest[1].replace(/[()]/g, '').split(' ').filter(Boolean) : [];
        this.add(rest[0], rest[rest.length - 1], flags);
        return ok(`[APPENDUID ${b.uidvalidity} ${b.uidnext - 1}] done`);
      }
      if (!cur) return send(`${tag} BAD no mailbox selected`);
      const pick = (set) => {
        const max = uid ? Math.max(0, ...cur.msgs.map((m) => m.uid)) : cur.msgs.length;
        const out = new Set();
        for (const r of set.split(',')) {
          let [a, b] = r.split(':').map((x) => x === '*' ? max : +x);
          if (b === undefined) b = a;
          if (a > b) [a, b] = [b, a];
          cur.msgs.forEach((m, i) => { const k = uid ? m.uid : i + 1; if (k >= a && k <= b) out.add(m); });
        }
        return [...out];
      };
      if (cmd === 'FETCH') {
        const items = rest.slice(1).join(' ').replace(/^\(|\)$/g, '');
        for (const m of pick(rest[0])) {
          const seq = cur.msgs.indexOf(m) + 1;
          const parts = [`UID ${m.uid}`];
          if (/FLAGS/.test(items)) parts.push(`FLAGS (${[...m.flags].join(' ')})`);
          if (/INTERNALDATE/.test(items)) parts.push(`INTERNALDATE "${m.date.toUTCString()}"`);
          if (/RFC822\.SIZE/.test(items)) parts.push(`RFC822.SIZE ${m.raw.length}`);
          if (/ENVELOPE/.test(items)) parts.push(`ENVELOPE ${envelope(m.raw)}`);
          if (/BODYSTRUCTURE/.test(items)) parts.push(`BODYSTRUCTURE ${bodystructure(parseMime(m.raw))}`);
          for (const b of items.matchAll(/BODY(\.PEEK)?\[([^\]]*)\](?:<(\d+)\.(\d+)>)?/g)) {
            let data = section(m.raw, b[2]);
            if (b[3] !== undefined) data = data.slice(+b[3], +b[3] + +b[4]);
            parts.push(`BODY[${b[2]}]${b[3] !== undefined ? `<${b[3]}>` : ''} {${data.length}}\r\n${data}`);
            if (!b[1] && !ro) m.flags.add('\\Seen');
          }
          send(`* ${seq} FETCH (${parts.join(' ')})`);
        }
        return ok();
      }
      if (cmd === 'STORE') {
        if (ro) return send(`${tag} NO read-only`);
        const fl = rest.slice(2).join(' ').replace(/[()]/g, '').split(' ').filter(Boolean);
        for (const m of pick(rest[0])) for (const f of fl) rest[1].startsWith('+') ? m.flags.add(f) : m.flags.delete(f);
        return ok();
      }
      if (cmd === 'MOVE' || cmd === 'COPY') {
        if (ro) return send(`${tag} NO read-only`);
        const dest = this.boxes.get(rest[1]);
        if (!dest) return send(`${tag} NO [TRYCREATE] no such mailbox`);
        for (const m of pick(rest[0])) {
          dest.msgs.push({ ...m, flags: new Set(m.flags), uid: dest.uidnext++ });
          if (cmd === 'MOVE') { send(`* ${cur.msgs.indexOf(m) + 1} EXPUNGE`); cur.msgs.splice(cur.msgs.indexOf(m), 1); }
        }
        return ok();
      }
      if (cmd === 'EXPUNGE') {
        for (let i = cur.msgs.length - 1; i >= 0; i--) if (cur.msgs[i].flags.has('\\Deleted')) { send(`* ${i + 1} EXPUNGE`); cur.msgs.splice(i, 1); }
        return ok();
      }
      if (cmd === 'SEARCH') {
        let toks = rest;
        if (String(toks[0]).toUpperCase() === 'CHARSET') toks = toks.slice(2);
        const utf = (s) => new TextDecoder().decode(binToU8(s)).toLowerCase();
        const hdr = (m, k) => header(parseMime(m.raw).headers, k).toLowerCase();
        const text = (m) => { const c = extractContent(parseMime(m.raw)); return (c.text + ' ' + (c.html || '')).toLowerCase(); };
        let i = 0;
        const crit = () => {
          const k = String(toks[i++]).toUpperCase();
          if (k === 'OR') { const a = crit(), b = crit(); return (m) => a(m) || b(m); }
          if (k === 'UNSEEN') return (m) => !m.flags.has('\\Seen');
          if (k === 'FLAGGED') return (m) => m.flags.has('\\Flagged');
          if (k === 'HEADER') { const h = toks[i++].toLowerCase(), v = utf(toks[i++]); return (m) => hdr(m, h).includes(v); }
          const v = utf(toks[i++]);
          if (k === 'BODY') return (m) => text(m).includes(v);
          return (m) => hdr(m, k.toLowerCase()).includes(v);
        };
        const all = [];
        while (i < toks.length) all.push(crit());
        send(`* SEARCH ${cur.msgs.filter((m) => all.every((c) => c(m))).map((m) => uid ? m.uid : cur.msgs.indexOf(m) + 1).join(' ')}`.trim());
        return ok();
      }
      send(`${tag} BAD unknown command ${cmd}`);
    };
  }

  smtpSession(sock) {
    let buf = '', data = null, env = { rcpts: [] };
    const send = (s) => sock.write(s + '\r\n');
    sock.on('error', () => {});
    send('220 fake smtp ready');
    sock.on('data', (d) => {
      buf += u8ToBin(new Uint8Array(d));
      let i;
      while ((i = buf.indexOf('\r\n')) >= 0) {
        const line = buf.slice(0, i); buf = buf.slice(i + 2);
        if (data !== null) {
          if (line === '.') { this.sent.push({ ...env, data: data.join('\r\n').replace(/(^|\r\n)\.\./g, '$1.') }); data = null; env = { rcpts: [] }; send('250 queued'); }
          else data.push(line);
          continue;
        }
        const up = line.toUpperCase();
        if (up.startsWith('EHLO')) { send('250-fake'); send('250-AUTH PLAIN'); send('250 8BITMIME'); }
        else if (up.startsWith('AUTH PLAIN ')) {
          const [, u, p] = atob(line.slice(11)).split('\0');
          send(u === this.user && p === this.pass ? '235 ok' : '535 5.7.8 auth failed');
        }
        else if (up.startsWith('MAIL FROM:')) { env.from = line.slice(10).replace(/[<>]/g, ''); send('250 ok'); }
        else if (up.startsWith('RCPT TO:')) { env.rcpts.push(line.slice(8).replace(/[<>]/g, '')); send('250 ok'); }
        else if (up === 'DATA') { data = []; send('354 go'); }
        else if (up === 'QUIT') { send('221 bye'); sock.end(); }
        else send('500 what');
      }
    });
  }
}
