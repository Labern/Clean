# Focus — changelog

Semantic versioning: MAJOR.MINOR.PATCH. New features bump MINOR, fixes bump PATCH.
The version lives in `focus/VERSION`; `build.sh` stamps it into the app. Releases are tagged `focus-vX.Y.Z`.
New features are built on `focus/feat-<name>` branches, cut from `focus/main`.

## 0.18.65 — 2026-11-15
- **Tiers in the app: Free, Pro or Max,** read live from the purchase (`focusTier`; the older `focusPro` flag counts as Pro). A bought Max shows a white **Max** box by the name, where Pro shows **Pro**. Max has full functionality; it's priced to make Pro the one people buy.
- **Pricing (docs/PRICING.md):** his sales logic. The low monthly price is the lure: Pro £5/month, Max £10/month, and a very limited Free. Checkout then reveals 10× once (Pro £50 forever, Max £100) or yearly. Planned for Pro and Max: opening apps at a set time, and blocking apps.
- The GUI tests cover Max (check 8). All 13 pass.

## 0.18.64 — 2026-11-15
- **GUI tests:** `Focus --selftest-gui`, 13 checks covering sizing, widths, text size, the session line, the Buy words, pressure squares, Focus Pro, colours, the Manual, mode order, every page drawing, and the Focus mark. All run off-screen. See docs/GUI-TESTS.md. All pass.
- **The window opens big enough for the sidebar:** at least 1100 × 780, taller with more modes (36 pt each), never bigger than the screen.
- **Links show the pointing hand:** Buy, the PARADOX mark, the Manual's link, its Contents entries and "Contents ↑".
- **Manual Contents** are numbered down each column (1–5, then 6–9), and wrapped titles line up with their numbers.
- Pricing thoughts now live in docs/PRICING.md (merged with the Focus Site session's notes).

## 0.18.63 — 2026-11-15
- **Buy button:** "14 Days of Pro Left — Buy Now" on one line, at full size. The two-line version is gone.

## 0.18.62 — 2026-11-15
- **Buy button:** two lines, "14 Days of Pro Remaining" small and quiet above a bold "Buy Now" (his choice; "14 Days of Pro Left — Buy Now" was a close second).

## 0.18.61 — 2026-11-15
- **The free trial is now called the Pro Preview.** The button reads "14 Days of Pro — Buy Now". The days aren't counted yet.

## 0.18.60 — 2026-11-15
- **Focus Pro sits at the top left:** a bought copy shows a small white "Pro" box beside the Focus name. The badge at the foot of the sidebar is gone. For review, your build shows Pro at the top and the Buy button at the bottom together.

## 0.18.59 — 2026-11-15
- **For looking at the design:** the Focus Pro badge and the Buy button both show in the sidebar foot (`DesktopModel.showBoth`, temporary).
- Noted, not built: free + Focus Pro, with a suggested split (docs/OPEN-ITEMS.md).

## 0.18.58 — 2026-11-15
- **Focus Pro:** a bought copy shows "Focus Pro" beside a white tick in a black circle, where the Buy button was. It reads the purchase live, so it changes as soon as a purchase is recorded. Licences aren't built yet.
- **Sidebar mode names** keep their size when "Start" appears on hover; a long name is shortened with "…" rather than shrunk.

## 0.18.57 — 2026-11-15
- **Bought copies:** a "Pro User" badge (outlined, with the Focus mark) takes the Buy button's place. Licences aren't built yet, so it only shows in renders (`licensed`).
- **Price decided:** £55 per person; team packs in round figures (docs/OPEN-ITEMS.md).

## 0.18.56 — 2026-11-15
- **In a session the big button shows the Focus mark** (ring and dot, in the button's text colour) at its right, beside the key.
- **Trying it without the lasting border** (`SessionButton.keepBorder = false`): starting a session still draws the line round the button, which then fades; ending one shows the whole line and undraws it.
- **Sidebar modes:** under the pointer, "Start" (or "End" for the running mode) takes the key's place. Clicking the name opens the mode to edit.
- **Session Editor row:** "On" during a session, nothing otherwise; "Off" is gone.
- **Shortcuts:** the stray "Then F." and "Then E." notes are gone.
- **Settings ▸ Appearance ▸ Text colour:** White or Black for the big button's text (Black by default). The Icon colour tiles now show hover.
- **Buy button:** "14 Days Remaining — Buy Now", with squarer corners and slightly larger text. The days aren't counted yet; it shows the planned 14 until licences exist.

## 0.18.55 — 2026-11-15
- **Settings ▸ Appearance ▸ Width** is now **Default** (space either side of the page; the new standard), **Wide** (the page fills the window, as before) or **Minimal**, which takes a sidebar's width off the window itself, so the whole app is smaller. Switching into or out of Minimal narrows or widens the open window, keeping its left edge where it is.
- **Hover:** every option you can pick in Settings, and the − / + text-size keys, now show they're under the pointer: they fill a little and the outline brightens.

## 0.18.54 — 2026-11-15
- **The session line:** starting a session draws the line round the button (from the top centre, anticlockwise) and it stays for the whole session. Ending the session undraws it, back the way it came. It follows the session itself, so the menu and ⌘⇧F draw and undraw it too.
- **Modes in the Session Editor:** under the pointer each mode shows a white "Start session" button. A running mode says "On" (hover: "End session"). Clicking a mode's name, or the rest of its row, opens it to edit. Right-click still has the full menu.
- **Session Editor row:** the "Click to…" hover text is gone, and a click just opens the page.
- **Spacing:** the gap under the description in Apps in Session is gone.

## 0.18.53 — 2026-11-15
- **Headings inside every panel** (Apps Outside Session, Critical System Processes, Modes, and those on the mode, Tools and Settings pages) are large and white with a fine white line under them, the same as Behaviour and Appearance. They replace the small grey labels; "Usage" stays a small column name.
- Noted, not built: the idea of an empty bordered circle as the out-of-session icon (docs/OPEN-ITEMS.md).

## 0.18.52 — 2026-11-15
- **Buy Now** (white) sits above Feedback · Manual and opens paradoxica.co.uk/focus#buy, the same place as the site's own Buy link. It shows while on a trial; licences aren't built yet, so for now it always shows (`DesktopModel.trial`).
- **Headings inside a panel** (Behaviour, Appearance, the Manual's sections) have a fine white line under them, full width.

## 0.18.51 — 2026-11-15
- **Manual:** text can be selected and copied, a paragraph, heading or caption at a time. "This window" wording is gone: the button is "at the top of the app", the Feedback button is just the Feedback button, and the keys say "Hide the app" and "Close the app".

## 0.18.50 — 2026-11-15
- **Manual:** a Contents box at the top, numbered; click a section to go to it, and "Contents ↑" beside each heading goes back. Each section has a figure built from the window's own parts, with sample Mac apps: choosing apps beside the Start button, the Modes list with keys, a History row with Save as Mode, two of the Tools, the button in three colours, and the keys that matter. End a session keeps its two drawings, before and in a session.
- **Settings ▸ Appearance ▸ Width:** Default (fills the window, as before), Narrow (space either side) or Space (an empty column on the right). Default is the standard.

## 0.18.49 — 2026-11-15
- **Session button hover:** pressure builds. Thick dark squares slide in from both outer edges along the button's middle and pile up against the title, the same number each side. Once the pile is full it presses inward in a slow pulse. Clicking lets it all go: the squares fly out and fade while the line draws. Leaving without a click fades them. They replace the faint dots.
- **Session Editor:** the sidebar's "Session Manager" is renamed. Its page now ends with **Modes — frequently used sessions**, as the menu does: click a mode to start it, right-click to edit, or Create New Mode. The sidebar's Modes open each one in detail.
- **Mode pages:** the start button says "Start this session".

## 0.18.48 — 2026-11-15
- **Session page headings now match the menu's:** "Apps in Session", "Apps Outside Session" and "Critical System Processes — never quit", each with the menu's line of explanation. "Keep open this session" is gone.
- **The big button takes the colour from Settings ▸ Appearance:** the ring colour, running into the dot's colour when the two differ. Its text turns black on light colours and white on dark ones, and the click line and hover dots follow. White is still the default. A colour picked in the menu reaches the window within 1.5 s.

## 0.18.47 — 2026-11-15
- **Session button hover:** small dark dots drift in from the right along its lower third. They ease in and out, bunching and stretching like a rubber band being drawn back. They are subtle, and only show while the pointer is on the button.
- **Manual:** its text is one stop (one ⌘+) larger than the other pages.
- **Margins:** the space either side of the button and page is down from 110 to 36 points.

## 0.18.46 — 2026-11-15
- **Session button hover:** quiet. The button dims a touch and grows a touch; there are no sparkles, sheen, glow or lift. The click still draws the line round it.
- **Trying equal margins for real:** the sidebar is as it was, with equal space either side of the button and the page. The right sidebar is off; `DesktopView.trial` switches between `.none` (the saved good look), `.right` and `.narrow`.
- **Manual drawings:** realistic chaos, 8 windows, then true calm, 3.
- `Focus --open-desktop` asks again over two seconds, so it opens the window even straight after an install.

## 0.18.45 — 2026-11-15
- **Manual:** the Manual button opens the Manual, his own text with typos corrected. It covers starting and ending a session, modes, snapshots and previous sessions, tools, appearance, the menu and the app, feedback, and about. His before/after screenshots are drawn as abstractions: a crowded desktop, then the chosen few windows.
- **Trying the right sidebar for real:** an empty column on the right, as wide as the left one, at all times. To go back, set `DesktopView.trial = .none` (the saved good look, tag `focus-look-good`).
- **Icon:** Finder and Spotlight show the same logo as the Dock and the window. The bundle icon was still the menu bar mark.

## 0.18.44 — 2026-11-15
- The About button and panel are gone (to be folded into the Manual). The sidebar foot is Feedback · Manual.
- 0.18.43's look is saved as the good version: renders in `docs/looks/`, tag `focus-look-good`.
- Layout trials for comparison, drawn off-screen only (`--render-desktop FILE trial=right|narrow wide`): an empty right sidebar, or equal margins either side of the page. The app itself is unchanged.

## 0.18.43 — 2026-11-15
- Settings ▸ Text size is now − / Default / +, the same steps as ⌘− and ⌘+. The middle says how far from Default you are (e.g. "Default +2"); click it to go back. The size the window had is now Default.
- Feedback, About and Manual sit side by side in one row across the sidebar's width.

## 0.18.42 — 2026-11-15
- The Start/End Session button, hovered: it lifts, a sheen crosses its face, a soft white glow breathes and sparks flare at its corners.
- Clicked: it presses in, then a white line draws round it the way the website's Buy square does. It starts at the top centre and takes 2.4 s, quick then settling. It runs anticlockwise when a session starts and clockwise when one ends.
- The sidebar's Session row is now "Session Manager", with a switch at its right: white "On" in a session, black outlined "Off" otherwise.
- Reordering modes is instant: rows jump to their new place with no easing or dimming, and icons are read once rather than on every redraw.
- The feedback card is black, like the rest of the app.
- No scroll bars anywhere in the window; scrolling still works.
- New "About" button in the sidebar foot, between Feedback and Manual. It opens an About panel for the maker's own words (`AboutPage.words` in desktop.swift).

## 0.18.41 — 2026-11-15
- The Start/End Session button: under the pointer, a white line traces round it anticlockwise and sparks flare at its corners. The line stays while the pointer is on the button.
- Clicking it: the button presses in, and a ring of light leaves its edge.
- Modes in the sidebar can be dragged to reorder (the menu shows the same order). Right-click a mode to start or end it, edit it, set its shortcut or delete it.
- Each panel's name has a single white line under it, full width. Sub-sections are divided by a quiet grey line, as in the menu.
- The sidebar's Session row says what a click does when the pointer is on it: "Open" from another page; on the Session page, "Click to start" (or "Click to end"), and a click does that.

## 0.18.40 — 2026-11-15
- **Desktop app:** one top row across the whole window, with the logo and the Start/End Session button. Below it the sidebar and the page start on the same line. The button stays on every page, modes included.
- What 0.18.39 looked like is kept in docs/looks/.

## 0.18.39 — 2026-11-15
- More space between the session button's line and the page below, so the top row (logo, button) stands apart.

## 0.18.38 — 2026-11-15
- More space between the logo and the sidebar's first page.

## 0.18.37 — 2026-11-15
- The desktop app's standard text size is one step larger (1.0 of the written sizes).

## 0.18.36 — 2026-11-14
- The desktop app's standard text size is two steps smaller (back to 0.9 of the written sizes). The value now lives in one place, `Site.standard`.

## 0.18.35 — 2026-11-14
- Tools page: each tool is a large button with a line beside it saying when you'd use it.
- Settings page: two groups, Behaviour and Appearance; more room between settings and a line under each; a choice reads like a switch (the chosen option solid white, the other outlined in white). The icon and colour pickers are even grids, with the chosen one outlined.
- Settings ▸ Appearance ▸ This window: Light, Dark, System. Dark is the standard; Light and System are shown but not built yet.
- The window opens a little taller (up to 1000 × 730).

## 0.18.34 — 2026-11-14
- The desktop app's standard text size is now what two presses of ⌘+ used to give. Any earlier size change is reset once, so everyone starts from the new standard.
- The session button's own text is two steps smaller than that, so it sits inside the button comfortably. The sidebar is a little wider and the window opens at up to 1000 × 660.
- ⌘H hides the desktop app; pressed again within four seconds, it brings it back.
- One face throughout: the feedback box's typed text is now Graphik like everything else.
- During a session the line under the button reads "End the session to restore all of your apps as they were." The memory bar and the memory saved are shown only before a session starts.
- The mode in use is highlighted in the sidebar: outlined in white, with an "On" label.
- The arrow beside "Modes" sits on the middle of its line. More space at the bottom of the window.

## 0.18.33 — 2026-11-14 (branch focus/feat-desktop-app)
- **⌘Q quits the desktop app, never the menu bar app.** Only the menu's own Quit, or the Mac shutting down or logging out, ends Focus. A quit that arrives any other way while the window is open is refused and closes the window. "Quit Focus Completely" is removed from the window's menus.
- **The logo** is at the top left of the window, the same height as the Start/End Session button and level with it.
- **Text** is a step larger again (0.9 of the original sizes).
- **Send feedback** in the app (sidebar ▸ Feedback, or Help ▸ Send Feedback…): write it, press Send.
  - It posts to https://paradoxica.co.uk/api/feedback. Until that address answers, the message is put into an email to labern@paradoxica.co.uk instead.
  - It sends the message, the Focus version and the macOS version, and says so.

## 0.18.32 — 2026-11-14 (branch focus/feat-desktop-app)
**Desktop app, reworked around the session.** Getting into a session is the point of the app; modes are secondary.
- **The Start/End Session button** is the largest thing in the window: full width of the pane, centred, at the top of every page. Under it, one line: how many apps close, how much memory that saves, and that they reopen. The "in session for…" line is gone.
- **Text** is 0.8 of what it was, with more room around everything. The window opens slightly larger (960 × 640 at most).
- **Sidebar:** only your modes and Create New Mode sit under "Modes", and clicking that heading hides them. Suggested modes are no longer listed there. Editing happens inside the mode.
- **Drag an app row** to reorder the list. It changes nothing but the order you see. Dragging no longer moves the window; drag the top strip for that.
- **Fixed:** the icon picker showed several designs upside-down, so they didn't match the real menu bar icons. Each preview is now the menu bar's own drawing, the right way up.
- The text-size choice in Settings shows the current setting.

## 0.18.31 — 2026-11-14 (branch focus/feat-desktop-app)
**Desktop app**
- **Size:** a smaller, squat window (900 × 580 at most, always inside the screen), with tighter spacing at the top.
- **Text:** larger throughout, and adjustable with View ▸ Increase / Decrease Font Size (⌘+ / ⌘−), or in Settings.
- **Menu bar while it's open:** Focus, File, Edit, View, Window, Help. ⌘Q and ⌘H leave the desktop app (Focus keeps running in the menu bar); ⌥⌘Q quits Focus completely.
- **The session button:** fat, white, at the top left of every page, never full width, with its key. What it will do is written beside it, with the time in session and a pulse while one runs.
- **Sidebar:** Session, Shortcuts, Tools, History and Settings pages, then your modes, Create New Mode and up to three suggested modes.
- **Sidebar foot:** "Update available" (only when the release page has a newer build), Help (writes to help@paradoxica.co.uk), Manual (not written yet), and the ★★★★★ × PARADOX™ mark, larger and centred, which opens paradoxica.co.uk.
- **Session page:** a memory bar, one segment per app (white stays, grey closes; hover for whose it is).
- **Settings page:** the menu's settings, plus the icon picker (hover plays each design into a session) and icon colours.
- **Right-click an app** in the window: Quit or Force Quit it.
- **Motion:** pages fade as you move between them, rows and the button respond to the pointer, and clicking the logo replays its opening.
- **Dividers** between the sidebar and the pane are gone: the window is one black surface.

**Menu bar app**
- **Menu bar icon:** a new design, "Default", is the website's mark: the ring in pieces round a small dot out of session, closed round the large dot in session. The previous one is still offered as "Original".
- **Right-click an app row** in the menu: Quit / Force Quit. Still unproven: right-clicks inside a menu may not arrive.
- **Log:** Focus writes its own log to ~/Library/Logs/Focus.log, so that can now be checked.

## 0.18.30 — 2026-11-14
- Fixes 0.18.29, which did not build (a comment cut a line of the window's code short). Use this version, not 0.18.29.

## 0.18.29 — 2026-11-14
- The desktop window follows the menu's record in every case: a mode renamed from the menu now updates in the window's name field at once.

## 0.18.28 — 2026-11-14
- `Focus --open-desktop` asks the running Focus to show its desktop window.

## 0.18.27 — 2026-11-14 (branch focus/feat-desktop-app)
- **The desktop app (first version).** An optional window, hidden until asked for. The menu bar app still does everything on its own.
  - **Design:** the website's. Black ground, white ink, the Graphik face, rounded corners.
  - **Sidebar (fixed):** the logo and "Focus"; Session; your modes with their shortcuts; Create New Mode; ★★★★★ × PARADOX™.
  - **Session view:** every open app with its full-size icon and memory. Click to keep or release an app, or to take it out of a running session or bring it back. Also Apps Outside Session, Critical System Processes, and the Start/End button with its caption.
  - **Mode view:** rename, choose its shortcut, add and remove apps, start it, delete it.
  - **Opening it:** "Open Desktop App ↗" to the left of Quit in the menu, and Settings ▸ Show/Hide Desktop App.
  - **While it's open:** Focus is in the Dock and ⌘-Tab. ⌘H (or ⌘W) puts the window away and returns Focus to the menu bar only.
- **The logo (final):** a closed white ring round a large white dot on a near-black rounded tile. It's used in the window and the Dock, and it plays its opening when the window appears.
- **Code:** the window lives in `desktop.swift`, apart from the menu. `--render-desktop FILE [mode]` draws it off-screen.

## 0.18.26 — 2026-11-14
- Right-click on a mode: now also caught at the app level while the menu is open, because a menu doesn't pass a right-click to its rows. Logged.
- The Create New Mode builder keeps a half-typed name (and the apps picked) if its menu closes by accident.

## 0.18.25 — 2026-11-14
- The stars are removed from the menu bar name animation.

## 0.18.24 — 2026-11-14
- Taking an app out of a running session from the menu, or bringing one back, plays the session animation for just that app: into the menu bar icon when it leaves, out of it when it returns. The animation itself is unchanged.

## 0.18.23 — 2026-11-14
- **Fixed:** on a Mac in Light mode the menu could open with its rows drawn in light-mode ink (dark text, dark button) on the dark background.
  - Cause: the dark look was applied only as the menu opened, too late for the first drawing.
  - Fix: it's now set when the menu is built, on the menu, every submenu and every drawn row.
  - Test scenario 46 checks all of them.

## 0.18.22 — 2026-11-14
- Settings ▸ Appearance ▸ Light or Dark: the menu can be light. Dark is the standard and is unchanged.

## 0.18.21 — 2026-11-14
- **The session animation (apps flying to and from the menu bar icon) is restored exactly as it was in 0.17.0.** Everything added to it in 0.18.0 is removed: the name written letter by letter in the pill, its sparks, and the in/out animation when switching modes.
- "Its apps — click to add" now reads "Add apps for mode". "Animate the Name" now reads "Animate on Session Start/End".

## 0.18.20 — 2026-11-14
- A wider gap between the name and the character on each side of it in the menu bar.

## 0.18.19 — 2026-11-14
- Settings ▸ Appearance ▸ Menu Bar Name:
  - Choose the character beside the name: | · — / › • or none.
  - "Animate the Name" turns on the letter-by-letter writing and sparkle. It's off unless you turn it on.

## 0.18.18 — 2026-11-14
- Verbose headings, during a session: a line under the app list says these apps are in your session, and a line under "Apps Outside Session" says those aren't and that clicking one adds it.
- The menu bar reads "icon | name |", with a bar on each side of the name.

## 0.18.17 — 2026-11-14
- When the name has been written in the menu bar it sparkles: a flash pops behind it and glowing stars sweep from its first letter to its last. When a session ends, the stars sweep the other way before the name is deleted.
- Developer flag `--render-sparkle FILE` draws the sparkle off-screen as a filmstrip.
- docs/PORTING.md: first notes on Windows, Linux and Unix.

## 0.18.16 — 2026-11-14
- The menu bar reads "icon | name": a bar between the icon and the session's name.

## 0.18.15 — 2026-11-14
- In the menu bar, the session's name is written one letter at a time beside the icon (the icon slides left as it grows), then sparkles and pops. When the session ends it is deleted the same way, from the right.

## 0.18.14 — 2026-11-14
- Settings ▸ Appearance ▸ Headings: Minimalist (section names only), Normal (as now) or Verbose (a sentence under each heading saying what the section does).

## 0.18.13 — 2026-11-14
- The help link writes to help@paradoxica.co.uk, with the subject starting "Focus: ".

## 0.18.12 — 2026-11-14
- "Help / Suggest Improvement" at the bottom left of the menu, with a help icon. For now it opens a new email.

## 0.18.11 — 2026-11-14
- The headings carry their descriptions again: "Keep open this session — click to choose", "Critical System Processes — never quit" and "Modes — frequently used sessions".

## 0.18.10 — 2026-11-14
- Right-clicking a mode: the menu closes and the mode's edit menu opens at the pointer (the first attempt opened nothing). Logged, so a click that doesn't arrive can be traced.

## 0.18.9 — 2026-11-14
- The ★★★★★ × PARADOX™ mark is small, plain and at the bottom right.

## 0.18.8 — 2026-11-14
- The menu ends with the maker's mark: ★★★★★ × PARADOX™.

## 0.18.7 — 2026-11-14
- Clicking "Usage" cycles the order of the app list: as listed, most memory first, most used first (the apps you've kept open in the most sessions), then back.

## 0.18.6 — 2026-11-14
- "Focus" at the top left is large (21 pt bold).
- "Apps in Session" sits to the left of "Usage", on one line over the app list.
- The Start/End button is taller, with more padding above and below its text.
- Tools: "Analyse performance" comes first; the quit section is headed "Quit Unresponsive Apps".

## 0.18.5 — 2026-11-14
- Critical System Processes rows can't be clicked and don't react to hover: the lock stays, and changes go through "Add or remove…".
- "Create New Mode" sits under your modes (it's first when you have none). Edit Modes starts with "Add New Mode".

## 0.18.4 — 2026-11-14
- "Focus" is back at the top left, on the same row as Quit.
- **Minimal headings:** "In Session", "Critical System Processes" and "Modes". Each heading's description shows when you hover over it. The "Keep open this session…" line is gone.
- A little more space between the Start/End button and its description.

## 0.18.3 — 2026-11-14
- **Taken back out:** the "Focus — mode (apps, since…)" line at the top; the "App" title and the mark over the ticks (only "Usage" stays); the larger custom headings (macOS's own grey headings are back); the taller button.
- **Quit** is the first row of the menu, at the top right.
- **Mode names** start in one fixed place, clear of three icons, however many apps a mode has.
- "Temporarily Closed / End Session to Reopen" is now "Apps Outside Session". "In this session —" is gone from the app list's heading.
- The lock on Critical System Processes stays a lock on hover. + and × show only where a click adds to or removes from a session or mode.
- **Settings:** Reopen windows and Open at login show on or off with their icon, so they line up with the icons above.
- Removed two marks that could push a menu's icons to the right.

## 0.18.2 — 2026-11-14
- Every mode's name starts in the same place, however many apps the mode has.

## 0.18.1 — 2026-11-14
- **Headings:** every grey heading in the menu and its submenus is drawn by Focus at one size (13 pt), set in one place with its weight and colour.
- **Tools:** "Quit apps to free RAM" heads the three Quit items; "Analyse performance" heads Activity Monitor and System Settings.
- **Settings ▸ Behaviour** (under Appearance and Shortcuts) holds App Open/Close Speed, Hide Instead of Quit and snapshots.
- **Modes:**
  - "Create New Mode" comes first. It needs no name: each new mode takes the next number (⌘1 … ⌘9, ⌘0) and is called "Mode 3" until named.
  - Right-click or ⌃-click a mode to edit it.
  - A mode's shortcut sits in the same column as the apps' memory.
- **Column titles over the app list:** App, Usage, and the Focus mark over the ticks.
- **Menu bar name:** Settings ▸ Appearance ▸ Menu Bar Name offers "AI", "AI session", "AI (in session)" or icon only.
- The banner naming the mode at the top of the menu is removed. The button reads "End Session" again, with more space above its description.

## 0.18.0 — 2026-11-13
- **Switching between modes has its own animation.**
  - The apps leaving fan out on the left and are pulled into the menu bar icon.
  - The apps arriving fly out of the icon on the right and drop into the pill.
  - The pill stays until they land.
- **The mode's name writes itself in,** letter by letter from left to right, with a glowing spark at each letter. When a session ends it deletes itself from the right.
- The ordinary start and end keep their exact timing, Normal included.
- Developer flag `--render-pill FILE start|switch|end` draws the show off-screen as a filmstrip.

## 0.17.0 — 2026-11-13
- **Modes start with one click:**
  - Each mode is an item under the Modes heading, with its shortcut on the right.
  - Click it to start it; during a session it moves the session to that mode.
  - The live mode is ticked, and clicking it ends the session.
- Renaming, apps, shortcut and delete are in the Edit Modes submenu.

## 0.16.2 — 2026-11-13
- The menu bar always names the session: its own name, else the mode it matches, else "Focus".
  - A mode matches when the session kept at least half of that mode's apps.
  - The menu's first line uses the same name.
- "Switch to" is removed from the mode menu: a mode offers Start, or End when it's the live one.

## 0.16.1 — 2026-11-13
- During a session a mode's menu offers "Switch to <mode>" instead of a greyed-out Start, or "End <mode>" if it's the live one, the same as its key.
- The menu's first line names the mode: "Focus — AI (4 apps, since 21:40)".
- Mode keys write a line to the system log when pressed, so a key that doesn't arrive can be traced.

## 0.16.0 — 2026-11-13
- **Suggested Modes:** three at most, built from the apps you actually use. For each kind, Focus picks what's running or was used most recently, from macOS's last-used dates. The list no longer has a grey line under each suggestion.
- **New Mode is a builder:**
  - Name it at the top; press Return to save.
  - Click apps in or out: what's open, plus apps your sessions kept.
  - Add App… for anything else.
  - It replaces "New Mode from Ticked Apps".

## 0.15.0 — 2026-11-13
- Naming happens in the menu itself, with no popups. Type and press Return for:
  - a new mode
  - renaming a mode, as the first line of its submenu
  - renaming a past session
  - saving a past session as a mode
- During a session the menu bar shows the icon, then the mode's or session's name. Turn it off in Settings ▸ Appearance ▸ Show Session Name Next to Icon.

## 0.14.1 — 2026-11-13
- The Modes heading reads "Modes — pre-defined app combinations".

## 0.14.0 — 2026-11-13
- **Modes, built out.**
  - **Suggested Modes:** Game Design, Web Only, Writing, Coding, Design, Calls. Each is built only from apps this Mac has; Web Only uses your default browser. Click one to add it, then make it your own.
  - **A mode's menu lists its apps ticked and your open apps unticked.** Click to put one in or take it out, or use Add App… for anything installed.
  - **Mode shortcuts:** give any mode a number in its Shortcut menu. Nothing is set until you choose.
    - Pressing it starts the mode, pressing it again ends the session, and pressing it in another session switches straight to it.
    - The modifier is in Settings ▸ Shortcuts. ⌘ is the default, and the menu notes that browsers use ⌘1–9 for tabs.
    - A mode's key shows at the right of its row.
- **"Parked" is now "Temporarily Closed / End Session to Reopen".**
- **App rows on hover:**
  - + when a click will add the app, × when it will remove it.
  - After 2.5 seconds, a popup says exactly what a click does ("Click to remove Chrome from your session.").

## 0.13.0 — 2026-11-13
- The menu's first line says where you are: "Focus" out of a session, "Focus — in session (3 apps, since 21:48)"
  in one.

## 0.12.0 — 2026-11-13
- Settings ▸ Appearance ▸ Icon Colour ▸ **Evangelion**: UNIT 01, Asuka, Rei, Shinji, Misato, Kaworu and Pen Pen,
  each a ring and dot pair in the show's colours. The original presets stay.
- **Your Schemes**: "Save Current Colours as Scheme…" names and keeps your ring and dot colours; hold ⌥ to delete one.

## 0.11.1 — 2026-11-13
- Settings ▸ Switching is now **App Open/Close Speed**: "Safety first (closes all apps carefully, slower)" or
  "Speed first (opens/closes apps immediately)".

## 0.11.0 — 2026-11-13
- Settings ▸ Appearance ▸ Icon: hover over a design and it plays, from out of session to in session with the hit
  stop and back, on a loop, so you see what it will do in the menu bar before choosing it.

## 0.10.1 — 2026-11-13
- Only the icons you picked in the Icon Lab stay: Full stop, Aperture, Reticle, Zoom, Ichi (三 → 一), Ensō,
  Hinomaru, Tomoe, Stone, Windows, Spotlight, Counter and Door. The 14 you didn't pick are removed. 20 designs in all.

## 0.10.0 — 2026-11-13
- 27 new menu bar icons from the Icon Lab, in Settings ▸ Appearance: every idea on the page, now 34 designs.
  - Narrowing in session: Pillar, Ghost, Fuse, Point, Wide, Keystone, Tally.
  - Minimal: Full stop, Aperture, Selection, Reticle, Zoom.
  - Japanese: Ichi (三 → 一), Ensō, Hinomaru, Shōji, Tomoe, Stone, Hanko.
  - Maximal: Orbit, Stars, Gather, Windows, Spotlight.
  - Counter (shows how many apps are open), Hourglass, Door.
- Each one follows your icon colours and animates into its in-session state.
- The icon picker shows five per row so all 34 fit.

## 0.9.0 — 2026-11-13 (branch focus/feat-live-session)

- **Edit a session while it runs.** Click an open app to take it out now (saved and quit, or hidden if it's hide-only;
  End Session brings it back). Click a parked app under **Parked** to bring it back now. No ending, no procedure.
- **Never stuck behind a save prompt.** An app waiting for you to save gets its own line with **Show Its Save Prompt**,
  **Keep It in the Session** and **Force Quit — Unsaved Changes Lost…** (asks first, in red). Scenario 31.

## 0.8.0 — 2026-11-13 (branch focus/feat-switching)

- **Settings ▸ Switching:** Careful (one app at a time, each saving before the next) or Fast (every app quits and
  reopens at once — still never forced).
- **Settings ▸ Hide Instead of Quit:** tick any app to have it hidden, never quit, so it comes back exactly as it was —
  the same Claude chat, the same page. For apps that don't restore themselves after quitting. ("Hide every app" moved here.)
- **New icon: Fewer** — a wide row of apps narrows to the two you keep.
- Wording: dropped the "Normal is the original" line; "Default (white)" is now "White". Scenarios 29, 30.

## 0.7.0 — 2026-11-13 (branch focus/feat-session-banner)

- **A session says what it is.** During a session the menu opens with a banner: the mode's name (or the name you
  gave the session) in bold, with "Mode · started 21:48 · keeps Unreal Editor, Claude" under it. Unnamed sessions read
  "Focus session". The big button reads "End Game design". Renaming the live session shows at once. Scenario 28.

## 0.6.0 — 2026-11-13 (branch focus/feat-modes-plumbing)

- **Modes plumbing, ready for drag and drop** (no dragging in the UI yet, by design): every mode has a permanent id
  (older modes are migrated); create, rename, delete, add an app (by id, or from a .app dragged in from Finder or the
  Dock), remove, reorder and start — all by id. The menu now addresses modes by id, not position. Scenario 27.

## 0.5.0 — 2026-11-13 (branch focus/feat-icon-styles)

- **A chunkier menu bar icon, like the logo.** Off: four thick brackets round a solid dot. On: the brackets close and
  the disc floods solid with the dot knocked out — outline vs solid, obvious at a glance. Same animation timing.
  The app logo keeps the original drawing (frozen as `classicLens`).
- **Settings ▸ Appearance ▸ Icon:** six designs — Lens (default), Less more, Narrowing, Framed, Gathered, Switcher.
  Each animates into its focused state; the icon colours apply to all; white by default.

## 0.4.0 — 2026-11-13 (branch focus/feat-kept-apps)

- **A session is defined by the apps you keep open**, not the ones it parks (Unreal + Claude = game design). Every
  session now records its kept apps. Past sessions are titled by them ("Kept Unreal, Claude · Today 21:48") and list
  **Kept open** above **Parked**.
- Fix: **Save as Mode…** built the mode from the *parked* apps — the wrong set. It now uses the kept apps (and is
  greyed out for older sessions that didn't record them). Modes read "the apps you keep open".

## 0.3.0 — 2026-11-13 (branch focus/feat-animation-speed)

- **Settings ▸ Appearance:** Icon Colour moves here, beside a new **Animation Speed** dial: a small clock with the hand
  straight up for **Normal**, back at 10 for **Slow**, on at 2 for **Fast**. Speed sets how long the app icons stay on
  screen before they're swept into the menu bar (start) or drop into the pill (end).
- **Normal is the original animation and the permanent default.** Its timing, recorded: icons hold **0.24 s** at the
  start of a session and **0.02 s** at the end; unchanged at every speed: pop-in 0.16 s, hit stop 0.10 s, burst 0.16 s,
  flight 0.34 s (+35 ms per icon), zip 0.22 s. Slow holds 1.2 s / 0.9 s; Fast 0.08 s / 0 s.

## 0.2.1 — 2026-11-12 (branch focus/feat-shortcuts)

- **Test suite:** `./test.sh` (quick, ~15 s, touches no apps — run after every major change) and `./test.sh full`
  (~7 min, every scenario — run when needed). Both print a plain-English table and save docs/TEST-REPORT.md.
  Stand-in app source now lives in tests/standins.swift.
- Fix (found by the full suite): Focus recognised a session's apps by file path, which has several spellings
  (/var vs /private/var, moved or translocated apps), so an app could be missed — e.g. one that reopened itself.
  It now recognises apps by bundle ID, falling back to the path for older saved sessions.

## 0.2.0 — 2026-11-12 (branch focus/feat-shortcuts)

- **Settings ▸ Shortcuts:** choose the keys. Start/End Session: ⌘⇧F (default), ⌃⌥F, ⌃⇧F, ⌃⌥⌘F; open the menu: ⌘⇧E
  (default), ⌃⌥E, ⌃⇧E, ⌃⌥⌘E. Each choice says what it clashes with; a change takes effect at once; a combination
  another app already holds is flagged instead of failing silently. The Start button shows the current key.

## 0.1.2 — 2026-11-12 (branch focus/feat-modes)

Bug hunt — the whole of main.swift read through; eight real defects fixed, each with a stress scenario (19–22):
- Deleting the live session from Past sessions made End Session reopen an older session's apps. Delete is now
  disabled for it; it's marked "· now", and its Open item reads "End Session and Reopen".
- "Open all" on an old session silently ended the live one. It now just opens that session's apps.
- ⌘⇧F during Quit All & Restart started a session mid-quit, and the Mac could then restart mid-session. Now ignored.
- Ending a Mode's session early left the mode's app list active, so the next ordinary session quit the wrong apps;
  the "waiting for you to save" note lingered too. End Session now clears both.
- A session started while the last one was still being restored had apps reopened into it — and the apps that
  restore hadn't reached were lost. Restores now stop when a new session starts, and their unreached apps join it.
- Ending a session within the first second (before the snapshot finished) could hide apps afterwards. Fixed.
- No display (lid shut, screens off) would crash Focus when placing the pop-up. Fixed.
- Confirmation dialogs could open behind other windows. They float in front now.
- Restoring no longer waits 0.7 s on apps that are already open.

## 0.1.1 — 2026-11-12 (branch focus/feat-modes)

- Fix: hovering Settings (or any submenu) showed a copy of the whole menu instead of its own items — a side effect
  of 0.1.0's dark menu. Covered by a new stress scenario.

## 0.1.0 — 2026-11-12 (branch focus/feat-modes)

- **Modes:** named sets of apps — tick some apps, "New Mode from Ticked Apps…", name it (say, Writing). Starting a mode
  opens its apps and parks everything else; End Session brings it all back. Rename, update from ticks, or delete.
  None are built in.
- **Named sessions:** rename any past session; hovering one shows its snapshot first; "Save as Mode…" turns a session
  into a mode.
- **A true dark menu:** opaque off-black (#1F1F21) with white text, always — matching the product page.
- Fixes: a parked app that's been deleted is skipped quietly (no "can't be found" dialog); an app that relaunches
  itself is spotted even if it comes back hidden.

## 0.0.4 — 2026-11-12

Stress-tested (see `docs/STRESS-TEST.md`). Two fixes:
- **Two Focuses launched at the same instant could leave none running.** The oldest copy now always survives,
  with a re-check after launch.
- **Apps that reopen themselves** (login items, helpers) now get their own line in the menu — "Reopened by itself:
  … — quit again" — instead of being described as a save prompt.

## 0.0.3 — 2026-11-12

- Monochrome menu, matching the product page: the Start New Session pill and the kept/locked marks are white with
  black in dark mode (near-black #171A20 with white in light mode). Colour now belongs to the icon you choose.
- Force Quit All Apps… is red — the only red in the menu, because it's the only hazard.

## 0.0.2 — 2026-11-12

- The big button now reads **Start New Session**, and underneath it says in plain English what will happen:
  "Starting a new session will save and quit 6 apps, freeing about 10.7 GB of RAM. Click again to reopen them."
  Matching sentences while a session is running, in hide mode, and when nothing would be quit.

## 0.0.1 — 2026-11-12

First versioned build.

- **Sessions:** ⌘⇧F parks every app you haven't kept and brings them all back exactly as they were. Apps quit one
  at a time, biggest first, the normal way (they save their state); nothing is ever force-quit. An app waiting on
  a save prompt doesn't hold the rest up — it's brought forward at the end.
- **The menu (⌘⇧E):** every Dock app with its memory; click to keep it open; a live caption says what a session
  will quit and free. Critical System Processes are never quit or hidden. Past sessions reopen from the menu.
- **Session pop-up:** the pill pops, hit-stops, and pulls the parked apps into the menu bar icon — and back out.
- **Snapshot:** a screenshot of where you were (only with Screen Recording already allowed; never prompts).
  Keeps the newest and one spare.
- **Tools:** Quit All Apps, Quit All & Restart Mac, Force Quit All Apps, Open Activity Monitor, Open System Settings.
- **Colour:** menu bar icon ring and dot colours (shades, 360° wheel, presets) and a Customised Logo for the app icon.
  White by default.
- **Safety:** only one Focus ever runs; the system ⌘⇥ is never touched; Chrome comes back with its tabs but no autoplay.
