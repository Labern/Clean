# Focus — test report

**quick** run · version 0.20.0 · 2026-11-18 18:09 · 60s · **40 passed, 0 failed**

| Result | Check | Detail |
|---|---|---|
| PASS | Builds with zero errors and zero warnings |  |
| PASS | 4. corrupted / odd saved settings | menu built with 19 items; session state reset to false |
| PASS | 9. session history is capped at 12 | 12 kept of 15 |
| PASS | 18. submenus keep their own items when they open (Settings must not become a copy of the menu) | Settings, Tools, Past sessions unchanged on open |
| PASS | 23. shortcuts: switching registers the new keys at once; the defaults are ⌘⇧F (session), ⌘⇧E (desktop app), ⌥⇧E (menu) | defaults ⌘⇧F / ⌘⇧E app / ⌥⇧E menu: true; ⌃⇧F registered live: true; ticked in the menu: true |
| PASS | 24. animation speed: Normal is the default and keeps the original timing; Slow/Fast change only the holds | default Normal with hold 0.24 s / 0.02 s: true; slow longer: true; fast shorter: true; Appearance has Icon Colour: true and the dial: true |
| PASS | 32. icon picker: hovering a design plays it back and forth (rest → in session with hit stop → back); leaving stops it; 21 designs | starts: true; landing t=1.0 scale=1.1199999999998653; rest t=0.0; returning t=0.5555555555555557; stops: true; designs: 21 |
| PASS | 33. colour schemes: the Evangelion pairs are listed by name; a user can save, pick and delete their own; the originals stay | Evangelion listed: true; originals kept: true; saved scheme listed: true; picking it applies it: true; ⌥ delete: true; deleted: true |
| PASS | 34. the menu has no state line; its first row is Quit, at the top right | first row is Quit: 'Quit' |
| PASS | 35. modes: suggestions use only installed apps (Web Only = the default browser); adding one makes a real mode and it leaves the list; a mode's apps can be added and removed; Temporarily Closed wording | suggestions ["Web Only: Google Chrome", "Coding: Xcode, Terminal, Google Chrome", "Game Design: UnrealEditor, Claude"]; Web Only = default browser: true; all apps installed: true; added as a mode: true, then leaves the list: true; add/remove apps: true; mode menu has app rows + Add App: true |
| PASS | 36. mode shortcuts: each new mode takes the next number; a digit belongs to one mode; the row shows it; the modifier is a Setting; a self-test never takes the keys | numbered 1, 2 as created: true; set: true; digit moves: true; row shows ⌘1: true; picker: true; modifier in Settings: true; test took no keys: true; None clears: true |
| PASS | 38. app rows: hovering shows + (will add) or × (will remove); after 2.5 s a popup says exactly what a click does | add: 'Click to add Chrome to your session.'; remove: 'Click to remove Chrome from your session.'; mode: 'Click to add Chrome to this mode.'; no popup where nothing is added: true; delay 2.5 s; popup shows: true |
| PASS | 39. naming is inline (no popups): new mode, rename mode, rename session, save as mode; the menu bar shows the session's name, or only the icon if turned off | new mode inline: true; rename inline: true; no Rename…/New Mode… popups: true; menu bar ' AI': true; icon only when off: true; past session has 2 inline fields: true; session rename: true, menu bar follows: true; clears after: true |
| PASS | 40. the menu bar always names the session: its name, else the mode it matches, else Focus | matches mode → ' AI': true; no match → ' Focus': true; own name wins: true |
| PASS | 41. organised: Tools headings; Settings ▸ Behaviour; Create New Mode first; unnamed modes are numbered; right-click edit menu; column headings; headings share one size | unnamed → Mode 1 on ⌘1: true; Tools headings: true; Appearance, Shortcuts, Behaviour: true; Behaviour holds the three: true, moved out of Settings: true; Create New Mode under the modes, Add New Mode in Edit Modes, lock rows inert: true; right-click edit menu: true; column headings: true; standard macOS headings + name styles: true |
| PASS | 42. clicking Usage cycles the app list: as listed → most memory first → most used first → back | as listed: true; most used first: true; cycles 1, 2, 0: true; Usage is clickable: true |
| PASS | 43. Settings ▸ Appearance ▸ Headings: Minimalist (names only), Normal (as now), Verbose (a sentence under each) | in a session, Verbose explains both lists (Normal doesn't): true; minimalist: true; normal unchanged: true; verbose adds three explanations: true; picker, Normal ticked: true |
| PASS | 45. Settings ▸ Appearance ▸ Light or Dark: Dark is standard and unchanged (#1F1F21); Light is optional | dark is the standard, #1F1F21: true; picker, Dark ticked: true; light look when chosen: true |
| PASS | 46. the dark look is on every menu, submenu and drawn row as soon as the menu is built (never light ink on the dark ground) | 20 menus and 41 drawn rows all dark at build: true; light look consistent when chosen: true |
| PASS | 48. the mode builder keeps a half-typed name if its menu closes; cleared once the mode is made | half-typed name survives the menu closing: true; cleared after creating: true |
| PASS | 26. icon designs: Default (the website's mark) is the default, Original is still offered; every design draws at rest and focused, in the user's colours; the picker is in Appearance | Default is the default, Original offered: true; designs that drew nothing: none; choice saved: true; picker in Appearance: true |
| PASS | 27. modes plumbing: stable ids, add (by id and by dragged .app), dedupe, reorder, remove, rename, delete, migration | migration true · create+dedupe true · dragged .app true · no duplicates true · reorder true · remove+rename true · found by id true · delete true |
| PASS | 28. a live session: no banner and no state line at the top; the button says End Session | first line 'Quit', no banner or state line: true; button 'End Session' |
| PASS | 29. switching and hide-instead-of-quit settings; the Fewer icon | careful unless chosen: true; menu ticks Careful: true; per-app hide rows: true; Fewer icon: true |
| PASS | 16. menu speed with every process on the Mac | 64 ms per menu open |
| PASS | 201. SSS: a word finds its window | Budget November.numbers |
| PASS | 202. SSS: a typo still finds it | invioce → Invoice INV-2041 – Stripe Dashboard; screnplay → Screenplay draft 4.pdf |
| PASS | 203. SSS: the start of a word is enough | kit → Kitten weights 2026; down → Downloads |
| PASS | 204. SSS: words in any order, across name, app and address | stripe inv → Invoice INV-2041 – Stripe Dashboard; clean pull → Pull requests · Labern/Clean |
| PASS | 205. SSS: a site's name finds a tab whose title doesn't say it | github → Pull requests · Labern/Clean; bbc → Weather for London |
| PASS | 206. SSS: accents don't matter | Café menu ideas – Google Docs |
| PASS | 207. SSS: initials work | sd → Invoice INV-2041 – Stripe Dashboard |
| PASS | 208. SSS: nonsense finds nothing | 0 results |
| PASS | 209. SSS: nothing typed lists everything, most recent first | 11 of 11 |
| PASS | 210. SSS: an app's name lists all of its tabs | 5 for “chrome” |
| PASS | 211. SSS: a browser's answer becomes its tabs, the current one ranked with its window | 3 tabs; orders [24, 4, 5] |
| PASS | 215. SSS: a window's name drops its app's name from the end | Inbox |
| PASS | 214. SSS: every installed browser understands its tab scripts | Chrome, Safari |
| PASS | 212. SSS: the panel reads in dark mode | ground 56855, ink 1050 of 146188 samples |
| PASS | 213. SSS: the panel reads in light mode | ground 144101, ink 862 of 146188 samples |

Quick: `./test.sh` (every major change). Full: `./test.sh full` (when needed).
