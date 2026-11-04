// Neon Cruise service worker: offline app shell, never touches the live audio or metadata streams.
const VERSION = 'neoncruise-v3';
// Works at the domain root or under a subpath (e.g. GitHub Pages /<repo>/).
const BASE = new URL('./', self.location).pathname;
const SHELL = ['', 'manifest.webmanifest', 'icons/icon.svg', 'icons/icon-192.png', 'icons/icon-512.png'].map((p) => BASE + p);

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(VERSION).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  // Live radio, now-playing feed and listener stats must always hit the network.
  if (url.hostname.endsWith('nightride.fm')) return;
  if (req.headers.get('accept')?.includes('text/event-stream')) return;

  // Pages: network first so updates land, cached shell when offline.
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(VERSION).then((c) => c.put(BASE, copy));
          return res;
        })
        .catch(() => caches.match(BASE)),
    );
    return;
  }

  // Hashed build assets and fonts: cache first.
  const immutable =
    (url.origin === location.origin && url.pathname.startsWith(`${BASE}_astro/`)) ||
    url.hostname === 'fonts.gstatic.com';
  if (immutable) {
    event.respondWith(
      caches.match(req).then(
        (hit) =>
          hit ||
          fetch(req).then((res) => {
            if (res.ok || res.type === 'opaque') {
              const copy = res.clone();
              caches.open(VERSION).then((c) => c.put(req, copy));
            }
            return res;
          }),
      ),
    );
    return;
  }

  // Everything else (icons, font CSS): stale-while-revalidate.
  if (url.origin === location.origin || url.hostname === 'fonts.googleapis.com') {
    event.respondWith(
      caches.match(req).then((hit) => {
        const net = fetch(req)
          .then((res) => {
            if (res.ok) {
              const copy = res.clone();
              caches.open(VERSION).then((c) => c.put(req, copy));
            }
            return res;
          })
          .catch(() => hit);
        return hit || net;
      }),
    );
  }
});
