# Focus — changelog

Semantic versioning: MAJOR.MINOR.PATCH. New features bump MINOR, fixes bump PATCH.
The version lives in `focus/VERSION`; `build.sh` stamps it into the app. Releases are tagged `focus-vX.Y.Z`.
New features are built on `focus/feat-<name>` branches, cut from `focus/main`.

## 0.1.0 — 2026-11-12 (branch focus/feat-modes)

- **Modes:** named sets of apps — tick some apps, "New Mode from Ticked Apps…", name it (say, Writing). Starting a mode
  opens its apps and parks everything else; End Session brings it all back. Rename, update from ticks, or delete.
  None are built in.
- **Named sessions:** rename any past session; hovering one shows its snapshot first; "Save as Mode…" turns a session
  into a mode.
- **A true dark menu:** opaque off-black (#1F1F21) with white text, always — matching the product page.
- Fixes: a parked app that's been deleted is skipped quietly (no "can't be found" dialog); an app that relaunches
  itself is spotted even if it comes back hidden.

## 0.0.4 — 2026-11-12

Stress-tested (see `docs/STRESS-TEST.md`). Two fixes:
- **Two Focuses launched at the same instant could leave none running.** The oldest copy now always survives,
  with a re-check after launch.
- **Apps that reopen themselves** (login items, helpers) now get their own line in the menu — "Reopened by itself:
  … — quit again" — instead of being described as a save prompt.

## 0.0.3 — 2026-11-12

- Monochrome menu, matching the product page: the Start New Session pill and the kept/locked marks are white with
  black in dark mode (near-black #171A20 with white in light mode). Colour now belongs to the icon you choose.
- Force Quit All Apps… is red — the only red in the menu, because it's the only hazard.

## 0.0.2 — 2026-11-12

- The big button now reads **Start New Session**, and underneath it says in plain English what will happen:
  "Starting a new session will save and quit 6 apps, freeing about 10.7 GB of RAM. Click again to reopen them."
  Matching sentences while a session is running, in hide mode, and when nothing would be quit.

## 0.0.1 — 2026-11-12

First versioned build.

- **Sessions:** ⌘⇧F parks every app you haven't kept and brings them all back exactly as they were. Apps quit one
  at a time, biggest first, the normal way (they save their state); nothing is ever force-quit. An app waiting on
  a save prompt doesn't hold the rest up — it's brought forward at the end.
- **The menu (⌘⇧E):** every Dock app with its memory; click to keep it open; a live caption says what a session
  will quit and free. Critical System Processes are never quit or hidden. Past sessions reopen from the menu.
- **Session pop-up:** the pill pops, hit-stops, and pulls the parked apps into the menu bar icon — and back out.
- **Snapshot:** a screenshot of where you were (only with Screen Recording already allowed; never prompts).
  Keeps the newest and one spare.
- **Tools:** Quit All Apps, Quit All & Restart Mac, Force Quit All Apps, Open Activity Monitor, Open System Settings.
- **Colour:** menu bar icon ring and dot colours (shades, 360° wheel, presets) and a Customised Logo for the app icon.
  White by default.
- **Safety:** only one Focus ever runs; the system ⌘⇥ is never touched; Chrome comes back with its tabs but no autoplay.
