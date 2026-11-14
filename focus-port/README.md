# Focus — the Windows and Linux port (Rust)

A port of the Mac app (`focus/`, version 0.18.25). Same behaviour, same menu, same animation.

## Layout
| Folder | What it is |
|---|---|
| `core/` | Sessions, modes, the careful quit queue, saved state. No system calls. 13 tests. |
| `ui/` | The menu, the Lens icon and the session animation, drawn in plain Rust (the same pixels on every system). |
| `win/` | The Windows app: finds open apps, closes and reopens them, tray icon, Ctrl+Shift+F, the menu and animation windows. |

## What "an app" is on Windows
- Every window a person could switch to (what Alt+Tab shows), grouped by the program that owns it.
- A classic program is identified by its `.exe` path and reopened by starting that `.exe`.
- A Microsoft Store app is identified by its Application User Model ID and reopened through the shell's AppsFolder,
  as the Start menu does. Store apps drawn inside the shared frame window are traced to the process behind it.
- Closing is always polite: each window gets the same request as clicking ✕. Nothing is ever terminated.
- Windows' own shell (desktop, taskbar, Start, search…) is never listed or closed.

## Shortcuts
| Mac | Windows |
|---|---|
| ⌘⇧F start / end a session | Ctrl+Shift+F |
| ⌘⇧E open the menu | Ctrl+Shift+E |
| ⌘1 … ⌘0 start a mode | Ctrl+1 … Ctrl+0 (only for modes that have a number) |

## Commands
```
./cargo.sh test                                              core + drawing tests (any system)
./cargo.sh run -p focus-ui --example render -- out           draw the menu, icon and animation to PNG files
./cargo.sh check --target x86_64-pc-windows-msvc -p focus    type-check the Windows app from a Mac
focus.exe                the tray app
focus.exe --list         the apps Focus can see, with their memory
focus.exe --selftest     a real session with throwaway apps, pass/fail per step
focus.exe --cloud-test DIR   the tray app driven like a person, with a screenshot at every step
```
`cargo.sh` uses a private toolchain in `~/Library/Caches/focus-port-rust` if present (it has the Windows target).

## The session animation
`ui/src/pill.rs` is a line-for-line port of the Mac's `SessionPill.play` as of 0.17.0. Its timings are pinned by tests.
Do not change the timing or the motion without the owner's say-so.

## Not built yet
- The submenus (Create New Mode, Edit Modes, Suggested Modes, Past sessions, Tools, Settings), sorting by Usage, and
  Add or remove: the rows are drawn; the windows behind them are not.
- Icons for Store apps (a coloured tile stands in).
- The menu-bar-style name beside the tray icon (Windows shows it as the icon's tooltip for now).
- Linux: the core and drawing already run and are tested there; the app shell is not written.
- Apps that close to the tray instead of quitting keep their memory; Focus sees their window go and counts them closed.
