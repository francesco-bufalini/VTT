// Shared item-copy, effect-extension and resource-tracker lifecycle for stored spells.
import {resolveOwnedItem,itemAttunementCount,requiresAttunement} from './item_controls.js';
const rows=v=>Array.isArray(v)?v:[];
// A physical spell-bearing item must have one stable instance, even if it
// originated as a stack. Shared by Spell-Storing Item and feat spell imprints.
export function isolateSpellBearingItem(record={},index,instanceId=''){
 if(!Number.isInteger(index))throw Error('Seleziona una copia di oggetto valida.');
 const inventory=structuredClone(rows(record.inventory)),item=inventory[index];
 if(!item||Number(item.quantity??1)<1)throw Error('Oggetto non disponibile.');
 if(item.standalone_instance!==true&&Number(item.quantity??1)>1){
  const rest=structuredClone(item);
  const count=Math.trunc(Number(item.quantity));
  rest.quantity=count-1;rest.equipped=false;rest.equipped_slots=[];
  rest.instance_id='pwa_instance_'+String(instanceId||'').trim()+'_rest';
  if(requiresAttunement(resolveOwnedItem(item))){
   const attuned=itemAttunementCount(item);
   item.attuned_count=Math.min(1,attuned);item.attuned=item.attuned_count>0;
   rest.attuned_count=Math.max(0,attuned-1);rest.attuned=rest.attuned_count>0;
  }
  item.quantity=1;inventory.splice(index+1,0,rest);
 }
 item.instance_id=item.instance_id||String(instanceId||'');
 if(!item.instance_id)throw Error('Identificatore fisico della copia mancante.');
 item.standalone_instance=true;
 return {inventory,item};
}

export function replaceItemSpellState(record,inventory,extension,tracker,removeExtension,{zeroSpent=false}={}){
 const spent={...(record.resource_tracker_spent||{})};
 if(zeroSpent)spent[tracker.id]=0;else delete spent[tracker.id];
 return {inventory,
  effect_extensions:[...rows(record.effect_extensions).filter(row=>!removeExtension(row)),extension],
  resource_trackers:[...rows(record.resource_trackers).filter(row=>row.id!==tracker.id),tracker],
  resource_tracker_spent:spent};
}
export function clearItemSpellState(record,removeExtension,trackerIds=[]){
 const ids=new Set(trackerIds.filter(Boolean)),spent={...(record.resource_tracker_spent||{})};
 for(const id of ids)delete spent[id];
 return {effect_extensions:rows(record.effect_extensions).filter(row=>!removeExtension(row)),
  resource_trackers:rows(record.resource_trackers).filter(row=>!ids.has(row.id)),
  resource_tracker_spent:spent};
}
