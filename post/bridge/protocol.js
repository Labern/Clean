// IMAP4rev1 and SMTP clients over an abstract socket, so the same code runs on
// Cloudflare (cloudflare:sockets) and Node (net/tls).
//
// Socket contract: { read(): Promise<Uint8Array|null>, write(u8): Promise,
//                    startTls(): Socket, close() }

import { u8ToBin, binToU8, utf8ToBin } from './mime.js';

export class ProtocolError extends Error {
  constructor(message, kind = 'protocol') { super(message); this.kind = kind; }
}

class Conn {
  constructor(sock) { this.sock = sock; this.buf = ''; }
  async fill() {
    const c = await this.sock.read();
    if (!c) throw new ProtocolError('Connection closed by server', 'network');
    this.buf += u8ToBin(c);
  }
  async line() {
    let i;
    while ((i = this.buf.indexOf('\r\n')) < 0) await this.fill();
    const l = this.buf.slice(0, i);
    this.buf = this.buf.slice(i + 2);
    return l;
  }
  async bytes(n) {
    while (this.buf.length < n) await this.fill();
    const b = this.buf.slice(0, n);
    this.buf = this.buf.slice(n);
    return b;
  }
  write(bin) { return this.sock.write(binToU8(bin)); }
}

// ---- IMAP response tokenizer --------------------------------------------
// Literals are lifted out of the line while reading and stand in as \0, so the
// tokenizer never has to reason about byte counts.

export function tokenize(s, lits = []) {
  let i = 0, li = 0;
  function list(end) {
    const out = [];
    while (i < s.length) {
      const c = s[i];
      if (c === ' ') { i++; continue; }
      if (c === end) { i++; return out; }
      if (c === '(') { i++; out.push(list(')')); continue; }
      if (c === '"') {
        i++;
        let v = '';
        while (i < s.length && s[i] !== '"') { if (s[i] === '\\') i++; v += s[i++]; }
        i++;
        out.push(v);
        continue;
      }
      if (c === '\0') { i++; out.push(lits[li++] ?? ''); continue; }
      let v = '';
      while (i < s.length && s[i] !== ' ' && s[i] !== '(' && s[i] !== ')' && s[i] !== '\0') {
        if (s[i] === '[') {
          const j = s.indexOf(']', i);
          if (j < 0) { v += s.slice(i); i = s.length; break; }
          v += s.slice(i, j + 1); i = j + 1; continue;
        }
        v += s[i++];
      }
      out.push(v === 'NIL' ? null : v);
    }
    return out;
  }
  return list(null);
}

export function fetchMap(list) {
  const o = {};
  for (let i = 0; i + 1 < list.length; i += 2) o[String(list[i]).toUpperCase()] = list[i + 1];
  return o;
}

export const quote = (s) => /[^\x20-\x7e]/.test(s) ? null : `"${s.replace(/[\\"]/g, '\\$&')}"`;
// An IMAP string argument: quoted when it can be, a literal when it must be.
export const astring = (s) => quote(s) ?? { lit: utf8ToBin(s) };

export class Imap {
  constructor(sock) { this.c = new Conn(sock); this.n = 0; this.caps = new Set(); }

  async greet() {
    const g = await this.c.line();
    if (!g.startsWith('* OK') && !g.startsWith('* PREAUTH')) throw new ProtocolError(`Unexpected greeting: ${g}`);
    this.readCaps(g);
  }

  readCaps(text) {
    const m = /\[CAPABILITY ([^\]]*)\]/i.exec(text) || /^\* CAPABILITY (.*)$/i.exec(text);
    if (m) this.caps = new Set(m[1].toUpperCase().split(' '));
  }

  async readResponse() {
    let text = '';
    const lits = [];
    for (;;) {
      const l = await this.c.line();
      const m = /\{(\d+)\+?\}$/.exec(l);
      if (m) { text += l.slice(0, m.index) + '\0'; lits.push(await this.c.bytes(+m[1])); continue; }
      return { text: text + l, lits };
    }
  }

  // args: strings, joined verbatim, and { lit } objects sent as literals.
  async cmd(...args) {
    const tag = `A${++this.n}`;
    const untagged = [];
    const take = (r) => {
      untagged.push({ text: r.text, tokens: tokenize(r.text, r.lits) });
      this.readCaps(r.text);
    };
    let out = `${tag} `;
    for (const a of args) {
      if (typeof a === 'string') { out += a; continue; }
      const plus = this.caps.has('LITERAL+');
      out += `{${a.lit.length}${plus ? '+' : ''}}\r\n`;
      await this.c.write(out);
      out = '';
      if (!plus) for (;;) {
        const r = await this.readResponse();
        if (r.text.startsWith('+')) break;
        if (r.text.startsWith(tag + ' ')) throw new ProtocolError(r.text.slice(tag.length + 1));
        take(r);
      }
      out += a.lit;
    }
    await this.c.write(out + '\r\n');
    for (;;) {
      const r = await this.readResponse();
      if (r.text.startsWith(tag + ' ')) {
        const rest = r.text.slice(tag.length + 1);
        this.readCaps(rest);
        if (!/^OK\b/i.test(rest)) {
          const auth = /AUTHENTICATIONFAILED|AUTHORIZATIONFAILED|\[AUTH|Invalid credentials|LOGIN failed/i.test(rest);
          throw new ProtocolError(rest.replace(/^(NO|BAD)\s*/i, ''), auth ? 'auth' : 'protocol');
        }
        return { untagged, text: rest };
      }
      if (r.text.startsWith('+')) continue;
      take(r);
    }
  }

  async login(user, pass) {
    try { await this.cmd('LOGIN ', astring(user), ' ', astring(pass)); }
    catch (e) { if (e.kind === 'protocol' && /^LOGIN|fail|invalid|denied|credential/i.test(e.message)) e.kind = 'auth'; throw e; }
    if (!this.caps.size || !this.caps.has('IMAP4REV1')) await this.cmd('CAPABILITY');
  }

  async logout() { try { await this.cmd('LOGOUT'); } catch {} }
}

// ---- SMTP ----------------------------------------------------------------

export class Smtp {
  constructor(sock) { this.c = new Conn(sock); this.sock = sock; }

  async reply() {
    const lines = [];
    for (;;) {
      const l = await this.c.line();
      lines.push(l);
      if (!/^\d{3}-/.test(l)) return { code: +l.slice(0, 3), lines, text: lines.map((x) => x.slice(4)).join('\n') };
    }
  }
  async expect(ok, line) {
    if (line != null) await this.c.write(line + '\r\n');
    const r = await this.reply();
    if (!ok.includes(r.code)) {
      const kind = r.code === 535 || r.code === 534 ? 'auth' : r.code >= 500 ? 'rejected' : 'protocol';
      throw new ProtocolError(`SMTP ${r.code}: ${r.text}`, kind);
    }
    return r;
  }

  async session({ user, pass, from, rcpts, data, requireTls }) {
    await this.expect([220]);
    let ehlo = await this.expect([250], 'EHLO post.bridge');
    if (requireTls !== 'implicit') {
      const can = ehlo.lines.some((l) => /^250[ -]STARTTLS/i.test(l));
      if (!can && requireTls) throw new ProtocolError('Server did not offer STARTTLS', 'network');
      if (can) {
        await this.expect([220], 'STARTTLS');
        this.sock = await this.sock.startTls();
        this.c = new Conn(this.sock);
        ehlo = await this.expect([250], 'EHLO post.bridge');
      }
    }
    await this.expect([235], 'AUTH PLAIN ' + btoa(utf8ToBin(`\0${user}\0${pass}`)));
    await this.expect([250], `MAIL FROM:<${from}>`);
    for (const r of rcpts) await this.expect([250, 251], `RCPT TO:<${r}>`);
    await this.expect([354], 'DATA');
    const body = data.replace(/\r?\n/g, '\r\n').replace(/(^|\r\n)\./g, '$1..');
    await this.expect([250], body + (body.endsWith('\r\n') ? '' : '\r\n') + '.');
    try { await this.c.write('QUIT\r\n'); } catch {}
  }
}
