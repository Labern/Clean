// Drive segmentation and the statistics the car never shows you.
// A sample is { ts, lat, lng, speed (km/h), odo (km, optional), soc (%, optional) }.

export const START_SPEED = 5;      // km/h: moving above this starts a drive
export const STOP_AFTER_MS = 5 * 60000; // stopped this long ends the drive

const R = 6371; // km
export function haversine(a, b) {
  const dLat = (b.lat - a.lat) * Math.PI / 180;
  const dLng = (b.lng - a.lng) * Math.PI / 180;
  const s = Math.sin(dLat / 2) ** 2 +
    Math.cos(a.lat * Math.PI / 180) * Math.cos(b.lat * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

// Feed samples in order; returns completed drives and the one in progress.
export function createSegmenter(opts = {}) {
  const startSpeed = opts.startSpeed ?? START_SPEED;
  const stopAfter = opts.stopAfter ?? STOP_AFTER_MS;
  let cur = null, stoppedAt = null, prev = null;
  const drives = [];

  function close(endTs) {
    if (!cur) return;
    cur.endTs = endTs;
    cur.durationMs = cur.endTs - cur.startTs;
    cur.avgSpeed = cur.durationMs ? cur.distanceKm / (cur.durationMs / 3600000) : 0;
    drives.push(cur);
    cur = null; stoppedAt = null;
  }

  return {
    push(s) {
      const moving = s.speed >= startSpeed;
      if (!cur && moving) {
        cur = { startTs: s.ts, start: { lat: s.lat, lng: s.lng }, startOdo: s.odo ?? null,
                startSoc: s.soc ?? null, distanceKm: 0, maxSpeed: 0, samples: 0, end: null };
        prev = s;
      }
      if (cur) {
        if (prev && prev !== s) cur.distanceKm += haversine(prev, s);
        cur.maxSpeed = Math.max(cur.maxSpeed, s.speed);
        cur.samples++;
        cur.end = { lat: s.lat, lng: s.lng };
        cur.endOdo = s.odo ?? cur.endOdo ?? null;
        cur.endSoc = s.soc ?? cur.endSoc ?? null;
        cur.lastTs = s.ts;
        prev = s;
        if (moving) stoppedAt = null;
        else if (stoppedAt == null) stoppedAt = s.ts;
        else if (s.ts - stoppedAt >= stopAfter) close(stoppedAt);
      }
    },
    flush(ts) { close(ts ?? (cur?.lastTs ?? Date.now())); },
    get current() { return cur; },
    get drives() { return drives; },
  };
}

// Aggregate facts from a list of drives (km, km/h; the UI converts).
export function stats(drives, batteryKwh = 100) {
  const n = drives.length;
  if (!n) return { count: 0 };
  const sum = (f) => drives.reduce((a, d) => a + f(d), 0);
  const totalKm = sum(d => d.distanceKm);
  const totalMs = sum(d => d.durationMs);
  const longest = drives.reduce((a, d) => d.distanceKm > a.distanceKm ? d : a);
  const fastest = drives.reduce((a, d) => d.maxSpeed > a.maxSpeed ? d : a);
  const withSoc = drives.filter(d => d.startSoc != null && d.endSoc != null && d.distanceKm > 1);
  const kwhUsed = withSoc.reduce((a, d) => a + (d.startSoc - d.endSoc) / 100 * batteryKwh, 0);
  const kmWithSoc = withSoc.reduce((a, d) => a + d.distanceKm, 0);
  const whPerKm = kmWithSoc ? (kwhUsed * 1000) / kmWithSoc : null;
  const best = withSoc.length
    ? withSoc.map(d => ({ d, w: ((d.startSoc - d.endSoc) / 100 * batteryKwh * 1000) / d.distanceKm }))
        .reduce((a, x) => x.w < a.w ? x : a)
    : null;
  return {
    count: n,
    totalKm, totalMs,
    avgKm: totalKm / n,
    avgSpeed: totalMs ? totalKm / (totalMs / 3600000) : 0,
    longest, fastest,
    whPerKm,
    bestDrive: best?.d ?? null, bestWhPerKm: best?.w ?? null,
    moonFraction: totalKm / 384400,
    earthLaps: totalKm / 40075,
  };
}
