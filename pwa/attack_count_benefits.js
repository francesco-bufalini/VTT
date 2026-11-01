// Attack count is a trait benefit, not a bonus to a roll or an extra action.
// Multiple grants never stack: the Attack action uses the highest active count.
import {featureEnabled} from './feature_mechanics.js';
import {removedBenefitIds} from './trait_benefit_editor.js';
import {normalizeMonsterStatBlock} from './character_core.js';
import {SKILLS} from './skill_definitions.js';
import {monsterActions,monsterTraits,monsterActionCost,monsterActionUsePatch} from './monster_traits.js';

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
  if(attack.weapon_type==='ranged'||attack.melee===false&&categories.has('weapon'))categories.add('ranged_weapon');
  if(attack.weapon_type==='melee'||attack.melee===true&&categories.has('weapon'))categories.add('melee_weapon');
  if(rows(attack.weapon_properties).includes('T')||id.startsWith('item:throw:'))categories.add('thrown');
  if(/(?:crossbow|balestr)/i.test(name+' '+String(attack.weapon_category||'')))categories.add('crossbow');
  if(attack.spell_attack===true)categories.add('spell_attack');
 }
 return [...categories];
}
// Resolve a sequence from existing attacks, general actions, capabilities and
// the canonical skill list. "one_of" means choose exactly one branch.
const stepCount=value=>Math.min(99,Math.max(1,Math.trunc(Number(value)||1)));
const skillCheck=target=>{
 const id=normal(target),skill=id.startsWith('skill:')?
  SKILLS.find(([key])=>key===id.slice(6)):null;
 if(skill)return {id:'check:'+id,name:'Prova di '+skill[1],check_target:id};
 const ability=/^ability_check:(str|dex|con|int|wis|cha)$/.exec(id);
 if(!ability)return null;
 const name=({str:'Forza',dex:'Destrezza',con:'Costituzione',
  int:'Intelligenza',wis:'Saggezza',cha:'Carisma'})[ability[1]];
 return {id:'check:'+id,name:'Prova di '+name,check_target:id};
};
export function resolveAttackActionSteps(action={},attacks=[],otherActions=[]){
 const attackRows=rows(attacks),otherRows=rows(otherActions);
 const candidates=[...attackRows,...otherRows];
 const resolve=part=>{
  const selector=part.selector||{},kind=normal(selector.kind);
  const check=kind==='check'?skillCheck(selector.target||selector.id):null;
  const options=check?[check]:candidates.filter(row=>{
   const isAttack=attackRows.includes(row),isCheck=!!row.check_target;
   const isAbility=!!row.monster_action||row.type==='Capacità';
   const isAction=!isAttack&&!isCheck&&!isAbility;
   if(kind==='attack'&&!isAttack||kind==='check'&&!isCheck||
      kind==='action'&&!isAction||kind==='ability'&&!isAbility)return false;
   if(!kind&&!isAttack&&!isCheck)return false;
   if(selector.id&&normal(row.id)!==normal(selector.id))return false;
   if(selector.name&&singular(row.name)!==singular(selector.name))return false;
   if(selector.category&&!attackCategories(row).includes(normal(selector.category)))return false;
   return true;
  });
  return {...part,count:stepCount(part.count),options,resolved:options.length>0};
 };
 return rows(action.steps).map(step=>{
  const alternatives=rows(step.one_of||step.any_of);
  if(!alternatives.length)return resolve(step);
  const one_of=alternatives.map((choice,index)=>resolve({...choice,
   id:String(choice.id||'choice:'+index)}));
  return {...step,count:stepCount(step.count),one_of,options:[],
   resolved:one_of.some(choice=>choice.resolved)};
 });
}
// Keep branch IDs stable in saved data; a missing or unknown OR selection must
// never silently spend the default resource amount.
export function attackActionChoice(action={},choiceId=''){
 const options=rows(action.steps).flatMap(step=>rows(step.one_of||step.any_of));
 if(!options.length){
  if(choiceId)throw Error('Opzione non prevista per questa azione.');
  return null;
 }
 const chosen=options.find((choice,index)=>String(choice.id||'choice:'+index)===String(choiceId||''));
 if(!chosen)throw Error('Scegli una delle alternative disponibili.');
 return chosen;
}
export function attackActionPayment(action={},choiceId=''){
 const choice=attackActionChoice(action,choiceId);
 const cost=Number(choice?.tracker_cost??action.cost??0);
 if(!Number.isSafeInteger(cost)||cost<0||cost>99)throw Error('Costo dell’azione non valido.');
 return {choice,cost,tracker_id:String(choice?.tracker_id??action.tracker_id??'')};
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
   (String(f.origin_key||'')===source||String(f.origin_key||'').startsWith(source+'|'))&&
   (!rule.subclass||String(f.origin_key||'').toLowerCase().includes('|subclass|'+normal(rule.subclass)+'|'))&&active(f));
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
 // Features and homebrew grants can declare the same sequence without
 // requiring a new catalog entry or per-trait runtime handler.
 for(const feature of rows(features)){
  const spec=feature.action_sequence||feature.attack_action;
  if(!active(feature)||!rows(spec?.steps).length)continue;
  if(result.some(row=>row.origin_id===feature.origin_id&&
    JSON.stringify(row.steps)===JSON.stringify(spec.steps)))continue;
  const tracker=rows(trackers).find(t=>t.id===spec.tracker_id||t.name===spec.tracker_name);
  const cost=Number(spec.tracker_cost||0);
  result.push({id:'attack_action:feature:'+String(feature.key||feature.origin_id),
   name:spec.name||feature.name,time:spec.time||'action',description:spec.detail||feature.entries||'',
   origin_id:feature.origin_id,feature_id:feature.origin_id,feature_name:feature.name,
   attack_action:true,steps:spec.steps,tracker_id:tracker?.id||'',
   tracker:tracker?.name||spec.tracker_name||'',cost,
   available:cost===0||!!tracker,automatic:true});
 }
 for(const grant of rows(record.action_grants)){
  if(!rows(grant?.steps).length||grant.disabled||!sourceEnabled(record,grant.origin_id))continue;
  const id='attack_action:grant:'+String(grant.id||grant.name||'');
  if(result.some(row=>row.id===id))continue;
  const tracker=rows(trackers).find(t=>t.id===grant.tracker_id||t.name===grant.tracker_name);
  const cost=Number(grant.tracker_cost||0);
  result.push({...grant,id,name:grant.name||'Azione concessa',time:grant.time||grant.action_type||'action',
   origin_id:grant.origin_id||'',attack_action:true,tracker_id:tracker?.id||'',
   tracker:tracker?.name||grant.tracker_name||'',cost,
   available:cost===0||!!tracker,automatic:false});
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
  // The whole legendary-action pool is one OR group. The options and their
  // distinct costs come from the monster's own structured legendary entries.
  const owner=monsterTraits(record).find(row=>row.monster_role==='legendary');
  const actions=monsterActions(record,trackers).filter(row=>row.id.startsWith('monster:legendary:'));
  if(owner&&actions.length){
   const tracker=rows(trackers).find(t=>t.id===owner.monster_pool?.id||
     t.origin_id==='feature:'+owner.feature_key);
   const options=actions.map(action=>{
    const index=Number(String(action.id).split(':')[2]);
    const raw=rows(record.stat_block?.legendary)[index]||{};
    const prose=String(action.description||'');
    // Explicit homebrew selectors take precedence. Otherwise translate a
    // check directly to the canonical d20 target: no synthetic Detect action.
    const explicit=raw.action_selector||raw.vtt_action_selector;
    const check=SKILLS.find(([key])=>prose.toLowerCase().includes(key)&&/\bcheck\b/i.test(prose));
    const stem=normal(action.name).replace(/\s*\(costs?.*$/i,'').replace(/\s+attack$/,'');
    const referencedIndex=rows(record.stat_block?.action).findIndex(row=>normal(row?.name)===stem);
    const selector=explicit||(
     action.roll_attack?.id?{kind:'attack',id:action.roll_attack.id}:
     check?{kind:'check',target:'skill:'+check[0]}:
     referencedIndex>=0?{kind:'attack',id:'monster:action:'+referencedIndex}:
     {kind:'ability',id:action.id});
    const targetCheck=selector.kind==='check'?skillCheck(selector.target||selector.id):null;
    return {id:action.id,
     // A check is the actual option; Detect is only the source's legacy name.
     label:targetCheck?.name||action.name,
     selector,tracker_cost:monsterActionCost(raw),description:prose};
   });
   result.push({id:'monster:legendary:choices',name:owner.name,time:'free',
    description:owner.entries||'',origin_id:'feature:'+owner.feature_key,
    feature_id:'feature:'+owner.feature_key,attack_action:true,monster_action:true,
    steps:[{one_of:options}],covered_action_ids:actions.map(row=>row.id),
    tracker_id:tracker?.id||owner.monster_pool?.id||'',
    tracker:tracker?.name||owner.monster_pool?.name||'',cost:1,
    available:!!tracker&&!tracker.disabled,automatic:true});
  }
 }
 return result;
}
export function attackActionUsePatch(record={},calculated={},actionId='',choiceId=''){
 const action=rows(calculated.attack_actions).find(row=>row.id===actionId);
 if(!action||action.available===false)throw Error('Azione non disponibile.');
 const {choice,cost,tracker_id}=attackActionPayment(action,choiceId);
 if(!choice&&cost<=0)return {};
 if(choice){
  // Only actual, live options can be spent. Reuse the native action identity
  // for abilities rather than creating a second, synthetic action.
  const candidates=[...rows(calculated.action_entries),...monsterActions(record,calculated.trackers)];
  const resolved=resolveAttackActionSteps({steps:[{selector:choice.selector}]},
   rows(calculated.attacks),candidates)[0];
  if(!resolved?.resolved)throw Error('Azione o tiro collegato non disponibile.');
  const native=candidates.find(row=>row.monster_action===true&&
   row.id===choice.selector?.id);
  if(native&&['ability','attack'].includes(choice.selector?.kind)){
   if(native.tracker_id!==tracker_id||Number(native.cost)!==cost)
    throw Error('Costo dell’azione non coerente con la capacità originale.');
   // Its original handler validates origin and consumes the same shared tracker.
   return monsterActionUsePatch(record,calculated,native.id);
  }
 }
 if(cost<=0)return {};
 const tracker=rows(calculated.trackers).find(row=>row.id===tracker_id&&!row.disabled);
 if(!tracker)throw Error('Tracker non collegato all’azione.');
 const spent={...(record.resource_tracker_spent||{})};
 if(Number(tracker.max)-Number(spent[tracker.id]||0)<cost)throw Error('Risorsa insufficiente.');
 spent[tracker.id]=Number(spent[tracker.id]||0)+cost;
 return {resource_tracker_spent:spent};
}
