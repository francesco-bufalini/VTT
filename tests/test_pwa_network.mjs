// Dependency-free Node test for the PWA transport state machine.
import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
if (!globalThis.CustomEvent) {
  globalThis.CustomEvent = class extends Event {
    constructor(type, { detail }) { super(type); this.detail = detail; }
  };
}
const source = readFileSync(resolve("pwa/network.js"), "utf8");
const { GameTransport, validPublicMap } = await import(
  "data:text/javascript;base64," + Buffer.from(source).toString("base64")
);
const map = { version: 1, tokens: [], combat:
  { active: false, round: 1, active_index: -1, entries: [] } };
assert(validPublicMap(map));
assert(!validPublicMap({ ...map, tokens: [{ id: "x", name: "X", conditions: [] },
  { id: "x", name: "Y", conditions: [] }] }));
let calls = 0;
globalThis.fetch = async (url, args) => {
  calls++;
  assert(url.endsWith("/api/v1/map"));
  assert.equal(JSON.parse(args.body).session, "1");
  assert.equal(args.headers.Authorization, "Bearer " + "x".repeat(32));
  if (calls === 1) throw new Error("Desktop offline");
  return { ok: true, json: async () => ({ data: map }) };
};
const connection = new GameTransport({ pairingToken: "x".repeat(32) });
let status = "";
connection.addEventListener("status", event => { status = event.detail; });
await connection.connect("1");
assert(connection.timer !== null, "polling must continue after initial failure");
await connection.refresh();
assert.equal(status, "connected");
assert.deepEqual(connection.map, map);
assert.equal(calls, 2);
// Two callers cannot launch two simultaneous map probes.
let release;
globalThis.fetch = () => {
  calls++;
  return new Promise(resolve => { release = resolve; });
};
const first = connection.refresh(), second = connection.refresh();
assert.equal(calls, 3);
release({ ok: true, json: async () => ({ data: map }) });
await Promise.all([first, second]);
assert.equal(calls, 3);
connection.disconnect();
assert.equal(connection.timer, null);
assert.equal(connection.map, null);
console.log("PWA transport tests passed");
