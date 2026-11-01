import {speciesPowerTestIndex} from './species_power_test_fixture.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {racialPowerProjection,racialAbilityEffectFormula,racialAbilityTemporaryHpPatch} from '../species_powers.js';
import {abilitiesForCreature} from '../activated_abilities.js';
import {battleAbilityEntries} from '../action_economy.js';
import {rollBattleDamage} from '../sheet_rules_view.js';

const catalog=speciesPowerTestIndex();
const source=JSON.parse(readFileSync(new URL('../../vtt/data/compendium_features_5etools.json',import.meta.url),'utf8'));
const originDetails={races:source.races};
const record=(name,source='MPMM')=>{
 const id='5etools:races:'+source.toLowerCase()+':'+name.toLowerCase().replaceAll(' ','%20');
 return {id:'test',kind:'character',rules_version:'2014',level:9,species:name,species_source:source,
  species_id:id,abilities:{str:12,dex:12,con:16,int:10,wis:10,cha:10},resource_tracker_spent:{}};
};
const owner=(c,trait)=>({
 name:trait,origin_key:'species|'+c.species_id+'|'+c.species_source.toLowerCase(),
 origin_id:'feature:species|'+c.species_id+'|'+c.species_source.toLowerCase()+'|1|'+trait.toLowerCase(),
 key:'racial-test|'+trait.toLowerCase(),entries:[trait],bonuses:[]});
const computed={stats:{proficiency:4},abilities:{con:{modifier:3}}};
const traits={
 Goliath:["Stone's Endurance"],Hadozee:['Hadozee Dodge'],
 Satyr:['Mirthful Leaps'],Lizardfolk:['Hungry Jaws'],
 Orc:['Adrenaline Rush'],Shifter:['Shifting'],
 Harengon:['Rabbit Hop'],Giff:['Firearms Mastery']
};
const projection=(name,source)=>{const c=record(name,source);return {c,p:racialPowerProjection(c,catalog,traits[name].map(t=>owner(c,t)),originDetails)};};

test('all eight latest 2014 racial features project from their own trait and source',()=>{
 for(const [name,source] of [['Goliath','MPMM'],['Hadozee','AAG'],['Satyr','MPMM'],
  ['Lizardfolk','MPMM'],['Orc','MPMM'],['Shifter','MPMM'],['Harengon','MPMM'],['Giff','AAG']]){
  const {c,p}=projection(name,source);
  const active=[...p.abilities,...(p.passive_notes||[])];
  assert(active.length,name);
  for(const item of active){
    assert.equal(item.origin_id,owner(c,traits[name][0]).origin_id);
    assert.equal(item.source||source,source);
  }
  const disabled=racialPowerProjection({...c,rules_version:'2024'},catalog,traits[name].map(t=>owner(c,t)));
  assert.equal(disabled.abilities.length,0,name+' 2024');
  assert.equal((disabled.passive_notes||[]).length,0,name+' 2024 notes');
 }
});

test('Goliath and Hadozee have reaction trackers and reusable damage mitigation dice',()=>{
 for(const [name,source,formula,total] of [['Goliath','MPMM','1d12+3',9],['Hadozee','AAG','1d6+4',10]]){
  const {c,p}=projection(name,source),ability=p.abilities[0];
  assert.equal(ability.action_type,'reaction');
  assert.equal(ability.mode,'tracked_action');
  assert.equal(ability.resource_cost,1);
  assert.equal(p.trackers[0].max,4);
  assert.equal(p.trackers[0].recharge,'long_rest');
  assert.equal(racialAbilityEffectFormula(ability,computed),formula);
  assert.equal(rollBattleDamage(formula,()=>6).total,total);
  const activated=abilitiesForCreature(c,[],{...p,racial_abilities:p.abilities,features:[owner(c,traits[name][0])]});
  assert.equal(activated.length,1);
  assert.equal(battleAbilityEntries(c,{...p,trackers:p.trackers},[],activated)
   .find(row=>row.name===ability.name)?.roll_effect?.label,'Riduzione danni');
 }
});

test('Satyr jump die is usable without a tracker or hidden action cost',()=>{
 const {c,p}=projection('Satyr','MPMM');
 assert.equal(p.trackers.length,0);
 assert.equal(p.abilities.length,1);
 assert.equal(p.abilities[0].resource_cost,0);
 assert.equal(p.abilities[0].action_type,'movement');
 assert.equal(racialAbilityEffectFormula(p.abilities[0],computed),'1d8');
 assert.equal(rollBattleDamage('1d8',()=>5).total,5);
 const activated=abilitiesForCreature(c,[],{...p,racial_abilities:p.abilities,features:[owner(c,'Mirthful Leaps')]});
 assert.equal(activated.length,1);
});

test('Lizardfolk, Orc, Shifter and Harengon have PB limited reusable bonus actions',()=>{
 for(const name of ['Lizardfolk','Orc','Shifter','Harengon']){
  const {p}=projection(name,'MPMM');
  assert.equal(p.abilities.length,1,name);
  assert.equal(p.abilities[0].action_type,'bonus',name);
  assert.equal(p.abilities[0].resource_cost,1,name);
  assert.equal(p.trackers.length,1,name);
  assert.equal(p.trackers[0].max,4,name);
  assert.equal(p.trackers[0].recharge,'long_rest',name);
 }
 const lizard=projection('Lizardfolk','MPMM').p.abilities[0];
 assert.equal(racialAbilityTemporaryHpPatch({},lizard,computed).temporary_hp,undefined);
 const orc=projection('Orc','MPMM').p.abilities[0];
 assert.deepEqual(racialAbilityTemporaryHpPatch({temporary_hp:7},orc,computed),{temporary_hp:7});
 assert.deepEqual(racialAbilityTemporaryHpPatch({temporary_hp:1},orc,computed),{temporary_hp:4});
 const shifter=projection('Shifter','MPMM').p.abilities[0];
 assert.equal(shifter.persistent_key,'racial:shifter:shifting');
 assert.equal(shifter.duration_rounds,10);
 assert.deepEqual(racialAbilityTemporaryHpPatch({temporary_hp:0},shifter,computed),{temporary_hp:8});
 const hop=projection('Harengon','MPMM').p.abilities[0];
 assert.match(hop.description,/five times your proficiency bonus/);
 assert.match(lizard.description,/If the attack hits/);
});

test('Giff Firearms Mastery is passive and does not create an action or a tracker',()=>{
 const {c,p}=projection('Giff','AAG');
 assert.equal(p.abilities.length,0);
 assert.equal(p.trackers.length,0);
 assert.equal(p.passive_notes.length,1);
 assert.match(p.passive_notes[0].description,/long range/);
 assert.match(p.passive_notes[0].description,/loading/);
 assert.equal(abilitiesForCreature(c,[],{...p,features:[owner(c,'Firearms Mastery')]}).length,0);
});

test('disabled racial trait or source produces no tracked power nor passive reminder',()=>{
 const c=record('Orc');
 const feat=owner(c,'Adrenaline Rush');
 assert.equal(racialPowerProjection({...c,trait_enabled:{[feat.key]:false}},catalog,[feat]).abilities.length,0);
 const g=record('Giff','AAG'),gf=owner(g,'Firearms Mastery');
 assert.equal(racialPowerProjection({...g,origin_enabled:{[gf.origin_id]:false}},catalog,[gf]).passive_notes.length,0);
 assert.equal(racialPowerProjection({...c,species_source:'PHB'},catalog,[feat]).abilities.length,0);
});
