// Browser geolocation → car.pos. If the Tesla browser exposes GPS (probe
// says), this is free, 1 Hz position for the map, the trip and live shares.

import { emit } from './bus.js';

export function startGeo({ send, geo = globalThis.navigator?.geolocation, minMs = 1000 } = {}) {
  if (!geo) { emit('geo.status', { ok: false, why: 'no api' }); return () => {}; }
  let last = 0, lastSent = null;
  const id = geo.watchPosition((p) => {
    const c = p.coords;
    const pos = { ts: p.timestamp || Date.now(), lat: c.latitude, lng: c.longitude,
      speed: c.speed == null ? null : c.speed * 3.6, heading: c.heading ?? null, acc: c.accuracy };
    emit('geo.status', { ok: true, acc: c.accuracy });
    emit('car.pos', pos);
    const now = Date.now();
    if (now - last < minMs) return;
    // Parked and unchanged → one position a minute is plenty.
    if (lastSent && dist(lastSent, pos) < 0.005 && now - last < 60000) return;
    // Only count it as sent if the link took it; otherwise keep trying.
    if (send?.('car.pos', pos)) { last = now; lastSent = pos; }
  }, (e) => emit('geo.status', { ok: false, why: e.message, code: e.code }),
  { enableHighAccuracy: true, maximumAge: 0, timeout: 30000 });
  return () => geo.clearWatch(id);
}

// km, flat-earth approximation — fine at street scale.
export function dist(a, b) {
  const dy = (b.lat - a.lat) * 111.32;
  const dx = (b.lng - a.lng) * 111.32 * Math.cos(((a.lat + b.lat) / 2) * Math.PI / 180);
  return Math.hypot(dx, dy);
}
