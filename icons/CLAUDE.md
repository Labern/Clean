# Icons

An iPhone app for designing app icons from the ★★★★★ × PARADOX marks, and for
wearing them as its own Home Screen icon. Spun off from PARADOX HQ's icon
designer (Company › Settings › Create custom app icon) on 2026-11-18; HQ keeps
its own copy.

## Layout (Labern/iOS pipeline)
- App: `ios/`. `project.yml` is the source of truth; the `.xcodeproj` is generated
  and gitignored. Swift 6, iOS 26, bundle `com.labern.paradox.icons`.
- On the Mac: `~/Desktop/Clean/iOS/bin/ios-run ~/Desktop/Clean/icons/ios`;
  tests: `bin/ios-test ~/Desktop/Clean/icons/ios`. After pulling new source files,
  run `xcodegen generate` in `ios/` first (ios-run can reuse a stale project).
- Cloud: `.github/workflows/icons-ios.yml` builds, tests and screenshots the shelf
  and the designer on any push touching `icons/ios/`, then force-pushes results to
  `ci/icons`. Launch argument: `-screen designer` opens straight on the artboard.

## How it works
- **Shelf** (`RootView.swift`): the app's own icon ("Original"), every icon you've
  made, then "New". Tap to wear; hold to Share the 1024px PNG or Delete. The ring
  follows `IconShelf.wearing`, never a copy held in the view.
- **Designer** (`IconDesigner.swift` + `Resources/IconDesigner/`): `designer.html`
  runs in a `WKWebView` with `logos.js`, a copy of `logo-experiments/logos.js`
  (generated: never edit it, re-copy it). SwiftUI draws the controls and calls
  `window.D`; the page answers on the `designer` message handler. Everything is a
  fraction of the board's side, so the 1024px save is exactly what was on screen.
- **Saving** flattens to a 1024px PNG with no alpha (`IconShelf.flatten`) and keeps
  it with its recipe in Application Support/Icons.
- **iOS only wears icons the app was built with.** A new icon shows as "Next
  install": tapping marks it `wanted`. The app copies every icon into
  `Icons to bake` inside the folder chosen under •••. `design/bake_custom.sh`
  (XcodeGen `preGenCommand`) turns each `<id>.png` in `design/custom/` or any
  `Icons to bake` folder in iCloud Drive into an `AppIcon-Custom-<id>` set listed in
  `Custom.xcconfig`. The first time that build becomes **active** it puts the wanted
  icon on (`IconShelf.adopt`). Verified end to end in the Simulator 2026-11-18.
- **Gotcha:** `setAlternateIconName` fails silently before the scene is active, so
  `adopt()` runs on `scenePhase == .active`, not in `.task` at launch.
- Never commit PNGs into `design/custom/` by accident: every one is baked into
  every build.

## Theme
`Theme.swift`: HQ's palette (black ground, off-black surfaces, one hazard red),
every colour with a dark and a light value, read from `@Environment(\.theme)`.
`.paradox` is the alternate. `ThemeTests` checks every ink against every ground
in both appearances: no white on white.

## Work with sub-agents
Delegate fan-out searches, independent parallel work, and noisy or large
investigations (CI logs, comparing with HQ's copy, sweeping the logo set) to
sub-agents, and keep the main thread for decisions and the code itself.
