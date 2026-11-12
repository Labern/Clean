# Focus — test report

**quick** run · version 0.2.0 · 2026-11-12 22:09 · 13s · **6 passed, 0 failed**

| Result | Check | Detail |
|---|---|---|
| PASS | Builds with zero errors and zero warnings |  |
| PASS | 4. corrupted / odd saved settings | menu built with 22 items; session state reset to false |
| PASS | 9. session history is capped at 12 | 12 kept of 15 |
| PASS | 18. submenus keep their own items when they open (Settings must not become a copy of the menu) | Settings, Tools, Past sessions unchanged on open |
| PASS | 23. shortcuts: switching registers the new keys at once; the default is ⌘⇧F / ⌘⇧E | default ⌘⇧F/⌘⇧E: true; ⌃⇧F registered live: true; ticked in the menu: true |
| PASS | 16. menu speed with every process on the Mac | 26 ms per menu open |

Quick: `./test.sh` (every major change). Full: `./test.sh full` (when needed).
