# Focus on Windows, Linux and Unix — notes (2026-11-14)

His intent, stated 2026-11-14: Focus **will** be ported to Windows, Linux and Unix. Not yet, and no rewrite has been
asked for. He wants the best-performing app possible. Not every feature has to carry over; the **core** must.
These are first thoughts from knowing the code, not researched facts. Anything marked "check" needs verifying first.

## The core that must work everywhere
1. See which apps are open, and how much memory each uses.
2. Start a session: close (or hide) every app not kept, safely, without losing unsaved work.
3. End a session: bring those apps back.
4. Modes: named sets of apps, started with one key.
5. One global shortcut to start and end, more for modes.
6. An icon in the system tray / menu bar with the menu.
7. Sessions survive a crash or restart (saved to disk).

## What is Mac-only today, and its equivalent
| Need | macOS (today) | Windows | Linux |
|---|---|---|---|
| List apps | NSWorkspace running apps | top-level windows grouped by process (EnumWindows) | windows via the compositor; process list from /proc |
| Memory per app | proc_pid_rusage | process memory counters | /proc/<pid>/smaps |
| Ask an app to quit politely | NSRunningApplication.terminate | post a close message to its windows | close its windows (X11: easy; Wayland: per-compositor, check) |
| Hide an app | NSRunningApplication.hide | minimise / hide windows | minimise (X11); Wayland varies (check) |
| Reopen an app | NSWorkspace.openApplication | start the executable / app id | start its .desktop entry |
| Apps restore their own windows | macOS window restoration | no system-wide equivalent | none |
| Global shortcuts | Carbon RegisterEventHotKey | RegisterHotKey | X11 grabs; Wayland needs the desktop's shortcuts portal (check) |
| Tray icon + menu | NSStatusItem + NSMenu | notification-area icon + popup | StatusNotifierItem (not on stock GNOME without an extension — check) |
| Open at login | SMAppService | Startup registry key / Task Scheduler | autostart .desktop file |
| Settings storage | UserDefaults | file in AppData | file in ~/.config |

## The hard parts
- **"An app" is a Mac idea.** Windows and Linux have processes and windows; one app can be many processes (browsers) and
  one process can show many windows. The port needs its own rule for grouping them into the rows the menu shows.
- **Coming back exactly as it was** is weakest off the Mac: there is no system window restoration. Hiding (minimise and
  keep running) is the only exact method there, so hide-first may have to be the rule on those platforms.
- **Wayland** deliberately stops one program from controlling another's windows or grabbing keys. Linux support
  should start with X11 and the big desktops' own interfaces (KDE, GNOME), not "all of Linux" at once.
- **Save prompts.** The careful quit queue (one app at a time, wait, notice a save prompt) depends on how each
  system reports "this app refused to close". Needs a design per platform.
- **The custom menu.** Today it is an AppKit menu with custom-drawn rows and animations. Each platform needs its own
  drawing, or one shared drawing layer.

## How to build it (options, not a decision)
1. **One portable core, three native shells (recommended to investigate first).** Move the session engine (what is
   kept, what is closed, the queue, modes, saved sessions, restore) into a small library with no UI and no system calls
   of its own; each platform supplies "list apps / quit / hide / reopen / hotkey / tray". The Mac app keeps its Swift
   AppKit shell. The core could be Rust or C++ for speed and reach; Swift itself also runs on Windows and Linux, which
   would let the existing engine move with far less rewriting (check how mature Swift's Windows support is for this).
2. **Three separate native apps** sharing only the design and the file formats. Best fit per platform, three codebases.
3. **One cross-platform toolkit for everything.** Fastest to ship, worst fit for a tray utility that must feel native
   and be as light as possible; he has ruled out web wrappers elsewhere.

## What to do now so the port is cheaper later
- Keep the session engine free of AppKit: `main.swift` mixes engine and menu in one file; splitting them is the first step.
- Keep saved data simple and documented (plain dictionaries today) so every platform can read the same sessions and modes.
- Keep every user-facing string in one place.
- Keep the test scenarios describing behaviour ("a parked app deleted before restore is skipped"), so each port can be
  held to the same list.

## Not expected to carry over
The session pill's exact animation, the menu bar name sparkle, snapshots, the Customised Logo, and anything that depends
on macOS window restoration. They can be redone per platform later.
