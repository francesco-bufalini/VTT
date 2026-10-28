// Generic, data-driven state privileges. Individual class/subclass effects live
// in catalog/trait_states.json; this runtime never recognizes a trait by name.
import {resolveOwnedItem} from './item_controls.js';
const arr = value => Array.isArray(value) ? value : [];
const norm = value => String(value ?? '').trim().toLowerCase();
const members = record => (arr(record.classes).length ? record.classes : [{name:record.class,source:record.class_source,subclass:record.subclass,level:record.level}]).map(member=>({...member,source:member.source||record.class_source||'TCE',subclass:member.subclass||(norm(member.name)===norm(record.class)?record.subclass:'')}));
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
  if(requirement&&!arr(record.inventory).some(saved=>{
    const item=resolveOwnedItem(saved);
    const type=String(item.type||'').split('|')[0].toUpperCase();
    const kind=['LA','MA','HA'].includes(type)?'armor':type==='S'?'shield':'other';
    return Number(saved.quantity??1)>0 && !saved.disabled &&
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
// Rest-gated power choices are not trackers. The source rules supply the
// recovery event and the same group identity used by trait-state exclusivity.
export const selectionRestLabel = event=>event==='short_rest'?'Riposo breve':
  event==='long_rest'?'Riposo lungo':'Nessun riposo';
export function powerRestSelections(record={},calculated={}){
 const rows=[],seen=new Set(),add=(id,name,recovery)=>{
   if(!id||!['short_rest','long_rest'].includes(recovery)||seen.has(id))return;
   seen.add(id);rows.push({id,name,recovery,label:selectionRestLabel(recovery)});
 };
 for(const rule of arr(calculated.trait_state_catalog)){
   if(!rule.selection_recovery||!rule.group)continue;
   // Eligibility for choices is based on the feature and subclass, even
   // when equipment is temporarily absent during a rest.
   const matching={...rule};delete matching.require_equipped;
   if(eligible(record,calculated.features||[],matching))
     add(rule.group,rule.trait||rule.name,rule.selection_recovery);
 }
 for(const choice of arr(calculated.racial_rest_choices))
   if(arr(calculated.features).some(f=>f.origin_id===choice.origin_id&&enabled(record,f)))
     add(choice.group,choice.trait,choice.recovery);
 for(const member of arr(calculated.casting_classes))
   if(member.mode==='Preparati')
     add('spells:'+String(member.id),String(member.name||'Incantesimi')+' · preparazione','long_rest');
 if(arr(calculated.infusion_catalog).length&&
   (arr(record.optional_features_catalog).some(x=>String(x?.id||'').startsWith('infusion|'))||
    arr(calculated.features).some(x=>norm(x.name)==='infuse item'&&!x.disabled&&!x.inactive)))
   add('infusions','Infusioni · oggetti applicati','long_rest');
 return rows;
}
export function powerRestChoicePatch(record={},event='',calculated={}){
 if(!['short_rest','long_rest'].includes(event))return {};
 const groups=powerRestSelections(record,calculated).filter(row=>
   row.recovery===event||(event==='long_rest'&&row.recovery==='short_rest'));
 if(!groups.length)return {};
 const ready={...(record.rest_selection_available||{})};
 for(const group of groups)ready[group.id]=true;
 const expired=new Set(arr(calculated.racial_rest_choices)
   .filter(choice=>choice.kind==='training'&&groups.some(row=>row.id===choice.group))
   .map(choice=>choice.group));
 // Training grants expire after the next eligible rest; never silently
 // retain proficiencies from a previous trance after their expiry.
 return {rest_selection_available:ready,
   ...(expired.size?{proficiency_choices:arr(record.proficiency_choices).filter(row=>
     !expired.has(row?.rest_training_group))}:{})};
}
export function canReselectPower(record={},group='',legacyField=''){
 if(record.rest_selection_available?.[group]===true)return true;
 // A character creating its first choice has no rest to wait for.
 return !Object.hasOwn(record.trait_state_selection||{},group)&&
   (!legacyField||!record[legacyField]);
}

export function traitStateActions(record={},features=[],catalog=[]) {
  return arr(catalog).flatMap(rule=>{
    const trait=eligible(record,features,rule);
    if(!trait)return [];
    return [{id:'trait_state:'+rule.id,class_feature_id:'trait_state:'+rule.id,
      name:rule.name,origin:'personal',origin_id:trait.origin_id,feature_id:trait.origin_id,
      mode:'trait_state',state_id:rule.id,active:selection(record,rule)===rule.id,
      time:'free',type:'Capacità',
       tracker_id:rule.activation_tracker?.id||'',tracker:rule.activation_tracker?.name||'',
       cost:selection(record,rule)===rule.id?0:Math.max(0,Number(rule.activation_tracker?.cost||0)),
       description:rule.summary||'',category:rule.category||'stato'}];
  });
}
export function activeTraitStates(record={},features=[],catalog=[]) {
  return arr(catalog).flatMap(rule=>{
    const trait=eligible(record,features,rule);
    return trait&&selection(record,rule)===rule.id?[{...rule,source_trait:trait}]:[];
  });
}
export function traitStateActivationPatch(record={},features=[],catalog=[],id='',trackers=[],options={}) {
  const rule=arr(catalog).find(row=>row.id===id);
  if(!rule||!eligible(record,features,rule))throw Error('Privilegio o armatura non disponibili.');
  const current=selection(record,rule)===rule.id;
  const rest=rule.selection_recovery||'';
  if(rest&&!canReselectPower(record,rule.group,rule.legacy_field))
    throw Error('Puoi riselezionare il modello dopo un '+selectionRestLabel(rest).toLowerCase()+'.');
  const active={...(record.active_class_features||{})};
  // An exclusive group changes atomically and cannot leave two states applied.
  for(const sibling of arr(catalog).filter(row=>row.group===rule.group))delete active['trait_state:'+sibling.id];
  const selected={...(record.trait_state_selection||{}),[rule.group]:current?'':rule.id};
  if(!current)active['trait_state:'+rule.id]={
    name:rule.name,origin_id:owningTrait(record,features,rule)?.origin_id||'',category:rule.category||'stato'};
  const changes={trait_state_selection:selected,active_class_features:active};
  if(rest)changes.rest_selection_available={...(record.rest_selection_available||{}),[rule.group]:false};
  // This cost is bound to the originating trait and only paid on activation.
  // Deselecting an active state is free, and payment is atomic with selection.
  const payment=rule.activation_tracker;
  if(!current&&payment&&Number(payment.cost)>0){
    const chosen=options.tracker_id===undefined?payment.id:String(options.tracker_id);
    if(chosen!==''&&chosen!==payment.id)throw Error('Tracker non collegato alla capacità.');
    if(chosen){
      const tracker=arr(trackers).find(row=>row.id===payment.id&&!row.disabled);
      if(!tracker)throw Error('Tracker della capacità non disponibile.');
      const cost=Math.max(0,Number(payment.cost));
      const spent=Number(record.resource_tracker_spent?.[tracker.id]||0);
      if(spent+cost>Number(tracker.max||0))throw Error('Utilizzi insufficienti per attivare il modello.');
      changes.resource_tracker_spent={...(record.resource_tracker_spent||{}),[tracker.id]:spent+cost};
    }
  }
  if(rule.legacy_field)changes[rule.legacy_field]=rule.legacy_value;
  return changes;
}
// A state is not a substitute for a missing or disabled child trait.
function source(record,features,rule,name){
 if(!name||norm(name)===norm(rule.source_trait.name))return rule.source_trait;
 return arr(features).find(feature=>norm(feature.name)===norm(name)&&
   String(feature.origin_key||'')===String(rule.source_trait.origin_key||'')&&
   enabled(record,feature))||null;
}
export function traitStateAttacks(record={},features=[],catalog=[]) {
 return activeTraitStates(record,features,catalog).flatMap(rule=>arr(rule.attacks).flatMap(attack=>{
   const feature=source(record,features,rule,attack.trait);
   return feature?[{
     id:attack.id,name:attack.name,origin_id:feature.origin_id,
     source:'trait_state',proficient:true,melee:!!attack.melee,
     damage:attack.damage,damage_type:attack.damage_type,
     ability:attack.intelligence_override&&record.attack_ability==='int'?'int':attack.ability,
     range_feet:attack.range_feet,long_range_feet:attack.long_range_feet||0,
     on_hit_effects:arr(attack.on_hit_effects).map(effect=>({...effect})),
     description:arr(attack.on_hit_effects).map(effect=>effect.description).filter(Boolean).join(' · ')
   }]:[];
 }));
}
export function traitStateNumericGrants(record={},features=[],catalog=[]) {
 return activeTraitStates(record,features,catalog).flatMap(rule=>arr(rule.numeric_grants).flatMap(grant=>{
   const feature=source(record,features,rule,grant.trait);
   return feature?[{
     id:'trait_state:'+rule.id+':'+grant.id,target:grant.target,expression:String(grant.amount),
     origin_id:feature.origin_id,origin_name:'Tratto · '+feature.name,automatic:true
   }]:[];
 }));
}
export function traitStateRollModes(record={},features=[],catalog=[]){
 return activeTraitStates(record,features,catalog).flatMap(rule=>arr(rule.roll_modes).flatMap(mode=>{
  const feature=source(record,features,rule,mode.trait);
  return feature&&['advantage','disadvantage'].includes(mode.mode)&&mode.target?[{
   ...mode,origin_id:feature.origin_id,origin_name:'Tratto · '+feature.name,
   state_id:rule.id
  }]:[];
 }));
}
export function traitStateTrackers(record={},features=[],catalog=[]) {
  // Payment trackers must exist while the model is inactive; sibling modes
  // share one counter rather than each receiving an independent pool.
  const available=[],seen=new Set();
  for(const rule of arr(catalog)){
    const payment=rule.activation_tracker,feature=payment&&eligible(record,features,rule);
    if(!feature||!payment?.id||seen.has(payment.id))continue;
    seen.add(payment.id);
    available.push({id:payment.id,name:payment.name,max:Math.max(0,Number(payment.max)||0),
      recharge:payment.recharge||'manual',automatic:true,
      origin_id:feature.origin_id,origin_name:'Tratto · '+feature.name});
  }
  return [...available,...activeTraitStates(record,features,catalog).flatMap(rule=>arr(rule.attacks).flatMap(attack=>{
   const feature=source(record,features,rule,attack.trait),bonus=attack.bonus_die;
   return feature&&bonus?[{
     id:bonus.tracker_id,name:bonus.name,max:bonus.max||1,recharge:bonus.recharge||'turn',
     automatic:true,origin_id:feature.origin_id,origin_name:'Tratto · '+feature.name
   }]:[];
  }))];
}
export function traitStateOptionalDice(record={},features=[],catalog=[]) {
 return activeTraitStates(record,features,catalog).flatMap(rule=>arr(rule.attacks).flatMap(attack=>{
   const feature=source(record,features,rule,attack.trait),bonus=attack.bonus_die;
   return feature&&bonus?[{
     ...bonus,attack_id:attack.id,origin_id:feature.origin_id,
     origin_name:feature.name,tracker_cost:1
   }]:[];
 }));
}
export function traitStateEffects(record={},features=[],catalog=[]) {
  return activeTraitStates(record,features,catalog).map(rule=>({
    key:'trait_state:'+rule.id,name:rule.name,origin_id:rule.source_trait.origin_id,
    category:rule.category||'stato',effective:true,summary:rule.summary||''
  }));
}
