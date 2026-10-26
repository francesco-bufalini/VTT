import {validateVariants} from './creature_variants.js';
// Portable creature schema shared with Godot's CreatureArea/_save_exported_creature.
// The complete record remains opaque JSON: do not drop unfamiliar game fields.
export const CREATURE_FORMAT = "vtt_creature_export_v1";
export const CREATURE_VERSION = 1;
export const MAX_CREATURE_BYTES = 16 * 1024 * 1024;
export const MAX_HOMEBREW_BYTES = 12 * 1024 * 1024;
export const MAX_HOMEBREW_ENTRIES = 250;
const CATEGORIES = new Set(["items", "documents", "subclasses", "subclass_features",
  "monsters", "races", "classes", "spells", "conditions", "diseases", "effects",
  "class_features", "species_traits", "feats", "backgrounds", "optional_features"]);
const ID_PATTERN = /^homebrew:([a-z0-9][a-z0-9_-]{0,47}):([a-z_]+):([a-z0-9][a-z0-9_-]{0,63})$/;
const textBytes = value => new TextEncoder().encode(JSON.stringify(value)).length;
const object = value => !!value && typeof value === "object" &&
  !Array.isArray(value) && Object.getPrototypeOf(value) === Object.prototype;
const clone = value => JSON.parse(JSON.stringify(value));

export function validDefinition(value) {
  if (!object(value) || !object(value.data) ||
      typeof value.name !== "string" || !value.name.trim() || value.name.length > 160 ||
      typeof value.id !== "string") return false;
  const parts = ID_PATTERN.exec(value.id);
  return !!parts && CATEGORIES.has(parts[2]) && textBytes(value) < 2 * 1024 * 1024 - 512;
}

export function validateCreature(value) {
  if (!object(value) || !["character", "monster"].includes(value.kind) ||
      typeof value.name !== "string" || !value.name.trim() ||
      typeof value.id !== "string" || !value.id.trim() || value.id.length > 256 ||
      (value.owner_id !== undefined && typeof value.owner_id !== "string")) {
    throw new TypeError("Invalid VTT creature record");
  }
  if (value.parent_creature_id !== undefined &&
      (typeof value.parent_creature_id !== "string" || !value.parent_creature_id ||
       value.parent_creature_id.length > 256 || value.parent_creature_id === value.id ||
       value.kind !== "monster"))
    throw new TypeError("Invalid subcreature ownership");
  validateVariants(value);
  // JSON-compatible records only. Explicitly enforce the native 16 MiB limit.
  if (textBytes(value) > MAX_CREATURE_BYTES) throw new Error("Creature exceeds 16 MiB");
  return clone(value);
}

export function parseCreatureExport(input) {
  const payload = typeof input === "string" ? JSON.parse(input) : input;
  if (!object(payload) || payload.format !== CREATURE_FORMAT ||
      payload.version !== CREATURE_VERSION || !object(payload.creature)) {
    throw new TypeError("Unsupported VTT creature export");
  }
  // Older exports may not contain homebrew_content (Godot compatibility).
  const definitions = payload.homebrew_content ?? [];
  if (!Array.isArray(definitions) || definitions.length > MAX_HOMEBREW_ENTRIES ||
      textBytes(definitions) > MAX_HOMEBREW_BYTES || !definitions.every(validDefinition)) {
    throw new TypeError("Invalid portable homebrew definitions");
  }
  const creature = validateCreature(payload.creature);
  const subs = payload.subcreatures ?? [];
  if (creature.parent_creature_id || !Array.isArray(subs) || subs.length > 50 ||
      !subs.every(row => object(row) && row.parent_creature_id === creature.id &&
        !row.subcreatures && row.kind === "monster") ||
      new Set(subs.map(row => row.id)).size !== subs.length ||
      textBytes(payload) > MAX_CREATURE_BYTES)
    throw new TypeError("Invalid portable subcreatures");
  return { creature, homebrew: clone(definitions),
    subcreatures: subs.map(validateCreature) };
}

export function makeOwnedCopy(creature, ownerId, newId) {
  if (typeof ownerId !== "string" || ownerId.length < 16 ||
      typeof newId !== "string" || !newId.startsWith("import_")) {
    throw new TypeError("Invalid local identity");
  }
  const record = validateCreature(creature);
  record.id = newId;
  record.owner_id = ownerId;
  record.transfer_revision = 0;
  record.linked_token_sync_id = "";
  record.linked_token_name = "";
  return record;
}

export function referencedDefinitions(creature, byId) {
  const seen = new Set(), wanted = new Set();
  function find(value) {
    if (typeof value === "string" && ID_PATTERN.test(value)) wanted.add(value);
    else if (Array.isArray(value)) value.forEach(find);
    else if (object(value)) Object.values(value).forEach(find);
  }
  find(creature);
  const output = [];
  while (wanted.size) {
    const id = wanted.values().next().value;
    wanted.delete(id);
    if (seen.has(id)) continue;
    seen.add(id);
    const definition = byId.get(id);
    if (!definition || !validDefinition(definition)) {
      throw new Error("Missing portable homebrew dependency: " + id);
    }
    output.push(clone(definition));
    find(definition);
    if (output.length > MAX_HOMEBREW_ENTRIES) throw new Error("Too many homebrew definitions");
  }
  output.sort((a,b) => a.id.localeCompare(b.id));
  if (textBytes(output) > MAX_HOMEBREW_BYTES) throw new Error("Homebrew content exceeds 12 MiB");
  return output;
}

export function makeCreatureExport(creature, definitions = [], subcreatures = []) {
  const payload = { format: CREATURE_FORMAT, version: CREATURE_VERSION,
    creature: validateCreature(creature), homebrew_content: clone(definitions),
    ...(subcreatures.length ? {subcreatures: subcreatures.map(validateCreature)} : {}) };
  // Godot's import dialog limits the complete file to 16 MiB.
  if (textBytes(payload) > MAX_CREATURE_BYTES) throw new Error("Portable export exceeds 16 MiB");
  parseCreatureExport(payload);
  return payload;
}
