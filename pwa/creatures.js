// Local character/monster archive using the *same* portable JSON schema as
// Godot's CreatureArchive, without copying Godot gameplay calculations.
import { getRecord, listRecords, putRecord, deleteRecord, insertRecords,
  getOrCreateSetting } from "./storage.js";
import { validateCreature, parseCreatureExport, makeOwnedCopy,
  referencedDefinitions, makeCreatureExport, MAX_CREATURE_BYTES } from "./creature_format.js";

const CREATURE_TYPE = "creature";
const HOMEBREW_SCOPE = "global";
const HOMEBREW_TYPE = "homebrew";
const OWNER_SETTING = "local-creature-owner-id";
const encoder = new TextEncoder();

function requiredScope(scope) {
  if (typeof scope !== "string" || !scope.trim() || scope.length > 256)
    throw new TypeError("Invalid creature archive scope");
  return scope;
}
function localId() {
  return Array.from(crypto.getRandomValues(new Uint8Array(16)),
    byte => byte.toString(16).padStart(2, "0")).join("");
}

export async function ownerId() {
  return getOrCreateSetting(OWNER_SETTING, localId);
}

export async function listCreatures(scope = "default") {
  return (await listRecords(requiredScope(scope), CREATURE_TYPE))
    .map(row => ({ creature: row.data, revision: row.revision }))
    .sort((a,b) => a.creature.name.localeCompare(b.creature.name));
}

export async function loadCreature(id, scope = "default") {
  return getRecord(requiredScope(scope), CREATURE_TYPE, id);
}

export async function saveCreature(creature, scope = "default", expectedRevision = null) {
  const record = validateCreature(creature);
  if (record.owner_id !== await ownerId()) {
    throw new Error("Cannot edit a creature owned by another installation");
  }
  const existing = await loadCreature(record.id, scope);
  if (existing) {
    if (existing.data.owner_id !== record.owner_id ||
        Number(existing.data.transfer_revision ?? 0) !==
          Number(record.transfer_revision ?? 0)) {
      throw new Error("Creature ownership/revision changed");
    }
    if (expectedRevision === null) {
      // Existing sheet edits must always be compare-and-swap, never last-writer-wins.
      throw new Error("Expected revision required when editing a saved creature");
    }
  } else if (expectedRevision !== null && expectedRevision !== 0) {
    throw new Error("Creature no longer exists");
  }
  return putRecord(requiredScope(scope), CREATURE_TYPE, record.id, record,
    expectedRevision === null ? 0 : expectedRevision);
}

export async function createCreature(kind = "character", name = "Nuova creatura", scope = "default") {
  if (!["character", "monster"].includes(kind)) throw new TypeError("Invalid creature kind");
  const creature = { id: "creature_" + localId(), owner_id: await ownerId(),
    transfer_revision: 0, linked_token_sync_id: "", linked_token_name: "",
    kind, name, inventory: [], documents: [] };
  const saved = await saveCreature(creature, scope, 0);
  return saved;
}

export async function removeCreature(id, scope = "default", expectedRevision) {
  const existing = await loadCreature(id, scope);
  if (!existing) return false;
  if (existing.data.owner_id !== await ownerId()) throw new Error("Not local owner");
  if (!Number.isInteger(expectedRevision) || expectedRevision !== existing.revision) {
    throw new Error("Creature changed since opening; refresh before deleting");
  }
  // For deletion the revision must be checked IN the write transaction.
  // Do not use deleteRecord (unconditional) for owned creature sheets.
  return deleteOwnedCreature(requiredScope(scope), id, expectedRevision);
}

// Delete with CAS (compare-and-swap), so a concurrent tab cannot lose edits.
async function deleteOwnedCreature(scope, id, expectedRevision) {
  const { deleteRecordIfRevision } = await import("./storage.js");
  return deleteRecordIfRevision(scope, CREATURE_TYPE, id, expectedRevision);
}

export async function importCreatureFile(file, scope = "default") {
  let payload;
  if (file instanceof Blob) {
    if (file.size > MAX_CREATURE_BYTES) throw new Error("VTT creature file exceeds 16 MiB");
    payload = JSON.parse(await file.text());
  } else {
    payload = file;
  }
  return importCreatureExport(payload, scope);
}

// Porting a creature always creates a fresh locally owned copy; it never
// transfers the authority or live token link of its source installation.
export async function importCreatureExport(raw, scope = "default") {
  const { creature, homebrew } = parseCreatureExport(raw);
  const local = makeOwnedCopy(creature, await ownerId(), "import_" + localId());
  const entries = homebrew.map(definition => ({
    scope: HOMEBREW_SCOPE, type: HOMEBREW_TYPE, id: definition.id,
    data: definition, ifAbsent: true
  }));
  entries.push({ scope: requiredScope(scope), type: CREATURE_TYPE,
    id: local.id, data: local });
  // If any entry fails, neither the creature nor its homebrew is installed.
  await insertRecords(entries);
  return { creature: local, revision: 1 };
}

export async function exportCreature(id, scope = "default") {
  const row = await loadCreature(id, scope);
  if (!row) throw new Error("Creature not found");
  const byId = new Map((await listRecords(HOMEBREW_SCOPE, HOMEBREW_TYPE))
    .map(item => [item.id, item.data]));
  const dependencies = referencedDefinitions(row.data, byId);
  const payload = makeCreatureExport(row.data, dependencies);
  return new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
}

export async function saveHomebrewDefinition(definition) {
  const { validDefinition } = await import("./creature_format.js");
  if (!validDefinition(definition)) throw new Error("Invalid portable definition");
  const old = await getRecord(HOMEBREW_SCOPE, HOMEBREW_TYPE, definition.id);
  // Keep existing content unless a caller explicitly edits it with its revision.
  if (old) throw new Error("Homebrew entry exists; editing requires expected revision");
  return putRecord(HOMEBREW_SCOPE, HOMEBREW_TYPE, definition.id, definition, 0);
}

export async function editHomebrewDefinition(definition, expectedRevision) {
  const { validDefinition } = await import("./creature_format.js");
  if (!validDefinition(definition)) throw new Error("Invalid portable definition");
  if (!Number.isInteger(expectedRevision) || expectedRevision < 1)
    throw new TypeError("Expected revision required");
  return putRecord(HOMEBREW_SCOPE, HOMEBREW_TYPE, definition.id, definition, expectedRevision);
}

// A real edit session: each changed record is queued for immediate IndexedDB
// persistence (not a debounced timer); flush resolves after all edits commit.
// UI wiring can call update() for every field/inventory/spell edit.
export async function openCreatureEditor(id, scope = "default") {
  let stored = await loadCreature(id, scope);
  if (!stored) throw new Error("Creature not found");
  let pending = Promise.resolve(), blocked = null;
  let latest = structuredClone(stored.data);
  return {
    read: () => structuredClone(latest),
    get revision() { return stored.revision; },
    update(patch) {
      if (blocked) return Promise.reject(blocked);
      if (!patch || typeof patch !== "object" || Array.isArray(patch))
        return Promise.reject(new TypeError("Creature update must be an object"));
      const proposed = validateCreature({ ...latest, ...structuredClone(patch) });
      if (proposed.id !== stored.data.id ||
          proposed.owner_id !== stored.data.owner_id ||
          Number(proposed.transfer_revision ?? 0) !==
            Number(stored.data.transfer_revision ?? 0)) {
        return Promise.reject(new Error("Cannot change creature identity through an edit"));
      }
      latest = proposed;
      // Serial transactions, revision checks, and no timers lost on background.
      pending = pending.then(async () => {
        const result = await saveCreature(proposed, scope, stored.revision);
        stored = result;
        return result;
      }).catch(error => {
        blocked = error;
        throw error;
      });
      return pending;
    },
    flush: () => pending,
    get error() { return blocked; }
  };
}
