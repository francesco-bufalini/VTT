// Generic cast-time item enchantments. The spell or catalog supplies typed rules;
// an individual inventory instance receives the temporary effect, never an item ID globally.
import {targetableInventoryItems,resolveOwnedItem,requiresAttunement,itemAttunementCount} from './item_controls.js';
const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').trim().toLowerCase();

export function spellItemRules(catalog=[],spell={},rulesVersion='2014'){
 const published=rows(catalog).filter(rule=>{
  const owner=rule?.owner||{};
  if(owner.kind!=='spell_cast'||rule.target_kind!=='item')return false;
  if(rule.rules_version&&String(rule.rules_version)!==String(rulesVersion))return false;
  if(owner.id&&norm(owner.id)===norm(spell.id))return true;
  if(![owner.name,...rows(owner.aliases)].some(name=>name&&norm(name)===norm(spell.name)))return false;
  return !owner.source||!spell.source||norm(owner.source)===norm(spell.source);
 });
 return [...published,...rows(spell.item_effect_extensions).map((rule,i)=>({
  ...rule,id:rule.id||'homebrew-item-effect-'+i,target_kind:'item',
  owner:{kind:'spell_cast',id:spell.id},
  item_selector:rule.item_selector||spell.item_target_selector||spell.target_item_selector||null
 }))];
}
export function spellItemTargetSelector(spell={},rules=[]){
 return spell.item_target_selector||spell.target_item_selector||
  rows(rules).find(rule=>rule.item_selector)?.item_selector||null;
}
export function spellItemDamageTypes(rules=[]){
 return [...new Set(rows(rules).flatMap(rule=>rows(rule.damage_type_choices)))];
}
function valueAtSlot(rule,slotLevel){
 const byLevel=rule.value_by_slot;
 if(!byLevel||typeof byLevel!=='object')return rule.value;
 const levels=Object.keys(byLevel).map(Number)
  .filter(level=>Number.isSafeInteger(level)&&level<=slotLevel).sort((a,b)=>b-a);
 return levels.length?byLevel[levels[0]]:rule.value;
}
export function itemSpellCastPatch(record={},selection={},spell={},rules=[],slotLevel=0,ids={}){
 if(!rows(rules).length)return {};
 const target=selection.item_target;
 if(!target||!Number.isSafeInteger(target.inventory_index)||target.inventory_index<0)
  throw Error('Seleziona un oggetto da incantare.');
 const matched=targetableInventoryItems(record,spellItemTargetSelector(spell,rules)||{});
 const choice=matched.find(row=>row.index===target.inventory_index&&
  String(row.item.id||'')===String(target.item_id||'')&&
  (!target.instance_id||String(row.item.instance_id||'')===String(target.instance_id)));
 if(!choice)throw Error('L’oggetto non è più un bersaglio valido.');
 const allowed=spellItemDamageTypes(rules);
 const damageType=String(selection.item_damage_type||'');
 if(allowed.length&&!allowed.includes(damageType))
  throw Error('Scegli un tipo di danno valido per l’incantesimo.');
 const quantity=Number(choice.item.quantity??1);
 if(!Number.isSafeInteger(quantity)||quantity<1)throw Error('Quantità dell’oggetto non valida.');
 const uuid=()=>globalThis.crypto.randomUUID();
 const inventory=structuredClone(rows(record.inventory));
 const chosen=inventory[target.inventory_index];
 chosen.instance_id=chosen.instance_id||ids.instanceId||'pwa_instance_'+uuid();
 chosen.standalone_instance=true;
 if(quantity>1){
  const other=structuredClone(chosen);
  chosen.quantity=1;other.quantity=quantity-1;
  other.instance_id=ids.otherInstanceId||'pwa_instance_'+uuid();
  other.standalone_instance=false;other.equipped=false;other.equipped_slots=[];
  if(requiresAttunement(resolveOwnedItem(chosen))){
   const attuned=itemAttunementCount(chosen);
   chosen.attuned_count=Math.min(1,attuned);chosen.attuned=chosen.attuned_count>0;
   other.attuned_count=Math.max(0,attuned-1);other.attuned=other.attuned_count>0;
  }
  inventory.splice(target.inventory_index+1,0,other);
 }
 const effects=rows(rules).map((rule,i)=>({
  id:String(rule.id||i),target_kind:'item',
  operation:rule.operation,trigger:rule.trigger||'passive',frequency:rule.frequency||'each',
  value:String(valueAtSlot(rule,slotLevel)??''),
  damage_type:rule.value_from_cast_choice==='damage_type'?damageType:String(rule.damage_type||''),
  description:rule.description||''
 }));
 const concentration=spell.requires_concentration===true||rules.some(rule=>rule.concentration===true)||
  rows(spell.duration).some(row=>row?.concentration===true)||
  (typeof spell.duration==='string'&&/concentration|concentrazione/i.test(spell.duration));
 const castId=ids.castId||'item_spell_'+uuid();
 const recordEffect={id:castId,spell_id:String(spell.id||selection.id||''),
  spell_name:String(spell.name||selection.name||spell.id||'Incantesimo'),
  item_id:String(chosen.id),target_instance_id:String(chosen.instance_id),
  source_caster_id:String(record.id||''),requires_concentration:concentration,
  duration:spell.duration||null,slot_level:slotLevel,effects};
 const active=rows(record.active_item_spell_effects)
  .filter(row=>!concentration||!row.requires_concentration);
 return {inventory,active_item_spell_effects:[...active,recordEffect],
  ...(concentration?{conditions:[...new Set([...rows(record.conditions),'concentrating'])],
    concentrating_spell_id:recordEffect.spell_id}:{})};
}
export function endItemSpellPatch(record={},castId=''){
 if(!rows(record.active_item_spell_effects).some(row=>row.id===castId))
  throw Error('Effetto non più attivo.');
 return {active_item_spell_effects:rows(record.active_item_spell_effects).filter(row=>row.id!==castId)};
}
export function concentrationItemSpellEndPatch(record={},spellId=null){
 return {active_item_spell_effects:rows(record.active_item_spell_effects).filter(row=>
  !row.requires_concentration||(spellId!==null&&row.spell_id!==spellId))};
}
