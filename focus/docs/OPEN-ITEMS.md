# Focus — things for you to read

Everything I've raised that you haven't answered or may have missed, in one place. Current version: **0.0.4**
(`focus/main`, tag `focus-v0.0.4`).

---

## 1. Questions waiting for your answer

1. **Named sessions** — saved groups of apps ("Essay" = Chrome + Word, "Dev" = VS Code + Xcode). Shall I build it
   now, on `focus/feat-named-sessions` → version 0.1.0? The plan is in section 3.
2. **The invisible self-test copy.** While developing, I test Focus by running a second, invisible copy of it
   (its own settings, no menu bar icon) against harmless apps like TextEdit and Calculator — so your real apps
   are never touched. You said there should never be two Focuses. Is this test copy acceptable, or should I
   stop using it?
3. **Merging feature branches.** New features go on `focus/feat-<name>` branches. I'm not allowed to merge
   branches myself. When a feature is done, will you merge it into `focus/main`, or do you want a different
   arrangement?
4. ~~The Wispr Flow bug report~~ — **resolved**: Wispr replied straight away, confirmed the fault and will fix it.

---

## 2. What a Developer ID certificate would do

- **You already have** an "Apple Development" certificate, and Focus is now signed with it. That alone fixes the
  most annoying problem: macOS keeps Focus's permissions (e.g. snapshot permission) across rebuilds.
- **Developer ID lets you share or sell Focus.** Apple can notarise it, so anyone can download and open it with no
  "unidentified developer" warning and no right-click → Open workaround. You need this for release.
- **It doesn't** let any app hide other apps from ⌘⇥ — no certificate can.
- **Why it got stuck before:** your keychain has Apple's Developer ID *intermediate* certificates but no
  "Developer ID Application" certificate. Only the team's **Account Holder** can create one, and it must be made
  with a key from this Mac.
- **How to get it:** Xcode → Settings → Accounts → select your team → **Manage Certificates…** → **+** →
  **Developer ID Application**. That creates the key and certificate on this Mac in one step. Focus's build
  picks it up automatically. For sharing, I'd then wire up notarisation, which needs an app-specific password or
  an App Store Connect key that you create.

---

## 3. Plan — named sessions (not built yet)

- **A group** is a named, saved set of apps, each with its own icon (optionally the documents they had open).
- **Open** a group (launch or bring forward just those apps), **close** a group (the same slow, safe quit for just
  those), or **switch** to one (close every other group's apps, open this one).
- **Make one** with "Save open apps as group…", or turn any Past session into a group in one click.
- **Rename** by right-clicking a group or session, or a ✎ button on the row. Past sessions rename the same way.
- **Split**: move apps between groups by ticking them, or split one session into two groups. An app can belong to
  more than one group.
- **In the menu:** a "Groups" section above Past sessions — one row per group with an open/closed dot, its
  memory, and open/close on click. Optional key per group later.
- **Stored** as a new `groups` list next to `sessions`; nothing existing changes, so no saved session is lost.
- **Build order:** storage and open/close/switch → rename and split → the menu section → your window.

---

## 4. Built, but not yet seen working live

These are done and pass their tests, but haven't been seen on your screen in real use:

- **End Session** and the reverse pop-up animation (icons streaming back out of the menu bar icon) in a real
  session.
- **Your purple and green icon colours during the focus animation** (each frame uses them; not watched live).
- **YouTube no longer autoplaying** when Focus restores Chrome (Chrome now relaunches with autoplay blocked until
  you click — confirm on your next real restore).
- **The menu in light mode** (should be a near-black `#171A20` pill with white text).
- **The microphone check** that makes me wait while you dictate — it reads "free" correctly; I haven't yet seen it
  catch an actual dictation.
- **Force Quit All Apps** and the two "Open…" items in Tools — built and listed in the menu, not clicked for real.

---

## 5. Optional things only you can do

- **Snapshot permission:** Settings ▸ "Allow snapshots…" asks once for Screen Recording. Without it, Focus simply
  skips the snapshot and never prompts.
- **Developer ID certificate** — see section 2.

---

## 6. Still on the list

- Named sessions (waiting for your go — section 3).
- Release polish: strip any AI-sounding wording from every string in the app before shipping.
- Your window design (the fuller settings window, later).
- ~~Stress test~~ — **done**: see `STRESS-TEST.md` in this folder. Every scenario passes; two bugs found and fixed.
  It ends with four recommendations before release (choosable shortcuts first).

---

## 7. Notes worth knowing

- **Wispr Flow in ⌘⇥** is Wispr's own bug: its invisible "Status" window counts as an open window, so its "Hide
  app in Dock" setting can never engage. Wispr confirmed it and will fix it. It's no longer part of this project.
- **Nothing about your own apps is built into Focus.** Wispr Flow and Terminal are in *your* Critical System
  Processes list; Claude is ticked "keep open" in *your* settings. A new user starts with none of that.
- **The product page** (paradoxica.uk/focus) mirrors the real menu. The Hub session updates it whenever the menu
  changes; it currently matches 0.0.3.
- **Your icon** is a purple ring with a green dot, and your app logo is a purple tile with a green mark. The
  default for everyone is white.

## Next: first-run tutorial (requested 2026-11-13)
- Like Wispr Flow's: the first time Focus opens, a short walkthrough of how it works. A Skip button. Reopen any time from Settings ▸ Show Tutorial.
- Where it lives (2026-11-14): a "Tutorial" item directly above Quit in the menus; clicking it shows the tutorial.

## Most important: apps must reopen exactly as they were (2026-11-14)
- His words: "when I close an app, I need it to open just the way it was. Otherwise, the app isn't doing what it promises."
- Today: quit apps come back only as well as each app restores itself (macOS window restoration is on; Chrome gets --restore-last-session). Only Hide Instead of Quit is exact, and his hide list is empty.
- Decision needed from him: hide by default (exact, frees less memory) vs quit by default with per-app hiding.

## Help link (2026-11-14)
- The menu's bottom-left "Help / Suggest Improvement" opens an email to labern@paradoxica.co.uk for now (`Maker.helpURL`).
- Later: it goes to the website, where a form lets the person send the message. Replace `Maker.helpURL` with that page once the Hub has built it.
