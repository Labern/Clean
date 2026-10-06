// Trip from the car's own GPS: segments car.pos into drives, emits the live
// drive.update, and keeps finished drives in localStorage so Facts has
// history from day one — no server, no Tesla API.

import { on, emit } from './bus.js';
import { createSegmenter } from './drives.js';

export const HISTORY_KEY = 'raven_drives_v1';

export function startTrip({ storage = globalThis.localStorage, now = Date.now } = {}) {
  let history = [];
  try { history = JSON.parse(storage?.getItem(HISTORY_KEY) || '[]'); } catch {}
  const seg = createSegmenter();
  let lastCount = 0;

  const save = () => { try { storage?.setItem(HISTORY_KEY, JSON.stringify(history.slice(-2000))); } catch {} };
  const publishHistory = () => emit('drives.history', { drives: history });
  publishHistory();

  const off = on('car.pos', (p) => {
    seg.push({ ts: p.ts || now(), lat: p.lat, lng: p.lng, speed: p.speed ?? 0 });
    const cur = seg.current;
    if (cur) {
      emit('drive.update', {
        startTs: cur.startTs, distanceKm: cur.distanceKm, kwh: null,
        speed: p.speed ?? 0, maxSpeed: cur.maxSpeed, at: p.ts || now(), live: true,
      });
    }
    if (seg.drives.length > lastCount) {
      const done = seg.drives.slice(lastCount).map(({ samples, lastTs, ...d }) => d);
      lastCount = seg.drives.length;
      history.push(...done.filter(d => d.distanceKm >= 0.2)); // ignore shuffles
      save(); publishHistory();
      emit('drive.done', done[done.length - 1]);
      emit('drive.update', null);
    }
  });

  return { stop: off, get history() { return history; }, get current() { return seg.current; } };
}
