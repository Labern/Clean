// One input-simulator scenario per Academy lesson. Each is a road, a few
// variants (line + driver) to compare, and what to watch. Physics in sim.js.
import { Road, simulate, cornerLine, half, CAR } from './sim.js';

const G = 9.81;
const corner1 = (road) => road.corners[0];
// offset keys through several corners: [[station, n, label]]
const K = (...ks) => ks;

// Wheelspin from stabbing the throttle out of a slow corner: drive beyond what the
// rear tyres can take (less what cornering is using) becomes slip, you lose drive,
// the rear steps out and the hands catch it with opposite lock.
function stab(fromApex) {
  return (o) => {
    const { N, car } = o;
    const iA = o.st.findIndex((s) => s >= fromApex);
    const ay = car.mu * G;
    o.slip = new Float64Array(N);
    let slipAng = 0;
    for (let i = iA; i < N; i++) {
      const dt = o.t[i] - o.t[i - 1];
      // stab to 100%, then the driver lifts to catch it once the rear goes
      const want = slipAng > 2 ? Math.max(0.35, 1 - slipAng * 0.08) : 1;
      o.thr[i] = Math.min(want, o.thr[i - 1] + (want > o.thr[i - 1] ? 25 : 40) * dt);
      o.brk[i] = 0;
      const lat = Math.min(1, (o.v[i] ** 2 * Math.abs(o.k[i])) / ay);
      const avail = car.tracG * G * Math.sqrt(Math.max(0, 1 - lat * lat));
      const demand = o.thr[i] * Math.min(car.P / Math.max(o.v[i], 4), 1.6 * G);
      const excess = Math.max(0, demand - avail) / G;
      // the rear only steps out while it is also cornering; it straightens as the corner opens
      slipAng += (excess * lat * 120 - slipAng * (1.6 + 4 * (1 - lat))) * dt;
      slipAng = Math.max(0, slipAng);
      o.slip[i] = slipAng;
      o.steer[i] = o.steer[i] - Math.sign(o.k[i] || 1) * -1 * slipAng * 9;   // opposite lock
      if (i < N - 1) {
        const a = Math.min(demand, avail) * (slipAng > 0.8 ? 0.55 : 1) - car.cd * o.v[i] ** 2;
        const ds = Math.hypot(o.x[i + 1] - o.x[i], o.y[i + 1] - o.y[i]);
        o.v[i + 1] = Math.min(o.v[i + 1] + 99, Math.sqrt(Math.max(1, o.v[i] ** 2 + 2 * a * ds)));
        o.v[i + 1] = Math.min(o.v[i + 1], Math.sqrt(ay / Math.max(Math.abs(o.k[i + 1]), 1e-6)));
        o.t[i + 1] = o.t[i] + ds / ((o.v[i] + o.v[i + 1]) / 2);
        o.latG[i + 1] = o.v[i + 1] ** 2 * o.k[i + 1] / G;
        o.lonG[i] = a / G;
      }
    }
  };
}

// Short look-ahead: the driver reacts late, so steering arrives in corrections,
// and confidence (usable grip) drops a few percent.
function twitchy(amp) {
  return (o) => {
    for (let i = 0; i < o.N; i++) {
      const w = Math.min(1, Math.abs(o.k[i]) * 45);
      o.steer[i] += amp * w * Math.sin(2 * Math.PI * 1.25 * o.t[i]) + amp * 0.5 * w * Math.sin(2 * Math.PI * 2.9 * o.t[i] + 1);
    }
  };
}

// Slipstream: two cars co-simulated in time. The follower's drag falls when it is
// close behind and on the same line; it pulls out to the inside before braking.
function towSim(variant) {
  const road = new Road(12).straight(720).corner(120, 18, 'R').straight(170).build();
  const c = road.corners[0], H = half(road);
  const lineL = cornerLine(road, c, 0.45);
  // right-hander: the racing line arrives on the left (+H); the inside is -H
  const keysF = variant.tow
    ? K([0, H], [c.s0 - 360, H, 'Pull out'], [c.s0 - 150, -H * 0.8], [c.mid, -H, 'Apex'], [c.s1 + 40, H, 'Track-out'])
    : K([0, -H * 0.8, 'Clean air'], [c.mid, -H, 'Apex'], [c.s1 + 40, H, 'Track-out']);
  const L = simulate(road, lineL, { v0: 40 });
  const F = simulate(road, keysF, { v0: 40 });
  // co-sim: each car follows its own braking-limit curve (from the solo runs), with draft for F
  const curve = (o) => (s) => { let i = 0, hi = o.N - 1; while (hi - i > 1) { const m = (i + hi) >> 1; if (o.st[m] <= s) i = m; else hi = m; } return o.vb[i]; };
  const vbL = curve(L), vbF = curve(F);
  const eng = (v) => Math.min(CAR.tracG * G, CAR.P / Math.max(v, 4));
  let sL = 18, vL = 40, sF = 0, vF = 40, T = 0;
  const trace = [];
  const latOf = (o, s) => { const i = o.st.findIndex((x) => x >= s); return i < 0 ? o.N - 1 : i; };
  const lat = (o, s) => { const i = latOf(o, s), j = Math.min(road.N - 1, Math.round(o.st[i] / 0.5)); return (o.x[i] - road.x[j]) * -Math.sin(road.h[j]) + (o.y[i] - road.y[j]) * Math.cos(road.h[j]); };
  for (let k = 0; k < 4000 && sF < road.N * 0.5 - 2; k++) {
    const dt = 1 / 60;
    const gap = sL - sF;
    const inTow = gap > 1 && gap < 45 && Math.abs(lat(F, sF) - lat(L, sL)) < 2;
    const tow = inTow ? 0.4 * (1 - gap / 45) : 0;
    const aL = eng(vL) - CAR.cd * vL * vL;
    const aF = eng(vF) - CAR.cd * (1 - tow) * vF * vF;
    vL = Math.min(vL + aL * dt, vbL(sL + vL * dt));
    vF = Math.min(vF + aF * dt, vbF(sF + vF * dt) * (variant.tow ? 1.0 : 1));
    if (inTow && gap < 7) vF = Math.min(vF, vL);   // don't drive into the back of it
    sL += vL * dt; sF += vF * dt; T += dt;
    trace.push({ T, sL, vL, sF, vF, tow, gap });
  }
  // re-express the follower as a normal sample set (by station), with the leader alongside
  const o = F;
  const tAt = new Float64Array(o.N), other = { x: new Float64Array(o.N), y: new Float64Array(o.N), h: new Float64Array(o.N) }, towA = new Float64Array(o.N), gapA = new Float64Array(o.N);
  let j = 0;
  for (let i = 0; i < o.N; i++) {
    while (j < trace.length - 1 && trace[j + 1].sF < o.st[i]) j++;
    const a = trace[j], b = trace[Math.min(trace.length - 1, j + 1)];
    const u = b.sF > a.sF ? (o.st[i] - a.sF) / (b.sF - a.sF) : 0;
    tAt[i] = a.T + (b.T - a.T) * u;
    o.v[i] = a.vF + (b.vF - a.vF) * u;
    const sl = a.sL + (b.sL - a.sL) * u, li = Math.min(L.N - 1, latOf(L, sl));
    other.x[i] = L.x[li]; other.y[i] = L.y[li]; other.h[i] = L.h[li];
    towA[i] = a.tow; gapA[i] = a.gap;
  }
  o.t = tAt; o.other = other; o.tow = towA; o.gap = gapA;
  // re-derive pedals from the co-simulated speed (smoothed: the co-sim steps are discrete)
  const sm = (arr, r) => { const out = Float64Array.from(arr); for (let i = 0; i < arr.length; i++) { let s2 = 0, n2 = 0; for (let k = -r; k <= r; k++) { const j = i + k; if (j >= 0 && j < arr.length) { s2 += arr[j]; n2++; } } out[i] = s2 / n2; } return out; };
  o.v = sm(o.v, 6);
  for (let i = 0; i < o.N - 1; i++) {
    const ds = Math.max(1e-3, Math.hypot(o.x[i + 1] - o.x[i], o.y[i + 1] - o.y[i]));
    const ax = (o.v[i + 1] ** 2 - o.v[i] ** 2) / (2 * ds), dragA = CAR.cd * (1 - towA[i]) * o.v[i] ** 2;
    const need = ax + dragA;
    o.thr[i] = need >= 0 ? Math.min(1, need / eng(o.v[i]) + 0.02) : 0;
    o.brk[i] = need < 0 ? Math.min(1, -need / (CAR.brakeG * G)) : 0;
    o.lonG[i] = ax / G; o.latG[i] = o.v[i] ** 2 * o.k[i] / G;
  }
  o.thr = sm(o.thr, 4); o.brk = sm(o.brk, 4);
  for (let i = 0; i < o.N; i++) if (o.brk[i] > 0.03) o.thr[i] = 0;
  return o;
}

const line90 = () => new Road(12).straight(200).corner(90, 30, 'R').straight(420);
const hairpin = () => new Road(12).straight(260).corner(150, 14, 'R').straight(200);
const fastLeft = () => new Road(12).straight(230).corner(100, 45, 'L').straight(220);

export const SCENARIOS = {
  line: {
    title: 'The racing line, input by input',
    intro: 'A 90° right onto a long straight. Watch the wheel: it starts at 0°, winds on as you approach the apex, then unwinds to 0° as you run out to the exit kerb. Switch lines and compare where the lock peaks, the minimum speed, and the speed onto the straight.',
    watch: ['Geometric: peak lock exactly at the apex, highest minimum speed', 'Late apex: the rotation happens early, so you\'re already unwinding (and on the throttle) at the kerb', 'Early apex: you clip the kerb too soon and have to add lock on the exit'],
    road: line90, v0: 55, ref: 1,
    variants: [
      { id: 'early', label: 'Early apex', line: (r) => cornerLine(r, corner1(r), 0.72) },
      { id: 'geo', label: 'Geometric', line: (r) => cornerLine(r, corner1(r), 0.5) },
      { id: 'late', label: 'Late apex', line: (r) => cornerLine(r, corner1(r), 0.35) },
    ],
  },
  braking: {
    title: 'Threshold braking, then the release',
    intro: 'A hairpin after a long straight, on the racing line. The expert hits peak pressure almost instantly, holds it at the threshold, then bleeds it off as the steering goes in (trail braking). The beginner squeezes gently, never reaches the limit and finishes braking before turning, so has to brake far earlier.',
    watch: ['Peak pressure in a tenth of a second, held at the limit', 'Pressure bleeds out exactly as steering comes in', 'The beginner\'s braking point is tens of metres earlier for the same corner'],
    road: hairpin, v0: 62, ref: 0, extra: 'brake',
    variants: [
      { id: 'expert', label: 'Expert', line: (r) => cornerLine(r, corner1(r), 0.42) },
      { id: 'beginner', label: 'Beginner', line: (r) => cornerLine(r, corner1(r), 0.42), driver: { brake: 0.75, trail: false, brakeRise: 2.5, brakeFall: 5 } },
    ],
  },
  trail: {
    title: 'Trail braking into a fast corner',
    intro: 'A 100° left taken at speed. With trail braking, brake pressure overlaps the steering: it fades from its peak to zero by the apex, keeping the front loaded. Without it, all the braking has to be finished in a straight line, so you brake earlier and turn in slower.',
    watch: ['Brake and steering traces overlap: as one rises the other falls', 'The front tyres carry more load at turn-in (loads view)', 'Brake-then-turn costs time on entry'],
    road: fastLeft, v0: 62, ref: 0, extra: 'loads',
    variants: [
      { id: 'trail', label: 'Trail braking', line: (r) => cornerLine(r, corner1(r), 0.45) },
      { id: 'notrail', label: 'Brake, then turn', line: (r) => cornerLine(r, corner1(r), 0.45), driver: { trail: false } },
    ],
  },
  weight: {
    title: 'Weight transfer: smooth vs abrupt',
    intro: 'The same corner and line, two pairs of feet. Smooth inputs move the weight progressively; abrupt ones (stab the brake, snap off it, stab the throttle) make the body pitch and rock, and the tyre loads swing past where you want them.',
    watch: ['Tyre-load circles: front grows under braking, rear on throttle, outside in the corner', 'Abrupt release: the front unloads suddenly at turn-in', 'The body keeps rocking after an abrupt input'],
    road: line90, v0: 55, ref: 0, extra: 'loads',
    variants: [
      { id: 'smooth', label: 'Smooth', line: (r) => cornerLine(r, corner1(r), 0.45), driver: { brakeRise: 8, brakeFall: 2.5, thrRise: 2.5, damping: 0.6 } },
      { id: 'abrupt', label: 'Abrupt', line: (r) => cornerLine(r, corner1(r), 0.45), driver: { brakeRise: 40, brakeFall: 40, thrRise: 30, damping: 0.25 } },
    ],
  },
  circle: {
    title: 'Riding the edge of the traction circle',
    intro: 'The G-meter dot is the force your tyres are making. Trail braking sweeps it round the edge of the circle from braking into cornering. Braking, releasing and only then turning makes an L shape through the middle: unused grip, lost time.',
    watch: ['Trail braking: the dot curves round the rim', 'Brake-then-turn: the dot drops to the centre before turning', 'The trail of the dot shows how much of the circle you use'],
    road: hairpin, v0: 62, ref: 0, extra: 'gg',
    variants: [
      { id: 'trail', label: 'Trail braking', line: (r) => cornerLine(r, corner1(r), 0.42) },
      { id: 'lshape', label: 'Brake, then turn', line: (r) => cornerLine(r, corner1(r), 0.42), driver: { trail: false } },
    ],
  },
  priority: {
    title: 'Corner priorities: which corner matters',
    intro: 'A slow right onto a 400 m straight. Sacrificing a little entry speed for exit speed: watch the time-gap trace. The exit-first line loses time into the corner and earns it back down the straight; the longer the straight, the more it gets back.',
    watch: ['Delta trace: where each line gains and loses', 'Speed onto the straight sets the speed all the way down it', 'Entry-first carries more speed in but exits slower'],
    road: () => new Road(12).straight(150).corner(90, 26, 'R').straight(400), v0: 50, ref: 0,
    variants: [
      { id: 'exit', label: 'Exit first', line: (r) => cornerLine(r, corner1(r), 0.35) },
      { id: 'entry', label: 'Entry first', line: (r) => cornerLine(r, corner1(r), 0.68) },
    ],
  },
  throttle: {
    title: 'Throttle out of a slow corner',
    intro: 'A powerful rear-drive car leaving a hairpin. Squeeze the throttle on as the steering unwinds and the rear tyres keep up. Stab it to 100% at the apex and the drive exceeds what the rears can take while they\'re also cornering: wheelspin, the rear steps out, and your hands have to catch it with opposite lock.',
    watch: ['Progressive: throttle rises as steering falls', 'Stab: steering flicks to opposite lock as the rear lets go', 'Wheelspin costs drive: compare the speed onto the straight'],
    road: () => new Road(12).straight(120).corner(160, 15, 'L').straight(240), v0: 40, ref: 0, car: { P: 420, tracG: 0.75 }, extra: 'spin',
    variants: [
      { id: 'smooth', label: 'Progressive', line: (r) => cornerLine(r, corner1(r), 0.42), driver: { thrRise: 2.2 } },
      { id: 'stab', label: 'Stab', line: (r) => cornerLine(r, corner1(r), 0.42), post: (r) => stab(corner1(r).mid) },
    ],
  },
  vision: {
    title: 'Eyes up: looking ahead through the esses',
    intro: 'A left-right-left sequence. The yellow line is where the driver is looking. Two seconds ahead, steering is one smooth input per corner. Looking at the nose of the car, every input arrives late and gets corrected, and confidence (usable grip) drops.',
    watch: ['The look point: two seconds ahead vs right in front', 'Steering trace: smooth arcs vs a saw-tooth of corrections', 'Minimum speeds through each corner'],
    road: () => new Road(12).straight(140).corner(55, 45, 'L').straight(8).corner(75, 38, 'R').straight(8).corner(60, 45, 'L').straight(180), v0: 50, ref: 0, extra: 'eye',
    variants: [
      { id: 'far', label: 'Look ahead (2 s)', look: 2.0, line: (r) => esses(r) },
      { id: 'near', label: 'Look at the nose', look: 0.5, line: (r) => esses(r), driver: { mu: 0.94 }, post: () => twitchy(9) },
    ],
  },
  slipstream: {
    title: 'Slipstream, pull out, outbrake',
    intro: 'You (blue) start 18 m behind the grey car on a 700 m straight. Tucked in its tow your drag falls, so you close in, pull out to the inside late and arrive alongside for the braking zone. Start in clean air and the gap barely moves. Watch the exit too: the inside line is tighter, so the grey car can switch back if you don\'t brake later and hold it.',
    watch: ['Tow meter: how much drag the car ahead is taking off you', 'Gap closing down the straight', 'Pull out late: too early and you lose the tow'],
    custom: towSim, ref: 0, extra: 'tow',
    variants: [
      { id: 'tow', label: 'In the tow', tow: true },
      { id: 'clean', label: 'Clean air', tow: false },
    ],
  },
  tyres: {
    title: 'Tyres and fuel over a stint',
    intro: 'The same fast left on lap 1 (fresh tyres, full tank), lap 15 (worn tyres, lighter car) and with overheated tyres. Less grip moves the braking point earlier and lowers the speed through the corner; the inputs look the same, the numbers don\'t.',
    watch: ['Braking point moves back as grip falls', 'Minimum speed through the corner', 'Lap-time cost per corner (delta)'],
    road: fastLeft, v0: 62, ref: 0,
    variants: [
      { id: 'fresh', label: 'Lap 1: fresh, full tank', line: (r) => cornerLine(r, corner1(r), 0.45), car: { P: 285 } },
      { id: 'worn', label: 'Lap 15: worn', line: (r) => cornerLine(r, corner1(r), 0.45), driver: { mu: 0.92 }, car: { P: 300 } },
      { id: 'hot', label: 'Overheated', line: (r) => cornerLine(r, corner1(r), 0.45), driver: { mu: 0.87 }, car: { P: 300 } },
    ],
  },
  wet: {
    title: 'The same corner in the wet',
    intro: 'Grip drops to about two-thirds. The wet line stays off the painted kerb and the rubbered racing line, braking starts much earlier, and every input is slower and smaller: brake squeezed on, released gently, throttle fed in.',
    watch: ['Braking point and pressure', 'Slower input rates on every pedal', 'The wet line apexes away from the kerb'],
    road: line90, v0: 55, ref: 0,
    variants: [
      { id: 'dry', label: 'Dry', line: (r) => cornerLine(r, corner1(r), 0.45) },
      { id: 'wet', label: 'Wet', line: (r) => cornerLine(r, corner1(r), 0.45, { apN: 0.55 }), driver: { mu: 0.64, brakeRise: 5, brakeFall: 1.6, thrRise: 1.4 } },
    ],
  },
  alien: {
    title: 'Rotation: V-line vs U-line in a hairpin',
    intro: 'Two ways through the same hairpin. The U-line carries speed round a wide, even arc. The V-line brakes deeper, rotates the car hard at a late apex and drives out in a straight line. Which wins depends on the car: compare minimum speed against speed onto the straight.',
    watch: ['V-line: lower minimum speed, earlier full throttle', 'U-line: higher minimum speed, longer time cornering', 'Delta on the exit straight'],
    road: () => new Road(12).straight(220).corner(170, 15, 'R').straight(260), v0: 58, ref: 0,
    variants: [
      { id: 'v', label: 'V-line', line: (r) => cornerLine(r, corner1(r), 0.3) },
      { id: 'u', label: 'U-line', line: (r) => cornerLine(r, corner1(r), 0.55, { apN: 0.5 }) },
    ],
  },
};

function esses(road) {
  const [a, b, c] = road.corners, H = half(road);
  return K([a.s0 - 30, -H, 'Turn-in'], [a.mid, H, 'Apex 1'], [b.mid, -H, 'Apex 2'], [c.mid, H, 'Apex 3'], [c.s1 + 40, -H, 'Track-out']);
}

// Run one scenario: every variant simulated (cached per page load).
const cache = new Map();
export function runScenario(id) {
  if (cache.has(id)) return cache.get(id);
  const sc = SCENARIOS[id];
  const runs = sc.variants.map((v) => {
    if (sc.custom) return { v, o: sc.custom(v) };
    const road = sc.road().build();
    const o = simulate(road, v.line(road), { v0: sc.v0, car: { ...(sc.car || {}), ...(v.car || {}) }, driver: v.driver, post: v.post && v.post(road) });
    o.look = v.look;
    return { v, o };
  });
  cache.set(id, runs);
  return runs;
}
