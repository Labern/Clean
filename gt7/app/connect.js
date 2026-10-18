// Account connections: PlayStation Network (profile, GT7 trophies, play time)
// and Gran Turismo stats via GT-Gridstats (credits, licence, garage, DR/SR).
// Results land in the synced save, so the phone sees them without the bridge.
import * as store from './state.js';
import { isNative, nativeFetch } from './platform.js';
import { bridgeBase, probe } from './telemetry.js';
import * as psn from './psn-core.js';

const GG = 'https://gtgridstats.com/api';
const NATIVE_TOKEN = 'gt7-endgame-psn-native'; // native only: tokens stay in the device keychain-backed storage

// ── GT-Gridstats ───────────────────────────────────────
export async function fetchGT(psnId, token) {
  const path = 'racers/' + encodeURIComponent(psnId.trim());
  let r;
  try {
    r = isNative() ? await nativeFetch(`${GG}/${path}`, { headers: { Authorization: 'Bearer ' + token, Accept: 'application/json' } })
      : await fetch(`${GG}/${path}`, { headers: { Authorization: 'Bearer ' + token, Accept: 'application/json' } });
  } catch {
    if (!(await probe())) throw new Error('GT-Gridstats can\'t be reached from this page directly. Open the app from your Mac bridge and try again.');
    r = await fetch(`${bridgeBase()}/api/proxy/gridstats/${path}`, { headers: { 'X-GG-Token': token } });
  }
  if (r.status === 401 || r.status === 403) throw new Error('GT-Gridstats rejected the token.');
  if (r.status === 429) throw new Error('GT-Gridstats rate limit: wait a minute.');
  const j = await r.json();
  const d = j.drivers?.[0];
  if (!d) throw new Error(`No GT7 driver found for "${psnId}". Check the PSN ID (case-sensitive), or let GT-Gridstats index it first.`);
  store.set((s) => { s.gtLink = { psnId: psnId.trim(), token }; s.gt = { ...d, fetchedAt: Date.now() }; applyGT(s); });
  return d;
}

const DR_RANK = { E: 0, D: 1, C: 2, B: 3, A: 4, 'A+': 5 };
export function applyGT(s) {
  const d = s.gt, st = d?.stats || {};
  if (typeof st.total_credits === 'number') { s.credits = st.total_credits; s.creditsSource = 'gt7'; }
  const lic = String(st.license || '').toUpperCase();
  const tick = (...ids) => ids.forEach((id) => (s.done[id] = true));
  if (/\bS\b|SUPER|MASTER/.test(lic)) tick('lic-ib', 'lic-ia', 'lic-s');
  else if (/\bIA\b|INTERNATIONAL A/.test(lic)) tick('lic-ib', 'lic-ia');
  else if (/\bIB\b|INTERNATIONAL B/.test(lic)) tick('lic-ib');
  if ((st.total_races || 0) > 0) tick('sport-first');
  if ((DR_RANK[d.DR] ?? -1) >= 3) tick('sport-dr-b');
  if ((DR_RANK[d.DR] ?? -1) >= 4) tick('sport-dr-a');
  if (d.SR === 'S') tick('sport-sr-s');
}

// ── PSN ────────────────────────────────────────────────
// Trophy → roadmap step, by name/description keywords.
const TROPHY_STEPS = [
  [/international b/i, 'lic-ib'], [/international a/i, 'lic-ia'], [/super licen[cs]e|\bS licen[cs]e/i, 'lic-s'],
  [/all circuit experience|every circuit experience/i, 'ce-all'], [/all missions|every mission/i, 'missions'],
  [/legend car/i, 'twenty-club'],
];
export function applyPSN(s) {
  for (const t of s.psn?.gt7?.trophies || []) {
    if (!t.earned) continue;
    for (const [re, id] of TROPHY_STEPS) if (re.test(t.name + ' ' + t.detail)) s.done[id] = true;
  }
}

async function nativeSummary(npsso) {
  let tok = JSON.parse(localStorage.getItem(NATIVE_TOKEN) || 'null');
  if (npsso) { tok = await psn.tokensFromCode(nativeFetch, await psn.exchangeNpsso(nativeFetch, npsso)); }
  if (!tok) throw new Error('not connected');
  if (Date.now() > tok.expiresAt) tok = await psn.refreshTokens(nativeFetch, tok.refresh);
  localStorage.setItem(NATIVE_TOKEN, JSON.stringify(tok));
  return psn.summary(nativeFetch, tok.access);
}

export async function connectPSN(npsso) {
  let sum;
  if (isNative()) sum = await nativeSummary(npsso);
  else {
    if (!(await probe())) throw new Error('Connecting PSN needs your Mac bridge running, with this app opened from it (http://<mac>:8787). Sony\'s servers block web pages from calling them directly.');
    const r = await fetch(`${bridgeBase()}/api/psn/connect`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ npsso }) });
    const j = await r.json();
    if (!j.ok) throw new Error(j.error);
    sum = j.summary;
  }
  savePSN(sum);
  return sum;
}

export async function refreshPSN() {
  let sum;
  if (isNative()) sum = await nativeSummary();
  else {
    if (!(await probe())) throw new Error('Refreshing PSN needs the Mac bridge (laps and PSN both go through it).');
    const j = await (await fetch(`${bridgeBase()}/api/psn/summary`)).json();
    if (!j.ok) throw new Error(j.error);
    sum = j.summary;
  }
  savePSN(sum);
  return sum;
}

export async function disconnectPSN() {
  if (isNative()) localStorage.removeItem(NATIVE_TOKEN);
  else if (await probe()) await fetch(`${bridgeBase()}/api/psn/disconnect`, { method: 'POST' });
  store.set((s) => { delete s.psn; });
}

function savePSN(sum) {
  store.set((s) => { s.psn = sum; applyPSN(s); if (!s.gtLink?.psnId && sum.profile?.onlineId) s.gtLink = { ...(s.gtLink || {}), psnId: sum.profile.onlineId }; });
}

// Quietly refresh what we can when the app opens (GT stats every 6 h).
export async function autoRefresh() {
  const s = store.get();
  if (s.gtLink?.token && s.gtLink?.psnId && Date.now() - (s.gt?.fetchedAt || 0) > 6 * 3600e3) { try { await fetchGT(s.gtLink.psnId, s.gtLink.token); } catch { /* offline: keep last */ } }
}

// The easiest GT7 trophies you haven't got: highest earned-rate first.
export function nextTrophies(s, n = 3) {
  return (s.psn?.gt7?.trophies || []).filter((t) => !t.earned && !t.hidden && t.type !== 'platinum').sort((a, b) => (b.rate ?? -1) - (a.rate ?? -1)).slice(0, n);
}
export const NPSSO_URL = psn.NPSSO_URL;
