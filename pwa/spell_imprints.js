// Generic spell-imprint benefit: a trait lets its owner choose a spell and
// place it into one physical item copy, then cast it under that trait's rules.
// Spell eligibility, item type, uses, timing and duration live in the grant.
import {resolveOwnedItem,targetableInventoryItems} from './item_controls.js';
import {normalizeEffectExtension,effectExtensionsFor} from './effect_extensions.js';
import {isolateSpellBearingItem} from './spell_storing_item.js';
const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').toLowerCase().trim();
const cards=/\b(card|cards|deck|playing cards|tarot|tarokka|carte|mazzo|carta|tarocchi)\b/i;

export const spellImprintTrackerId=(record,rule)=>'spell-imprint:'+String(rule.id)+':'+String(record?.id||'');
export const spellImprintExtensionId=(record,rule)=>spellImprintTrackerId(record,rule)+':effect';
export const spellImprintActive=(extension,now=Date.now())=>
 !!extension&&(!Number.isFinite(Number(extension.expires_at))||
 Number(extension.expires_at)>now);

export function eligibleSpellImprintItems(record={},rule={}){
 return targetableInventoryItems(record,{},item=>{
  const effective=resolveOwnedItem(item);
  if(rule.item_filter==='card')return item.spell_imprint_eligible===true||
   cards.test(String(effective.name||item.name||''))||
   cards.test(String(effective.id||item.id||'').replaceAll('-',' '));
  return true;
 });
}
function classNames(record={}){
 const classes=rows(record.classes).length?rows(record.classes):
   record.class?[{name:record.class,level:record.level}]:[];
 return classes.filter(row=>Number(row.level||record.level||0)>0)
  .map(row=>norm(row.name)).filter(Boolean);
}
function timeIsAction(spell={}){
 if(rows(spell.time).length)return rows(spell.time).some(t=>
   Number(t.number)===1&&norm(t.unit)==='action');
 return /^(?:1\s*)?(?:action|azione)$/i.test(String(spell.casting_time||'').trim());
}
export function eligibleSpellImprintSpells(record={},calculated={},spells=[],rule={}){
 const classes=classNames(record);
 const ordinary=rows(calculated.spell_slots).filter(s=>Number(s.total)>0)
  .map(s=>Number(s.level));
 const pact=Number(calculated.pact_slots?.total)>0?
   Number(calculated.pact_slots.level):0;
 const maxSlot=Math.max(0,...ordinary,pact);
 return rows(spells).filter(spell=>{
  if(!spell?.id||spell.internal_grant||Number(spell.level)<1||
     Number(spell.level)>maxSlot||!timeIsAction(spell))return false;
  if(rule.spell_filter==='class_action_with_slots'){
   return rows(spell.classes).some(c=>classes.includes(norm(
    typeof c==='string'?c:c?.name)));
  }
  return true;
 }).sort((a,b)=>Number(a.level)-Number(b.level)||
  String(a.name).localeCompare(String(b.name),'it',{sensitivity:'base'}));
}
export function spellImprintExtension(record={},rule={}){
 const id=spellImprintExtensionId(record,rule);
 return rows(record.effect_extensions).find(x=>x?.id===id&&
  x.stored_spell_feature==='spell_imprint'&&x.imprint_rule_id===rule.id)||null;
}
export function spellImprintAtItem(record={},index,now=Date.now()){
 const item=rows(record.inventory)[index];
 if(!item)return null;
 return rows(record.effect_extensions).find(extension=>
  extension?.stored_spell_feature==='spell_imprint'&&
  spellImprintActive(extension,now)&&effectExtensionsFor([extension],{
   kind:'item',id:item.id,name:item.name,instance_id:item.instance_id,
   inventory_index:index}).length>0)||null;
}
export function storeSpellImprintPatch(record={},calculated={},ruleId='',index,
 spell={},description='',instanceId='',now=Date.now()){
 const rule=rows(calculated.spell_imprint_rules).find(r=>r.id===ruleId&&!r.disabled);
 if(!rule)throw Error('Il privilegio che imprime incantesimi non è disponibile.');
 if(record.origin_enabled?.[rule.origin_id]===false)
  throw Error('Il privilegio che concede la carta è disattivato.');
 if(record.spell_imprint_prepared?.[ruleId]===true)
  throw Error('Hai già scelto un incantesimo per questo privilegio: serve un nuovo riposo lungo.');
 if(!eligibleSpellImprintItems(record,rule).some(item=>item.index===index))
  throw Error('Scegli una carta o un oggetto compatibile nel tuo inventario.');
 if(!eligibleSpellImprintSpells(record,calculated,[spell],rule).length)
  throw Error('L’incantesimo non è nella lista di classe o non soddisfa tempo e livello degli slot.');
 const {inventory,item}=isolateSpellBearingItem(record,index,instanceId);
 const trackerId=spellImprintTrackerId(record,rule);
 const extension=normalizeEffectExtension({
  id:spellImprintExtensionId(record,rule),
  stored_spell_feature:'spell_imprint',imprint_rule_id:rule.id,
  origin_id:rule.origin_id,origin_name:'Tratto · '+(rule.origin_name||rule.name),
  parent_origin:rule.origin_id,
  target_kind:'item',target_id:String(item.id),target_name:String(item.name||item.id),
  target_instance_id:String(item.instance_id),operation:'grant_action',
  trigger:'on_use',frequency:'once_per_use',
  description:String(rule.description||'Incantesimo immagazzinato.')+
   ' · '+String(spell.name)+' (livello '+spell.level+').',
  spell_id:String(spell.id),spell_name:String(spell.name),spell_level:Number(spell.level),
  spell_description:String(description),tracker_id:trackerId,
  action_type:rule.cast_action_type||'action',
  prepared_at:now,expires_at:now+Number(rule.duration_hours||8)*3600000
 });
 if(!extension)throw Error('Impossibile applicare l’incantesimo alla carta.');
 return {
  inventory,
  effect_extensions:[...rows(record.effect_extensions).filter(row=>row.id!==extension.id),extension],
  resource_trackers:[...rows(record.resource_trackers).filter(row=>row.id!==trackerId),{
   id:trackerId,name:(rule.name||'Incantesimo immagazzinato')+' · '+String(item.name||item.id),
   max:Number(rule.max_uses)||1,recharge:'manual',origin_id:rule.origin_id,
   origin_name:rule.origin_name||rule.name
  }],
  resource_tracker_spent:{...(record.resource_tracker_spent||{}),[trackerId]:0},
  spell_imprint_prepared:{...(record.spell_imprint_prepared||{}),[ruleId]:true}
 };
}
export function useSpellImprintPatch(record={},calculated={},index,now=Date.now()){
 const extension=spellImprintAtItem(record,index,now);
 if(!extension)throw Error('La carta non contiene un incantesimo attivo o è scaduta.');
 const tracker=rows(calculated.trackers).find(row=>row.id===extension.tracker_id&&!row.disabled);
 if(!tracker||Number(tracker.max)-Number(tracker.spent)<1)
  throw Error('Il lancio disponibile è già stato consumato.');
 const spent={...(record.resource_tracker_spent||{})};
 delete spent[extension.tracker_id];
 return {
  effect_extensions:rows(record.effect_extensions).filter(row=>row.id!==extension.id),
  resource_trackers:rows(record.resource_trackers).filter(row=>row.id!==extension.tracker_id),
  resource_tracker_spent:spent
 };
}
export function clearSpellImprintsPatch(record={}){
 const active=rows(record.effect_extensions).filter(x=>x.stored_spell_feature==='spell_imprint');
 const ids=new Set(active.map(x=>x.tracker_id).filter(Boolean));
 const spent={...(record.resource_tracker_spent||{})};
 for(const id of ids)delete spent[id];
 return {
  effect_extensions:rows(record.effect_extensions).filter(x=>x.stored_spell_feature!=='spell_imprint'),
  resource_trackers:rows(record.resource_trackers).filter(x=>!ids.has(x.id)),
  resource_tracker_spent:spent,
  spell_imprint_prepared:{}
 };
}
