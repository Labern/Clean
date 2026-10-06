// "Share where I am": a token the recipient's browser polls. The car feeds
// positions; each active share reads the latest. Optional pin refresh keeps
// a fresh location bubble inside WhatsApp too.

import { randomBytes } from 'node:crypto';

export function createLive({ db, now = Date.now, owner = 'Raven' }) {
  return {
    create({ jid, name, minutes = 60, refreshMin = 0 }) {
      const token = randomBytes(12).toString('base64url');
      const created = now();
      const s = { token, jid, name, created, expires: minutes > 0 ? created + minutes * 60000 : created + 24 * 3600000, refreshMin, lastPin: created };
      db.shareAdd(s);
      return s;
    },
    stop(token) { db.shareStop(token); },
    active() { db.shareExpire(now()); return db.shareActive(now()); },
    // What a recipient sees: the sharer's name, never the chat or the
    // recipient's own name.
    view(token) {
      const s = db.shareGet(token);
      if (!s) return null;
      const alive = !!s.active && s.expires > now();
      const p = db.posLast();
      return {
        name: owner,
        active: alive,
        expires: s.expires,
        pos: p ? { ts: p.ts, lat: p.lat, lng: p.lng, speed: p.speed, heading: p.heading } : null,
        trail: alive ? db.posSince(now() - 30 * 60000).map(r => [r.lat, r.lng]) : [],
      };
    },
    // Shares whose WhatsApp pin is older than their refresh interval.
    duePins() {
      const t = now();
      return this.active().filter(s => s.refresh_min > 0 && t - s.last_pin >= s.refresh_min * 60000);
    },
    pinned(token) { db.sharePinned(token, now()); },
  };
}
