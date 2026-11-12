# Focus — stress test (0.0.4, updated for 0.1.2, 2026-11-12)

How it was run: `Focus --selftest-stress` drives Focus's real code paths through each scenario, one after
another, with its own settings store. Only TextEdit, Calculator and throwaway stand-in apps were ever quit or
reopened; each scenario checks its scope before doing anything, and every run waited for the microphone to be
quiet first. Run a subset with `--only=5,8`.

**Result: every scenario passes. Two real bugs were found and fixed.**

---

## Bugs found and fixed

1. **Two Focuses launched at the same instant could leave none.** Each saw the other and both quit (1 of 3 cold
   races ended with no Focus running — e.g. "Open at login" and a manual open at the same moment).
   **Fix:** the oldest copy always survives (launch time, then process number), plus a re-check 1.5 s after
   launch. **Proof:** 12 rounds of three simultaneous cold launches → exactly one Focus every time.
2. **An app that reopened itself was described as "probably a save prompt."** Login-item helpers and updaters can
   relaunch an app right after Focus quits it. **Fix:** Focus remembers which process it quit; one that comes back
   under a new process gets its own line, **"Reopened by itself: … — quit again"**, and a click quits it again.

---

## Tested by machine

| # | Scenario | Result |
|---|---|---|
| 1 | ⌘⇧F twice fast (End while still quitting) | PASS — quitting stops, both apps back, no session left |
| 2 | Focus killed with SIGKILL mid-session, then relaunched | PASS — the new Focus knows the session; End Session restores it |
| 3 | A parked app deleted/moved before restore | PASS — skipped, the rest restore, no crash |
| 4 | Corrupted saved settings (wrong types, unknown apps, bad colour) | PASS — menu still builds; state resets cleanly |
| 5 | An app that relaunches itself after quitting | PASS — listed as "Reopened by itself"; End Session leaves one copy |
| 6 | You reopen a parked app mid-session, then End | PASS — no duplicate |
| 7 | Tools ▸ Quit All during a session | PASS — refused (greyed out), nothing quit |
| 8 | Hide mode instead of quit | PASS — hidden, then shown again |
| 9 | Session history | PASS — capped at 12 |
| 10 | An app merely slow to quit (12 s) | PASS — goes on the waiting list, clears itself when it quits |
| 11 | Two or three Focus launches at once | PASS after fix — always exactly one |
| 12 | Open at login on → off → on | PASS — macOS registers it; your setting is back where it was (on) |
| 16 | Menu speed, every process on the Mac | PASS — 26–28 ms per open |
| 17 | Modes: start, rename, End | PASS |
| 18 | Submenus keep their own items when they open | PASS (0.1.1 regression guard) |
| 19 | Ending a mode early leaves nothing behind | PASS (0.1.2 fix) |
| 20 | ⌘⇧F during Quit All & Restart is ignored | PASS (0.1.2 fix) |
| 21 | Live session can't be deleted; old Open all doesn't end it | PASS (0.1.2 fix) |
| 22 | New session mid-restore: nothing reopened into it, nothing lost | PASS (0.1.2 fix) |
| — | App stuck on a save prompt (earlier test) | PASS — queue moves on after 8 s, app brought forward |

---

## Reasoned through (can't be done safely by machine here)

- **Sleep mid-session or mid-quit:** the quit queue is driven by timers, which pause during sleep and carry on
  after wake. The session itself is saved to disk, so nothing depends on staying awake.
- **Restart or log out mid-session:** the session is on disk (scenario 2 proves a cold Focus picks it up). Apps
  still waiting to quit get quit by the logout anyway; if macOS's "reopen windows when logging back in" reopens them,
  End Session just un-hides them (scenario 6 — no duplicates).
- **Login items that open apps at login during a session** (e.g. a mail app set to open at login): they appear while
  you're focused. Nothing breaks and End Session handles them, but they aren't re-parked — see recommendation 2.
- **Several displays / full-screen Spaces:** the pop-up plays on the screen holding the menu bar icon and is allowed
  over full-screen apps. Only one display here, so not seen.
- **Apps on an external drive that's been ejected:** same as scenario 3 — skipped on restore.

---

## Recommendations before release

1. **Let people choose the shortcuts.** ⌘⇧F and ⌘⇧E are taken system-wide by Focus, and they clash with common app
   shortcuts: ⌘⇧F is "Find in files" in VS Code, Xcode, JetBrains IDEs and Sublime, and "Recents" in Finder; ⌘⇧E is
   the file explorer in VS Code. Developers will notice. A Settings ▸ Shortcuts recorder would fix it.
2. **Re-park apps that open themselves during a session** (login items, helpers) — optionally, automatically.
3. **Warn before quitting a busy app** — one playing audio, downloading, or exporting (Chrome downloads already
   prompt, which lands on the waiting list, but a heads-up in the caption would be kinder).
4. **Snapshots hold whatever was on screen.** Only two are ever kept, in Focus's own folder — worth one line in the
   release notes for privacy.
