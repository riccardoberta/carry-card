// Minimal offline app-shell cache. Never touches Google/Drive requests — those
// must always hit the network for auth to work correctly.
const CACHE_NAME = "carry-card-v1";
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
  "./manifest.webmanifest",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/apple-touch-icon.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_FILES)).then(() => self.skipWaiting())
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
  if (event.request.method !== "GET" || isThirdParty) return; // let Drive/Google/CDN requests pass through untouched

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
