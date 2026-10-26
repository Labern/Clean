# GT7 Endgame bridge

Reads Gran Turismo 7's telemetry from your PS5, records every lap, and serves
the app on your Mac so phone and Mac can see live data and replay laps.

```
node gt7/bridge/gt7-bridge.mjs --ps5 192.168.1.23   # PS5 IP: Settings → Network → Connection Status
node gt7/bridge/gt7-bridge.mjs --ps5 auto           # broadcast discovery
node gt7/bridge/gt7-bridge.mjs --demo               # synthetic Spa lap, no PS5 needed
```

Open `http://localhost:8787` (Mac) or the printed `http://<mac-ip>:8787` (phone).
Laps are written to `~/GT7Laps/*.json` (`--laps <dir>` to change) and picked up
by the app, which syncs them to your account.

- Node 18+, no dependencies. Mac and PS5 on the same network.
- Protocol in `protocol.mjs`: heartbeat `~` to UDP 33739, packets on 33740,
  Salsa20 (key "Simulator Interface Packet GT7 ver 0.0"[:32], nonce
  `(iv ^ 0x55FABB4F) ‖ iv`, iv = uint32 LE at 0x40). `--type A` for the basic
  296-byte packet.
- API: `/api/status`, `/api/laps`, `/api/laps/<id>`, `/api/live` (SSE, 10 Hz).
