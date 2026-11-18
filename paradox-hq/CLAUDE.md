# PARADOX HQ

The iOS app (SwiftUI) that runs ★★★★★ × PARADOX from the phone: what came in,
what needs a decision, and what every project needs next.

**Lives here for now.** Clean is public; this folder moves to the company's
private repo as soon as that exists. Until then: no keys, no tokens, no account
details in any file. The Stripe key and the feed token are typed into the app
and kept in the Keychain on the phone.

## Layout (Labern/iOS pipeline)
- App: `ios/` — `project.yml` is the source of truth; the `.xcodeproj` is generated
  (`xcodegen generate`) and gitignored. Swift 6, iOS 26, bundle `com.labern.paradox.hq`.
- On the Mac: `~/Desktop/Clean/iOS/bin/ios-run ~/Desktop/Clean/paradox-hq/ios`.
  **After pulling new source files, run `xcodegen generate` in `ios/` first.** `ios-run`
  reused a stale project when only sources changed (`project.yml` untouched) and the
  build failed with "cannot find 'NotesView' in scope" (2026-11-17).
- Cloud: `.github/workflows/paradox-hq-ios.yml` builds, tests and screenshots every
  screen on any push that touches `paradox-hq/ios/`, then force-pushes the results to
  `ci/paradox-hq` (`git fetch origin ci/paradox-hq`). `result.txt` holds the compiler
  errors. Launch arguments: `-unlocked YES -sampleNotes YES -screen lock|today|projects|project|cards|notes|note|money|company|widgets|designer`
  (`cards` is the Projects pane).

## The five tabs
Today · To-do · Notes · Money · Company. (Six would push one behind a "More" button.)
- **Notes** — a proper notebook. Chips filter to one project's notes; a note's menu
  turns it into a to-do (title becomes the line, the rest its note) on its project,
  or on My list. Plain text, the first line is the title, saved as
  typed. Search (every word must appear), pin, file under a project, share, delete.
  **Done:** swipe a note right for its options; a full swipe marks it done (`Note.set
  (done:)`, which touches nothing else). A done note is crossed out with a green tick
  that lands with hit stop, and moves to the **Done** list at the bottom, latest first;
  tapping that list's heading folds it away and back (remembered). Undo by tapping the
  tick, swiping again, or the note's own menu.
  A bar chart of notes started per day, scrubbable. An untouched new note deletes
  itself. Notes live on the phone only (`Note` in SwiftData; never name a stored property `updated`, `inserted` or `deleted`, the store reads them back empty). The model is ready
  for iCloud but that isn't switched on.
- **My list** — one `Project` with `isPersonal` set, named "My list" (renamed from
  "Me" on launch), always first, never sent to the feed, never deletable. Today shows
  it whole (`MyListCard`): type to add, tick, fold, tap a line to open its page.
- Each project page ends with its own notes.
- **Today** — the mark, today's takings over a 30-day trend, this month and the
  Stripe balance, *Needs you* (disputes, failed payments, deadlines inside 30 days,
  the site being down; hidden when empty), and the next open line of each project.
- **Money** — revenue by week, month, quarter or year against the same stretch of
  the period before; subscribers and monthly recurring; payouts; every payment.
- **To-do** (was Projects) — a switch at the top: To-do (My list, the default) and
  Projects. Each project has a Focus list (`TodoViews.swift`). Lines nest to any
  depth. Ticking a line ticks everything under it; ticking the last open sub-item
  ticks its parent, all the way up; reopening reopens every line above. A line with
  sub-items shows a done/total count that folds them (`collapsed`, stored). Swipe
  right on a line to type sub-items straight under it; long-press to put it under
  the line above, move it out a level, give it a due date. Tapping a line opens its
  page (`ItemPage`): title, note, due date, its sub-items (each opens its own page,
  drag to reorder), done, delete. `Outline.rows` flattens the tree for drawing and
  is tested. The tally counts the smallest lines at any depth.
- **Everything in To-do drags.** Hold a line or a project card, then drag it up or
  down; it lands with a thud (`Thud.play`). A line takes its sub-items along and
  stays where it is let go (`Outline.move`, tested): between two sub-items it becomes
  one, just under a line whose sub-items are showing it becomes the first, and where
  a gap could be either level it keeps its own. Lists are `List` + `.onMove`
  (`OutlineSection`, the Projects pane, a line's own page); the My list card on Today
  is not a `List`, so its lines use `.draggable` / `.dropDestination` and a line
  dropped on another takes its place. Projects keep `order` 0…n; My list stays below 0.
- **Company** — Links (Home, Focus, Google Workspace, Stripe, GitHub, Claude, Tesla;
  each with its company's logo as an app-icon tile, and App and Web buttons), filing
  deadlines, the connections, Settings (Auto/Light/Dark, app icon), the Face ID lock,
  Backup.

## Links: logos and opening the app
- **Logos** are `Logo-*` image sets drawn by `LogoTile` (full-square art, corners cut
  in the app at iOS's 22.5%). Built by `ios/design/logos/make_logos.py` from the
  companies' own outlines (simple-icons, the four-colour Google G, Focus's site icon)
  on the ground each app icon uses. Home uses the app's own icon. Never redraw one.
- **App** tries `QuickLink.app` in order and says "Couldn't open the app" only when
  every address fails. An https address is opened with `universalLinksOnly`, so it
  must be a path the app has claimed in the site's `apple-app-site-association`
  (read it at `https://app-site-association.cdn-apple.com/a/v1/<host>`). Apps refuse
  their site's bare home address: `dashboard.stripe.com` and `claude.ai` both failed
  with "App not installed" (2026-11-17) until they became `/dashboard` and `/new`.
  Tesla's is `/1/app/home`. `LinkTests` holds this.

## Look, light and dark
Every colour is an `Ink` token with a dark and a light value (`Shared/Theme.swift`);
views never use `.white`/`.black`. `Ink.head` for headings and figures, `Ink.button` /
`Ink.buttonInk` for the one solid button, `Ink.tint(hex)` for project colours (white
means "no colour" and becomes `Ink.head`). `InkTests` checks every pairing's contrast in
both appearances: no white on white, no black on black. Appearance is `@AppStorage
("appearance")` auto/light/dark. Focus-site touches: uppercase tracked eyebrow labels
(`SectionHeader`), figures at medium weight that tick (`.figure`), cards rising in once
per launch (`.rise`), the mark's "hunt" hit stop on Today (`.hunt`), the ground fading
under the status bar (`.statusBarFade`). "PARADOX Dashboard" on Today: the word sits on
the wordmark's baseline, stepped back into the space the mark keeps for its ™.

## Today's header and the profile
One row, one thing (`TodayHeader`): the mark and "Dashboard" on the left, the profile
hard against the right edge, centred on each other; the photo is the mark's height.
"Dashboard" is always in Graphik, on the wordmark's baseline. `ViewThatFits` gives
narrower phones a smaller mark, then drops the word. Labern, 2026-11-18, of the first
version (profile floating on a row of its own): "This is a mess."
`Sources/Profile.swift`. `[photo] Labern / Founder & Director`, laid out like the Claude
app's account row. Tap the photo to change it (`PhotosPicker`), and place it in its
circle: three sliders (zoom, left and right, up and down) and dragging or pinching the
photo itself (`Framing`, tested). A tall photo has no room sideways until it is zoomed.
A new photo is framed on the face automatically (Vision), or on head and shoulders. Tap the role for the list of
hats (`Profile.roles`: Founder & Director, Writer, Programmer, Actor, Designer,
Filmmaker) or "New role" to add one; the change lands with hit stop. Everything stays
on the phone: the photo in Application Support/Profile, the rest in UserDefaults. **No
photo of Labern is in this repo**, which is public. His photo sits on the Mac at
`ios/Resources/Private/profile.jpg` (gitignored); a build made there carries it, and the
app wears it, framed on the face, until he picks another on the phone.

## Typeface
`Sources/Typeface.swift`. Every font in the app is `Face.at(size, weight)` or
`Face.style(.body, weight)`, never `.system` or `.body` directly, so Company › Settings ›
Typeface (SF Pro / Graphik) changes the whole app. **Graphik's files are not in this
repo** (licensed, and the repo is public): they sit on the Mac in
`ios/Resources/Private/` (gitignored) and `Face.load` registers whatever the build
carries. A build without them is in SF Pro and hides the setting.

## App icons
Main icon = the app's own mark scaled to 90% width (`design/icons/classic-max-black.png`).
Eight alternates (`AppIcon-*` sets, `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`),
previews in `IconPreview-*` image sets, chosen in Company › Settings. Renders come from
the brand SVG masters via `design/icons/make_icons.py`; never redraw the mark.

## Icon designer (Company › Settings › Create custom app icon)
Made to be lifted out as its own app: `Sources/IconDesigner.swift`,
`Resources/IconDesigner/` and `design/icons/bake_custom.sh` are all of it.
- **The artboard is the logo playground.** `designer.html` runs in a `WKWebView` with
  `logos.js`, a copy of `logo-experiments/logos.js` (generated: never edit it, re-copy
  it). One finger moves, two fingers size and spin, the centre lines and every 45° snap
  with a tick. SwiftUI draws the controls (mark, ground, copies, turn, reset) and calls
  `window.D`; the page answers on the `designer` message handler. Everything is a
  fraction of the board's side, so the 1024px save is exactly what was on screen.
- **Saving** flattens to a 1024px PNG with no transparency (`IconShelf.flatten`) and
  keeps it with its recipe in Application Support/Icons (`IconShelf`).
- **iOS only wears icons the app was built with** (`setAlternateIconName` takes a name
  from the bundle, never a picture). So a new icon shows in the picker as "Next
  install": tapping it marks it `wanted`; the app copies every icon into
  `PARADOX icons` inside the backup folder; `bake_custom.sh` (XcodeGen `preGenCommand`,
  so every `ios-run`/`ios-device`) turns each `<id>.png` it finds there, or in
  `design/icons/custom/`, into an `AppIcon-Custom-<id>` set and lists them in
  `Custom.xcconfig` → `$(CUSTOM_APPICONS)`; the first launch of that build puts the
  wanted icon on (`IconShelf.adopt`). The cloud build proves the bake with a stand-in
  picture (`ci.txt`: "custom icon baked into the app: yes").
- Not verified on the Mac yet: the script finding the folder in iCloud Drive
  (`~/Library/Mobile Documents/com~apple~CloudDocs`, up to four levels down). If it
  doesn't, drop the PNGs (Share from the icon's menu) into `design/icons/custom/`.

## Face ID
Asks only when the app has been out of use longer than "Ask again after" (default 1 hour),
measured across launches (`lock-last-seen`). Unlock is only attempted while the scene is
active (asking earlier fails and shows "Try again").

## Backups (the safety net until iCloud sync)
`Backup.swift`: the whole store as one JSON `BackupFile` (projects with lines at every
depth, notes, deadlines). You pick a folder once (iCloud Drive recommended; kept as a
security-scoped bookmark); a copy is written every time the app goes to the background,
one file per day (`PARADOX yyyy-mm-dd.json`), the newest 30 kept. Restore replaces
everything after first writing a "before restore" copy. **iCloud sync proper** needs the
paid team: add the iCloud/CloudKit entitlement and container in `project.yml`; the
`ModelContainer` uses the default (automatic) CloudKit setting, and every model property
is already defaulted and optional-safe for it.

## Free Apple ID builds
`ios-device` builds for the specific phone (registers it) and, if the team can't sign
App Groups, rebuilds without entitlements (widgets then get no data). First install
needs the cable once and Settings › General › VPN & Device Management › Trust.

## Feed and the phone's edits
The feed renames a line/project only when the feed's own wording changed
(`remoteTitle`/`remoteName`), matches lines at any depth (moving one doesn't duplicate
it), never re-adds lines deleted on the phone (`Tombstones`, via `remove(from:)`), and
ticks through `set(done:)` so the tree cascades.

## Sources
- `Stripe.swift` — Keychain, Stripe's JSON, the client. **Read-only**: there is no
  call in the app that can move money. Charges are required; balance, payouts,
  disputes and subscriptions are each left empty if the key can't read them.
- `MoneyStore.swift` — `Period`, `Ledger` (all the sums, pure and tested), the
  example figures, the store. Example figures are deterministic and always labelled.
- `Feed.swift` — the Claude feed (below), the first-launch seed, the site check.
- `Models.swift` — SwiftData: `Project`, `FocusItem`, `Deadline`. Additive-only
  schema, every property defaulted. Never lose a line.
- `Lock.swift` — Face ID / passcode at launch and after 30 seconds away. The mark
  covers the app in the app switcher.
- `Theme.swift`, `Components.swift` — the look.

## The Claude feed
`ios/Resources/feed.json` is the list of projects and their Focus lines. It seeds
the first launch, and it is the file a Claude session edits to put work on the
phone: add a project, add a line, set `"done": true`. The app pulls the hosted copy
(address set in Company ▸ Claude; a token there reads it from a private repo through
GitHub's contents API) on every open and on pull-to-refresh.

Merging only adds and ticks. It never unticks a line, never deletes one, and never
touches a project made on the phone. Ids are permanent: change a line's wording by
keeping its id; a new id is a new line.

## The look
The Focus site's tokens (black, `#1A1A1A` surfaces, white and greys, one hazard red
`#ED4E3B`), with the Focus icon's violet `#A78BFA` and green `#5FD7AF`. Headings are
large and white with a white line under. Solid white is the one primary button on a
screen. SF Pro throughout. Dark only: the brand is the black box.

**The mark is never redrawn.** `Mark.imageset/mark.svg` is ★★★★★ × over PARADOX with
™ top right, built from the outlines in `logo-experiments/logos.js`. The proper
masters are on the Mac at `~/Documents/Codex/2026-09-17/t/outputs/PARADOX_Logo_Library/`;
swap the master in when on the Mac. Do not adjust spacing, order or glyphs.

## Rules
- **Merge without asking.** Labern, 2026-11-18: "I'm not doing any code: auto-merge
  latest version every time unless I say not to." Finished work goes straight into
  the branch the Mac builds from (`claude/dazzling-cerf-y7p4jg` today). Don't ask.
- **Hit stop.** Labern loves it and wants it wherever it can go: at the moment of
  impact, freeze for a few frames, then carry on. A direct descendant of Smash
  Brothers. Use it for ticks landing, figures arriving, the lock opening; pair it
  with a haptic; honour Reduce Motion. This rule travels with the project to its
  new repo.
- **Graphs scrub with a haptic.** Dragging along any chart reads off each point,
  with a selection tick each time the finger crosses onto another (`Ledger.pick`,
  `chartXSelection`, `.sensoryFeedback(.selection, …)`). Every new chart gets this.
- Apple's Human Interface Guidelines govern the design: `paradokkusu/docs/APPLE-HIG.md`.
- No instructional hint text in the UI.
- Xcode project, automatic signing under Labern's team. Never hardcode a Team ID.
- Tests are Swift Testing (`ios/Tests`), run by the cloud build.

## Widgets, notifications, two-way feed
- **Widgets** (`Widgets/`, target `ParadoxWidgets`): Home Screen small and medium,
  Lock Screen rectangular, circular and inline. The app writes one `WidgetSnapshot`
  into the App Group `group.com.labern.paradox.hq` (`Bridge.publish`) and reloads
  the timelines; the widgets only draw it and never hold the Stripe key. The views
  live in `Shared/` so the app can show them too: `-screen widgets` is the gallery
  the cloud build photographs.
- **Notifications** (`Herald.swift`): no server. iOS wakes the app in the background
  (`Background.run`), it asks Stripe what's new since it last looked (`Herald.digest`,
  pure and tested) and posts local notifications. That makes them minutes to hours
  late, never instant. The first look at an account says nothing. Deadline reminders
  are calendar notifications at 09:00, seven days and one day before.
  The Stripe key is stored after-first-unlock so this works while the phone is locked.
- **Two-way feed**: when the feed address is a GitHub link (page, raw or API form)
  and the token can write, `FeedSync.pull` also sends back ticks and lines made on
  the phone (`Outbox.plan` → `FeedPatch.apply` → a commit through the contents API).
  New lines get ids starting `phone-`. Unticking is never sent.
- **Customers** are derived from the payments (`Ledger.customers`), grouped by name.
- **Charging by hand** opens Stripe's own invoice and payment-link pages; the key in
  the app stays read-only on purpose.

## Not verified yet (needs the Mac or a live account)
- Widgets on a real Home Screen: the App Group needs signing under Labern's team.
- Background notifications arriving: the Simulator doesn't run background refresh
  on its own (Xcode ▸ Debug ▸ Simulate Background Fetch triggers it).
- The commit back to GitHub, and Stripe with a live key.

## Not built
Instant payment notifications. They need Stripe's webhook to reach Apple's push
service: the webhook already lands on the site (`/api/stripe/webhook`, in
Labern/paradoxica-hub), so that is where the push would be sent from, with an APNs key.
