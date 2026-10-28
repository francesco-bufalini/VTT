// Portable inventory copies: one selected stack remains one item, including quantity
// and instance-specific properties. This does not transfer creature ownership.
import {referencedDefinitions,validDefinition,MAX_CREATURE_BYTES,MAX_HOMEBREW_ENTRIES} from './creature_format.js';
import {listRecords} from './storage.js';
import {openCreatureEditor,importHomebrewPackage} from './creatures.js';
import {DEFAULT_INVENTORY_CONTAINER} from './item_controls.js';

export const INVENTORY_SHARE_FORMAT='vtt_inventory_export_v1';
const isObject=value=>value!==null&&typeof value==='object'&&!Array.isArray(value)&&
  Object.getPrototypeOf(value)===Object.prototype;
const sizeOf=value=>new TextEncoder().encode(JSON.stringify(value)).length;

export function parseInventoryPackage(raw){
  const payload=typeof raw==='string'?JSON.parse(raw):raw;
  if(!isObject(payload)||payload.format!==INVENTORY_SHARE_FORMAT||payload.version!==1||
    !Array.isArray(payload.items)||payload.items.length<1||payload.items.length>200||
    !payload.items.every(item=>isObject(item)&&
      (typeof item.name==='string'&&item.name.trim()||typeof item.id==='string'&&item.id.trim())&&
      (item.quantity===undefined||Number.isInteger(Number(item.quantity))&&
        Number(item.quantity)>=1&&Number(item.quantity)<=99999))||
    !Array.isArray(payload.definitions)||payload.definitions.length>MAX_HOMEBREW_ENTRIES||
    !payload.definitions.every(validDefinition)||
    new Set(payload.definitions.map(row=>row.id)).size!==payload.definitions.length||
    sizeOf(payload)>MAX_CREATURE_BYTES)
    throw Error('Pacchetto inventario non valido.');
  return {items:structuredClone(payload.items),definitions:structuredClone(payload.definitions)};
}

export async function exportInventoryItems(creature,indices){
  const inventory=Array.isArray(creature?.inventory)?creature.inventory:[];
  const chosen=[...new Set(indices)].sort((a,b)=>a-b);
  if(!chosen.length||chosen.length>200||
    chosen.some(i=>!Number.isInteger(i)||i<0||i>=inventory.length))
    throw Error('Seleziona da 1 a 200 oggetti validi.');
  const items=chosen.map(i=>structuredClone(inventory[i]));
  const byId=new Map((await listRecords('global','homebrew')).map(row=>[row.id,row.data]));
  const definitions=referencedDefinitions({inventory:items},byId);
  const payload={format:INVENTORY_SHARE_FORMAT,version:1,items,definitions};
  parseInventoryPackage(payload);
  return payload;
}

export async function importInventoryItems(raw,targetCreatureId){
  const {items,definitions}=parseInventoryPackage(raw);
  if(!targetCreatureId)throw Error('Scegli una creatura destinataria.');
  const editor=await openCreatureEditor(targetCreatureId);
  const creature=editor.read();
  if(!creature||!Array.isArray(creature.inventory))throw Error('Inventario della creatura non disponibile.');
  // Imported copies cannot silently occupy equipment slots or consume attunement
  // on the receiving character. Preserve infusion, overrides, and other metadata.
  const copies=items.map(item=>({
    ...item,instance_id:'shared_'+crypto.randomUUID(),
    container_id:DEFAULT_INVENTORY_CONTAINER,
    equipped:false,equipped_slots:[],attuned:false,attuned_count:0
  }));
  if(definitions.length)await importHomebrewPackage({
    format:'vtt_homebrew_share_v1',version:1,definitions
  });
  await editor.update({inventory:[...creature.inventory,...copies]});
  await editor.flush();
  return copies.length;
}
