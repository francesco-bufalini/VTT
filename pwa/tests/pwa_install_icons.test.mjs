import assert from "node:assert/strict";
import { test } from "node:test";
import { readFile } from "node:fs/promises";

const root = new URL("../../", import.meta.url);
const read = path => readFile(new URL(path, root), "utf8");

test("Godot serves manifest icons with cache-busting query strings", async () => {
  const [host, index, manifestText] = await Promise.all([
    read("network/pwa_host.gd"), read("pwa/index.html"),
    read("pwa/manifest.webmanifest")
  ]);
  assert.match(host, /_handle_http\.call_deferred\(client, request\[0\], request\[1\]\.get_slice\("\?", 0\), headers,/);
  const routes = new Set([...host.matchAll(/"([^"\n]+)":\s*\["res:\/\/[^"\n]+",\s*"[^"\n]+"\]/g)].map(m => m[1]));
  assert.match(index, /rel="manifest" href="\/manifest.webmanifest"/);
  const manifest = JSON.parse(manifestText);
  assert.equal(manifest.display, "standalone");
  for (const size of [192, 512]) {
    const icon = manifest.icons.find(entry => entry.sizes === size + "x" + size);
    assert(icon, "missing install icon " + size);
    assert.equal(icon.type, "image/png");
    assert(routes.has(new URL(icon.src, "https://vtt.example").pathname),
      "Godot route missing for " + icon.src);
    const png = await readFile(new URL("pwa/icon-" + size + ".png", root));
    assert.equal(png.subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
    assert.equal(png.readUInt32BE(16), size);
    assert.equal(png.readUInt32BE(20), size);
  }
  assert.match(index, /rel="icon"[^>]+href="\/icon-192\.png\?v=/);
  assert.match(index, /rel="apple-touch-icon"[^>]+href="\/icon-192\.png\?v=/);
});
