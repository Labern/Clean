# Focus — changelog

Semantic versioning: MAJOR.MINOR.PATCH. New features bump MINOR, fixes bump PATCH.
The version lives in `focus/VERSION`; `build.sh` stamps it into the app. Releases are tagged `focus-vX.Y.Z`.
New features are built on `focus/feat-<name>` branches, cut from `focus/main`.

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
