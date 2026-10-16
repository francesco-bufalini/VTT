// Offline-first persistence for the future mobile UI. No backend stores private sheets.
const DB_NAME = "vtt-mobile-pwa";
const DB_VERSION = 1;
const STORES = ["meta", "creatures", "homebrew", "documents", "assets", "outbox"];
const valid = s => typeof s === "string" && s.length > 0 && s.length <= 256;
const complete = tx => new Promise((resolve, reject) => {
  tx.oncomplete = resolve;
  tx.onerror = () => reject(tx.error || new Error("Storage error"));
  tx.onabort = () => reject(tx.error || new Error("Storage aborted"));
});
const result = request => new Promise((resolve, reject) => {
  request.onsuccess = () => resolve(request.result);
  request.onerror = () => reject(request.error);
});
const randomId = () => Array.from(crypto.getRandomValues(new Uint8Array(16)),
  byte => byte.toString(16).padStart(2, "0")).join("");
const creatureKey = (scope, creature) => `${scope}|${creature.kind}|${creature.id}`;
function checkCreature(creature) {
  if (!creature || !["character", "monster"].includes(creature.kind) ||
      !valid(creature.id) || !valid(creature.name)) throw new TypeError("Invalid creature");
}
function checkDefinition(definition) {
  if (!definition || !/^homebrew:[a-z0-9_-]+:[a-z0-9_-]+:[a-z0-9_-]+$/.test(definition.id) ||
      !valid(definition.name) || !definition.data ||
      typeof definition.data !== "object" || Array.isArray(definition.data)) {
    throw new TypeError("Invalid homebrew definition");
  }
}
export async function openStorage() {
  if (!globalThis.indexedDB || !globalThis.crypto?.getRandomValues)
    throw new Error("IndexedDB requires a secure browser context");
  const database = await new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      for (const name of STORES)
        if (!request.result.objectStoreNames.contains(name))
          request.result.createObjectStore(name);
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
    request.onblocked = () => reject(new Error("Close other VTT tabs"));
  });
  database.onversionchange = () => database.close();
  try { await navigator.storage?.persist?.(); } catch { /* Not always granted on iOS. */ }
  return new LocalArchive(database);
}
export class LocalArchive {
  constructor(database) { this.db = database; }
  close() { this.db.close(); }
  async get(store, key) {
    if (!STORES.includes(store)) throw new TypeError("Invalid store");
    return result(this.db.transaction(store).objectStore(store).get(key));
  }
  async put(store, key, value) {
    if (!STORES.includes(store) || !valid(key)) throw new TypeError("Invalid key");
    const tx = this.db.transaction(store, "readwrite");
    const done = complete(tx);
    tx.objectStore(store).put(value, key);
    await done;
  }
  async list(store, prefix = "") {
    if (!STORES.includes(store)) throw new TypeError("Invalid store");
    const cursor = this.db.transaction(store).objectStore(store).openCursor();
    const entries = [];
    await new Promise((resolve, reject) => {
      cursor.onerror = () => reject(cursor.error);
      cursor.onsuccess = () => {
        const row = cursor.result;
        if (!row) return resolve();
        if (typeof row.key === "string" && row.key.startsWith(prefix))
          entries.push({ key: row.key, value: row.value });
        row.continue();
      };
    });
    return entries;
  }
  async ownerId() {
    let owner = await this.get("meta", "owner_id");
    if (typeof owner === "string" && owner.length === 32) return owner;
    owner = randomId();
    // Identity is not a security credential; the gateway uses a separate token.
    const tx = this.db.transaction("meta", "readwrite");
    const done = complete(tx);
    const store = tx.objectStore("meta");
    const existing = await result(store.get("owner_id"));
    if (existing) owner = existing;
    else store.put(owner, "owner_id");
    await done;
    return owner;
  }
  listCreatures(scope = "default") { return this.list("creatures", scope + "|"); }
  async saveCreature(creature, scope = "default") {
    checkCreature(creature);
    const owner = await this.ownerId();
    if (creature.owner_id && creature.owner_id !== owner) throw new Error("Not the local owner");
    const key = creatureKey(scope, creature);
    const tx = this.db.transaction("creatures", "readwrite");
    const done = complete(tx);
    const store = tx.objectStore("creatures");
    const previous = await result(store.get(key));
    if (previous && (
      (previous.owner_id && previous.owner_id !== owner) ||
      Number(previous.transfer_revision || 0) !== Number(creature.transfer_revision || 0)
    )) {
      tx.abort(); await done.catch(() => {});
      throw new Error("Stale transfer revision");
    }
    store.put({ ...structuredClone(creature), owner_id: owner }, key);
    await done;
  }
  async deleteCreature(kind, id, scope = "default") {
    const key = `${scope}|${kind}|${id}`;
    const owner = await this.ownerId();
    const tx = this.db.transaction("creatures", "readwrite");
    const done = complete(tx);
    const store = tx.objectStore("creatures");
    const saved = await result(store.get(key));
    if (saved?.owner_id && saved.owner_id !== owner) {
      tx.abort(); await done.catch(() => {});
      throw new Error("Not the local owner");
    }
    store.delete(key);
    await done;
  }
  // Mirrors creature_archive.gd import_export_copy; companion definitions installed atomically.
  async importCreature(payload, scope = "default") {
    if (payload?.format !== "vtt_creature_export_v1" || payload.version !== 1)
      throw new TypeError("Expected vtt_creature_export_v1");
    checkCreature(payload.creature);
    const definitions = payload.homebrew_content ?? [];
    if (!Array.isArray(definitions) || definitions.length > 250 ||
        new Blob([JSON.stringify(definitions)]).size > 12 * 1024 * 1024)
      throw new RangeError("Invalid homebrew bundle");
    definitions.forEach(checkDefinition);
    const owner = await this.ownerId();
    const creature = { ...structuredClone(payload.creature), id: "import_" + randomId(),
      owner_id: owner, transfer_revision: 0, linked_token_sync_id: "" };
    const tx = this.db.transaction(["homebrew", "creatures"], "readwrite");
    const done = complete(tx);
    const homebrew = tx.objectStore("homebrew");
    for (const entry of definitions) {
      if (await result(homebrew.get(entry.id)) === undefined) homebrew.add(entry, entry.id);
    }
    tx.objectStore("creatures").add(creature, creatureKey(scope, creature));
    await done;
    return creature;
  }
  async exportCreature(kind, id, scope = "default") {
    const creature = await this.get("creatures", `${scope}|${kind}|${id}`);
    if (!creature) throw new Error("Creature missing");
    const lookup = new Map((await this.list("homebrew")).map(row => [row.key, row.value]));
    const needed = new Set(), included = new Set();
    function visit(value) {
      if (typeof value === "string" && /^homebrew:[^:]+:[^:]+:[^:]+$/.test(value)) needed.add(value);
      else if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === "object") Object.values(value).forEach(visit);
    }
    visit(creature);
    for (let pass = 0; pass < 251; pass++) {
      let changed = false;
      for (const name of needed) {
        if (included.has(name)) continue;
        if (!lookup.has(name)) throw new Error("Missing homebrew: " + name);
        included.add(name); changed = true; visit(lookup.get(name).data);
      }
      if (!changed) break;
    }
    if (included.size > 250) throw new RangeError("Too many homebrew definitions");
    return { format: "vtt_creature_export_v1", version: 1, creature: structuredClone(creature),
      homebrew_content: [...included].sort().map(name => lookup.get(name)) };
  }
  async saveFile(id, blob, kind = "assets") {
    if (!["assets", "documents"].includes(kind) || !(blob instanceof Blob))
      throw new TypeError("Expected binary file Blob");
    await this.put(kind, id, blob);
  }
  // JSON backup includes binary assets as base64. Save outside Safari's private storage.
  async exportBackup() {
    const stores = {};
    for (const name of STORES) {
      stores[name] = [];
      for (const row of await this.list(name)) {
        if (row.value instanceof Blob) {
          const bytes = new Uint8Array(await row.value.arrayBuffer());
          let base64 = "";
          for (let i = 0; i < bytes.length; i += 16384)
            base64 += String.fromCharCode(...bytes.subarray(i, i + 16384));
          stores[name].push({ key: row.key, base64: btoa(base64), mime: row.value.type });
        } else stores[name].push(row);
      }
    }
    return new Blob([JSON.stringify({ format: "vtt_pwa_backup_v1", version: 1, stores })],
      { type: "application/json" });
  }
  async importBackup(backup, { overwrite = false } = {}) {
    if (backup?.format !== "vtt_pwa_backup_v1" || backup.version !== 1 ||
        !backup.stores || typeof backup.stores !== "object") throw new TypeError("Invalid backup");
    // Validate/decode everything before opening the write transaction:
    // failed base64 or malformed entries must never leave a partial recovery.
    const prepared = {};
    for (const name of STORES) {
      prepared[name] = [];
      const rows = backup.stores[name] || [];
      if (!Array.isArray(rows) || rows.length > 50000)
        throw new TypeError("Invalid backup entries");
      for (const row of rows) {
        if (!valid(row?.key) || (!Object.hasOwn(row, "value") && typeof row.base64 !== "string"))
          throw new TypeError("Invalid backup row");
        let value = row.value;
        if (typeof row.base64 === "string") {
          const binary = atob(row.base64);
          value = new Blob([Uint8Array.from(binary, c => c.charCodeAt(0))],
            { type: row.mime || "application/octet-stream" });
        }
        if (name === "creatures") checkCreature(value);
        if (name === "homebrew") checkDefinition(value);
        prepared[name].push({ key: row.key, value });
      }
    }
    const tx = this.db.transaction(STORES, "readwrite");
    const done = complete(tx);
    for (const name of STORES) {
      const store = tx.objectStore(name);
      for (const row of prepared[name]) {
        if (!overwrite && await result(store.get(row.key)) !== undefined) continue;
        store.put(row.value, row.key);
      }
    }
    await done;
  }
}
