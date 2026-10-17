// Bump this version with every app-shell release. User data is in IndexedDB,
// outside the service worker cache, and MUST NEVER be purged on updates.
const CACHE = "vtt-mobile-shell-v40";
const CATALOGS = ["/catalog/backgrounds.json", "/catalog/features.json", "/catalog/items.json"];
const SHELL = ["/", "/index.html", "/main.js", "/ui.js", "/action_economy.js", "/icons/character_tabs.png", "/icons/action_dashboard_gloss.svg", "/icons/action_extras.svg", "/icons/gold_generated/gold_0.svg", "/icons/gold_generated/gold_1.svg", "/icons/gold_generated/gold_2.svg", "/icons/gold_generated/gold_3.svg", "/feature_mechanics.js", "/native_sheet.js", "/item_controls.js", "/documents.js", "/spell_selection.js", "/activated_abilities.js", "/character_core.js", "/class_spells.js", "/class_trackers.js", "/quick_homebrew.js", "/sheet_rules.js", "/structured_effects.js", "/sheet_rules_view.js", "/demo.js", "/tactical_view.js", "/catalog_data.js", "/styles.css", "/mobile_metal_theme.css", "/client.js", "/storage.js", "/creatures.js", "/creature_format.js",
  "/catalog/action_feature_overrides.json", "/catalog/combat_action_supplements_5etools.json", "/catalog/combat_actions_5etools.json", "/icons/action_controls.svg", "/catalog/feature_timing_recovery_rules.json", "/catalog/classes.json", "/catalog/ability_grants.json", "/catalog/activated_abilities.json", "/catalog/class_resource_overrides.json", "/catalog/class_mechanics.json", "/catalog/proficiency_grants.json", "/catalog/player.json", "/catalog/spells.json", "/manifest.webmanifest", "/icon.svg", "/icon-192.png", "/icon-512.png"];

// Catalog JSONs can be very large and the Godot host has limited concurrent
// connections. Downloading everything with cache.addAll() during install can
// starve the actual UI requests and fail the whole worker on one bad response.
// Only small application files are warmed; catalogs are cached as requested.
const CORE_SHELL = SHELL.filter(path => !path.startsWith("/catalog/"));
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
