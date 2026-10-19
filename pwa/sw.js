// Bump this version with every app-shell release. User data is in IndexedDB,
// outside the service worker cache, and MUST NEVER be purged on updates.
const CACHE = "vtt-mobile-shell-v84";
const CATALOGS = ["/catalog/backgrounds.json", "/catalog/features.json", "/catalog/items.json", "/catalog/miniatures.json"];
const SHELL = ["/", "/index.html", "/main.js", "/ui.js", "/trait_projection.js", "/spell_metadata.js", "/condition_catalog.js", "/chat_notifications.js", "/action_economy.js", "/icons/action_dashboard_gloss.svg", "/icons/action_extras.svg", "/icons/gold_generated/gold_0.svg", "/icons/gold_generated/gold_1.svg", "/icons/gold_generated/gold_2.svg", "/icons/gold_generated/gold_3.svg", "/icons/info/identity.svg", "/icons/info/physique.svg", "/icons/info/progression.svg", "/icons/info/talents.svg", "/icons/info/biography.svg", "/catalog/species_types.json", "/feature_mechanics.js", "/native_sheet.js", "/item_controls.js", "/documents.js", "/spell_selection.js", "/activated_abilities.js", "/character_core.js", "/class_spells.js", "/class_trackers.js", "/quick_homebrew.js", "/sheet_rules.js", "/structured_effects.js", "/sheet_rules_view.js", "/demo.js", "/tactical_view.js", "/session_map.js", "/catalog_data.js", "/styles.css", "/mobile_metal_theme.css", "/client.js", "/storage.js", "/creatures.js", "/creature_format.js",
  "/catalog/action_feature_overrides.json", "/catalog/combat_action_supplements_5etools.json", "/catalog/combat_actions_5etools.json", "/icons/action_controls.svg", "/catalog/effects_5etools.json", "/catalog/feature_timing_recovery_rules.json", "/catalog/classes.json", "/catalog/ability_grants.json", "/catalog/activated_abilities.json", "/catalog/class_resource_overrides.json", "/catalog/class_mechanics.json", "/catalog/proficiency_grants.json", "/catalog/player.json", "/catalog/spells.json", "/manifest.webmanifest", "/icon.svg", "/icon-192.png", "/icon-512.png"];

// Catalog JSONs can be very large and the Godot host has limited concurrent
// connections. Downloading everything with cache.addAll() during install can
// starve the actual UI requests and fail the whole worker on one bad response.
// Prioritize code needed for offline startup. Decorative icons and large
// catalogs are cached on demand instead of competing with module downloads.
// Installation is atomic for executable code and essential character rules:
// a partial cache must NEVER replace a previously working offline version.
const CORE_SHELL = SHELL.filter(path =>
  path === "/" || /\.(?:html|js|css|webmanifest)$/.test(path));
const REQUIRED_CATALOGS = [
  "/catalog/ability_grants.json", "/catalog/class_mechanics.json",
  "/catalog/proficiency_grants.json", "/catalog/classes.json",
  "/catalog/player.json", "/catalog/spells.json",
  "/catalog/feature_timing_recovery_rules.json",
  "/catalog/activated_abilities.json", "/catalog/effects_5etools.json", "/catalog/species_types.json",
  "/catalog/action_feature_overrides.json", "/catalog/combat_actions_5etools.json"
];
const REQUIRED_SHELL = [...new Set([...CORE_SHELL, ...REQUIRED_CATALOGS])];
const OPTIONAL_SHELL = [...new Set([...SHELL, ...CATALOGS])]
  .filter(path => !REQUIRED_SHELL.includes(path));

function usableResponse(path, response) {
  if (!response?.ok) return false;
  // A reverse proxy can occasionally serve a 200 HTML fallback for a .js
  // request. WebKit rejects it as a module; never poison our offline cache.
  if (/\.js$/.test(path) &&
      !/javascript|ecmascript/i.test(response.headers.get("content-type") || "")) return false;
  return true;
}

async function cacheAssets(paths, required = false) {
  const cache = await caches.open(CACHE);
  const queue = [...paths];
  const failures = [];
  // iOS limits parallel origin connections. Module startup gets priority;
  // optional compendia must never monopolize Safari's connection slots.
  const concurrency = required ? 2 : 1;
  await Promise.all(Array.from({ length: Math.min(concurrency, queue.length) }, async () => {
    while (queue.length) {
      const path = queue.shift();
      try {
        if (!required && await cache.match(path)) continue;
        const response = await fetch(path, { cache: "no-store" });
        if (!usableResponse(path, response))
          throw new Error("HTTP " + response.status + " (" + (response.headers.get("content-type") || "unknown MIME") + ")");
        await cache.put(path, response);
      } catch (error) {
        failures.push(path);
        console.warn("VTT offline asset unavailable:", path, error);
      }
    }
  }));
  if (required && failures.length)
    throw new Error("Incomplete VTT offline shell: " + failures.join(", "));
}
self.addEventListener("install", event => {
  self.skipWaiting();
  event.waitUntil(cacheAssets(REQUIRED_SHELL, true));
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
  // Large, optional compendia and decorative icons are downloaded after the
  // required shell activates. An unavailable server cannot break offline boot.
  if (event.data?.type === "CACHE_OPTIONAL")
    event.waitUntil(cacheAssets(OPTIONAL_SHELL));
});
self.addEventListener("fetch", event => {
  const url = new URL(event.request.url);
  if (event.request.method !== "GET" || url.origin !== self.location.origin ||
      url.pathname.startsWith("/api/")) return; // Never cache game state/credentials.
  if (!SHELL.includes(url.pathname) && !CATALOGS.includes(url.pathname)) return;

  // Store by path, not by request URL: /?open=chat must still use the cached /.
  const network = fetch(event.request, { cache: "no-store" });
  event.waitUntil(network.then(response => {
    if (!usableResponse(url.pathname, response)) return;
    const copy = response.clone();
    return caches.open(CACHE).then(cache => cache.put(url.pathname, copy));
  }).catch(error => console.warn("VTT offline caching skipped:", error)));
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const cached = await cache.match(url.pathname);
    let timer;
    try {
      // An unreachable desktop or HTTPS reverse proxy may hang without
      // rejecting promptly. Prefer the cached version after a short grace.
      const response = await Promise.race([
        network, new Promise(resolve => { timer = setTimeout(() => resolve(null), 1800); })
      ]);
      if (usableResponse(url.pathname, response)) return response;
      // Tailscale Serve may return 502/504 (not just 503) when Godot is down.
      if (cached) return cached;
      if (response) return response;
      return await network;
    } catch (_) {
      return cached || Response.error();
    } finally {
      clearTimeout(timer);
    }
  })());
});

// Open the existing PWA window from a system notification, or launch it.
self.addEventListener("notificationclick", event => {
  event.notification.close();
  event.waitUntil((async () => {
    const url = new URL(event.notification.data?.url || "/?open=chat", self.location.origin);
    if (url.origin !== self.location.origin) return;
    const windows = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    const existing = windows.find(client => new URL(client.url).origin === self.location.origin);
    if (existing) {
      await existing.focus();
      existing.postMessage({ type: "OPEN_CHAT" });
    } else if (self.clients.openWindow) {
      await self.clients.openWindow(url.href);
    }
  })());
});
