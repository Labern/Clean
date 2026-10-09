# To install on the Mac

The cloud can't write to `~/.claude/`. On the Mac, run:

```sh
cp ~/path/to/Clean/paradokkusu/docs/APPLE-HIG.md ~/.claude/APPLE-HIG.md
```

Then append the block below to `~/.claude/CLAUDE.md`.

---

## Apple design (any iOS / iPadOS / macOS / watchOS UI)

Full digest: `~/.claude/APPLE-HIG.md` (from Apple's HIG, Liquid Glass era). Read it before any
Apple-platform UI work. Always-on rules:

- SF Pro via system text styles (`.body`, `.headline`…); Dynamic Type to AX5. Body 17 pt, never
  under 11 pt. No Ultralight/Thin/Light. Fewest typefaces possible.
- Semantic colours (`label`, `secondaryLabel`, `systemBackground`, `separator`). Custom colours
  need light, dark and increased-contrast variants. Contrast ≥ 4.5:1, aim 7:1.
- One accent colour, used only for primary actions, selection and status. Brand colour lives in
  the content layer, not on bars.
- Liquid Glass only for floating controls/navigation, never content. No custom bar backgrounds.
- Hit targets 44×44 pt (floor 28). Standard components and gestures before custom ones.
- Tab bar: 3–5 tabs, single-word labels, filled SF Symbols, navigation only, never hidden.
- Nav titles < 15 chars, never the app name. Standard Back/Close symbols.
- No instructional hint text, no tours, no splash, no logo repeated through the app. Launch
  screen = first screen without text.
- Light and Dark both supported; no in-app appearance switch. Honour Reduce Motion, Increase
  Contrast, Reduce Transparency, Bold Text, VoiceOver.
- Buttons: verb labels, ≤ 2 prominent per view, destructive never primary.
