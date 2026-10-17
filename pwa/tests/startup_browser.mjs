// Real Chromium startup regression: the archive must render with empty
// IndexedDB, even when Service Worker registration never settles.
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { chromium } from "playwright";

const root = new URL("../../", import.meta.url);
const nativeHost = await readFile(new URL("network/pwa_host.gd", root), "utf8");
const routes = new Map([...nativeHost.matchAll(/"([^"\n]+)":\s*\["res:\/\/([^"\n]+)",\s*"([^"\n]+)"\]/g)]
  .map(match => [match[1], [match[2], match[3]]]));
let failUiModule = false;

const server = createServer(async (request, response) => {
  try {
    const path = new URL(request.url, "http://localhost").pathname;
    response.setHeader("Cache-Control", "no-store");
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
    if (failUiModule && path === "/ui.js") {
      response.writeHead(404);
      response.end("missing UI module");
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
  // Completely new browser profile and IndexedDB, as in incognito mode.
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", error => errors.push(error.message));
  await page.goto(origin);
  await page.locator('[data-act="create"]').waitFor({ timeout: 15000 });
  assert.match(await page.locator("#app").innerText(), /Le tue creature/);
  assert.equal(errors.length, 0, "Unexpected browser error: " + errors.join("; "));
  await page.reload();
  await page.locator('[data-act="create"]').waitFor({ timeout: 15000 });
  assert.doesNotMatch(await page.locator("#app").innerText(), /Apertura archivio locale/);
  await context.close();
  console.log("PASS: clean Chrome profile opens and reloads the local archive");

  // A Service Worker operation which never resolves must not block the UI.
  const slowContext = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const slowPage = await slowContext.newPage();
  await slowPage.addInitScript(() => {
    Object.defineProperty(navigator, "serviceWorker", {
      configurable: true,
      value: { register: () => new Promise(() => {}) }
    });
  });
  await slowPage.goto(origin);
  await slowPage.locator('[data-act="create"]').waitFor({ timeout: 5000 });
  await slowContext.close();
  console.log("PASS: hung Service Worker cannot block local archive");

  // Broken imports must show an actionable startup error, not an eternal placeholder.
  failUiModule = true;
  const errorContext = await browser.newContext();
  const errorPage = await errorContext.newPage();
  await errorPage.goto(origin);
  await errorPage.locator("#startup-error").waitFor({ timeout: 10000 });
  assert.match(await errorPage.locator("#startup-phase").innerText(), /Caricamento dei moduli/);
  assert.doesNotMatch(await errorPage.locator("#app").innerText(), /Apertura archivio locale/);
  await errorContext.close();
  console.log("PASS: failed module import reports startup error");
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
