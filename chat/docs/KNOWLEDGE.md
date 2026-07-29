# KNOWLEDGE — decisions and open threads

Technical facts, DOM hooks and gotchas live in `../CLAUDE.md` — this file holds
only what that doesn't: why the shape is what it is, and what's still open.

## CHAT is a background app now — and how to put it back (2026-07-29)

Labern: *"I'd like to remove CHAT and MU as cmd tab apps. I still want them to run
as Swift apps, but I don't want them to fill up the bar. I want them to be running
in the background."* Then, narrowing it: *"The only change I want is the items in
the CMD Tab. Everything else — identical."*

CHAT now launches as an **accessory** app: no Dock tile, no ⌘-Tab slot. It still
runs full-time, still holds the App Nap assertion, still notifies, still answers
⌘R and ⌃⌥⌘W. Nothing was lost — the unread count already lived in the menu-bar `◦`
rather than on a Dock badge, so the Dock tile was pure furniture.

**macOS couples the Dock icon and the ⌘-Tab slot to one setting** — the activation
policy (`.regular` / `.accessory` / `.prohibited`). You cannot have one without
the other. So it's set in two places, and both matter:

- `LSUIElement` = `true` in the `Info.plist` `build.sh` writes — the launch-time
  default. Without it the icon flashes up before the code can demote it.
- `app.setActivationPolicy(Prefs.showInDock ? .regular : .accessory)` in
  `ShellApp.main()`, reading a saved pref — which is what makes it reversible.

### Three ways back to the ⌘-Tab version, cheapest first

1. **App ▸ Show in Dock & ⌘-Tab** (right-click the menu-bar `◦` to reach the menu).
   Takes effect immediately, no restart, persists. Untick to hide again.
2. **From a terminal**, same switch without the GUI:
   `defaults write com.labern.chat showInDock -bool true` then relaunch CHAT.
   `-bool false` puts it back.
3. **The whole pre-change app**, if something about the new build is wrong:
   `ditto ~/AppSnapshots/2026-07-29-pre-accessory/CHAT.app /Applications/CHAT.app`
   — a byte-identical copy of the signed bundle as it ran that morning. The source
   is tagged too: `git checkout pre-accessory-chat -- chat/ && cd chat && ./build.sh --install`.

`LSUIElement=true` plus a runtime `.regular` is the supported combination — it's
how every app with a "Show icon in Dock" checkbox works. The reverse (no plist
key, runtime `.accessory`) is the one that flashes on launch.

### Why right-click on the `◦` opens the whole menu now

An accessory app **never draws its menu bar**. The ⌘-key equivalents still fire —
AppKit consults `NSApp.mainMenu` for those whether or not it's displayed — but
File/Edit/Chats/View/Window would have become unreachable by mouse. So
`showStatusMenu()` mirrors the live tree onto the status item on right-click.

It *mirrors* rather than calling `buildMenu()` twice on purpose: `buildMenu()`
also binds every `themeItems` / `hideItems` / `privacyItem` / … reference that
`syncMenuState()` writes to, so a second call would rebind that bookkeeping to
the copy and freeze the real menu's checkmarks. `mirror()` walks the live tree
instead, so one source of truth stays, and any menu item added later shows up
there for free. It copies field-by-field rather than via `NSMenuItem.copy()` so
nothing depends on how AppKit carries `target` across a copy.

### The launch-time notification alert is gone — don't add it back

`prepareNotifications()` used to raise a modal at **every** launch when macOS had
notifications switched off for CHAT, reasoning that silent notification failure is
total failure for this app. Labern answered that, 2026-07-29: *"Stop asking me
whether I want to turn on notifications for CHAT. I don't."* The state is still
tracked — the App menu still reads "Notifications — BLOCKED by macOS", and
App ▸ Check Notifications Work… still explains it in full **when he asks**. The
unprompted modal is what he rejected, not the information.

## Why a wrapper and not a real client (2026-07-25)

Four options were put to Labern with the trade-offs stated plainly:

| approach | power | risk |
|---|---|---|
| WhatsApp Web protocol via Baileys — link the number, read/send programmatically: full-history search, scheduled sends, digests, AI drafting | highest | unofficial; real if small chance of the **number being banned** |
| **wrap web.whatsapp.com in a themed native shell** | UI/UX only | **none** |
| offline analysis of exported chats | read-only snapshots | none |
| Business Cloud API bot | official | needs a separate business number |

He chose the **wrapper**, on **macOS native**. So: no protocol work, no ban
exposure, and the ceiling is whatever can be done to the page from outside. That
ceiling turned out to be higher than expected because of the design-token
discovery below.

## The discovery that made it worth building

Poked at the live site before writing anything. WhatsApp Web's colours all
resolve from ~163 semantic CSS custom properties (`--WDS-*`, 1513 with the `-RGB`
mirrors). Class names are obfuscated and churn; **token names are stable and
semantic**. That converts "hack a userstyle that breaks every deploy" into "point
a design system at a different palette" — which is why the theming is ~18 lines
per theme and durable.

Corollary worth remembering for any future WhatsApp work: reach for tokens and
`data-testid` / `data-navbar-item` / `aria-label`, never a class name.

## Deliberate calls, so they're not re-litigated

- **Normal title bar, not `.fullSizeContentView`.** WhatsApp's nav rail runs to
  the top of its own layout; traffic lights would sit on top of it. The titlebar
  is instead *tinted* to the active theme so the window reads as one object.
- **App keeps running when its window closes** (`…TerminateAfterLastWindowClosed
  = false`). A messenger shouldn't sign out because you hit ⌘W; ⌃⌥⌘W brings it
  back.
- **Resources read at runtime, not compiled in.** Theme edit + ⌘R, no rebuild —
  because he burns through whole design languages in an evening and the wiring
  underneath should stay stable while the skin changes.
- **Global hotkey is a three-modifier chord** (⌃⌥⌘W). Anything shorter shadows a
  character or a common app shortcut system-wide.
- **Pins store chat *names*, not ids.** Names are what he can see and edit;
  WhatsApp's internal ids carry phone numbers and would be opaque in a plist.
  Cost: renaming a contact breaks its pin. Judged the right trade.

## Verified live vs. code-complete-but-unverified

Verified end-to-end by `smoketest.swift` against the real site (30/30):
injection, CSS parsing, token remapping in all themes, hide attributes, privacy
on/off, the Notification bridge reaching native with title/body intact, and the
badge pump (`(7) WhatsApp` → 7).

Verified by hand in Chrome against his logged-in session (structure only, no
message content read, nothing clicked, nothing marked read): the nav-rail hooks,
the chat-list testids, and that the React search input responds to the native
setter + `input` event — the mechanism ⌘1–9 relies on.

**Not yet exercised in a real signed run:** the ⌘1–9 pin jumps and ⌘⇧P pinning
(need a linked session), the global hotkey, macOS notification *delivery* (the
bridge is proven; the OS-side authorisation prompt only happens in the real app),
replying from a notification, downloads, and companion mode's collapse with a
chat actually open. All code-complete, none of it confirmed by eye.

The layout measurements companion mode depends on **were** taken against his real
logged-in session (rail 40px, `#side` 453px, its parent column 454px with a 64px
header) — that probe is what caught `tagList()` hiding the list but leaving the
search header stranded. Structure only; no message content read, nothing clicked,
nothing marked as read.

## The stated purpose, arrived at after the first build (2026-07-25)

His words: *"the main reason I even built this is so that I don't have to look at
my phone while I'm doing stuff on my Mac. So this is the key feature."*

That reordered the roadmap. Notification delivery stopped being a feature and
became the product; quiet hours went in but off by default, because a feature
that suppresses notifications is in tension with the point. The concrete
consequences are listed under "Why this app exists" in `../CLAUDE.md` — the App
Nap assertion, ⌘W not closing the connection, and the app shouting when macOS has
blocked notifications rather than going quiet.

Worth stating plainly for a future session: **the failure mode to fear here is
silence, not a crash.** A crash he'll see. A missed message he won't — he'll just
drift back to his phone and stop trusting the app. Prefer loud, honest failure
everywhere in this codebase.

## Second round of features (same day)

He asked for a small floating one-chat pop-up, named resizing / font selection /
font size, and said "build a bunch of stuff". Delivered: companion mode, always
on top, fade when inactive, font family (curated + any installed via the system
panel, which supplies the size too), message text size separate from window zoom,
menu-bar unread glance, reply-from-notification, quiet hours, focus mode.

Two things the parallel PICA session and his own live Chrome taught this app on
the same day, both now fixed here: the **JS dialog delegates** (without them
`confirm()` silently returns false) and the **storage-persistence refusal**.

## What this session cost, and what it bought (2026-07-26)

Focus mode took ~15 build/verify rounds, and the pattern in the failures is worth
keeping: **every wrong turn came from changing CSS without measuring first.** The
things that finally worked were measurements — the bubble-to-edge distance, the
composer's real text position via a Range, the layout widths in the diagnostics
file. The things that wasted rounds were plausible-looking selectors.

Three of the bugs were mine, introduced while fixing something else: killing
`background-image` (wiped every emoji), zeroing the bubble margins (dragged his own
messages left, which he described as "splayed all over the place"), and persisting a
programmatically-clamped window frame (lost full height). All three were invisible
to the smoke test because they were visual. **The lesson: for this app, look at it —
`mcp__computer-use__screenshot` plus `zoom` — before claiming anything is fixed.**

He also asked, twice, for things I had already built but buried (Contact Name Size
was called "Names & List Text"). Naming a control after the thing he sees on screen
matters more than naming it after what it does internally.

## Open threads

- **The name.** `CHAT` is a placeholder — he said "I'll decide later". Two lines
  in `build.sh`; leave `BUNDLE_ID` alone once the account is linked.
- **Default theme is `paradox`** (monospace everything + drifting purple-black).
  A bold default for a daily-driver messenger. If it's too much: `midnight` or
  `stock`, one line in `Settings.load()`, or just ⌘⌥T.
- **Hide rules for Status/Channels/Communities/Media lean on English
  `aria-label`s** as one of two selectors. The `data-navbar-item-index` selector
  covers other languages, but the index mapping was read off one build — if
  WhatsApp reorders the rail, re-check it.
- **Meta AI hiding** targets its logo `svg[id^=…]` and a chat row titled exactly
  "Meta AI". Both plausible to change; there's no token for it.
- Possible next: per-chat theme overrides, a menu-bar unread glance, "send
  later", and an Archive-everything-unpinned sweep. None asked for.
