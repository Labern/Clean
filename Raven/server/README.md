# Raven server

One Node process. Holds the WhatsApp linked-device session, pushes events to
the car over a WebSocket, serves the phone setup page and the public JSON
behind live-location links. Runs on your Mac; Tailscale Funnel gives it a
stable public HTTPS address for free.

## First run (Mac)

```sh
# Node ≥ 22.13 (node:sqlite without a flag). `brew install node` is fine.
cd Clean/Raven/server
npm install --omit=peer
export APP_SECRET="$(openssl rand -base64 24 | tr -d '/+=' )"; echo "$APP_SECRET"   # keep it
APP_SECRET=$APP_SECRET node index.mjs
```

Open `http://localhost:8787/setup?key=$APP_SECRET` on the Mac, or from the
phone once Funnel is up. Scan the QR (WhatsApp → Linked devices). The
session persists in `data/wa-auth/`; you won't scan again unless you unlink.

## Public address (free)

```sh
brew install tailscale           # or the Mac App Store app
tailscale up                     # sign in; enable MagicDNS + HTTPS in the admin console (DNS tab)
tailscale funnel --bg 8787       # https://<mac-name>.<tailnet>.ts.net → localhost:8787
tailscale funnel status
```

Set `PUBLIC_URL=https://<mac-name>.<tailnet>.ts.net` in the environment so
share links use it (otherwise the server guesses from the request).

## Keep it running

`raven.plist` is a launchd job. Edit the two paths and the secret, then:

```sh
cp raven.plist ~/Library/LaunchAgents/com.labern.raven.plist
launchctl load -w ~/Library/LaunchAgents/com.labern.raven.plist
tail -f /tmp/raven.log
```

The Mac must stay awake: System Settings → Energy → Prevent automatic
sleeping when the display is off (or `caffeinate -s` in the plist).

## Environment

| var | default | what |
|---|---|---|
| `APP_SECRET` | required | the key the car and setup page present |
| `PORT` | 8787 | |
| `DATA_DIR` | `./data` | SQLite + WhatsApp auth |
| `PAGES_ORIGIN` | `https://labern.github.io` | allowed CORS origin(s), comma-separated |
| `PUBLIC_URL` | from request | used in share links |
| `OWNER_NAME` | `Raven` | the name a live-link recipient sees ("Luke is sharing their location") |
| `LIVE_PAGE` | `https://labern.github.io/Clean/Raven/live/` | recipient page |
| `WA_DEMO` | off | synthetic WhatsApp traffic, no network |
| `WA_LOG` | silent | pino level for Baileys (`info` when debugging) |

## Demo

```sh
npm run demo      # APP_SECRET=dev, synthetic messages every 20 s
```
Then `http://localhost:8765/Raven/?key=dev&server=http://localhost:8787` with
the static server from `Clean/` (`python3 -m http.server 8765`).

## Protocol

Server → car: `wa.status`, `wa.qr {svg}`, `wa.chats {chats, unread}`,
`wa.message {name, chat, ts}`, `wa.canned {canned}`, `share.state {shares}`,
`car.pos`, `wa.sent`, `wa.shared {token, url}`, `error {of, message}`.
Car → server: `car.pos {lat,lng,speed,heading,ts}`, `wa.send {chat,text}`,
`wa.read {chat}`, `wa.share {chat, minutes, refreshMin}`, `wa.share.stop {token}`,
`wa.location {chat, lat, lng}`, `ping`.

REST mirrors the same under `/api/*` (Bearer `APP_SECRET`); `/api/live/:token`
is public and returns `{name, active, expires, pos, trail}` for the live page.

Nothing here stores message text. `wa_events` is timestamps and names.
