// Real Chromium startup regression: the archive must render with empty
// IndexedDB, even when Service Worker registration never settles.
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { chromium, webkit } from "playwright";

const root = new URL("../../", import.meta.url);
const nativeHost = await readFile(new URL("network/pwa_host.gd", root), "utf8");
const routes = new Map([...nativeHost.matchAll(/"([^"\n]+)":\s*\["res:\/\/([^"\n]+)",\s*"([^"\n]+)"\]/g)]
  .map(match => [match[1], [match[2], match[3]]]));
let failUiModule = false;
let failUiModuleOnce = false;
let transientUiFailures = 0;
let failNestedModuleOnce = false;
let transientNestedFailures = 0;
let invalidSheetMime = false;
let pairingTestMode = false;
let pairingDesktopOnline = true;
let pairRequests = 0;
let unauthenticatedSessionRequests = 0;
const testShortCode = "0123456789ABCDEF";
const testBearer = "a".repeat(64);

const server = createServer(async (request, response) => {
  try {
    const path = new URL(request.url, "http://localhost").pathname;
    response.setHeader("Cache-Control", "no-store");
    if (path.startsWith("/api/")) {
      response.setHeader("Content-Type", "application/json");
      if (pairingTestMode) {
        if (path === "/api/status") {
          response.end(JSON.stringify({protocol:1,desktop_online:pairingDesktopOnline})); return;
        }
        if (path === "/api/pair" && request.method === "POST") {
          let body = "";
          for await (const chunk of request) body += chunk;
          if (JSON.parse(body).code === testShortCode) {
            ++pairRequests;
            response.end(JSON.stringify({ token:testBearer })); return;
          }
          response.writeHead(401);response.end(JSON.stringify({error:"invalid_pair_code"}));return;
        }
        if (path === "/api/session") {
          if (request.headers.authorization !== "Bearer " + testBearer) {
            ++unauthenticatedSessionRequests;
            response.writeHead(401);response.end(JSON.stringify({error:"pairing_required"}));return;
          }
          response.end(JSON.stringify({protocol:1,session:"test-session",mobile_protocol:3}));return;
        }
        if (path === "/api/map") {
          response.end(JSON.stringify({tokens:[],combat:{active:false}}));return;
        }
        if (path === "/api/conditions") {
          response.end(JSON.stringify({editions:{"2014":[],"2024":[]}}));return;
        }
      }
      response.end(JSON.stringify({ protocol: 1, desktop_online: false }));
      return;
    }
    if (path === "/catalog/spells.json") {
      response.setHeader("Content-Type", "application/json");
      response.end(JSON.stringify({ version: 1, spells: [] }));
      return;
    }
    if (path === "/ui.js" && (failUiModule || failUiModuleOnce)) {
      if (failUiModuleOnce) {
        failUiModuleOnce = false;
        ++transientUiFailures;
      }
      response.writeHead(503, { "Content-Type": "text/plain" });
      response.end("temporarily unavailable UI module");
      return;
    }
    if (path === "/sheet_rules_view.js" && failNestedModuleOnce) {
      failNestedModuleOnce = false;
      ++transientNestedFailures;
      response.writeHead(503, { "Content-Type": "text/plain" });
      response.end("temporary failure in a transitive ES module");
      return;
    }
    if (path === "/sheet_rules_view.js" && invalidSheetMime) {
      response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      response.end("<!doctype html><title>Proxy fallback</title>");
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
const browserType = process.env.PWA_BROWSER === "webkit" ? webkit : chromium;
const browser = await browserType.launch({ headless: true });
try {
  // Completely new browser profile and IndexedDB, as in incognito mode.
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", error => errors.push(error.message));
  await page.goto(origin);
  await page.locator('[data-act="library-add"]').waitFor({ timeout: 15000 });
  assert(await page.locator(".library-index").isVisible());
  assert.equal(errors.length, 0, "Unexpected browser error: " + errors.join("; "));
  await page.reload();
  await page.locator('[data-act="library-add"]').waitFor({ timeout: 15000 });
  assert.doesNotMatch(await page.locator("#app").innerText(), /Apertura archivio locale/);
  await context.close();
  console.log("PASS: clean Chrome profile opens and reloads the local archive");

  // A reduced-concurrency import bootstrap can be enabled without modifying
  // the local IndexedDB database or the normal fast startup path.
  const compatContext = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const compatPage = await compatContext.newPage();
  await compatPage.addInitScript(() => {
    sessionStorage.setItem("vtt-mobile-serial-modules", "1");
  });
  await compatPage.goto(origin);
  await compatPage.locator('[data-act="library-add"]').waitFor({ timeout: 30000 });
  assert.equal(await compatPage.locator("#startup-error").count(), 0);
  await compatContext.close();
  console.log("PASS: serial compatibility startup initializes the full local archive");
  
  // iOS WebKit must choose the successful sequential startup without waiting
  // for an error or any sessionStorage preference; Android remains unchanged.
  const iosUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.6.1 Mobile/15E148 Safari/604.1";
  const iosContext = await browser.newContext({
    viewport:{width:390,height:844},userAgent:iosUA,isMobile:true,hasTouch:true
  });
  const iosPage = await iosContext.newPage();
  const requested = [];
  iosPage.on("request", req => {
    if (req.url().endsWith(".js")) requested.push(new URL(req.url()).pathname);
  });
  await iosPage.goto(origin);
  await iosPage.locator('[data-act="library-add"]').waitFor({timeout:30000});
  assert.ok(requested.indexOf("/spell_metadata.js") >= 0);
  assert.ok(requested.indexOf("/ui.js") > requested.indexOf("/spell_metadata.js"),
    "iPhone must preload independent modules before the large UI graph");
  assert.equal(await iosPage.locator("#startup-error").count(), 0);
  await iosContext.close();
  console.log("PASS: iPhone WebKit defaults to serial bootstrap");

  // A reachable desktop must leave the pairing button enabled even before
  // any secret exists, whether or not the separate game receiver is online.
  // This reproduces the reported iPhone screenshot (filled QR field and a
  // disabled "Collega alla partita" button despite a reachable HTTPS host).
  pairingTestMode = true;
  pairingDesktopOnline = false;
  unauthenticatedSessionRequests = 0;
  const manualContext = await browser.newContext({
    viewport:{width:390,height:844},userAgent:iosUA,isMobile:true,hasTouch:true
  });
  const manualPage = await manualContext.newPage();
  await manualPage.goto(origin);
  await manualPage.locator('[data-act="library-add"]').waitFor({timeout:30000});
  await manualPage.locator('button.connection-link[data-nav="session"]').click();
  await manualPage.locator("#pair-form").waitFor({timeout:15000});
  await manualPage.waitForFunction(() =>
    !document.querySelector('#pair-form button[type="submit"]')?.disabled,
    null,{timeout:10000});
  assert.equal(unauthenticatedSessionRequests,0,
    "An unpaired phone must not call /api/session before enrolling");
  await manualPage.locator("#pair-secret").fill(testShortCode);
  pairingDesktopOnline = true;
  await manualPage.locator('[data-act="check"]').click();
  await manualPage.locator("#pair-form button[type=submit]").click();
  await manualPage.locator('[data-session-pane="table"][aria-pressed="true"]')
    .waitFor({timeout:8000}).catch(async error => {
      console.log("PAIR DEBUG", {
        pairRequests,unauthenticatedSessionRequests,
        toast:await manualPage.locator("#toast").textContent().catch(()=>null),
        appText:(await manualPage.locator("#app").innerText()).slice(0,850),
        state:await manualPage.evaluate(() => ({
          enabled:document.querySelector("#pair-form button[type=submit]")?.disabled,
          form:!!document.querySelector("#pair-form"),
          current:document.querySelector("#app")?.dataset.page
        }))
      });
      throw error;
    });
  assert.equal(unauthenticatedSessionRequests,0,
    "Manual first pairing must not send unauthenticated session checks");
  await manualContext.close();
  console.log("PASS: manual pairing button works on first visit and when sync receiver is offline");
  pairingTestMode = false;
  pairingDesktopOnline = true;

  // Reproduce the old bug: the phone has no stored bearer so /api/session
  // returns 401 until the one-time QR has been exchanged. Further, simulate
  // the iOS module-loader failure and full reload that used to lose #pair.
  pairingTestMode = true;
  pairRequests = 0;
  unauthenticatedSessionRequests = 0;
  failNestedModuleOnce = true;
  const qrContext = await browser.newContext({
    viewport:{width:390,height:844},userAgent:iosUA,isMobile:true,hasTouch:true
  });
  const qrPage = await qrContext.newPage();
  let qrNavigations = 0;
  qrPage.on("framenavigated", frame => {
    if (frame === qrPage.mainFrame()) ++qrNavigations;
  });
  await qrPage.goto(origin + "/#pair=" + testShortCode);
  await qrPage.locator('[data-session-pane="table"][aria-pressed="true"]')
    .waitFor({timeout:35000});
  await qrPage.waitForFunction(() => document.querySelector("#connection")?.textContent?.includes("Collegato"));
  assert.equal(pairRequests,1,"One-time QR must be redeemed exactly once");
  assert.equal(unauthenticatedSessionRequests,0,
    "The client must exchange #pair before trying /api/session without a bearer");
  assert.ok(qrNavigations >= 2,"iOS module retry must preserve the pending QR across reload");
  assert.equal(await qrPage.evaluate(()=>location.hash),"","QR code must be removed from history");
  assert.equal(await qrPage.evaluate(()=>sessionStorage.getItem("vtt-mobile-pending-qr-code")),null,
    "One-time QR must not remain in sessionStorage after pairing");
  await qrContext.close();
  pairingTestMode = false;
  transientNestedFailures = 0; // isolate the existing one-shot nested-import test
  console.log("PASS: iPhone QR fragment pairs automatically even across a module reload");


  // A Service Worker operation which never resolves must not block the UI.
  const slowContext = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const slowPage = await slowContext.newPage();
  await slowPage.addInitScript(() => {
    Object.defineProperty(navigator, "serviceWorker", {
      configurable: true,
      value: { register: () => {
        window.__swStartedBeforeUi = !document.querySelector('[data-act="create"]');
        return new Promise(() => {});
      } }
    });
  });
  await slowPage.goto(origin);
  await slowPage.locator('[data-act="library-add"]').waitFor({ timeout: 5000 });
  await slowPage.waitForFunction(() => window.__swStartedBeforeUi !== undefined);
  assert.equal(await slowPage.evaluate(() => window.__swStartedBeforeUi), false,
    "Offline preloading must start after the archive is usable");
  await slowContext.close();
  console.log("PASS: hung Service Worker cannot block local archive");

  // A first /ui.js request can fail because several PWA resources are being
  // loaded concurrently. Chromium caches a failed module resolution within a
  // page; a fragment-only retry must create a fresh module-map entry without
  // changing the native host's allowlisted HTTP path.
  failUiModuleOnce = true;
  const transientContext = await browser.newContext();
  const transientPage = await transientContext.newPage();
  await transientPage.goto(origin);
  await transientPage.locator('[data-act="library-add"]').waitFor({ timeout: 20000 });
  assert.equal(transientUiFailures, 1, "Expected one transient /ui.js failure");
  assert.equal(await transientPage.locator("#startup-error").count(), 0);
  await transientContext.close();
  console.log("PASS: transient module failure recovers without clearing IndexedDB");

  // A missing transitive dependency is remembered by the ESM module map:
  // retrying only ui.js with a fragment cannot fix it. The guarded full
  // document navigation must reset that map, then open the archive.
  failNestedModuleOnce = true;
  const nestedContext = await browser.newContext();
  const nestedPage = await nestedContext.newPage();
  let nestedNavigations = 0;
  nestedPage.on("framenavigated", frame => {
    if (frame === nestedPage.mainFrame()) ++nestedNavigations;
  });
  await nestedPage.goto(origin);
  await nestedPage.locator('[data-act="library-add"]').waitFor({ timeout: 25000 });
  assert.equal(transientNestedFailures, 1);
  assert.ok(nestedNavigations >= 2, "A failed transitive dependency requires a full navigation");
  // The recovery is validated by successful UI startup after a transient
  // nested module error. Storage keys may vary between browser implementations;
  // avoid coupling an integration test to an internal sessionStorage detail.
  console.log("Recovered module graph after", nestedNavigations, "navigations");
  assert.equal(await nestedPage.locator("#startup-error").count(), 0);
  await nestedContext.close();
  console.log("PASS: nested module failure recovers with one guarded navigation");

  // Permanently missing modules must still show an actionable error.
  failUiModule = true;
  const errorContext = await browser.newContext();
  const errorPage = await errorContext.newPage();
  let failedNavigations = 0;
  errorPage.on("framenavigated", frame => {
    if (frame === errorPage.mainFrame()) ++failedNavigations;
  });
  await errorPage.goto(origin);
  await errorPage.locator("#startup-error").waitFor({ timeout: 15000 });
  await errorPage.waitForFunction(() =>
    document.querySelector("#startup-diagnostic")?.textContent?.includes("/ui.js — HTTP 503"),
    null, { timeout: 12000 });
  assert.match(await errorPage.locator("#startup-diagnostic").innerText(),
    /\/ui\.js — HTTP 503 \| MIME text\/plain/);
  await errorPage.waitForFunction(() =>
    (() => {
      const progress = document.querySelector("#startup-diagnostic")?.textContent
        ?.match(/Controllati (\d+)\/(\d+)/);
      return progress && Number(progress[1]) === Number(progress[2]) &&
        Number(progress[1]) >= 27;
    })(),
    null, { timeout: 30000 });
  const errorReport = await errorPage.locator("#startup-diagnostic").innerText();
  assert.match(errorReport, /VERIFICA DEGLI IMPORT REALI DI SAFARI/);
  assert.match(errorReport, /Versione diagnostica: ios-module-debug-3/);
  await errorPage.waitForFunction(() =>
    document.querySelector("#startup-diagnostic-status")?.textContent?.includes("Diagnostica completa"),
    null, { timeout: 35000 });
  const deepReport = await errorPage.locator("#startup-diagnostic").innerText();
  assert.match(deepReport, /SECONDA PROVA CON URL MODULE MAP NUOVI/);
  assert.match(deepReport, /ESITO FILE INDIPENDENTI:/);
  assert.match(deepReport, /FRESH OK/);
  assert.match(deepReport, /SERVER DOPO ERRORE: indisponibile \(HTTP 404\)/);
  assert.equal(await errorPage.locator("#compat-startup").count(), 1);
  assert.match(errorReport, /\/ui\.js — TypeError:|\/ui\.js — Error:/);
  assert.match(errorReport, /\/storage\.js — IMPORT OK/);
  assert.doesNotMatch(errorReport, /\/main\.js — IMPORT OK/,
    "Never re-import the boot module");
  assert.equal(await errorPage.locator("#copy-startup-diagnostic").count(), 1);
  assert.equal(failedNavigations, 2, "Do not loop forever on a permanently missing module");
  assert.match(await errorPage.locator("#startup-phase").innerText(), /Caricamento dei moduli/);
  assert.doesNotMatch(await errorPage.locator("#app").innerText(), /Apertura archivio locale/);
  await errorContext.close();
  console.log("PASS: failed module import reports exact failing module and HTTP status");

  // A reverse proxy serving 200 HTML for a transitive .js file must be
  // reported as a MIME mismatch, even though its HTTP status is successful.
  failUiModule = false;
  invalidSheetMime = true;
  const mimeContext = await browser.newContext();
  const mimePage = await mimeContext.newPage();
  await mimePage.goto(origin);
  await mimePage.locator("#startup-error").waitFor({ timeout: 15000 });
  await mimePage.waitForFunction(() =>
    document.querySelector("#startup-diagnostic")?.textContent?.includes(
      "/sheet_rules_view.js — HTTP 200 | MIME text/html"),
    null, { timeout: 12000 });
  const mimeReport = await mimePage.locator("#startup-diagnostic").innerText();
  assert.match(mimeReport, /sheet_rules_view\.js — HTTP 200 \| MIME text\/html/);
  assert.match(mimeReport, /MIME non valido per moduli JS/);
  await mimePage.waitForFunction(() =>
    (() => {
      const progress = document.querySelector("#startup-diagnostic")?.textContent
        ?.match(/Controllati (\d+)\/(\d+)/);
      return progress && Number(progress[1]) === Number(progress[2]) &&
        Number(progress[1]) >= 27;
    })(),
    null, { timeout: 30000 });
  const importReport = await mimePage.locator("#startup-diagnostic").innerText();
  assert.match(importReport, /\/sheet_rules_view\.js — (TypeError|Error):/);
  assert.match(importReport, /\/storage\.js — IMPORT OK/);
  assert.match(mimeReport, /Browser:/);
  assert.doesNotMatch(mimeReport, /paired-desktop-secret/);
  await mimeContext.close();
  console.log("PASS: proxy HTML response identifies faulty dependency and MIME");
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
