import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

// Execute the actual worker with a minimal CacheStorage and network, rather
// than inspecting strings for "cache-first" and missing the real behavior.
async function workerFixture(revision = "a".repeat(40)) {
  const listeners = new Map();
  const buckets = new Map();
  const requests = [];
  let offline = false;
  const origin = "https://vtt.example";
  const caches = {
    async open(name) {
      if (!buckets.has(name)) buckets.set(name, new Map());
      const entries = buckets.get(name);
      return {
        async match(key) { return entries.get(key)?.clone(); },
        async put(key, value) { entries.set(key, value.clone()); }
      };
    },
    async keys() { return [...buckets.keys()]; },
    async delete(name) { return buckets.delete(name); }
  };
  const fetch = async input => {
    const path = new URL(typeof input === "string" ? input : input.url, origin).pathname;
    requests.push(path);
    if (offline) throw new TypeError("Failed to fetch");
    const type = path.endsWith(".js") ? "text/javascript" :
      path.endsWith(".css") ? "text/css" :
      path.endsWith(".webmanifest") || path.endsWith(".json") ? "application/json" :
      path.endsWith(".svg") ? "image/svg+xml" :
      path.endsWith(".png") ? "image/png" :
      path.endsWith(".webp") ? "image/webp" : "text/html";
    return new Response(path, { headers: { "Content-Type": type } });
  };
  const self = {
    location: { origin },
    addEventListener(type, fn) { listeners.set(type, fn); },
    skipWaiting() {},
    clients: { claim: async () => {} }
  };
  const source = await readFile(new URL("../sw.js", import.meta.url), "utf8");
  runInNewContext(source.replaceAll("__VTT_COMMIT_SHA__", revision),
    { self, caches, fetch, Response, URL, console });
  const dispatch = async (kind, request) => {
    const tasks = [];
    let response;
    listeners.get(kind)({
      request,
      data: undefined,
      waitUntil(promise) { tasks.push(promise); },
      respondWith(promise) { response = promise; }
    });
    await Promise.all(tasks);
    return response && await response;
  };
  return {
    dispatch, requests, caches, setOffline(value) { offline = value; }
  };
}

test("Android offline installation includes required code, icon sprites and miniatures", async () => {
  const worker = await workerFixture();
  await worker.dispatch("install");
  worker.setOffline(true);
  worker.requests.length = 0;
  const expected = [
    "/", "/index.html", "/main.js", "/ui.js", "/styles.css",
    "/dragonborn_ftd.js", "/ability_areas.js",
    "/class_defenses.js", "/armor_rules.js",
    "/feature_item_grants.js", "/catalog/feature_item_grants.json",
    "/power_selection.js", "/catalog/power_selections.json",
    "/optional_feature_progression.js", "/catalog/optional_feature_progressions.json",
    "/slot_feature_powers.js", "/catalog/slot_feature_powers.json",
    "/zero_hp_responses.js",
    "/mobile_metal_theme.css", "/catalog/class_mechanics.json",
    "/catalog/sense_grants.json", "/catalog/species_roll_modes.json",
    "/catalog/miniatures.json", "/icons/action_controls.svg",
    "/icons/gold_generated/gold_2.svg", "/icons/info/identity.svg",
    "/icon-192.png", "/icon-512.png", "/miniature-images/ore.webp", "/miniature-images/harmakis.webp"
  ];
  for (const path of expected) {
    const request = new Request("https://vtt.example" + path +
      (path.endsWith(".png") ? "?v=20261023c" : ""));
    const response = await worker.dispatch("fetch", request);
    assert.equal(response.status, 200, "Unavailable offline: " + path);
  }
  assert.deepEqual(worker.requests, [], "Cached assets must not attempt a dead server");
});

test("uncached assets fail safely and game APIs are never cached", async () => {
  const worker = await workerFixture();
  await worker.dispatch("install");
  worker.setOffline(true);
  const missing = await worker.dispatch("fetch",
    new Request("https://vtt.example/catalog/bestiary/missing.json"));
  assert.equal(missing.type, "error");
  assert.equal(await worker.dispatch("fetch",
    new Request("https://vtt.example/api/status")), undefined);
  const storage = await worker.caches.open("vtt-mobile-shell-v132");
  assert.equal(await storage.match("/api/status"), undefined);
  assert.equal(await storage.match("/catalog/bestiary/missing.json"), undefined);
});


test("offline cache name follows the served asset fingerprint without deleting saved data", async () => {
  const revision = "b".repeat(64);
  const worker = await workerFixture(revision);
  await worker.dispatch("install");
  const sw = await readFile(new URL("../sw.js", import.meta.url), "utf8");
  const cachePrefix = sw.match(/vtt-mobile-shell-v\d+-/)?.[0];
  assert(cachePrefix, "The worker must declare a versioned shell cache");
  assert((await worker.caches.keys()).includes(cachePrefix + revision));
  worker.setOffline(true);
  const cached = await worker.dispatch("fetch", new Request("https://vtt.example/ui.js"));
  assert.equal(cached.status, 200);
});
