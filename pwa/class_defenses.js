import {resolveOwnedItem} from './item_controls.js';
// Source-qualified class and subclass defenses for the pre-2024 (2014) rules.
// A feature must actually belong to the character. Never infer effects from prose.
// Ranks: 1 resistance, 2 damage immunity, 3 condition immunity, -1 vulnerability.
const rows = value => Array.isArray(value) ? value : [];
const norm = value => String(value ?? '').trim().toLowerCase();
const same = (a,b) => norm(a) === norm(b);
// Declarative source data is kept separate from the defense evaluator.
export {CLASS_DEFENSE_RULES} from './catalog/class_defense_rules.js';
import {CLASS_DEFENSE_RULES} from './catalog/class_defense_rules.js';


const muted = (record,id) => Boolean(id && (
 record.origin_enabled?.[id]===false ||
 rows(record.proficiency_origins).some(row=>row?.id===id&&row.disabled)
));

function hasCondition(record,name) {
 return rows(record.conditions).some(c=>same(typeof c==='string'?c:c?.id||c?.name,name));
}
function wearingHeavyArmor(record) {
 return rows(record.inventory).map(resolveOwnedItem).some(item=>{
  const slots=rows(item?.equipped_slots);
  return Number(item?.quantity??1)>0&&item.active!==false&&slots.includes('body')&&
   String(item?.type||'').split('|')[0].toUpperCase()==='HA';
 });
}
function usableRage(record) {
 return Boolean(record.active_class_features?.rage)&&!wearingHeavyArmor(record)&&
  !hasCondition(record,'unconscious');
}
function ruleMatchesFeature(rule,feature) {
 const key=norm(feature.origin_key);
 if(!key.startsWith('class|'))return false;
 const parts=key.split('|');
 if(parts[2]!==norm(rule.owner))return false;
 if(rule.class_source && parts[1]!==norm(rule.class_source))return false;
 if(![rule.feature,...rows(rule.aliases)].some(n=>same(feature.name,n)))return false;
 if(rule.subclass) {
  if(parts[3]!=='subclass'||parts[4]!==norm(rule.subclass)||
    rule.subclass_source&&parts[5]!==norm(rule.subclass_source))return false;
 } else if(parts.includes('subclass'))return false;
 return true;
}

// The same class-owned feature ID drives the choice popup and defense rules.
export function classDefenseChoices(record={},features=[]) {
 if(record.rules_version==='2024'||record.kind==='monster')return [];
 const result=[];
 for(const feature of rows(features)){
  const rule=CLASS_DEFENSE_RULES.find(row=>row.choice&&ruleMatchesFeature(row,feature));
  if(!rule||feature.disabled||feature.inactive||muted(record,feature.origin_id)||
     muted(record,feature.origin_key)||
     muted(record,feature.origin_key.split('|').slice(0,3).join('|'))||
     record.trait_enabled?.[feature.key]===false)continue;
  const options=rule.choice.options;
  const chosen=norm(record.origin_defense_choices?.[feature.origin_id]);
  const selected=options.includes(chosen)?[chosen]:[];
  result.push({id:'defense:'+feature.origin_id,
   kind:'defense',origin_id:feature.origin_id,defense_source_id:feature.origin_id,
   name:'Tratto · '+feature.name,label:rule.choice.label,
   count:1,selected,remaining:selected.length?0:1,options,
   option_labels:rule.choice.option_labels||{}});
 }
 return result;
}
export function classDefenseEntries(record={},features=[],removed=new Set()) {
 if(record.rules_version==='2024'||record.kind==='monster')return [];
 const out=[];
 for(const feature of rows(features)) {
  const rule=CLASS_DEFENSE_RULES.find(row=>ruleMatchesFeature(row,feature));
  if(!rule || feature.disabled || feature.inactive ||
     muted(record,feature.origin_id) || muted(record,feature.origin_key) ||
     record.trait_enabled?.[feature.key]===false)continue;
  const classParent=feature.origin_key.split('|').slice(0,3).join('|');
  if(muted(record,classParent))continue;
  if(rule.conscious&&(hasCondition(record,'unconscious')||
    hasCondition(record,'incapacitated')))continue;
  if(rule.active==='rage'?!usableRage(record):
     rule.active&&!record.active_class_features?.[rule.active])continue;
  const chosen=norm(record.origin_defense_choices?.[feature.origin_id]);
  const chosenValid=rule.choice?.options.includes(chosen);
  const entries=[...rule.entries];
  if(chosenValid && !rule.choice.grant_only)
   entries.push({rank:rule.choice.rank,key:chosen,condition_label:rule.choice.condition_label||''});
  if(rule.choice?.grant_only && chosen!==rule.choice.grant_only)continue;
  if(rule.choice && !chosenValid)continue;
  for(const {rank,key,condition_label,requires_heavy_armor} of entries){
   if(requires_heavy_armor&&!wearingHeavyArmor(record))continue;
   const id='defense:class:'+feature.origin_id+':'+rank+':'+key;
   if(removed.has(id))continue;
   out.push({id:'auto|'+id,benefit_id:id,rank,key,automatic:true,
    disabled:false,origin_id:feature.origin_id,
    origin_name:'Tratto · '+feature.name,origin_parent_id:feature.origin_key,
    origin_parent_name:rule.subclass||rule.owner,granting_trait:feature.name,
    ...(condition_label?{condition_label}:{})});
  }
 }
 return out;
}
