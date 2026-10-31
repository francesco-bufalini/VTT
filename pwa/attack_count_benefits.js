// Attack count is a trait benefit, not a bonus to a roll or an extra action.
// Multiple grants never stack: the Attack action uses the highest active count.
import {featureEnabled} from './feature_mechanics.js';
import {removedBenefitIds} from './trait_benefit_editor.js';
import {normalizeMonsterStatBlock} from './character_core.js';

const rows=value=>Array.isArray(value)?value:[];
const count=value=>{
 const n=Number(value);
 return Number.isSafeInteger(n)&&n>=2&&n<=99?n:0;
};
const sourceEnabled=(record,id)=>!id||record.origin_enabled?.[id]!==false&&
 !rows(record.proficiency_origins).some(row=>row?.id===id&&row.disabled===true);

export function attackCountBenefits(record={},features=[]){
 const suppressed=removedBenefitIds(record),benefits=[];
 const add=(id,source,name,value,automatic=false)=>{
  const amount=count(value);
  if(!amount||suppressed.has('attack_count:'+id))return;
  benefits.push({id,origin_id:source,origin_name:name,
   attacks_per_action:amount,automatic});
 };
 for(const feature of rows(features)){
  if(!featureEnabled(record,feature)||record.trait_enabled?.[feature.key]===false||
    !sourceEnabled(record,feature.origin_id))continue;
  const owner=String(feature.origin_key||'');
  if(!sourceEnabled(record,owner)||!sourceEnabled(record,owner.split('|subclass|')[0]))continue;
  add('feature:'+feature.origin_id,feature.origin_id,'Tratto · '+feature.name,
   feature.attacks_per_action,true);
 }
 for(const grant of rows(record.attack_count_grants)){
  if(!grant||grant.disabled||record.trait_enabled?.[grant.trait_key]===false||
    !sourceEnabled(record,grant.origin_id)||!sourceEnabled(record,grant.parent_origin))continue;
  // A custom grant on a class trait inherits the status of its owning feature.
  const parent=rows(features).find(feature=>feature.origin_id===grant.parent_origin);
  if(parent&&(!featureEnabled(record,parent)||record.trait_enabled?.[parent.key]===false||
    !sourceEnabled(record,parent.origin_key)||
    !sourceEnabled(record,String(parent.origin_key).split('|subclass|')[0])))continue;
  add(String(grant.id||''),grant.origin_id,grant.origin_name||'Tratto',
    grant.attacks_per_action,false);
 }
 return benefits;
}

export function attacksPerActionFromBenefits(benefits=[]){
 return rows(benefits).reduce((max,row)=>Math.max(max,count(row?.attacks_per_action)),1);
}


// Canonical vocabulary for attack selectors and roll bonuses. Categories are
// derived from the same typed attack properties used by roll requirements.
const normal=value=>String(value??'').trim().toLowerCase();
const singular=value=>normal(value).replace(/ies$/,'y').replace(/(?<!s)s$/,'');
export function attackCategories(attack={}){
 const categories=new Set(rows(attack.categories).map(normal));
 const id=normal(attack.id),name=normal(attack.name);
 if(attack.check_target){
  categories.add('check');
  if(id==='grapple'||attack.action_id==='grapple'||attack.check_target==='skill:athletics'&&attack.grapple===true)categories.add('grapple');
  if(id==='shove'||attack.action_id==='shove')categories.add('shove');
 }else{
  categories.add('attack');
  if(attack.melee===true)categories.add('melee');
  if(attack.melee===false)categories.add('ranged');
  if(id.startsWith('unarmed'))categories.add('unarmed');
  if(attack.weapon_type||attack.weapon_category||id.startsWith('item:'))categories.add('weapon');
  if(attack.weapon_type==='ranged')categories.add('ranged_weapon');
  if(attack.weapon_type==='melee')categories.add('melee_weapon');
  if(rows(attack.weapon_properties).includes('T')||id.startsWith('item:throw:'))categories.add('thrown');
  if(/(?:crossbow|balestr)/i.test(name+' '+String(attack.weapon_category||'')))categories.add('crossbow');
  if(attack.spell_attack===true)categories.add('spell_attack');
 }
 return [...categories];
}
export function resolveAttackActionSteps(action={},attacks=[],otherActions=[]){
 const options=[...rows(attacks),...rows(otherActions).filter(row=>row?.check_target||row?.action_id||row?.monster_action)];
 const result=[];
 for(const step of rows(action.steps)){
  const selector=step.selector||{};
  const candidates=options.filter(row=>{
   const categories=attackCategories(row);
   if(selector.kind==='ability')return !!row.monster_action&&
     singular(row.name)===singular(selector.name);
   if(selector.id&&normal(row.id)!==normal(selector.id))return false;
   if(selector.name&&singular(row.name)!==singular(selector.name))return false;
   if(selector.category&&!categories.includes(normal(selector.category)))return false;
   if(selector.kind==='attack'&&!categories.includes('attack'))return false;
   return selector.kind==='ability'||categories.includes('attack')||categories.includes('check');
  });
  result.push({...step,count:Math.min(99,Math.max(1,Math.trunc(Number(step.count)||1))),options:candidates,
   resolved:candidates.length>0});
 }
 return result;
}
// An attack action is a sequence with its own action economy and payment.
// Named class/monster rules live in data; the engine does not test feature IDs.
export function attackActionGrants(record={},features=[],trackers=[],catalog={}){
 const result=[];
 const active=feature=>featureEnabled(record,feature)&&record.trait_enabled?.[feature.key]!==false;
 const classes=rows(record.classes).length?record.classes:record.class?[{name:record.class,source:record.class_source,level:record.level||1}]:[];
 for(const rule of rows(catalog.attack_actions)){
  if(rule.rules_version&&rule.rules_version!==String(record.rules_version||'2014'))continue;
  const member=classes.find(c=>normal(c.name)===normal(rule.class_name)&&
   (!rule.class_source||!c.source||normal(c.source)===normal(rule.class_source))&&
   Number(c.level||0)>=Number(rule.min_level||1));
  if(!member)continue;
  const source='class|'+normal(rule.class_source||member.source)+'|'+normal(rule.class_name);
  const feature=rows(features).find(f=>normal(f.name)===normal(rule.feature)&&
   (String(f.origin_key||'')===source||String(f.origin_key||'').startsWith(source+'|'))&&active(f));
  if(!feature)continue;
  const tracker=rule.tracker_name?rows(trackers).find(t=>!t.disabled&&normal(t.name)===normal(rule.tracker_name)&&
   (!t.origin_class||normal(t.origin_class)===normal(rule.class_name))):null;
  const cost=Math.max(0,Number(rule.tracker_cost)||0);
  result.push({id:'attack_action:'+rule.id,name:rule.name||feature.name,time:rule.time||'action',
   origin_id:feature.origin_id,feature_id:feature.origin_id,feature_name:feature.name,
   description:rule.detail||feature.entries||'',steps:rows(rule.steps),attack_action:true,
   tracker_id:tracker?.id||'',tracker:tracker?.name||rule.tracker_name||'',cost,
   available:cost===0||!!tracker,unavailable_reason:cost&&!tracker?'Risorsa non disponibile':'',
   class_feature_id:rule.class_feature_id||'',automatic:true});
 }
 if(record.kind==='monster'){
  // Import normalization adds attack_action to 5eTools stat-block entries.
  for(const [i,row] of rows(normalizeMonsterStatBlock(record.stat_block||{}).action).entries()){
   if(!/^(?:multiattack|multiattacco)$/i.test(String(row?.name||'').trim()))continue;
   const spec=row.attack_action;
   if(!Array.isArray(spec?.steps)||!spec.steps.length)continue;
   const trait=rows(features).find(f=>f.monster_role==='multiattack'&&
    normal(f.name)===normal(row.name)&&f.id==='trait:action:'+i);
   if(trait&&!active(trait))continue;
   const tracker=rows(trackers).find(t=>t.id===spec.tracker_id);
   const cost=Math.max(0,Number(spec.tracker_cost)||0);
   result.push({id:i===0?'monster:multiattack':'monster:multiattack:'+i,name:spec.name||row.name,
    time:spec.time||'action',description:row.entries||row.description||'',
    origin_id:trait?.origin_id||'',feature_id:trait?.origin_id||'',
    steps:spec.steps,attack_action:true,monster_action:true,
    tracker_id:tracker?.id||'',tracker:tracker?.name||'',
    cost,available:cost===0||!!tracker,automatic:true});
  }
 }
 return result;
}
export function attackActionUsePatch(record={},calculated={},actionId=''){
 const action=rows(calculated.attack_actions).find(row=>row.id===actionId);
 if(!action||action.available===false)throw Error('Azione di attacco non disponibile.');
 const cost=Number(action.cost)||0;
 if(cost<=0)return {};
 const tracker=rows(calculated.trackers).find(row=>row.id===action.tracker_id&&!row.disabled);
 if(!tracker)throw Error('Tracker non collegato all’azione.');
 const spent={...(record.resource_tracker_spent||{})};
 if(Number(tracker.max)-Number(spent[tracker.id]||0)<cost)throw Error('Risorsa insufficiente.');
 spent[tracker.id]=Number(spent[tracker.id]||0)+cost;
 return {resource_tracker_spent:spent};
}
