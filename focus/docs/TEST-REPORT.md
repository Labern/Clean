# Focus — test report

**quick** run · version 0.17.0 · 2026-11-13 23:16 · 37s · **19 passed, 0 failed**

| Result | Check | Detail |
|---|---|---|
| PASS | Builds with zero errors and zero warnings |  |
| PASS | 4. corrupted / odd saved settings | menu built with 18 items; session state reset to false |
| PASS | 9. session history is capped at 12 | 12 kept of 15 |
| PASS | 18. submenus keep their own items when they open (Settings must not become a copy of the menu) | Settings, Tools, Past sessions unchanged on open |
| PASS | 23. shortcuts: switching registers the new keys at once; the default is ⌘⇧F / ⌘⇧E | default ⌘⇧F/⌘⇧E: true; ⌃⇧F registered live: true; ticked in the menu: true |
| PASS | 24. animation speed: Normal is the default and keeps the original timing; Slow/Fast change only the holds | default Normal with hold 0.24 s / 0.02 s: true; slow longer: true; fast shorter: true; Appearance has Icon Colour: true and the dial: true |
| PASS | 32. icon picker: hovering a design plays it back and forth (rest → in session with hit stop → back); leaving stops it; 20 designs | starts: true; landing t=1.0 scale=1.1199999999998653; rest t=0.0; returning t=0.5555555555555557; stops: true; designs: 20 |
| PASS | 33. colour schemes: the Evangelion pairs are listed by name; a user can save, pick and delete their own; the originals stay | Evangelion listed: true; originals kept: true; saved scheme listed: true; picking it applies it: true; ⌥ delete: true; deleted: true |
| PASS | 34. the menu opens with its state: Focus out of session, and in a session how many apps and since when | first line out of session: 'Focus' |
| PASS | 35. modes: suggestions use only installed apps (Web Only = the default browser); adding one makes a real mode and it leaves the list; a mode's apps can be added and removed; Temporarily Closed wording | suggestions ["Game Design: UnrealEditor, Claude", "Web Only: Google Chrome", "Coding: Xcode, Terminal, Google Chrome"]; Web Only = default browser: true; all apps installed: true; added as a mode: true, then leaves the list: true; add/remove apps: true; mode menu has app rows + Add App: true |
| PASS | 36. mode shortcuts: none until the user sets one; a digit belongs to one mode; the row shows it; the modifier is a Setting; a self-test never takes the keys | no keys until set: true; set: true; digit moves: true; row shows ⌘1: true; picker: true; modifier in Settings: true; test took no keys: true; None clears: true |
| PASS | 38. app rows: hovering shows + (will add) or × (will remove); after 2.5 s a popup says exactly what a click does | add: 'Click to add Chrome to your session.'; remove: 'Click to remove Chrome from your session.'; mode: 'Click to add Chrome to this mode.'; no popup where nothing is added: true; delay 2.5 s; popup shows: true |
| PASS | 39. naming is inline (no popups): new mode, rename mode, rename session, save as mode; the menu bar shows the session's name, or only the icon if turned off | new mode inline: true; rename inline: true; no Rename…/New Mode… popups: true; menu bar ' AI': true; icon only when off: true; past session has 2 inline fields: true; session rename: true, menu bar follows: true; clears after: true |
| PASS | 40. the menu bar always names the session: its name, else the mode it matches, else Focus | matches mode → ' AI': true; no match → ' Focus': true; own name wins: true |
| PASS | 26. icon designs: Lens is the default; every design draws at rest and focused, in the user's colours; the picker is in Appearance | Lens default: true; designs that drew nothing: none; choice saved: true; picker in Appearance: true |
| PASS | 27. modes plumbing: stable ids, add (by id and by dragged .app), dedupe, reorder, remove, rename, delete, migration | migration true · create+dedupe true · dragged .app true · no duplicates true · reorder true · remove+rename true · found by id true · delete true |
| PASS | 28. a live session says what it is: banner with the mode's name at the top, 'End <name>', renames show at once | first line 'Focus — Game design (4 apps, since 23:16)': true; banner 'Game design' / 'Mode · started 23:16 · keeps TextEdit': true; button 'End Game design'; rename shows: true; unnamed says Focus session: true; no banner outside a session: true |
| PASS | 29. switching and hide-instead-of-quit settings; the Fewer icon | careful unless chosen: true; menu ticks Careful: true; per-app hide rows: true; Fewer icon: true |
| PASS | 16. menu speed with every process on the Mac | 102 ms per menu open |

Quick: `./test.sh` (every major change). Full: `./test.sh full` (when needed).
