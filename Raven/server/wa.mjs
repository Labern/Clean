// WhatsApp bridge. A linked device (like WhatsApp Web) that never reads
// bodies into the car: it forwards who messaged, counts unread, sends your
// replies and location pins. Baileys speaks the protocol directly, no browser.

import path from 'node:path';
import { rmSync } from 'node:fs';

const DEMO_NAMES = ['Dad', 'Sam', 'Jess', 'Ollie', 'Mum', 'Team ★★★★★', 'Nadia', 'Tom B'];

export function createWhatsApp({ db, hub, dataDir, demo = false, log = console }) {
  const status = { state: 'off', me: null, since: Date.now() };
  const lastKey = new Map(); // jid → last inbound message key (for read receipts)
  let sock = null, stopped = false, demoTimer = null, retry = null;

  function setStatus(state, extra = {}) {
    Object.assign(status, { state, since: Date.now() }, extra);
    hub.broadcast('wa.status', { ...status });
    log.log(`[wa] ${state}`);
  }

  function publishChats() {
    const chats = db.chats(30).map(c => ({ id: c.jid, name: c.name, unread: c.unread, ts: c.last_ts }));
    hub.broadcast('wa.chats', { chats, unread: chats.reduce((a, c) => a + c.unread, 0) });
  }

  function inbound(jid, name, ts) {
    db.chatBump(jid, name, ts);
    db.eventAdd(ts, jid, name);
    hub.broadcast('wa.message', { name, chat: jid, ts }, { remember: false });
    publishChats();
  }

  // ---- Demo: synthetic traffic, no network.
  function startDemo() {
    setStatus('open', { me: 'demo' });
    const now = Date.now();
    DEMO_NAMES.slice(0, 5).forEach((n, i) => db.chatTouch(`demo${i}@s.whatsapp.net`, n, now - (i + 1) * 7 * 60000));
    db.chatBump('demo1@s.whatsapp.net', DEMO_NAMES[1], now - 14 * 60000);
    publishChats();
    demoTimer = setInterval(() => {
      const i = Math.floor(Math.random() * DEMO_NAMES.length);
      inbound(`demo${i}@s.whatsapp.net`, DEMO_NAMES[i], Date.now());
    }, 20000);
  }

  // ---- Real: Baileys.
  async function connect() {
    const B = await import('baileys');
    const { default: makeWASocket, useMultiFileAuthState, fetchLatestBaileysVersion, DisconnectReason, makeCacheableSignalKeyStore, Browsers, isJidGroup, jidNormalizedUser } = B;
    const pino = (await import('pino')).default;
    const logger = pino({ level: process.env.WA_LOG || 'silent' });
    const authDir = path.join(dataDir, 'wa-auth');
    const { state, saveCreds } = await useMultiFileAuthState(authDir);
    const { version } = await fetchLatestBaileysVersion().catch(() => ({ version: undefined }));

    sock = makeWASocket({
      version,
      auth: { creds: state.creds, keys: makeCacheableSignalKeyStore(state.keys, logger) },
      logger,
      browser: Browsers.macOS('Raven'),
      markOnlineOnConnect: false,      // phone keeps getting its own pushes
      syncFullHistory: false,
      generateHighQualityLinkPreview: false,
    });
    setStatus('connecting');

    sock.ev.on('creds.update', saveCreds);

    sock.ev.on('connection.update', async (u) => {
      if (u.qr) {
        const QR = await import('qrcode');
        const svg = await QR.toString(u.qr, { type: 'svg', margin: 1 });
        setStatus('qr');
        hub.broadcast('wa.qr', { svg }, { remember: true });
      }
      if (u.connection === 'open') {
        hub.forget('wa.qr');
        setStatus('open', { me: jidNormalizedUser(sock.user?.id || '') });
        try { await sock.sendPresenceUpdate('unavailable'); } catch {}
        publishChats();
      }
      if (u.connection === 'close') {
        const code = u.lastDisconnect?.error?.output?.statusCode;
        if (code === DisconnectReason.loggedOut) {
          setStatus('logged_out');
          rmSync(authDir, { recursive: true, force: true });
        } else {
          setStatus('reconnecting', { code });
        }
        if (!stopped) retry = setTimeout(connect, code === DisconnectReason.loggedOut ? 1000 : 3000);
      }
    });

    sock.ev.on('contacts.upsert', (cs) => { for (const c of cs) if (c.id && (c.name || c.notify)) db.contactSet(c.id, c.name || c.notify); });
    sock.ev.on('contacts.update', (cs) => { for (const c of cs) if (c.id && (c.name || c.notify)) db.contactSet(c.id, c.name || c.notify); });
    sock.ev.on('chats.upsert', (cs) => { for (const c of cs) if (c.id && c.name) db.contactSet(c.id, c.name); });
    sock.ev.on('chats.update', (cs) => {
      let changed = false;
      for (const c of cs) {
        if (c.id && c.name) db.contactSet(c.id, c.name);
        if (c.id && c.unreadCount === 0) { db.chatRead(c.id); changed = true; } // read on the phone
      }
      if (changed) publishChats();
    });

    sock.ev.on('messages.upsert', ({ messages, type }) => {
      if (type !== 'notify') return;
      for (const m of messages) {
        const jid = m.key?.remoteJid;
        if (!jid || m.key.fromMe || jid === 'status@broadcast' || jid.endsWith('@newsletter')) continue;
        if (!m.message) continue; // protocol/receipt-only
        lastKey.set(jid, m.key);
        const group = isJidGroup(jid);
        const sender = m.pushName || db.contactName(group ? m.key.participant : jid) || jid.split('@')[0];
        const name = group ? `${sender} · ${db.contactName(jid) || 'Group'}` : (db.contactName(jid) || sender);
        inbound(jid, name, (Number(m.messageTimestamp) || Date.now() / 1000) * 1000);
      }
    });
  }

  return {
    status,
    async start() {
      stopped = false;
      if (demo) return startDemo();
      try { await connect(); } catch (e) { setStatus('error', { error: e.message }); if (!stopped) retry = setTimeout(() => this.start(), 5000); }
    },
    stop() {
      stopped = true;
      clearTimeout(retry); clearInterval(demoTimer);
      try { sock?.end?.(); } catch {}
      sock = null;
      setStatus('off');
    },
    chats: publishChats,
    async sendText(jid, text) {
      if (!text || !jid) throw new Error('chat and text required');
      db.chatTouch(jid, db.contactName(jid) || db.chats(100).find(c => c.jid === jid)?.name || jid, Date.now());
      if (demo) { log.log(`[wa demo] → ${jid}: ${text}`); publishChats(); return { ok: true }; }
      if (!sock || status.state !== 'open') throw new Error('WhatsApp not linked');
      await sock.sendMessage(jid, { text });
      publishChats();
      return { ok: true };
    },
    async sendLocation(jid, { lat, lng, name, address }) {
      if (demo) { log.log(`[wa demo] → ${jid}: pin ${lat},${lng}`); return { ok: true }; }
      if (!sock || status.state !== 'open') throw new Error('WhatsApp not linked');
      await sock.sendMessage(jid, { location: { degreesLatitude: lat, degreesLongitude: lng, name, address } });
      return { ok: true };
    },
    async markRead(jid) {
      db.chatRead(jid);
      publishChats();
      const key = lastKey.get(jid);
      if (!demo && sock && key) { try { await sock.readMessages([key]); } catch {} }
      return { ok: true };
    },
  };
}
