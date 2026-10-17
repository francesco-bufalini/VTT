// Local character/monster archive using the *same* portable JSON schema as
// Godot's CreatureArchive, without copying Godot gameplay calculations.
import { getRecord, listRecords, putRecord, deleteRecordIfRevision, insertRecords,
  getOrCreateSetting } from "./storage.js";
import { validateCreature, validDefinition, parseCreatureExport, makeOwnedCopy,
  referencedDefinitions, makeCreatureExport, MAX_CREATURE_BYTES } from "./creature_format.js";

// Native-compatible defaults for newly created records; imported records remain untouched.
function initialCreature(kind,name,id,owner_id){
  if(!["character","monster"].includes(kind)||typeof name!=="string"||!name.trim()||
     !id||!owner_id)throw Error("Dati iniziali della creatura non validi.");
  const c={
    id,name,owner_id,kind,transfer_revision:0,
    default_miniature_id:"",current_miniature_id:"",size_name:"Medium",
    footprint:1,reach_feet:5,visual_front_quarter_turns:0,party_id:"",
    rules_version:"2014",player_name:"",classes:[],class:"",class_source:"",
    class_id:"",subclass:"",subclass_id:"",subclass_source:"",
    level:1,xp:0,proficiency_bonus:2,spellcasting_calculation:{},
    species:"",species_id:"",species_source:"",subrace:"",subrace_id:"",
    subrace_source:"",subtype:"",subtype_is_custom:false,background:"",
    background_source:"",alignment:"Completamente neutrale",sex:"",inspiration:false,
    abilities:{str:10,dex:10,con:10,int:10,wis:10,cha:10},
    saving_throw_proficiencies:[],skill_proficiencies:[],skill_expertise:[],
    armor_class:10,armor_class_base:10,armor_natural_formula:"",
    temporary_ac:0,initiative:0,initiative_base:0,
    max_hp:1,max_hp_base:1,current_hp:1,temporary_hp:0,
    second_form_hp:0,second_form_max_hp:0,
    speed_base:30,speed:30,speed_is_custom:false,darkvision:0,exhaustion:0,
    hit_dice:"",death_save_successes:0,death_save_failures:0,
    attacks:"",attack_ability:"str",attack_overrides:{},equipped_attack_id:"",
    equipped_inventory_index:-1,hand_main_special:"none",hand_off_special:"none",
    hand_grip_two_handed:false,two_weapon_fighting:false,fighting_styles:[],
    proficiency_choices:[],formula_bonuses:[],dice_bonuses:[],
    resource_trackers:[],resource_tracker_spent:{},origin_spell_grants:[],
    origin_spell_configs:{},spellcasting_section_abilities:{},
    active_spell_context:{},conditions:[],concentrating_spell_id:"",
    damage_defense_overrides:{},condition_immunity_overrides:{},
    documents:[],inventory:[],weapons_catalog:[],armor_catalog:[],
    tools_catalog:[],languages_catalog:[],feats_catalog:[],class_features_catalog:[],
    species_traits_catalog:[],optional_features_catalog:[],inventory_mundane:[],
    inventory_magic:[],
    spellcasting_class:"",spellcasting_ability:"",spell_save_dc:0,
    spell_attack_bonus:0,spells:[],prepared_spells:[],spellbook_spells:[],
    spell_slots_total:Array(10).fill(0),spell_slots_spent:Array(10).fill(0),
    pact_slots_total:0,pact_slots_spent:0,pact_slot_level:1,
    spell_slots_visible:true,spell_slots_manual:false,spell_slots_automatic:false,
    pact_slots_visible:true,linked_token_sync_id:"",linked_token_name:"",
    background_personality:"",notes:"",appearance:"",personality_traits:"",
    ideals:"",bonds:"",flaws:"",additional_traits:"",
    faction:"",symbol:"",enemies:"",age:"",height:"",weight:"",eyes:"",
    skin:"",hair:"",ammunition:"",armor_proficiencies:"",
    weapon_proficiencies:"",tool_proficiencies:"",languages:"",
    feats:"",equipment:"",consumables:"",magic_items:"",
    class_features:"",racial_background_traits:"",limited_features:""
  };
  if(kind==="monster")c.stat_block={};
  return c;
}

const CREATURE_TYPE = "creature";
const HOMEBREW_SCOPE = "global";
const HOMEBREW_TYPE = "homebrew";
const OWNER_SETTING = "local-creature-owner-id";

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
  const creature = initialCreature(kind, name, "creature_" + localId(), await ownerId());
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
  return deleteRecordIfRevision(requiredScope(scope), CREATURE_TYPE, id, expectedRevision);
}

export async function importCreatureFile(file, scope = "default") {
  let payload;
  if (file instanceof Blob) {
    if (file.size > MAX_CREATURE_BYTES) throw new Error("VTT creature file exceeds 16 MiB");
    payload = JSON.parse(await file.text());
  } else {
    payload = file;
  }
  if (payload?.format === "vtt_creature_batch_export_v1") {
    const entries=payload.entries;
    if(payload.version!==1 || !Array.isArray(entries) || entries.length<1 || entries.length>200)
      throw new Error("Archivio creature multiplo non valido.");
    // Import one portable package in ONE IndexedDB transaction. A failure
    // (quota, collision, malformed dependency) must not leave half the
    // selected characters behind on the phone.
    const parsed=entries.map(parseCreatureExport);
    const owner=await ownerId();
    const definitions=new Map();
    const imported=[];
    for(const {creature,homebrew} of parsed){
      for(const definition of homebrew){
        const prior=definitions.get(definition.id);
        if(prior && JSON.stringify(prior)!==JSON.stringify(definition))
          throw new Error("Definizioni homebrew in conflitto nel pacchetto: "+definition.id);
        definitions.set(definition.id,definition);
      }
      imported.push(makeOwnedCopy(creature,owner,"import_"+localId()));
    }
    const batch=[
      ...[...definitions.values()].map(definition=>({
        scope:HOMEBREW_SCOPE,type:HOMEBREW_TYPE,id:definition.id,
        data:definition,ifAbsent:true
      })),
      ...imported.map(creature=>({
        scope:requiredScope(scope),type:CREATURE_TYPE,id:creature.id,data:creature
      }))
    ];
    await insertRecords(batch);
    return imported.map(creature=>({creature,revision:1}));
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
