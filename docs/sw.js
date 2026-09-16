// Offline app-shell cache. Everything the "open app -> see a card -> show its
// barcode" path needs — including the barcode-drawing library — is self-hosted
// and listed here, so it works with zero connection, not just the UI shell.
// Never touches Google/Drive requests — those must always hit the network.
const CACHE_NAME = "carry-card-v2";
const SHELL_FILES = [
  "./",
  "./index.html",
  "./css/app.css",
  "./js/app.js",
  "./js/model.js",
  "./js/db.js",
  "./js/barcodeRender.js",
  "./js/barcodeScan.js",
  "./js/driveSync.js",
  "./js/sync.js",
  "./js/config.js",
  "./vendor/bwip-js-min.js",
  "./vendor/zxing-min.js",
  "./manifest.webmanifest",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/apple-touch-icon.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(async (cache) => {
      // One failed file shouldn't sink the whole install (cache.addAll is
      // all-or-nothing) — cache each file independently and keep going.
      await Promise.allSettled(
        SHELL_FILES.map(async (file) => {
          try {
            const response = await fetch(file, { cache: "no-cache" });
            if (response.ok) await cache.put(file, response);
          } catch {
            // offline on first install, or a transient network blip — the
            // fetch handler below will retry and cache it on next success.
          }
        })
      );
      await self.skipWaiting();
    })
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  const isThirdParty = url.origin !== self.location.origin;
  if (event.request.method !== "GET" || isThirdParty) return; // let Drive/Google requests pass through untouched

  event.respondWith(
    caches.match(event.request).then((cached) => {
      if (cached) return cached;
      return fetch(event.request).then((response) => {
        const copy = response.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
        return response;
      });
    })
  );
});
