# CHAT — a native macOS WhatsApp client

> **The name is a placeholder.** Labern deferred it ("I'll decide later").
> Renaming = change `APP_NAME` and `BUNDLE_ID` at the top of `build.sh`, rebuild,
> and optionally `git mv chat <newname>`. Nothing else refers to the name:
> `Shell.swift` reads it out of the bundle at runtime and the injected code is
> namespaced `shell`. **But** `BUNDLE_ID` keys the WebKit data store — changing it
> after the account is linked means scanning the QR code once more, so change the
> display name freely and leave the bundle id alone once it's in use.

Real `web.whatsapp.com` in a WKWebView, wrapped in a proper Mac app. It does
**not** touch the WhatsApp protocol — the account links exactly as a browser
links it, so there is no ban risk. What the wrapper adds is everything a browser
tab can't: a Dock tile with an unread badge, real macOS notifications, his own
themes, the furniture removed, ⌘1–9 jumps to pinned chats, a global summon
hotkey, and a privacy blur for screen-sharing.

## Files
- `Shell.swift` — the whole app (~700 lines). Window, menus, notifications,
  downloads, hotkey, settings.
- `Resources/theme.css` — the themes and every hide/blur rule.
- `Resources/shell.js` — the page half: Notification shim, badge pump, chat
  opening, privacy-coverage check.
- `build.sh [--install]` — icon → compile → sign → optionally install.
- `makeicon.swift` — the icon, drawn in code (speech bubble + block cursor).
- `smoketest.swift` — headless verification against the live site.

Both resource files are read from the bundle **at runtime**, so a theme tweak is
a file edit plus ⌘R — no recompile.

## Commands
```bash
./build.sh                 # → build/CHAT.app
./build.sh --install       # → also /Applications/CHAT.app
swiftc -O -swift-version 5 smoketest.swift -o build/smoketest && ./build/smoketest
```

## THE CONTRACT — don't break these
1. **`cfg.websiteDataStore` stays `.default()`.** That single line is why the
   WhatsApp link survives quitting. Anything non-persistent = re-scan the QR
   every launch. Same for `BUNDLE_ID`, which keys that store.
2. **Never style a WhatsApp class name.** Their classes are obfuscated and churn
   every deploy. Theme by re-pointing their `--WDS-*` design tokens — those are
   stable and semantic. See `theme.css` §2.
3. **Run the smoketest after any change** to `shell.js`, `theme.css` or the
   shell. It talks to the real site and catches CSS that didn't parse, a broken
   notification bridge, and token overrides that stopped resolving.
4. **Don't launch the GUI repeatedly to check things** — it steals his focus and
   he hates it. That's what the headless smoketest is for; launch the real app at
   most once, at the end.

## How the theming actually works
WhatsApp Web resolves every colour from ~163 semantic CSS custom properties
named `--WDS-*` (1513 including `-RGB` mirrors). `theme.css` declares a small
`--x-*` token set per theme (~18 values) and one shared block maps `--x-*` onto
all the `--WDS-*` that matter, with `!important`. So:
- a new theme costs ~18 lines,
- one attribute on `<html>` re-themes the whole app,
- a WhatsApp redeploy doesn't break it.

The mapping is repeated for `html, body, #app` on purpose: a custom property
declared lower in the tree shadows an inherited one, so if WhatsApp ever moves
its token block down onto `body`, an `html`-only override would silently lose.

Themes: `stock` (untouched), `midnight`, `paradox`, `monograph`. Default on first
launch is **paradox**; ⌘⌥T cycles.

## Why this app exists — read this before changing anything
**He built it so he never has to look at his phone while working on the Mac.**
That single sentence ranks every trade-off here: a message that fails to reach
him sends him back to his phone, and the app has failed at its only job. So:
- Notification delivery outranks every other feature. Never make it conditional
  on the window being open, focused, or visible.
- `ProcessInfo.beginActivity(.userInitiated)` is held for the whole app lifetime
  in `applicationDidFinishLaunching`. **Do not remove it.** Without it App Nap
  suspends a backgrounded app and its timers, WhatsApp's connection goes idle,
  and notifications stop — silently.
- `windowShouldClose` orders the window out instead of closing it, so ⌘W never
  severs the connection.
- If macOS has blocked notifications the app says so loudly (an alert at launch,
  the App-menu item renaming itself to "BLOCKED by macOS") rather than going
  quiet. App ▸ Check Notifications Work… re-checks and fires a real test one.

## Shortcuts
| | |
|---|---|
| ⌘1–9 | jump to pinned chat |
| ⌘⇧P | pin the open chat to the next free slot |
| ⌘⇧E | **companion mode** — shrink to a floating one-chat panel |
| ⌥⌘P | always on top |
| ⌘⇧F | focus mode (pinned chats only) |
| ⌘⌥T | next theme |
| ⌘⇧B | privacy blur |
| ⌘⌥+ / ⌘⌥- / ⌘⌥0 | message text bigger / smaller / default |
| ⌘+ / ⌘- / ⌘0 | zoom the whole interface |
| ⌘K / ⌘F | focus search |
| ⌘N | new chat |
| ⌘R | reload |
| ⌃⌥⌘W | **global** — summon or dismiss from any app |

## Companion mode
One chat, small, floating beside other work. It reuses the **one** webview —
WhatsApp Web allows a single active session per browser, so a second webview
would be told "WhatsApp is open in another window" and fight this one for the
connection. So ⌘⇧E shrinks and floats the existing window and collapses the
furniture with CSS. It keeps its own remembered frame (`companionFrame` in
defaults, updated as he resizes), separate from the full window, and is
deliberately **not** restored at launch — opening into a sliver would be
disorienting.

Measured live, which is why the selectors are what they are:
- the nav rail is a **40px** column whose container is an obfuscated div → found
  by walking up from `[data-navbar-item]` until one ancestor holds them all,
  then tagged `data-shell-rail`;
- `#side` is only the list (**453px**); its parent is the whole left column
  (**454px**) holding a 64px search header above it. `tagList()` therefore tags
  the *parent* — hiding only `#side` leaves an orphaned search strip. The width
  test (`parent ≤ side × 1.15`) is what tells "the column" from a broader wrapper.
- The list is collapsed only once a conversation is open and still has width
  without it (`data-shell-compact-list`), so a companion window with no chat open
  keeps the list and stays usable instead of being an empty box.

**Why it CROPPED before, and the two-part fix.** His report: *"it just crops it
without changing layout."* Measured against the real layout, the cause was two
things at once: the ancestors of the conversation carry **`min-width: auto`** (the
flex default, which refuses to shrink a flex item below its content) and several
carry **`overflow-x: hidden`** — so a narrower window clips the layout instead of
reflowing it. Hence:
1. `theme.css` §7 forces `min-width: 0` across `#app *` in compact mode, which is
   the standard fix for flex children that won't shrink; plus `width: 100vw` on
   `#app` and `overflow-x: hidden` on body.
2. `fitCompact()` in Shell.swift then asks the page (`__shell.compactFit()`) how
   much width it actually took and **zooms out just enough to fit**, in up to
   three passes because reflowing at the new zoom changes the answer. It eases
   back toward 1.0 when the panel is widened again. Floor is 0.55 — below that
   it's unreadable, and an unreadable panel is no better than a cropped one.

`fitCompact` logs `inner / scroll / rail / list / listHidden / convo` on its first
pass. If companion mode ever looks wrong again, read that line first
(`log show --predicate 'process == "CHAT"' --last 5m | grep "companion fit"`):
if `rail` or `list` is false, the tagging failed and the zoom is not the problem.

## Verified DOM hooks (live, 2026-07-25)
Recorded because rediscovering them means poking at a logged-in account:
- Nav rail: `[data-navbar-item]` with `aria-label` of Chats / Calls / Status /
  Channels / Communities / Media / You, and `data-navbar-item-index` 0–5 (Calls
  has none). Hide rules use **both** — the label is English-only, the index isn't.
- Chat list: `[data-testid="chat-list"]`, rows `[data-testid^="list-item-"]`,
  name in `[data-testid="cell-frame-title"] span[title]`, preview in
  `cell-frame-secondary`, timestamp in `cell-frame-primary-detail`.
- Search: `input[data-tab="3"]`. React owns its value — assigning `.value` is
  ignored; you need the native setter plus a bubbling `input` event
  (`setSearch()` in shell.js). Verified working live.
- Unread total: WhatsApp writes it into `document.title` as `(3) WhatsApp`. More
  reliable than summing unread pills, which include muted chats and only the
  rendered slice of a virtualised list.
- Meta AI: `svg[id^="WDSIconWdsIcLogoMetaAi"]`.
- Filter chips: `#all-filter`, `#additional-filters`, `[id^="label_item_"]`.
- Archived: `[data-testid="chatlist-panel-archived-button"]`. Nags:
  `[data-testid="chat-butterbar"]`.

## Notifications are silent by default
His verdict on the first version: *"Absurdly loud and annoying noise. Let's try no
noise. I change it if I want to."* Two separate sources had to be dealt with:
- the **macOS** notification sound (`content.sound`), and
- **WhatsApp's own in-page beep**, played through an `<audio>` element. This is the
  loud one, and silencing only the first would not have fixed it.

Both follow one switch, **App ▸ Notification Sound**, default **off**
(`sounds` in defaults). The page-side block is deliberately narrow: it swallows
only *programmatic* playback — audio started with no user gesture in the last
second — so pressing play on a voice note still works. **Looping audio is always
allowed through**, because that is what a ringtone is; an incoming call can still
ring. `play()` returns a resolved promise when swallowed, so WhatsApp's own code
doesn't throw.

## Building: never inside the repo
`build.sh` builds into `$TMPDIR/chat-build`, **not** the project directory, and
this is not a style preference. `~/Desktop` is iCloud-synced; the FileProvider
stamps `com.apple.fileprovider.fpfs#P` and `com.apple.FinderInfo` onto newly
created directories, and `codesign` then rejects the bundle with *"resource fork,
Finder information, or similar detritus not allowed"*. `xattr -cr` cannot reliably
win that race — sync re-adds the attribute between clearing and signing — so
builds fail **intermittently**, which is far worse than failing every time. Two
builds succeeded before one failed this way. Override with `CHAT_BUILD_DIR` if
needed, but keep it out of any synced folder.

## Gotchas paid for already
- **WKWebView has no Notification API at all.** Unpatched, WhatsApp Web
  feature-detects, finds nothing and stays silent forever — it never even offers.
  `shell.js` installs a shim *unconditionally* (not just when missing) and
  forwards to `UNUserNotificationCenter`; a half-working native implementation
  reporting `denied` would leave him silently un-notified, which is the exact
  failure this app exists to fix.
- **Privacy blur must not fail silently.** It's scoped to `[data-shell-convo]`,
  a tag `shell.js` puts on the conversation pane itself (preferring `#main`,
  falling back to the composer's tall ancestor), and it checks at runtime whether
  any per-message hook actually matched. If none did it sets
  `data-shell-privacy-fallback` and blurs the whole pane. Coarse beats lying.
- **Uploads and downloads need delegates.** Without `runOpenPanelWith` the
  attach button does nothing; without `WKDownloadDelegate` saving media fails
  quietly. Both implemented; downloads never overwrite (`photo-2.jpg`).
- **Mic/camera need both** an Info.plist usage string *and*
  `requestMediaCapturePermissionFor` returning `.grant`, or voice notes die.
- **WKWebView answers `confirm()`/`prompt()` with false/nil and swallows
  `alert()`** unless the app implements the three JS dialog delegates. Any
  WhatsApp flow built on a confirmation ("Delete message?", "Log out?") then
  silently does nothing. All three are implemented as window sheets. (Same bug
  was found and fixed in PICA the same day — check there if it regresses.)
- **`navigator.storage.persist()` is refused**, and WhatsApp logs
  `aquire-persistent-storage-denied` on every boot and may trim its caches in
  response. Observed live in Chrome too, so it isn't a WKWebView quirk.
  `shell.js` answers `true`. That is accurate here for a different reason than in
  a browser: this is the app's own container, not site data competing for a
  shared quota, so nothing evicts it.
- **Page errors are invisible in a WKWebView** — there's no console to look at.
  `shell.js` forwards `error`, `unhandledrejection` and `console.error` to the
  app (capped at 40 so a shouting page can't flood), which NSLogs them, and the
  smoke test fails if the count spikes.
- **Replying from a notification verifies before sending.** `replyTo()` inserts
  via `execCommand('insertText')` (WhatsApp's editor listens for real
  `beforeinput`/`input` events; assigning `textContent` is ignored), then
  compares the composer's contents against the intended text and **refuses to
  press send on a mismatch**, reporting why. Sending the wrong thing to a real
  person is not a recoverable error. Don't "simplify" that check away.
- `-swift-version 5` is required: the Carbon hot-key callback is a C function
  pointer and trips strict concurrency otherwise.
- Non-WhatsApp URLs are handed to the default browser, which also means a
  hostile link can't navigate the logged-in session somewhere else.

## Working style
Use sub-agents freely: fan-out searches, DOM-hook archaeology across WhatsApp
builds, cross-file investigations. Delegate the noisy work and keep only the
conclusions in the main thread.

Two standing cautions when working on this:
- It's a **live account**. Don't click chat rows or send anything while probing;
  opening a chat marks messages read. Read structure, never message content.
- Ask before naming anything.
