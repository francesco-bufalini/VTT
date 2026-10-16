// Bump this version with every app-shell release. User data is in IndexedDB,
// outside the service worker cache, and MUST NEVER be purged on updates.
const CACHE = "vtt-mobile-shell-v21";
const CATALOGS = ["/catalog/backgrounds.json", "/catalog/features.json", "/catalog/items.json"];
const SHELL = ["/", "/index.html", "/main.js", "/ui.js", "/native_sheet.js", "/item_controls.js", "/documents.js", "/spell_selection.js", "/sheet_rules.js", "/structured_effects.js", "/sheet_rules_view.js", "/character_core.js", "/class_spells.js", "/quick_homebrew.js", "/demo.js", "/tactical_view.js", "/catalog_data.js", "/styles.css", "/client.js", "/storage.js", "/creatures.js", "/creature_format.js",
  "/catalog/classes.json", "/catalog/ability_grants.json", "/catalog/class_mechanics.json", "/catalog/proficiency_grants.json", "/catalog/player.json", "/catalog/spells.json", "/manifest.webmanifest", "/icon.svg", "/icon-192.png", "/icon-512.png"];

self.addEventListener("install", event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(SHELL)));
});
self.addEventListener("activate", event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(key => key.startsWith("vtt-mobile-shell-") &&
      key !== CACHE).map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});
self.addEventListener("message", event => {
  if (event.data?.type === "ACTIVATE_UPDATE") self.skipWaiting();
});
self.addEventListener("fetch", event => {
  const url = new URL(event.request.url);
  if (event.request.method !== "GET" || url.origin !== self.location.origin ||
      url.pathname.startsWith("/api/")) return; // Never cache game state/credentials.
  if (!SHELL.includes(url.pathname) && !CATALOGS.includes(url.pathname)) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    // Prefer new assets from the current native desktop installation.
    // The cached version is used only when offline. Never touch IndexedDB.
    try {
      const response = await fetch(event.request, { cache: "no-store" });
      if (response.ok) {
        await cache.put(event.request, response.clone());
        return response;
      }
      if (response.status !== 503) return response;
    } catch (_) { /* Desktop is offline. */ }
    return (await cache.match(event.request)) || Response.error();
  })());
});
