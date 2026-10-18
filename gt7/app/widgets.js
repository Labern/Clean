// Interactive diagrams for the Academy. Each mount(el) draws into `el` and wires its controls.

const W = {
  // Racing line: one 90° corner leading onto a straight; toggle the line type.
  line(el) {
    const lines = {
      early: { d: 'M 120 560 L 120 430 Q 120 300 250 300 L 300 300 Q 470 300 470 140 L 470 60', label: 'Early apex', note: 'Turns in too soon. The car runs wide at the exit, so you lift. Slowest onto the straight.', exit: 0.82 },
      geo: { d: 'M 90 560 L 90 400 Q 90 230 260 230 Q 470 230 520 60', label: 'Geometric', note: 'The widest constant arc gives the highest minimum speed, but the exit is no better than the entry.', exit: 0.92 },
      late: { d: 'M 90 560 L 90 330 Q 95 210 260 205 Q 380 205 410 160 L 470 60', label: 'Late apex', note: 'Turns in later and straightens the exit. Full throttle earlier, so it wins the straight that follows.', exit: 1 },
    };
    let cur = 'late';
    const draw = () => {
      const L = lines[cur];
      el.innerHTML = `
        <svg viewBox="0 0 640 600">
          <path d="M 40 600 L 40 300 Q 40 160 180 160 L 640 160 L 640 260 L 240 260 Q 160 260 160 340 L 160 600 Z" fill="#23407f" opacity=".0"/>
          <path d="M 60 600 L 60 330 Q 60 180 210 180 L 640 180" fill="none" stroke="#2c4a8f" stroke-width="150" stroke-linejoin="round"/>
          <path d="M 60 600 L 60 330 Q 60 180 210 180 L 640 180" fill="none" stroke="rgba(255,255,255,.08)" stroke-width="2" stroke-dasharray="10 12"/>
          <path d="M 640 115 L 640 245" stroke="#fff" stroke-width="6" stroke-dasharray="12 8"/>
          <path d="${L.d.replace(/470 60|520 60/g, '640 180')}" fill="none" stroke="#ffc531" stroke-width="7" stroke-linecap="round"/>
          <circle cx="135" cy="255" r="10" fill="#e1131f"/><text x="150" y="250" fill="#ffd5d8" font-size="18" font-family="Barlow">apex zone</text>
        </svg>
        <div class="ctrl">
          <div class="seg">${Object.entries(lines).map(([k, v]) => `<button data-k="${k}" class="${k === cur ? 'on' : ''}">${v.label}</button>`).join('')}</div>
          <div><b style="color:#fff">${L.label}.</b> ${L.note}</div>
          <div>Speed onto the straight: <b style="color:#ffc531">${Math.round(L.exit * 100)}%</b></div>
        </div>`;
      el.querySelectorAll('button[data-k]').forEach((b) => (b.onclick = () => { cur = b.dataset.k; draw(); }));
    };
    draw();
  },

  // Brake trace: drag the release shape and see stopping distance change.
  brake(el) {
    let attack = 0.15, release = 0.6;
    const draw = () => {
      const pts = [];
      for (let i = 0; i <= 100; i++) {
        const t = i / 100;
        const rise = Math.min(1, t / Math.max(0.02, attack));
        const fall = t < attack ? 1 : 1 - Math.pow((t - attack) / (1 - attack), 1 / release) * 0.9;
        pts.push([40 + t * 560, 260 - 200 * rise * fall]);
      }
      // grip available falls with speed; reward early peak and a taper
      const eff = (1 - attack * 1.6) * (0.75 + 0.25 * Math.min(1, release / 0.9)) - Math.max(0, release - 1.1) * 0.15;
      const dist = Math.round(100 / Math.max(0.4, eff));
      el.innerHTML = `
        <svg viewBox="0 0 640 300">
          <line x1="40" y1="260" x2="600" y2="260" stroke="#5a75b8"/><line x1="40" y1="40" x2="40" y2="260" stroke="#5a75b8"/>
          <text x="46" y="36" fill="#9fb3e6" font-size="14">brake pressure</text><text x="540" y="284" fill="#9fb3e6" font-size="14">time →</text>
          <polyline points="${pts.map((p) => p.join(',')).join(' ')}" fill="none" stroke="#e1131f" stroke-width="5" stroke-linejoin="round"/>
          <text x="420" y="80" fill="#fff" font-size="22" font-family="Barlow Condensed" font-style="italic" font-weight="800">STOP: ${dist} m</text>
        </svg>
        <div class="ctrl">
          <label>Time to peak pressure <input type="range" min="0.02" max="0.5" step="0.01" value="${attack}" data-k="a"></label>
          <label>Release shape (left = early bleed, right = hold to the end) <input type="range" min="0.3" max="2" step="0.05" value="${release}" data-k="r"></label>
          <div>${attack > 0.25 ? 'Too slow to peak: you waste the highest-grip moment.' : release > 1.3 ? 'Holding full pressure too long: the wheels lock as grip falls.' : 'Good: sharp peak, smooth taper. That is the trace fast drivers have.'}</div>
        </div>`;
      el.querySelectorAll('input').forEach((i) => (i.oninput = () => { if (i.dataset.k === 'a') attack = +i.value; else release = +i.value; draw(); }));
    };
    draw();
  },

  // Weight transfer: top-down car, tyre circles sized by load.
  weight(el) {
    let lon = 0, lat = 0; // -1 braking .. +1 throttle ; -1 left .. +1 right
    const draw = () => {
      const base = 0.25;
      const fl = base - lon * 0.09 + lat * 0.08, fr = base - lon * 0.09 - lat * 0.08;
      const rl = base + lon * 0.09 + lat * 0.08, rr = base + lon * 0.09 - lat * 0.08;
      const tyre = (x, y, l) => `<circle cx="${x}" cy="${y}" r="${30 + l * 140}" fill="rgba(225,19,31,${0.25 + l})" stroke="#fff" stroke-width="3"/><text x="${x}" y="${y + 6}" text-anchor="middle" fill="#fff" font-size="16" font-weight="700">${Math.round(l * 100)}%</text>`;
      el.innerHTML = `
        <svg viewBox="0 0 640 420">
          <rect x="230" y="40" width="180" height="340" rx="60" fill="#2c4a8f" stroke="#7f98d6" stroke-width="3"/>
          <text x="320" y="30" text-anchor="middle" fill="#9fb3e6" font-size="14">FRONT</text>
          ${tyre(200, 110, fl)}${tyre(440, 110, fr)}${tyre(200, 310, rl)}${tyre(440, 310, rr)}
        </svg>
        <div class="ctrl">
          <label>Brake ← → Throttle <input type="range" min="-1" max="1" step="0.05" value="${lon}" data-k="lon"></label>
          <label>Turn left ← → Turn right <input type="range" min="-1" max="1" step="0.05" value="${lat}" data-k="lat"></label>
          <div>${lon < -0.3 ? 'Braking loads the fronts: more front grip, which is why trail braking helps the car turn.' : lon > 0.3 ? 'Throttle loads the rears: traction, and less front grip (exit understeer).' : 'Balanced.'} ${Math.abs(lat) > 0.3 ? 'Cornering loads the outside tyres.' : ''}</div>
        </div>`;
      el.querySelectorAll('input').forEach((i) => (i.oninput = () => { if (i.dataset.k === 'lon') lon = +i.value; else lat = +i.value; draw(); }));
    };
    draw();
  },

  // Traction circle: animate a corner as a novice "plus sign" vs a pro edge trace.
  circle(el) {
    let mode = 'pro', raf, t0;
    const path = (mode, t) => {
      // phases: brake -> turn -> throttle, 0..1
      if (mode === 'novice') {
        if (t < 0.3) return [0, -0.95];
        if (t < 0.36) return [0, -0.95 + (t - 0.3) / 0.06 * 0.95];
        if (t < 0.64) return [0.95 * Math.min(1, (t - 0.36) / 0.05), 0];
        if (t < 0.7) return [0.95 * (1 - (t - 0.64) / 0.06), 0];
        return [0, 0.8];
      }
      const a = -Math.PI / 2 + t * Math.PI; // sweep around the edge from brake to throttle
      return [Math.cos(a) * 0.95, Math.sin(a) * 0.95 * (a > 0 ? 0.85 : 1)];
    };
    const frame = (now) => {
      t0 ??= now;
      const t = ((now - t0) / 3200) % 1;
      const [x, y] = path(mode, t);
      const dot = el.querySelector('#tc-dot');
      if (!dot) return;
      dot.setAttribute('cx', 320 + x * 180);
      dot.setAttribute('cy', 210 + y * 180);
      const tr = el.querySelector('#tc-trail');
      const pts = [];
      for (let i = 0; i <= 60 && t - i / 200 >= 0; i++) { const [px, py] = path(mode, t - i / 200); pts.push(`${320 + px * 180},${210 + py * 180}`); }
      tr.setAttribute('points', pts.join(' '));
      raf = requestAnimationFrame(frame);
    };
    const draw = () => {
      cancelAnimationFrame(raf);
      el.innerHTML = `
        <svg viewBox="0 0 640 420">
          <circle cx="320" cy="210" r="180" fill="rgba(255,255,255,.04)" stroke="#7f98d6" stroke-width="3"/>
          <line x1="140" y1="210" x2="500" y2="210" stroke="#3f5ea8"/><line x1="320" y1="30" x2="320" y2="390" stroke="#3f5ea8"/>
          <text x="320" y="22" text-anchor="middle" fill="#9fb3e6" font-size="14">BRAKING</text>
          <text x="320" y="410" text-anchor="middle" fill="#9fb3e6" font-size="14">ACCELERATING</text>
          <text x="520" y="215" fill="#9fb3e6" font-size="14">CORNERING</text>
          <polyline id="tc-trail" fill="none" stroke="rgba(255,197,49,.6)" stroke-width="5" stroke-linecap="round"/>
          <circle id="tc-dot" r="13" fill="#e1131f" stroke="#fff" stroke-width="3"/>
        </svg>
        <div class="ctrl">
          <div class="seg"><button data-m="novice" class="${mode === 'novice' ? 'on' : ''}">Novice: brake, then turn, then throttle</button><button data-m="pro" class="${mode === 'pro' ? 'on' : ''}">Pro: blends along the edge</button></div>
          <div>${mode === 'pro' ? 'The pro trace stays on the edge of the circle: 100% of the grip, all the time.' : 'The plus sign wastes the corners of the circle, which is time lost in every turn.'}</div>
        </div>`;
      el.querySelectorAll('button[data-m]').forEach((b) => (b.onclick = () => { mode = b.dataset.m; t0 = undefined; draw(); }));
      raf = requestAnimationFrame(frame);
    };
    draw();
  },
};

export function mountWidget(name, el) {
  if (W[name]) W[name](el);
}
