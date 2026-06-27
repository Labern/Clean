# SpotifyDrive — v1 Retro & v2 Direction

Status: v1.0 tagged + frozen at `/SpotifyDrive/v1/`. v2 is a driving-first overhaul.
Verdict from the first real drive (2026-06-26): **looks great, well thought-out, fundamentally
unfit for purpose while driving.** This doc captures *why*, what to keep, and the v2 north-star.

---

## 0. The central flaw — the thesis was the bug
v1's whole differentiator was **"more info, denser, richer than CarPlay's Spotify."** That's a
great desk demo and a *liability at 70mph*. Driving wants the **opposite** of density: the fewer
things on screen, the fewer glances, the better. The very things that impressed (information
density, deep navigation, the discover pullover) are what make it unusable while moving.

**v2 inverts the thesis:** glanceable, huge, eyes-free-first. Less, not more. The win over
CarPlay is no longer "richer" — it's "you barely have to look."

## 1. Concrete failure-modes (designer's view — what I can infer from the build)
1. **Reading required everywhere.** Track/album/artist text, multi-line search rows, the discover
   pullover (a wall of tiles + labels), album track lists. Reading = eyes off road.
2. **Small, precise targets.** Corner icons (i / discover / album), the slide-out header, the
   stacked per-row Artist/Album/Queue actions, search rows. Driving = imprecise thumb + peripheral
   vision only; these demand aimed taps.
3. **Too many steps per task.** "Find/queue a song" = open panel → read → scroll → tap → maybe open
   album → tap track. Every step is a glance. Core tasks must be ~1 action, 0–1 glances.
4. **Hidden / morphing affordances.** Header hidden behind an icon; layout changes between
   player / search / album / discover / header-out (art appears & disappears, controls shift). A
   layout that moves forces you to look just to re-orient.
5. **No working eyes-free path.** Voice/dictation was the intended hands-free route, but Web Speech
   breaks in installed iOS PWAs — so there is no reliable eyes-free control. For driving, voice/
   eyes-free isn't a feature, it's THE interface. This is the biggest single gap.
6. **State ambiguity.** Several modes; at a glance you can't always tell where you are or what a tap
   will do.
7. **Confirmation glances.** Any doubt that a tap registered makes you look again.

## 2. What I CANNOT know — needs your lived input (the real ground truth)
I built it; I didn't drive it. These reframe everything below:
- **The task:** what were you actually trying to do when it failed — skip? pause? change the vibe?
  find a specific song? discover something new? (Rank them by how often, in the car.)
- **Failure type:** mostly **precision** (couldn't hit controls) or **cognition** (too much to
  parse) or both?
- **Worst moment:** the single screen/action that felt most dangerous or annoying.
- **Look-budget:** how much do you want to look at the screen at all — vs. operate it blind / by
  voice / by feel?
- **Physical setup:** phone mounted? where, and how big is it in your field of view?

## 3. Keep / Scrap / Rebuild (initial — will refine after your input)
- **KEEP — the engine (solid, hard-won):** Spotify PKCE auth + token refresh, playback control,
  wall-clock progress interpolation, device handling, the album-continue/queue logic, like/library
  writes, the scope contract, themeable design tokens, the zero-dep test harness, the deploy
  pipeline. None of this is the problem.
- **SCRAP / RETHINK — the surface:** the visual layout, the discover pullover (reading-heavy), the
  slide-out header, dense search rows, multi-step navigation, small corner icons.
- **v2 = a new skin + a new interaction model on the same engine.** We are not rewriting the Spotify
  plumbing; we're replacing how a human operates it while driving.

## 4. v2 north-star (driving-first principles)
- **Eyes-free-first.** Voice and/or a few enormous fixed zones you can hit blind.
- **Glanceable.** At most one word/number changes; no reading to operate.
- **1 action per core task.** The 3 core tasks (play/pause, skip, "more / next vibe") reachable
  without looking.
- **Fixed, non-morphing layout.** The same control is always in the same place, every mode.
- **Big, edge-anchored hit zones.** Thumb-reachable, findable in peripheral vision.
- **Solve eyes-free input explicitly.** If Web Speech is dead in PWAs, name the real path: native
  wrapper for proper speech? big preset buttons? a steering/hardware trigger? Don't hand-wave it.

## 5. Open question for v2's shape (decide before building)
Two broad directions (not mutually exclusive):
- **A. Eyes-free / voice + gesture** — minimal screen; you talk or swipe big zones; screen is mostly
  feedback. Highest ceiling, depends on solving voice.
- **B. Giant-zone touch** — 2–4 full-screen-quadrant buttons; no text to read; everything is one
  big blind-tappable target. Lower ceiling, but works today with zero new tech.

Likely v2 = **B as the floor, A layered on top.** Confirm after the Section 2 answers.
