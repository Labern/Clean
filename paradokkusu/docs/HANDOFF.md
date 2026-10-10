# Handoff — 2026-10-09

Planning session moved from the Mac to the cloud. No app code exists yet.

## What Labern asked for
An iOS app that gathers his key things. First version is **a series of shortcuts with
a proper iOS layout**, not live integrations.

## Structure — APPROVED ("the structure is correct")
- **Vertical tabs** fill the screen side by side. One is open at a time; the rest fold
  to thin strips. Tap a strip to open it.
- **Tab 1, the default on launch:** the ★★★★★ × PARADOX mark in its *vertical Japanese*
  form: five stars stacked, ×, パラドックス running down. All white stars, all white ×,
  all white text.
- **Tabs 2–5:** each a different colour, with its name written horizontally and rotated
  90°, so it reads left to right if you tilt your head.
- **Tesla tab:** a to-do list of things to do for the car (fix this, wash this, get
  that). Not the Tesla app, no API.
- **Ring tab:** just a Ring page or a button that opens the Ring app. The Mac is not
  always on, so no local daemon. The Ring account may be connected later.
- **No bottom row for now.** In future there will be one: iOS apps always have 3–5
  items at the bottom (a tab bar).
- **App name:** パラドックス.

## Visual design — REJECTED ("Heinous design… colours and font are AWFUL")
`design/mockup-v4.html` / `.png` is the rejected version. Keep its structure, throw
away its look. What was wrong, as far as stated:
- The colours (flat teal / pink / green / gold strips taken from the PARADOX terminal
  palette).
- The fonts (serif titles + JetBrains Mono rows + Mincho).
- A footer line explaining how to use the app. Removed for good; see CLAUDE.md.
He did not say what the right colours and fonts are. Do not guess a third time
without grounding it in Apple's guidelines first, which is the next task.

Original brief also said: black and white base, the logo set as the key, bold and
interesting, with visuals.

## Next tasks, in order
1. **DONE (cloud, 2026-10-09):** all 173 HIG pages crawled and read; digest written to
   `docs/APPLE-HIG.md` (since moved to the iOS repo: `iOS/docs/APPLE-HIG.md`, crawler `iOS/tools/`). **Still to do on the Mac:** follow `docs/global-claude-section.md`
   (copy the digest to `~/.claude/APPLE-HIG.md`, append the block to `~/.claude/CLAUDE.md`).
   Original instruction, for reference:
1. **Apple design docs.** He said: "Pull from the Apple Design docs, suck it all up,
   and add it to the global Claude.md so we can pull from it. Do that first then come
   back to me."
   - `tools/hig-crawl.py` crawls all 173 Human Interface Guidelines pages from Apple's
     JSON endpoint into `md/*.md` (about 1.4 MB). Run it in a scratch directory. Do
     **not** commit Apple's raw text: this repo is public.
   - Read the iOS-relevant pages in full (design principles, designing for iOS, color,
     dark mode, materials, typography, layout, branding, app icons, SF Symbols, tab
     bars, toolbars, sidebars, buttons, lists and tables, sheets, gestures, motion,
     accessibility, launching, onboarding, feedback, writing, widgets, and the rest of
     the components). The guidelines were revised in June 2026, including Liquid Glass.
   - Write a digest in our own words to `docs/APPLE-HIG.md`: concrete rules and numbers
     (type sizes, touch targets, margins, tab bar rules, colour and contrast rules).
   - **The global file lives on the Mac at `~/.claude/CLAUDE.md` and cannot be edited
     from the cloud.** So: put the digest in this repo, and on the next Mac session copy
     it to `~/.claude/APPLE-HIG.md` and add a short section to the global CLAUDE.md that
     points to it and states the handful of always-on rules. Tell Labern this plainly.
2. **Come back to him** with a redesigned look built on those guidelines, same
   structure. Show it as a picture he can open on his phone.
3. Only after he approves the look: bootstrap the Xcode project here and build the
   shell with mocked data.

## Brand assets (on the Mac, not in this repo)
- Logo library: `~/Documents/Codex/2026-09-17/t/outputs/PARADOX_Logo_Library/`
  16 designs × 11 colour treatments, SVG and PNG. The vertical Japanese ones are
  designs 10 (compact), 11 (spaced), 12 (small type), 13 (stars across).
  `design/logo-vertical-variants.png` shows designs 06, 10, 11, 12, 13 side by side.
- The library's own colours: black, white, lavender `#836BB7`, purple `#5A4A92`,
  deep purple `#462D7D`.
- Style specs: `~/Desktop/★★★★★/STYLE.md` (PARADOX terminal) and `MONOGRAPH.md`.
- Mockup artifact: https://claude.ai/artifact/Msu1bt8w3iEdCUwPN4swNi

## Facts about the Mac
Xcode 27 installed. iPhone 17, 17 Pro, 17 Pro Max, Air, 17e simulators available.
