// WebSocket hub: every connected page (the car, the phone setup page) gets
// every event; the last value of each type is replayed on connect so a tile
// is never blank while it waits for the next tick.

export function createHub() {
  const clients = new Set();
  const last = new Map();
  const handlers = new Set();

  function send(ws, type, data) {
    if (ws.readyState !== 1) return false;
    try { ws.send(JSON.stringify({ type, data })); return true; } catch { return false; }
  }

  return {
    get size() { return clients.size; },
    last,
    add(ws, meta = {}) {
      ws.meta = meta;
      clients.add(ws);
      for (const [type, data] of last) send(ws, type, data);
      ws.on('message', (raw) => {
        let msg; try { msg = JSON.parse(String(raw)); } catch { return; }
        if (!msg || typeof msg.type !== 'string') return;
        for (const fn of handlers) {
          try { fn(msg.type, msg.data, ws); } catch (e) { console.error(`[hub] ${msg.type}`, e.message); }
        }
      });
      ws.on('close', () => clients.delete(ws));
      ws.on('error', () => clients.delete(ws));
    },
    broadcast(type, data, { remember = true } = {}) {
      if (remember) last.set(type, data);
      let n = 0;
      for (const ws of clients) if (send(ws, type, data)) n++;
      return n;
    },
    send,
    onMessage(fn) { handlers.add(fn); return () => handlers.delete(fn); },
    forget(type) { last.delete(type); },
    close() { for (const ws of clients) { try { ws.close(); } catch {} } clients.clear(); },
  };
}
