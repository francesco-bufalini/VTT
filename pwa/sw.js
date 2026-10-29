// Substituted by the host with the fingerprint of the actual served assets.
// Each deployed version gets an atomic app-shell cache; IndexedDB is untouched.
const REVISION = "__VTT_COMMIT_SHA__";
const CACHE = "vtt-mobile-shell-v198-" + REVISION;
const CATALOGS = ["/catalog/companion_spells.json", "/catalog/backgrounds.json", "/catalog/features.json", "/catalog/items.json", "/catalog/miniatures.json"];
const SHELL = [
  "/miniature-images/ore.webp",
  "/miniature-images/gilliam.webp",
  "/miniature-images/kaos.webp",
  "/miniature-images/kryss.webp",
  "/miniature-images/phenax.webp",
  "/miniature-images/sariel.webp",
  "/miniature-images/valandir.webp",
  "/miniature-images/wilfred.webp",
  "/miniature-images/wyrda.webp",
  "/miniature-images/nazaryl.webp",
  "/miniature-images/tiabald.webp",
  "/miniature-images/harmakis.webp",

  "/companion_rules.js",
  "/companion_owner_stats.js",
  "/creature_variants.js",
  "/creature_variants_view.js",
  "/concentration_rules.js",
  "/",
  "/index.html",
  "/main.js",
  "/version_gate.js",
  "/ui.js",
  "/ui_primitives.js",
  "/trait_benefits.js",
  "/trait_benefit_distribution.js",
  "/trait_benefit_editor.js",
  "/effect_extensions.js",
  "/monster_traits.js",
  "/trait_projection.js",
  "/spell_metadata.js",
  "/condition_catalog.js",
  "/exhaustion_rules.js",
  "/chat_notifications.js",
  "/action_economy.js",
  "/icons/action_dashboard_gloss.svg",
  "/icons/action_extras.svg",
  "/icons/gold_generated/gold_0.svg",
  "/icons/gold_generated/gold_1.svg",
  "/icons/gold_generated/gold_2.svg",
  "/icons/gold_generated/gold_3.svg",
  "/icons/info/identity.svg",
  "/icons/info/physique.svg",
  "/icons/info/progression.svg",
  "/icons/info/talents.svg",
  "/icons/info/biography.svg",
  "/catalog/species_types.json",
  "/catalog/species_attacks.json",
  "/catalog/species_defenses.json",
  "/catalog/species_roll_modes.json", "/catalog/species_conditional_bonuses.json",
  "/species_defenses.js",
  "/class_defenses.js",
  "/catalog/class_defense_rules.js",
  "/catalog/class_feature_operations.js",
  "/catalog/class_numeric_feature_grants.js",
  "/catalog/feature_feat_grants.js",
  "/species_variant_families.js",
  "/catalog/barbarian_2014_rules.js",
  "/catalog/supplemental_rules.js",
  "/armor_rules.js",
  "/armor_class_formula.js",
  "/species_roll_modes.js",
  "/species_origin_rules.js",
  "/species_conditional_bonuses.js",
  "/feature_mechanics.js",
  "/barbarian_2014.js",
  "/trait_state_rules.js",
  "/power_selection.js",
  "/slot_feature_powers.js",
  "/optional_feature_progression.js",
  "/native_sheet.js",
  "/identity_aliases.js",
  "/defense_summary.js",
  "/d20_rerolls.js",
  "/source_edition.js",
  "/item_controls.js",
  "/inventory_search.js",
  "/item_detail_facts.js",
  "/documents.js",
  "/spell_selection.js",
  "/species_powers.js",
  "/feature_rolls.js",
  "/zero_hp_responses.js",
  "/dragonborn_ftd.js",
  "/ability_areas.js",
  "/activated_abilities.js",
  "/character_core.js",
  "/level_up.js",
  "/character_portrait.js",
  "/quick_homebrew.js",
  "/character_homebrew.js",
  "/sheet_rules.js",
  "/skill_definitions.js",
  "/offhand_rules.js",
  "/sense_rules.js",
  "/catalog/sense_grants.json",
  "/ability_choice_rules.js",
  "/feat_picker.js",
  "/rule_supplements.js",
  "/structured_effects.js",
  "/attack_count_benefits.js",
  "/pending_choices.js",
  "/sheet_rules_view.js",
  "/sheet_roll_origin.js",
  "/demo.js",
  "/tactical_view.js",
  "/session_map.js",
  "/catalog_data.js",
  "/styles.css",
  "/mobile_metal_theme.css",
  "/client.js",
  "/share_transfer.js",
  "/inventory_transfer.js",
  "/storage.js",
  "/server_backups.js",
  "/server_backup_core.js",
  "/server_backup_worker.js",
  "/creatures.js",
  "/creature_format.js",
  "/catalog/action_feature_overrides.json",
  "/catalog/combat_action_supplements_5etools.json",
  "/catalog/combat_actions_5etools.json",
  "/icons/action_controls.svg",
  "/catalog/effects_5etools.json",
  "/catalog/feature_timing_recovery_rules.json",
  "/catalog/classes.json",
  "/catalog/ability_grants.json",
  "/catalog/activated_abilities.json",
  "/catalog/class_resource_overrides.json",
  "/catalog/class_mechanics.json",
  "/catalog/spell_grant_rules.json",
  "/catalog/species_powers.json",
  "/catalog/species_conditional_bonuses.json",
  "/catalog/trait_states.json",
  "/catalog/power_selections.json",
  "/catalog/slot_feature_powers.json",
  "/catalog/optional_feature_progressions.json",
  "/catalog/roll_bonus_rules.json",
  "/catalog/effect_extensions.json",
  "/catalog/proficiency_grants.json",
  "/catalog/player.json",
  "/catalog/spells.json",
  "/manifest.webmanifest",
  "/icon.svg",
  "/icon-192.png",
  "/icon-512.png",
  "/icon-1024.png",
  "/feature_item_grants.js",
  "/spell_storing_item.js",
  "/spell_imprints.js",
  "/spell_item_effects.js",
  "/attack_hit_effects.js",
  "/catalog/feature_item_grants.json"
];

// Catalog JSONs can be very large and the Godot host has limited concurrent
// connections. Downloading everything with cache.addAll() during install can
// starve the actual UI requests and fail the whole worker on one bad response.
// Prioritize executable code, essential rules, icon atlases and the miniature
// index. The full spell catalog downloads only in the optional background pass.
// Installation is atomic for executable code and essential character rules:
// a partial cache must NEVER replace a previously working offline version.
const CORE_SHELL = SHELL.filter(path =>
  path === "/" || /\.(?:html|js|css|webmanifest)$/.test(path));
const REQUIRED_CATALOGS = [
  "/catalog/ability_grants.json", "/catalog/class_mechanics.json",
  "/catalog/spell_grant_rules.json", "/catalog/species_powers.json", "/catalog/proficiency_grants.json", "/catalog/classes.json",
  "/catalog/player.json", "/catalog/sense_grants.json", "/catalog/species_roll_modes.json",
  "/catalog/feature_timing_recovery_rules.json", "/catalog/trait_states.json", "/catalog/power_selections.json",
  "/catalog/optional_feature_progressions.json",
  "/catalog/slot_feature_powers.json",
  "/catalog/roll_bonus_rules.json", "/catalog/feature_item_grants.json", "/catalog/effect_extensions.json",
  "/catalog/activated_abilities.json", "/catalog/effects_5etools.json", "/catalog/species_types.json", "/catalog/species_attacks.json", "/catalog/species_defenses.json",
  "/catalog/action_feature_overrides.json", "/catalog/combat_actions_5etools.json",
  "/catalog/combat_action_supplements_5etools.json",
  "/catalog/class_resource_overrides.json",
  "/catalog/miniatures.json"
];
// Fonts and sprite atlases are UI dependencies, not optional decoration:
// cached CSS without its icons results in an unusable offline interface.
const REQUIRED_ICONS = SHELL.filter(path =>
  path.startsWith("/icons/") || /^\/icon(?:-|\.)/.test(path));
const REQUIRED_PORTRAITS = SHELL.filter(path => path.startsWith("/miniature-images/"));
const REQUIRED_SHELL = [...new Set([...CORE_SHELL, ...REQUIRED_CATALOGS, ...REQUIRED_ICONS, ...REQUIRED_PORTRAITS])];
const OPTIONAL_SHELL = [...new Set([...SHELL, ...CATALOGS])]
  .filter(path => !REQUIRED_SHELL.includes(path));

function usableResponse(path, response) {
  if (!response?.ok) return false;
  // A reverse proxy can return HTTP 200 with HTML for a missing JS, JSON,
  // CSS or image. Never make that invalid body our offline copy.
  const type = response.headers.get("content-type") || "";
  if (/\.js$/.test(path)) return /javascript|ecmascript/i.test(type);
  if (/\.json$|\.webmanifest$/.test(path)) return /json/i.test(type);
  if (/\.css$/.test(path)) return /text\/css/i.test(type);
  if (/\.svg$/.test(path)) return /image\/svg\+xml/i.test(type);
  if (/\.png$/.test(path)) return /image\/png/i.test(type);
  if (/\.webp$/.test(path)) return /image\/webp/i.test(type);
  if (path === "/" || /\.html$/.test(path)) return /text\/html/i.test(type);
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
  if (event.data?.type === "VTT_SHELL_REVISION")
    event.ports?.[0]?.postMessage({ commit: REVISION });
  if (event.data?.type === "ACTIVATE_UPDATE") self.skipWaiting();
  // Large, optional compendia and decorative icons are downloaded after the
  // required shell activates. An unavailable server cannot break offline boot.
  if (event.data?.type === "CACHE_OPTIONAL")
    event.waitUntil(cacheAssets(OPTIONAL_SHELL));
});
self.addEventListener("fetch", event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== "GET" || url.origin !== self.location.origin ||
      url.pathname.startsWith("/api/")) return; // No caching of game state or credentials.
  if (!SHELL.includes(url.pathname) && !CATALOGS.includes(url.pathname) &&
      url.pathname !== "/catalog/bestiary.json" &&
      !url.pathname.startsWith("/catalog/bestiary/")) return;

  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    // Cache-first is essential for Android/Chromium: attempting the network on
    // every module, stylesheet and SVG adds multi-second delays and can reject
    // the module graph while the desktop or Tailscale proxy is unavailable.
    // Each app release gets a new atomic cache; the startup version gate
    // checks it against the live host before allowing a session connection.
    // Query strings (/?open=chat and icon ?v=...) resolve to the same asset.
    const cached = await cache.match(url.pathname);
    if (cached) return cached;
    try {
      const response = await fetch(request, { cache: "no-store" });
      if (!usableResponse(url.pathname, response)) return response;
      // Opportunistically store lazily opened bestiary segments too. If the
      // device is low on space, deliver the network response nonetheless.
      await cache.put(url.pathname, response.clone()).catch(error =>
        console.warn("VTT offline caching skipped:", url.pathname, error));
      return response;
    } catch (_) {
      return Response.error();
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
