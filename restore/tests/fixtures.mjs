// Synthetic ground truth + reproducible degradation. No binary fixtures: the
// "photograph" is generated, so the suite is self-contained and deterministic.
export function prng(seed){let s=seed>>>0||1;return()=>{s^=s<<13;s>>>=0;s^=s>>17;s^=s<<5;s>>>=0;return s/4294967296;};}

export function makePhoto(w, h) {
  const d = new Uint8ClampedArray(w * h * 4);
  const rnd = prng(42);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const p = (y * w + x) * 4, u = x / w, v = y / h;
    // sky-ish vertical gradient
    let R = 150 - 60 * v, G = 160 - 55 * v, B = 185 - 40 * v;
    // hard-edged building block (sharp edges = what SR/sharpening is judged on)
    if (u > 0.08 && u < 0.42 && v > 0.30) { R = 92; G = 78; B = 70;
      // windows: high-contrast small structure
      const wx = Math.floor((x - 0.08 * w) / (0.05 * w)), wy = Math.floor((y - 0.30 * h) / (0.09 * h));
      if ((wx + wy) % 2 === 0 && ((x - 0.08 * w) % (0.05 * w)) < 0.032 * w
          && ((y - 0.30 * h) % (0.09 * h)) < 0.055 * h) { R = 226; G = 214; B = 176; }
    }
    // a face-like smooth ellipse — flat tone, where haloing and blotching show
    const dx = (u - 0.70) / 0.16, dy = (v - 0.42) / 0.22;
    if (dx * dx + dy * dy < 1) {
      const s = 1 - 0.35 * Math.sqrt(dx * dx + dy * dy);
      R = 214 * s; G = 176 * s; B = 150 * s;
      if (Math.abs(u - 0.70) > 0.05 && Math.abs(v - 0.36) < 0.012) { R = 60; G = 45; B = 40; } // eyes line
    }
    // fine diagonal texture, confined to a band — the detail a denoiser must
    // not eat. The rest of the frame stays smooth, so a noise estimator has
    // flat ground to measure against, exactly like a real photograph.
    if (v > 0.72) { const t = Math.sin((x * 0.9 + y * 0.6)) * 6; R += t; G += t; B += t; }
    d[p] = R; d[p + 1] = G; d[p + 2] = B; d[p + 3] = 255;
  }
  return { width: w, height: h, data: d };
}

// Optical downscale (box) — models the low-res scan we must upsample from.
export function downscale(img, f) {
  const w = Math.floor(img.width / f), h = Math.floor(img.height / f);
  const d = new Uint8ClampedArray(w * h * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    let a = 0, b = 0, c = 0;
    for (let j = 0; j < f; j++) for (let i = 0; i < f; i++) {
      const p = ((y * f + j) * img.width + (x * f + i)) * 4;
      a += img.data[p]; b += img.data[p + 1]; c += img.data[p + 2];
    }
    const q = (y * w + x) * 4, k = f * f;
    d[q] = a / k; d[q + 1] = b / k; d[q + 2] = c / k; d[q + 3] = 255;
  }
  return { width: w, height: h, data: d };
}

// Damage: dust specks + scratches. Returns the image and the truth mask.
export function damage(img, { specks = 400, scratches = 6, seed = 7 } = {}) {
  const { width: w, height: h } = img;
  const d = Uint8ClampedArray.from(img.data);
  const truth = new Uint8Array(w * h);
  const rnd = prng(seed);
  const put = (x, y, v) => {
    x |= 0; y |= 0;
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    const p = (y * w + x) * 4;
    d[p] = v; d[p + 1] = v; d[p + 2] = v; truth[y * w + x] = 1;
  };
  for (let i = 0; i < specks; i++) {
    const x = rnd() * w, y = rnd() * h, bright = rnd() > 0.45;
    const v = bright ? 236 + rnd() * 19 : rnd() * 18;
    const r = rnd() < 0.75 ? 0 : 1;
    for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) put(x + dx, y + dy, v);
  }
  for (let s = 0; s < scratches; s++) {
    let x = rnd() * w, y = rnd() * h;
    const ang = rnd() * Math.PI * 2, len = (0.18 + rnd() * 0.5) * Math.max(w, h);
    const vx = Math.cos(ang), vy = Math.sin(ang);
    const bright = rnd() > 0.4, v = bright ? 240 : 10;
    for (let t = 0; t < len; t += 0.5) {
      const wob = Math.sin(t * 0.07) * 2.0;
      put(x + vx * t - vy * wob, y + vy * t + vx * wob, v);
    }
  }
  return { img: { width: w, height: h, data: d }, truth };
}

// Fade: compress the range and yellow it, the way a print in a window does.
export function fade(img, { lift = 34, ceil = 196, cast = [1.0, 0.95, 0.80] } = {}) {
  const d = Uint8ClampedArray.from(img.data);
  for (let p = 0; p < d.length; p += 4) for (let c = 0; c < 3; c++)
    d[p + c] = lift + (d[p + c] / 255) * (ceil - lift) * cast[c];
  return { width: img.width, height: img.height, data: d };
}

export function addNoise(img, amp, seed = 99) {
  const d = Uint8ClampedArray.from(img.data), rnd = prng(seed);
  for (let p = 0; p < d.length; p += 4) {
    const g = (rnd() + rnd() + rnd() - 1.5) * amp;
    d[p] += g; d[p + 1] += g * 1.1; d[p + 2] += g * 0.9;
  }
  return { width: img.width, height: img.height, data: d };
}

export function psnr(a, b) {
  let se = 0, cnt = 0;
  for (let i = 0; i < a.length; i++) { if ((i & 3) === 3) continue; const x = a[i] - b[i]; se += x * x; cnt++; }
  return se === 0 ? Infinity : 10 * Math.log10(65025 / (se / cnt));
}
// Error restricted to a pixel set — how well the damaged pixels specifically came back.
export function psnrAt(a, b, sel, w, h) {
  let se = 0, cnt = 0;
  for (let i = 0; i < w * h; i++) if (sel[i]) {
    for (let c = 0; c < 3; c++) { const x = a[i * 4 + c] - b[i * 4 + c]; se += x * x; cnt++; }
  }
  return cnt === 0 ? Infinity : (se / cnt === 0 ? Infinity : 10 * Math.log10(65025 / (se / cnt)));
}
