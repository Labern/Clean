// Per-corner video moments. YouTube's own Data API (with the player's free key,
// called from their browser) returns each video's description; creators list
// chapters there as timestamps. We match chapter titles to corners by name and
// turn number, so a corner can link straight to the second it's explained.
import * as store from './state.js';

const CACHE = 'gt7-yt-chapters-v1';
const load = () => { try { return JSON.parse(localStorage.getItem(CACHE) || '{}'); } catch { return {}; } };
const save = (c) => { try { localStorage.setItem(CACHE, JSON.stringify(c)); } catch { /* full or private */ } };

export const hasKey = () => !!store.get().ytKey;
export const cached = () => load();

// "1:23 Turn 1 La Source", "(12:05) - Eau Rouge", "0:00 Intro"
export function parseChapters(desc) {
  const out = [];
  for (const line of String(desc || '').split('\n')) {
    const m = line.match(/^\s*[[(]?((?:\d{1,2}:)?\d{1,2}:\d{2})[\])]?\s*[-–—:|]?\s*(.+?)\s*$/);
    if (!m) continue;
    const sec = m[1].split(':').reduce((a, b) => a * 60 + +b, 0);
    out.push([sec, m[2]]);
  }
  return out.length >= 2 ? out : [];
}

export async function fetchChapters(ids) {
  const key = store.get().ytKey; if (!key) return load();
  const cache = load(), todo = ids.filter((id) => !cache[id]);
  for (let i = 0; i < todo.length; i += 50) {
    const batch = todo.slice(i, i + 50);
    const r = await fetch(`https://www.googleapis.com/youtube/v3/videos?part=snippet&id=${batch.join(',')}&key=${encodeURIComponent(key)}`);
    const j = await r.json();
    if (j.error) throw new Error(j.error.message || 'YouTube API error');
    for (const it of j.items || []) cache[it.id] = { ch: parseChapters(it.snippet.description), desc: String(it.snippet.description || '').split('\n').find((l) => l.trim().length > 30)?.slice(0, 220) || '' };
    for (const id of batch) if (!cache[id]) cache[id] = { ch: [], desc: '' };
  }
  save(cache);
  return cache;
}

const STOP = new Set(['turn', 'turns', 'corner', 'corners', 'curve', 'the', 'and', 'complex', 'section']);
const norm = (s) => String(s).toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
function keys(c) {
  const words = norm(c.name).split(/[^a-z0-9]+/).filter((w) => w.length >= 4 && !STOP.has(w));
  const nums = (String(c.n).match(/\d+/g) || []).map(Number);
  return { words, nums };
}
// Chapters across the track's videos that cover this corner: [{ id, sec, title }]
export function cornerMoments(corner, videos, cache) {
  const { words, nums } = keys(corner), out = [];
  for (const v of videos) {
    const ch = cache[v.id]?.ch || [];
    for (const [sec, title] of ch) {
      const t = norm(title);
      const byName = words.some((w) => t.includes(w));
      const byNum = nums.some((n) => new RegExp(`\\b(t|turn|corner|c)\\s?${n}\\b`).test(t));
      if (byName || byNum) { out.push({ id: v.id, sec, title, video: v }); break; }
    }
  }
  return out;
}
