// The one WebSocket between the car and the server. Reconnects with backoff,
// republishes every server event onto the bus, and reports link state.

import { emit } from './bus.js';

export function createLink({ server, key, WS = globalThis.WebSocket }) {
  let ws = null, tries = 0, closed = false, timer = null;
  const state = { status: 'off' }; // off | connecting | on | retry

  function set(status) { state.status = status; emit('link.status', { ...state }); }

  function connect() {
    if (closed || !server || !key || !WS) { set('off'); return; }
    set(tries ? 'retry' : 'connecting');
    const url = server.replace(/^http/, 'ws').replace(/\/$/, '') + `/ws?key=${encodeURIComponent(key)}`;
    try { ws = new WS(url); } catch { schedule(); return; }
    ws.onopen = () => { tries = 0; set('on'); };
    ws.onmessage = (ev) => {
      let msg; try { msg = JSON.parse(ev.data); } catch { return; }
      if (msg && msg.type) emit(msg.type, msg.data);
    };
    ws.onclose = () => { ws = null; if (!closed) schedule(); };
    ws.onerror = () => { try { ws?.close(); } catch {} };
  }
  function schedule() {
    set('retry');
    const wait = Math.min(30000, 1000 * 2 ** Math.min(tries++, 5));
    timer = setTimeout(connect, wait);
  }

  return {
    state,
    start() { closed = false; tries = 0; connect(); },
    stop() { closed = true; clearTimeout(timer); try { ws?.close(); } catch {} ws = null; set('off'); },
    send(type, data) {
      if (ws && ws.readyState === 1) { ws.send(JSON.stringify({ type, data })); return true; }
      return false;
    },
  };
}
