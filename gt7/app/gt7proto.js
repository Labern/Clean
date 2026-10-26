// GT7 Simulator Interface protocol for the app itself (no Node Buffer), so the
// native shells decode the PS5's telemetry on the phone with no bridge.
// Byte-for-byte the same as bridge/protocol.mjs (the tests check it).
// Sources: Nenkai/PDTools, snipem/gt7dashboard.
export const XOR = { A: 0xDEADBEAF, B: 0xDEADBEEF, '~': 0x55FABB4F };
export const SIZE = { A: 0x128, B: 0x13C, '~': 0x158 };
const enc = (s) => new TextEncoder().encode(s);
const KEY = enc('Simulator Interface Packet GT7 ver 0.0').subarray(0, 32);
const SIGMA = enc('expand 32-byte k');
const u32 = (b, o) => (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) >>> 0;
const rotl = (v, n) => (v << n) | (v >>> (32 - n));

function block(out, inp) {
  const x = Uint32Array.from(inp);
  for (let i = 0; i < 10; i++) {
    x[4] ^= rotl(x[0] + x[12], 7); x[8] ^= rotl(x[4] + x[0], 9); x[12] ^= rotl(x[8] + x[4], 13); x[0] ^= rotl(x[12] + x[8], 18);
    x[9] ^= rotl(x[5] + x[1], 7); x[13] ^= rotl(x[9] + x[5], 9); x[1] ^= rotl(x[13] + x[9], 13); x[5] ^= rotl(x[1] + x[13], 18);
    x[14] ^= rotl(x[10] + x[6], 7); x[2] ^= rotl(x[14] + x[10], 9); x[6] ^= rotl(x[2] + x[14], 13); x[10] ^= rotl(x[6] + x[2], 18);
    x[3] ^= rotl(x[15] + x[11], 7); x[7] ^= rotl(x[3] + x[15], 9); x[11] ^= rotl(x[7] + x[3], 13); x[15] ^= rotl(x[11] + x[7], 18);
    x[1] ^= rotl(x[0] + x[3], 7); x[2] ^= rotl(x[1] + x[0], 9); x[3] ^= rotl(x[2] + x[1], 13); x[0] ^= rotl(x[3] + x[2], 18);
    x[6] ^= rotl(x[5] + x[4], 7); x[7] ^= rotl(x[6] + x[5], 9); x[4] ^= rotl(x[7] + x[6], 13); x[5] ^= rotl(x[4] + x[7], 18);
    x[11] ^= rotl(x[10] + x[9], 7); x[8] ^= rotl(x[11] + x[10], 9); x[9] ^= rotl(x[8] + x[11], 13); x[10] ^= rotl(x[9] + x[8], 18);
    x[12] ^= rotl(x[15] + x[14], 7); x[13] ^= rotl(x[12] + x[15], 9); x[14] ^= rotl(x[13] + x[12], 13); x[15] ^= rotl(x[14] + x[13], 18);
  }
  for (let i = 0; i < 16; i++) { const v = (x[i] + inp[i]) >>> 0; out[i * 4] = v & 255; out[i * 4 + 1] = (v >>> 8) & 255; out[i * 4 + 2] = (v >>> 16) & 255; out[i * 4 + 3] = v >>> 24; }
}
export function salsa20(key, nonce, data) {
  const st = new Uint32Array(16);
  st[0] = u32(SIGMA, 0); st[5] = u32(SIGMA, 4); st[10] = u32(SIGMA, 8); st[15] = u32(SIGMA, 12);
  for (let i = 0; i < 4; i++) { st[1 + i] = u32(key, i * 4); st[11 + i] = u32(key, 16 + i * 4); }
  st[6] = u32(nonce, 0); st[7] = u32(nonce, 4);
  const out = new Uint8Array(data.length), ks = new Uint8Array(64);
  for (let off = 0, ctr = 0; off < data.length; off += 64, ctr++) {
    st[8] = ctr >>> 0; st[9] = Math.floor(ctr / 0x100000000);
    block(ks, st);
    for (let j = 0; j < 64 && off + j < data.length; j++) out[off + j] = data[off + j] ^ ks[j];
  }
  return out;
}
const put32 = (b, o, v) => { b[o] = v & 255; b[o + 1] = (v >>> 8) & 255; b[o + 2] = (v >>> 16) & 255; b[o + 3] = (v >>> 24) & 255; };
export function nonceFor(iv1, type) { const n = new Uint8Array(8); put32(n, 0, (iv1 ^ XOR[type]) >>> 0); put32(n, 4, iv1 >>> 0); return n; }
export function decrypt(buf, type = '~') {
  const d = salsa20(KEY, nonceFor(u32(buf, 0x40), type), buf);
  return u32(d, 0) === 0x47375330 ? d : null;
}
export function encrypt(plain, iv1, type = '~') { const e = salsa20(KEY, nonceFor(iv1, type), plain); put32(e, 0x40, iv1 >>> 0); return e; }

export function parse(d) {
  const v = new DataView(d.buffer, d.byteOffset, d.byteLength), f = (o) => v.getFloat32(o, true);
  const flags = v.getInt16(0x8E, true), gearByte = d[0x90];
  return {
    x: f(0x04), y: f(0x08), z: f(0x0C), v: f(0x4C) * 3.6,
    rpm: f(0x3C), fuel: f(0x44), fuelCap: f(0x48), boost: f(0x50) - 1,
    tyre: [f(0x60), f(0x64), f(0x68), f(0x6C)],
    id: v.getInt32(0x70, true), lap: v.getInt16(0x74, true), laps: v.getInt16(0x76, true),
    best: v.getInt32(0x78, true), last: v.getInt32(0x7C, true),
    pos: v.getInt16(0x84, true), cars: v.getInt16(0x86, true),
    rpmMax: v.getInt16(0x8A, true), flags,
    onTrack: !!(flags & 1), paused: !!(flags & 2), loading: !!(flags & 4),
    gear: gearByte & 0x0f, sgear: gearByte >> 4, thr: d[0x91] / 255, brk: d[0x92] / 255,
    car: v.getInt32(0x124, true),
    steer: d.length >= 0x13C ? v.getFloat32(0x128, true) : null,
  };
}

// Recorder shared by the phone and the bridge. Two outputs:
//  - laps: a lap closes when the lap counter increments, with GT7's official time;
//  - runs: any continuous drive between resets. A Circuit Experience sector, a
//    licence test or a time-trial attempt never completes a lap, so a run starts
//    when the car moves off and ends when GT7 teleports or reloads it (or the
//    stream stops). Runs are what the sector trainer compares against the demo.
export const COLS = ['t', 'x', 'z', 'y', 'kmh', 'thr', 'brk', 'gear', 'rpm', 'steer', 'd'];
export function createRecorder({ onLap, onRun, onLive }) {
  let cur = null, pending = null, n = 0, run = null, prev = null;
  const id = (t0, car, tag) => new Date(t0).toISOString().replace(/[:.]/g, '-').slice(0, 19) + `-car${car}-${tag}`;
  const closeRun = () => {
    const r = run; run = null;
    if (!r || !onRun || r.pts.length < 40) return;
    const last = r.pts.at(-1), dist = last[10], time = Math.round(last[0] * 1000);
    if (dist < 150 || time < 4000) return;
    onRun({ id: id(r.t0, r.car, 'run'), kind: 'run', car: r.car, t0: r.t0, time, dist: Math.round(dist), n: r.pts.length, cols: COLS, pts: r.pts,
      start: [r.pts[0][1], r.pts[0][2]], end: [last[1], last[2]] });
  };
  const rec = (fr) => {
    n++; onLive?.(fr);
    const now = Date.now();
    // a reset: loading, a different car, or a jump no car could make between packets
    const jump = prev && Math.hypot(fr.x - prev.x, fr.z - prev.z) > 25;
    if (fr.loading || jump || (prev && fr.car !== prev.car)) closeRun();
    prev = fr;
    if (fr.paused || fr.loading || !fr.onTrack) return;
    if (!cur || fr.lap !== cur.lap) {
      if (cur && fr.lap === cur.lap + 1 && cur.pts.length > 100) pending = { ...cur, closedAt: now };
      cur = { lap: fr.lap, car: fr.car, t0: now, pts: [] };
    }
    if (pending && ((fr.last > 0 && now - pending.closedAt > 300) || now - pending.closedAt > 4000)) {
      const ms = fr.last > 0 ? fr.last : null, l = pending; pending = null;
      onLap?.({ id: id(l.t0, l.car, 'L' + l.lap), car: l.car, lap: l.lap, t0: l.t0, time: ms ?? Math.round(l.pts.at(-1)[0] * 1000), timeSource: ms ? 'gt7' : 'measured', n: l.pts.length,
        cols: COLS.slice(0, 10), pts: l.pts });
    }
    if (!run && fr.v > 5) run = { car: fr.car, t0: now, pts: [], d: 0, lx: fr.x, lz: fr.z };
    if (n % 3 === 0) {
      const sample = (t) => [+t.toFixed(3), +fr.x.toFixed(2), +fr.z.toFixed(2), +fr.y.toFixed(2), +fr.v.toFixed(1), Math.round(fr.thr * 100), Math.round(fr.brk * 100), fr.gear, Math.round(fr.rpm), fr.steer == null ? 0 : +fr.steer.toFixed(3)];
      cur.pts.push(sample((now - cur.t0) / 1000));
      if (run) { run.d += Math.hypot(fr.x - run.lx, fr.z - run.lz); run.lx = fr.x; run.lz = fr.z; run.pts.push([...sample((now - run.t0) / 1000), +run.d.toFixed(1)]); }
    }
  };
  rec.flush = closeRun;   // the stream stopped: keep the run in progress
  return rec;
}
