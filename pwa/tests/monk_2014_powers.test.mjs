import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {classFeatureDescriptors,classFeatureActivationPatch,classFeatureActive,featureActionEntries} from '../feature_mechanics.js';
import {persistentBattleAbility} from '../sheet_rules_view.js';

const catalog=JSON.parse(readFileSync(new URL('../catalog/classes.json',import.meta.url),'utf8'));
const rules=JSON.parse(readFileSync(new URL('../../vtt/data/feature_timing_recovery_rules.json',import.meta.url),'utf8'));
const feature=(name,source='PHB',subclass='')=>{
 const owner='class|'+source.toLowerCase()+'|monk'+(subclass?'|subclass|'+subclass.toLowerCase()+'|phb':'');
 return {name,origin_key:owner,origin_id:'feature:'+owner+'|'+name.toLowerCase(),
  entries:[name+' description'],requirements:{class_name:'Monk',class_source:source}};
};
const creature=(level,edition='2014',subclass='')=>{
 const source=edition==='2024'?'XPHB':'PHB';
 return {kind:'character',class:'Monk',class_source:source,rules_version:edition,
  level,subclass,classes:[{name:'Monk',source,level,subclass}],resource_tracker_spent:{}};
};
const withKi=features=>({features,trackers:[{id:'class:monk:phb:ki',name:'Ki Points',
 origin_class:'Monk',max:20,spent:0}],feature_rules:{}});

test('2014 Monk Ki techniques retain their own 5etools trait texts and source identities',()=>{
 const entries=catalog.class_features.filter(row=>row.class_name==='Monk'&&row.class_source==='PHB');
 for(const name of ['Ki','Flurry of Blows','Patient Defense','Step of the Wind']){
  const row=entries.find(item=>item.name===name&&item.source==='PHB');
  assert(row&&row.entries.length,'missing separate PHB trait: '+name);
 }
 const names=['Ki','Flurry of Blows','Patient Defense','Step of the Wind'];
 const projection=withKi(names.map(name=>feature(name)));
 const results=classFeatureDescriptors(creature(5),projection);
 for(const [id,name] of [['flurry_of_blows','Flurry of Blows'],
  ['patient_defense','Patient Defense'],['step_of_the_wind','Step of the Wind']]){
  const row=results.find(item=>item.class_feature_id===id);
  assert(row,'missing operation '+id);
  assert.equal(row.feature_name,name);
  assert.deepEqual(row.description,[name+' description']);
  assert.equal(row.origin_id,projection.features.find(item=>item.name===name).origin_id);
  assert.equal(row.cost,1);
  assert.equal(row.mode,'context');
  assert.equal(row.time,'bonus');
 }
 assert.equal(classFeatureDescriptors(creature(5),withKi([feature('Ki')])).length,0,
  'A resource-owning Ki trait must not impersonate the three usable techniques');
});

test('2014 Patient Defense and Step of the Wind pay once, never store an indefinite toggle',()=>{
 const projection=withKi(['Patient Defense','Step of the Wind'].map(name=>feature(name)));
 const record=creature(5);
 for(const id of ['patient_defense','step_of_the_wind']){
  const row=classFeatureDescriptors(record,projection).find(item=>item.class_feature_id===id);
  assert.equal(persistentBattleAbility({classAction:row}),false);
  const patch=classFeatureActivationPatch(record,projection,id);
  assert.deepEqual(patch.resource_tracker_spent,{'class:monk:phb:ki':1});
  assert.equal(patch.active_class_features,undefined);
  assert.equal(classFeatureActive({...record,active_class_features:{[id]:{}}},projection,id),false,
   'a stale old-save toggle must not grant a permanent effect');
 }
 const revised=creature(5,'2024'),revProjection={
  features:[feature('Patient Defense','XPHB'),feature('Step of the Wind','XPHB')],
  trackers:[{id:'class:monk:xphb:focus',name:'Focus Points',origin_class:'Monk',max:5,spent:0}]
 };
 for(const id of ['patient_defense','step_of_the_wind']){
  const row=classFeatureDescriptors(revised,revProjection).find(item=>item.class_feature_id===id);
  assert.equal(row.mode,'toggle','2024 existing behavior is preserved');
  assert.equal(persistentBattleAbility({classAction:row}),true);
 }
});

test('2014 Monk contextual actions are trait-owned, level-gated and pay their own trackers',()=>{
 const monkRules=rules.actions.filter(rule=>rule.class_name==='Monk'&&rule.class_source==='PHB');
 const names=['Martial Arts','Slow Fall','Stillness of Mind','Diamond Soul','Empty Body'];
 const projection=withKi(names.map(name=>feature(name)));
 const levelOne=featureActionEntries(creature(1),projection.trackers,{actions:monkRules},projection.features);
 assert.equal(levelOne.length,1);
 assert.equal(levelOne[0].rule_action_id,'martial_arts_bonus_unarmed');
 assert.equal(levelOne[0].time,'bonus');
 assert.equal(levelOne[0].cost,0);
 const level18=featureActionEntries(creature(18),projection.trackers,{actions:monkRules},projection.features);
 for(const id of ['slow_fall','stillness_of_mind','diamond_soul_retry','empty_body_invisibility'])
  assert(level18.some(row=>row.rule_action_id===id),id);
 const retry=level18.find(row=>row.rule_action_id==='diamond_soul_retry');
 const invisible=level18.find(row=>row.rule_action_id==='empty_body_invisibility');
 assert.equal(retry.cost,1);
 assert.equal(invisible.cost,4);
 assert.equal(invisible.tracker_id,'class:monk:phb:ki');
 const openFeature=feature('Wholeness of Body','PHB','open hand');
 const longRest={id:'class:monk:phb:wholeness',name:'Wholeness of Body',max:1,spent:0};
 const open=featureActionEntries(creature(6,'2014','Way of the Open Hand'),
  [longRest],{actions:monkRules},[openFeature]);
 assert.equal(open.find(row=>row.rule_action_id==='wholeness_of_body')?.cost,1);
 assert.equal(featureActionEntries(creature(6,'2014','Way of Shadow'),
  [longRest],{actions:monkRules},[openFeature]).length,0,
  'an Open Hand benefit cannot appear for a Shadow monk');
});
