import assert from "node:assert/strict";
import { MessageChannel } from "node:worker_threads";
import { test } from "node:test";
import { ensureCurrentAppVersion } from "../version_gate.js";

const oldFetch = globalThis.fetch;
const oldMessageChannel = Object.getOwnPropertyDescriptor(globalThis, "MessageChannel");
const oldNavigator = Object.getOwnPropertyDescriptor(globalThis, "navigator");

async function withVersionEnvironment({ served = "", cached = "", updateTo = "" }, callback) {
  const worker = revision => ({
    postMessage(message, ports) {
      assert.equal(message.type, "VTT_SHELL_REVISION");
      ports[0].postMessage({ commit: revision });
      ports[0].close();
    }
  });
  let updates = 0;
  const service = new EventTarget();
  service.controller = cached ? worker(cached) : null;
  service.getRegistration = async () => ({
    async update() {
      updates++;
      if (updateTo) {
        service.controller = worker(updateTo);
        service.dispatchEvent(new Event("controllerchange"));
      }
    }
  });
  Object.defineProperty(globalThis, "navigator", {
    configurable: true, value: { serviceWorker: service }
  });
  Object.defineProperty(globalThis, "MessageChannel", {
    configurable: true, value: MessageChannel
  });
  globalThis.fetch = async () => {
    if (!served) throw new TypeError("Offline");
    return new Response(JSON.stringify({ revision: served }), {
      status: 200, headers: { "content-type": "application/json" }
    });
  };
  try {
    await callback(() => updates);
  } finally {
    globalThis.fetch = oldFetch;
    if (oldNavigator) Object.defineProperty(globalThis, "navigator", oldNavigator);
    else delete globalThis.navigator;
    if (oldMessageChannel) Object.defineProperty(globalThis, "MessageChannel", oldMessageChannel);
    else delete globalThis.MessageChannel;
  }
}

test("no controlling worker means live modules are not served by a stale PWA cache", async () => {
  await withVersionEnvironment({ served: "b".repeat(64) }, async updates => {
    assert.equal(await ensureCurrentAppVersion({ strict: true }), "uncontrolled");
    assert.equal(updates(), 0);
  });
});

test("the offline local archive starts without deleting its existing cache", async () => {
  await withVersionEnvironment({ cached: "a".repeat(64) }, async updates => {
    assert.equal(await ensureCurrentAppVersion({ waitForUpdate: true }), "offline");
    assert.equal(updates(), 0);
  });
});

test("matching fingerprints allow normal startup", async () => {
  const revision = "b".repeat(64);
  await withVersionEnvironment({ cached: revision, served: revision }, async updates => {
    assert.equal(await ensureCurrentAppVersion({ waitForUpdate: true }), "current");
    assert.equal(updates(), 0);
  });
});

test("startup waits until the new atomic offline shell controls the page", async () => {
  const oldRevision = "a".repeat(64), newRevision = "b".repeat(64);
  await withVersionEnvironment({
    cached: oldRevision, served: newRevision, updateTo: newRevision
  }, async updates => {
    assert.equal(await ensureCurrentAppVersion({ waitForUpdate: true }), "updated");
    assert.equal(updates(), 1);
  });
});

test("joining a game refuses stale modules while scheduling a worker update", async () => {
  await withVersionEnvironment({
    cached: "a".repeat(64), served: "b".repeat(64)
  }, async updates => {
    await assert.rejects(
      ensureCurrentAppVersion({ strict: true }),
      /Nuova versione della PWA/
    );
    assert.equal(updates(), 1);
  });
});

test("joining a game fails closed if the online host version cannot be verified", async () => {
  await withVersionEnvironment({ cached: "a".repeat(64) }, async updates => {
    await assert.rejects(
      ensureCurrentAppVersion({ strict: true }),
      /Impossibile verificare/
    );
    assert.equal(updates(), 0);
  });
});
