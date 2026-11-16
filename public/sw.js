// Neon Cruise service worker: offline app shell, never touches the live audio or metadata streams.
const VERSION = 'neoncruise-v4';
// Works at the domain root or under a subpath (e.g. GitHub Pages /<repo>/).
const BASE = new URL('./', self.location).pathname;
const SHELL = ['', 'manifest.webmanifest', 'icons/icon.svg', 'icons/icon-192.png', 'icons/icon-512.png'].map((p) => BASE + p);

/**
 * The first visit happens before the worker controls the page, so the hashed JS/CSS it loaded
 * never went through `fetch` below and the app wouldn't start offline until a second visit.
 * Scan the shell HTML for its build assets and precache them too (best effort).
 */
async function precache() {
  const c = await caches.open(VERSION);
  await c.addAll(SHELL);
  try {
    const html = await (await c.match(BASE)).text();
    const re = new RegExp(`${BASE}_astro/[\\w./-]+\\.(?:js|css|woff2)`, 'g');
    const assets = [...new Set(html.match(re) ?? [])];
    await Promise.all(assets.map((a) => c.add(a).catch(() => {})));
  } catch {
    /* runtime caching below still picks assets up */
  }
}

self.addEventListener('install', (event) => {
  event.waitUntil(precache().then(() => self.skipWaiting()));
});

/** Keep the worker alive until the write lands (otherwise it can be killed mid-put). */
const store = (event, key, res) => event.waitUntil(caches.open(VERSION).then((c) => c.put(key, res)));

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
          // Never let a 404/5xx (or a redirect) replace the offline shell.
          if (res.ok && res.type === 'basic') store(event, BASE, res.clone());
          return res;
        })
        .catch(() => caches.match(BASE)),
    );
    return;
  }

  // Only same-origin requests are cached (fonts are self-hosted now). Opaque cross-origin
  // responses are padded to several MB each against the storage quota, so never store them.
  if (url.origin !== location.origin) return;

  // Hashed build assets (JS, CSS, fonts): cache first.
  if (url.pathname.startsWith(`${BASE}_astro/`)) {
    event.respondWith(
      caches.match(req).then(
        (hit) =>
          hit ||
          fetch(req).then((res) => {
            if (res.ok) store(event, req, res.clone());
            return res;
          }),
      ),
    );
    return;
  }

  // Everything else (icons, manifest): stale-while-revalidate.
  event.respondWith(
    caches.match(req).then((hit) => {
      const net = fetch(req)
        .then((res) => {
          if (res.ok) store(event, req, res.clone());
          return res;
        })
        .catch(() => hit ?? Response.error());
      if (hit) event.waitUntil(net.catch(() => {}));
      return hit || net;
    }),
  );
});
