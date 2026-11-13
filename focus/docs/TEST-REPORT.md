# Focus — test report

**quick** run · version 0.10.1 · 2026-11-13 03:21 · 23s · **12 passed, 0 failed**

| Result | Check | Detail |
|---|---|---|
| PASS | Builds with zero errors and zero warnings |  |
| PASS | 4. corrupted / odd saved settings | menu built with 17 items; session state reset to false |
| PASS | 9. session history is capped at 12 | 12 kept of 15 |
| PASS | 18. submenus keep their own items when they open (Settings must not become a copy of the menu) | Settings, Tools, Past sessions unchanged on open |
| PASS | 23. shortcuts: switching registers the new keys at once; the default is ⌘⇧F / ⌘⇧E | default ⌘⇧F/⌘⇧E: true; ⌃⇧F registered live: true; ticked in the menu: true |
| PASS | 24. animation speed: Normal is the default and keeps the original timing; Slow/Fast change only the holds | default Normal with hold 0.24 s / 0.02 s: true; slow longer: true; fast shorter: true; Appearance has Icon Colour: true and the dial: true |
| PASS | 32. icon picker: hovering a design plays it back and forth (rest → in session with hit stop → back); leaving stops it; 20 designs | starts: true; landing t=1.0 scale=1.1199999999998653; rest t=0.0; returning t=0.5555531713697647; stops: true; designs: 20 |
| PASS | 26. icon designs: Lens is the default; every design draws at rest and focused, in the user's colours; the picker is in Appearance | Lens default: true; designs that drew nothing: none; choice saved: true; picker in Appearance: true |
| PASS | 27. modes plumbing: stable ids, add (by id and by dragged .app), dedupe, reorder, remove, rename, delete, migration | migration true · create+dedupe true · dragged .app true · no duplicates true · reorder true · remove+rename true · found by id true · delete true |
| PASS | 28. a live session says what it is: banner with the mode's name at the top, 'End <name>', renames show at once | banner 'Game design' / 'Mode · started 03:21 · keeps TextEdit': true; button 'End Game design'; rename shows: true; unnamed says Focus session: true; no banner outside a session: true |
| PASS | 29. switching and hide-instead-of-quit settings; the Fewer icon | careful unless chosen: true; menu ticks Careful: true; per-app hide rows: true; Fewer icon: true |
| PASS | 16. menu speed with every process on the Mac | 28 ms per menu open |

Quick: `./test.sh` (every major change). Full: `./test.sh full` (when needed).
