# パラドックス (paradokkusu)

An iOS app (SwiftUI) that pulls together the things Labern uses: a branded home
plus spines for Tesla, Ring, Spotify and Diary. Read `docs/HANDOFF.md` for the design
history and rejections.

**Purpose:** everything Labern reaches for, on one shelf, one thumb away.
**Feeling:** assured.

## Layout (Labern/iOS pipeline)
- App: `ios/` — `project.yml` is the source of truth; the `.xcodeproj` is generated
  (`xcodegen generate`) and gitignored. Swift 6, iOS 26, bundle `com.labern.paradox`.
- On the Mac: `~/Desktop/Clean/iOS/bin/ios-run ~/Desktop/Clean/paradokkusu/ios`.
- Cloud: `.github/workflows/paradokkusu-ios.yml` builds, tests and screenshots every
  spine, then force-pushes results to the `ci/paradokkusu` branch
  (`git fetch origin ci/paradokkusu`). `-openSpine N` (0 home … 4 diary) opens a spine
  at launch.
- `Sources/`: `Shelf.swift` (spines, strips, lockup), `Components.swift` (page
  scaffold, cards, buttons, to-dos), one file per spine page, `Models.swift`
  (SwiftData), `Seed.swift` (first-launch examples), `Theme.swift` (pigments).

## Visual language
- Spine colours are traditional Japanese pigments: 紅緋 benihi (Tesla), 群青 gunjō
  (Ring), 常磐 tokiwa (Spotify), 山吹 yamabuki (Diary), 藤紫/菫 for home. Pigment name
  sits at the head of each strip and beside each title.
- SF Pro for all UI; Hiragino Mincho only for the mark (★, ×, kana).
- Flourishes: stars arrive one by one on launch; book-spine shading and cord bands on
  strips; a slow mesh-gradient wash of the pigment behind each page; the spine's name
  in katakana down the trailing edge; Mincho ★ day rating in the journal.
- Read-only at the top, everything touchable in the bottom half.

## Rules for this project
- **Design is governed by Apple's Human Interface Guidelines.** Read
  `docs/APPLE-HIG.md` before any UI work. If it is missing, build it first
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
