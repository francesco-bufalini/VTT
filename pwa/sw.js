// Bump this version with every app-shell release. User data is in IndexedDB,
// outside the service worker cache, and MUST NEVER be purged on updates.
const CACHE = "vtt-mobile-shell-v53";
const CATALOGS = ["/catalog/backgrounds.json", "/catalog/features.json", "/catalog/items.json", "/catalog/miniatures.json"];
const SHELL = ["/", "/index.html", "/main.js", "/ui.js", "/action_economy.js", "/icons/action_dashboard_gloss.svg", "/icons/action_extras.svg", "/icons/gold_generated/gold_0.svg", "/icons/gold_generated/gold_1.svg", "/icons/gold_generated/gold_2.svg", "/icons/gold_generated/gold_3.svg", "/icons/info/identity.svg", "/icons/info/physique.svg", "/icons/info/progression.svg", "/icons/info/talents.svg", "/icons/info/biography.svg", "/catalog/species_types.json", "/feature_mechanics.js", "/native_sheet.js", "/item_controls.js", "/documents.js", "/spell_selection.js", "/activated_abilities.js", "/character_core.js", "/class_spells.js", "/class_trackers.js", "/quick_homebrew.js", "/sheet_rules.js", "/structured_effects.js", "/sheet_rules_view.js", "/demo.js", "/tactical_view.js", "/session_map.js", "/catalog_data.js", "/styles.css", "/mobile_metal_theme.css", "/client.js", "/storage.js", "/creatures.js", "/creature_format.js",
  "/catalog/action_feature_overrides.json", "/catalog/combat_action_supplements_5etools.json", "/catalog/combat_actions_5etools.json", "/icons/action_controls.svg", "/catalog/feature_timing_recovery_rules.json", "/catalog/classes.json", "/catalog/ability_grants.json", "/catalog/activated_abilities.json", "/catalog/class_resource_overrides.json", "/catalog/class_mechanics.json", "/catalog/proficiency_grants.json", "/catalog/player.json", "/catalog/spells.json", "/manifest.webmanifest", "/icon.svg", "/icon-192.png", "/icon-512.png"];

// Catalog JSONs can be very large and the Godot host has limited concurrent
// connections. Downloading everything with cache.addAll() during install can
// starve the actual UI requests and fail the whole worker on one bad response.
// Prioritize code needed for offline startup. Decorative icons and large
// catalogs are cached on demand instead of competing with module downloads.
const CORE_SHELL = SHELL.filter(path =>
  path === "/" || /\.(?:html|js|css|webmanifest)$/.test(path));
self.addEventListener("install", event => {
  self.skipWaiting();
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    for (const path of CORE_SHELL) {
      try {
        const response = await fetch(path, { cache: "no-store" });
        if (response.ok) await cache.put(path, response);
      } catch (error) {
        console.warn("VTT offline asset unavailable:", path, error);
      }
    }
  })());
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
  // Return the network response as soon as it arrives: a slow CacheStorage
  // write must never delay a JavaScript module response during startup.
  const network = fetch(event.request, { cache: "no-store" });
  event.waitUntil(network.then(response => {
    if (!response.ok) return;
    const copy = response.clone();
    return caches.open(CACHE).then(cache => cache.put(event.request, copy));
  }).catch(error => console.warn("VTT offline caching skipped:", error)));
  event.respondWith((async () => {
    // Prefer files from the currently running native desktop. Only use the
    // offline copy if the desktop is unreachable/temporarily unavailable.
    try {
      const response = await network;
      if (response.status !== 503) return response;
    } catch (_) { /* Desktop is offline. */ }
    const cache = await caches.open(CACHE);
    return (await cache.match(event.request)) || Response.error();
  })());
});
