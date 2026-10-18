// Data Logger: live telemetry from the bridge, the lap library, and the lap
// replay with a scrubbable racing line. Views plug into main.js's router.
import { $, $$, html, raw, esc, toast } from './util.js';
import * as store from './state.js';
import * as L from './laps.js';
import { SECTOR_COLORS } from './map.js';
import { trackById } from '../data/tracks.js';

const DEMO_URL = 'data/demo-lap.json';
let live = null, es = null, bridgeOk = null;

// The bridge serves the app itself, so when we're on it the API is same-origin.
export function bridgeBase() {
  const s = store.get();
  if (bridgeOk === 'same') return '';
  return (s.bridgeUrl || '').replace(/\/$/, '');
}
export async function probe() {
  try { const r = await fetch('api/status', { cache: 'no-store' }); if (r.ok && (await r.json()).ok) { bridgeOk = 'same'; return true; } } catch { /* not on the bridge */ }
  const b = (store.get().bridgeUrl || '').replace(/\/$/, '');
  if (b) { try { const r = await fetch(b + '/api/status', { cache: 'no-store' }); if (r.ok) { bridgeOk = 'remote'; return true; } } catch { /* unreachable or mixed content */ } }
  bridgeOk = false; return false;
}
function openLive(onFrame) {
  es?.close();
  es = new EventSource(bridgeBase() + '/api/live');
  es.addEventListener('live', (e) => { live = JSON.parse(e.data); onFrame(live); });
  es.addEventListener('lap', async (e) => { const meta = JSON.parse(e.data); toast(`Lap ${meta.lap}: ${L.fmtLap(meta.time)}`); await importFromBridge(meta.id); onFrame(live, true); });
}
async function importFromBridge(id) {
  const r = await fetch(bridgeBase() + '/api/laps/' + encodeURIComponent(id));
  if (!r.ok) return null;
  const lap = await r.json();
  await L.putLap(lap);
  window.dispatchEvent(new CustomEvent('gt7-lap-saved', { detail: lap }));
  return lap;
}
async function loadDemo() {
  let lap = await L.getLap('demo-spa');
  if (!lap) { lap = await (await fetch(DEMO_URL)).json(); await L.putLap(lap); }
  return lap;
}

// ── #/telemetry ─────────────────────────────────────────
export function telemetryView() {
  const s = store.get();
  return {
    html: html`
    <div class="kicker">Data Logger</div><h1>Your Real Laps</h1>
    <p class="muted" style="max-width:72ch;margin-top:10px">GT7 broadcasts live telemetry from your PS5: position, speed, revs, gear, throttle, brake, steering, tyres. The bridge on your Mac records every lap. Here you replay your actual racing line on the real circuit, corner by corner.</p>
    <section class="section grid g2" style="margin-top:20px;align-items:start">
      <div class="card pad" id="conn"><div class="kicker">Bridge</div><h3 style="margin:6px 0">Checking…</h3></div>
      <div class="card pad" id="hud" style="background:linear-gradient(135deg,#0b1f4b,#13306e);color:#fff;min-height:200px">
        <div class="kicker" style="color:#ff8a90">Live</div>
        <div class="muted" style="color:#9fb3e6;margin-top:6px">Waiting for the bridge…</div>
      </div>
    </section>
    <section class="section">
      <div class="head"><h2>Lap Library</h2>
        <div class="row"><label class="btn sm ghost" style="cursor:pointer">Import lap file<input type="file" id="lapfile" accept=".json,application/json" multiple hidden></label><button class="btn sm" id="demo">Open demo lap (Spa)</button></div></div>
      <div class="grid" style="gap:8px" id="laplist"><p class="muted">Loading…</p></div>
    </section>
    <section class="section card pad">
      <h3>Set up the bridge (once)</h3>
      <ol style="margin:12px 0 0;padding-left:22px;display:grid;gap:8px;max-width:80ch">
        <li>On the Mac: install Node.js (nodejs.org, LTS). Open Terminal.</li>
        <li>Get the app: <code>git clone https://github.com/Labern/Clean</code> (or download the repo zip).</li>
        <li>Find your PS5's IP: PS5 Settings → Network → Connection Status → View Connection Status.</li>
        <li>Run <code>node Clean/gt7/bridge/gt7-bridge.mjs --ps5 192.168.x.x</code>. Use <code>--ps5 auto</code> to try broadcast, or <code>--demo</code> to test without the PS5.</li>
        <li>Open <b>http://localhost:8787</b> on the Mac, or the phone address it prints, while you drive. Laps also save as files in <code>~/GT7Laps</code>, and the app keeps them, synced to your account.</li>
      </ol>
      <p class="muted small" style="margin-top:12px">Why a bridge: GT7 sends telemetry as encrypted UDP on your home network. Browsers can't receive UDP, so a small script on the Mac decodes it (no installs beyond Node). Your Mac and PS5 must be on the same network.</p>
      <label class="f" style="margin-top:12px;max-width:420px">Bridge address (only if this page isn't opened from the bridge)<input type="text" id="burl" placeholder="http://192.168.1.20:8787" value="${s.bridgeUrl || ''}"></label>
    </section>`,
    async wire(root) {
      const conn = $('#conn', root), hud = $('#hud', root);
      const paintLaps = async () => {
        if (!root.isConnected || !$('#laplist', root)) { window.removeEventListener('gt7-lap-saved', paintLaps); return; }
        const laps = await L.allLaps();
        if (!$('#laplist', root)) return;
        $('#laplist', root).innerHTML = laps.length ? laps.map((l) => {
          const al = l.track ? { track: trackById[l.track] } : null;
          return `<a class="check" href="#/lap/${encodeURIComponent(l.id)}" style="text-decoration:none"><span class="cls gr3" style="font-size:16px">${esc(L.fmtLap(l.time))}</span>
            <div style="flex:1"><div class="t">${esc(l.demo ? 'Demo lap · ' : '')}${esc(al?.track?.short || l.trackName || 'Unidentified track')} · lap ${l.lap}</div><div class="d">${new Date(l.t0).toLocaleString()} · car #${l.car} · ${l.n} samples${l.timeSource === 'gt7' ? ' · official time' : ''}</div></div>
            <span class="chip blue">Replay →</span></a>`;
        }).join('') : '<p class="muted">No laps yet. Open the demo, connect the bridge, or import a lap file from ~/GT7Laps.</p>';
      };
      await paintLaps();
      window.addEventListener('gt7-lap-saved', paintLaps);
      $('#demo', root).onclick = async () => { const lap = await loadDemo(); location.hash = '#/lap/' + encodeURIComponent(lap.id); };
      $('#lapfile', root).onchange = async (e) => {
        let n = 0;
        for (const f of e.target.files) { try { const lap = JSON.parse(await f.text()); if (lap.pts && lap.cols) { await L.putLap(lap); window.dispatchEvent(new CustomEvent('gt7-lap-saved', { detail: lap })); n++; } } catch { /* skip */ } }
        toast(`Imported ${n} lap${n === 1 ? '' : 's'}`); paintLaps();
      };
      $('#burl', root).onchange = (e) => { store.set((s) => { s.bridgeUrl = e.target.value.trim(); }); location.reload(); };

      const ok = await probe();
      if (!ok) {
        conn.innerHTML = `<div class="kicker">Bridge</div><h3 style="margin:6px 0">Not connected</h3><p class="muted small">Run the bridge on your Mac (steps below) and open this app from the address it prints${location.protocol === 'https:' ? '. A secure (https) page can\'t talk to a local http bridge, so use the bridge\'s own address while driving' : ''}. Your laps sync back to this device afterwards.</p>`;
        return;
      }
      const st = await (await fetch(bridgeBase() + '/api/status')).json();
      conn.innerHTML = `<div class="kicker">Bridge</div><h3 style="margin:6px 0;color:var(--ok)">Connected${st.demo ? ' · demo mode' : ''}</h3><p class="muted small">${st.ps5 ? 'PS5 ' + esc(st.ps5) : st.demo ? 'Streaming a synthetic Spa lap' : 'Waiting for the PS5…'} · laps saved to ${esc(st.laps)}</p><button class="btn sm" id="sync-b">Import all bridge laps</button>`;
      $('#sync-b', root).onclick = async () => {
        const list = await (await fetch(bridgeBase() + '/api/laps')).json();
        const have = new Set((await L.allLaps()).map((l) => l.id));
        let n = 0; for (const m of list) if (!have.has(m.id)) { await importFromBridge(m.id); n++; }
        toast(`${n} new lap${n === 1 ? '' : 's'}`); paintLaps();
      };
      openLive((f) => {
        if (!root.isConnected) { es?.close(); return; }
        if (!f || f.offline) { hud.innerHTML = `<div class="kicker" style="color:#ff8a90">Live</div><h3 style="color:#fff;margin:8px 0">No telemetry</h3><p style="color:#9fb3e6">Start GT7 and drive. Data flows once you're on track.</p>`; return; }
        hud.innerHTML = `<div class="row" style="justify-content:space-between"><div class="kicker" style="color:#ff8a90">● Live · lap ${f.lap}${f.recording ? ' · recording' : ''}</div><div style="color:#9fb3e6;font-weight:600">best ${L.fmtLap(f.best)} · last ${L.fmtLap(f.last)}</div></div>
          <div class="row" style="gap:26px;margin-top:10px;align-items:end">
            <div><div style="font-family:var(--display);font-style:italic;font-weight:900;font-size:76px;line-height:.9">${Math.round(f.v)}</div><div style="color:#9fb3e6;font-weight:600">km/h</div></div>
            <div><div style="font-family:var(--display);font-style:italic;font-weight:900;font-size:76px;line-height:.9;color:#ffc531">${f.gear || 'N'}</div><div style="color:#9fb3e6;font-weight:600">gear</div></div>
            <div style="flex:1;min-width:160px;display:grid;gap:8px">
              <div class="bar" style="background:rgba(255,255,255,.12)"><i style="width:${Math.min(100, (f.rpm / (f.rpmMax || 9000)) * 100)}%;background:${f.rpm > (f.rpmMax || 9000) * 0.95 ? '#e1131f' : '#ffc531'}"></i></div>
              <div class="bar" style="background:rgba(255,255,255,.12)"><i style="width:${f.thr * 100}%;background:#36d399"></i></div>
              <div class="bar" style="background:rgba(255,255,255,.12)"><i style="width:${f.brk * 100}%;background:#e1131f"></i></div>
              <div style="color:#9fb3e6;font-size:13px">rpm ${Math.round(f.rpm)} · fuel ${f.fuel.toFixed(1)} L · tyres ${f.tyre.map((t) => Math.round(t)).join('/')}°C</div>
            </div>
          </div>`;
      });
    },
  };
}

// ── #/lap/<id>: the replay ──────────────────────────────
const speedCol = (v, lo, hi) => {
  const k = Math.max(0, Math.min(1, (v - lo) / ((hi - lo) || 1)));
  const stops = [[225, 19, 31], [255, 197, 49], [54, 211, 153], [61, 123, 255]];
  const p = k * (stops.length - 1), i = Math.min(stops.length - 2, Math.floor(p)), f = p - i;
  const c = stops[i].map((x, j) => Math.round(x + (stops[i + 1][j] - x) * f));
  return `rgb(${c})`;
};
let colorMode = 'speed';

export function lapView(id) {
  return {
    html: html`
    <a class="back" href="#/telemetry">← Data Logger</a>
    <div id="lapwrap"><p class="muted">Loading lap…</p></div>`,
    async wire(root) {
      let lap = await L.getLap(id);
      if (!lap && id === 'demo-spa') lap = await loadDemo();
      if (!lap && bridgeBase() !== null) { try { lap = await importFromBridge(id); } catch { /* ignore */ } }
      if (!lap) { $('#lapwrap', root).innerHTML = '<h1>Lap not found</h1>'; return; }
      const al = L.align(lap);
      if (al && lap.track !== al.track.id) { lap.track = al.track.id; await L.putLap(lap); }
      const others = (await L.allLaps()).filter((l) => l.id !== lap.id && (!al || l.track === al.track.id));
      const wrap = $('#lapwrap', root);
      if (wrap && root.isConnected) renderReplay(wrap, lap, al, others); // user may have navigated away meanwhile
    },
  };
}

function renderReplay(el, lap, al, others) {
  const C = L.cols(lap), D = L.distances(lap);
  // Draw north-up in the guide maps' frame when the track is identified.
  const toView = (x, z) => (al ? al.Tinv([x, z]) : [x, z]);
  const P = lap.pts.map((p) => { const q = p.slice(); [q[C.x], q[C.z]] = toView(p[C.x], p[C.z]); return q; });
  const total = P.at(-1)[C.t];
  const xs = P.map((p) => p[C.x]), zs = P.map((p) => p[C.z]);
  let minX = Math.min(...xs), maxX = Math.max(...xs), minZ = Math.min(...zs), maxZ = Math.max(...zs);
  const pad = Math.max(maxX - minX, maxZ - minZ) * 0.07;
  minX -= pad; minZ -= pad; maxX += pad; maxZ += pad;
  const W = maxX - minX, H = maxZ - minZ, sw = Math.max(W, H) / 220;
  const vmin = Math.min(...P.map((p) => p[C.kmh])), vmax = Math.max(...P.map((p) => p[C.kmh]));
  const t = al?.track;
  const mapPt = (f) => { const m = al.map, i = Math.round(f * m.pts.length) % m.pts.length; return [m.pts[i][0] * m.mPerUnit, m.pts[i][1] * m.mPerUnit]; };
  const refPts = (r) => { const R = L.cols(r); return r.pts.map((p) => toView(p[R.x], p[R.z])); };
  let ref = null, refD = null, dl = null;

  const segs = () => P.slice(1).map((p, i) => {
    const a = P[i];
    const col = colorMode === 'speed' ? speedCol(a[C.kmh], vmin, vmax)
      : colorMode === 'inputs' ? (a[C.brk] > 5 ? `rgba(225,19,31,${0.4 + a[C.brk] / 170})` : a[C.thr] > 90 ? '#36d399' : a[C.thr] > 5 ? '#ffc531' : '#9aa6c4')
      : ['#888', '#e1131f', '#ff8a2a', '#ffc531', '#36d399', '#3d7bff', '#a78bfa', '#f472b6', '#fff'][a[C.gear]] || '#fff';
    return `<line x1="${a[C.x]}" y1="${a[C.z]}" x2="${p[C.x]}" y2="${p[C.z]}" stroke="${col}" stroke-width="${sw * 1.6}" stroke-linecap="round"/>`;
  }).join('');
  const outline = () => {
    if (!al) return '';
    const m = al.map, pts = m.pts.map(([x, y]) => [x * m.mPerUnit, y * m.mPerUnit].map((v) => v.toFixed(1)).join(',')).join(' ');
    return `<polygon points="${pts}" fill="none" stroke="rgba(255,255,255,.10)" stroke-width="${sw * 9}" stroke-linejoin="round"/>`;
  };
  const pins = () => !t ? '' : t.corners.map((c, i) => {
    const [x, y] = mapPt(c.at);
    const lbl = String(c.n).replace(/^T(?=\d)/, '').slice(0, 5);
    return `<g class="pin" data-c="${i}" transform="translate(${x},${y})"><circle r="${sw * 4.2}" fill="${c.key ? '#e1131f' : '#0b1f4b'}" stroke="#fff" stroke-width="${sw * 0.8}"/><text text-anchor="middle" dy="${sw * 1.4}" fill="#fff" style="font-size:${sw * (lbl.length > 3 ? 2.6 : 3.8)}px">${lbl}</text></g>`;
  }).join('');
  const refLine = () => ref ? `<polyline points="${refPts(ref).map((p) => p.join(',')).join(' ')}" fill="none" stroke="rgba(255,255,255,.55)" stroke-width="${sw * 0.7}" stroke-dasharray="${sw * 2} ${sw * 2}"/>` : '';

  // per-corner analysis: nearest lap sample to each corner pin
  const cornerStats = () => !t ? [] : t.corners.map((c) => {
    const [x, y] = mapPt(c.at);
    let bi = 0, bd = Infinity;
    P.forEach((p, i) => { const d = (p[C.x] - x) ** 2 + (p[C.z] - y) ** 2; if (d < bd) { bd = d; bi = i; } });
    const win = P.slice(Math.max(0, bi - 15), bi + 15);
    const vmn = Math.min(...win.map((p) => p[C.kmh]));
    let j = bi; while (j > 0 && D[bi] - D[j] < 300 && P[j][C.brk] <= 3) j--; // last braking before the apex
    let brakeDist = 0;
    if (P[j][C.brk] > 3) { let bs = j; while (bs > 0 && P[bs - 1][C.brk] > 3) bs--; let be = j; while (be < bi && P[be + 1][C.brk] > 3) be++; brakeDist = Math.round(D[be] - D[bs]); }
    return { c, i: bi, vmin: vmn, gear: P[bi][C.gear], brakeDist };
  });

  const CH = 120;
  const chart = (key, color, max, fill) => {
    const pts = P.map((p, i) => `${(D[i] / D.at(-1)) * 1000},${CH - (p[C[key]] / max) * (CH - 8)}`).join(' ');
    return fill ? `<polygon points="0,${CH} ${pts} 1000,${CH}" fill="${color}" opacity=".35"/><polyline points="${pts}" fill="none" stroke="${color}" stroke-width="2"/>` : `<polyline points="${pts}" fill="none" stroke="${color}" stroke-width="2.5"/>`;
  };
  const refSpeed = () => { if (!ref) return ''; const R = L.cols(ref); return `<polyline points="${ref.pts.map((p, i) => `${(refD[i] / refD.at(-1)) * 1000},${CH - (p[R.kmh] / vmax) * (CH - 8)}`).join(' ')}" fill="none" stroke="rgba(255,255,255,.6)" stroke-width="1.5" stroke-dasharray="5 4"/>`; };
  const deltaChart = () => {
    if (!dl) return '';
    const mx = Math.max(0.5, ...dl.map((d) => Math.abs(d[1])));
    const pts = dl.map(([d, v]) => `${(d / D.at(-1)) * 1000},${CH / 2 - (v / mx) * (CH / 2 - 6)}`).join(' ');
    return `<line x1="0" y1="${CH / 2}" x2="1000" y2="${CH / 2}" stroke="#3f5ea8"/><polyline points="${pts}" fill="none" stroke="#ffc531" stroke-width="2.5"/><text x="8" y="16" fill="#9fb3e6" style="font-size:13px;font-family:Barlow">+${mx.toFixed(2)} s (slower)</text><text x="8" y="${CH - 6}" fill="#9fb3e6" style="font-size:13px;font-family:Barlow">−${mx.toFixed(2)} s (faster)</text>`;
  };

  const stats = cornerStats();
  el.innerHTML = String(html`
    <div class="row" style="justify-content:space-between;align-items:end">
      <div><div class="kicker">${lap.demo ? 'Demo lap · ' : ''}${t ? `${t.flag} ${t.short}` : 'Unidentified track'} · lap ${lap.lap} · car #${lap.car}</div><h1>${L.fmtLap(lap.time)}</h1></div>
      <div class="chips">${al ? raw(`<span class="chip ok">Track matched · ${al.rms.toFixed(1)} m fit</span>`) : raw('<span class="chip">No circuit match (GT original or partial lap)</span>')}${lap.timeSource === 'gt7' ? raw('<span class="chip blue">Official GT7 time</span>') : ''}</div>
    </div>
    <div class="t-hero" style="margin-top:16px">
      <div class="mapstage" style="padding-bottom:18px">
        <svg id="rsvg" viewBox="${minX} ${minZ} ${W} ${H}" width="100%" preserveAspectRatio="xMidYMid meet" style="max-height:min(620px,64vh)">
          <g id="r-outline">${raw(outline())}</g><g id="r-refline">${raw(refLine())}</g><g id="r-segs">${raw(segs())}</g><g>${raw(pins())}</g>
          <circle id="r-ghost" r="${sw * 2.6}" fill="rgba(255,255,255,.7)" stroke="#fff" stroke-width="${sw * 0.6}" style="display:none"/>
          <g id="r-car"><circle r="${sw * 3.4}" fill="#fff" stroke="#e1131f" stroke-width="${sw * 1.4}"/><path id="r-dir" d="M0 0" stroke="#e1131f" stroke-width="${sw * 1.2}" stroke-linecap="round"/></g>
        </svg>
      </div>
      <div class="grid" style="gap:14px;align-content:start">
        <div class="card pad" style="background:linear-gradient(135deg,#0b1f4b,#13306e);color:#fff">
          <div class="row" style="justify-content:space-between"><div class="kicker" style="color:#ff8a90" id="r-time">0:00.000</div><div style="color:#9fb3e6;font-weight:600" id="r-dist">0 m</div></div>
          <div class="row" style="gap:22px;margin-top:8px;align-items:end">
            <div><div id="r-v" style="font-family:var(--display);font-style:italic;font-weight:900;font-size:70px;line-height:.9">0</div><div style="color:#9fb3e6;font-weight:600">km/h</div></div>
            <div><div id="r-g" style="font-family:var(--display);font-style:italic;font-weight:900;font-size:70px;line-height:.9;color:#ffc531">1</div><div style="color:#9fb3e6;font-weight:600">gear</div></div>
            <svg viewBox="-50 -50 100 100" width="74" height="74" id="r-wheel"><g id="r-wheel-g"><circle r="40" fill="none" stroke="#fff" stroke-width="9"/><rect x="-40" y="-5" width="80" height="10" fill="#fff"/><rect x="-5" y="0" width="10" height="38" fill="#fff"/><rect x="-4" y="-46" width="8" height="12" fill="#e1131f"/></g></svg>
            <div style="flex:1;min-width:110px;display:grid;gap:7px">
              <div class="bar" style="background:rgba(255,255,255,.12)"><i id="r-rpm" style="background:#ffc531"></i></div>
              <div class="bar" style="background:rgba(255,255,255,.12)"><i id="r-thr" style="background:#36d399"></i></div>
              <div class="bar" style="background:rgba(255,255,255,.12)"><i id="r-brk" style="background:#e1131f"></i></div>
            </div>
          </div>
        </div>
        <div class="card pad">
          <div class="row"><button class="btn red" id="r-play">▶ Play</button>
            <div class="seg">${[['0.5', '½×'], ['1', '1×'], ['4', '4×']].map(([k, l]) => html`<button data-sp="${k}" class="${k === '1' ? 'on' : ''}">${l}</button>`)}</div></div>
          <input type="range" id="r-scrub" min="0" max="${total}" step="0.01" value="0" style="width:100%;margin-top:14px;accent-color:var(--red)">
          <div class="row" style="margin-top:10px"><span class="muted small">Colour by</span>
            <div class="seg">${[['speed', 'Speed'], ['inputs', 'Throttle/Brake'], ['gear', 'Gear']].map(([k, l]) => html`<button data-cm="${k}" class="${colorMode === k ? 'on' : ''}">${l}</button>`)}</div></div>
          <label class="f" style="margin-top:12px">Compare against<select id="r-ref"><option value="">— no reference —</option>${others.map((o) => html`<option value="${o.id}">${L.fmtLap(o.time)} · ${new Date(o.t0).toLocaleDateString()} · lap ${o.lap}</option>`)}</select></label>
          ${t ? html`<div class="row" style="margin-top:12px"><button class="btn sm ghost" id="r-pb">Save as PB on ${t.short} guide</button><a class="btn sm ghost" href="#/track/${t.id}">Open ${t.short} guide</a></div>` : ''}
        </div>
      </div>
    </div>
    <section class="section card pad" style="background:#0b1f4b;color:#fff">
      <div class="kicker" style="color:#9fb3e6">Speed${ref ? ' vs reference' : ''} · tap to scrub</div>
      <svg id="c-speed" viewBox="0 0 1000 ${CH}" width="100%" preserveAspectRatio="none" style="height:120px;margin-top:6px;cursor:pointer"><g id="c-speed-ref"></g>${raw(chart('kmh', '#3d7bff', vmax, true))}<line id="ph1" x1="0" x2="0" y1="0" y2="${CH}" stroke="#fff" stroke-width="2"/></svg>
      <div class="kicker" style="color:#9fb3e6;margin-top:10px">Throttle <span style="color:#36d399">■</span> · Brake <span style="color:#e1131f">■</span></div>
      <svg id="c-inp" viewBox="0 0 1000 ${CH}" width="100%" preserveAspectRatio="none" style="height:90px;margin-top:6px;cursor:pointer">${raw(chart('thr', '#36d399', 100, true))}${raw(chart('brk', '#e1131f', 100, true))}<line id="ph2" x1="0" x2="0" y1="0" y2="${CH}" stroke="#fff" stroke-width="2"/></svg>
      <div id="c-delta-wrap" style="display:none"><div class="kicker" style="color:#9fb3e6;margin-top:10px">Time delta vs reference</div>
      <svg id="c-delta" viewBox="0 0 1000 ${CH}" width="100%" preserveAspectRatio="none" style="height:100px;margin-top:6px;cursor:pointer"><g id="c-delta-g"></g><line id="ph3" x1="0" x2="0" y1="0" y2="${CH}" stroke="#fff" stroke-width="2"/></svg></div>
    </section>
    ${stats.length ? html`<section class="section card pad scroll-x"><h3>Corner by corner</h3>
      <table class="tbl" style="margin-top:10px;min-width:560px"><tr><th>Corner</th><th>Min speed</th><th>Gear</th><th>Braking zone</th><th>Guide says</th></tr>
      ${stats.map((s) => html`<tr class="crow" data-i="${s.i}" style="cursor:pointer"><td><b>${s.c.n}</b> ${s.c.name}</td><td class="num">${Math.round(s.vmin)} km/h</td><td class="num">${s.gear}</td><td>${s.brakeDist ? s.brakeDist + ' m' : 'flat / lift'}</td><td class="muted small">${s.c.speed} · gear ${s.c.gear} · ${s.c.brake}</td></tr>`)}
      </table><p class="muted small" style="margin-top:8px">Tap a row to jump the replay to that corner.</p></section>` : ''}`);

  // ── playback ──
  let ti = 0, playing = false, speed = 1, last = 0;
  const car = $('#r-car', el), dir = $('#r-dir', el), ghost = $('#r-ghost', el), scrub = $('#r-scrub', el);
  const idxAt = (time) => { let lo = 0, hi = P.length - 1; while (lo < hi) { const mid = (lo + hi) >> 1; if (P[mid][C.t] < time) lo = mid + 1; else hi = mid; } return lo; };
  const show = (time) => {
    ti = Math.max(0, Math.min(total, time));
    const i = idxAt(ti), p = P[i], q = P[Math.min(P.length - 1, i + 2)];
    car.setAttribute('transform', `translate(${p[C.x]},${p[C.z]})`);
    const ang = Math.atan2(q[C.z] - p[C.z], q[C.x] - p[C.x]);
    dir.setAttribute('d', `M0 0 L${Math.cos(ang) * sw * 7} ${Math.sin(ang) * sw * 7}`);
    $('#r-v', el).textContent = Math.round(p[C.kmh]);
    $('#r-g', el).textContent = p[C.gear] || 'N';
    $('#r-thr', el).style.width = p[C.thr] + '%';
    $('#r-brk', el).style.width = p[C.brk] + '%';
    $('#r-rpm', el).style.width = Math.min(100, (p[C.rpm] / 9000) * 100) + '%';
    $('#r-wheel-g', el).setAttribute('transform', `rotate(${(-(p[C.steer] || 0) * 180) / Math.PI * 2.5})`);
    $('#r-time', el).textContent = L.fmtLap(ti * 1000);
    $('#r-dist', el).textContent = Math.round(D[i]) + ' m';
    const x = (D[i] / D.at(-1)) * 1000;
    ['#ph1', '#ph2', '#ph3'].forEach((s) => { const l = $(s, el); if (l) { l.setAttribute('x1', x); l.setAttribute('x2', x); } });
    scrub.value = ti;
    if (ref) {
      const R = L.cols(ref), j = Math.min(ref.pts.length - 1, (() => { let lo = 0, hi = ref.pts.length - 1; while (lo < hi) { const m = (lo + hi) >> 1; if (ref.pts[m][R.t] < ti) lo = m + 1; else hi = m; } return lo; })());
      const g = toView(ref.pts[j][R.x], ref.pts[j][R.z]);
      ghost.style.display = ''; ghost.setAttribute('cx', g[0]); ghost.setAttribute('cy', g[1]);
    } else ghost.style.display = 'none';
  };
  const loop = (now) => {
    if (!playing || !el.isConnected) return;
    const dt = (now - last) / 1000; last = now;
    let nt = ti + dt * speed; if (nt >= total) nt = 0;
    show(nt); requestAnimationFrame(loop);
  };
  $('#r-play', el).onclick = (e) => { playing = !playing; e.target.textContent = playing ? '❚❚ Pause' : '▶ Play'; last = performance.now(); if (playing) requestAnimationFrame(loop); };
  scrub.oninput = () => show(+scrub.value);
  $$('[data-sp]', el).forEach((b) => (b.onclick = () => { speed = +b.dataset.sp; $$('[data-sp]', el).forEach((x) => x.classList.toggle('on', x === b)); }));
  $$('[data-cm]', el).forEach((b) => (b.onclick = () => { colorMode = b.dataset.cm; $('#r-segs', el).innerHTML = segs(); $$('[data-cm]', el).forEach((x) => x.classList.toggle('on', x === b)); }));
  const seekByChart = (svg) => (svg.onclick = (e) => { const r = svg.getBoundingClientRect(); const f = (e.clientX - r.left) / r.width; const d = f * D.at(-1); let i = D.findIndex((x) => x >= d); if (i < 0) i = P.length - 1; show(P[i][C.t]); });
  ['#c-speed', '#c-inp', '#c-delta'].forEach((s) => seekByChart($(s, el)));
  $$('.crow', el).forEach((r) => (r.onclick = () => { show(P[+r.dataset.i][C.t]); el.querySelector('#rsvg').scrollIntoView({ behavior: 'smooth', block: 'center' }); }));
  $$('#rsvg .pin', el).forEach((p) => (p.onclick = () => { const s = stats[+p.dataset.c]; if (s) show(P[s.i][C.t]); }));
  $('#r-ref', el).onchange = async (e) => {
    ref = e.target.value ? await L.getLap(e.target.value) : null;
    refD = ref ? L.distances(ref) : null; dl = ref ? L.delta(lap, ref) : null;
    $('#r-ref', el).blur();
    $('#r-refline', el).innerHTML = refLine();
    $('#c-speed-ref', el).innerHTML = refSpeed();
    $('#c-delta-g', el).innerHTML = deltaChart();
    $('#c-delta-wrap', el).style.display = ref ? '' : 'none';
    show(ti);
  };
  const pb = $('#r-pb', el);
  if (pb) pb.onclick = () => {
    const cls = prompt('Which class was this lap? (e.g. Gr.3, Gr.4, Gr.1, N)', 'Gr.3');
    if (!cls) return;
    store.set((s) => { s.pbs[t.id] = { ...(s.pbs[t.id] || {}), [cls]: L.fmtLap(lap.time).replace(/(\.\d)\d\d$/, '$1') }; });
    toast('PB saved to the ' + t.short + ' guide');
  };
  show(0);
}
