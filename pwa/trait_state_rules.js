// Generic, data-driven state privileges. Individual class/subclass effects live
// in catalog/trait_states.json; this runtime never recognizes a trait by name.
const arr = value => Array.isArray(value) ? value : [];
const norm = value => String(value ?? '').trim().toLowerCase();
const members = record => arr(record.classes).length ? record.classes : [{name:record.class,source:record.class_source,subclass:record.subclass,level:record.level}];
const enabled = (record, feature) => {
  if (!feature || feature.inactive || feature.disabled) return false;
  const ids = [feature.origin_id,feature.origin_key,String(feature.origin_key||'').split('|').slice(0,3).join('|')];
  return !ids.some(id => id && (record.origin_enabled?.[id]===false ||
    arr(record.proficiency_origins).some(row => row.id===id && row.disabled)));
};
const owningTrait = (record, features, rule) => arr(features).find(feature =>
  norm(feature.name)===norm(rule.trait) && enabled(record,feature) &&
  norm(feature.class_name||feature.requirements?.class_name||String(feature.origin_key||'').split('|')[2])===norm(rule.class_name) &&
  norm(feature.class_source||feature.requirements?.class_source||String(feature.origin_key||'').split('|')[1])===norm(rule.class_source));
function eligible(record,features,rule) {
  if (!members(record).some(m=>norm(m.name)===norm(rule.class_name) &&
    (!rule.class_source||norm(m.source)===norm(rule.class_source)) &&
    (!rule.subclass||norm(m.subclass)===norm(rule.subclass)))) return null;
  const trait=owningTrait(record,features,rule);
  if(!trait)return null;
  const requirement=rule.require_equipped;
  if(requirement&&!arr(record.inventory).some(item=>{
    const type=String(item.type||'').split('|')[0].toUpperCase();
    const kind=['LA','MA','HA'].includes(type)?'armor':type==='S'?'shield':'other';
    return Number(item.quantity??1)>0 && !item.disabled &&
      arr(item.equipped_slots).includes(requirement.slot) &&
      (!arr(requirement.kinds).length||requirement.kinds.includes(kind));
  }))return null;
  return trait;
}
function selection(record,rule) {
  if(Object.hasOwn(record.trait_state_selection||{},rule.group))
    return record.trait_state_selection[rule.group];
  const stored=record[rule.legacy_field];
  if(stored!==undefined&&stored!==null&&stored!=='')return stored===rule.legacy_value?rule.id:null;
  return rule.legacy_default?rule.id:null;
}
export function traitStateActions(record={},features=[],catalog=[]) {
  return arr(catalog).flatMap(rule=>{
    const trait=eligible(record,features,rule);
    if(!trait)return [];
    return [{id:'trait_state:'+rule.id,class_feature_id:'trait_state:'+rule.id,
      name:rule.name,origin:'personal',origin_id:trait.origin_id,feature_id:trait.origin_id,
      mode:'trait_state',state_id:rule.id,active:selection(record,rule)===rule.id,
      time:'free',type:'Capacità',cost:0,
      description:rule.summary||'',category:rule.category||'stato'}];
  });
}
export function activeTraitStates(record={},features=[],catalog=[]) {
  return arr(catalog).flatMap(rule=>{
    const trait=eligible(record,features,rule);
    return trait&&selection(record,rule)===rule.id?[{...rule,source_trait:trait}]:[];
  });
}
export function traitStateActivationPatch(record={},features=[],catalog=[],id='') {
  const rule=arr(catalog).find(row=>row.id===id);
  if(!rule||!eligible(record,features,rule))throw Error('Privilegio o armatura non disponibili.');
  const current=selection(record,rule)===rule.id;
  const active={...(record.active_class_features||{})};
  // An exclusive group changes atomically and cannot leave two states applied.
  for(const sibling of arr(catalog).filter(row=>row.group===rule.group))delete active['trait_state:'+sibling.id];
  const selected={...(record.trait_state_selection||{}),[rule.group]:current?'':rule.id};
  if(!current)active['trait_state:'+rule.id]={
    name:rule.name,origin_id:owningTrait(record,features,rule)?.origin_id||'',category:rule.category||'stato'};
  const changes={trait_state_selection:selected,active_class_features:active};
  if(rule.legacy_field)changes[rule.legacy_field]=rule.legacy_value;
  return changes;
}
function origin(features,trait,parent){
 const feature=arr(features).find(f=>norm(f.name)===norm(trait)&&
   String(f.origin_key||'')===String(parent.source_trait?.origin_key||'')&&enabled(parent.record||{},f));
 return feature?.origin_id||parent.source_trait.origin_id;
}
export function traitStateAttacks(record={},features=[],catalog=[]) {
  return activeTraitStates(record,features,catalog).flatMap(rule=>arr(rule.attacks).map(attack=>({
    id:attack.id,name:attack.name,origin_id:origin(features,attack.trait,{...rule,record}),
    source:'trait_state',proficient:true,melee:!!attack.melee,
    damage:attack.damage,damage_type:attack.damage_type,
    ability:attack.intelligence_override&&record.attack_ability==='int'?'int':attack.ability,
    range_feet:attack.range_feet,long_range_feet:attack.long_range_feet||0
  })));
}
export function traitStateNumericGrants(record={},features=[],catalog=[]) {
  return activeTraitStates(record,features,catalog).flatMap(rule=>arr(rule.numeric_grants).map(grant=>({
    id:'trait_state:'+rule.id+':'+grant.id,target:grant.target,expression:String(grant.amount),
    origin_id:origin(features,grant.trait,{...rule,record}),
    origin_name:'Tratto · '+(grant.trait||rule.trait),automatic:true
  })));
}
export function traitStateTrackers(record={},features=[],catalog=[]) {
  return activeTraitStates(record,features,catalog).flatMap(rule=>arr(rule.attacks).flatMap(attack=>
    attack.bonus_die?[{
      id:attack.bonus_die.tracker_id,name:attack.bonus_die.name,
      max:attack.bonus_die.max||1,recharge:attack.bonus_die.recharge||'turn',
      automatic:true,origin_id:origin(features,attack.trait,{...rule,record}),
      origin_name:'Tratto · '+(attack.trait||rule.trait)
    }]:[]));
}
export function traitStateOptionalDice(record={},features=[],catalog=[]) {
  return activeTraitStates(record,features,catalog).flatMap(rule=>arr(rule.attacks).flatMap(attack=>
    attack.bonus_die?[{
      ...attack.bonus_die,attack_id:attack.id,origin_id:origin(features,attack.trait,{...rule,record}),
      origin_name:attack.trait||rule.name,tracker_cost:1
    }]:[]));
}
export function traitStateEffects(record={},features=[],catalog=[]) {
  return activeTraitStates(record,features,catalog).map(rule=>({
    key:'trait_state:'+rule.id,name:rule.name,origin_id:rule.source_trait.origin_id,
    category:rule.category||'stato',effective:true,summary:rule.summary||''
  }));
}
