// SQLite via node:sqlite (Node ≥ 22.13, no native build). Names, counts,
// shares, positions. Never message bodies.

import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import path from 'node:path';

export function openDb(dir) {
  mkdirSync(dir, { recursive: true });
  const db = new DatabaseSync(path.join(dir, 'raven.db'));
  db.exec(`
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY, v TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS wa_contacts (jid TEXT PRIMARY KEY, name TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS wa_chats (jid TEXT PRIMARY KEY, name TEXT NOT NULL, unread INTEGER NOT NULL DEFAULT 0, last_ts INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS wa_events (id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, jid TEXT NOT NULL, name TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS shares (token TEXT PRIMARY KEY, jid TEXT NOT NULL, name TEXT NOT NULL, created INTEGER NOT NULL, expires INTEGER NOT NULL, active INTEGER NOT NULL DEFAULT 1, refresh_min INTEGER NOT NULL DEFAULT 0, last_pin INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS positions (ts INTEGER PRIMARY KEY, lat REAL NOT NULL, lng REAL NOT NULL, speed REAL, heading REAL);
  `);

  const q = {
    kvGet: db.prepare('SELECT v FROM kv WHERE k = ?'),
    kvSet: db.prepare('INSERT INTO kv (k, v) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v'),
    contactSet: db.prepare('INSERT INTO wa_contacts (jid, name) VALUES (?, ?) ON CONFLICT(jid) DO UPDATE SET name = excluded.name'),
    contactGet: db.prepare('SELECT name FROM wa_contacts WHERE jid = ?'),
    chatBump: db.prepare(`INSERT INTO wa_chats (jid, name, unread, last_ts) VALUES (?, ?, 1, ?)
      ON CONFLICT(jid) DO UPDATE SET name = excluded.name, unread = unread + 1, last_ts = excluded.last_ts`),
    chatTouch: db.prepare(`INSERT INTO wa_chats (jid, name, unread, last_ts) VALUES (?, ?, 0, ?)
      ON CONFLICT(jid) DO UPDATE SET name = excluded.name, last_ts = MAX(last_ts, excluded.last_ts)`),
    chatRead: db.prepare('UPDATE wa_chats SET unread = 0 WHERE jid = ?'),
    chats: db.prepare('SELECT jid, name, unread, last_ts FROM wa_chats ORDER BY last_ts DESC LIMIT ?'),
    eventAdd: db.prepare('INSERT INTO wa_events (ts, jid, name) VALUES (?, ?, ?)'),
    shareAdd: db.prepare('INSERT INTO shares (token, jid, name, created, expires, refresh_min, last_pin) VALUES (?, ?, ?, ?, ?, ?, ?)'),
    shareGet: db.prepare('SELECT * FROM shares WHERE token = ?'),
    shareActive: db.prepare('SELECT * FROM shares WHERE active = 1 AND expires > ? ORDER BY created DESC'),
    shareStop: db.prepare('UPDATE shares SET active = 0 WHERE token = ?'),
    shareExpire: db.prepare('UPDATE shares SET active = 0 WHERE active = 1 AND expires <= ?'),
    sharePinned: db.prepare('UPDATE shares SET last_pin = ? WHERE token = ?'),
    posAdd: db.prepare('INSERT OR REPLACE INTO positions (ts, lat, lng, speed, heading) VALUES (?, ?, ?, ?, ?)'),
    posLast: db.prepare('SELECT * FROM positions ORDER BY ts DESC LIMIT 1'),
    posSince: db.prepare('SELECT * FROM positions WHERE ts >= ? ORDER BY ts'),
    posPrune: db.prepare('DELETE FROM positions WHERE ts < ?'),
  };

  return {
    raw: db,
    kvGet: (k, def = null) => { const r = q.kvGet.get(k); return r ? JSON.parse(r.v) : def; },
    kvSet: (k, v) => q.kvSet.run(k, JSON.stringify(v)),
    contactSet: (jid, name) => q.contactSet.run(jid, name),
    contactName: (jid) => q.contactGet.get(jid)?.name ?? null,
    chatBump: (jid, name, ts) => q.chatBump.run(jid, name, ts),
    chatTouch: (jid, name, ts) => q.chatTouch.run(jid, name, ts),
    chatRead: (jid) => q.chatRead.run(jid),
    chats: (limit = 30) => q.chats.all(limit),
    eventAdd: (ts, jid, name) => q.eventAdd.run(ts, jid, name),
    shareAdd: (s) => q.shareAdd.run(s.token, s.jid, s.name, s.created, s.expires, s.refreshMin || 0, s.lastPin || 0),
    shareGet: (token) => q.shareGet.get(token) ?? null,
    shareActive: (now = Date.now()) => q.shareActive.all(now),
    shareStop: (token) => q.shareStop.run(token),
    shareExpire: (now = Date.now()) => q.shareExpire.run(now).changes,
    sharePinned: (token, ts) => q.sharePinned.run(ts, token),
    posAdd: (p) => q.posAdd.run(p.ts, p.lat, p.lng, p.speed ?? null, p.heading ?? null),
    posLast: () => q.posLast.get() ?? null,
    posSince: (ts) => q.posSince.all(ts),
    posPrune: (before) => q.posPrune.run(before).changes,
    close: () => db.close(),
  };
}
