// VTT PWA: per-origin, local-first storage. Never put user content in CacheStorage.
// Records and attachment references are transactional; blobs are deduplicated by SHA-256.
export const DATABASE_NAME = "vtt-mobile-local";
export const DATABASE_VERSION = 1;
const BACKUP_VERSION = 1;
const MAX_IMPORT_BYTES = 128 * 1024 * 1024;

export function openStorage() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DATABASE_NAME, DATABASE_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains("records")) {
        db.createObjectStore("records", { keyPath: ["scope", "type", "id"] });
      }
      if (!db.objectStoreNames.contains("blobs")) {
        db.createObjectStore("blobs", { keyPath: "digest" });
      }
      if (!db.objectStoreNames.contains("settings")) {
        db.createObjectStore("settings", { keyPath: "key" });
      }
      if (!db.objectStoreNames.contains("outbox")) {
        db.createObjectStore("outbox", { keyPath: "id" });
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
    request.onblocked = () => reject(new Error("Close the other VTT tab to migrate local storage"));
  });
}

function completed(tx, getResult = () => undefined) {
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve(getResult());
    tx.onerror = () => reject(tx.error || new Error("IndexedDB transaction failed"));
    tx.onabort = () => reject(tx.error || new Error("IndexedDB transaction aborted"));
  });
}

function requiredString(value, label) {
  if (typeof value !== "string" || !value || value.length > 256) {
    throw new TypeError("Invalid " + label);
  }
  return value;
}

export async function getRecord(scope, type, id) {
  const db = await openStorage();
  try {
    const tx = db.transaction("records", "readonly");
    const request = tx.objectStore("records").get([
      requiredString(scope, "scope"), requiredString(type, "type"), requiredString(id, "id")
    ]);
    return await completed(tx, () => request.result || null);
  } finally {
    db.close();
  }
}

export async function listRecords(scope, type = null) {
  requiredString(scope, "scope");
  const db = await openStorage();
  try {
    const tx = db.transaction("records", "readonly");
    const request = tx.objectStore("records").getAll();
    return await completed(tx, () => request.result.filter(row =>
      row.scope === scope && (type === null || row.type === type)));
  } finally {
    db.close();
  }
}

// expectedRevision prevents a second tab from silently overwriting an edited sheet.
export async function putRecord(scope, type, id, data, expectedRevision = null) {
  const key = [requiredString(scope, "scope"), requiredString(type, "type"), requiredString(id, "id")];
  const db = await openStorage();
  try {
    const tx = db.transaction("records", "readwrite");
    let result;
    const request = tx.objectStore("records").get(key);
    request.onsuccess = () => {
      const old = request.result;
      if (expectedRevision !== null && (old?.revision ?? 0) !== expectedRevision) {
        tx.abort();
        return;
      }
      result = { scope: key[0], type: key[1], id: key[2],
        data, revision: (old?.revision ?? 0) + 1, updatedAt: Date.now() };
      tx.objectStore("records").put(result);
    };
    return await completed(tx, () => result);
  } finally {
    db.close();
  }
}

export async function deleteRecord(scope, type, id) {
  const db = await openStorage();
  try {
    const tx = db.transaction("records", "readwrite");
    tx.objectStore("records").delete([
      requiredString(scope, "scope"), requiredString(type, "type"), requiredString(id, "id")
    ]);
    await completed(tx);
  } finally {
    db.close();
  }
}

async function sha256(blob) {
  const bytes = await blob.arrayBuffer();
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), value => value.toString(16).padStart(2, "0")).join("");
}

// Stores a Blob with its record in ONE IndexedDB transaction: no dangling new refs.
export async function putAttachment(scope, type, id, data, blob) {
  if (!(blob instanceof Blob)) throw new TypeError("Attachment must be a Blob");
  const digest = await sha256(blob);
  const db = await openStorage();
  try {
    const tx = db.transaction(["records", "blobs"], "readwrite");
    tx.objectStore("blobs").put({ digest, blob, mime: blob.type, bytes: blob.size });
    const key = [requiredString(scope, "scope"), requiredString(type, "type"), requiredString(id, "id")];
    const request = tx.objectStore("records").get(key);
    let result;
    request.onsuccess = () => {
      const old = request.result;
      result = { scope: key[0], type: key[1], id: key[2], data,
        digest, revision: (old?.revision ?? 0) + 1, updatedAt: Date.now() };
      tx.objectStore("records").put(result);
    };
    return await completed(tx, () => result);
  } finally {
    db.close();
  }
}

export async function getAttachment(digest) {
  const db = await openStorage();
  try {
    const tx = db.transaction("blobs", "readonly");
    const request = tx.objectStore("blobs").get(requiredString(digest, "digest"));
    return await completed(tx, () => request.result?.blob || null);
  } finally {
    db.close();
  }
}

export async function setting(key, value) {
  requiredString(key, "setting");
  const db = await openStorage();
  try {
    const tx = db.transaction("settings", value === undefined ? "readonly" : "readwrite");
    const store = tx.objectStore("settings");
    const request = value === undefined ? store.get(key) : store.put({ key, value });
    return await completed(tx, () => value === undefined ? request.result?.value : value);
  } finally {
    db.close();
  }
}

export async function queueAction(scope, action, payload) {
  requiredString(scope, "scope");
  requiredString(action, "action");
  const envelope = { id: crypto.randomUUID(), scope, action, payload, queuedAt: Date.now() };
  const db = await openStorage();
  try {
    const tx = db.transaction("outbox", "readwrite");
    tx.objectStore("outbox").add(envelope);
    return await completed(tx, () => envelope);
  } finally {
    db.close();
  }
}

export async function pendingActions(scope) {
  requiredString(scope, "scope");
  const db = await openStorage();
  try {
    const tx = db.transaction("outbox", "readonly");
    const request = tx.objectStore("outbox").getAll();
    return await completed(tx, () => request.result.filter(item => item.scope === scope));
  } finally {
    db.close();
  }
}

export async function acknowledgeAction(id) {
  const db = await openStorage();
  try {
    const tx = db.transaction("outbox", "readwrite");
    tx.objectStore("outbox").delete(requiredString(id, "id"));
    await completed(tx);
  } finally {
    db.close();
  }
}

export async function storageEstimate() {
  const persisted = await navigator.storage?.persisted?.().catch(() => false) ?? false;
  const estimate = await navigator.storage?.estimate?.().catch(() => ({})) ?? {};
  return { persisted, usage: estimate.usage ?? null, quota: estimate.quota ?? null };
}

export async function requestPersistentStorage() {
  return await navigator.storage?.persist?.().catch(() => false) ?? false;
}

function toBase64(buffer) {
  const bytes = new Uint8Array(buffer);
  let out = "";
  for (let i = 0; i < bytes.length; i += 32768) {
    out += String.fromCharCode(...bytes.subarray(i, i + 32768));
  }
  return btoa(out);
}

function fromBase64(text) {
  const binary = atob(text);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

// Export user records and binary attachments. Pairing credentials are deliberately excluded.
export async function exportBackup() {
  const db = await openStorage();
  let records, blobs, outbox;
  try {
    const tx = db.transaction(["records", "blobs", "outbox"], "readonly");
    const recordReq = tx.objectStore("records").getAll();
    const blobReq = tx.objectStore("blobs").getAll();
    const outboxReq = tx.objectStore("outbox").getAll();
    await completed(tx);
    records = recordReq.result;
    blobs = blobReq.result;
    outbox = outboxReq.result;
  } finally {
    db.close();
  }
  const encoded = [];
  for (const entry of blobs) {
    encoded.push({ digest: entry.digest, mime: entry.mime,
      base64: toBase64(await entry.blob.arrayBuffer()) });
  }
  return new Blob([JSON.stringify({
    format: "vtt-pwa-backup", version: BACKUP_VERSION,
    createdAt: new Date().toISOString(), records, blobs: encoded, outbox
  })], { type: "application/json" });
}

// Validate the whole backup (including attachment checksums) BEFORE writing anything.
// Default merge adds missing IDs and preserves existing edits.
// Explicit overwrite is only for deliberate restoration.
export async function importBackup(file, { overwrite = false } = {}) {
  if (!(file instanceof Blob) || file.size > MAX_IMPORT_BYTES) {
    throw new Error("Invalid or oversized VTT backup");
  }
  const content = JSON.parse(await file.text());
  if (content?.format !== "vtt-pwa-backup" || content.version !== BACKUP_VERSION ||
      !Array.isArray(content.records) || !Array.isArray(content.blobs) ||
      !Array.isArray(content.outbox)) {
    throw new Error("Unsupported VTT backup");
  }
  const attachments = [];
  for (const item of content.blobs) {
    if (typeof item.digest !== "string" || typeof item.base64 !== "string") throw new Error("Invalid attachment");
    const blob = new Blob([fromBase64(item.base64)], { type: item.mime || "" });
    if (await sha256(blob) !== item.digest) throw new Error("Attachment checksum mismatch");
    attachments.push({ digest: item.digest, blob, mime: blob.type, bytes: blob.size });
  }
  const archivedDigests = new Set(attachments.map(entry => entry.digest));
  for (const item of content.records) {
    requiredString(item.scope, "scope");
    requiredString(item.type, "type");
    requiredString(item.id, "id");
    if (item.digest && !archivedDigests.has(item.digest)) {
      throw new Error("Backup contains a missing attachment reference");
    }
  }
  for (const item of content.outbox) {
    requiredString(item.id, "id");
    requiredString(item.scope, "scope");
    requiredString(item.action, "action");
  }
  const db = await openStorage();
  try {
    const tx = db.transaction(["records", "blobs", "outbox"], "readwrite");
    for (const entry of attachments) tx.objectStore("blobs").put(entry);
    const records = tx.objectStore("records");
    const outbox = tx.objectStore("outbox");
    for (const record of content.records) {
      if (overwrite) {
        records.put(record);
      } else {
        const check = records.get([record.scope, record.type, record.id]);
        check.onsuccess = () => { if (!check.result) records.put(record); };
      }
    }
    for (const event of content.outbox) {
      if (overwrite) {
        outbox.put(event);
      } else {
        const check = outbox.get(event.id);
        check.onsuccess = () => { if (!check.result) outbox.put(event); };
      }
    }
    await completed(tx);
  } finally {
    db.close();
  }
  return { records: content.records.length, attachments: attachments.length };
}
