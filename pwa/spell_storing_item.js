// Artificer (TCE, 2014) Spell-Storing Item: one active effect on one owned
// physical inventory copy. The item remains itself: there is no duplicate.
// The usual effect-extension and resource-tracker pipelines own its UI and uses.
import {itemKind,resolveOwnedItem,targetableInventoryItems,itemAttunementCount,requiresAttunement} from './item_controls.js';
import {normalizeEffectExtension,effectExtensionsFor} from './effect_extensions.js';
import {spendTrackerUses} from './character_core.js';
const rows=v=>Array.isArray(v)?v:[];
const norm=v=>String(v??'').trim().toLowerCase();
const PREFIX='artificer:spell_storing_item:';
export const storedSpellTrackerId=record=>PREFIX+String(record?.id||'');
export const storedSpellExtensionId=record=>PREFIX+String(record?.id||'')+':effect';

export function spellStoringArtificerLevel(record={}){
 if(record.rules_version==='2024')return 0;
 const members=rows(record.classes).length?rows(record.classes):
  record.class?[{name:record.class,source:record.class_source,level:record.level}]:[];
 return Math.max(0,...members.filter(row=>norm(row.name)==='artificer'&&
  (!row.source||norm(row.source)==='tce')).map(row=>Number(row.level)||0));
}
export function eligibleSpellStoringItems(record={}){
 return targetableInventoryItems(record,{},item=>{
  const resolved=resolveOwnedItem(item),kind=itemKind(resolved);
  const type=String(resolved.type||'').split('|')[0].toUpperCase();
  // Artificers use artisan's/thieves' tools and their infused items as foci.
  return kind==='weapon'||['M','R','SCF','AT','T'].includes(type)||
   Boolean(item.infusion?.id||resolved.spellcasting_focus||resolved.is_spellcasting_focus);
 });
}
export function eligibleStoredSpells(spells=[]){
 return rows(spells).filter(spell=>{
  if(!spell?.id||spell.internal_grant||![1,2].includes(Number(spell.level)))return false;
  if(!rows(spell.classes).some(cls=>norm(typeof cls==='string'?cls:cls?.name)==='artificer'))return false;
  const times=rows(spell.time);
  if(times.length)return times.some(t=>Number(t?.number)===1&&norm(t?.unit)==='action');
  return /^(?:1\s*)?(?:action|azione)$/i.test(String(spell.casting_time||'').trim());
 }).sort((a,b)=>Number(a.level)-Number(b.level)||
  String(a.name||'').localeCompare(String(b.name||''),'it',{sensitivity:'base'}));
}
export function storedSpellExtension(record={}){
 return rows(record.effect_extensions).find(row=>row?.id===storedSpellExtensionId(record)||
  row?.stored_spell_feature==='spell_storing_item')||null;
}
export function storedSpellMaxUses(modifier){
 const n=Number(modifier);
 return Math.max(2,Number.isFinite(n)?Math.trunc(n)*2:2);
}
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
export function storeSpellInItemPatch(record={},calculated={},index,spell={},spellDescription='',instanceId=''){
 if(spellStoringArtificerLevel(record)<11)throw Error('Spell-Storing Item richiede Artefice TCE di livello 11.');
 const feature=rows(calculated.features).find(f=>norm(f.name)==='spell-storing item'&&
  !f.disabled&&!f.inactive&&String(f.origin_key||'').startsWith('class|'));
 if(!feature||record.origin_enabled?.[feature.origin_id]===false)
  throw Error('Il privilegio Spell-Storing Item non è disponibile.');
 const available=eligibleSpellStoringItems(record);
 if(!Number.isInteger(index)||!available.some(row=>row.index===index))
  throw Error('Seleziona un’arma o un focus da incantatore disponibile.');
 if(!eligibleStoredSpells([spell]).length)
  throw Error('Serve un incantesimo da Artefice di 1° o 2° livello con tempo di lancio 1 azione.');
 const {inventory,item}=isolateSpellBearingItem(record,index,instanceId);
 const trackerId=storedSpellTrackerId(record),extensionId=storedSpellExtensionId(record);
 const max=storedSpellMaxUses(calculated?.abilities?.int?.modifier);
 const description='L’oggetto contiene '+String(spell.name)+
  ' (livello '+spell.level+'). Una creatura che lo tiene in mano può usare un’azione per '+
  'produrre l’effetto dell’incantesimo, usando la caratteristica da incantatore dell’Artefice '+
  '(Intelligenza) e concentrandosi personalmente quando richiesto. Non consuma slot. '+
  'Utilizzi: due volte il modificatore di Intelligenza (minimo 2); '+
  'l’effetto termina al prossimo riposo lungo o a una nuova applicazione.';
 const extension=normalizeEffectExtension({
  id:extensionId,origin_id:feature.origin_id,parent_origin:feature.origin_key,
  origin_name:'Tratto · Spell-Storing Item',stored_spell_feature:'spell_storing_item',
  target_kind:'item',target_name:String(item.name||item.id),target_id:String(item.id),
  target_instance_id:String(item.instance_id),operation:'grant_action',trigger:'on_use',
  frequency:'each',description,spell_id:String(spell.id),spell_name:String(spell.name),
  spell_level:Number(spell.level),spell_description:String(spellDescription||'').trim(),
  tracker_id:trackerId,casting_ability:'int',action_type:'action'
 });
 if(!extension)throw Error('Impossibile creare l’estensione dell’oggetto.');
 const existing=rows(record.effect_extensions).filter(row=>
  row?.id!==extensionId&&row?.stored_spell_feature!=='spell_storing_item');
 const resources=rows(record.resource_trackers).filter(row=>row?.id!==trackerId);
 const spent={...(record.resource_tracker_spent||{})};
 delete spent[trackerId];
 return {
  inventory,
  effect_extensions:[...existing,extension],
  resource_trackers:[...resources,{
   id:trackerId,name:'Spell-Storing Item · '+String(item.name||item.id),
   max,min_max:2,max_formula:'int_mod*2',recharge:'manual',
   origin_id:feature.origin_id,origin_name:'Tratto · Spell-Storing Item',
   origin_class:'Artificer',origin_class_source:'TCE'
  }],
  resource_tracker_spent:spent
 };
}
export function useStoredSpellPatch(record={},calculated={},index){
 const item=rows(record.inventory)[index],extension=storedSpellExtension(record);
 if(!item||!extension||!effectExtensionsFor([extension],{
  kind:'item',id:item.id,name:item.name,instance_id:item.instance_id,
  inventory_index:index}).length)throw Error('L’oggetto non contiene un incantesimo attivo.');
 const tracker=rows(calculated.trackers).find(row=>row.id===extension.tracker_id&&!row.disabled);
 return spendTrackerUses(record,extension.tracker_id,1,tracker?[tracker]:[]);
}
export function clearStoredSpellPatch(record={}){
 const old=storedSpellExtension(record);
 if(!old)return {};
 const trackerId=storedSpellTrackerId(record),spent={...(record.resource_tracker_spent||{})};
 delete spent[trackerId];
 return {
  effect_extensions:rows(record.effect_extensions).filter(row=>
   row?.id!==storedSpellExtensionId(record)&&row?.stored_spell_feature!=='spell_storing_item'),
  resource_trackers:rows(record.resource_trackers).filter(row=>row?.id!==trackerId),
  resource_tracker_spent:spent
 };
}
