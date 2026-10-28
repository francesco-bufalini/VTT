import {SKILL_ABILITY} from './skill_definitions.js';
import {norm,same,sourceMuted,speciesOriginKey,speciesTraitOwner,flattenedSpeciesSources} from './species_origin_rules.js';
// Non-destructive 2014 racial advantages/disadvantages. A source-qualified
// 5etools trait supplies each mode. The condition_label is intentionally
// *not* inferred from game state: the player confirms it on the roll popup.
const rows=value=>Array.isArray(value)?value:[];
const muted=sourceMuted;
const signature=rule=>[norm(rule.trait),rule.target,rule.mode,rule.condition_label].join('|');
export function selectedSpeciesRollModeRules(record={},catalog={}){
 if(record.rules_version==='2024'||!record.species||!record.species_source)return [];
 const {parent,sub}=flattenedSpeciesSources(record,catalog);
 const parentKey=speciesOriginKey(record);
 const selected=[];
 if(parent)selected.push({row:parent,source_id:'race|'+norm(parent.source)+'|'+norm(parent.name),
  origin_key:parentKey,rules:rows(parent.rules)});
 if(sub){
  const inherited=new Set(rows(parent?.rules).map(signature));
  const uniques=rows(sub.rules).filter(rule=>!inherited.has(signature(rule)));
  if(uniques.length)selected.push({row:sub,
   source_id:'subrace|'+norm(record.subrace_source||sub.source)+'|'+norm(record.subrace),
   origin_key:'subrace|'+norm(record.subrace_source||sub.source)+'|'+norm(record.subrace),
   rules:uniques});
 }
 return selected;
}
function actualFeature(record,source,trait,features){
 const parent=speciesOriginKey(record);
 return speciesTraitOwner(features,trait,source.origin_key)||
  speciesTraitOwner(features,trait,parent)||
  speciesTraitOwner(features,trait,speciesOriginKey(record,true));
}
export function speciesRollModeFeatures(record={},catalog={},existing=[]){
 const output=[];
 for(const source of selectedSpeciesRollModeRules(record,catalog)){
  for(const name of new Set(source.rules.map(x=>x.trait))){
   if(!name||actualFeature(record,source,name,[...rows(existing),...output]))continue;
   const detail=rows(source.row.trait_details).find(row=>same(row.name,name));
   const key=source.origin_key+'|'+source.origin_key+'|1|'+norm(name);
   output.push({name,key,origin_id:'feature:'+key,origin_key:source.origin_key,
    level:1,source:source.row.source,entries:rows(detail?.entries),
    requirements:{scope:'character',min_level:1},bonuses:[],
    action_kind:'Capacità',synthetic_species_roll_mode:true});
  }
 }
 return output;
}
export function speciesRollModeEntries(record={},catalog={},features=[],removed=new Set()){
 const base='race|'+norm(record.species_source)+'|'+norm(record.species);
 const parent=speciesOriginKey(record);
 if(muted(record,base)||muted(record,parent))return [];
 const result=[];
 for(const source of selectedSpeciesRollModeRules(record,catalog)){
  if(muted(record,source.source_id)||muted(record,source.origin_key))continue;
  for(const rule of source.rules){
   if(!['advantage','disadvantage'].includes(rule.mode)||!rule.trait||!rule.target)continue;
   const owner=actualFeature(record,source,rule.trait,features);
   if(owner?.disabled||owner?.inactive||owner?.key&&record.trait_enabled?.[owner.key]===false||
      muted(record,owner?.origin_id))continue;
   const id='roll_mode:'+source.source_id+':'+rule.mode+':'+rule.target+
    ':'+norm(rule.trait)+':'+norm(rule.condition_label);
   if(removed.has(id))continue;
   const origin_id=owner?.origin_id||source.source_id;
   const tracker_id=rule.uses?'species-roll:'+origin_id:'';
   result.push({...rule,id,benefit_id:id,roll_mode:rule.mode,origin_id,
    origin_key:owner?.origin_key||source.origin_key,
    origin_name:owner?'Tratto · '+owner.name:'Specie · '+source.row.name,
    origin_parent_id:source.source_id,origin_parent_name:source.row.name,
    granting_trait:rule.trait,tracker_id,
    ...(tracker_id?{tracker_cost:1,strict_tracker:true}:{}),
    automatic:true,conditional:!!rule.condition_label});
  }
 }
 return result;
}
export function speciesRollModeTrackers(record={},modes=[],proficiency=2){
 const seen=new Set(),trackers=[];
 for(const rule of rows(modes)){
  if(!rule.tracker_id||seen.has(rule.tracker_id))continue;
  seen.add(rule.tracker_id);
  trackers.push({id:rule.tracker_id,name:rule.granting_trait,
   max:rule.uses==='proficiency'?Math.max(1,Math.trunc(Number(proficiency)||2)):Number(rule.uses)||1,
   recharge:rule.recharge||'long_rest',
   origin_id:rule.origin_id,origin_name:rule.origin_name,
   origin_parent_id:rule.origin_parent_id,automatic:true});
 }
 return trackers;
}
export function speciesRollModeMatches(rule,target,calculated={}){
 const expected=String(rule?.target||'');
 if(!expected||!target)return false;
 if(rule.attack_name){
  if(!target.startsWith('attack_hit:'))return false;
  const attack=rows(calculated.attacks).find(item=>'attack_hit:'+item.id===target);
  if(!attack||!norm(attack.name).includes(norm(rule.attack_name)))return false;
 }
 if(rule.requires_proficiency&&target.startsWith('skill:')){
  const key='skill:'+target.slice(6);
  if(!rows(calculated.proficiencies).some(item=>item===key||
     item==='expertise:'+target.slice(6)))return false;
 }
 if(expected===target)return true;
 if(expected==='saving_throw')return target.startsWith('save:');
 if(expected==='attack_roll')return target.startsWith('attack_hit:')||target.startsWith('casting_hit:');
 if(expected==='ability_check')return target.startsWith('skill:')||target.startsWith('ability_check:')||
  target.startsWith('ability_mod:');
 if(expected==='skill')return target.startsWith('skill:');
 if(expected.startsWith('ability_check:')){
  const ability=expected.slice('ability_check:'.length);
  return target==='ability_mod:'+ability||target==='ability_check:'+ability||
   target.startsWith('skill:')&&SKILL_ABILITY[target.slice(6)]===ability;
 }
 return false;
}
export function applicableSpeciesRollModes(record={},calculated={},target=''){
 return rows(calculated.racial_roll_modes).filter(rule=>rule.conditional&&
   speciesRollModeMatches(rule,target,calculated));
}
