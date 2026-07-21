#!/usr/bin/env node
// ENHANCE — local 4K video amplifier.
// Zero dependencies: Node stdlib + native ffmpeg/ffprobe.
// Everything stays on this Mac; the browser is just the control surface.

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawn, execFile } = require('child_process');

const PORT = 2160; // the vertical resolution of 4K, naturally
const ROOT = __dirname;
const WORK = path.join(ROOT, 'work');
const UPLOADS = path.join(WORK, 'uploads');
const OUTPUT = path.join(WORK, 'output');
fs.mkdirSync(UPLOADS, { recursive: true });
fs.mkdirSync(OUTPUT, { recursive: true });

const jobs = new Map(); // id → { src, name, meta, status, opts, out, outName, proc, prog, listeners }

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

// ── the enhancement pipeline ───────────────────────────────────────────────
// denoise (optional) → frame-rate (MCI or resample, at source res — cheaper)
// → lanczos upscale → subtle unsharp → HEVC (hardware or x265) + faststart

const RES_LABEL = { 1080: '1080p', 1440: '1440p', 2160: '4K', 4320: '8K' };

function buildArgs(job) {
  const { src, out, meta, opts } = job;
  const H = parseInt(opts.res, 10) || 2160;
  const filters = [];

  if (opts.denoise) filters.push('hqdn3d=2:1.5:3:3');

  const srcFps = meta.fps || 30;
  const targetFps = opts.fps === 'source' ? null : parseInt(opts.fps, 10);
  if (targetFps && Math.abs(targetFps - srcFps) > 0.01) {
    if (opts.mode === 'smooth' && targetFps > srcFps) {
      // motion-compensated interpolation — slow, beautiful
      filters.push(`minterpolate=fps=${targetFps}:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1`);
    } else {
      filters.push(`fps=${targetFps}`); // resample (or decimate downward)
    }
  }

  // long edge → target: landscape gets height H, portrait gets width H
  filters.push(`scale='if(gt(a,1),-2,${H})':'if(gt(a,1),${H},-2)':flags=lanczos+accurate_rnd`);
  filters.push('unsharp=5:5:0.6:5:5:0.0'); // restore perceived detail, luma only

  const args = ['-y', '-hide_banner', '-nostats', '-progress', 'pipe:1',
    '-i', src, '-vf', filters.join(','), '-map', '0:v:0', '-map', '0:a:0?'];

  if (opts.enc === 'max') {
    args.push('-c:v', 'libx265', '-preset', 'medium', '-crf', '16',
      '-tag:v', 'hvc1', '-pix_fmt', 'yuv420p');
  } else {
    // Apple media engine — 4K in minutes, not hours
    args.push('-c:v', 'hevc_videotoolbox', '-q:v', '65', '-allow_sw', '1',
      '-tag:v', 'hvc1', '-pix_fmt', 'yuv420p');
  }

  const copyOk = ['aac', 'mp3', 'ac3', 'eac3'].includes(meta.audio);
  if (meta.audio) args.push('-c:a', copyOk ? 'copy' : 'aac');
  if (meta.audio && !copyOk) args.push('-b:a', '256k');

  args.push('-movflags', '+faststart', out);
  return args;
}

function broadcast(job, event) {
  const line = `data: ${JSON.stringify(event)}\n\n`;
  for (const res of job.listeners) res.write(line);
}

function runJob(job) {
  const args = buildArgs(job);
  job.status = 'running';
  job.prog = { pct: 0, fps: 0, speed: 0, frame: 0 };
  const proc = spawn('ffmpeg', args);
  job.proc = proc;
  let stderrTail = '';
  proc.stderr.on('data', c => { stderrTail = (stderrTail + c).slice(-4000); });

  let buf = '';
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
    if (us > 0 && job.meta.duration > 0) {
      job.prog.pct = Math.min(99.9, (us / 1e6 / job.meta.duration) * 100);
    }
    if (kv.fps) job.prog.fps = parseFloat(kv.fps) || 0;
    if (kv.frame) job.prog.frame = parseInt(kv.frame, 10) || 0;
    if (kv.speed) job.prog.speed = parseFloat(kv.speed) || 0;
    broadcast(job, { type: 'progress', ...job.prog });
  });

  proc.on('close', async code => {
    job.proc = null;
    if (job.status === 'cancelled') {
      fs.rm(job.out, { force: true }, () => {});
      broadcast(job, { type: 'cancelled' });
      return;
    }
    if (code !== 0) {
      job.status = 'error';
      job.error = stderrTail.split('\n').filter(Boolean).slice(-3).join(' · ');
      broadcast(job, { type: 'error', message: job.error });
      return;
    }
    try {
      const outMeta = summarize(await probe(job.out));
      job.status = 'done';
      job.outMeta = outMeta;
      job.prog.pct = 100;
      broadcast(job, { type: 'done', meta: outMeta, name: job.outName });
    } catch (e) {
      job.status = 'error';
      job.error = 'output probe failed: ' + e.message;
      broadcast(job, { type: 'error', message: job.error });
    }
  });
}

// ── the photo pipeline ─────────────────────────────────────────────────────
// decode (sips for HEIC) → light denoise → lanczos upscale → look:
//   natural — gentle CAS sharpen + slight vibrance/contrast
//   vivid   — stronger colour + contrast lift
//   crisp   — detail only, no colour push

const LOOKS = {
  natural: 'cas=0.4,vibrance=intensity=0.10,eq=contrast=1.03:saturation=1.04',
  vivid:   'cas=0.45,vibrance=intensity=0.25,eq=contrast=1.07:saturation=1.12:brightness=0.01',
  crisp:   'cas=0.6,unsharp=5:5:0.5:5:5:0.0,eq=contrast=1.04',
};

function sipsToPng(src, dst) {
  return new Promise((resolve, reject) => {
    execFile('sips', ['-s', 'format', 'png', src, '--out', dst], err =>
      err ? reject(new Error('HEIC decode failed')) : resolve());
  });
}

function ffmpegOnce(args) {
  return new Promise((resolve, reject) => {
    execFile('ffmpeg', args, { maxBuffer: 32 * 1024 * 1024 }, (err, _out, stderr) =>
      err ? reject(new Error(String(stderr).split('\n').filter(Boolean).slice(-2).join(' · '))) : resolve());
  });
}

// ── file streaming (Range-aware, for the inline preview) ───────────────────

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

// ── routes ─────────────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  try {
    if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/index.html')) {
      const html = fs.readFileSync(path.join(ROOT, 'public', 'index.html'));
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      return res.end(html);
    }

    if (req.method === 'POST' && url.pathname === '/upload') {
      // raw streamed body — no size limit, no buffering
      const rawName = decodeURIComponent(req.headers['x-filename'] || 'video.mp4');
      const name = path.basename(rawName).replace(/[^\w.\- ()\[\]]/g, '_');
      const ext = path.extname(name).toLowerCase();
      if (!['.mp4', '.mov', '.m4v'].includes(ext)) return json(res, 415, { error: 'mp4 / mov only' });
      const id = crypto.randomBytes(6).toString('hex');
      const dst = path.join(UPLOADS, id + ext);
      const ws = fs.createWriteStream(dst);
      req.pipe(ws);
      req.on('error', () => { ws.destroy(); fs.rm(dst, { force: true }, () => {}); });
      ws.on('finish', async () => {
        try {
          const meta = summarize(await probe(dst));
          if (!meta) throw new Error('no video stream');
          jobs.set(id, { id, src: dst, name, meta, status: 'uploaded', listeners: new Set() });
          json(res, 200, { id, name, meta });
        } catch (e) {
          fs.rm(dst, { force: true }, () => {});
          json(res, 415, { error: 'not a readable video: ' + e.message });
        }
      });
      return;
    }

    if (req.method === 'POST' && url.pathname === '/upload-image') {
      const rawName = decodeURIComponent(req.headers['x-filename'] || 'photo.jpg');
      const name = path.basename(rawName).replace(/[^\w.\- ()\[\]]/g, '_');
      const ext = path.extname(name).toLowerCase();
      if (!['.jpg', '.jpeg', '.png', '.heic', '.webp', '.tiff', '.tif'].includes(ext))
        return json(res, 415, { error: 'jpg / png / heic / webp / tiff only' });
      const id = crypto.randomBytes(6).toString('hex');
      const dst = path.join(UPLOADS, id + ext);
      const ws = fs.createWriteStream(dst);
      req.pipe(ws);
      req.on('error', () => { ws.destroy(); fs.rm(dst, { force: true }, () => {}); });
      ws.on('finish', async () => {
        try {
          let src = dst;
          if (ext === '.heic') { // ffmpeg can't read HEIC; macOS can
            src = path.join(UPLOADS, id + '-decoded.png');
            await sipsToPng(dst, src);
          }
          const meta = summarize(await probe(src));
          if (!meta) throw new Error('no image data');
          jobs.set(id, { id, kind: 'image', src, name, meta, status: 'uploaded', listeners: new Set() });
          json(res, 200, { id, name, meta: { width: meta.width, height: meta.height, size: meta.size } });
        } catch (e) {
          fs.rm(dst, { force: true }, () => {});
          json(res, 415, { error: 'not a readable photo: ' + e.message });
        }
      });
      return;
    }

    if (req.method === 'POST' && url.pathname === '/enhance-image') {
      const { id, scale, look } = await readJson(req);
      const job = jobs.get(id);
      if (!job || job.kind !== 'image') return json(res, 404, { error: 'unknown id' });
      const F = ['1', '2', '4'].includes(String(scale)) ? parseInt(scale, 10) : 2;
      const L = LOOKS[look] ? look : 'natural';
      const filters = ['hqdn3d=1.5:1.5:4:4'];
      if (F > 1) filters.push(`scale=iw*${F}:ih*${F}:flags=lanczos+accurate_rnd`);
      filters.push(LOOKS[L]);
      const base = path.basename(job.name, path.extname(job.name));
      job.outName = `${base}-${F}x-${L}.jpg`;
      job.out = path.join(OUTPUT, `${id}-${F}x-${L}.jpg`);
      try {
        await ffmpegOnce(['-y', '-hide_banner', '-i', job.src, '-vf', filters.join(','),
          '-frames:v', '1', '-q:v', '1', '-pix_fmt', 'yuvj444p', job.out]);
        const outMeta = summarize(await probe(job.out));
        job.status = 'done';
        job.outMeta = outMeta;
        json(res, 200, { meta: { width: outMeta.width, height: outMeta.height, size: outMeta.size }, name: job.outName });
      } catch (e) {
        job.status = 'error';
        json(res, 500, { error: e.message });
      }
      return;
    }

    if (req.method === 'POST' && url.pathname === '/enhance') {
      const { id, res: r, fps, mode, enc, denoise } = await readJson(req);
      const job = jobs.get(id);
      if (!job) return json(res, 404, { error: 'unknown id' });
      if (job.status === 'running') return json(res, 409, { error: 'already running' });
      job.opts = {
        res: ['1080', '1440', '2160', '4320'].includes(String(r)) ? String(r) : '2160',
        fps: ['source', '24', '30', '60', '120'].includes(String(fps)) ? String(fps) : 'source',
        mode: mode === 'fast' ? 'fast' : 'smooth',
        enc: enc === 'max' ? 'max' : 'turbo',
        denoise: !!denoise,
      };
      const base = path.basename(job.name, path.extname(job.name));
      const tag = RES_LABEL[job.opts.res] + (job.opts.fps === 'source' ? '' : job.opts.fps);
      job.outName = `${base}-${tag}.mp4`;
      job.out = path.join(OUTPUT, `${id}-${tag}.mp4`);
      runJob(job);
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

    if (req.method === 'GET' && (url.pathname === '/download' || url.pathname === '/file')) {
      const job = jobs.get(url.searchParams.get('id'));
      if (!job) return json(res, 404, { error: 'no result' });
      if (url.searchParams.get('orig')) // hold-to-compare: the decoded source
        return sendFile(req, res, job.src, job.name, false);
      if (job.status !== 'done') return json(res, 404, { error: 'no result' });
      return sendFile(req, res, job.out, job.outName, url.pathname === '/download');
    }

    res.writeHead(404); res.end('not found');
  } catch (e) {
    json(res, 500, { error: e.message });
  }
});

// ── go ─────────────────────────────────────────────────────────────────────

const C = (n, s) => `\x1b[38;5;${n}m${s}\x1b[0m`;
server.listen(PORT, '127.0.0.1', () => {
  console.log('');
  console.log('  ' + C(141, 'E N H A N C E') + C(103, '  ·  4K video amplifier'));
  console.log('  ' + C(103, '─'.repeat(40)));
  console.log('  ' + C(116, `▸ http://localhost:${PORT}`));
  console.log('  ' + C(103, 'everything stays on this mac · ctrl-c to stop'));
  console.log('');
});
