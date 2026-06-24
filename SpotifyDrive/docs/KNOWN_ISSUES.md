# SpotifyDrive — Known Issues

Tracked bugs and limitations. Status: `🔴 open` · `🟡 monitoring` · `✅ fixed`.
Fixed items stay here briefly for context, then move to the changelog/history.

| # | Status | Severity | Issue | Notes / fix |
|---|--------|----------|-------|-------------|
| 1 | 🔴 open | medium | **Jam button doesn't start a Jam** | It only deep-links to `spotify://` (opens the app). Spotify exposes **no public API** to create/join a Jam, so a web remote can't start one programmatically. Best achievable: deep-link + pre-staged share link. Deferred by user. |
| 2 | 🔴 open | medium | **Search overlay hides the transport controls** | Search opens a full-screen `#results-overlay` that covers now-playing. Want **inline** search so play/pause stay visible & working. On the roadmap. |
| 3 | 🟡 monitoring | low | **GitHub Pages build intermittently reports "errored"** | The legacy Jekyll build status often shows `errored` even though the CDN serves the correct latest content (HTTP 200, right commit). `.nojekyll` is present. Hasn't blocked serving so far; revisit if a deploy ever fails to update. |
| 4 | ✅ fixed | high | **Search failed with "Invalid limit"** | Code sent `/search?...&limit=25`; Spotify caps `/search` `limit` at **10**. Fixed to `limit=10` across the live app and all three variants (2026-06-24). Never raise above 10. |

## How we triage
- **Severity**: critical = app unusable / data loss; high = a core feature broken;
  medium = a feature degraded or a workaround exists; low = cosmetic / rare.
- A pending **automated test suite** (see `ROADMAP.md`) should add a regression test
  for every `✅ fixed` row so it can't silently come back (e.g. assert search `limit <= 10`).
