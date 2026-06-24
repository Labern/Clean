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
