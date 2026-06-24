# SpotifyDrive — Notes (Architecture, Ops & Decisions)

Miscellaneous reference material that doesn't belong in the roadmap or issue list.

## What this is
A single-file web app (`SpotifyDrive/index.html`) that acts as a big-button
Spotify **remote for driving**. It controls playback on whatever device Spotify
is running on (e.g. CarPlay) via the Spotify Web API. No build step, no
dependencies — inline `<style>` and `<script>`.

## Architecture
- **Auth:** Spotify OAuth **PKCE** flow (no client secret; safe for a static page).
  Tokens in `localStorage`; auto-refresh on expiry.
- **Playback:** the app is a *remote* — it sends commands (play/pause/next/transfer)
  to an active Spotify device and polls `/me/player` every few seconds for state.
- **No backend:** everything runs client-side against `api.spotify.com`.

## Live deployment
- **Hosting:** GitHub Pages, served from the **`gh-pages`** branch.
- **URL:** https://labern.github.io/Clean/SpotifyDrive/index.html
- **Deploy a design variant:** copy the chosen variant over the served file and push:
  ```
  cp SpotifyDrive/variants/<name>/index.html  <gh-pages>/SpotifyDrive/index.html
  # commit + push gh-pages
  ```
- `.nojekyll` at the gh-pages root disables Jekyll processing.

## Configuration gotchas
- **`REDIRECT_URI` is hardcoded** and must match a Redirect URI registered in the
  Spotify Developer Dashboard **exactly** (including `/index.html`). A mismatch is
  the classic "redirect URI not matching configuration" error (esp. on iOS).
- **`CLIENT_ID`** is set at the top of the `<script>` block.

## Spotify Web API quirks worth remembering
- `/search` `limit` **max is 10** (not 50). Paginate with `offset` for more.
- Method matters: `play`/`pause`/`shuffle`/transfer use **PUT**; `next`/`previous` use **POST**.
- `/me/tracks/contains?ids=` returns a **JSON array of booleans** (read index `[0]`).
- A `device_id` must be targeted (or an active device must exist) or commands no-op.

## Design variants
Three full designs live under `SpotifyDrive/variants/`:
- **pure** — faithful, premium Spotify look (current base choice).
- **aurora** — album-art colours bleed into a drifting gradient; frosted glass.
- **dashboard** — instrument-cluster look; circular progress ring around play.
Planned: fold these into a single in-app toggle rather than separate files.

## Docs in this folder
- `ROADMAP.md` — proposed/planned features.
- `KNOWN_ISSUES.md` — bugs & limitations.
- `NOTES.md` — this file (architecture, ops, decisions).
- For any large feature, add a short RFC/design doc under `docs/design/` before building.
