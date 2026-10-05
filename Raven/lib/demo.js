// Demo mode: synthetic events so every widget is alive without a server,
// a car, or a sign-in. Turns on for localhost, LAN hosts, or ?demo=1.

import { emit } from './bus.js';

export function isDemo(loc = globalThis.location) {
  if (!loc) return false;
  if (/[?&]demo=1/.test(loc.search)) return true;
  if (/[?&]demo=0/.test(loc.search)) return false;
  return /^(localhost|127\.|192\.168\.|10\.)/.test(loc.hostname);
}

const NAMES = ['Dad', 'Sam', 'Jess', 'Ollie', 'Mum', 'Team ★★★★★', 'Nadia', 'Tom B'];
const TRACKS = [
  { name: 'Running Up That Hill', artist: 'Kate Bush', album: 'Hounds of Love', ms: 300000 },
  { name: 'Teardrop', artist: 'Massive Attack', album: 'Mezzanine', ms: 331000 },
  { name: 'Hunter', artist: 'Björk', album: 'Homogenic', ms: 254000 },
  { name: 'Open Eye Signal', artist: 'Jon Hopkins', album: 'Immunity', ms: 468000 },
];

export function startDemo({ setInterval: si = globalThis.setInterval, now = Date.now } = {}) {
  const timers = [];
  // --- Spotify
  let ti = 0, pos = 42000, playing = true;
  const spot = () => emit('spotify.state', {
    playing, progressMs: pos, track: TRACKS[ti], liked: ti % 2 === 0,
    device: 'iPhone', shuffle: false, art: null, at: now(),
  });
  spot();
  timers.push(si(() => {
    if (playing) pos += 1000;
    if (pos >= TRACKS[ti].ms) { ti = (ti + 1) % TRACKS.length; pos = 0; spot(); }
  }, 1000));
  timers.push(si(spot, 3000));

  // --- WhatsApp
  const chats = NAMES.slice(0, 5).map((name, i) => ({ id: `c${i}`, name, unread: i === 1 ? 2 : 0, ts: now() - (i + 1) * 7 * 60000 }));
  const wa = () => emit('wa.chats', { chats: [...chats].sort((a, b) => b.ts - a.ts), unread: chats.reduce((a, c) => a + c.unread, 0) });
  wa();
  timers.push(si(() => {
    const name = NAMES[Math.floor(Math.random() * NAMES.length)];
    let c = chats.find(x => x.name === name);
    if (!c) { c = { id: `c${chats.length}`, name, unread: 0, ts: 0 }; chats.push(c); }
    c.unread++; c.ts = now();
    emit('wa.message', { name, chat: c.id, ts: c.ts });
    wa();
  }, 25000));

  // --- Car / trip
  const car = { soc: 72, rangeKm: 318, charging: false, inside: 21, outside: 14, odoKm: 61234, speed: 0, lat: 51.5074, lng: -0.1278, heading: 90 };
  let driveStart = now() - 14 * 60000, distKm = 11.2, kwh = 2.9;
  const tick = () => {
    car.speed = Math.max(0, Math.min(110, car.speed + (Math.random() - 0.45) * 12));
    const dKm = car.speed / 3600;
    distKm += dKm; car.odoKm += dKm; kwh += dKm * 0.19;
    car.lng += dKm / 70; // drift east
    emit('tesla.state', { ...car, at: now() });
    emit('drive.update', { startTs: driveStart, distanceKm: distKm, kwh, speed: car.speed, maxSpeed: 104, at: now() });
  };
  tick();
  timers.push(si(tick, 1000));

  // --- History for facts
  emit('drives.history', { drives: demoDrives(now()) });

  return () => timers.forEach(clearInterval);
}

export function demoDrives(now) {
  const out = [];
  let ts = now - 90 * 86400000;
  for (let i = 0; i < 120; i++) {
    const km = 3 + Math.random() ** 2 * 120;
    const h = km / (25 + Math.random() * 60);
    const startSoc = 40 + Math.random() * 55;
    out.push({ startTs: ts, endTs: ts + h * 3600000, durationMs: h * 3600000, distanceKm: km,
      maxSpeed: 60 + Math.random() * 70, avgSpeed: km / h, startSoc, endSoc: startSoc - km * 0.19,
      start: { lat: 51.5, lng: -0.12 }, end: { lat: 51.5 + Math.random() * 0.5, lng: -0.12 + Math.random() } });
    ts += (0.3 + Math.random()) * 86400000;
  }
  return out;
}
