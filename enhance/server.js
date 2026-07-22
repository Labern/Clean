#!/usr/bin/env node
// ENHANCE — local video & photo mastering.
// Zero npm dependencies: Node stdlib + native ffmpeg/ffprobe (+ sips for HEIC,
// + optional Real-ESRGAN for the neural engine — see setup-neural.sh).
// Everything stays on this Mac; the browser is just the control surface.

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawn, execFile } = require('child_process');

const PORT = parseInt(process.env.PORT || '2160', 10); // 2160 = the vertical resolution of 4K
const ROOT = __dirname;
const WORK = path.join(ROOT, 'work');
const UPLOADS = path.join(WORK, 'uploads');
const OUTPUT = path.join(WORK, 'output');
const THUMBS = path.join(WORK, 'thumbs');
const JOBS_FILE = path.join(WORK, 'jobs.json');
const ESRGAN_DIR = path.join(ROOT, 'vendor', 'realesrgan');
for (const d of [UPLOADS, OUTPUT, THUMBS]) fs.mkdirSync(d, { recursive: true });

const jobs = new Map();

const esrganBin = () => {
  const p = path.join(ESRGAN_DIR, 'realesrgan-ncnn-vulkan');
  return fs.existsSync(p) ? p : null;
};

// ── persistence — download links survive restarts (never lose progress) ────

function persistJobs() {
  const plain = [];
  for (const j of jobs.values()) {
    if (!['uploaded', 'done', 'error'].includes(j.status)) continue;
    plain.push({ id: j.id, kind: j.kind || 'video', src: j.src, name: j.name, meta: j.meta,
      status: j.status, out: j.out, outName: j.outName, outMeta: j.outMeta, frames: j.frames,
      compare: j.compare });
  }
  try {
    fs.writeFileSync(JOBS_FILE + '.tmp', JSON.stringify(plain));
    fs.renameSync(JOBS_FILE + '.tmp', JOBS_FILE);
  } catch {}
}

async function bootRestore() {
  try {
    for (const j of JSON.parse(fs.readFileSync(JOBS_FILE, 'utf8'))) {
      if (!j.src || !fs.existsSync(j.src)) continue;
      if (j.out && !fs.existsSync(j.out)) { j.out = null; j.outName = null; j.status = 'uploaded'; }
      jobs.set(j.id, { ...j, listeners: new Set() });
    }
  } catch {}
  for (const f of fs.readdirSync(UPLOADS)) {
    const m = /^([0-9a-f]{12})\.(\w+)$/.exec(f);
    if (!m || jobs.has(m[1])) continue;
    try {
      let src = path.join(UPLOADS, f);
      const decoded = path.join(UPLOADS, m[1] + '-decoded.png');
      if (fs.existsSync(decoded)) src = decoded;
      const meta = summarize(await probe(src));
      if (!meta) continue;
      const kind = ['.mp4', '.mov', '.m4v'].includes(path.extname(f).toLowerCase()) ? 'video' : 'image';
      jobs.set(m[1], { id: m[1], kind, src, name: f, meta, status: 'uploaded', listeners: new Set() });
    } catch {}
  }
  for (const f of fs.readdirSync(OUTPUT)) {
    const m = /^([0-9a-f]{12})-(.+)$/.exec(f);
    if (!m || m[2].startsWith('frame-')) continue;
    if (m[2] === 'compare.mp4') { // re-attach orphaned comparison renders
      const cj = jobs.get(m[1]);
      if (cj && !cj.compare) cj.compare = { out: path.join(OUTPUT, f),
        name: path.basename(cj.name, path.extname(cj.name)) + '-before-after.mp4' };
      continue;
    }
    const j = jobs.get(m[1]);
    if (!j || j.out) continue;
    j.out = path.join(OUTPUT, f);
    j.outName = path.basename(j.name, path.extname(j.name)) + '-' + m[2];
    j.status = 'done';
    try { j.outMeta = summarize(await probe(j.out)); } catch {}
  }
  persistJobs();
}

// ── helpers ────────────────────────────────────────────────────────────────

function probe(file) {
  return new Promise((resolve, reject) => {
    execFile('ffprobe',
      ['-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', file],
      { maxBuffer: 32 * 1024 * 1024 },
      (err, out) => {
        if (err) return reject(err);
        try { resolve(JSON.parse(out)); } catch (e) { reject(e); }
      });
  });
}

function summarize(p) {
  const v = (p.streams || []).find(s => s.codec_type === 'video');
  if (!v) return null;
  const a = (p.streams || []).find(s => s.codec_type === 'audio');
  const [n, d] = (v.avg_frame_rate || '0/1').split('/').map(Number);
  const fps = d ? n / d : 0;
  return {
    width: v.width, height: v.height,
    codec: v.codec_name, pix_fmt: v.pix_fmt,
    fps: Math.round(fps * 100) / 100,
    duration: parseFloat(p.format.duration || 0),
    size: parseInt(p.format.size || 0, 10),
    audio: a ? a.codec_name : null,
  };
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', c => { body += c; });
    req.on('end', () => { try { resolve(JSON.parse(body || '{}')); } catch (e) { reject(e); } });
    req.on('error', reject);
  });
}

function json(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) });
  res.end(body);
}

function ffmpegOnce(args) {
  return new Promise((resolve, reject) => {
    execFile('ffmpeg', args, { maxBuffer: 64 * 1024 * 1024 }, (err, _out, stderr) =>
      err ? reject(new Error(String(stderr).split('\n').filter(Boolean).slice(-2).join(' · '))) : resolve(String(stderr)));
  });
}

function esrganOnce(args) {
  return new Promise((resolve, reject) => {
    execFile(esrganBin(), [...args, '-m', path.join(ESRGAN_DIR, 'models')],
      { maxBuffer: 16 * 1024 * 1024 },
      (err, _out, stderr) => err
        ? reject(new Error('neural engine: ' + String(stderr).split('\n').filter(Boolean).slice(-2).join(' · ')))
        : resolve());
  });
}

function sipsToPng(src, dst) {
  return new Promise((resolve, reject) => {
    execFile('sips', ['-s', 'format', 'png', src, '--out', dst], err =>
      err ? reject(new Error('HEIC decode failed')) : resolve());
  });
}

// ── the film pipeline ──────────────────────────────────────────────────────
// [neural: frames redrawn 4× by Real-ESRGAN first] → slo-mo retime or
// frame-rate change → lanczos to exact target → subtle unsharp (classic only)
// → HEVC + faststart.

const RES_LABEL = { 1080: '1080p', 1440: '1440p', 2160: '4K', 4320: '8K' };

function buildFilterChain(job) {
  const { meta, opts } = job;
  const H = parseInt(opts.res, 10) || 2160;
  const S = [1, 2, 4, 8].includes(+opts.speed) ? +opts.speed : 1;
  const filters = [];
  const srcFps = meta.fps || 30;
  const targetFps = opts.fps === 'source' ? null : parseInt(opts.fps, 10);

  if (S > 1) {
    if (opts.mode === 'smooth') {
      let play = targetFps || Math.min(60, Math.round(srcFps * 2));
      const synth = Math.min(240, play * S);
      filters.push(`minterpolate=fps=${synth}:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1`);
      filters.push(`setpts=${S}*PTS`);
    } else {
      filters.push(`setpts=${S}*PTS`);
      if (targetFps) filters.push(`fps=${targetFps}`);
    }
  } else if (targetFps && Math.abs(targetFps - srcFps) > 0.01) {
    if (opts.mode === 'smooth' && targetFps > srcFps) {
      filters.push(`minterpolate=fps=${targetFps}:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1`);
    } else {
      filters.push(`fps=${targetFps}`);
    }
  }

  filters.push(`scale='if(gt(a,1),-2,${H})':'if(gt(a,1),${H},-2)':flags=lanczos+accurate_rnd`);
  if (opts.engine !== 'neural') filters.push('unsharp=5:5:0.6:5:5:0.0'); // ESRGAN output is already crisp

  job.effDur = (meta.duration || 0) * S;
  return filters.join(',');
}

function buildCodecAudioArgs(job) {
  const { meta, opts } = job;
  const S = [1, 2, 4, 8].includes(+opts.speed) ? +opts.speed : 1;
  const args = [];
  if (opts.enc === 'max') {
    args.push('-c:v', 'libx265', '-preset', 'medium', '-crf', '16',
      '-tag:v', 'hvc1', '-pix_fmt', 'yuv420p');
  } else {
    args.push('-c:v', 'hevc_videotoolbox', '-q:v', '65', '-allow_sw', '1',
      '-tag:v', 'hvc1', '-pix_fmt', 'yuv420p');
  }
  if (meta.audio && S > 1) {
    args.push('-af', Array(Math.log2(S)).fill('atempo=0.5').join(','), '-c:a', 'aac', '-b:a', '256k');
  } else if (meta.audio) {
    const copyOk = ['aac', 'mp3', 'ac3', 'eac3'].includes(meta.audio);
    args.push('-c:a', copyOk ? 'copy' : 'aac');
    if (!copyOk) args.push('-b:a', '256k');
  }
  return args;
}

function broadcast(job, event) {
  const line = `data: ${JSON.stringify(event)}\n\n`;
  for (const res of job.listeners) res.write(line);
}

// spawn ffmpeg for a job with -progress parsing; handles done/error/cancelled
function runFfmpegJob(job, args, cleanup) {
  const proc = spawn('ffmpeg', args);
  job.proc = proc;
  let stderrTail = '';
  proc.stderr.on('data', c => { stderrTail = (stderrTail + c).slice(-4000); });

  let buf = '';
  const prog = { pct: 0, fps: 0, speed: 0, frame: 0, eta: 0, phase: 'encode' };
  proc.stdout.on('data', chunk => {
    buf += chunk;
    const lines = buf.split('\n');
    buf = lines.pop();
    const kv = {};
    for (const l of lines) {
      const i = l.indexOf('=');
      if (i > 0) kv[l.slice(0, i).trim()] = l.slice(i + 1).trim();
    }
    const us = parseFloat(kv.out_time_us || kv.out_time_ms || 0); // both are µs
    if (us > 0 && job.effDur > 0) prog.pct = Math.min(99.9, (us / 1e6 / job.effDur) * 100);
    if (kv.fps) prog.fps = parseFloat(kv.fps) || 0;
    if (kv.frame) prog.frame = parseInt(kv.frame, 10) || 0;
    if (kv.speed) prog.speed = parseFloat(kv.speed) || 0;
    prog.eta = prog.speed > 0 ? Math.max(0, (job.effDur - us / 1e6) / prog.speed) : 0;
    broadcast(job, { type: 'progress', ...prog });
  });

  proc.on('close', async code => {
    job.proc = null;
    if (cleanup) cleanup();
    if (job.status === 'cancelled') {
      fs.rm(job.out, { force: true }, () => {});
      broadcast(job, { type: 'cancelled' });
      return;
    }
    if (code !== 0) {
      job.status = 'error';
      job.error = stderrTail.split('\n').filter(Boolean).slice(-3).join(' · ');
      persistJobs();
      broadcast(job, { type: 'error', message: job.error });
      return;
    }
    try {
      const outMeta = summarize(await probe(job.out));
      job.status = 'done';
      job.outMeta = outMeta;
      persistJobs();
      broadcast(job, { type: 'done', meta: outMeta, name: job.outName });
    } catch (e) {
      job.status = 'error';
      job.error = 'output probe failed: ' + e.message;
      persistJobs();
      broadcast(job, { type: 'error', message: job.error });
    }
  });
}

function runJob(job) {
  job.status = 'running';
  const vf = buildFilterChain(job);
  runFfmpegJob(job, ['-y', '-hide_banner', '-nostats', '-progress', 'pipe:1',
    '-i', job.src, '-vf', vf, '-map', '0:v:0', '-map', '0:a:0?',
    ...buildCodecAudioArgs(job), '-movflags', '+faststart', job.out]);
}

// neural: extract frames → Real-ESRGAN redraws each 4× → encode from frames
async function runJobNeural(job) {
  job.status = 'running';
  const FR = path.join(WORK, `nn-${job.id}-in`);
  const SR = path.join(WORK, `nn-${job.id}-out`);
  const cleanup = () => { for (const d of [FR, SR]) fs.rmSync(d, { recursive: true, force: true }); };
  try {
    cleanup();
    fs.mkdirSync(FR, { recursive: true });
    fs.mkdirSync(SR, { recursive: true });
    broadcast(job, { type: 'progress', phase: 'extract', pct: 0 });
    await ffmpegOnce(['-y', '-hide_banner', '-i', job.src, path.join(FR, '%06d.png')]);
    const total = fs.readdirSync(FR).length || 1;

    const proc = spawn(esrganBin(), ['-i', FR, '-o', SR, '-n', 'realesrgan-x4plus',
      '-s', '4', '-f', 'jpg', '-m', path.join(ESRGAN_DIR, 'models')]);
    job.proc = proc;
    let err = '';
    proc.stderr.on('data', c => { err = (err + c).slice(-2000); });
    const t0 = Date.now();
    const tick = setInterval(() => {
      let done = 0;
      try { done = fs.readdirSync(SR).length; } catch {}
      const rate = done / Math.max(1, (Date.now() - t0) / 1000);
      broadcast(job, { type: 'progress', phase: 'neural', pct: Math.min(99, done / total * 100),
        frame: done, total, eta: rate > 0 ? (total - done) / rate : 0 });
    }, 1000);
    const code = await new Promise(r => proc.on('close', r));
    clearInterval(tick);
    job.proc = null;
    if (job.status === 'cancelled') { cleanup(); broadcast(job, { type: 'cancelled' }); return; }
    if (code !== 0) throw new Error('neural engine failed: '
      + err.split('\n').filter(Boolean).slice(-2).join(' · '));

    const srcFps = job.meta.fps || 30;
    const vf = buildFilterChain(job);
    runFfmpegJob(job, ['-y', '-hide_banner', '-nostats', '-progress', 'pipe:1',
      '-framerate', String(srcFps), '-i', path.join(SR, '%06d.jpg'), '-i', job.src,
      '-vf', vf, '-map', '0:v:0', '-map', '1:a:0?',
      ...buildCodecAudioArgs(job), '-movflags', '+faststart', job.out], cleanup);
  } catch (e) {
    cleanup();
    job.status = 'error';
    job.error = e.message;
    persistJobs();
    broadcast(job, { type: 'error', message: e.message });
  }
}

// ── the photo pipeline ─────────────────────────────────────────────────────

const LOOKS = {
  natural: 'cas=0.4,vibrance=intensity=0.10,eq=contrast=1.03:saturation=1.04',
  vivid:   'cas=0.45,vibrance=intensity=0.25,eq=contrast=1.07:saturation=1.12:brightness=0.01',
  crisp:   'cas=0.6,unsharp=5:5:0.5:5:5:0.0,eq=contrast=1.04',
  punch:   'split[o][b];[b]gblur=sigma=12[bl];[o][bl]blend=all_mode=softlight:all_opacity=0.35,cas=0.35,eq=saturation=1.05',
  film:    'curves=preset=vintage,eq=saturation=0.92:contrast=1.05,noise=alls=5:allf=t',
  noir:    'hue=s=0,split[o][b];[b]gblur=sigma=10[bl];[o][bl]blend=all_mode=softlight:all_opacity=0.3,eq=contrast=1.16,vignette=angle=PI/6',
  gold:    'colortemperature=temperature=5100:pl=0.8,vibrance=intensity=0.12,cas=0.35',
  dream:   'split[m][b];[b]gblur=sigma=22[g];[m][g]blend=all_mode=screen:all_opacity=0.32,cas=0.2,eq=saturation=1.05',
};

// ── frame capture ──────────────────────────────────────────────────────────

function dedupeTimes(ts, gap) {
  const out = [];
  for (const t of [...ts].sort((a, b) => a - b))
    if (!out.length || t - out[out.length - 1] >= gap) out.push(t);
  return out;
}

function spreadPick(arr, n) {
  if (arr.length <= n) return arr;
  const out = [];
  for (let i = 0; i < n; i++) out.push(arr[Math.round(i * (arr.length - 1) / (n - 1))]);
  return [...new Set(out)];
}

async function analyzeFrames(job, count) {
  const dur = job.meta.duration || 1;
  let times = [];
  try {
    const stderr = await new Promise(resolve => {
      execFile('ffmpeg', ['-hide_banner', '-i', job.src, '-vf',
        "scale=160:-2,select='gt(scene,0.30)',showinfo", '-frames:v', '120', '-f', 'null', '-'],
        { maxBuffer: 64 * 1024 * 1024 }, (_e, _o, se) => resolve(String(se)));
    });
    for (const m of stderr.matchAll(/pts_time:\s*([\d.]+)/g)) times.push(parseFloat(m[1]));
  } catch {}
  const gap = Math.max(0.5, dur / (count * 6));
  let picks = dedupeTimes(times, gap);
  if (picks.length < count) {
    const even = [];
    for (let i = 0; i < count; i++) even.push(+(dur * (i + 0.5) / count).toFixed(2));
    picks = dedupeTimes([...picks, ...even], gap);
  }
  picks = spreadPick(picks, count).map(t => +t.toFixed(2));
  const dir = path.join(THUMBS, job.id);
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
  for (let i = 0; i < picks.length; i++) {
    await ffmpegOnce(['-y', '-hide_banner', '-ss', String(picks[i]), '-i', job.src,
      '-frames:v', '1', '-q:v', '4', '-vf', 'scale=400:-2', path.join(dir, i + '.jpg')]);
  }
  job.frames = picks;
  persistJobs();
  return picks;
}

// A seek at ~duration can decode zero frames; clamp and walk back until one lands.
async function grabFrame(job, t) {
  const file = path.join(OUTPUT, `${job.id}-frame-${t.toFixed(2)}.jpg`);
  if (fs.existsSync(file)) return file;
  const dur = job.meta.duration || 0;
  const clamped = Math.max(0, Math.min(t, Math.max(0, dur - 0.05)));
  for (const cand of [clamped, clamped - 0.5, clamped - 1].filter(x => x >= 0)) {
    try {
      await ffmpegOnce(['-y', '-hide_banner', '-ss', String(cand), '-i', job.src,
        '-frames:v', '1', '-q:v', '1', '-qmin', '1', '-pix_fmt', 'yuvj444p', file]);
    } catch {}
    if (fs.existsSync(file)) return file;
  }
  throw new Error(`no frame decodable near ${t.toFixed(2)}s`);
}

// ── minimal ZIP writer (store mode — JPEGs don't recompress) ───────────────

const CRC_T = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(buf) {
  let c = 0xFFFFFFFF;
  for (let i = 0; i < buf.length; i++) c = CRC_T[(c ^ buf[i]) & 0xFF] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}
function zipStore(entries) {
  const parts = [], central = [];
  let off = 0;
  for (const { name, data } of entries) {
    const n = Buffer.from(name), crc = crc32(data);
    const lh = Buffer.alloc(30);
    lh.writeUInt32LE(0x04034b50, 0); lh.writeUInt16LE(20, 4);
    lh.writeUInt32LE(crc, 14); lh.writeUInt32LE(data.length, 18); lh.writeUInt32LE(data.length, 22);
    lh.writeUInt16LE(n.length, 26);
    parts.push(lh, n, data);
    const ch = Buffer.alloc(46);
    ch.writeUInt32LE(0x02014b50, 0); ch.writeUInt16LE(20, 4); ch.writeUInt16LE(20, 6);
    ch.writeUInt32LE(crc, 16); ch.writeUInt32LE(data.length, 20); ch.writeUInt32LE(data.length, 24);
    ch.writeUInt16LE(n.length, 28); ch.writeUInt32LE(off, 42);
    central.push(ch, n);
    off += 30 + n.length + data.length;
  }
  const cd = Buffer.concat(central);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(entries.length, 8); eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(cd.length, 12); eocd.writeUInt32LE(off, 16);
  return Buffer.concat([...parts, cd, eocd]);
}

// ── file streaming (Range-aware, for inline previews) ──────────────────────

const MIME = { '.mp4': 'video/mp4', '.mov': 'video/quicktime', '.m4v': 'video/mp4',
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png',
  '.webp': 'image/webp', '.tiff': 'image/tiff', '.tif': 'image/tiff' };

function sendFile(req, res, file, name, download) {
  let stat;
  try { stat = fs.statSync(file); } catch { return json(res, 404, { error: 'not found' }); }
  const type = MIME[path.extname(file).toLowerCase()] || 'application/octet-stream';
  const headers = { 'Content-Type': type, 'Accept-Ranges': 'bytes' };
  if (download) headers['Content-Disposition'] = `attachment; filename="${name.replace(/"/g, '')}"`;
  const range = req.headers.range && /bytes=(\d*)-(\d*)/.exec(req.headers.range);
  if (range) {
    const start = range[1] ? parseInt(range[1], 10) : 0;
    const end = range[2] ? Math.min(parseInt(range[2], 10), stat.size - 1) : stat.size - 1;
    headers['Content-Range'] = `bytes ${start}-${end}/${stat.size}`;
    headers['Content-Length'] = end - start + 1;
    res.writeHead(206, headers);
    fs.createReadStream(file, { start, end }).pipe(res);
  } else {
    headers['Content-Length'] = stat.size;
    res.writeHead(200, headers);
    fs.createReadStream(file).pipe(res);
  }
}

function streamUpload(req, res, exts, onReady) {
  const rawName = decodeURIComponent(req.headers['x-filename'] || 'file');
  const name = path.basename(rawName).replace(/[^\w.\- ()\[\]]/g, '_');
  const ext = path.extname(name).toLowerCase();
  if (!exts.includes(ext)) return json(res, 415, { error: exts.join(' / ') + ' only' });
  const id = crypto.randomBytes(6).toString('hex');
  const dst = path.join(UPLOADS, id + ext);
  const ws = fs.createWriteStream(dst);
  req.pipe(ws);
  req.on('error', () => { ws.destroy(); fs.rm(dst, { force: true }, () => {}); });
  ws.on('finish', () => onReady(id, dst, name, ext).catch(e => {
    fs.rm(dst, { force: true }, () => {});
    json(res, 415, { error: 'not readable: ' + e.message });
  }));
}

// ── routes ─────────────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  try {
    if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/index.html')) {
      const html = fs.readFileSync(path.join(ROOT, 'public', 'index.html'));
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      return res.end(html);
    }

    if (req.method === 'GET' && url.pathname === '/caps') {
      return json(res, 200, { neural: !!esrganBin() });
    }

    if (req.method === 'POST' && url.pathname === '/upload') {
      return streamUpload(req, res, ['.mp4', '.mov', '.m4v'], async (id, dst, name) => {
        const meta = summarize(await probe(dst));
        if (!meta) throw new Error('no video stream');
        jobs.set(id, { id, kind: 'video', src: dst, name, meta, status: 'uploaded', listeners: new Set() });
        persistJobs();
        json(res, 200, { id, name, meta });
      });
    }

    if (req.method === 'POST' && url.pathname === '/upload-image') {
      return streamUpload(req, res, ['.jpg', '.jpeg', '.png', '.heic', '.webp', '.tiff', '.tif'],
        async (id, dst, name, ext) => {
          let src = dst;
          if (ext === '.heic') {
            src = path.join(UPLOADS, id + '-decoded.png');
            await sipsToPng(dst, src);
          }
          const meta = summarize(await probe(src));
          if (!meta) throw new Error('no image data');
          jobs.set(id, { id, kind: 'image', src, name, meta, status: 'uploaded', listeners: new Set() });
          persistJobs();
          json(res, 200, { id, name, meta: { width: meta.width, height: meta.height, size: meta.size } });
        });
    }

    if (req.method === 'POST' && url.pathname === '/enhance') {
      const { id, res: r, fps, mode, enc, speed, engine } = await readJson(req);
      const job = jobs.get(id);
      if (!job || job.kind !== 'video') return json(res, 404, { error: 'unknown id' });
      if (job.status === 'running') return json(res, 409, { error: 'already running' });
      const wantNeural = engine === 'neural';
      if (wantNeural && !esrganBin())
        return json(res, 503, { error: 'neural engine not installed — run setup-neural.sh' });
      job.opts = {
        res: ['1080', '1440', '2160', '4320'].includes(String(r)) ? String(r) : '2160',
        fps: ['source', '24', '30', '60', '120'].includes(String(fps)) ? String(fps) : 'source',
        mode: mode === 'fast' ? 'fast' : 'smooth',
        enc: enc === 'max' ? 'max' : 'turbo',
        speed: ['1', '2', '4', '8'].includes(String(speed)) ? String(speed) : '1',
        engine: wantNeural ? 'neural' : 'classic',
      };
      const base = path.basename(job.name, path.extname(job.name));
      const tag = RES_LABEL[job.opts.res] + (job.opts.fps === 'source' ? '' : job.opts.fps)
        + (job.opts.speed !== '1' ? `-slo${job.opts.speed}x` : '')
        + (wantNeural ? '-nn' : '');
      job.outName = `${base}-${tag}.mp4`;
      job.out = path.join(OUTPUT, `${id}-${tag}.mp4`);
      if (wantNeural) runJobNeural(job); else runJob(job);
      return json(res, 200, { ok: true, outName: job.outName });
    }

    if (req.method === 'GET' && url.pathname === '/events') {
      const job = jobs.get(url.searchParams.get('id'));
      if (!job) return json(res, 404, { error: 'unknown id' });
      res.writeHead(200, {
        'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive',
      });
      res.write(`data: ${JSON.stringify({ type: 'hello', status: job.status })}\n\n`);
      job.listeners.add(res);
      const beat = setInterval(() => res.write(': beat\n\n'), 15000);
      req.on('close', () => { clearInterval(beat); job.listeners.delete(res); });
      return;
    }

    if (req.method === 'POST' && url.pathname === '/cancel') {
      const { id } = await readJson(req);
      const job = jobs.get(id);
      if (job && job.proc) { job.status = 'cancelled'; job.proc.kill('SIGKILL'); }
      return json(res, 200, { ok: true });
    }

    if (req.method === 'POST' && url.pathname === '/enhance-image') {
      const { id, scale, look, levels, grain, engine } = await readJson(req);
      const job = jobs.get(id);
      if (!job || job.kind !== 'image') return json(res, 404, { error: 'unknown id' });
      const F = ['1', '2', '4'].includes(String(scale)) ? parseInt(scale, 10) : 2;
      const L = LOOKS[look] ? look : 'natural';
      const wantNeural = engine === 'neural';
      if (wantNeural && !esrganBin())
        return json(res, 503, { error: 'neural engine not installed — run setup-neural.sh' });
      const base = path.basename(job.name, path.extname(job.name));
      const tag = `${F}x-${L}${levels ? '-lv' : ''}${grain ? '-gr' : ''}${wantNeural ? '-nn' : ''}`;
      job.outName = `${base}-${tag}.jpg`;
      job.out = path.join(OUTPUT, `${id}-${tag}.jpg`);
      let input = job.src;
      let srTmp = null;
      try {
        const filters = [];
        if (levels) filters.push('normalize');
        if (wantNeural) {
          // redraw with Real-ESRGAN at 4× (or the exact factor), then grade
          srTmp = path.join(WORK, `nn-${id}-photo.png`);
          await esrganOnce(['-i', job.src, '-o', srTmp, '-n', 'realesrgan-x4plus',
            '-s', String(F === 1 ? 4 : F)]);
          input = srTmp;
          if (F === 1) filters.push(`scale=${job.meta.width}:${job.meta.height}:flags=lanczos+accurate_rnd`);
        } else {
          filters.push('hqdn3d=1.5:1.5:4:4');
          if (F > 1) filters.push(`scale=iw*${F}:ih*${F}:flags=lanczos+accurate_rnd`);
        }
        filters.push(LOOKS[L]);
        if (grain) filters.push('noise=alls=6:allf=t+u');
        await ffmpegOnce(['-y', '-hide_banner', '-i', input, '-vf', filters.join(','),
          '-frames:v', '1', '-q:v', '1', '-pix_fmt', 'yuvj444p', job.out]);
        const outMeta = summarize(await probe(job.out));
        job.status = 'done';
        job.outMeta = outMeta;
        persistJobs();
        json(res, 200, { meta: { width: outMeta.width, height: outMeta.height, size: outMeta.size }, name: job.outName });
      } catch (e) {
        job.status = 'error';
        json(res, 500, { error: e.message });
      } finally {
        if (srTmp) fs.rm(srTmp, { force: true }, () => {});
      }
      return;
    }

    if (req.method === 'POST' && url.pathname === '/compare') {
      // proof render: original (naively upscaled, as a display would) beside the master
      const { id, labels } = await readJson(req);
      const job = jobs.get(id);
      if (!job || job.kind !== 'video' || job.status !== 'done' || !job.out)
        return json(res, 404, { error: 'no finished master to compare' });
      const outMeta = job.outMeta || summarize(await probe(job.out));
      const aspect = outMeta.width / outMeta.height;
      let H = Math.min(outMeta.height, 2160);
      if (2 * aspect * H > 8100) H = Math.floor(8100 / (2 * aspect)); // VideoToolbox width limit
      H -= H % 2;
      const F = outMeta.fps || job.meta.fps || 30;
      const ratio = job.meta.duration > 0 ? outMeta.duration / job.meta.duration : 1;
      const retime = ratio > 1.05 ? `setpts=${ratio.toFixed(4)}*PTS,` : '';
      const lblH = Math.max(28, Math.round(H / 12));

      const tmpLbls = [];
      const writeLbl = (dataUrl, suffix) => {
        if (!/^data:image\/png;base64,/.test(dataUrl || '')) return null;
        const p = path.join(WORK, `lbl-${id}-${suffix}.png`);
        fs.writeFileSync(p, Buffer.from(dataUrl.split(',')[1], 'base64'));
        tmpLbls.push(p);
        return p;
      };
      const lo = labels && writeLbl(labels.orig, 'o');
      const le = labels && writeLbl(labels.enh, 'e');

      let fc, inputs;
      if (lo && le) {
        inputs = ['-i', job.src, '-i', job.out, '-i', lo, '-i', le];
        fc = `[0:v]${retime}fps=${F},scale=-2:${H}[L];[1:v]scale=-2:${H}[R];`
          + `[2:v]scale=-2:${lblH}[lo];[3:v]scale=-2:${lblH}[le];`
          + `[L][lo]overlay=16:16[Lo];[R][le]overlay=16:16[Ro];[Lo][Ro]hstack=inputs=2[v]`;
      } else {
        inputs = ['-i', job.src, '-i', job.out];
        fc = `[0:v]${retime}fps=${F},scale=-2:${H}[L];[1:v]scale=-2:${H}[R];[L][R]hstack=inputs=2[v]`;
      }
      const base = path.basename(job.name, path.extname(job.name));
      const cmpOut = path.join(OUTPUT, `${id}-compare.mp4`);
      try {
        await ffmpegOnce(['-y', '-hide_banner', ...inputs, '-filter_complex', fc,
          '-map', '[v]', '-map', '1:a?', '-c:v', 'hevc_videotoolbox', '-q:v', '60',
          '-allow_sw', '1', '-tag:v', 'hvc1', '-pix_fmt', 'yuv420p',
          '-c:a', 'copy', '-shortest', '-movflags', '+faststart', cmpOut]);
        const cmpMeta = summarize(await probe(cmpOut));
        job.compare = { out: cmpOut, name: `${base}-before-after.mp4` };
        persistJobs();
        json(res, 200, { name: job.compare.name,
          meta: { width: cmpMeta.width, height: cmpMeta.height, size: cmpMeta.size } });
      } catch (e) {
        json(res, 500, { error: e.message });
      } finally {
        for (const p of tmpLbls) fs.rm(p, { force: true }, () => {});
      }
      return;
    }

    if (req.method === 'POST' && url.pathname === '/frames/analyze') {
      const { id, count } = await readJson(req);
      const job = jobs.get(id);
      if (!job || job.kind !== 'video') return json(res, 404, { error: 'unknown id' });
      const n = [6, 12, 24].includes(+count) ? +count : 12;
      const picks = await analyzeFrames(job, n);
      return json(res, 200, { moments: picks.map((t, i) => ({ i, t })) });
    }

    if (req.method === 'GET' && url.pathname === '/frames/thumb') {
      const id = url.searchParams.get('id');
      const i = parseInt(url.searchParams.get('i'), 10);
      if (!jobs.has(id) || !(i >= 0)) return json(res, 404, { error: 'not found' });
      return sendFile(req, res, path.join(THUMBS, id, i + '.jpg'), i + '.jpg', false);
    }

    if (req.method === 'GET' && url.pathname === '/frames/grab') {
      const job = jobs.get(url.searchParams.get('id'));
      const t = parseFloat(url.searchParams.get('t'));
      if (!job || job.kind !== 'video' || !(t >= 0)) return json(res, 404, { error: 'not found' });
      try {
        const file = await grabFrame(job, t);
        const base = path.basename(job.name, path.extname(job.name));
        return sendFile(req, res, file, `${base}-${t.toFixed(2)}s.jpg`, true);
      } catch (e) {
        return json(res, 404, { error: e.message });
      }
    }

    if (req.method === 'POST' && url.pathname === '/frames/zip') {
      const { id, times } = await readJson(req);
      const job = jobs.get(id);
      if (!job || job.kind !== 'video' || !Array.isArray(times) || !times.length)
        return json(res, 404, { error: 'nothing selected' });
      const base = path.basename(job.name, path.extname(job.name));
      const entries = [];
      for (let i = 0; i < times.length; i++) {
        const t = parseFloat(times[i]);
        if (!(t >= 0)) continue;
        try {
          const file = await grabFrame(job, t);
          entries.push({ name: `${base}-${String(i + 1).padStart(2, '0')}-${t.toFixed(2)}s.jpg`,
            data: fs.readFileSync(file) });
        } catch {} // skip undecodable frames rather than failing the batch
      }
      if (!entries.length) return json(res, 404, { error: 'no frames could be extracted' });
      const zip = zipStore(entries);
      res.writeHead(200, { 'Content-Type': 'application/zip', 'Content-Length': zip.length,
        'Content-Disposition': `attachment; filename="${base}-frames.zip"` });
      return res.end(zip);
    }

    if (req.method === 'GET' && (url.pathname === '/download' || url.pathname === '/file')) {
      const job = jobs.get(url.searchParams.get('id'));
      if (!job) return json(res, 404, { error: 'no result' });
      if (url.searchParams.get('orig'))
        return sendFile(req, res, job.src, job.name, false);
      if (url.searchParams.get('compare')) {
        if (!job.compare) return json(res, 404, { error: 'no comparison yet' });
        return sendFile(req, res, job.compare.out, job.compare.name, url.pathname === '/download');
      }
      if (job.status !== 'done') return json(res, 404, { error: 'no result' });
      return sendFile(req, res, job.out, job.outName, url.pathname === '/download');
    }

    res.writeHead(404); res.end('not found');
  } catch (e) {
    try { json(res, 500, { error: e.message }); } catch {}
  }
});

// ── go ─────────────────────────────────────────────────────────────────────

const C = (n, s) => `\x1b[38;5;${n}m${s}\x1b[0m`;
bootRestore().then(() => {
  server.listen(PORT, '127.0.0.1', () => {
    console.log('');
    console.log('  ' + C(221, 'ENHANCE') + C(103, '  ·  local mastering console'));
    console.log('  ' + C(103, '─'.repeat(40)));
    console.log('  ' + C(116, `▸ http://localhost:${PORT}`));
    console.log('  ' + C(103, `${jobs.size} job(s) restored · neural engine ${esrganBin() ? 'ready' : 'not installed (run setup-neural.sh)'}`));
    console.log('');
  });
});
