# パラドックス (paradokkusu)

An iOS app (SwiftUI) that pulls together the things Labern uses: a branded home
plus tabs for Tesla, Ring, and others. Built on macOS, runs on iPhone. Not started
yet in code. Read `docs/HANDOFF.md` first: it holds the design decisions, the
rejections, and what to do next.

## Rules for this project
- **Design is governed by Apple's Human Interface Guidelines.** Read
  `../ios/docs/APPLE-HIG.md` before any UI work (moved there: it is shared by every iOS app). If it is missing, build it first
  (see HANDOFF).
- Never put instructional hint text in the UI ("tap a tab, swipe to move"). No iOS
  app does this.
- Xcode project, automatic signing under Labern's team. Never hardcode a Team ID.
- To-do data: SwiftData, additive-only schema. Never lose a user's items.
- Clean is a **public** repo. No tokens, no account details. The moment real
  credentials config appears, graduate this folder to a private repo.

## Sub-agents
Use sub-agents for fan-out work: crawling and digesting documentation, parallel
independent investigations, and anything large or noisy. Keep the main thread for
design decisions with Labern.
