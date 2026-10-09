# Apple HIG — working digest (iOS)

Our own summary of Apple's Human Interface Guidelines, written for building iPhone apps.
Source: all 173 HIG pages, crawled 2026-10-09 (guidelines revised June 2026; Liquid Glass era).
Apple's raw text is not in this repo. To re-crawl: `python3 paradokkusu/tools/hig-crawl.py`
in a scratch directory. When this file and Apple disagree, Apple wins; re-crawl and fix this.

---

## 0. The ten rules that apply to every screen

1. **System font, system text styles.** SF Pro via `.font(.body)`, `.title`, etc. Never a fixed
   point size for running text. Dynamic Type must work up to AX5.
2. **Semantic colours, not hex.** `Color(.label)`, `.secondaryLabel`, `.systemBackground`,
   `.systemGroupedBackground`, `.separator`. Custom colours go in the asset catalog with light,
   dark, and increased-contrast variants.
3. **One accent colour, used sparingly.** Primary actions, selected tab, status. Not on body text,
   not on every control.
4. **Controls float on Liquid Glass; content sits under them.** No glass in the content layer.
   No custom bar backgrounds. Let content scroll under bars with the scroll edge effect.
5. **Hit targets 44×44 pt.** Absolute floor 28×28. ~12 pt gap around bezelled controls,
   ~24 pt around bezel-less ones.
6. **Text at least 11 pt; body defaults to 17 pt.** Avoid Ultralight/Thin/Light weights.
7. **Contrast ≥ 4.5:1** for text ≤17 pt; ≥ 3:1 for 18 pt+ or bold. Aim for 7:1 on custom colours.
8. **No instructional chrome.** No "tap here to…", no coach marks, no app logo sprinkled about,
   no splash advertising. The app should explain itself by being used.
9. **Standard components and gestures first.** Tap selects, swipe reveals/dismisses, long-press
   opens a context menu. Never repurpose a standard gesture. Every gesture needs an on-screen
   alternative.
10. **Light and Dark both shipped and tested,** plus Increase Contrast and Reduce Transparency /
    Reduce Motion. No in-app appearance toggle.

---

## 1. Principles (re-introduced June 2026)

Purpose, Agency, Responsibility, Familiarity, Flexibility, Simplicity, Craft, Delight.
The working ones:

- **Stay out of the way.** Take people straight to the content or task.
- **Simplicity isn't minimalism.** Keep what's needed close, let the rest fall away. Every element
  earns its place.
- **Familiarity.** Same look and behaviour for the same thing everywhere in the app.
- **Delight isn't decoration.** Pick the emotion the app should evoke and let it shape design;
  never let flourish block the task.
- **Craft.** Stunning visuals, smooth animation, precise wording. Keep current with the platform.

iPhone specifics: limit on-screen controls, put secondary actions one interaction away; the
middle and bottom of the screen are easiest to reach; support swipe-back and row swipe actions;
adapt to orientation, Dark Mode and Dynamic Type.

---

## 2. Colour

**System colours (iOS 26+ values, sRGB).** Use the API, never hard-code; values change between
releases. Listed so mockups match.

| Name | Light | Dark | Light, Increase Contrast | Dark, Increase Contrast |
|---|---|---|---|---|
| Red | 255 56 60 | 255 66 69 | 233 21 45 | 255 97 101 |
| Orange | 255 141 40 | 255 146 48 | 197 83 0 | 255 160 86 |
| Yellow | 255 204 0 | 255 214 0 | 161 106 0 | 254 223 67 |
| Green | 52 199 89 | 48 209 88 | 0 137 50 | 74 217 104 |
| Mint | 0 200 179 | 0 218 195 | 0 133 117 | 84 223 203 |
| Teal | 0 195 208 | 0 210 224 | 0 129 152 | 59 221 236 |
| Cyan | 0 192 232 | 60 211 254 | 0 126 174 | 109 217 255 |
| Blue | 0 136 255 | 0 145 255 | 30 110 244 | 92 184 255 |
| Indigo | 97 85 245 | 109 124 255 | 86 74 222 | 167 170 255 |
| Purple | 203 48 224 | 219 52 242 | 176 47 194 | 234 141 255 |
| Pink | 255 45 85 | 255 55 95 | 231 18 77 | 255 138 196 |
| Brown | 172 127 94 | 183 138 102 | 149 109 81 | 219 166 121 |

**System grays (iOS)**

| Name | Light | Dark |
|---|---|---|
| systemGray | 142 142 147 | 142 142 147 |
| systemGray2 | 174 174 178 | 99 99 102 |
| systemGray3 | 199 199 204 | 72 72 74 |
| systemGray4 | 209 209 214 | 58 58 60 |
| systemGray5 | 229 229 234 | 44 44 46 |
| systemGray6 | 242 242 247 | 28 28 30 |

**Backgrounds.** Two families, each primary / secondary / tertiary: `systemBackground` set for
plain views, `systemGroupedBackground` set for grouped lists. Primary = whole view, secondary =
groups within it, tertiary = groups within those. In Dark Mode the system swaps base (dimmer) for
elevated (brighter) when a view is in front (sheets, popovers); a custom background breaks this.
Dark-mode base is pure black (#000) for `systemBackground`; elevated and secondary step up through
the gray ramp (≈ #1C1C1E, #2C2C2E).

**Foreground.** `label`, `secondaryLabel`, `tertiaryLabel` (unavailable things), `quaternaryLabel`
(watermarks), `placeholderText`, `separator`, `opaqueSeparator`, `link`. Never reuse one for
another purpose (no separator-coloured text).

**Rules**
- Same colour never means two things. If the accent marks "tappable", don't use it on static text.
- Never rely on colour alone: add a symbol, shape, or label. Red/green and blue/orange are the
  common blind pairs.
- Brand colour: put it in the **content layer** (where it scrolls under glass and tints the bars
  automatically) rather than painting controls. On the glass layer, colour only the primary
  action's background, and only one control.
- If content is colourful, keep bars and button labels monochrome.
- Colourful content scrolling under controls is fine; its *resting* state must stay legible.
- Wide colour: Display P3, 16-bit PNG for images that benefit.
- Colours look darker outdoors and more saturated in the dark. Test both.

## 3. Dark Mode

- Respect the system setting. **No app-specific light/dark switch.**
- Permanent dark is allowed only for immersive media-style apps.
- Dark palette is not an inversion: dimmer backgrounds, brighter foregrounds.
- Contrast floor 4.5:1, target 7:1 for custom pairs, especially small text.
- Darken white-background images slightly so they don't glow.
- Test Dark + Increase Contrast + Reduce Transparency, separately and together.

## 4. Materials and Liquid Glass

- **Liquid Glass = the functional layer** (tab bars, toolbars, sidebars, floating buttons). It
  floats above content and takes colour from what's behind it.
- **Never use glass in the content layer.** Exception: sliders/toggles turn glassy while touched.
- Use it sparingly on custom controls; standard components get it for free.
- Two variants: **regular** (blurs, keeps text legible; default; use for anything with much text)
  and **clear** (very translucent; only over photos/video). Over bright media add a 35 % black
  dimming layer behind clear glass.
- Small glass elements flip light/dark automatically with the content under them; their symbols
  go monochrome dark-on-light or light-on-dark.
- In the content layer use the standard materials: ultraThin, thin, regular, thick, with the
  matching vibrant label/fill/separator colours. Don't put quaternary label on thin/ultraThin.
- Don't put a solid or semi-opaque fill under bars. Use the scroll edge effect (automatic style
  by default; one per view; only where content actually scrolls under floating UI).
- Full-bleed backgrounds extend under bars. If a bar would hide an important part of an image,
  use the background extension effect (mirrored blur).

## 5. Typography

- System font **SF Pro** (variable, dynamic optical sizes). **New York** is the serif companion.
  SF Pro Rounded, SF Mono and Condensed/Expanded widths exist. Don't embed them; use
  `Font.Design.default / .serif / .rounded / .monospaced`.
- **Default 17 pt, minimum 11 pt.** Thin custom faces need to be bigger.
- Prefer Regular, Medium, Semibold, Bold. Avoid Ultralight, Thin, Light.
- **Use as few typefaces as possible.** Custom brand font for headlines is acceptable; keep body
  and captions in the system font. Any custom font must support Dynamic Type and Bold Text.
- Hierarchy by weight, size and colour (label → secondaryLabel), not by adding fonts.
- Three or more lines: no tight leading.

**Text styles at the default size (Large)** — pt size / leading:

| Style | Weight | Size | Leading | Emphasised |
|---|---|---|---|---|
| Large Title | Regular | 34 | 41 | Bold |
| Title 1 | Regular | 28 | 34 | Bold |
| Title 2 | Regular | 22 | 28 | Bold |
| Title 3 | Regular | 20 | 25 | Semibold |
| Headline | Semibold | 17 | 22 | Semibold |
| Body | Regular | 17 | 22 | Semibold |
| Callout | Regular | 16 | 21 | Semibold |
| Subheadline | Regular | 15 | 20 | Semibold |
| Footnote | Regular | 13 | 18 | Semibold |
| Caption 1 | Regular | 12 | 16 | Semibold |
| Caption 2 | Regular | 11 | 13 | Semibold |

Range: xSmall Large Title 31 / Body 14 … xxxLarge Large Title 40 / Body 23; accessibility sizes
AX1 Body 28 … AX5 Body 53, Large Title 60. Build for AX5: stack horizontal rows vertically,
let rows grow, keep truncation minimal, keep primary items at the top.

**SF Pro tracking** (for mockups only; the system does this live): 11 pt +0.06, 12 pt 0,
13 −0.08, 15 −0.23, 17 −0.43, 20 −0.45, 22 −0.26, 24 +0.07, 28 +0.38, 34 +0.40, 48 +0.35,
64 +0.22, 80 0. Small sizes track looser, body tracks tight, display sizes open slightly again.

## 6. Layout

- Most important content top-leading. Align things to make them scannable; indent to show
  subordination. Group with space, containers or separators.
- Progressive disclosure over showing everything.
- Lay out by **size class** (compact/regular), never by device model or orientation.
- Respect **safe areas** (Dynamic Island, home indicator, bars) and system margins. (Not in the
  HIG text, but true of the frameworks: default readable margins are 16 pt on iPhone portrait,
  20 pt on the Plus/Pro Max widths. Use the system padding, don't hard-code.)
- Widgets: 16 pt standard margin, 11 pt for tight internal groupings.
- Corners of custom shapes inside bars/containers should be **concentric** with the container.
- Restore state on relaunch: last tab, scroll position.

## 7. Navigation

**Tab bar (iOS)**
- Navigation between top-level sections only. Never actions (that's a toolbar).
- Floats at the bottom on Liquid Glass; content shows through.
- Always visible across sections (a modal may cover it).
- Use as few tabs as do the job; **3–5 in practice**, five or fewer before overflow becomes "More".
  Avoid the More tab.
- Never hide or disable a tab; if it's empty, say why inside it.
- Single-word labels. SF Symbols, **filled** variants. System handles selected state.
- Badges (red oval, white number/!) only for genuinely critical/new things.
- Optional dedicated Search tab at the trailing end. Can minimise on scroll with an accessory
  (like Music's mini player).
- Bright colourful content → monochrome tab bar.

**Toolbars / navigation bars**
- Title, navigation (Back, search), and actions. Title under 15 characters; **never the app name**.
- Large title on root screens, collapses to inline on scroll.
- Standard Back and Close symbols; never the words "Back" or "Close".
- Borderless system symbols; no custom bar backgrounds or tinted items.
- One `.prominent` primary action (Done/Submit), trailing edge.
- Max ~3 groups. Separate text buttons with fixed space.

**Sheets**
- For a scoped task related to the current context. One sheet at a time.
- Cancel leading, Done trailing. Never all three of Cancel/Done/Back.
- Detents: medium (~half) and large. Show the grabber on resizable sheets. Swipe down dismisses;
  if there are unsaved changes, confirm with an action sheet.
- Long or complex flows: full-screen modal instead.

**Modality** — only with a clear benefit; short; obvious dismissal; title it with its task.

**Segmented control** — switches closely related subviews, ≤5 segments on iPhone, all text or
all icons, equal widths. Separate app sections are a tab bar's job.

**Page control** — sequential pages only, centred near the bottom, ≤~10 dots, system colours.

**Search** — bottom placement on iPhone when there's room; top when there's no bottom toolbar or
the bottom must belong to content.

## 8. Components

**Buttons**
- 44×44 pt hit region minimum; always a pressed state.
- One or two prominent (accent-filled) buttons per view, max.
- Distinguish preferred choice by style, not size.
- Labels: verb first, Title Case, e.g. "Add to Cart". Familiar SF Symbol where it reads better.
- Roles: primary (accent), cancel, destructive (red). Never give a destructive action the primary
  role.
- Slow actions: spinner inside the button, label can change ("Checking out…").

**Lists and tables**
- Default for text. Grouped style for settings-like data (`insetGrouped`).
- Disclosure chevron to drill in; info button only for extra details, never navigation.
- Persistently highlight the selected row when navigating a hierarchy; briefly highlight then
  checkmark when choosing options.
- Let people reorder where it makes sense. Swipe actions on rows.
- Switches only inside list rows; elsewhere use a toggle-style button.

**Alerts** — rare; never at launch; never purely informational if avoidable; never for common
undoable deletes. Specific button verbs ("Delete", not "OK"); "Cancel" always named Cancel;
default trailing / top; max three buttons.

**Action sheets** — choices following a deliberate action. Destructive item at top, Cancel at
bottom. No scrolling.

**Context menus** — long-press; short; ≤3 groups; one submenu level; destructive items last and
red; hide unavailable items; everything also reachable in the main UI. Context menu *or* edit
menu, not both.

**Progress** — determinate whenever possible; never stalled; spinner never morphs into a bar;
pull-to-refresh title only if it adds info (e.g. last updated), never instructions. Refresh
automatically too.

**Text fields** — placeholder plus a label; right keyboard type; Clear button trailing; validate
at the right moment; errors beside the field, phrased as what to do.

## 9. Icons and SF Symbols

- Use **SF Symbols** for interface icons: weight-matched to adjacent text, nine weights, three
  scales, auto Dark Mode and Dynamic Type.
- Rendering modes: monochrome, hierarchical (depth via opacity), palette, multicolor.
- Outline variant in toolbars and lists; **fill** in tab bars and swipe actions.
- Animations (bounce, pulse, scale, replace/magic replace, wiggle, breathe, rotate, draw on/off)
  only when they communicate something.
- Custom icons: same weight, detail, and perspective as the rest; vector; optical centring;
  accessibility label. No Apple hardware replicas. Symbols may not be used in logos/app icons.
- Standard actions: share `square.and.arrow.up`, add `plus`, more `ellipsis`, delete `trash`,
  done `checkmark`, cancel `xmark`, edit `pencil`, compose `square.and.pencil`, search
  `magnifyingglass`, filter `line.3.horizontal.decrease`, calendar `calendar`, account
  `person.crop.circle`.

**App icon**
- Built in **Icon Composer**: 1024×1024 px square layers, unmasked; system applies rounded mask
  and Liquid Glass (highlights, refraction, translucency).
- Background layer (solid or gradient) + one or more foreground layers with crisp edges.
- Simple, few shapes, centred. Text only if it's the brand. No photos, no UI screenshots.
- Don't paint your own shadows, bevels, glows.
- Ship default, dark, clear (light/dark) and tinted (light/dark) appearances; keep core features
  identical across them.

## 10. Branding

- Express brand through voice, accent colour, and optionally a headline font, inside familiar
  components.
- **Branding defers to content.** Don't spend screen space on a logo that does nothing.
- Don't repeat the logo through the app. Don't title screens with the app name.
- **The launch screen is not a brand moment:** it should look like the first screen, without
  text or logos unless they're a fixed part of that first screen.

## 11. Motion and haptics

- Motion has a purpose: feedback, status, continuity. Never motion for its own sake.
- Brief and precise. Follow the finger. Cancellable; never make people wait for an animation.
- No custom animation on very frequent interactions.
- Reduce Motion: tighten springs, swap slides for fades, no z-depth or blur animation.
- Haptics: use system patterns for their documented meaning (notification = outcome, impact =
  physical snap/collision, selection = value changing). Short, consistent, optional, paired with
  visuals.

## 12. Launch, onboarding, help

- Launch instantly. Launch screen ≈ first screen, no text.
- Ideally no onboarding at all; the app explains itself by being used. If needed: short,
  interactive, skippable, shown once, after launch.
- Prefer contextual tips (TipKit) near the relevant control over a tour. Never explain how
  standard components work.
- Ask permissions at the moment of use, not at launch, with a clear reason.
- Defaults should be right for most people; postpone setup.
- Restore previous state on relaunch.

## 13. Writing

- Decide the app's voice; vary tone by situation.
- Fewest words that are clear. Verbs on buttons ("Send", not "Let's do it!").
- Pick one capitalisation scheme per element type and keep it.
- Avoid "my/your" unless needed; never "we".
- Say "tap", not "click".
- Empty states: say what's possible next and offer the button.
- Errors: next to the problem, no blame, say how to fix ("Use at least 8 characters"),
  no "Oops".

## 14. Accessibility

- Dynamic Type to at least 200 % (AX sizes on iOS).
- Contrast table: ≤17 pt any weight 4.5:1; 18 pt+ 3:1; bold 3:1.
- Controls 44×44 (min 28×28), spacing 12 pt (bezelled) / 24 pt (bezel-less).
- Never colour alone. VoiceOver labels for every icon and custom control; headings for structure.
- Simple gestures; on-screen alternative to every gesture.
- No time-boxed UI that auto-dismisses.
- Reduce Motion, Increase Contrast, Reduce Transparency, Bold Text all respected.
- Support Voice Control, Full Keyboard Access, Switch Control (free with standard controls and
  good labels).

## 15. System integrations worth using

- **Widgets**: glanceable, dynamic, opens the app at the right place; system font and symbols;
  16 pt margins; light/dark; don't mirror the widget inside the app.
- **Live Activities**: tasks with a start and end; end them promptly; 14 pt Lock Screen margin;
  Dynamic Island corner radius 44 pt.
- **Home Screen quick actions, App Shortcuts, Siri**: expose the most common tasks; short
  phrases; SF Symbols, never emoji.
- **Notifications**: concise, actionable, never marketing without opt-in, no app name/icon in
  the body, badge = unread count only.
- **iCloud**: sync silently, keep state in iCloud, handle offline and conflicts quietly.
- **Settings**: few; task-specific options live with the task; never duplicate system settings
  (appearance, text size).

---

## How this applies to パラドックス

- Vertical tab spines are a custom navigation component. They must still obey: 44 pt minimum
  width per collapsed spine, labels in SF Pro, VoiceOver labels and an accessibility action per
  spine, and Reduce Motion fallback (cross-fade instead of fold).
- Brand colour belongs to the content layer (each spine's colour) not the bars.
- Logo appears once, on the home spine, because the mark *is* that screen's content. Nowhere else.
- No hint text, no splash, no onboarding.
- When the bottom tab bar arrives: 3–5 tabs, single-word labels, filled SF Symbols, Liquid Glass,
  monochrome if spines stay colourful.
