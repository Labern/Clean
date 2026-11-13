# Focus — test report

**quick** run · version 0.6.0 · 2026-11-13 00:25 · 17s · **9 passed, 0 failed**

| Result | Check | Detail |
|---|---|---|
| PASS | Builds with zero errors and zero warnings |  |
| PASS | 4. corrupted / odd saved settings | menu built with 23 items; session state reset to false |
| PASS | 9. session history is capped at 12 | 12 kept of 15 |
| PASS | 18. submenus keep their own items when they open (Settings must not become a copy of the menu) | Settings, Tools, Past sessions unchanged on open |
| PASS | 23. shortcuts: switching registers the new keys at once; the default is ⌘⇧F / ⌘⇧E | default ⌘⇧F/⌘⇧E: true; ⌃⇧F registered live: true; ticked in the menu: true |
| PASS | 24. animation speed: Normal is the default and keeps the original timing; Slow/Fast change only the holds | default Normal with hold 0.24 s / 0.02 s: true; slow longer: true; fast shorter: true; Appearance has Icon Colour: true and the dial: true |
| PASS | 26. icon designs: Lens is the default; every design draws at rest and focused, in the user's colours; the picker is in Appearance | Lens default: true; designs that drew nothing: none; choice saved: true; picker in Appearance: true |
| PASS | 27. modes plumbing: stable ids, add (by id and by dragged .app), dedupe, reorder, remove, rename, delete, migration | migration true · create+dedupe true · dragged .app true · no duplicates true · reorder true · remove+rename true · found by id true · delete true |
| PASS | 16. menu speed with every process on the Mac | 30 ms per menu open |

Quick: `./test.sh` (every major change). Full: `./test.sh full` (when needed).
