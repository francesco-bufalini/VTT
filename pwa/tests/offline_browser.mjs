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
const browser = await chromium.launch({ headless: true });
try {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await context.newPage();
  page.setDefaultTimeout(15000);
  const errors = [];
  page.on("pageerror", error => errors.push(error.message));
  const archive = async () => {
    await page.locator('[data-act="create"]').waitFor({ timeout: 15000 });
    assert.match(await page.locator("#app").innerText(), /Le tue creature/);
  };
  const rename = async name => {
    await page.locator('[data-sheet-context="identity"]').first().click();
    const field = page.locator('[data-field="name"]').first();
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
    const currentCache = (await caches.keys()).find(name => /^vtt-mobile-shell-v\d+$/.test(name));
    if (!currentCache) return false;
    const cache = await caches.open(currentCache);
    const paths = ["/", "/index.html", "/main.js", "/ui.js", "/storage.js",
      "/creatures.js", "/styles.css", "/catalog/class_mechanics.json",
      "/catalog/ability_grants.json", "/catalog/spells.json", "/catalog/player.json"];
    return (await Promise.all(paths.map(path => cache.match(path)))).every(Boolean);
  }, null, { timeout: 60000 });
  await page.waitForFunction(() => !!navigator.serviceWorker.controller, null, { timeout: 15000 });
  await page.locator('[data-act="create"]').click();
  await rename("Creatura iniziale");
  console.log("PASS: complete offline shell installed and creature saved locally");

  // Tailscale/HTTPS proxy still responds, but Godot is no longer running.
  hostDown = true;
  await page.reload();
  await archive();
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
  assert.equal(await page.locator('[data-field="name"]').first().inputValue(),
    "Creatura modificata offline");
  await page.goto(origin + "/?open=chat");
  await archive();
  await page.locator('[data-nav="session"]').first().click();
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
