// GT7 Simulator Interface protocol: Salsa20 decryption and packet parsing.
// Pure functions, no I/O, shared by the bridge and the tests.
// Sources: Nenkai/PDTools (SimulatorPacket.cs, SimulatorInterfaceClient.cs),
// snipem/gt7dashboard (gt7communication.py).

export const XOR = { A: 0xDEADBEAF, B: 0xDEADBEEF, '~': 0x55FABB4F };
export const SIZE = { A: 0x128, B: 0x13C, '~': 0x158 };
const KEY = Buffer.from('Simulator Interface Packet GT7 ver 0.0').subarray(0, 32);

// ── Salsa20 (DJB), 8-byte nonce, 64-bit block counter ─────────────────────
const SIGMA = Buffer.from('expand 32-byte k');
const rotl = (v, n) => (v << n) | (v >>> (32 - n));
function salsaBlock(out, inp) {
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
  for (let i = 0; i < 16; i++) out.writeUInt32LE((x[i] + inp[i]) >>> 0, i * 4);
}
export function salsa20(key, nonce, data) {
  const st = new Uint32Array(16);
  st[0] = SIGMA.readUInt32LE(0); st[5] = SIGMA.readUInt32LE(4); st[10] = SIGMA.readUInt32LE(8); st[15] = SIGMA.readUInt32LE(12);
  for (let i = 0; i < 4; i++) { st[1 + i] = key.readUInt32LE(i * 4); st[11 + i] = key.readUInt32LE(16 + i * 4); }
  st[6] = nonce.readUInt32LE(0); st[7] = nonce.readUInt32LE(4);
  const out = Buffer.alloc(data.length), ks = Buffer.alloc(64);
  for (let off = 0, ctr = 0; off < data.length; off += 64, ctr++) {
    st[8] = ctr >>> 0; st[9] = Math.floor(ctr / 0x100000000);
    salsaBlock(ks, st);
    for (let j = 0; j < 64 && off + j < data.length; j++) out[off + j] = data[off + j] ^ ks[j];
  }
  return out;
}
export function nonceFor(iv1, type) {
  const n = Buffer.alloc(8);
  n.writeUInt32LE((iv1 ^ XOR[type]) >>> 0, 0); n.writeUInt32LE(iv1 >>> 0, 4);
  return n;
}
export function decrypt(buf, type = '~') {
  const iv1 = buf.readUInt32LE(0x40);
  const d = salsa20(KEY, nonceFor(iv1, type), buf);
  return d.readUInt32LE(0) === 0x47375330 ? d : null;
}
export function encrypt(plain, iv1, type = '~') { // used by --demo and the tests
  const enc = salsa20(KEY, nonceFor(iv1, type), plain);
  enc.writeUInt32LE(iv1 >>> 0, 0x40); // the IV travels in the clear
  return enc;
}

// ── packet → frame ────────────────────────────────────────────────────────
export function parse(d) {
  const f = (o) => d.readFloatLE(o);
  const gearByte = d[0x90];
  const flags = d.readInt16LE(0x8E);
  return {
    x: f(0x04), y: f(0x08), z: f(0x0C),
    v: f(0x4C) * 3.6, // km/h
    rpm: f(0x3C), fuel: f(0x44), fuelCap: f(0x48), boost: f(0x50) - 1,
    tyre: [f(0x60), f(0x64), f(0x68), f(0x6C)],
    id: d.readInt32LE(0x70), lap: d.readInt16LE(0x74), laps: d.readInt16LE(0x76),
    best: d.readInt32LE(0x78), last: d.readInt32LE(0x7C),
    pos: d.readInt16LE(0x84), cars: d.readInt16LE(0x86),
    rpmMax: d.readInt16LE(0x8A), flags,
    onTrack: !!(flags & 1), paused: !!(flags & 2), loading: !!(flags & 4),
    gear: gearByte & 0x0f, sgear: gearByte >> 4,
    thr: d[0x91] / 255, brk: d[0x92] / 255,
    car: d.readInt32LE(0x124),
    steer: d.length >= 0x13C ? d.readFloatLE(0x128) : null, // radians at the wheel
  };
}

