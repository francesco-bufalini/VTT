import {resolveVariant, applyVariantEdit, migrateSecondForm, bestiarySheet} from './creature_variants.js';
// Local character/monster archive using the *same* portable JSON schema as
// Godot's CreatureArchive, without copying Godot gameplay calculations.
import { getRecord, listRecords, putRecord, deleteRecordIfRevision, deleteCreatureFamily, insertRecords,
  localOwnerId } from "./storage.js";
import { validateCreature, validDefinition, parseCreatureExport, makeOwnedCopy,
  referencedDefinitions, makeCreatureExport, MAX_CREATURE_BYTES } from "./creature_format.js";
import { initialCreature, experienceFloorPatch } from "./character_core.js";
import { consolidateOwnedItems } from "./item_controls.js";

const CREATURE_TYPE = "creature";
const HOMEBREW_SCOPE = "global";
const HOMEBREW_TYPE = "homebrew";

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
  return localOwnerId();
}

export async function listCreatures(scope = "default", {includeSubcreatures = false} = {}) {
  return (await listRecords(requiredScope(scope), CREATURE_TYPE))
    .filter(row => includeSubcreatures || !row.data.parent_creature_id)
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
  if (record.parent_creature_id) {
    const parent = await loadCreature(record.parent_creature_id, scope);
    if (!parent || parent.data.parent_creature_id ||
        parent.data.owner_id !== record.owner_id)
      throw new Error("Proprietario della sottocreatura non disponibile.");
  }
  if (existing) {
    if ((existing.data.parent_creature_id || "") !== (record.parent_creature_id || ""))
      throw new Error("Cannot change subcreature parent");

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

export async function createCreature(kind = "character", name = "Nuova creatura", scope = "default", miniature = null) {
  if (!["character", "monster"].includes(kind)) throw new TypeError("Invalid creature kind");
  const creature = initialCreature(kind, name, "creature_" + localId(), await ownerId());
  // Assign the chosen miniature in the initial save, not in a second write:
  // an interrupted creation must never leave an unconfigured new sheet.
  if (miniature !== null) {
    const id=typeof miniature?.id==="string"?miniature.id.trim():"";
    if (!id || id.length>160) throw new Error("Seleziona una miniatura valida.");
    const footprint=Number(miniature.footprint);
    creature.default_miniature_id=id;
    creature.current_miniature_id=id;
    creature.size_name=typeof miniature.size_name==="string"&&miniature.size_name.trim()?miniature.size_name:"Medium";
    creature.footprint=Number.isFinite(footprint)&&footprint>=0.5&&footprint<=100?footprint:1;
  }
  const saved = await saveCreature(creature, scope, 0);
  return saved;
}

export async function listSubcreatures(parentId, scope = "default") {
  return (await listRecords(requiredScope(scope), CREATURE_TYPE))
    .filter(row => row.data.parent_creature_id === parentId)
    .map(row => ({creature: row.data, revision: row.revision}))
    .sort((a,b) => a.creature.name.localeCompare(b.creature.name));
}

// A familiar is a complete monster sheet, never another form of its owner.
export async function createSubcreature(parentId, source, reference = {}, scope = "default") {
  const parent = await loadCreature(parentId, scope);
  if (!parent || parent.data.parent_creature_id || parent.data.owner_id !== await ownerId())
    throw new Error("Apri una creatura proprietaria valida.");
  if ((await listSubcreatures(parentId, scope)).length >= 50)
    throw new Error("Limite di 50 sottocreature per proprietario.");
  const raw = source?.stat_block || source;
  if (!raw || typeof raw !== "object" || Array.isArray(raw))
    throw new Error("Voce del bestiario non valida.");
  const creature = source?.kind === "monster" ? structuredClone(source) :
    bestiarySheet(raw, reference.miniature);
  creature.id = "creature_" + localId();
  creature.owner_id = parent.data.owner_id;
  creature.kind = "monster";
  creature.parent_creature_id = parentId;
  creature.transfer_revision = 0;
  creature.linked_token_sync_id = "";
  creature.linked_token_name = "";
  creature.current_form_id = "";
  creature.bestiary_ref = {
    name: String(reference.name || raw.name || creature.name).slice(0,160),
    source: String(reference.source || raw.source || "").slice(0,80)
  };
  if (reference.spell_id) creature.companion_origin_spell_id = String(reference.spell_id).slice(0,256);
  if (reference.feature_id) creature.companion_origin_feature_id = String(reference.feature_id).slice(0,256);
  if (reference.rule_id) creature.companion_rule_id = String(reference.rule_id).slice(0,160);
  if (reference.duration) creature.companion_duration = String(reference.duration).slice(0,80);
  if (reference.template_id) creature.companion_template_id = String(reference.template_id).slice(0,160);
  if (reference.grant?.kind && reference.grant?.id)
    creature.companion_grant={kind:String(reference.grant.kind).slice(0,60),id:String(reference.grant.id).slice(0,256)};
  if (reference.limit_per_owner_rule===1) creature.companion_selected=true;
  return saveCreature(creature, scope, 0);
}

// One complete, editable saved sheet per owner + bestiary source/name.
// Other selected types may be hidden, but are never reset or deleted.
export async function summonSubcreature(parentId,source,reference={},scope="default"){
 const max=Number(reference.limit_per_owner_rule??1);
 if(!Number.isInteger(max)||max<0||max>50)throw Error("Limite evocazione non valido.");
 const children=await listSubcreatures(parentId,scope),stat=source?.stat_block||source;
 const name=String(reference.name||stat?.name||"").trim().toLowerCase();
 const book=String(reference.source||stat?.source||"").trim().toLowerCase();
 const existing=max===1?children.find(row=>
  String(row.creature.bestiary_ref?.name||"").trim().toLowerCase()===name&&
  String(row.creature.bestiary_ref?.source||"").trim().toLowerCase()===book):null;
 const fromRule=children.filter(row=>reference.rule_id&&row.creature.companion_rule_id===reference.rule_id);
 if(max>1&&fromRule.length>=max)throw Error("Limite di creature evocate raggiunto.");
 if(max===1)for(const other of fromRule){
  if(other.creature.id===existing?.creature.id||other.creature.companion_selected===false)continue;
  await saveCreature({...other.creature,companion_selected:false},scope,other.revision);
 }
 if(existing){
  const updated={...existing.creature,companion_selected:true,
   ...(reference.rule_id?{companion_rule_id:String(reference.rule_id)}:{}),
   ...(reference.spell_id?{companion_origin_spell_id:String(reference.spell_id)}:{}),
   ...(reference.feature_id?{companion_origin_feature_id:String(reference.feature_id)}:{}),
   ...(reference.grant?.kind&&reference.grant?.id?{companion_grant:{
    kind:String(reference.grant.kind),id:String(reference.grant.id)}}:{})};
  return {...await saveCreature(updated,scope,existing.revision),reused:true};
 }
 return {...await createSubcreature(parentId,source,reference,scope),reused:false};
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
  const children = await listSubcreatures(id, scope);
  if (children.length)
    return deleteCreatureFamily(requiredScope(scope),
      [{id,revision:expectedRevision},...children.map(row=>({id:row.creature.id,revision:row.revision}))]);
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
    const family=[];
    for(const {creature,homebrew,subcreatures} of parsed){
      for(const definition of homebrew){
        const prior=definitions.get(definition.id);
        if(prior && JSON.stringify(prior)!==JSON.stringify(definition))
          throw new Error("Definizioni homebrew in conflitto nel pacchetto: "+definition.id);
        definitions.set(definition.id,definition);
      }
      const local = makeOwnedCopy(creature,owner,"import_"+localId());
      imported.push(local);
      for (const child of subcreatures)
        family.push({...makeOwnedCopy(child,owner,"import_"+localId()), parent_creature_id:local.id});
    }
    const batch=[
      ...[...definitions.values()].map(definition=>({
        scope:HOMEBREW_SCOPE,type:HOMEBREW_TYPE,id:definition.id,
        data:definition,ifAbsent:true
      })),
      ...[...imported,...family].map(creature=>({
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
  const { creature, homebrew, subcreatures } = parseCreatureExport(raw);
  const owner = await ownerId();
  const local = makeOwnedCopy(creature, owner, "import_" + localId());
  const family = subcreatures.map(child=>({
    ...makeOwnedCopy(child, owner, "import_" + localId()),parent_creature_id:local.id
  }));
  const entries = homebrew.map(definition => ({
    scope: HOMEBREW_SCOPE, type: HOMEBREW_TYPE, id: definition.id,
    data: definition, ifAbsent: true
  }));
  for (const member of [local,...family])
    entries.push({ scope: requiredScope(scope), type: CREATURE_TYPE,
      id: member.id, data: member });
  // If any entry fails, neither the creature nor its homebrew is installed.
  await insertRecords(entries);
  return { creature: local, revision: 1 };
}

export async function exportCreature(id, scope = "default") {
  const row = await loadCreature(id, scope);
  if (!row) throw new Error("Creature not found");
  const byId = new Map((await listRecords(HOMEBREW_SCOPE, HOMEBREW_TYPE))
    .map(item => [item.id, item.data]));
  if (row.data.parent_creature_id)
    throw new Error("Esporta la sottocreatura insieme al suo proprietario.");
  const children = (await listSubcreatures(id, scope)).map(row => row.creature);
  const dependencies = referencedDefinitions([row.data,...children], byId);
  const payload = makeCreatureExport(row.data, dependencies, children);
  return new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
}

export async function exportCreatureBatch(ids, scope = "default") {
  if (!Array.isArray(ids) || !ids.length || ids.length > 200)
    throw new Error("Seleziona da 1 a 200 creature per l'esportazione.");
  const entries=[];
  const roots = new Set();
  for (const id of ids) {
    const row = await loadCreature(id,scope);
    if (!row) throw new Error("Creature not found");
    roots.add(row.data.parent_creature_id || id);
  }
  for (const id of roots) entries.push(JSON.parse(await (await exportCreature(id,scope)).text()));
  const data=JSON.stringify({format:"vtt_creature_batch_export_v1",version:1,entries},null,2);
  if(new TextEncoder().encode(data).length>MAX_CREATURE_BYTES)
    throw new Error("Esportazione troppo grande per il formato portatile.");
  return new Blob([data],{type:"application/json"});
}

// Share a homebrew definition together with any referenced homebrew entries.
// The receiving device imports definitions into its catalog, not into a
// character. Existing identical IDs are reused; conflicting IDs are rejected.
export async function exportHomebrewPackage(id) {
  const byId=new Map((await listRecords(HOMEBREW_SCOPE,HOMEBREW_TYPE))
    .map(row=>[row.id,row.data]));
  if(!byId.has(id))throw new Error("Contenuto homebrew non trovato.");
  const definitions=referencedDefinitions({homebrew_id:id},byId);
  return {format:"vtt_homebrew_share_v1",version:1,definitions};
}

// Character-owned custom catalog rows may not be in the global homebrew
// archive. Turn such definitions into the same portable format, preserving all
// structured fields and only excluding local instance state. Never mutate the
// original record or silently send a reference without its dependencies.
export async function exportCatalogHomebrewEntry(entry) {
  if(!entry?._homebrew||typeof entry.name!=="string"||!entry.name.trim())
    throw new Error("Seleziona un contenuto homebrew valido.");
  if(typeof entry.id==="string" && await getRecord(HOMEBREW_SCOPE,HOMEBREW_TYPE,entry.id))
    return exportHomebrewPackage(entry.id);
  const type=String(entry._category||entry.category||"");
  const category=["weapons","armor","tools","magic_items","mundane_items"].includes(type)?"items":type;
  const fields={...entry};
  for(const key of ["id","name","source","category","_category","_homebrew","data",
    "_description_warning","instance_id","quantity","equipped","equipped_slots",
    "attuned","attuned_count","instance_overrides","container_id",
    "uses_spent","charges_spent"]) delete fields[key];
  const value={
    id:String(entry.id||""), category, name:entry.name,
    source:String(entry.source||"Personalizzato"),
    data:{...(entry.data&&typeof entry.data==="object"&&!Array.isArray(entry.data)?entry.data:{}),...fields}
  };
  if(!validDefinition(value)){
    const id=Array.from(crypto.getRandomValues(new Uint8Array(12)),
      x=>x.toString(16).padStart(2,"0")).join("");
    value.id="homebrew:shared:"+category+":entry_"+id;
  }
  if(!validDefinition(value))throw new Error("Questo contenuto non è esportabile come homebrew portabile.");
  const byId=new Map((await listRecords(HOMEBREW_SCOPE,HOMEBREW_TYPE))
    .map(row=>[row.id,row.data]));
  const other=referencedDefinitions(value.data,byId);
  return {format:"vtt_homebrew_share_v1",version:1,definitions:[value,...other]};
}

export async function importHomebrewPackage(raw) {
  const payload=typeof raw==="string"?JSON.parse(raw):raw;
  if(payload?.format!=="vtt_homebrew_share_v1"||payload.version!==1||
    !Array.isArray(payload.definitions)||!payload.definitions.length||
    payload.definitions.length>250||!payload.definitions.every(validDefinition)||
    new TextEncoder().encode(JSON.stringify(payload)).length>12*1024*1024)
    throw new Error("Pacchetto homebrew non valido.");
  const seen=new Set();
  for(const definition of payload.definitions){
    if(seen.has(definition.id))throw new Error("ID homebrew duplicato nel pacchetto.");
    seen.add(definition.id);
  }
  await insertRecords(payload.definitions.map(definition=>({
    scope:HOMEBREW_SCOPE,type:HOMEBREW_TYPE,id:definition.id,
    data:definition,ifAbsent:true
  })));
  return payload.definitions.length;
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
  // Upgrade older saves with repeated copies as soon as the creature is edited.
  // Do not rewrite records that already have canonical inventory stacks.
  if (Array.isArray(stored.data.inventory)) {
    const inventory = consolidateOwnedItems(stored.data.inventory);
    if (JSON.stringify(inventory) !== JSON.stringify(stored.data.inventory))
      stored = await saveCreature({...stored.data,inventory},scope,stored.revision);
  }
  const migrated=migrateSecondForm(stored.data);
  if(JSON.stringify(migrated)!==JSON.stringify(stored.data))
    stored=await saveCreature(migrated,scope,stored.revision);
  // Repair legacy high-level characters with insufficient XP on first open.
  // This is local IndexedDB migration; no desktop connection is required.
  const xpRepair=experienceFloorPatch(stored.data);
  if(Object.keys(xpRepair).length)
    stored=await saveCreature({...stored.data,...xpRepair},scope,stored.revision);
  let pending = Promise.resolve(), blocked = null;
  let latest = structuredClone(stored.data);
  const editor = {
    read: () => resolveVariant(latest),
    readBase: () => structuredClone(latest),
    get revision() { return stored.revision; },
    replaceBase(record) { return editor.update(record,true); },
    update(patch, replaceBase=false) {
      if (blocked) return Promise.reject(blocked);
      // Evaluate read-modify-write edits at submission against the current
      // optimistic state, before any asynchronous persistence can interleave.
      if (typeof patch === "function") {
        try { patch = patch(resolveVariant(latest)); }
        catch (error) { return Promise.reject(error); }
      }
      if (!patch || typeof patch !== "object" || Array.isArray(patch))
        return Promise.reject(new TypeError("Creature update must be an object"));
      if(Array.isArray(patch.inventory))patch={...patch,inventory:consolidateOwnedItems(patch.inventory)};
      const proposed = validateCreature(replaceBase?structuredClone(patch):applyVariantEdit(latest,structuredClone(patch)));
      // Also cover direct/imported edits that bypass the Info field handlers.
      Object.assign(proposed,experienceFloorPatch(proposed));
      if (Array.isArray(proposed.inventory))
        proposed.inventory = consolidateOwnedItems(proposed.inventory);
      if (proposed.id !== stored.data.id ||
          proposed.owner_id !== stored.data.owner_id ||
          proposed.kind !== stored.data.kind ||
          (proposed.parent_creature_id || "") !== (stored.data.parent_creature_id || "") ||
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
  return editor;
}

// Android CreatureArea._copy_public_token_status parity: a token's public
// status is sufficient to reconcile locally owned spell origins, but NEVER
// a source of private inventory, hit points, class stats or dice settings.
export function linkedTokenStatusPatch(record, token, spells=[]){
  if(!record?.linked_token_sync_id||!token||token.id!==record.linked_token_sync_id)
    return {};
  const patch={};
  for(const key of ["conditions","concentrating_spell_id"]){
    const value=token[key];
    if(key==="conditions"&&(!Array.isArray(value)||value.length>64||
       !value.every(x=>typeof x==="string"&&x.length<=256)))continue;
    if(key==="concentrating_spell_id"&&typeof value!=="string")continue;
    if(JSON.stringify(record[key]??(key==="conditions"?[]:""))!==JSON.stringify(value))
      patch[key]=structuredClone(value);
  }
  // The native board publishes spell IDs after resolution on the *specific*
  // target tokens. Do not mistake temporary targeting previews for effects.
  if(Array.isArray(token.active_spell_ids)&&token.active_spell_ids.length<=128&&
    token.active_spell_ids.every(id=>typeof id==="string"&&id.length<=256)){
    const ids=new Set(token.active_spell_ids.filter(Boolean)),previous=Array.isArray(record.proficiency_origins)?
      record.proficiency_origins:[];
    const known=new Map((Array.isArray(spells)?spells:[]).filter(row=>row?.id).map(row=>[row.id,row]));
    const next=structuredClone(previous),context={...(record.active_spell_context||{})};
    let originsChanged=false,contextsChanged=false;
    for(let i=next.length-1;i>=0;i--){
      const row=next[i],id=String(row?.id||"");
      if(row?.group!=="spell"||row?.applied!==true||!id.startsWith("spell:")||
         ids.has(id.slice(6)))continue;
      next.splice(i,1);originsChanged=true;
      if(Object.hasOwn(context,id.slice(6))){delete context[id.slice(6)];contextsChanged=true;}
    }
    for(const id of ids){
      const sid="spell:"+id,exists=next.find(row=>row?.id===sid&&row.group==="spell");
      if(exists){
        if(exists.applied!==true||exists.disabled===true){
          exists.applied=true;exists.disabled=false;originsChanged=true;
        }
      }else{
        // Native board already validates duration and resolves the spell ID.
        // Keep a portable applied-origin even when the full catalog is offline.
        next.push({id:sid,group:"spell",name:"Incantesimo · "+(known.get(id)?.name||id),
          disabled:false,automatic:false,applied:true});
        originsChanged=true;
      }
    }
    if(originsChanged)patch.proficiency_origins=next;
    if(contextsChanged)patch.active_spell_context=context;
  }
  for(const key of ["current_miniature_id","default_miniature_id"]){
    if(typeof token[key]==="string"&&token[key]&&token[key]!==record[key])
      patch[key]=token[key];
  }
  // Party and size are native token properties; update only these public
  // appearance fields. Never infer them from a miniature catalogue on mobile.
  if(typeof token.party_id==="string"&&token.party_id.length<=80&&
     token.party_id!==(record.party_id||""))patch.party_id=token.party_id;
  if(typeof token.size_name==="string"&&token.size_name.length<=80&&
     token.size_name&&token.size_name!==record.size_name)patch.size_name=token.size_name;
  if(typeof token.footprint_cells==="number"&&Number.isFinite(token.footprint_cells)&&
     token.footprint_cells>=0.5&&token.footprint_cells<=100&&
     token.footprint_cells!==record.footprint)patch.footprint=token.footprint_cells;
  return patch;
}

export async function syncLinkedTokenStatuses(mapData,{liveEditor=null,spells=[],scope="default"}={}){
  if(!Array.isArray(mapData?.tokens))return [];
  const byId=new Map(mapData.tokens.filter(row=>row&&typeof row.id==="string").map(row=>[row.id,row]));
  if(!byId.size)return [];
  const updated=[];
  // Use the *same* live editor for a currently open sheet. A separate editor
  // would invalidate its compare-and-swap revision and drop the next edit.
  for(const {creature} of await listCreatures(scope)){
    const token=byId.get(creature.linked_token_sync_id);
    if(!token)continue;
    const editor=liveEditor?.id===creature.id&&liveEditor.editor?
      liveEditor.editor:await openCreatureEditor(creature.id,scope);
    const patch=linkedTokenStatusPatch(editor.read(),token,spells);
    if(Object.keys(patch).length){
      await editor.update(patch);
      updated.push(creature.id);
    }
  }
  return updated;
}
