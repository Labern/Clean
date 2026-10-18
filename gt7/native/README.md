# GT7 Endgame: iOS & Android

The native apps are thin [Capacitor](https://capacitorjs.com) shells around the
exact same web code (`../`). No fork, no rewrite. What native adds:

- **PSN without the Mac bridge.** `app/platform.js` detects the shell and routes
  PSN + GT-Gridstats calls through native HTTP (no CORS), using the same
  `app/psn-core.js` the bridge uses. The PSN token stays on the device.
- Home-screen app, offline bundle, safe areas (notch, home indicator) already in the CSS.

Telemetry still needs the Mac bridge: GT7 streams UDP on your home network,
and a later native UDP plugin can replace it (the protocol is in
`../bridge/protocol.mjs`, ready to port).

## Build (on the Mac)
```
cd gt7/native
npm install
npm run ios       # opens Xcode: pick your team, run on your iPhone
npm run android   # opens Android Studio
```
After web changes: `npm run sync`.

App id `com.labern.gt7endgame`. Icons are in `../img/brand/` (512 px source;
generate the sets with `npx @capacitor/assets generate` if wanted). For
TestFlight, the repo's `iOS/` pipeline (`bin/ios-*`) can take the generated
Xcode project.

Storage: the save uses `localStorage`/IndexedDB inside the WebView, which is
persistent in the app container, and the encrypted cloud save backs it up.
