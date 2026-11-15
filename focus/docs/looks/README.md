# Focus desktop app — looks, version by version

Kept so a change can always be compared with what came before (his request, 2026-11-15: "Remember this for this
current version so we know what this looked like, before changing it").

## 0.18.39 (before the full-width top row)
- `0.18.39-session.png`, `0.18.39-session-live.png`, `0.18.39-mode.png`: drawn off-screen with sample modes.
- His own screenshot of it running (2026-11-15, in the conversation): a live session in "Research".
- Layout:
  - The logo and "Focus" sat at the top of the sidebar.
  - The Start/End Session button and its line sat at the top of the page column.
  - The sidebar's pages (Session, Shortcuts, Tools, History, Settings), then Modes, started under the logo.
  - The page heading started under the button's line, at a different height from the sidebar.
- Code: tag `focus-v0.18.39`, branch `focus/feat-desktop-app`.

## 0.18.40
- One top row across the whole window: the logo and "Focus" on the left, the Start/End Session button and its line on
  the right, on every page (modes included).
- Below it the sidebar and the page start on the same line.

## 0.18.43 — "a very good version" (his words, 2026-11-15)
- `0.18.43-session.png`, `0.18.43-session-live.png`, `0.18.43-mode.png`, `0.18.43-settings.png`: drawn off-screen.
- The look he approved:
  - The top row is the logo and "Focus" plus the full-width white Start/End Session button. Clicking it draws the website's line round the button; hovering lifts it, with a sheen and sparks.
  - The sidebar has Session Manager with an On/Off switch, Shortcuts, Tools, History and Settings, then Modes.
  - The sidebar foot is one row of Feedback · About · Manual, then the ★★★★★ × PARADOX™ lockup.
  - Panel names have a white full-width rule under them; there are no scroll bars; Text size is − / Default / +.
- Code: tag `focus-v0.18.43` (also tagged `focus-look-good`), branch `focus/feat-desktop-app`. To go back to exactly this:
  `git checkout focus-look-good -- focus/desktop.swift`.
