// Offline shell: network-first for code/data (always fresh when online),
// cache-first for images. Bump VERSION to drop old caches.
const VERSION = 'gt7-v11';
self.addEventListener('install', (e) => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== VERSION).map((k) => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  const isImg = /\.(jpg|png|svg|woff2?)$/.test(url.pathname);
  if (isImg) {
    e.respondWith(caches.match(req).then((hit) => hit || fetch(req).then((res) => { const c = res.clone(); caches.open(VERSION).then((ca) => ca.put(req, c)); return res; })));
  } else {
    e.respondWith(fetch(req).then((res) => { const c = res.clone(); caches.open(VERSION).then((ca) => ca.put(req, c)); return res; }).catch(() => caches.match(req)));
  }
});
