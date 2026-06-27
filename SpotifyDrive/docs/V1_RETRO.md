# SpotifyDrive — v1 Retro & v2 Brief

v1.0 tagged + frozen at `/SpotifyDrive/v1/`. v2 = driving-first overhaul on the same engine.
Verdict from real drives: **looks great, fundamentally unfit for purpose while driving.**
*"It wasn't working at 30mph, let alone 70. I couldn't see at a glance what I needed and I
didn't even know how or if I could see what I needed: music."*

## The one-line diagnosis
v1 optimised for **impressive** (dense, rich, prettier than CarPlay). Driving needs
**operable-without-looking**. The density that impressed on a desk is the exact thing that
fails at speed. v2 inverts: **comically big, glanceable, one-tap, fixed.** Less, not more.

## What actually failed (from the driver — authoritative)
1. **Disconnects every ~20s.** [BUG — root cause found + fixed.] `fetchState` polled
   `GET /me/player` every 3s and flipped to "Nothing playing" on ANY empty/204 response;
   Spotify flaps to 204 intermittently mid-playback (backgrounded phone). Fix: tolerance — hold
   the last track through transient blanks, only disconnect after ~12s of consecutive blanks.
   Shipped to the live app. (Verify on the next drive.)
2. **Big play button is the right idea but still doesn't work** — needs to be far bigger / dead
   simple; the ring/gauge framing and surrounding clutter dilute it.
3. **Fonts look good parked, far too small driving.** Everything needs to be **comically big.**
4. **Function over form. Huge targets + huge text, ~100% width.** Taking a hand off the wheel to
   tap → the target must be enormous. Names (track / album / artist) must be **ridiculously big,
   basically full-width.**
5. **Strip non-driving features** — like button, per-row action clusters, etc. Cool, not useful
   at the wheel.
6. **THE KILLER FEATURE (biggest gap):** show recently-played **albums & playlists** like the
   native app, and **one tap to start a new album/playlist playing instantly.** That — not search
   — is the core loop. Search is fine for a long road trip, not a normal drive.
7. **Glanceability failed.** Couldn't tell at a glance what's playing or how to change it. If you
   have to *study* the screen, it's already failed.

## Keep / Scrap
- **KEEP — the engine:** PKCE auth + refresh, playback control, wall-clock progress, device
  handling, album-continue/queue logic, `playContext()` (one-tap album play already exists!),
  recently-played + playlists endpoints, themeable tokens, test harness, deploy pipeline.
- **SCRAP — the surface:** the entire layout, discover pullover, slide-out header, dense search
  rows, per-row clusters, like button, BPM, stats, album library/download (move to a non-driving
  spot if kept at all). Small corner icons. Morphing layouts.

## THE primary action (everything else is secondary)
**See the name of what's playing → pick the next thing.** That's the loop. NOT pause/play — when
the user wants quiet they turn the *volume* down, not pause. So: a giant always-visible song name,
and one-tap "play this next thing" from recent albums/playlists. Pause/play and skip exist but are
NOT the headline; don't let them dominate the screen.

## v2 v0 spec (build this)
- **ONE screen, no modes.** Top half: the **giant song name** (+ artist) of what's playing —
  comically big, ~100% width, auto-fitting. Bottom half: **"Pick next"** — your recent
  **albums + playlists** as huge art-forward tiles, **one tap = play it now** (`playContext(uri)`).
- **Controls are minimal + secondary.** Skip-next as a big zone; pause/play small (rarely used).
  No like, no queue clutter, no shuffle front-and-centre.
- **The glance test (the bar v2 must pass):** in <0.5s, eyes-forward-ish, you can (a) see what's
  playing and (b) know how to change it. If a feature doesn't survive that test, it's not on the
  driving screen.
- **Fixed, non-morphing layout.** Same control, same place, always.
- **Search:** one button, long-trips only. Not primary.
- **Later:** eyes-free / voice layer once PWA speech is solved (native wrapper likely).

## Process for v2
- **No test suites while iterating** (user: "forget test suites as we develop next version; focus
  on iterating"). Build → `node --check` for syntax → deploy → react. The engine's existing tests
  stay green as a safety net, but we don't grow them per-change during the v2 surface rebuild.

## Status
- [x] v1 frozen + tagged; v2 branch + this brief.
- [x] Disconnect bug fixed (engine) + tested + shipped to main.
- [ ] Build HOME ("Jump back in", one-tap album/playlist play).
- [ ] Build comically-big NOW PLAYING.
- [ ] Strip the non-driving surface.
