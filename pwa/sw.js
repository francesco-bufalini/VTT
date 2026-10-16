// Only immutable-ish application shell resources are cached here.
// IndexedDB, not Cache Storage, owns characters, homebrew and image files.
const CACHE = "vtt-pwa-shell-v1";
const SHELL = ["./", "./index.html", "./app.js", "./network.js",
  "./storage.js", "./manifest.webmanifest", "./icon.svg"];
self.addEventListener("install", event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(SHELL)));
  self.skipWaiting();
});
self.addEventListener("activate", event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys
    .filter(name => name.startsWith("vtt-pwa-shell-") && name !== CACHE)
    .map(name => caches.delete(name)))));
  self.clients.claim();
});
self.addEventListener("fetch", event => {
  if (event.request.method !== "GET") return;
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin || url.pathname.startsWith("/api/")) return;
  event.respondWith(caches.match(event.request).then(hit => hit || fetch(event.request)));
});
