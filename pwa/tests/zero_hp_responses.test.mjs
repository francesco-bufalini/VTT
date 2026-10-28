import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {racialPowerProjection,racialAbilityEffectFormula} from '../species_powers.js';
import {featureRollTarget} from '../feature_rolls.js';
import {availableZeroHpResponses,resolveZeroHpDamage} from '../zero_hp_responses.js';
const index=JSON.parse(readFileSync(new URL('../catalog/species_powers.json',import.meta.url),'utf8'));
function setup(species,source,traitName){
 const id='5etools:races:'+source.toLowerCase()+':'+species.toLowerCase();
 const record={kind:'character',rules_version:'2014',level:8,species,species_source:source,species_id:id,
  current_hp:8,temporary_hp:3,abilities:{con:16},resource_tracker_spent:{}};
 const owner={name:traitName,origin_key:'species|'+id+'|'+source.toLowerCase(),
  origin_id:'feature:species|'+id+'|'+source.toLowerCase()+'|1|'+traitName.toLowerCase()};
 const projection=racialPowerProjection(record,index,[owner]);
 const calculated={stats:{max_hp:24,proficiency:3},abilities:{con:{modifier:3}},
  trackers:projection.trackers,damage_responses:projection.abilities.filter(x=>x.damage_response)};
 return {record,calculated,projection};
}
test('Goliath and Hadozee prevent lethal damage before reducing temporary/current HP',()=>{
 for(const [name,source,trait,formula] of [['Goliath','MPMM',"Stone's Endurance",'1d12+3'],['Hadozee','AAG','Hadozee Dodge','1d6+3']]){
  const {record,calculated,projection}=setup(name,source,trait);
  assert.equal(availableZeroHpResponses(record,calculated,10).length,0);
  const ability=availableZeroHpResponses(record,calculated,12)[0];
  assert(ability,name);
  assert.equal(racialAbilityEffectFormula(ability,calculated),formula);
  assert.equal(featureRollTarget(ability),'feature_roll:'+ability.id);
  const result=resolveZeroHpDamage(record,calculated,12,ability.id,6);
  assert.equal(result.prevented,6);
  assert.equal(result.damage,6);
  assert.equal(result.patch.current_hp,5);
  assert.equal(result.patch.temporary_hp,0);
  assert.equal(result.patch.resource_tracker_spent[ability.tracker_id],1);
  const fully=resolveZeroHpDamage(record,calculated,12,ability.id,40);
  assert.equal(fully.damage,0);
  assert.equal(fully.patch.temporary_hp,3);
  const exhausted={...record,resource_tracker_spent:{[ability.tracker_id]:projection.trackers[0].max}};
  assert.equal(availableZeroHpResponses(exhausted,calculated,12).length,0);
  assert.throws(()=>resolveZeroHpDamage(exhausted,calculated,12,ability.id,4),/esauriti/);
  assert.throws(()=>resolveZeroHpDamage(record,calculated,12,ability.id),/risultato/);
 }
});
test('2014 Orc and Half-Orc Relentless Endurance works without a roll or reaction',()=>{
 for(const [name,source] of [['Orc','MPMM'],['Half-Orc','PHB']]){
  const {record,calculated}=setup(name,source,'Relentless Endurance');
  const ability=availableZeroHpResponses(record,calculated,12)[0];
  assert(ability,name);
  assert.equal(ability.action_type,'free');
  assert.equal(ability.roll_effect,undefined);
  assert.equal(ability.damage_response.effect,'retain_one_hp');
  const result=resolveZeroHpDamage(record,calculated,12,ability.id);
  assert.equal(result.patch.current_hp,1);
  assert.equal(result.patch.resource_tracker_spent[ability.tracker_id],1);
  assert.equal(availableZeroHpResponses(record,calculated,35).length,0,'instant death');
  assert.equal(availableZeroHpResponses({...record,current_form_id:'wild_shape'},calculated,12).length,0);
  assert.equal(availableZeroHpResponses({...record,current_hp:0},calculated,12).length,0);
  assert.equal(racialPowerProjection({...record,rules_version:'2024'},index,[{
   name:'Relentless Endurance',origin_key:'species|'+record.species_id+'|'+source.toLowerCase()
  }]).abilities.length,0);
 }
});
