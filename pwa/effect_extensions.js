import {activeInfusions,targetableInventoryItems,resolveOwnedItem,requiresAttunement,itemAttunementCount} from './item_controls.js';
// Typed extensions to spells, magical abilities and infused inventory items. All effects originate from
// explicit catalog rules or trait-owned records: never parse feature prose.
const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').trim().toLowerCase();
export const EXTENSION_TARGETS=[['spell','Incantesimo'],['ability','Capacità magica'],['item','Oggetto']];
export const EXTENSION_OPERATIONS=[
 ['set_range','Imposta gittata (ft)'],['bonus_damage','Danni aggiuntivi'],
 ['attack_bonus','Bonus al tiro per colpire'],['damage_bonus','Bonus ai danni'],
 ['push','Spinge (ft)'],['pull','Attira (ft)'],['reduce_speed','Riduce velocità (ft)'],
 ['roll_twice','Tira due volte, usa il migliore'],['area_damage','Danni ad area'],
 ['temporary_hp','Punti ferita temporanei'],['add_effect','Effetto aggiuntivo'],
 ['grant_property','Proprietà aggiuntiva'],['grant_action','Azione concessa'],
 ['resistance','Resistenza a un danno'],['roll_mode','Modalità del tiro']
];
export const EXTENSION_TRIGGERS=[
 ['passive','Sempre'],['on_hit','Quando colpisce'],
 ['ability_check','Prova di caratteristica'],['attack_roll','Tiro per colpire'],
 ['saving_throw','Tiro salvezza'],['reaction','Reazione'],['on_throw','Quando viene lanciato'],
 ['initiative','Iniziativa'],['on_use','Quando viene usato'],['concentration_fail','Concentrazione fallita']
];
export const EXTENSION_FREQUENCIES=[
 ['each','Ogni applicazione'],['once_per_turn','Una volta per turno'],
 ['once_per_use','Una volta per utilizzo']
];
const known=(options,value)=>options.some(([id])=>id===value);
const enabled=(record,row)=>{
 if(row.disabled||record.trait_enabled?.[row.trait_key]===false)return false;
 for(const id of [row.origin_id,row.parent_origin]){
  if(id&&(record.origin_enabled?.[id]===false||
    rows(record.proficiency_origins).some(x=>x?.id===id&&x.disabled)))return false;
 }
 return true;
};
const classMembers=record=>rows(record.classes).length?rows(record.classes):
 record.class?[{name:record.class,source:record.class_source,level:record.level,subclass:record.subclass}]:[];
const shortSubclass=value=>norm(value).replace(/^(?:college of |the )/,'');
function catalogOwner(record,features,rule){
 const owner=rule.owner||{},members=classMembers(record);
 if(owner.class_name&&!members.some(c=>norm(c.name)===norm(owner.class_name)&&
   Number(c.level||0)>=Number(owner.min_level||1)&&
   (!owner.subclass||shortSubclass(c.subclass||record.subclass)===shortSubclass(owner.subclass))))return null;
 if(owner.kind==='optional_feature'){
  const match=rows(record.optional_features_catalog).find(row=>norm(row.name)===norm(owner.name)&&
   (!owner.source||!row.source||norm(row.source)===norm(owner.source))&&!row.disabled);
  if(!match)return null;
  const origin_id=match.origin_id||'optional|'+norm(match.source||owner.source)+'|'+norm(match.name);
  const trait_key=origin_id+'|0|'+norm(match.name);
  return enabled(record,{origin_id,trait_key})?
   {origin_id,trait_key,origin_name:match.name,parent_origin:''}:null;
 }
 if(owner.kind==='feature'){
  const match=rows(features).find(f=>norm(f.name)===norm(owner.name)&&
   !f.disabled&&!f.inactive&&(!owner.class_name||
    norm(f.requirements?.class_name||f.class_name||String(f.origin_key||'').split('|')[2])===norm(owner.class_name))&&
   (!owner.subclass||String(f.origin_key||'').includes('|subclass|')&&
     shortSubclass(String(f.origin_key).split('|subclass|')[1].split('|')[0])===shortSubclass(owner.subclass)));
  if(!match)return null;
  return enabled(record,{origin_id:match.origin_id,parent_origin:match.origin_key})?
    {origin_id:match.origin_id,parent_origin:match.origin_key,origin_name:match.name}:null;
 }
 return null;
}
export function normalizeEffectExtension(row={}){
 const target_kind=norm(row.target_kind),operation=norm(row.operation),
  trigger=norm(row.trigger||'passive'),frequency=norm(row.frequency||'each');
 if(!known(EXTENSION_TARGETS,target_kind)||!known(EXTENSION_OPERATIONS,operation)||
    !known(EXTENSION_TRIGGERS,trigger)||!known(EXTENSION_FREQUENCIES,frequency)||
    !String(row.target_name||row.target_id||'').trim())return null;
 const value=String(row.value??'').trim();
 if(['attack_bonus','damage_bonus'].includes(operation)){
  if(!/^[+-]?\d{1,3}$/.test(value))return null;
 }else if(['set_range','push','pull','reduce_speed'].includes(operation)){
  if(!/^[1-9]\d{0,3}$/.test(value))return null;
 }else if(['bonus_damage','temporary_hp','area_damage'].includes(operation)){
  if(!/^[a-z0-9_+*(). -]{1,120}$/i.test(value))return null;
 }else if(['add_effect','grant_action','grant_property'].includes(operation)&&
   !String(row.description||value||'').trim())return null;
 if(operation==='resistance'&&!/^(acid|bludgeoning|cold|fire|force|lightning|necrotic|piercing|poison|psychic|radiant|slashing|thunder)$/i.test(value))return null;
 if(operation==='roll_mode'&&!['advantage','disadvantage'].includes(value))return null;
 return {...row,target_kind,operation,trigger,frequency,value,
  target_name:String(row.target_name||'').trim(),target_id:String(row.target_id||'').trim(),
  target_instance_id:String(row.target_instance_id||'').trim(),
  target_aliases:rows(row.target_aliases).filter(x=>typeof x==='string'),
  description:String(row.description||'').trim()};
}
export function collectEffectExtensions(record={},catalog=[],features=[],infusionDefinitions=[]){
 const result=[];
 const excluded=new Set(Object.values(record.trait_benefit_removed||{}).flatMap(rows));
 for(const rule of rows(catalog)){
  if(rule.rules_version&&String(record.rules_version||'2014')!==String(rule.rules_version))continue;
  if(['infusion','spell_cast'].includes(rule.owner?.kind))continue;
  const owner=catalogOwner(record,features,rule);
  if(!owner)continue;
  const row=normalizeEffectExtension({...rule,...owner});
  if(row&&!excluded.has('effect_extension:'+row.id))result.push(row);
 }
 // Each infusion targets exactly its physical inventory copy. Ordinary numeric
 // infusion grants remain in infusionNumericBonuses: do not stack them twice.
 for(const active of activeInfusions(record,infusionDefinitions,features)){
  const {item,infusion,definition,index}=active;
  for(const rule of rows(catalog)){
   if(rule.owner?.kind!=='infusion'||rule.target_kind!=='item'||
      rule.rules_version&&String(rule.rules_version)!==String(record.rules_version||'2014')||
      rule.owner.id&&rule.owner.id!==definition.id||
      rule.owner.name&&norm(rule.owner.name)!==norm(definition.name))continue;
   const choiceKey=String(rule.value_from_item_choice||'');
   const value=choiceKey?infusion.effect_choice?.[choiceKey]:rule.value;
   if(choiceKey&&!value)continue;
   const parent=rows(record.optional_features_catalog).find(row=>row.id===definition.id);
   const origin_id=active.id,id=String(rule.id)+'|'+origin_id;
   const row=normalizeEffectExtension({...rule,id,origin_id,
    parent_origin:parent?.origin_id||'optional|'+norm(definition.source)+'|'+norm(definition.name),
    origin_name:'Infusione · '+definition.name,
    target_name:item.name||item.id,target_id:item.id,
    target_instance_id:item.instance_id||'',target_inventory_index:index,value});
   if(row&&!excluded.has('effect_extension:'+id)&&enabled(record,row))result.push(row);
  }
 }
 // Temporary spell effects are tied to an individual item instance and cast.
 // Once the concentration condition or spell identity changes they no longer
 // project, even if a stale saved row survives a host synchronization.
 for(const active of rows(record.active_item_spell_effects)){
  if(active.requires_concentration&&(!rows(record.conditions).includes('concentrating')||
    String(record.concentrating_spell_id||'')!==String(active.spell_id||'')))continue;
  const index=rows(record.inventory).findIndex(item=>item&&
    String(item.instance_id||'')===String(active.target_instance_id||'')&&
    String(item.id||'')===String(active.item_id||'')&&Number(item.quantity??1)>0);
  if(index<0)continue;
  const item=record.inventory[index];
  for(const rule of rows(active.effects)){
   const id=String(active.id)+'|'+String(rule.id);
   const row=normalizeEffectExtension({...rule,id,origin_id:'spell_cast:'+active.id,
    origin_name:'Incantesimo · '+active.spell_name,
    cast_id:active.id,source_spell_id:active.spell_id,
    target_kind:'item',target_name:item.name||item.id,target_id:item.id,
    target_instance_id:item.instance_id,target_inventory_index:index});
   if(row&&!excluded.has('effect_extension:'+id))result.push(row);
  }
 }
 for(const raw of rows(record.effect_extensions)){
  const row=normalizeEffectExtension(raw);
  if(row&&enabled(record,row)&&!excluded.has('effect_extension:'+row.id))result.push(row);
 }
 return result;
}
export function effectExtensionsFor(extensions=[],target={}){
 const kind=norm(target.kind||target.target_kind),id=norm(target.id),name=norm(target.name);
 return rows(extensions).filter(row=>{
  if(row.target_kind!==kind)return false;
  if(kind==='item'){
   // An infused copy must not confer its effects on another identical item.
   if(row.target_inventory_index!==undefined&&row.target_inventory_index!==null)
    return Number(target.inventory_index)===Number(row.target_inventory_index)&&
     norm(row.target_id)===id;
   if(row.target_instance_id)return norm(target.instance_id)===norm(row.target_instance_id);
   if(row.target_id)return norm(row.target_id)===id;
  }
  return Boolean(row.target_id&&id&&norm(row.target_id)===id||
   name&&[row.target_name,...rows(row.target_aliases)].some(alias=>norm(alias)===name));
 });
}
// Project effects onto the actual equipped attack; never enchant a different
// copy of the same catalog weapon, including the corresponding thrown attack.
export function applyItemAttackExtensions(record={},attacks=[],extensions=[]){
 return rows(attacks).map(attack=>{
  if(!String(attack.id||'').startsWith('item:')||!Number.isSafeInteger(attack.inventory_index)||
    attack.inventory_index<0)return attack;
  const item=rows(record.inventory)[attack.inventory_index];
  if(!item)return attack;
  const active=effectExtensionsFor(extensions,{kind:'item',id:item.id,name:item.name,
    instance_id:item.instance_id,inventory_index:attack.inventory_index})
    .filter(effect=>['passive','on_hit','attack_roll'].includes(effect.trigger));
  let hit=0,damageBonus=0;
  const hitSources=[],extra=[];
  for(const effect of active){
   if(effect.operation==='attack_bonus'){
    hit+=Number(effect.value)||0;
    hitSources.push({id:effect.id,value:Number(effect.value)||0,
      cast_id:effect.cast_id||'',origin_name:effect.origin_name});
   }
   if(effect.operation==='damage_bonus')damageBonus+=Number(effect.value)||0;
   if(effect.operation==='bonus_damage'&&/^([1-9]\d{0,1})d(4|6|8|10|12|20|100)([+-]\d+)?$/i.test(effect.value))
    extra.push({dice:effect.value,damage_type:effect.damage_type||'',
      origin_name:effect.origin_name,cast_id:effect.cast_id||''});
  }
  if(!hit&&!damageBonus&&!extra.length)return attack;
  const sign=value=>value>0?' + '+value:value<0?' − '+Math.abs(value):'';
  const damage=String(attack.damage||'')+sign(damageBonus);
  return {...attack,hit:Number(attack.hit)+hit,damage,
   damage_extra_modifier:Number(attack.damage_extra_modifier||0)+damageBonus,
   damage_extras:extra,enchantment_hit_bonuses:hitSources,
   damage_roll_formula:damage+extra.map(row=>' + '+row.dice).join(''),
   damage_explanation:[attack.damage_explanation||'',
    ...(hit?['Incantesimo: colpire '+sign(hit).trim()]:[]),
    ...(damageBonus?['Incantesimo: danni '+sign(damageBonus).trim()]:[])]
    .filter(Boolean).join(' · ')};
 });
}
const expressionValue=(expr,variables={})=>{
 const value=String(expr||'').replace(/\s+/g,'');
 if(/^[+-]?\d+(?:\.\d+)?$/.test(value))return Number(value);
 // Expressions are not evaluated as JavaScript; unknown dice/symbols stay
 // symbolic for the UI/roller rather than inventing a numerical result.
 const pieces=value.match(/^([a-z_][a-z\d_]*)([+-]\d+)?$/i);
 if(pieces&&Number.isFinite(Number(variables[pieces[1]])))
  return Number(variables[pieces[1]])+Number(pieces[2]||0);
 return null;
};
export function applyEffectExtensions(effect={},extensions=[],target={},variables={}){
 const matches=effectExtensionsFor(extensions,target);
 let range=Number(effect.range_feet);
 const additions=[];
 for(const row of matches){
  const numeric=expressionValue(row.value,variables);
  if(row.operation==='set_range'&&numeric!==null)range=numeric;
  else additions.push({...row,resolved_value:numeric});
 }
 const nativeRange=Number.isFinite(range)&&matches.some(row=>row.operation==='set_range')?
  (effect.range&&typeof effect.range==='object'&&effect.range.distance?
    {...effect.range,distance:{...effect.range.distance,amount:range,type:'feet'}}:
    typeof effect.range==='string'?range+' ft':effect.range):effect.range;
 return {...effect,...(Number.isFinite(range)?{range_feet:range}:{}),range:nativeRange,
  effect_extensions:matches,
  extended_effects:additions};
}
export function effectExtensionLabel(row,variables={}){
 const labels={set_range:'Gittata',bonus_damage:'Danni aggiuntivi',
  attack_bonus:'Bonus al tiro per colpire',damage_bonus:'Bonus ai danni',
  push:'Spinta',pull:'Attrazione',reduce_speed:'Velocità ridotta',
  roll_twice:'Ripeti il dado (tieni il migliore)',area_damage:'Danni ad area',
  temporary_hp:'PF temporanei',add_effect:'Effetto aggiuntivo',
  grant_property:'Proprietà aggiuntiva',grant_action:'Azione concessa',
  resistance:'Resistenza',roll_mode:'Modalità del tiro'};
 const times={passive:'',on_hit:'Al colpo',ability_check:'Prova di caratteristica',
  attack_roll:'Tiro per colpire',saving_throw:'Tiro salvezza',reaction:'Reazione',
  on_throw:'Al lancio',initiative:'Iniziativa',on_use:'All’uso',concentration_fail:'Concentrazione fallita'};
 const value=expressionValue(row.value,variables);
 const suffix=row.operation==='roll_twice'?'':row.operation==='add_effect'?'':row.value?
  ' · '+(value===null?row.value:value)+
   (['set_range','push','pull','reduce_speed'].includes(row.operation)?' ft':'')+
   (row.damage_type?' '+row.damage_type:''):'';
 return [labels[row.operation]||row.operation,suffix,
   times[row.trigger]?' · '+times[row.trigger]:'',
   row.frequency==='once_per_turn'?' · 1/turno':row.frequency==='once_per_use'?' · 1/uso':'',
   row.description?' · '+row.description:''].join('');
}

// Spell-origin item enchantments share this served module with infusion extensions.
// Generic cast-time item enchantments. The spell or catalog supplies typed rules;
// an individual inventory instance receives the temporary effect, never an item ID globally.


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
