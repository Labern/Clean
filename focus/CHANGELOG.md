# Focus — changelog

Semantic versioning: MAJOR.MINOR.PATCH. New features bump MINOR, fixes bump PATCH.
The version lives in `focus/VERSION`; `build.sh` stamps it into the app. Releases are tagged `focus-vX.Y.Z`.
New features are built on `focus/feat-<name>` branches, cut from `focus/main`.

## 0.18.10 — 2026-11-14
- Right-clicking a mode: the menu closes and the mode's edit menu opens at the pointer (the first attempt opened nothing). Logged, so a click that doesn't arrive can be traced.

## 0.18.9 — 2026-11-14
- The ★★★★★ × PARADOX™ mark is small, plain and at the bottom right.

## 0.18.8 — 2026-11-14
- The menu ends with the maker's mark: ★★★★★ × PARADOX™.

## 0.18.7 — 2026-11-14
- Clicking "Usage" cycles the order of the app list: as listed, most memory first, most used first (the apps you've kept open in the most sessions), then back.

## 0.18.6 — 2026-11-14
- "Focus" at the top left is large (21 pt bold).
- "Apps in Session" sits to the left of "Usage", on one line over the app list.
- The Start/End button is taller, with more padding above and below its text.
- Tools: "Analyse performance" comes first; the quit section is headed "Quit Unresponsive Apps".

## 0.18.5 — 2026-11-14
- Critical System Processes rows can't be clicked and don't react to hover: the lock stays, and changes go through "Add or remove…".
- "Create New Mode" sits under your modes (it's first when you have none). Edit Modes starts with "Add New Mode".

## 0.18.4 — 2026-11-14
- "Focus" is back at the top left, on the same row as Quit.
- **Minimal headings:** "In Session", "Critical System Processes" and "Modes". Each heading's description shows when you hover over it. The "Keep open this session…" line is gone.
- A little more space between the Start/End button and its description.

## 0.18.3 — 2026-11-14
- **Taken back out:** the "Focus — mode (apps, since…)" line at the top; the "App" title and the mark over the ticks (only "Usage" stays); the larger custom headings (macOS's own grey headings are back); the taller button.
- **Quit** is the first row of the menu, at the top right.
- **Mode names** start in one fixed place, clear of three icons, however many apps a mode has.
- "Temporarily Closed / End Session to Reopen" is now "Apps Outside Session". "In this session —" is gone from the app list's heading.
- The lock on Critical System Processes stays a lock on hover. + and × show only where a click adds to or removes from a session or mode.
- **Settings:** Reopen windows and Open at login show on or off with their icon, so they line up with the icons above.
- Removed two marks that could push a menu's icons to the right.

## 0.18.2 — 2026-11-14
- Every mode's name starts in the same place, however many apps the mode has.

## 0.18.1 — 2026-11-14
- **Headings:** every grey heading in the menu and its submenus is drawn by Focus at one size (13 pt), set in one place with its weight and colour.
- **Tools:** "Quit apps to free RAM" heads the three Quit items; "Analyse performance" heads Activity Monitor and System Settings.
- **Settings ▸ Behaviour** (under Appearance and Shortcuts) holds App Open/Close Speed, Hide Instead of Quit and snapshots.
- **Modes:**
  - "Create New Mode" comes first. It needs no name: each new mode takes the next number (⌘1 … ⌘9, ⌘0) and is called "Mode 3" until named.
  - Right-click or ⌃-click a mode to edit it.
  - A mode's shortcut sits in the same column as the apps' memory.
- **Column titles over the app list:** App, Usage, and the Focus mark over the ticks.
- **Menu bar name:** Settings ▸ Appearance ▸ Menu Bar Name offers "AI", "AI session", "AI (in session)" or icon only.
- The banner naming the mode at the top of the menu is removed. The button reads "End Session" again, with more space above its description.

## 0.18.0 — 2026-11-13
- **Switching between modes has its own animation.**
  - The apps leaving fan out on the left and are pulled into the menu bar icon.
  - The apps arriving fly out of the icon on the right and drop into the pill.
  - The pill stays until they land.
- **The mode's name writes itself in,** letter by letter from left to right, with a glowing spark at each letter. When a session ends it deletes itself from the right.
- The ordinary start and end keep their exact timing, Normal included.
- Developer flag `--render-pill FILE start|switch|end` draws the show off-screen as a filmstrip.

## 0.17.0 — 2026-11-13
- **Modes start with one click:**
  - Each mode is an item under the Modes heading, with its shortcut on the right.
  - Click it to start it; during a session it moves the session to that mode.
  - The live mode is ticked, and clicking it ends the session.
- Renaming, apps, shortcut and delete are in the Edit Modes submenu.

## 0.16.2 — 2026-11-13
- The menu bar always names the session: its own name, else the mode it matches, else "Focus".
  - A mode matches when the session kept at least half of that mode's apps.
  - The menu's first line uses the same name.
- "Switch to" is removed from the mode menu: a mode offers Start, or End when it's the live one.

## 0.16.1 — 2026-11-13
- During a session a mode's menu offers "Switch to <mode>" instead of a greyed-out Start, or "End <mode>" if it's the live one, the same as its key.
- The menu's first line names the mode: "Focus — AI (4 apps, since 21:40)".
- Mode keys write a line to the system log when pressed, so a key that doesn't arrive can be traced.

## 0.16.0 — 2026-11-13
- **Suggested Modes:** three at most, built from the apps you actually use. For each kind, Focus picks what's running or was used most recently, from macOS's last-used dates. The list no longer has a grey line under each suggestion.
- **New Mode is a builder:**
  - Name it at the top; press Return to save.
  - Click apps in or out: what's open, plus apps your sessions kept.
  - Add App… for anything else.
  - It replaces "New Mode from Ticked Apps".

## 0.15.0 — 2026-11-13
- Naming happens in the menu itself, with no popups. Type and press Return for:
  - a new mode
  - renaming a mode, as the first line of its submenu
  - renaming a past session
  - saving a past session as a mode
- During a session the menu bar shows the icon, then the mode's or session's name. Turn it off in Settings ▸ Appearance ▸ Show Session Name Next to Icon.

## 0.14.1 — 2026-11-13
- The Modes heading reads "Modes — pre-defined app combinations".

## 0.14.0 — 2026-11-13
- **Modes, built out.**
  - **Suggested Modes:** Game Design, Web Only, Writing, Coding, Design, Calls. Each is built only from apps this Mac has; Web Only uses your default browser. Click one to add it, then make it your own.
  - **A mode's menu lists its apps ticked and your open apps unticked.** Click to put one in or take it out, or use Add App… for anything installed.
  - **Mode shortcuts:** give any mode a number in its Shortcut menu. Nothing is set until you choose.
    - Pressing it starts the mode, pressing it again ends the session, and pressing it in another session switches straight to it.
    - The modifier is in Settings ▸ Shortcuts. ⌘ is the default, and the menu notes that browsers use ⌘1–9 for tabs.
    - A mode's key shows at the right of its row.
- **"Parked" is now "Temporarily Closed / End Session to Reopen".**
- **App rows on hover:**
  - + when a click will add the app, × when it will remove it.
  - After 2.5 seconds, a popup says exactly what a click does ("Click to remove Chrome from your session.").

## 0.13.0 — 2026-11-13
- The menu's first line says where you are: "Focus" out of a session, "Focus — in session (3 apps, since 21:48)"
  in one.

## 0.12.0 — 2026-11-13
- Settings ▸ Appearance ▸ Icon Colour ▸ **Evangelion**: UNIT 01, Asuka, Rei, Shinji, Misato, Kaworu and Pen Pen,
  each a ring and dot pair in the show's colours. The original presets stay.
- **Your Schemes**: "Save Current Colours as Scheme…" names and keeps your ring and dot colours; hold ⌥ to delete one.

## 0.11.1 — 2026-11-13
- Settings ▸ Switching is now **App Open/Close Speed**: "Safety first (closes all apps carefully, slower)" or
  "Speed first (opens/closes apps immediately)".

## 0.11.0 — 2026-11-13
- Settings ▸ Appearance ▸ Icon: hover over a design and it plays, from out of session to in session with the hit
  stop and back, on a loop, so you see what it will do in the menu bar before choosing it.

## 0.10.1 — 2026-11-13
- Only the icons you picked in the Icon Lab stay: Full stop, Aperture, Reticle, Zoom, Ichi (三 → 一), Ensō,
  Hinomaru, Tomoe, Stone, Windows, Spotlight, Counter and Door. The 14 you didn't pick are removed. 20 designs in all.

## 0.10.0 — 2026-11-13
- 27 new menu bar icons from the Icon Lab, in Settings ▸ Appearance: every idea on the page, now 34 designs.
  - Narrowing in session: Pillar, Ghost, Fuse, Point, Wide, Keystone, Tally.
  - Minimal: Full stop, Aperture, Selection, Reticle, Zoom.
  - Japanese: Ichi (三 → 一), Ensō, Hinomaru, Shōji, Tomoe, Stone, Hanko.
  - Maximal: Orbit, Stars, Gather, Windows, Spotlight.
  - Counter (shows how many apps are open), Hourglass, Door.
- Each one follows your icon colours and animates into its in-session state.
- The icon picker shows five per row so all 34 fit.

## 0.9.0 — 2026-11-13 (branch focus/feat-live-session)

- **Edit a session while it runs.** Click an open app to take it out now (saved and quit, or hidden if it's hide-only;
  End Session brings it back). Click a parked app under **Parked** to bring it back now. No ending, no procedure.
- **Never stuck behind a save prompt.** An app waiting for you to save gets its own line with **Show Its Save Prompt**,
  **Keep It in the Session** and **Force Quit — Unsaved Changes Lost…** (asks first, in red). Scenario 31.

## 0.8.0 — 2026-11-13 (branch focus/feat-switching)

- **Settings ▸ Switching:** Careful (one app at a time, each saving before the next) or Fast (every app quits and
  reopens at once — still never forced).
- **Settings ▸ Hide Instead of Quit:** tick any app to have it hidden, never quit, so it comes back exactly as it was —
  the same Claude chat, the same page. For apps that don't restore themselves after quitting. ("Hide every app" moved here.)
- **New icon: Fewer** — a wide row of apps narrows to the two you keep.
- Wording: dropped the "Normal is the original" line; "Default (white)" is now "White". Scenarios 29, 30.

## 0.7.0 — 2026-11-13 (branch focus/feat-session-banner)

- **A session says what it is.** During a session the menu opens with a banner: the mode's name (or the name you
  gave the session) in bold, with "Mode · started 21:48 · keeps Unreal Editor, Claude" under it. Unnamed sessions read
  "Focus session". The big button reads "End Game design". Renaming the live session shows at once. Scenario 28.

## 0.6.0 — 2026-11-13 (branch focus/feat-modes-plumbing)

- **Modes plumbing, ready for drag and drop** (no dragging in the UI yet, by design): every mode has a permanent id
  (older modes are migrated); create, rename, delete, add an app (by id, or from a .app dragged in from Finder or the
  Dock), remove, reorder and start — all by id. The menu now addresses modes by id, not position. Scenario 27.

## 0.5.0 — 2026-11-13 (branch focus/feat-icon-styles)

- **A chunkier menu bar icon, like the logo.** Off: four thick brackets round a solid dot. On: the brackets close and
  the disc floods solid with the dot knocked out — outline vs solid, obvious at a glance. Same animation timing.
  The app logo keeps the original drawing (frozen as `classicLens`).
- **Settings ▸ Appearance ▸ Icon:** six designs — Lens (default), Less more, Narrowing, Framed, Gathered, Switcher.
  Each animates into its focused state; the icon colours apply to all; white by default.

## 0.4.0 — 2026-11-13 (branch focus/feat-kept-apps)

- **A session is defined by the apps you keep open**, not the ones it parks (Unreal + Claude = game design). Every
  session now records its kept apps. Past sessions are titled by them ("Kept Unreal, Claude · Today 21:48") and list
  **Kept open** above **Parked**.
- Fix: **Save as Mode…** built the mode from the *parked* apps — the wrong set. It now uses the kept apps (and is
  greyed out for older sessions that didn't record them). Modes read "the apps you keep open".

## 0.3.0 — 2026-11-13 (branch focus/feat-animation-speed)

- **Settings ▸ Appearance:** Icon Colour moves here, beside a new **Animation Speed** dial: a small clock with the hand
  straight up for **Normal**, back at 10 for **Slow**, on at 2 for **Fast**. Speed sets how long the app icons stay on
  screen before they're swept into the menu bar (start) or drop into the pill (end).
- **Normal is the original animation and the permanent default.** Its timing, recorded: icons hold **0.24 s** at the
  start of a session and **0.02 s** at the end; unchanged at every speed: pop-in 0.16 s, hit stop 0.10 s, burst 0.16 s,
  flight 0.34 s (+35 ms per icon), zip 0.22 s. Slow holds 1.2 s / 0.9 s; Fast 0.08 s / 0 s.

## 0.2.1 — 2026-11-12 (branch focus/feat-shortcuts)

- **Test suite:** `./test.sh` (quick, ~15 s, touches no apps — run after every major change) and `./test.sh full`
  (~7 min, every scenario — run when needed). Both print a plain-English table and save docs/TEST-REPORT.md.
  Stand-in app source now lives in tests/standins.swift.
- Fix (found by the full suite): Focus recognised a session's apps by file path, which has several spellings
  (/var vs /private/var, moved or translocated apps), so an app could be missed — e.g. one that reopened itself.
  It now recognises apps by bundle ID, falling back to the path for older saved sessions.

## 0.2.0 — 2026-11-12 (branch focus/feat-shortcuts)

- **Settings ▸ Shortcuts:** choose the keys. Start/End Session: ⌘⇧F (default), ⌃⌥F, ⌃⇧F, ⌃⌥⌘F; open the menu: ⌘⇧E
  (default), ⌃⌥E, ⌃⇧E, ⌃⌥⌘E. Each choice says what it clashes with; a change takes effect at once; a combination
  another app already holds is flagged instead of failing silently. The Start button shows the current key.

## 0.1.2 — 2026-11-12 (branch focus/feat-modes)

Bug hunt — the whole of main.swift read through; eight real defects fixed, each with a stress scenario (19–22):
- Deleting the live session from Past sessions made End Session reopen an older session's apps. Delete is now
  disabled for it; it's marked "· now", and its Open item reads "End Session and Reopen".
- "Open all" on an old session silently ended the live one. It now just opens that session's apps.
- ⌘⇧F during Quit All & Restart started a session mid-quit, and the Mac could then restart mid-session. Now ignored.
- Ending a Mode's session early left the mode's app list active, so the next ordinary session quit the wrong apps;
  the "waiting for you to save" note lingered too. End Session now clears both.
- A session started while the last one was still being restored had apps reopened into it — and the apps that
  restore hadn't reached were lost. Restores now stop when a new session starts, and their unreached apps join it.
- Ending a session within the first second (before the snapshot finished) could hide apps afterwards. Fixed.
- No display (lid shut, screens off) would crash Focus when placing the pop-up. Fixed.
- Confirmation dialogs could open behind other windows. They float in front now.
- Restoring no longer waits 0.7 s on apps that are already open.

## 0.1.1 — 2026-11-12 (branch focus/feat-modes)

- Fix: hovering Settings (or any submenu) showed a copy of the whole menu instead of its own items — a side effect
  of 0.1.0's dark menu. Covered by a new stress scenario.

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
