// Real Chromium regression: a previously installed VTT must keep the creature
// editor functional when the native Godot host is down, even behind a 502 proxy.
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { chromium } from "playwright";

const root = new URL("../../", import.meta.url);
const nativeHost = await readFile(new URL("network/pwa_host.gd", root), "utf8");
const routes = new Map([...nativeHost.matchAll(/"([^"\n]+)":\s*\["res:\/\/([^"\n]+)",\s*"([^"\n]+)"\]/g)]
  .map(match => [match[1], [match[2], match[3]]]));
let hostDown = false;
const server = createServer(async (request, response) => {
  try {
    const path = new URL(request.url, "http://localhost").pathname;
    response.setHeader("Cache-Control", "no-store");
    if (hostDown) {
      response.writeHead(502, { "Content-Type": "text/plain" });
      response.end("Godot desktop is offline");
      return;
    }
    if (path.startsWith("/api/")) {
      response.setHeader("Content-Type", "application/json");
      response.end(JSON.stringify({ protocol: 1, desktop_online: false }));
      return;
    }
    if (path === "/catalog/spells.json") {
      response.setHeader("Content-Type", "application/json");
      response.end(JSON.stringify({ version: 1, spells: [] }));
      return;
    }
    const route = routes.get(path);
    if (!route) {
      response.writeHead(404);
      response.end();
      return;
    }
    response.setHeader("Content-Type", route[1]);
    response.end(await readFile(new URL(route[0], root)));
  } catch (error) {
    response.writeHead(404);
    response.end(String(error));
  }
});
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
const origin = "http://127.0.0.1:" + server.address().port;
const browser = await chromium.launch({ headless: true,
  ...(process.platform==='win32'?{executablePath:process.env.CHROME_PATH||'C:/Program Files/Google/Chrome/Application/chrome.exe'}:{}) });
try {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await context.newPage();
  page.setDefaultTimeout(15000);
  const errors = [];
  page.on("pageerror", error => errors.push(error.message));
  const archive = async () => {
    await page.locator('[data-act="library-add"]').waitFor({ timeout: 15000 });
    assert(await page.locator(".library-index").isVisible());
  };
  const rename = async name => {
    await page.locator('[data-sheet-context="identity"]').first().click();
    const field = page.locator('#sheet-context-dialog [data-identity-value="names"]').first();
    await field.fill(name);
    await field.press("Tab");
    await page.waitForFunction(async expected => {
      const { listCreatures } = await import("/creatures.js");
      return (await listCreatures()).some(row => row.creature.name === expected);
    }, name);
  };

  // Online first use, after which all REQUIRED_SHELL files must be cached.
  await page.goto(origin);
  await archive();
  await page.waitForFunction(async () => {
    const ready = await navigator.serviceWorker.ready;
    if (!ready.active) return false;
    const currentCache = (await caches.keys()).find(name => /^vtt-mobile-shell-v\d+(?:-.+)?$/.test(name));
    if (!currentCache) return false;
    const cache = await caches.open(currentCache);
    const paths = ["/", "/index.html", "/main.js", "/ui.js", "/storage.js",
      "/creatures.js", "/styles.css", "/catalog/class_mechanics.json",
      "/catalog/ability_grants.json", "/catalog/spells.json", "/catalog/player.json",
      "/power_selection.js", "/catalog/power_selections.json",
      "/catalog/sense_grants.json", "/catalog/species_roll_modes.json",
      "/catalog/miniatures.json", "/catalog/species_attacks.json", "/catalog/combat_action_supplements_5etools.json",
      "/icons/action_controls.svg", "/icons/gold_generated/gold_2.svg",
      "/icons/info/identity.svg", "/icon-192.png"];
    return (await Promise.all(paths.map(path => cache.match(path)))).every(Boolean);
  }, null, { timeout: 60000 });
  await page.waitForFunction(() => !!navigator.serviceWorker.controller, null, { timeout: 15000 });
  await page.locator('[data-act="library-add"]').click();
  await page.locator('[data-act="create"]').click();
  await rename("Creatura iniziale");
  console.log("PASS: complete offline shell installed and creature saved locally");

  // Tailscale/HTTPS proxy still responds, but Godot is no longer running.
  hostDown = true;
  await page.reload();
  await archive();
  // Static app resources must come straight from CacheStorage (not from the
  // 502 proxy), including sprite atlases and assets referenced by CSS.
  const offlineAssets = await page.evaluate(async () => {
    const paths = ["/main.js", "/ui.js", "/power_selection.js", "/catalog/power_selections.json", "/styles.css", "/mobile_metal_theme.css",
      "/icons/gold_generated/gold_2.svg", "/icons/action_controls.svg",
      "/icons/info/identity.svg", "/icon-192.png", "/catalog/miniatures.json"];
    return Promise.all(paths.map(async path => {
      const response = await fetch(path + (path.endsWith(".png") ? "?v=installed" : ""),
        { cache: "no-store" });
      return { path, ok: response.ok, type: response.headers.get("content-type") };
    }));
  });
  assert(offlineAssets.every(row => row.ok),
    "Offline static assets missing: " + JSON.stringify(offlineAssets.filter(row => !row.ok)));
  assert(offlineAssets.find(row => row.path === "/icons/gold_generated/gold_2.svg")
    .type.includes("image/svg+xml"));
  await page.locator('[data-act="open"]').first().click();
  await rename("Creatura modificata offline");
  await page.reload();
  await archive();
  assert.match(await page.locator("#app").innerText(), /Creatura modificata offline/);
  console.log("PASS: cached PWA opens through a 502 proxy and edits persist");

  // A true network outage must likewise permit reopening the existing sheet.
  hostDown = false;
  await context.setOffline(true);
  await page.reload();
  await archive();
  await page.locator('[data-act="open"]').first().click();
  await page.locator('[data-sheet-context="identity"]').first().click();
  assert.equal(await page.locator('#sheet-context-dialog [data-identity-value="names"]').first().inputValue(),
    "Creatura modificata offline");
  await page.goto(origin + "/?open=chat");
  // Chat links now open the full-height chat on a saved creature, even offline.
  await page.locator("#chat-screen #events").waitFor({state:"visible",timeout:15000});
  assert.equal(await page.locator("#header-chat-notifications").isVisible(),true);
  assert.equal(await page.locator("#mobile-tabs").isVisible(),false);
  await page.locator('#creature-back').click();
  await page.locator('#dock-session').click();
  await page.locator("#app").waitFor();
  assert.equal(await page.locator('#pair-form button[type="submit"]').isDisabled(), true,
    "Offline pairing must be unavailable");
  console.log("PASS: airplane mode reload, deep link and offline session controls");

  await context.setOffline(false);
  await page.goto(origin);
  await archive();
  assert.match(await page.locator("#app").innerText(), /Creatura modificata offline/);
  assert.deepEqual(errors, []);
  console.log("PASS: offline edits survive desktop reconnection");
  await context.close();
} finally {
  await browser.close();
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
