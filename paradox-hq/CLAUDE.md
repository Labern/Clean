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

## Cards can be rearranged (Work, Money, Company)
`Sources/Layout.swift`. Every card on those tabs sits in an `Arranged` wrapper: hold it,
drag it onto another card, and it takes that card's place; a line across the top of
the target shows where it will land. The order is kept per tab (`layout-work`,
`layout-money`, `layout-company`), survives cards being added or removed later
(`Layout.order`), and Company › Settings has "Put every tab back in its original
order". **What ships is only the default**: add a new card to the tab's list in
`Layout` and to the tab's `switch`, never as a fixed view above or below the loop.
A card carries the payload `card:<id>`, so it is never mistaken for a to-do line.

## The five tabs
Work · To-do · Notes · Money · Company. (Six would push one behind a "More" button.)
"Work" was "Today" until 2026-11-18; in code it is still `TodayView` and `Screen.today`.
- **Work card** (`Work.swift`, `WorkViews.swift`), first thing on the Work tab: versions
  pushed, published, and messages sent to Claude, for a stretch chosen along the
  bottom: Hour, Session (the current Claude conversation), Today, Week, Month. The
  switch at the bottom left makes those the last 24 hours, 7 days and 30 days
  (`WorkSpan`, tested). The graph switches between Pushed, Claude and Writing, is cut by
  the hour or the day to suit, and scrubs with a haptic; under it, what was done in the
  chosen bar. Tapping the card's heading folds it down to its three figures.
  `WorkLog` is the way in to everything: each version at its time as "Added: …",
  "Fixed: …", "Styled: …". Lines are one line until tapped (then the commit's bullets
  show), a day's heading folds the day, and Expand/Contract does all at once.
  - **Every change leads back to its conversation.** A commit that carries
    `Claude-Session: https://claude.ai/code/session_…` keeps that address in its
    `WorkEntry.session`. **Opening Claude is an option, never the tap**: tapping a
    line on the card opens that day's work, as it always did; "Open in Claude" is a
    button on the opened line and in the menu when the line is held. It opens the
    conversation in the Claude app, which claims `/code/*`. (Tap-opens-Claude was
    shipped and rejected the same day, as was a Claude logo on the lines.) **Always
    end commit messages with the Claude-Session trailer**, or the link is lost.
  - **Real data only.** Example work exists for the cloud build's screenshots and is
    behind `-unlocked YES -sampleNotes YES`; the phone never shows it.
  - **GitHub** (Company › Connected to › GitHub). Without a token GitHub allows 60
    questions an hour, and the first reader spent about 50 on every refresh, so refresh
    was refused most of the time and the spans disagreed (2026-11-18). It now asks one
    thing first, `users/<owner>/events/public` (with a token `users/<owner>/events`,
    which adds private work), stops at the last event it has already seen
    (`Progress.lastEvent`), and reads `commits?sha=<branch>&since=` only for branches
    whose head moved (`GitHubWork.moved`). A refresh with nothing new costs one
    question. It reads at most every 4 minutes (1 with a token); pull to refresh forces
    it; a refusal waits until GitHub's own `X-RateLimit-Reset`; a failed read keeps what
    was there. New entries are merged into the saved ones, never replace them. Merges,
    `ci/` and `stats/` branches and robots are left out. The card's foot says how fresh
    each source is (`WorkCard.freshness`).
  - **That activity feed can run minutes to hours behind a push**, which left the newest
    work off the card. So the repo worked in most recently (eight of them with a token)
    is also asked for its branches as they stand now (`repos/<repo>/branches`, one
    question), and any whose head differs from the one last read is read at once
    (`GitHubWork.moved(_:repo:heads:)`, tested). Branches never read before may be old,
    so only three of those are taken up per read.
  - **Hour is the last sixty minutes**, never "since the clock struck": that read 0 for
    most of every hour (Labern, 2026-11-18: "it always shows 0").
  - **Private work is invisible without a token** (Company › Connected to › GitHub):
    the dashboard site in `paradoxica-hub` and the iOS pipeline are private repos.
  - Saved work (`work.json`) carries a `version`; a file from an older build is dropped
    and read afresh, since its entries lack things kept now. Each entry keeps its commit
    message (`raw`) and is read again from it on launch (`reread`), so better reading
    never needs GitHub again.
  - **All work ends with "Copy all"**, small and bottom right, past the last line: the
    work on show as plain text, oldest first (`WorkLedger.retrospective`), for pasting
    into Claude to look back over it. It is out of the way on purpose.
  - **Published means a live production site was updated**: a commit on `gh-pages`,
    which GitHub serves (Labern, 2026-11-18: "not products"). A product's code reaching
    its main branch is `shipped`, a separate figure ("Products") that only shows when
    Company › Settings › "Products on the Work card" is on. The main branch and
    `gh-pages` are always read, however long ago they last moved. `WorkEntry.read` turns a commit
    message into kind, product, subject and bullets, and is tested: **write commit
    messages as `type(product): subject` with `- ` bullets and they read well here.**
  - **Claude messages**: there is no API for it. `tools/claude_stats.py` counts the
    messages typed in every transcript under `~/.claude/projects`, per session per hour,
    and publishes only those counts. Two files are read and joined, a session counted
    once: the Mac's `claude.json` on the branch `stats/claude` (`--publish`, run at each
    install), and `paradox-hq/stats/cloud.json` on the app branch, for conversations
    that ran in the cloud, whose transcripts never reach the Mac. **A cloud session
    working on this app runs
    `python3 paradox-hq/tools/claude_stats.py --out paradox-hq/stats/cloud.json --link
    https://claude.ai/code/<its own session id>` before each push and commits the
    file**; that is the only way its messages count. The link is what lets "Session"
    count exactly the changes made in that conversation (they carry the same address);
    without one it counts everything since the conversation began.
  - The counts are plain files and are re-read on every refresh; only GitHub's API is
    paced. (When they shared GitHub's pacing, a new build started with no
    conversation loaded and "Session" showed nothing while "Hour" was full: 2026-11-18.)
- **Notes** — a proper notebook. Chips are its **sections**: every project, with or
  without notes. The plus makes a new one (`SectionEditor`: a name and a colour, twelve
  swatches or any colour from the wheel); the pencil, shown when a section is chosen,
  or holding a chip, renames or recolours it; a note written while a section is chosen
  is filed there. A section is a `Project`, so one made here has a to-do list too, and
  deleting it deletes that list but keeps its notes. A note's menu
  turns it into a to-do (title becomes the line, the rest its note) on its project,
  or on My list. Plain text, the first line is the title, saved as
  typed. Search (every word must appear), pin, file under a project, share, delete.
  **The editor draws the text as it reads** (`NoteMarkup`, pure and tested;
  `MarkupEditor`, a `UITextView`, because `TextEditor` draws one style only):
  `#`, `##`, `###` headings in three sizes; `•` bullets that nest (a tab a level, hanging
  indent; a dash or star and a space becomes a bullet as it is typed; Return carries
  the list on and an empty bullet steps out of it); `**bold**`, `_italic_`;
  `[words](address)` and any address written out are links that open on a tap. The
  marks stay in the text, drawn faint: the note is stored exactly as typed, so the
  site and the Mac read the same text by the same rules. A bar over the keyboard does
  what a phone keyboard has no key for: heading, bullet, out, in, link, hide. Titles
  and summaries in lists drop the marks (`NoteMarkup.plain`). (Asked for 2026-11-18:
  "a bit like a .md editor… Styling looks amazing, just add some key functionality",
  so the look of plain text was left exactly as it was.)
  **The note's ⋯ menu**: Done, "Add to a to-do list" (My list or any project: the
  title becomes the line, the rest its note), "Add to a project" (files the note
  under it), Share, Delete.
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
- **A project knows its own work** (`ProjectWork`, `WorkLedger.belongs`, tested): its
  page lists the changes made to it, read from GitHub, each one tap from the Claude
  conversation it was made in. A change belongs when it names the project
  (`feat(paradox-hq): …`, "Focus 0.0.4: …") or sits on a branch filed under it
  (`focus/…`); a word in the subject is not enough, so a project never claims work that
  isn't its own. The section is absent until there is some, so nothing breaks without it.
- **Work** (was Today), top to bottom: the header, the Work card, My list and the
  next open line of each project, *Needs you* (disputes, failed payments, deadlines
  inside 30 days, the site being down; hidden when empty), this month and the Stripe
  balance. The takings graph moved to the top of Money (2026-11-18).
- **Money** — today's takings over a 30-day trend first, then revenue by week, month, quarter or year against the same stretch of
  the period before; subscribers and monthly recurring; payouts; every payment.
- **To-do** (was Projects) — a switch **at the foot of the screen**: two large
  buttons, To-do (My list, the default) in the accent and Projects in the second
  colour, the chosen one filled; it lands with hit stop and steps aside while the
  keyboard is up. (Labern, 2026-11-18: "move To-Do and Projects to the bottom of the
  screen with bigger buttons… colour code them. I'd rather have it be its own things,
  to be honest. But do this for now", so they may become tabs of their own.) Each project has a Focus list (`TodoViews.swift`). Lines nest to any
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

## The Work tab's header and the profile
`TodayHeader`: the mark top left, the profile top right, their tops level; beneath both,
the word Dashboard in Graphik, centred, with a line running out either side, all in
grey (his design, 2026-11-18; the first version was white and "looks worse", so grey is
on trial: he may remove it or make it a setting). `ViewThatFits` gives
narrower phones a smaller mark. Of the first version, with the profile floating on a
row of its own: "This is a mess."
**Roles stack.** Under the name, every role being worn, one per line, as many or as
few as he likes. Tapping them opens a menu of ticks that stays open while several are
chosen (`Profile.toggled`, tested); "New role" adds one.
`Sources/Profile.swift`. `[photo] Labern / Founder & Director`, laid out like the Claude
app's account row. Tap the photo to change it (`PhotosPicker`), and place it in its
circle: three sliders (zoom, left and right, up and down) and dragging or pinching the
photo itself (`Framing`, tested). A tall photo has no room sideways until it is zoomed.
A new photo is framed on the face automatically (Vision), or on head and shoulders. Everything stays
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

## Colours (Company › Settings)
Focus's own customisation, brought over name for name (`Palette` in `Shared/Theme.swift`,
`Sources/Colours.swift`): its two-tone presets (Purple & Green, Pink & Teal … Pen Pen)
and nine hues set the accent (`Ink.violet`) and the second colour (`Ink.ok`); Buttons
can take the accent instead of white. **Default is the app exactly as it was.** A chosen
colour is deepened for the light appearance, and words on a coloured button are black
or white, whichever reads (tested). Ticks draw with `Ink.onHead`, not the button ink.

## App icons
Main icon = the app's own mark scaled to 90% width (`design/icons/classic-max-black.png`).
Eight alternates (`AppIcon-*` sets, `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`),
previews in `IconPreview-*` image sets, chosen in Company › Settings. Renders come from
the brand SVG masters via `design/icons/make_icons.py`; never redraw the mark.

## Icon designer (Company › Settings › Create custom app icon)
Made to be lifted out as its own app: `Sources/IconDesigner.swift`,
`Resources/IconDesigner/` and `design/icons/bake_custom.sh` are all of it.
**Lifted out 2026-11-18** as the Icons app (`icons/`); HQ keeps this copy. Fixes
found there: `adopt()` must run once the scene is active (iOS refuses an icon
change earlier, so the `.task` call here can silently do nothing).
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
- **Every install carries the icons made on the phone.** Before building, the Mac
  copies `Library/Application Support/Icons/*.png` out of the app on the phone into
  `design/icons/custom/` (gitignored), so no folder has to be chosen and nothing shared
  by hand: make an icon, pick it ("Next install"), and the next install wears it. iOS
  cannot put on a picture the build doesn't carry, so "at once" is not possible.
- The icon being worn is remembered (`icon-worn`, kept with the settings), so a
  reinstall, which starts on the standard icon, puts it back on (`IconShelf.toPutBack`).
- Not verified on the Mac yet: the script finding the folder in iCloud Drive
  (`~/Library/Mobile Documents/com~apple~CloudDocs`, up to four levels down). If it
  doesn't, drop the PNGs (Share from the icon's menu) into `design/icons/custom/`.

## Face ID
Asks only when the app has been out of use longer than "Ask again after" (default 1 hour),
measured across launches (`lock-last-seen`). Unlock is only attempted while the scene is
active (asking earlier fails and shows "Try again").

## Saving (nothing typed into the app can be lost)
`Vault.swift` and `Backup.swift`. A copy is the whole store as one JSON `BackupFile`
(projects with lines at every depth, notes, deadlines) plus the app's settings
(`SavedSettings`: profile, layout, colours and the rest, minus clocks and caches). Every
time the app is left, without being asked, a copy goes to:
1. **The phone**, `Application Support/Backups`, only when something changed. Every copy
   from the last day is kept (up to 48), then the newest of each day for 60 days
   (`Vault.surplus`). Company › Backup › "Go back to an earlier copy" puts one back
   (data only, settings stay), after first saving what is there.
2. **The Keychain**, compressed, which iOS keeps when an app is deleted. Two slots
   written in turn with a pointer moved last, so a failed write never destroys the good
   copy; a third, slow slot is not replaced by a store under half its size for a week.
   A fresh install with an empty store puts the newest back by itself before anything is
   seeded (`Vault.recoverIfFresh`, settings and profile photo included) and lands the
   older Keychain copies in the list. Stores are made in `ParadoxHQApp.init` after this,
   so they start from the restored settings.
3. **The folder chosen in Company › Backup** (iCloud Drive), one file a day, newest 30.
   A file chosen there by hand puts settings back too.
4. **The Mac**: every install first copies `Library/Application Support/Backups`,
   `Icons` and `Profile` out of the app on the phone to `~/PARADOX backups/<stamp>/`
   with `devicectl` (newest 60 kept). The Mac session does this; it is not in this repo.

Rules that keep it from making things worse: a copy is read back and compared before it
counts and before anything older is removed; an empty store is never saved, and never
replaces a copy with something in it; nothing here runs under `-unlocked` (the cloud
screenshots). Tests use `Vault(folder:usesKeychain: false)`. **iCloud sync proper** needs
the paid team: add the iCloud/CloudKit entitlement and container in `project.yml`; the
`ModelContainer` uses the default (automatic) CloudKit setting, and every model property
is already defaulted and optional-safe for it.

## One canonical copy (the phone, the site and the Mac are the same data)
The company's Supabase project holds the one copy; `Labern/paradoxica-hub` `dash/CONTRACT.md`
is the contract every client follows (tables, ids, deletes, realtime, auth). The master
account is Labern's login address; "Founder & Director" is that account's alone.
- `Cloud.swift`: the plumbing, no dependencies. `CloudConfig` (address and publishable key,
  read from `Resources/Private/cloud.json`, which is on the Mac only: a build without it
  has no cloud and behaves exactly as before), `CloudAccount` (email and password once;
  the hour-long pass is renewed with one kept in the Keychain; sign-up works for allowed
  addresses only), `CloudAPI` (rows, add, change, remove, the Money and Work functions),
  `CloudSocket` (a line held open that says "something changed").
- `CloudSync.swift`: each pass reads every row there and every record here and compares
  both with what they last agreed on, **column by column** (`CloudMerge.plan`, pure and
  tested): only the server changed it → the phone takes it; the phone changed it, or both
  did → the server takes the phone's; new on one side → added to the other; gone from one
  since they agreed → removed from the other. Passes run on opening, a moment after any
  save here (`ModelContext.didSave`), and the moment the server says something changed.
- **First sign-in sends everything on the phone up** and brings everything on the server
  down. The server's own "My list" and feed projects are matched to the phone's and their
  ids taken (`CloudSync.adopt`), so nothing is doubled.
- Every record has a permanent `uid` (a uuid made here, the row's `id` there). Backups
  carry it, so going back to a copy keeps each record the same record.
- **Guards:** an empty phone never empties the server; an empty answer from the server
  never empties the phone; a pass that would remove most of a table stops and says so.
  The server is written first, so a refusal leaves the phone untouched.
- Synced so far: projects, lines, notes, deadlines, and **the profile**: name, roles
  worn, roles added, the photo and its framing (`CloudSync.syncProfile`). The photo goes
  to Storage bucket `profile` at `<account id>/photo-<ms>.jpg` and `profiles.photo` holds
  the path. The phone knows its own photo by a mark of its bytes (`CloudSync.mark`): the
  same photo is never sent twice, a new one is, and one chosen on another device comes
  down as it is. Framing crosses to four decimal places so it always compares equal.
  **Not yet:** settings and layout, links (the server makes its seven), Money and Work
  read through the server's functions (the phone still reads Stripe and GitHub itself).
- **Signing out is under the photo, on every platform** (Labern, 2026-11-19: "if you click
  the user you need to be able to sign out… click pic and have it there as an option").
  On the phone the photo is a menu: Photo and position, the account's address, Sign out
  (asked once more before it does; the data stays on the phone and stops syncing), or
  Sign in when signed out. Signing out leads straight to the sign-in sheet.
- Sign-in is asked once, by itself, the first time a build that can sync is opened
  (`CloudSignIn`: the mark, Dashboard, two fields); after that Company › Connected to ›
  Dashboard shows the account, "Sync now" and Sign out.
- **A pass is never cancelled by the next ask.** `kick` only debounces; the pass runs in
  a task of its own. When the pass ran inside the debounce task, the save it made itself
  (giving records their ids) asked for another pass, cancelled its own requests, and the
  first sync after signing in said "Couldn't reach the dashboard" although the sign-in
  had worked and the next pass synced (2026-11-18). A refused sign-in (`refusal`) and an
  unfinished sync (`problem`) are separate messages for the same reason.
- Dates cross as ISO 8601 to the millisecond, written and read by hand (`CloudDate`): the
  system formatter turns .123 into .122 now and then, which the comparing would see as a
  change every pass.

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

**The five stars twinkle, left to right, as on the website** (its `.m-stars` /
`@keyframes twinkle`: each star dims to 35% and back, 0.18s apart; `Twinkle`). A tap
on the mark plays it (with the hunt and a tick per star), and so does a pull to refresh
finishing on the Work tab. Pages without the mark use `.refreshStars { }` in place of
`.refreshable { }`: five stars drop in under the status bar, twinkle once and go
(`StarsRow` is the mark itself shown down to its stars). The stars are dimmed through
a mask over the picture (`StarMask`), using where they sit in `mark.svg`: if the
master is ever swapped, check `Twinkle.first`/`step`. Reduce Motion: none of it.

**The "working" sign is five stars completing a circle** (`StarSpinner`; his idea,
2026-11-18: "5 stars spinning round to complete the circle"). They arrive one after
another around a ring until it is whole, then the ring turns a star's place at a time,
resting on each (hit stop). It replaces every system spinner: `ProgressView` is not used
anywhere, and the pull-to-refresh spinner is hidden (`UIRefreshControl.appearance()
.tintColor = .clear`) with the ring shown in its place while the refresh runs. Each star
is `MarkStar`, the mark itself shown down to one star. Reduce Motion: the five stand still.

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
