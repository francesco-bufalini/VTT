import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {activeExhaustionEffects,exhaustionAdjustedValue,exhaustionRollModifier,
 exhaustionIsDead,exhaustionRemovablePatch} from '../exhaustion_rules.js';
import {classFeatureRollSources} from '../feature_mechanics.js';
import {calculateSheet} from '../sheet_rules.js';
import {traitBenefitGroups} from '../trait_benefits.js';
const rules=JSON.parse(readFileSync(fileURLToPath(
 new URL('../catalog/trait_states.json',import.meta.url)),'utf8')).exhaustion;
const base={kind:'character',name:'Eroe',abilities:{str:14,dex:12,con:12,int:10,wis:10,cha:10},
 max_hp_base:37,speed_base:30,inventory:[],conditions:['poisoned'],rules_version:'2014'};
const calculate=(record)=>calculateSheet(record,{exhaustionRules:rules});
const trait=(level)=>({category:'stati',rank:0,readonly:true,
 condition_id:'exhaustion:'+level,origin_key:'state|condition:exhaustion:'+level});
test('2014 cumulative exhaustion slows at 2, penalizes d20 modes at 1/3 and halves HP at 4',()=>{
 const one=calculate({...base,exhaustion:1});
 assert.equal(one.stats.speeds.walk,30);
 assert.equal(one.stats.max_hp,37);
 assert(classFeatureRollSources({...base,exhaustion:1},one,'skill:athletics')
  .some(row=>row.condition_id==='exhaustion:1'&&row.mode==='disadvantage'));
 assert(!classFeatureRollSources({...base,exhaustion:1},one,'save:con')
  .some(row=>row.condition_id==='exhaustion:1'));
 const two=calculate({...base,exhaustion:2});
 assert.equal(two.stats.speeds.walk,15);
 assert.equal(two.stats.max_hp,37);
 const three=calculate({...base,exhaustion:3});
 for(const scope of ['attack_hit:weapon','save:con','casting_hit:int'])
  assert(classFeatureRollSources({...base,exhaustion:3},three,scope)
   .some(row=>row.condition_id==='exhaustion:3'&&row.mode==='disadvantage'),scope);
 const four=calculate({...base,exhaustion:4});
 assert.equal(four.stats.max_hp,18);
 assert.equal(four.stats.speeds.walk,15);
 const five=calculate({...base,exhaustion:5});
 assert.equal(five.stats.speeds.walk,0);
 const six=calculate({...base,exhaustion:6});
 assert.equal(six.exhaustion_dead,true);
 assert.equal(six.stats.speeds.walk,0);
 assert.equal(calculate({...base,exhaustion:0}).stats.max_hp,37);
});
test('2024 exhaustion applies mandatory -2 per level only to d20 tests and -5 ft per level',()=>{
 const record={...base,rules_version:'2024',exhaustion:3};
 const result=calculate(record);
 assert.equal(result.stats.speeds.walk,15);
 assert.equal(result.stats.max_hp,37);
 assert.equal(result.abilities.str.modifier,2);
 assert.equal(result.stats.passive_perception,10);
 for(const target of ['skill:athletics','ability_mod:wis','initiative','save:dex','attack_hit:weapon','casting_hit:int'])
  assert.equal(exhaustionRollModifier(result.exhaustion_effects,target),-6,target);
 assert.equal(exhaustionRollModifier(result.exhaustion_effects,'attack_damage:weapon'),0);
 assert(!classFeatureRollSources(record,result,'skill:athletics')
  .some(row=>row.condition_id?.startsWith('exhaustion:')));
 const fatal=calculate({...record,exhaustion:6});
 assert.equal(fatal.exhaustion_dead,true);
 assert.equal(fatal.stats.speeds.walk,0);
});
test('exhaustion tiers produce structured benefit groups rather than prose-only traits',()=>{
 const record={...base,exhaustion:4},calculated=calculate(record);
 const groups=traitBenefitGroups(trait(4),record,calculated);
 const modes=groups.find(group=>group.type==='roll_modes')?.items||[];
 const effects=groups.find(group=>group.type==='effects')?.items||[];
 assert(modes.some(row=>row.label==='Prove di caratteristica'&&row.value==='Svantaggio'));
 assert(modes.some(row=>row.label==='Tiri per colpire'&&row.value==='Svantaggio'));
 assert(effects.some(row=>row.label==='PF massimi'&&row.value==='Dimezzati'));
 const revised={...base,rules_version:'2024',exhaustion:3};
 const revisedGroups=traitBenefitGroups(trait(3),revised,calculate(revised));
 assert(revisedGroups.find(group=>group.type==='bonus').items.some(row=>row.value==='-6'));
 assert(revisedGroups.find(group=>group.type==='effects').items.some(row=>row.value==='-15 ft'));
});
test('removing one condition is isolated; deleting active exhaustion resets its numeric field',()=>{
 const record={...base,conditions:['poisoned','stunned','concentrating'],exhaustion:4,concentrating_spell_id:'spell'};
 assert.equal(exhaustionRemovablePatch(record,'exhaustion:2'),null);
 assert.deepEqual(exhaustionRemovablePatch(record,'exhaustion:4'),
  {exhaustion:0,conditions:record.conditions});
 assert.deepEqual(exhaustionRemovablePatch(record,'poisoned'),
  {conditions:['stunned','concentrating']});
 assert.deepEqual(exhaustionRemovablePatch(record,'concentrating'),
  {conditions:['poisoned','stunned'],concentrating_spell_id:''});
 assert.equal(exhaustionRemovablePatch(record,'unknown'),null);
});
test('numeric transformations are catalog-driven, compositional, and safe for absent data',()=>{
 const active=activeExhaustionEffects({...base,exhaustion:3},rules);
 assert.equal(exhaustionAdjustedValue(31,'speed',active),15);
 assert.equal(exhaustionAdjustedValue(20,'hp',active),20);
 assert.equal(exhaustionIsDead(active),false);
 assert.deepEqual(activeExhaustionEffects({...base,exhaustion:3},{}),[]);
});
