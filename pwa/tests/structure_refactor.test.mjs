import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {normalizeMonsterStatBlock} from '../character_core.js';
import {fixedProficiencies,collectStructuredFeatures} from '../structured_effects.js';
import {calculateSheet,SKILLS} from '../sheet_rules.js';
import {SKILLS as nativeSkills,rowsFor} from '../native_sheet.js';
import {resolveVariant} from '../creature_variants.js';
import {parseCreatureExport,makeCreatureExport} from '../creature_format.js';
import {contextualFeatureDescriptors,contextualFeatureGrants,classFeatureEntries,classFeatureDescriptors} from '../feature_mechanics.js';
import {traitBenefitGroups} from '../trait_benefits.js';
import {selectedTraitState} from '../trait_state_rules.js';

test('skill metadata and state selection have one owner',()=>{
 assert.equal(nativeSkills,SKILLS);
 const rules=[{id:'guardian',group:'armor'},{id:'infiltrator',group:'armor'}];
 assert.equal(selectedTraitState({},rules),'');
 assert.equal(selectedTraitState({artificer_armor_model:'infiltrator'},rules),'');
 assert.equal(selectedTraitState({trait_state_selection:{armor:'guardian'}},rules),'guardian');
 assert.equal(selectedTraitState({trait_state_selection:{armor:''}},rules),'');
});

test('only canonical proficiency choices grant saved ranks',()=>{
 const record={skill_proficiencies:['athletics'],skill_expertise:['athletics'],saving_throw_proficiencies:['str']};
 assert.equal(fixedProficiencies(record).size,0);
 assert.deepEqual(rowsFor(record,'proficiency_choices'),[]);
 assert(fixedProficiencies({proficiency_choices:[{kind:'skill',key:'athletics'}]}).has('skill:athletics'));
});

test('current bestiary imports type multiattack without migrating saved sheets',()=>{
 const record={id:'monster',kind:'monster',name:'Monster',stat_block:{action:[{name:'Multiattack',entries:['The beast makes two attacks.']}]}};
 const typed=normalizeMonsterStatBlock(record.stat_block);
 assert.equal(typed.action[0].attacks_per_action,2);
 assert.equal(normalizeMonsterStatBlock(typed),typed);
 assert.deepEqual(parseCreatureExport(makeCreatureExport(record)).creature,record);
});

const featureActionOverrides=JSON.parse(readFileSync(new URL('../../vtt/data/action_feature_overrides.json',import.meta.url),'utf8')).entries;
const feature=(name,owner='Monk',source='XPHB')=>({name,
 origin_key:`class|${source.toLowerCase()}|${owner.toLowerCase()}`,
 origin_id:`feature:${owner}:${name}`,entries:['Description']});
const benefits=(record,calculated,f)=>traitBenefitGroups({rank:2,category:'classi',
 key:f.origin_id,feature_origin:f.origin_id},record,calculated)
 .find(group=>group.type==='abilities')?.items||[];

test('actions and benefits share 2024 timing, resource and free base costs',()=>{
 for(const [name,owner,expectedTime,expectedCost] of [
  ['Lay on Hands','Paladin','bonus',1],['Divine Sense','Paladin','action',1],
  ['Patient Defense','Monk','bonus',0]]){
  const f=feature(name,owner),record={rules_version:'2024'},calculated={features:[f],feature_action_overrides:featureActionOverrides};
  const descriptors=classFeatureDescriptors(record,calculated);
  const action=classFeatureEntries(record,calculated).find(row=>
   row.feature_name===name);
  assert.equal(action.time,expectedTime);assert.equal(action.cost,expectedCost);
  assert(descriptors.some(row=>row.id===action.id&&row.available));
  const preview=benefits(record,calculated,f).find(row=>row.label===action.name);
  assert.equal(preview.timing,expectedTime==='bonus'?'Azione bonus':'Azione');
  assert.equal(preview.cost,expectedCost?'1 utilizzo · '+action.resource_name:'Nessun costo');
 }
});

test('unavailable owned operations stay in benefits and cannot become usable actions',()=>{
 const f=feature('Guardian','Artificer','TCE');
 const rule={id:'guardian',name:'Guardian model',class_name:'Artificer',granted_features:['Guardian']};
 for(const disabled of [false,true]){
  const record=disabled?{origin_enabled:{[f.origin_id]:false}}:{};
  const calculated={features:[f],feature_action_overrides:featureActionOverrides,trait_state_catalog:[rule],active_trait_state_ids:[]};
  const descriptor=classFeatureDescriptors(record,calculated)[0];
  assert.equal(descriptor.available,false);
  assert.equal(classFeatureEntries(record,calculated).length,0);
  const preview=benefits(record,calculated,f)[0];
  assert.equal(preview.status,disabled?'Tratto disattivato':'Modello richiesto');
  assert.match(preview.requirements,/Guardian model/);
 }
});

test('bundled canonical subraces carry the speed of the native source',()=>{
 const mechanics=JSON.parse(readFileSync(new URL('../catalog/class_mechanics.json',import.meta.url)));
 const references=JSON.parse(readFileSync(new URL('../../vtt/data/creature_references_5etools.json',import.meta.url)));
 const key=value=>String(value||'').toLowerCase();
 assert(references.subraces.length>0);
 for(const native of references.subraces){
  const canonical=mechanics.subraces.find(row=>
   [row.raceName,row.raceSource,row.name,row.source].map(key).join('|')===
   [native.raceName,native.raceSource,native.name,native.source].map(key).join('|'));
  assert(canonical,'missing canonical identity: '+native.raceName+' · '+native.name);
  assert.deepEqual(canonical.speed,native.speed);
  assert(!mechanics.races.some(row=>row.id===native.id),'subrace is not a second independent species');

 }
 for(const subrace of mechanics.subraces){
  const native=references.races.find(row=>key(row.name)===key(subrace.raceName+' ('+subrace.name+')')&&
   key(row.source)===key(subrace.source));
  if(native?.speed!==undefined)assert.deepEqual(subrace.speed,native.speed,subrace.name);
 }
});

test('migrated Barbarian contextual operations retain stable IDs, counters and source gates',()=>{
 const rules=JSON.parse(readFileSync(new URL('../../vtt/data/feature_timing_recovery_rules.json',import.meta.url)));
 assert(rules.contextual_actions.length>=30,'previously migrated contextual actions must not disappear');
 assert.equal(new Set(rules.contextual_actions.map(row=>row.id)).size,rules.contextual_actions.length,
  'contextual action IDs must remain unique');
 for(const rule of rules.contextual_actions.filter(row=>row.class_name==='Barbarian')){
  const f={name:rule.feature,key:'key:'+rule.feature,origin_id:'feature:'+rule.feature,
   origin_key:'class|phb|barbarian'+(rule.subclass?'|subclass|'+rule.subclass.toLowerCase()+'|tce':'')};
  const c={kind:'character',class:'Barbarian',class_source:'PHB',level:20,
   classes:[{name:'Barbarian',source:'PHB',subclass:rule.subclass,level:20}]};
  const grants=contextualFeatureGrants(c,[f],rules,6),action=grants.actions.find(row=>row.id===rule.id);
  assert(action,rule.feature);
  assert.equal(action.id,rule.id);
  assert.equal(action.origin_id,f.origin_id);assert.equal(action.action_type,rule.activation);
  if(rule.resource){
   const tracker=grants.trackers.find(row=>row.id===action.tracker_id);
   assert.equal(tracker.id,rule.id);assert.equal(tracker.recharge,rule.resource.recharge);
   assert.equal(tracker.max,rule.resource.max==='proficiency'?6:rule.resource.max);
  }
  for(const record of [{...c,rules_version:'2024'},
   {...c,origin_enabled:{[f.origin_id]:false}},
   {...c,origin_enabled:{'class|phb|barbarian':false}},
   {...c,trait_enabled:{[f.key]:false}},
   {...c,classes:[{name:'Barbarian',source:'PHB',subclass:'Unowned',level:20}]}]){
   if(!rule.subclass&&record.classes[0].subclass==='Unowned')continue;
   assert.equal(contextualFeatureGrants(record,[f],rules).actions.length,0);
  }
  assert.equal(contextualFeatureGrants(c,[{...f,action_type:'action'}],rules).actions.length,0,
   'already typed native activations are never duplicated');
  const disabled={...c,origin_enabled:{[f.origin_id]:false}};
  assert(contextualFeatureDescriptors(disabled,[f],rules).every(row=>!row.available));
  const preview=benefits(disabled,{features:[f],feature_rules:rules},f);
  assert(preview.some(row=>row.label===rule.name&&row.status==='Tratto disattivato'));
 }
});
