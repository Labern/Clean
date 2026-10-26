// The bridge's HTTP API. Stateless: every request opens a connection to Apple,
// signs in with the credentials in its Authorization header, does one job and
// signs out. Nothing is stored. It can only ever talk to Apple's two mail
// hosts, so it is not a general-purpose socket relay.

import { Imap, Smtp, ProtocolError, fetchMap, astring } from './protocol.js';
import {
  parseMime, extractContent, findPart, decodeTransfer, decodeCharset, decodeWords, bin8ToText,
  header, rawHeader, parseAddresses, buildMessage, mutf7Decode, b64decodeBin, binToU8,
} from './mime.js';

export const ICLOUD = {
  imap: { host: 'imap.mail.me.com', port: 993, tls: 'implicit' },
  smtp: { host: 'smtp.mail.me.com', port: 587, tls: 'starttls' },
};

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type',
  'Access-Control-Max-Age': '86400',
};
const json = (o, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...CORS, 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' } });

// ---- helpers ---------------------------------------------------------------

const text8 = (s) => (s == null ? '' : decodeWords(bin8ToText(s)));
const envAddrs = (list) => (Array.isArray(list) ? list : [])
  .filter((a) => Array.isArray(a) && a[3] != null)
  .map((a) => ({ name: text8(a[0]), email: `${a[2] || ''}@${a[3]}`.toLowerCase() }));

const SPECIAL = {
  '\\SENT': 'sent', '\\TRASH': 'trash', '\\DRAFTS': 'drafts', '\\JUNK': 'junk', '\\ARCHIVE': 'archive', '\\ALL': 'all', '\\FLAGGED': 'flagged',
};
const BY_NAME = {
  'sent messages': 'sent', sent: 'sent', 'sent items': 'sent', 'deleted messages': 'trash', trash: 'trash', 'deleted items': 'trash',
  drafts: 'drafts', junk: 'junk', spam: 'junk', 'bulk mail': 'junk', archive: 'archive',
};

function parseBodystructure(node, path = '') {
  if (!Array.isArray(node)) return null;
  if (Array.isArray(node[0])) {
    const children = [];
    let i = 0;
    for (; Array.isArray(node[i]); i++) children.push(parseBodystructure(node[i], path ? `${path}.${i + 1}` : String(i + 1)));
    return { type: 'multipart', subtype: String(node[i] || '').toLowerCase(), children, path };
  }
  const type = String(node[0] || '').toLowerCase(), subtype = String(node[1] || '').toLowerCase();
  const params = {};
  if (Array.isArray(node[2])) for (let i = 0; i + 1 < node[2].length; i += 2) params[String(node[2][i]).toLowerCase()] = node[2][i + 1];
  const dispAt = type === 'text' ? 9 : type === 'message' && subtype === 'rfc822' ? 11 : 8;
  const disp = Array.isArray(node[dispAt]) ? node[dispAt] : null;
  const dparams = {};
  if (disp && Array.isArray(disp[1])) for (let i = 0; i + 1 < disp[1].length; i += 2) dparams[String(disp[1][i]).toLowerCase()] = disp[1][i + 1];
  return {
    type, subtype, params, path: path || '1', encoding: String(node[5] || '').toLowerCase(), size: +node[6] || 0,
    disposition: disp ? String(disp[0]).toLowerCase() : '', filename: dparams.filename || dparams['filename*'] || params.name || '',
  };
}
const leaves = (n, out = []) => { if (!n) return out; if (n.children) n.children.forEach((c) => leaves(c, out)); else out.push(n); return out; };
function previewPart(bs) {
  const body = leaves(bs).filter((l) => l.type === 'text' && l.disposition !== 'attachment' && !l.filename);
  return body.find((l) => l.subtype === 'plain') || body.find((l) => l.subtype === 'html') || null;
}
const hasAttachments = (bs) => leaves(bs).some((l) => l.disposition === 'attachment' || (l.filename && l.type !== 'text' && !(l.type === 'image' && l.disposition === 'inline')));

export function htmlToText(html) {
  return html
    .replace(/<(head|style|script|title)[^>]*>[\s\S]*?<\/\1>/gi, ' ')
    .replace(/<(head|style|script)[^>]*>[\s\S]*$/gi, ' ') // truncated mid-block
    .replace(/<br\s*\/?>|<\/(p|div|tr|li|h\d)>/gi, '\n')
    .replace(/<[^>]*>?/g, ' ')
    .replace(/&nbsp;/gi, ' ').replace(/&amp;/gi, '&').replace(/&lt;/gi, '<').replace(/&gt;/gi, '>').replace(/&quot;/gi, '"').replace(/&#39;|&apos;/gi, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n)).replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/&[a-z]+;/gi, ' ');
}
function previewText(raw, part) {
  let t = decodeCharset(decodeTransfer(raw, part.encoding), part.params.charset);
  if (part.subtype === 'html') t = htmlToText(t);
  return t.split(/\r?\n/).filter((l) => !/^\s*>/.test(l)).join(' ').replace(/[​-‏­͏﻿]/g, '').replace(/\s+/g, ' ').trim().slice(0, 220);
}

function summarize(f, seq) {
  const env = f.ENVELOPE || [];
  const bs = parseBodystructure(f.BODYSTRUCTURE);
  return {
    uid: +f.UID, seq: +seq,
    flags: (f.FLAGS || []).map(String),
    date: Date.parse(text8(env[0])) || Date.parse(String(f.INTERNALDATE || '').replace(/^(\d+)-(\w+)-(\d+)/, '$1 $2 $3')) || null,
    subject: text8(env[1]),
    from: envAddrs(env[2]), to: envAddrs(env[5]), cc: envAddrs(env[6]), replyTo: envAddrs(env[4]),
    inReplyTo: env[8] || null, messageId: env[9] || null,
    size: +f['RFC822.SIZE'] || 0,
    attachments: hasAttachments(bs),
    _bs: bs,
  };
}

async function selectBox(imap, mailbox, readOnly) {
  const r = await imap.cmd(readOnly ? 'EXAMINE ' : 'SELECT ', astring(mailbox));
  const info = { exists: 0, uidvalidity: 0, uidnext: 0 };
  for (const u of r.untagged) {
    let m;
    if ((m = /^\* (\d+) EXISTS/i.exec(u.text))) info.exists = +m[1];
    if ((m = /\[UIDVALIDITY (\d+)\]/i.exec(u.text))) info.uidvalidity = +m[1];
    if ((m = /\[UIDNEXT (\d+)\]/i.exec(u.text))) info.uidnext = +m[1];
  }
  return info;
}

const FETCH_SUMMARY = '(UID FLAGS INTERNALDATE RFC822.SIZE ENVELOPE BODYSTRUCTURE)';

async function fetchSummaries(imap, set, byUid) {
  const r = await imap.cmd(`${byUid ? 'UID ' : ''}FETCH ${set} ${FETCH_SUMMARY}`);
  const msgs = [];
  for (const u of r.untagged) {
    const t = u.tokens;
    if (t[0] === '*' && String(t[2]).toUpperCase() === 'FETCH' && Array.isArray(t[3])) {
      const f = fetchMap(t[3]);
      if (f.UID && f.ENVELOPE) msgs.push(summarize(f, t[1]));
    }
  }
  // Previews: one partial fetch per distinct part path, all on this connection.
  const groups = new Map();
  for (const m of msgs) {
    const p = previewPart(m._bs);
    if (!p) { m.preview = ''; continue; }
    m._pp = p;
    const n = p.subtype === 'html' ? 4096 : 700;
    const key = `${p.path}|${n}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(m);
  }
  for (const [key, group] of groups) {
    const [path, n] = key.split('|');
    const byU = new Map(group.map((m) => [m.uid, m]));
    const r2 = await imap.cmd(`UID FETCH ${group.map((m) => m.uid).join(',')} (UID BODY.PEEK[${path}]<0.${n}>)`);
    for (const u of r2.untagged) {
      const t = u.tokens;
      if (!Array.isArray(t[3])) continue;
      const f = fetchMap(t[3]);
      const m = byU.get(+f.UID);
      if (!m) continue;
      const raw = Object.entries(f).find(([k]) => k.startsWith('BODY['))?.[1] || '';
      m.preview = previewText(String(raw), m._pp);
    }
  }
  for (const m of msgs) { delete m._bs; delete m._pp; m.preview ??= ''; }
  return msgs.sort((a, b) => b.seq - a.seq);
}

async function listMailboxes(imap) {
  const r = await imap.cmd(imap.caps.has('SPECIAL-USE') ? 'LIST "" "*" RETURN (SPECIAL-USE)' : 'LIST "" "*"');
  const boxes = [];
  for (const u of r.untagged) {
    const t = u.tokens;
    if (String(t[1]).toUpperCase() !== 'LIST') continue;
    const flags = (t[2] || []).map((f) => String(f).toUpperCase());
    const path = String(t[4] ?? '');
    const delim = t[3] || '/';
    const name = mutf7Decode(path);
    const leaf = name.split(delim).pop();
    const flagged = flags.map((f) => SPECIAL[f]).find(Boolean);
    const special = flagged || (path.toUpperCase() === 'INBOX' ? 'inbox' : BY_NAME[name.toLowerCase()] || null);
    boxes.push({ _flagged: !!flagged, path, name: path.toUpperCase() === 'INBOX' ? 'Inbox' : leaf, full: name, delim, special, noselect: flags.includes('\\NOSELECT') || flags.includes('\\NONEXISTENT'), depth: name.split(delim).length - 1 });
  }
  // One special per role: a flagged mailbox beats a name match.
  const seen = new Set();
  for (const b of [...boxes].sort((a, b) => b._flagged - a._flagged)) {
    if (!b.special) continue;
    if (seen.has(b.special)) b.special = null; else seen.add(b.special);
  }
  for (const b of boxes) {
    delete b._flagged;
    if (b.noselect) continue;
    try {
      const s = await imap.cmd('STATUS ', astring(b.path), ' (MESSAGES UNSEEN UIDNEXT)');
      for (const u of s.untagged) {
        const m = /\(([^)]*)\)\s*$/.exec(u.text);
        if (!m) continue;
        const kv = m[1].split(/\s+/);
        for (let i = 0; i + 1 < kv.length; i += 2) b[{ MESSAGES: 'total', UNSEEN: 'unseen', UIDNEXT: 'uidnext' }[kv[i].toUpperCase()] || '_'] = +kv[i + 1];
      }
      delete b._;
    } catch { /* a mailbox we can't STATUS still lists */ }
  }
  return boxes;
}
function specialPath(boxes, role) { return boxes.find((b) => b.special === role)?.path || null; }

async function moveUids(imap, uids, to) {
  const set = uids.join(',');
  if (imap.caps.has('MOVE')) return imap.cmd(`UID MOVE ${set} `, astring(to));
  await imap.cmd(`UID COPY ${set} `, astring(to));
  await imap.cmd(`UID STORE ${set} +FLAGS.SILENT (\\Deleted)`);
  await imap.cmd(imap.caps.has('UIDPLUS') ? `UID EXPUNGE ${set}` : 'EXPUNGE');
}

async function fullMessage(imap, uid) {
  const r = await imap.cmd(`UID FETCH ${uid} (UID FLAGS INTERNALDATE BODY.PEEK[])`);
  for (const u of r.untagged) {
    const t = u.tokens;
    if (!Array.isArray(t[3])) continue;
    const f = fetchMap(t[3]);
    if (+f.UID === +uid && f['BODY[]'] != null) return { raw: String(f['BODY[]']), flags: (f.FLAGS || []).map(String), internal: f.INTERNALDATE };
  }
  throw new ProtocolError('Message not found — it may have been moved or deleted', 'notfound');
}

// Search terms: a phrase matches From, To, Subject or body. "from:x" etc. narrow.
// Keywords are plain strings; values are wrapped as { v } so they get quoted.
export function searchCriteria(q) {
  const terms = [];
  const re = /(\w+):("([^"]*)"|\S+)|"([^"]*)"|(\S+)/g;
  let m;
  while ((m = re.exec(q))) {
    const key = m[1]?.toLowerCase();
    const val = m[3] ?? m[2] ?? m[4] ?? m[5];
    if (key === 'is' && /^unread$/i.test(val)) terms.push('UNSEEN');
    else if (key === 'is' && /^(flagged|starred)$/i.test(val)) terms.push('FLAGGED');
    else if (key === 'has' && /^attachments?$/i.test(val)) terms.push('HEADER', { v: 'Content-Type' }, { v: 'multipart/mixed' });
    else if (['from', 'to', 'cc', 'subject', 'body'].includes(key)) terms.push(key.toUpperCase(), { v: val });
    else {
      const v = { v: m[1] ? m[0] : val };
      terms.push('OR', 'OR', 'FROM', v, 'SUBJECT', v, 'OR', 'TO', v, 'BODY', v);
    }
  }
  const args = [];
  for (const t of terms) {
    if (args.length) args.push(' ');
    args.push(typeof t === 'string' ? t : astring(t.v));
  }
  return args;
}

// ---- handlers ----------------------------------------------------------------

const handlers = {
  async mailboxes({ imap }) {
    return { mailboxes: await listMailboxes(imap) };
  },

  async list({ imap }, { mailbox = 'INBOX', end, count = 50 }) {
    const info = await selectBox(imap, mailbox, true);
    count = Math.min(Math.max(+count || 50, 1), 200);
    const hi = Math.min(+end || info.exists, info.exists);
    if (hi < 1) return { ...info, messages: [], end: 0 };
    const lo = Math.max(1, hi - count + 1);
    const messages = await fetchSummaries(imap, `${lo}:${hi}`, false);
    return { ...info, messages, end: lo - 1 };
  },

  // New mail since uidnext, plus current flags for the uids the app shows.
  async sync({ imap }, { mailbox = 'INBOX', since, uids = [] }) {
    const info = await selectBox(imap, mailbox, true);
    let messages = [];
    if (since && info.uidnext > since) messages = (await fetchSummaries(imap, `${since}:*`, true)).filter((m) => m.uid >= since);
    const flags = {};
    const known = uids.filter((u) => Number.isInteger(u) && u > 0).slice(0, 500);
    if (known.length) {
      const r = await imap.cmd(`UID FETCH ${known.join(',')} (UID FLAGS)`);
      for (const u of r.untagged) {
        if (!Array.isArray(u.tokens[3])) continue;
        const f = fetchMap(u.tokens[3]);
        if (f.UID) flags[+f.UID] = (f.FLAGS || []).map(String);
      }
    }
    return { ...info, messages, flags };
  },

  async message({ imap }, { mailbox = 'INBOX', uid, markSeen = true }) {
    await selectBox(imap, mailbox, !markSeen);
    const { raw, flags } = await fullMessage(imap, uid);
    const root = parseMime(raw);
    const h = root.headers;
    const content = extractContent(root);
    if (markSeen && !flags.includes('\\Seen')) {
      await imap.cmd(`UID STORE ${uid} +FLAGS.SILENT (\\Seen)`);
      flags.push('\\Seen');
    }
    const listUnsub = rawHeader(h, 'list-unsubscribe');
    return {
      uid: +uid, flags,
      subject: header(h, 'subject'),
      from: parseAddresses(rawHeader(h, 'from')), to: parseAddresses(rawHeader(h, 'to')),
      cc: parseAddresses(rawHeader(h, 'cc')), bcc: parseAddresses(rawHeader(h, 'bcc')), replyTo: parseAddresses(rawHeader(h, 'reply-to')),
      inReplyTo: rawHeader(h, 'in-reply-to') || null,
      date: Date.parse(rawHeader(h, 'date')) || null,
      messageId: rawHeader(h, 'message-id') || null,
      references: rawHeader(h, 'references') || null,
      unsubscribe: (listUnsub.match(/<(https?:[^>]+)>/) || [])[1] || (listUnsub.match(/<(mailto:[^>]+)>/) || [])[1] || null,
      ...content,
    };
  },

  async raw({ imap }, { mailbox = 'INBOX', uid }) {
    await selectBox(imap, mailbox, true);
    const { raw } = await fullMessage(imap, uid);
    return new Response(binToU8(raw), { headers: { ...CORS, 'Content-Type': 'message/rfc822', 'Content-Disposition': `attachment; filename="message-${uid}.eml"` } });
  },

  async attachment({ imap }, { mailbox = 'INBOX', uid, part }) {
    await selectBox(imap, mailbox, true);
    const { raw } = await fullMessage(imap, uid);
    const node = findPart(parseMime(raw), String(part));
    if (!node) throw new ProtocolError('Attachment not found', 'notfound');
    const data = decodeTransfer(node.body, node.encoding);
    const name = node.filename || `attachment-${part}`;
    return new Response(binToU8(data), {
      headers: {
        ...CORS, 'Content-Type': `${node.type}/${node.subtype}`,
        'Content-Disposition': `attachment; filename*=UTF-8''${encodeURIComponent(name)}`,
        'Access-Control-Expose-Headers': 'Content-Disposition',
      },
    });
  },

  async flags({ imap }, { mailbox = 'INBOX', uids, add = [], remove = [] }) {
    const ok = (f) => /^\\?[\w$-]+$/.test(f);
    await selectBox(imap, mailbox, false);
    const set = uids.map(Number).filter(Boolean).join(',');
    if (!set) return { ok: true };
    if (add.length) await imap.cmd(`UID STORE ${set} +FLAGS.SILENT (${add.filter(ok).join(' ')})`);
    if (remove.length) await imap.cmd(`UID STORE ${set} -FLAGS.SILENT (${remove.filter(ok).join(' ')})`);
    return { ok: true };
  },

  async move({ imap }, { mailbox = 'INBOX', uids, to }) {
    await selectBox(imap, mailbox, false);
    await moveUids(imap, uids.map(Number).filter(Boolean), to);
    return { ok: true };
  },

  // To Trash; already in Trash (or no Trash) means gone for good.
  async delete({ imap }, { mailbox = 'INBOX', uids, trash }) {
    trash ||= specialPath(await listMailboxesLite(imap), 'trash');
    await selectBox(imap, mailbox, false);
    const list = uids.map(Number).filter(Boolean);
    if (trash && trash !== mailbox) { await moveUids(imap, list, trash); return { ok: true, moved: trash }; }
    await imap.cmd(`UID STORE ${list.join(',')} +FLAGS.SILENT (\\Deleted)`);
    await imap.cmd(imap.caps.has('UIDPLUS') ? `UID EXPUNGE ${list.join(',')}` : 'EXPUNGE');
    return { ok: true, expunged: true };
  },

  async search({ imap }, { mailbox = 'INBOX', query = '' }) {
    if (!query.trim()) return { messages: [] };
    await selectBox(imap, mailbox, true);
    const crit = searchCriteria(query);
    const utf = crit.some((a) => typeof a === 'object');
    const r = await imap.cmd(`UID SEARCH ${utf ? 'CHARSET UTF-8 ' : ''}`, ...crit);
    const uids = [];
    for (const u of r.untagged) if (/^\* SEARCH/i.test(u.text)) uids.push(...u.text.slice(9).trim().split(/\s+/).filter(Boolean).map(Number));
    const top = uids.sort((a, b) => b - a).slice(0, 100);
    const messages = top.length ? await fetchSummaries(imap, top.join(','), true) : [];
    return { messages: messages.sort((a, b) => b.uid - a.uid), total: uids.length };
  },

  async send({ imap, creds, env }, body) {
    const attachments = (body.attachments || []).map((a) => ({ filename: a.filename, type: a.type, data: b64decodeBin(a.data || '') }));
    // Forwarding: the original's attachments come straight from the server.
    if (body.forward?.uid) {
      await selectBox(imap, body.forward.mailbox || 'INBOX', true);
      const { raw } = await fullMessage(imap, body.forward.uid);
      const root = parseMime(raw);
      // Everything that isn't the body text: attachments and inline images
      // (the forwarded body is plain text, so images would otherwise vanish).
      const keep = new Set(body.forward.parts || leaves(root).filter((n) => !((n.type === 'text' && (n.subtype === 'plain' || n.subtype === 'html')) && n.disposition !== 'attachment' && !n.filename)).map((n) => n.path));
      for (const part of keep) {
        const n = findPart(root, part);
        if (n) attachments.push({ filename: n.filename || `attachment-${part}`, type: `${n.type}/${n.subtype}`, data: decodeTransfer(n.body, n.encoding) });
      }
    }
    const from = { name: body.fromName || '', email: body.from || creds.user };
    const { raw, messageId } = buildMessage({
      from, to: body.to || [], cc: body.cc || [], subject: body.subject, text: body.text,
      inReplyTo: body.inReplyTo, references: body.references, attachments,
    });
    const rcpts = [...(body.to || []), ...(body.cc || []), ...(body.bcc || [])].map((a) => a.email).filter(Boolean);
    if (!rcpts.length) throw new ProtocolError('No recipients', 'input');
    const s = env.smtp;
    const smtp = new Smtp(await env.open(s.host, s.port, s.tls));
    try {
      await smtp.session({ user: creds.user, pass: creds.pass, from: from.email, rcpts, data: raw, requireTls: s.tls === 'implicit' ? 'implicit' : !env.insecure });
    } finally { try { smtp.sock.close(); } catch {} }
    // iCloud's SMTP does not file a copy; do it like Mail.app does.
    let saved = null;
    try {
      const sent = body.sentMailbox || specialPath(await listMailboxesLite(imap), 'sent');
      if (sent) {
        await imap.cmd('APPEND ', astring(sent), ' (\\Seen) ', { lit: raw });
        saved = sent;
      }
      if (body.deleteDraft?.uid) await removeUid(imap, body.deleteDraft.mailbox, body.deleteDraft.uid);
      if (body.inReplyTo && body.replyTo?.uid) {
        await selectBox(imap, body.replyTo.mailbox || 'INBOX', false);
        await imap.cmd(`UID STORE ${+body.replyTo.uid} +FLAGS.SILENT (\\Answered)`);
      }
    } catch { /* sent is sent; filing is best-effort */ }
    return { ok: true, messageId, saved };
  },

  // Save to Drafts (replacing the previous version) so it shows up in Mail
  // on every device, exactly like Mail.app's own drafts.
  async draft({ imap, creds }, body) {
    const drafts = body.draftsMailbox || specialPath(await listMailboxesLite(imap), 'drafts');
    if (!drafts) throw new ProtocolError('No Drafts mailbox', 'notfound');
    const { raw } = buildMessage({
      from: { name: body.fromName || '', email: body.from || creds.user },
      to: body.to || [], cc: body.cc || [], bcc: body.bcc || [], subject: body.subject, text: body.text,
      inReplyTo: body.inReplyTo, references: body.references, attachments: [],
    });
    await imap.cmd('APPEND ', astring(drafts), ' (\\Seen \\Draft) ', { lit: raw });
    if (body.replace) await removeUid(imap, drafts, body.replace);
    return { ok: true, saved: drafts };
  },

  async ping() { return { ok: true }; },
};

async function removeUid(imap, mailbox, uid) {
  await selectBox(imap, mailbox, false);
  await imap.cmd(`UID STORE ${+uid} +FLAGS.SILENT (\\Deleted)`);
  await imap.cmd(imap.caps.has('UIDPLUS') ? `UID EXPUNGE ${+uid}` : 'EXPUNGE');
}

async function listMailboxesLite(imap) {
  const r = await imap.cmd(imap.caps.has('SPECIAL-USE') ? 'LIST "" "*" RETURN (SPECIAL-USE)' : 'LIST "" "*"');
  return r.untagged.filter((u) => String(u.tokens[1]).toUpperCase() === 'LIST').map((u) => {
    const flags = (u.tokens[2] || []).map((f) => String(f).toUpperCase());
    const path = String(u.tokens[4] ?? '');
    return { path, special: flags.map((f) => SPECIAL[f]).find(Boolean) || BY_NAME[mutf7Decode(path).toLowerCase()] || null };
  });
}

function credsFrom(req) {
  const m = /^Basic\s+(.+)$/i.exec(req.headers.get('Authorization') || '');
  if (!m) return null;
  let s;
  try { s = new TextDecoder().decode(binToU8(atob(m[1]))); } catch { return null; }
  const i = s.indexOf(':');
  if (i < 0) return null;
  let pass = s.slice(i + 1).trim();
  const letters = pass.replace(/[\s-]/g, '');
  if (/^[a-z]{16}$/i.test(letters)) pass = letters.toLowerCase().match(/.{4}/g).join('-'); // Apple's canonical form
  return { user: s.slice(0, i).trim(), pass };
}

// env: { open(host, port, tls) -> socket, imap, smtp, insecure }
export async function handle(req, env) {
  const url = new URL(req.url);
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  const name = url.pathname.replace(/^.*\/api\//, '');
  if (!url.pathname.includes('/api/') || !Object.hasOwn(handlers, name)) return json({ error: 'Not found' }, 404);
  if (name === 'ping') return json({ ok: true, service: 'post-bridge' });
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405);
  const creds = credsFrom(req);
  if (!creds || !creds.user || !creds.pass) return json({ error: 'Missing credentials', kind: 'auth' }, 401);
  let body = {};
  try { body = await req.json(); } catch {}
  env = { imap: ICLOUD.imap, smtp: ICLOUD.smtp, ...env };
  let imap;
  try {
    imap = new Imap(await env.open(env.imap.host, env.imap.port, env.imap.tls));
    await imap.greet();
    await imap.login(creds.user, creds.pass);
    const out = await handlers[name]({ imap, creds, env }, body);
    return out instanceof Response ? out : json(out);
  } catch (e) {
    const kind = e.kind || 'network';
    const status = { auth: 401, notfound: 404, input: 400, rejected: 422 }[kind] || 502;
    const msg = kind === 'auth'
      ? 'Apple refused the sign-in. Use an app-specific password (account.apple.com → Sign-In and Security), not your Apple Account password.'
      : e.message || String(e);
    return json({ error: msg, kind }, status);
  } finally {
    if (imap) { await Promise.race([imap.logout(), new Promise((r) => setTimeout(r, 1500))]); try { imap.c.sock.close(); } catch {} }
  }
}
