// Cloudflare Worker entry. `wrangler deploy` from post/ serves the app (static
// assets) and this API from one origin, so the app needs no configuration.

import { connect } from 'cloudflare:sockets';
import { handle } from './api.js';

function wrap(socket) {
  const reader = socket.readable.getReader();
  const writer = socket.writable.getWriter();
  return {
    async read() { const { value, done } = await reader.read(); return done ? null : value; },
    write: (u8) => writer.write(u8),
    startTls() { reader.releaseLock(); writer.releaseLock(); return wrap(socket.startTls()); },
    close() { try { socket.close(); } catch {} },
  };
}

const open = async (hostname, port, tls) =>
  wrap(connect({ hostname, port }, { secureTransport: tls === 'implicit' ? 'on' : 'starttls', allowHalfOpen: false }));

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname.startsWith('/api/')) return handle(request, { open });
    return env.ASSETS ? env.ASSETS.fetch(request) : new Response('Not found', { status: 404 });
  },
};
