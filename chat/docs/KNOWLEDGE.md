# KNOWLEDGE — decisions and open threads

Technical facts, DOM hooks and gotchas live in `../CLAUDE.md` — this file holds
only what that doesn't: why the shape is what it is, and what's still open.

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
