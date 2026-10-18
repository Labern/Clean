// PSN access, shared by the Mac bridge (Node) and the future native apps
// (Capacitor HTTP). Browsers can't call these endpoints directly (no CORS),
// which is why the web app goes through the bridge.
//
// Auth is the PlayStation App's own flow, as used by psn-api
// (github.com/achievements-app/psn-api): an NPSSO cookie value → OAuth code →
// access + refresh tokens. The refresh token lasts about two months, so the
// player pastes the NPSSO once.
//
// `http(url, { method, headers, body, redirect })` → { status, headers: Map-like get(), json(), text() }
// matching WHATWG fetch, so Node's fetch can be passed straight in.

const AUTH = 'https://ca.account.sony.com/api/authz/v3/oauth';
const CLIENT_ID = '09515159-7237-4370-9b40-3806e67c0891';
const BASIC = 'Basic MDk1MTUxNTktNzIzNy00MzcwLTliNDAtMzgwNmU2N2MwODkxOnVjUGprYTV0bnRCMktxc1A=';
const REDIRECT = 'com.scee.psxandroid.scecompcall://redirect';
const SCOPE = 'psn:mobile.v2.core psn:clientapp';
const API = 'https://m.np.playstation.com/api';
const LEGACY = 'https://us-prof.np.community.playstation.net/userProfile/v1/users';

export const NPSSO_URL = 'https://ca.account.sony.com/api/v1/ssocookie';

export async function exchangeNpsso(http, npsso) {
  const q = new URLSearchParams({ access_type: 'offline', client_id: CLIENT_ID, redirect_uri: REDIRECT, response_type: 'code', scope: SCOPE });
  const r = await http(`${AUTH}/authorize?${q}`, { headers: { Cookie: `npsso=${npsso.trim()}` }, redirect: 'manual' });
  const loc = r.headers.get('location') || '';
  if (!loc.includes('?code=')) throw new Error('PSN rejected that NPSSO. Sign in at playstation.com again and copy a fresh one.');
  return new URLSearchParams(loc.split('redirect/')[1] || loc.split('?')[1]).get('code');
}

async function token(http, body) {
  const r = await http(`${AUTH}/token`, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded', Authorization: BASIC }, body: new URLSearchParams(body).toString() });
  const j = await r.json();
  if (!j.access_token) throw new Error(j.error_description || 'PSN token exchange failed');
  return { access: j.access_token, refresh: j.refresh_token, expiresAt: Date.now() + (j.expires_in - 60) * 1000, refreshExpiresAt: Date.now() + (j.refresh_token_expires_in || 0) * 1000 };
}
export const tokensFromCode = (http, code) => token(http, { code, redirect_uri: REDIRECT, grant_type: 'authorization_code', token_format: 'jwt' });
export const refreshTokens = (http, refresh) => token(http, { refresh_token: refresh, grant_type: 'refresh_token', token_format: 'jwt', scope: SCOPE });

async function get(http, access, url) {
  const r = await http(url, { headers: { Authorization: `Bearer ${access}`, 'Accept-Language': 'en-GB' } });
  if (r.status >= 400) throw new Error(`PSN ${r.status} on ${url.split('?')[0].replace(API, '')}`);
  return r.json();
}

const hours = (iso) => { const m = /PT(?:(\d+)H)?(?:(\d+)M)?/.exec(iso || ''); return m ? (+(m[1] || 0)) + (+(m[2] || 0)) / 60 : null; };

// Everything the app uses from PSN in one call. Each part fails soft.
export async function summary(http, access, match = /gran\s*turismo\W*7/i) { // PSN lists it as "Gran Turismo™ 7"
  const out = { fetchedAt: Date.now(), profile: null, gt7: null, play: null, errors: [] };
  try {
    const p = await get(http, access, `${LEGACY}/me/profile2?fields=onlineId,avatarUrls,plus,trophySummary(@default)`);
    out.profile = { onlineId: p.profile?.onlineId, avatar: p.profile?.avatarUrls?.at(-1)?.avatarUrl, plus: !!p.profile?.plus, level: p.profile?.trophySummary?.level };
  } catch (e) { out.errors.push(String(e.message)); }
  try {
    const t = await get(http, access, `${API}/trophy/v1/users/me/trophyTitles?limit=800`);
    const title = (t.trophyTitles || []).filter((x) => match.test(x.trophyTitleName)).sort((a, b) => (b.npServiceName === 'trophy2') - (a.npServiceName === 'trophy2'))[0];
    if (title) {
      const id = title.npCommunicationId, svc = title.npServiceName;
      const defs = await get(http, access, `${API}/trophy/v1/npCommunicationIds/${id}/trophyGroups/all/trophies?npServiceName=${svc}`);
      const mine = await get(http, access, `${API}/trophy/v1/users/me/npCommunicationIds/${id}/trophyGroups/all/trophies?npServiceName=${svc}`);
      const earned = Object.fromEntries((mine.trophies || []).map((x) => [x.trophyId, x]));
      out.gt7 = {
        title: title.trophyTitleName, icon: title.trophyTitleIconUrl, progress: title.progress,
        earnedCounts: title.earnedTrophies, definedCounts: title.definedTrophies,
        trophies: (defs.trophies || []).map((d) => ({
          id: d.trophyId, type: d.trophyType, name: d.trophyName, detail: d.trophyDetail, icon: d.trophyIconUrl, hidden: !!d.trophyHidden,
          earned: !!earned[d.trophyId]?.earned, earnedAt: earned[d.trophyId]?.earnedDateTime || null,
          rate: earned[d.trophyId]?.trophyEarnedRate != null ? +earned[d.trophyId].trophyEarnedRate : null,
        })),
      };
    }
  } catch (e) { out.errors.push(String(e.message)); }
  try {
    const g = await get(http, access, `${API}/gamelist/v2/users/me/titles?categories=ps4_game,ps5_native_game&limit=200`);
    const t = (g.titles || []).find((x) => match.test(x.name));
    if (t) out.play = { name: t.name, hours: hours(t.playDuration), count: t.playCount, first: t.firstPlayedDateTime, last: t.lastPlayedDateTime, image: t.imageUrl };
  } catch (e) { out.errors.push(String(e.message)); }
  return out;
}
