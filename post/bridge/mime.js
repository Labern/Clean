// MIME: parse what Apple's IMAP server hands us, build what its SMTP server takes.
//
// Everything below the text layer works on *binary strings* (one char per
// byte, 0-255). Mail is bytes in arbitrary charsets; decoding to text happens
// exactly once, as late as possible, with the charset the part declares.

const enc = new TextEncoder();

export function u8ToBin(u8) {
  let s = '';
  for (let i = 0; i < u8.length; i += 8192) s += String.fromCharCode.apply(null, u8.subarray(i, i + 8192));
  return s;
}
export function binToU8(s) {
  const u8 = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) u8[i] = s.charCodeAt(i) & 0xff;
  return u8;
}
export const utf8ToBin = (str) => u8ToBin(enc.encode(str));

// windows-1252's 0x80-0x9F. Per WHATWG, "iso-8859-1" and "us-ascii" mean this
// too — and Node's TextDecoder gets it wrong (decodes them as C1 controls).
const CP1252 = '\u20ac\x81\u201a\u0192\u201e\u2026\u2020\u2021\u02c6\u2030\u0160\u2039\u0152\x8d\u017d\x8f\x90\u2018\u2019\u201c\u201d\u2022\u2013\u2014\u02dc\u2122\u0161\u203a\u0153\x9d\u017e\u0178';
const LATIN = new Set(['iso-8859-1', 'latin1', 'l1', 'windows-1252', 'cp1252', 'x-cp1252', 'iso8859-1', 'iso_8859-1', 'cp819', 'ibm819', 'us-ascii', 'ascii']);
const cp1252 = (bin) => bin.replace(/[\x80-\x9f]/g, (c) => CP1252[c.charCodeAt(0) - 0x80]);

export function decodeCharset(bin, charset) {
  let cs = String(charset || 'utf-8').trim().replace(/^"|"$/g, '').toLowerCase();
  // Mislabelled "ascii" that is really UTF-8 is common; valid UTF-8 wins.
  if (LATIN.has(cs)) {
    if (!/[\x80-\xff]/.test(bin)) return bin;
    if (cs.includes('ascii')) { try { return new TextDecoder('utf-8', { fatal: true }).decode(binToU8(bin)); } catch {} }
    return cp1252(bin);
  }
  if (cs === 'unicode-1-1-utf-7' || cs === '') cs = 'utf-8';
  try { return new TextDecoder(cs).decode(binToU8(bin)); }
  catch { return new TextDecoder('utf-8').decode(binToU8(bin)); }
}

// Raw 8-bit header bytes: UTF-8 if they are valid UTF-8, else windows-1252.
export function bin8ToText(bin) {
  if (!/[\x80-\xff]/.test(bin)) return bin;
  try { return new TextDecoder('utf-8', { fatal: true }).decode(binToU8(bin)); }
  catch { return cp1252(bin); }
}

export function b64decodeBin(s) {
  s = s.replace(/[^A-Za-z0-9+/]/g, '');
  const r = s.length % 4;
  if (r === 1) s = s.slice(0, -1);
  else if (r) s += '='.repeat(4 - r);
  try { return atob(s); } catch { return ''; }
}
export function qpDecode(s) {
  return s.replace(/=\r?\n/g, '').replace(/=([0-9A-Fa-f]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)));
}

// RFC 2047. Adjacent encoded words in the same charset are joined at the byte
// level before decoding: senders routinely split one multibyte character
// across two words, and decoding word by word turns it into two U+FFFD.
const EW = /=\?([^?\s]+)\?([BbQq])\?([^?\s]*)\?=/g;
export function decodeWords(str) {
  if (!str || str.indexOf('=?') < 0) return str || '';
  let out = '', last = 0, run = null;
  const flush = () => { if (run) { out += decodeCharset(run.bin, run.cs); run = null; } };
  for (const m of str.matchAll(EW)) {
    const gap = str.slice(last, m.index);
    const cs = m[1].split('*')[0].toLowerCase();
    const bin = m[2].toUpperCase() === 'B' ? b64decodeBin(m[3]) : qpDecode(m[3].replace(/_/g, ' '));
    if (run && /^\s*$/.test(gap) && run.cs === cs) run.bin += bin;
    else if (run && /^\s*$/.test(gap)) { flush(); run = { cs, bin }; }
    else { flush(); out += gap; run = { cs, bin }; }
    last = m.index + m[0].length;
  }
  flush();
  return out + str.slice(last);
}

export function encodeWord(str) {
  if (!/[^\x20-\x7e]/.test(str)) return str;
  // Split on character boundaries so no word carries half a code point.
  const words = [];
  let cur = '';
  for (const ch of str) {
    if (utf8ToBin(cur + ch).length > 45) { words.push(cur); cur = ''; }
    cur += ch;
  }
  if (cur) words.push(cur);
  return words.map((w) => `=?UTF-8?B?${btoa(utf8ToBin(w))}?=`).join(' ');
}

// ---- headers -------------------------------------------------------------

export function parseHeaders(bin) {
  const map = new Map();
  for (const line of bin.replace(/\r?\n(?=[ \t])/g, '').split(/\r?\n/)) {
    const i = line.indexOf(':');
    if (i <= 0) continue;
    const k = line.slice(0, i).trim().toLowerCase();
    if (!map.has(k)) map.set(k, []);
    map.get(k).push(line.slice(i + 1).trim());
  }
  return map;
}
export const rawHeader = (h, k) => (h.get(k) || [])[0] || '';
export const header = (h, k) => decodeWords(bin8ToText(rawHeader(h, k)));

// "text/plain; charset=utf-8; name*0*=utf-8''%E2..." -> { value, params }
export function parseStructured(v) {
  v = bin8ToText(v || '');
  const parts = [];
  let cur = '', q = false;
  for (let i = 0; i < v.length; i++) {
    const ch = v[i];
    if (ch === '\\' && q) { cur += ch + (v[++i] || ''); continue; }
    if (ch === '"') q = !q;
    if (ch === ';' && !q) { parts.push(cur); cur = ''; } else cur += ch;
  }
  parts.push(cur);
  const value = parts.shift().trim().toLowerCase();
  const params = {}, cont = {};
  for (const p of parts) {
    const i = p.indexOf('=');
    if (i < 0) continue;
    const key = p.slice(0, i).trim().toLowerCase();
    let val = p.slice(i + 1).trim();
    if (val.startsWith('"')) val = val.slice(1, val.endsWith('"') && val.length > 1 ? -1 : undefined).replace(/\\(.)/g, '$1');
    const m = /^([^*]+)(?:\*(\d+))?(\*)?$/.exec(key);
    if (!m) continue;
    if (m[2] === undefined && !m[3]) params[m[1]] = decodeWords(val);
    else (cont[m[1]] ||= []).push({ i: +(m[2] || 0), val, encoded: !!m[3] });
  }
  // RFC 2231: charset'lang'%XX continuations
  for (const [name, segs] of Object.entries(cont)) {
    segs.sort((a, b) => a.i - b.i);
    let cs = 'utf-8', bin = '';
    for (const s of segs) {
      let val = s.val;
      if (s.encoded) {
        if (s.i === 0) {
          const m = /^([^']*)'[^']*'(.*)$/.exec(val);
          if (m) { cs = m[1] || cs; val = m[2]; }
        }
        bin += val.replace(/%([0-9A-Fa-f]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)));
      } else bin += utf8ToBin(val);
    }
    params[name] = decodeCharset(bin, cs);
  }
  return { value, params };
}

// Address lists. Split on raw text (an encoded name can decode to a comma).
export function parseAddresses(raw) {
  const s = bin8ToText(raw || '');
  const items = [];
  let cur = '', q = false, angle = 0, paren = 0;
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (q) { if (ch === '\\') { cur += ch + (s[++i] || ''); continue; } if (ch === '"') q = false; cur += ch; continue; }
    if (ch === '"') q = true;
    else if (ch === '<') angle++;
    else if (ch === '>') angle = Math.max(0, angle - 1);
    else if (ch === '(') paren++;
    else if (ch === ')') paren = Math.max(0, paren - 1);
    else if ((ch === ',' || ch === ';') && !angle && !paren) { items.push(cur); cur = ''; continue; }
    else if (ch === ':' && !angle && !paren && !/[<@"]/.test(cur)) { cur = ''; continue; } // group label
    cur += ch;
  }
  items.push(cur);
  const out = [];
  for (let t of items) {
    t = t.trim();
    if (!t) continue;
    let name = '', email = '';
    const m = /^(.*?)\s*<([^>]*)>\s*(?:\(.*\))?$/.exec(t);
    if (m) { name = m[1]; email = m[2]; }
    else {
      const c = /^([^\s(]+)\s*\((.*)\)\s*$/.exec(t);
      if (c) { email = c[1]; name = c[2]; } else email = t;
    }
    name = decodeWords(name.trim().replace(/^"(.*)"$/s, '$1').replace(/\\(.)/g, '$1')).trim();
    email = email.trim().replace(/^mailto:/i, '');
    if (email || name) out.push({ name, email });
  }
  return out;
}

export function formatAddress({ name, email }) {
  if (!name || name === email) return email;
  if (/[^\x20-\x7e]/.test(name)) return `${encodeWord(name)} <${email}>`;
  return /^[\w .!#$%&'*+\/=?^`{|}~-]+$/.test(name) ? `${name} <${email}>` : `"${name.replace(/[\\"]/g, '\\$&')}" <${email}>`;
}

// ---- body tree -----------------------------------------------------------

function splitMultipart(body, boundary) {
  const esc = boundary.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`(?:^|\\r?\\n)--${esc}(--)?[ \\t]*(?=\\r?\\n|$)`, 'g');
  const parts = [];
  let last = -1, m;
  while ((m = re.exec(body))) {
    if (last >= 0) parts.push(body.slice(last, m.index));
    if (m[1]) { last = -1; break; }
    let p = m.index + m[0].length;
    if (body[p] === '\r') p++;
    if (body[p] === '\n') p++;
    last = p;
  }
  if (last >= 0) parts.push(body.slice(last));
  return parts;
}

// IMAP part numbering: a multipart's children are 1,2,…; nested 1.2; a
// non-multipart message is part "1". message/rfc822 is a leaf here.
export function parseMime(bin, path = '') {
  let head, body;
  if (bin.startsWith('\r\n')) { head = ''; body = bin.slice(2); }
  else if (bin.startsWith('\n')) { head = ''; body = bin.slice(1); }
  else {
    let i = bin.indexOf('\r\n\r\n'), sep = 4;
    const j = bin.indexOf('\n\n');
    if (i < 0 || (j >= 0 && j < i)) { i = j; sep = 2; }
    head = i < 0 ? bin : bin.slice(0, i);
    body = i < 0 ? '' : bin.slice(i + sep);
  }
  const headers = parseHeaders(head);
  const ct = parseStructured(rawHeader(headers, 'content-type') || 'text/plain; charset=us-ascii');
  const [type = 'text', subtype = 'plain'] = ct.value.split('/');
  const disp = parseStructured(rawHeader(headers, 'content-disposition'));
  const node = {
    headers, type, subtype, params: ct.params, path: path || '1',
    encoding: rawHeader(headers, 'content-transfer-encoding').toLowerCase().trim(),
    disposition: disp.value, filename: disp.params.filename || ct.params.name || '',
    cid: rawHeader(headers, 'content-id').replace(/^<|>$/g, '').trim(),
  };
  if (type === 'multipart' && ct.params.boundary) {
    node.path = path;
    node.children = splitMultipart(body, ct.params.boundary)
      .map((p, k) => parseMime(p, path ? `${path}.${k + 1}` : String(k + 1)));
  } else node.body = body;
  return node;
}

export function decodeTransfer(bin, encoding) {
  const e = (encoding || '').toLowerCase();
  if (e === 'base64') return b64decodeBin(bin);
  if (e === 'quoted-printable') return qpDecode(bin);
  return bin;
}
export const partText = (n) => decodeCharset(decodeTransfer(n.body, n.encoding), n.params.charset);

export function findPart(node, path) {
  if (node.path === path && !node.children) return node;
  for (const c of node.children || []) { const f = findPart(c, path); if (f) return f; }
  return null;
}

const hasType = (n, t) => n.children ? n.children.some((c) => hasType(c, t)) : `${n.type}/${n.subtype}` === t && n.disposition !== 'attachment';
const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
const INLINE_BUDGET = 8 * 1024 * 1024;

// The readable message: html (if any), text, and what's left as attachments.
export function extractContent(root) {
  const segs = [], attachments = [], cids = new Map();
  const leafName = (n) => n.filename || (n.type === 'message' ? `${header(parseMime(decodeTransfer(n.body, n.encoding)).headers, 'subject') || 'message'}.eml` : '');
  function walk(n) {
    if (n.children) {
      if (n.subtype === 'alternative') {
        const pick = [...n.children].reverse().find((c) => hasType(c, 'text/html'))
          || n.children.find((c) => hasType(c, 'text/plain')) || n.children[n.children.length - 1];
        if (pick) walk(pick);
      } else n.children.forEach(walk);
      return;
    }
    const mime = `${n.type}/${n.subtype}`;
    const att = { part: n.path, filename: leafName(n), type: mime, size: Math.round(n.encoding === 'base64' ? n.body.replace(/\s/g, '').length * 0.75 : n.body.length), cid: n.cid };
    if ((mime === 'text/plain' || mime === 'text/html') && n.disposition !== 'attachment' && !n.filename) {
      segs.push({ kind: mime === 'text/html' ? 'html' : 'text', content: partText(n) });
    } else if (n.type === 'image' && n.disposition !== 'attachment' && (n.cid || n.disposition === 'inline')) {
      if (n.cid) cids.set(n.cid, { n, att });
      if (n.disposition === 'inline' || !n.cid) segs.push({ kind: 'image', n, att });
      else attachments.push(att); // pruned below if the html references it
    } else attachments.push(att);
  }
  walk(root);

  let budget = INLINE_BUDGET;
  const dataUri = (n) => {
    const b = decodeTransfer(n.body, n.encoding);
    if (b.length > budget) return null;
    budget -= b.length;
    return `data:${n.type}/${n.subtype};base64,${btoa(b)}`;
  };
  const text = segs.filter((s) => s.kind === 'text').map((s) => s.content).join('\n');
  let html = null;
  if (segs.some((s) => s.kind === 'html' || s.kind === 'image')) {
    const used = new Set();
    html = segs.map((s) => {
      if (s.kind === 'html') return s.content;
      if (s.kind === 'text') return `<pre style="white-space:pre-wrap;font:inherit">${esc(s.content)}</pre>`;
      if (s.n.cid && used.has(s.n.cid)) return '';
      const uri = dataUri(s.n);
      if (!uri) { attachments.push(s.att); return ''; }
      if (s.n.cid) used.add(s.n.cid);
      return `<img src="${uri}" style="max-width:100%;display:block;margin:8px 0" alt="${esc(s.att.filename)}">`;
    }).join('\n');
    html = html.replace(/cid:([^"'\s)>]+)/gi, (m, id) => {
      const key = decodeURIComponent(id);
      const hit = cids.get(key);
      if (!hit) return m;
      if (!used.has(key)) { const uri = dataUri(hit.n); if (!uri) return m; hit.uri = uri; used.add(key); }
      return hit.uri || m;
    });
    for (const [key] of cids) if (used.has(key)) {
      const i = attachments.findIndex((a) => a.cid === key);
      if (i >= 0) attachments.splice(i, 1);
    }
  }
  return { html, text, attachments };
}

// ---- building ------------------------------------------------------------

export function qpEncode(bin) {
  const out = [];
  for (const line of bin.split('\r\n')) {
    let cur = '';
    const push = (tok) => { if (cur.length + tok.length > 75) { out.push(cur + '='); cur = ''; } cur += tok; };
    for (let i = 0; i < line.length; i++) {
      const c = line.charCodeAt(i);
      const last = i === line.length - 1;
      if ((c >= 33 && c <= 126 && c !== 61) || ((c === 32 || c === 9) && !last)) push(line[i]);
      else push('=' + c.toString(16).toUpperCase().padStart(2, '0'));
    }
    out.push(cur);
  }
  return out.join('\r\n');
}
const wrap76 = (b64) => b64.replace(/.{1,76}/g, '$&\r\n').trimEnd();

function rfc2822Date(d = new Date()) {
  const day = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d.getUTCDay()];
  const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.getUTCMonth()];
  const p = (n) => String(n).padStart(2, '0');
  return `${day}, ${d.getUTCDate()} ${mon} ${d.getUTCFullYear()} ${p(d.getUTCHours())}:${p(d.getUTCMinutes())}:${p(d.getUTCSeconds())} +0000`;
}
const rand = () => [...crypto.getRandomValues(new Uint8Array(12))].map((b) => b.toString(16).padStart(2, '0')).join('');

// msg: { from:{name,email}, to:[], cc:[], subject, text, inReplyTo, references,
//        attachments:[{ filename, type, data /* binary string */ }] }
export function buildMessage(msg) {
  const domain = (msg.from.email.split('@')[1] || 'icloud.com');
  const messageId = `<${rand()}@${domain}>`;
  const h = [
    `From: ${formatAddress(msg.from)}`,
    msg.to?.length && `To: ${msg.to.map(formatAddress).join(', ')}`,
    msg.cc?.length && `Cc: ${msg.cc.map(formatAddress).join(', ')}`,
    msg.bcc?.length && `Bcc: ${msg.bcc.map(formatAddress).join(', ')}`,
    `Subject: ${encodeWord(msg.subject || '')}`,
    `Date: ${rfc2822Date()}`,
    `Message-ID: ${messageId}`,
    msg.inReplyTo && `In-Reply-To: ${msg.inReplyTo}`,
    msg.references && `References: ${msg.references}`,
    'MIME-Version: 1.0',
  ].filter(Boolean);
  const text = utf8ToBin((msg.text || '').replace(/\r?\n/g, '\r\n'));
  const textPart = 'Content-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n' + qpEncode(text);
  let body;
  if (!msg.attachments?.length) body = textPart;
  else {
    const b = `post-${rand()}`;
    h.push(`Content-Type: multipart/mixed; boundary="${b}"`);
    const parts = [textPart, ...msg.attachments.map((a) => {
      const fn = a.filename || 'attachment';
      const name = /[^\x20-\x7e]/.test(fn) ? `filename*=utf-8''${encodeURIComponent(fn)}` : `filename="${fn.replace(/[\\"]/g, '\\$&')}"`;
      return `Content-Type: ${a.type || 'application/octet-stream'}; name="${encodeWord(fn).replace(/"/g, '')}"\r\n`
        + `Content-Disposition: attachment; ${name}\r\nContent-Transfer-Encoding: base64\r\n\r\n${wrap76(btoa(a.data))}`;
    })];
    return { messageId, raw: h.join('\r\n') + '\r\n\r\n' + parts.map((p) => `--${b}\r\n${p}\r\n`).join('') + `--${b}--\r\n` };
  }
  const [ctLine, cteLine, , ...rest] = textPart.split('\r\n');
  return { messageId, raw: [...h, ctLine, cteLine].join('\r\n') + '\r\n\r\n' + rest.join('\r\n') + '\r\n' };
}

// Modified UTF-7 (RFC 3501 §5.1.3) for mailbox names.
export function mutf7Decode(s) {
  return s.replace(/&([^-]*)-/g, (_, b) => {
    if (!b) return '&';
    const bin = b64decodeBin(b.replace(/,/g, '/'));
    let out = '';
    for (let i = 0; i + 1 < bin.length; i += 2) out += String.fromCharCode((bin.charCodeAt(i) << 8) | bin.charCodeAt(i + 1));
    return out;
  });
}
export function mutf7Encode(s) {
  return s.replace(/&/g, '&-').replace(/[^\x20-\x7e]+/g, (run) => {
    let bin = '';
    for (let i = 0; i < run.length; i++) { const c = run.charCodeAt(i); bin += String.fromCharCode(c >> 8, c & 0xff); }
    return '&' + btoa(bin).replace(/=+$/, '').replace(/\//g, ',') + '-';
  });
}
