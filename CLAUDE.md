# CLAUDE.md

## Project
Strata — a macOS app that visualises Claude conversation history as a
heatmap (Timeline tab) and bubble chart (Themes tab). Built in Swift/SwiftUI,
no external dependencies, single `swift build` step.

## Structure
- `Strata/Sources/Strata/` — SwiftUI views and app-level model (`HeatmapModel`, `HeatmapView`, `App`)
- `Strata/Sources/StrataCore/` — pure logic: `Heatmap.swift` (matrix + bubble building, grouping), `ThemeExtractor.swift` (TF-IDF), `Models.swift`, `Loaders.swift`, `ConversationCache.swift`
- `Strata/build_app.sh` — builds and installs to `/Applications/Strata.app`
- `Strata/Package.swift` — Swift package manifest

## Commands
```
cd Strata && bash build_app.sh   # build + install
open /Applications/Strata.app   # launch
```

## Conventions

### Never use arbitrary display caps
Do NOT hardcode small limits on how many items are shown (themes, bubbles,
rows, results, etc.). If a count needs a default, start high (200+) or expose
it as a user-facing control. Never silently discard data with a magic number
like 18 without asking first. When in doubt: assume the user wants to see
everything, and let them dial it down.

### UI controls over constants
Any limit that affects what the user sees should be a live UI control (stepper,
slider, picker) rather than a code constant. The "Subjects" stepper in the
header is the model for this: range 10–500, default 200, updates live.

### Visual style
Dark navy/indigo background, teal/violet/pink accent palette, glassy cards.
`accentRamp()` in `HeatmapView.swift` is the canonical colour function — use
it for any new data visualisation.

### Theme grouping
`groupBubbles()` in `Heatmap.swift` classifies bubble themes into named
groups (Cars & Transport, People & Relationships, Work & Building, etc.)
using substring-aware keyword matching. When adding groups, think about what
the TF-IDF extractor actually surfaces — proper nouns, bigrams, diagnostic
terms — not just generic dictionary words.

## Gotchas
- The app reads conversation data from `~/Library/Application Support/` and
  a local claude.ai web sync cache. Requires login for claude.ai data.
- `screencapture` + `osascript activate` sometimes loses focus to other apps;
  confirm frontmost process before screenshotting.
