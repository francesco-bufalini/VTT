import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {normalizeCreatureRecord,normalizeMonsterStatBlock} from '../character_core.js';
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
 const rules=[{id:'guardian',group:'armor',legacy_field:'old',legacy_value:'g',legacy_default:true},
  {id:'infiltrator',group:'armor',legacy_field:'old',legacy_value:'i'}];
 assert.equal(selectedTraitState({},rules),'guardian');
 assert.equal(selectedTraitState({old:'i'},rules),'infiltrator');
 assert.equal(selectedTraitState({old:'unknown'},rules),'');
 assert.equal(selectedTraitState({old:'i',trait_state_selection:{armor:''}},rules),'');
 assert.equal(selectedTraitState({old:'i',trait_state_selection:{armor:'guardian'}},rules),'guardian');
});

test('legacy choice normalization preserves calculations, exclusions and explicit removals',()=>{
 const base={kind:'character',abilities:{dex:14,wis:12},
  skill_proficiencies:['stealth','perception'],skill_expertise:['stealth'],
  saving_throw_proficiencies:['dex'],unknown_field:{kept:true}};
 const records=[base,{...base,proficiency_choices:[]},
  {...base,proficiency_choices:[],proficiency_origins:[]},
  {...base,proficiency_choices:[{kind:'skill',key:'arcana',disabled:true}]},
  {...base,proficiency_choices:[{kind:'skill',key:'arcana',origin_id:'custom'}]},
  {...base,proficiency_choices:[{kind:'skill',key:'arcana',origin_id:'custom'}],
   proficiency_origins:[{id:'custom',disabled:true}]}];
 for(const record of records){
  const before=structuredClone(record),normalized=normalizeCreatureRecord(record);
  assert.deepEqual(record,before,'conversion never mutates its input');
  assert.deepEqual([...fixedProficiencies(normalized)],[...fixedProficiencies(record)]);
  const a=calculateSheet(record),b=calculateSheet(normalized);
  assert.deepEqual(a.skills,b.skills);assert.deepEqual(a.saves,b.saves);
  assert.deepEqual(a.proficiencies,b.proficiencies);
  assert.deepEqual(rowsFor(normalized,'proficiency_choices'),rowsFor(record,'proficiency_choices'));
  assert.equal(normalizeCreatureRecord(normalized),normalized,'conversion is idempotent');
  assert.deepEqual(normalized.unknown_field,{kept:true});
 }
 assert.equal(normalizeCreatureRecord(records[2]).proficiency_choices.length,0);
});

test('normalization commutes with variant resolution and keeps shared origin removals',()=>{
 for(const origins of [undefined,[]]){
  const record={id:'hero',kind:'character',name:'Hero',current_form_id:'form',
   ...(origins?{proficiency_origins:origins}:{}),
   variants:[{id:'form',name:'Form',sections:['proficiencies'],values:{
    proficiency_choices:[],skill_proficiencies:['athletics']}}]};
  assert.deepEqual(normalizeCreatureRecord(resolveVariant(record)),
   resolveVariant(normalizeCreatureRecord(record)));
 }
});

test('untyped monster ingress preserves feature identities and typed counts take precedence',()=>{
 for(const row of [
  {name:'Multiattack',entries:['The dragon makes three attacks: one bite and two claws.']},
  {name:'Multiattack',description:'The beast can make two melee attacks.'},
  {name:'Multiattack',attacks_per_action:4,entries:['The dragon makes three attacks.']},
  {name:'Multiattack',entries:['See the encounter instructions.']},
  {name:'Bite',entries:['The beast makes two attacks.']}
 ]){
  const record={kind:'monster',stat_block:{action:[row]}};
  const normalized=normalizeCreatureRecord(record);
  assert.deepEqual(collectStructuredFeatures(normalized),collectStructuredFeatures(record));
  assert.equal(normalizeMonsterStatBlock(normalized.stat_block),normalized.stat_block);
  assert.deepEqual(record.stat_block.action[0],row);
 }
 const old={id:'old',kind:'monster',name:'Old',skill_proficiencies:['perception'],
  stat_block:{action:[{name:'Multiattack',entries:['The beast makes two attacks.']}]}};
 const exported=makeCreatureExport(old),parsed=parseCreatureExport(exported).creature;
 assert.equal(parsed.stat_block.action[0].attacks_per_action,2);
 assert.equal(parsed.proficiency_choices[0].key,'perception');
});

const feature=(name,owner='Monk',source='XPHB')=>({name,
 origin_key:`class|${source.toLowerCase()}|${owner.toLowerCase()}`,
 origin_id:`feature:${owner}:${name}`,entries:['Description']});
const benefits=(record,calculated,f)=>traitBenefitGroups({rank:2,category:'classi',
 key:f.origin_id,feature_origin:f.origin_id},record,calculated)
 .find(group=>group.type==='abilities')?.items||[];

test('actions and benefits share 2024 timing, resource and free base costs',()=>{
 for(const [name,owner,expectedTime,expectedCost] of [
  ['Lay on Hands','Paladin','bonus',1],['Divine Sense','Paladin','action',1],
  ['Monk’s Focus','Monk','bonus',0]]){
  const f=feature(name,owner),record={rules_version:'2024'},calculated={features:[f]};
  const descriptors=classFeatureDescriptors(record,calculated);
  const action=classFeatureEntries(record,calculated).find(row=>
   name==='Monk’s Focus'?row.class_feature_id==='patient_defense':true);
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
  const calculated={features:[f],trait_state_catalog:[rule],active_trait_state_ids:[]};
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
  const legacy={kind:'character',species:native.legacy_name,species_source:native.source,
   species_id:native.id,abilities:{str:10,dex:10,con:10,int:10,wis:10,cha:10}};
  const modern={...legacy,species:native.raceName,species_source:native.raceSource,
   species_id:'',subrace:native.name,subrace_source:native.source};
  const options={classMechanics:mechanics};
  assert.deepEqual(calculateSheet(legacy,options).stats.speeds,
   calculateSheet(modern,options).stats.speeds,'legacy movement: '+native.legacy_name);
  const normalized=normalizeCreatureRecord(legacy,options);
  assert.equal(normalized.species_id,legacy.species_id);assert.equal(normalized.species,legacy.species);
 }
 for(const subrace of mechanics.subraces){
  const native=references.races.find(row=>key(row.name)===key(subrace.raceName+' ('+subrace.name+')')&&
   key(row.source)===key(subrace.source));
  if(native?.speed!==undefined)assert.deepEqual(subrace.speed,native.speed,subrace.name);
 }
});

test('all migrated contextual operations retain stable IDs, counters and source gates',()=>{
 const rules=JSON.parse(readFileSync(new URL('../../vtt/data/feature_timing_recovery_rules.json',import.meta.url)));
 assert.equal(rules.contextual_actions.length,30);
 assert.equal(new Set(rules.contextual_actions.map(row=>row.id)).size,30);
 for(const rule of rules.contextual_actions){
  const f={name:rule.feature,key:'key:'+rule.feature,origin_id:'feature:'+rule.feature,
   origin_key:'class|phb|barbarian'+(rule.subclass?'|subclass|'+rule.subclass.toLowerCase()+'|tce':'')};
  const c={kind:'character',class:'Barbarian',class_source:'PHB',level:20,
   classes:[{name:'Barbarian',source:'PHB',subclass:rule.subclass,level:20}]};
  const grants=contextualFeatureGrants(c,[f],rules,6),action=grants.actions.find(row=>row.id===rule.id);
  assert(action,rule.name);
  assert.equal(action.id,'barbarian:2014:'+rule.name.trim().toLowerCase().replace(/[^a-z0-9]+/g,'-'));
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
