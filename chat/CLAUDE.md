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

## Shortcuts
| | |
|---|---|
| ⌘1–9 | jump to pinned chat |
| ⌘⇧P | pin the open chat to the next free slot |
| ⌘⌥T | next theme |
| ⌘⇧B | privacy blur |
| ⌘K / ⌘F | focus search |
| ⌘N | new chat |
| ⌘R | reload |
| ⌃⌥⌘W | **global** — summon or dismiss from any app |

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
