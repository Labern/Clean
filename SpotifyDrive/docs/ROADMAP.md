# SpotifyDrive — Roadmap & Proposed Features

A living list of features we want, roughly prioritised. Status legend:
`💡 idea` · `📋 planned` · `🚧 in progress` · `✅ done` · `❄️ deferred`

> Convention: small features live here as a line item. Anything large or
> architecturally risky should get its own short design doc in `docs/design/`
> (an RFC) before we build it.

---

## Core remote (the driving use case)
- ✅ Now-playing display (art, title, artist, progress)
- ✅ Big circular transport controls (play/pause/prev/next)
- ✅ Shuffle + Like
- ✅ Search → tap to play
- ✅ Device picker / playback transfer (control CarPlay from the phone)
- ✅ Three design directions built (Pure / Aurora / Dashboard); **Pure** chosen as the base

## Proposed
- ❄️ **Inline search** — results should NOT hide the transport controls; play/pause
  must stay visible & working while searching. (See `KNOWN_ISSUES.md`.)
- 💡 **Custom voice control** — the built-in CarPlay/Spotify voice control is poor.
  Explore a custom voice layer (e.g. Web Speech API in the PWA, or an iOS
  Shortcut) mapping spoken commands → Spotify actions. Hands-free is ideal for driving.
- 💡 **Preset / "scene" tiles** — big one-tap tiles for favourite playlists/stations
  so there's no searching mid-drive (e.g. "Morning Drive", "Hype", "Chill").
- 💡 **Volume control** — large slider or +/- buttons.
- 📋 **Live queue** — add songs to the Spotify play queue (`POST /me/player/queue`) and
  show the upcoming queue updating live on-screen, so you can line up tracks without
  leaving the app. (Requested 2026-06-25.)
- 💡 **Travel scrobble map** — log which song was playing at which point along a drive
  and overlay it on a Google Maps route ("what was I listening to here?"). Needs a
  song-timeline + geolocation capture; a fun stretch feature. (Requested 2026-06-25.)
- ✅ **Session uptime readout** — small "open for Xm" line at the bottom (added 2026-06-25);
  seed for richer session stats later.
- ✅ **Stats and Facts** (was "Dashboard under search") — DONE (2026-06-25): the browse
  area below search, retitled. Two live tiles — **Drive time** (session uptime ≈ how long
  this drive's been going) and **Plays this week** (current track) — above "Recently played"
  + "Your playlists" (tap a playlist to play it). Fixed the bug where it showed empty: the
  data calls needed `user-read-recently-played` + `playlist-read-private` scopes that were
  never requested; added them + a one-time auto-reconnect (SCOPE_VER) for existing users.
  Next in this section: add-to-playlist, in-app design toggle.
- 💡 **In-app album / artist view** — tapping a song title or artist currently opens the
  Spotify app (universal link). Ideally show the album/artist tracks inline in our own UI
  instead of leaving the app. Deferred. (Noted 2026-06-25.)
- ✅ **Play-count stats** — "played X times this week" (current track), DONE 2026-06-25 in
  Stats and Facts. NOTE the limit: Spotify has no per-track play-count API and recently-played
  caps at the last 50 plays, so this is a best-effort LOCAL play-log (seeded from
  recently-played timestamps, extended on each observed track change), not a true server count.
- 💡 **Add to playlist** — a button to add the current or a searched track to a chosen
  playlist (`POST /playlists/{id}/tracks`). (Requested 2026-06-25.)
- 🚧 **BMW Mode** — optional theme toggle: BMW blue/white/black palette + the play button
  rebuilt as the BMW roundel. In progress 2026-06-25.
- 💡 **Jam automation** — best-effort flow to start/share a Spotify Jam (limited by
  the lack of a Jam API — see `KNOWN_ISSUES.md`).
- 💡 **Bigger album art / glance mode** — a stripped, maximally-legible mode for at-speed glances.
- 📋 **In-app design toggle** — a switch near the top to flip between the three designs
  (Pure / Aurora / Dashboard) live, instead of redeploying. Planned right after the
  Dashboard review.
- ❄️ **Theme options** — Light, Dark, and a "Zesty" (vivid/high-energy) theme, switchable
  by the user. Deferred.

## Quality / infrastructure
- 📋 **Thorough automated test suite** (static + behavioural) so changes can't silently break the app.
- 💡 One-tap way to switch which design variant is live (overlaps with the in-app design toggle above).
