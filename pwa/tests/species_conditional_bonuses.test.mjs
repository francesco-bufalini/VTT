import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {selectedRacialBonusSources,racialBonusFeatures,racialBonusEntries,racialBonusTrackers} from '../species_conditional_bonuses.js';
import {calculateSheet,applicableDiceBonuses} from '../sheet_rules.js';
import {traitBenefitGroups} from '../trait_benefits.js';
import {rollOptionalDice} from '../sheet_roll_origin.js';
const rules=JSON.parse(readFileSync(new URL('../catalog/species_conditional_bonuses.json',import.meta.url),'utf8'));
const character=(species,source,options={})=>({
 kind:'character',rules_version:'2014',level:8,species,species_source:source,
 species_id:'5etools:races:'+source.toLowerCase()+':'+species.toLowerCase(),
 inventory:[],abilities:{str:10,dex:14,con:10,int:14,wis:12,cha:10},...options});
const project=record=>{
 const features=racialBonusFeatures(record,rules);
 return {features,bonuses:racialBonusEntries(record,rules,features)};
};
const available=(bonuses,target)=>applicableDiceBonuses({inventory:[]},target,[],{
 racial_roll_bonuses:bonuses,values:{attunement_max:3},attunements:{counts:[]}});
test('ERLW dragonmarks are bounded to the correct 2014 race and subrace',()=>{
 for(const [species,subrace,skill,tool] of [
  ['Elf','Mark of Shadow','skill:stealth',false],
  ['Gnome','Mark of Scribing','skill:history',true],
  ['Dwarf','Mark of Warding','skill:investigation',true],
  ['Halfling','Mark of Healing','skill:medicine',true],
  ['Half-Elf','Variant; Mark of Detection','skill:insight',false],
  ['Half-Elf','Variant; Mark of Storm','skill:acrobatics',true],
  ['Human','Variant; Mark of Making','skill:arcana',true],
  ['Human','Variant; Mark of Finding','skill:survival',false],
  ['Half-Orc','Variant; Mark of Finding','skill:perception',false]
 ]){
  const c=character(species,'PHB',{subrace,subrace_source:'ERLW'}),{features,bonuses}=project(c);
  const mark=bonuses.filter(x=>x.origin_key.startsWith('subrace|'));
  assert.equal(mark.length,1,species+' '+subrace);
  assert.equal(available(mark,skill).length,1,species+' '+subrace+' skill');
  assert.equal(available(mark,'skill:athletics').length,0,'bonus must not apply to unrelated skills');
  assert.equal(available(mark,'ability_check:int').length,tool?1:0,'tool checks only for marked variants with tools');
  assert.equal(mark[0].origin_id,features.find(f=>f.origin_id===mark[0].origin_id)?.origin_id);
  assert.equal(mark[0].origin_key,'subrace|erlw|'+subrace.toLowerCase());
  assert.match(mark[0].condition_label,/Solo per/);
  assert(!project({...c,subrace_source:'SCAG'}).bonuses.length);
  assert(!project({...c,rules_version:'2024'}).bonuses.length);
 }
});
test('all 12 distinct ERLW marks exist and are not available without their selected variant',()=>{
 const markSources=rules.races.filter(r=>r.subrace);
 assert.equal(new Set(markSources.map(r=>r.subrace.replace(/^Variant; /,''))).size,12);
 assert.equal(markSources.length,13);
 assert.equal(project(character('Elf','PHB')).bonuses.length,0);
 assert.equal(project(character('Vedalken','PSK')).bonuses.length,0);
 assert.equal(project(character('Vedalken','GGR')).bonuses.length,1);
});
test('Reborn applies a d6 to skill checks only, PB times per long rest',()=>{
 const c=character('Reborn','VRGR'),{features,bonuses}=project(c);
 assert.equal(bonuses[0].dice,'1d6');
 assert.equal(available(bonuses,'skill:perception').length,1);
 assert.equal(available(bonuses,'ability_check:wis').length,0);
 assert.equal(available(bonuses,'save:wis').length,0);
 const tracker=racialBonusTrackers(bonuses,4)[0];
 assert.equal(tracker.max,4);assert.equal(tracker.recharge,'long_rest');
 assert.equal(rollOptionalDice(c,{trackers:[{...tracker,spent:0}]},bonuses)[0].tracker_cost,1);
 const masked={...c,trait_enabled:{[features[0].key]:false}};
 assert.equal(racialBonusEntries(masked,rules,features).length,0);
 assert.equal(racialBonusEntries(c,rules,features,new Set(['dice:'+bonuses[0].id])).length,0);
});
test('Harengon Lucky Footwork applies only to Dexterity saves and requires a reaction',()=>{
 const bonuses=project(character('Harengon','MPMM')).bonuses;
 assert.equal(available(bonuses,'save:dex').length,1);
 assert.equal(available(bonuses,'save:con').length,0);
 assert.equal(bonuses[0].tracker_id,undefined);
 assert.match(bonuses[0].condition_label,/Reazione/);
 assert.equal(project(character('Harengon','WBtW')).bonuses.length,0);
});
test('MPMM Hobgoblin Fortune has three mutually exclusive bounded bonuses and one shared PB tracker',()=>{
 const c=character('Hobgoblin','MPMM'),{features,bonuses}=project(c);
 assert.deepEqual(bonuses.map(x=>x.flat_bonus),[1,2,3]);
 assert.equal(new Set(bonuses.map(x=>x.exclusive_group)).size,1);
 assert.equal(new Set(bonuses.map(x=>x.tracker_id)).size,1);
 assert.equal(racialBonusTrackers(bonuses,5).length,1);
 assert.equal(racialBonusTrackers(bonuses,5)[0].max,5);
 assert.equal(available(bonuses,'save:wis').length,3);
 assert.equal(available(bonuses,'attack_hit:test').length,3);
 assert.equal(available(bonuses,'initiative').length,0,'initiative has no failed check');
 assert.equal(available(bonuses,'attack_damage:test').length,0);
 assert.deepEqual(project({...c,origin_enabled:{[features[0].origin_id]:false}}).bonuses,[]);
});
test('racial bonuses appear under the source trait, never as permanent formula modifiers',()=>{
 const c=character('Elf','PHB',{subrace:'Mark of Shadow',subrace_source:'ERLW'});
 const out=calculateSheet(c,{speciesConditionalBonuses:rules,classMechanics:{races:[],subraces:[]}});
 const bonus=out.racial_roll_bonuses.find(x=>x.granting_trait==='Cunning Intuition');
 assert(bonus);
 const card=traitBenefitGroups({category:'razza',rank:2,key:out.features.find(f=>f.origin_id===bonus.origin_id).key,
  feature_origin:bonus.origin_id,origin_key:bonus.origin_key},c,out);
 assert(card.some(group=>group.items.some(row=>row.value?.includes('1d4'))));
 assert(!out.automatic_bonuses?.some(x=>x.origin_id===bonus.origin_id));
});


test('PHB Stonecunning and Rock Gnome Artificer Lore replace, never stack, proficiency',()=>{
 for(const c of [
  character('Dwarf','PHB'),
  character('Gnome','PHB',{subrace:'Rock',subrace_source:'PHB'})
 ]){
  const b=project(c).bonuses.filter(x=>x.proficiency_multiplier===2);
  assert.equal(b.length,1);
  const withProfs=owned=>applicableDiceBonuses(c,'skill:history',[],{
   racial_roll_bonuses:b,proficiencies:owned,
   values:{proficiency:4,attunement_max:3},attunements:{counts:[]}
  });
  assert.equal(withProfs([])[0].flat_bonus,8);
  assert.equal(withProfs(['skill:history'])[0].flat_bonus,4);
  assert.equal(withProfs(['skill:history','expertise:history']).length,0);
  assert.equal(applicableDiceBonuses(c,'skill:arcana',[],{
   racial_roll_bonuses:b,proficiencies:[],values:{proficiency:4,attunement_max:3},
   attunements:{counts:[]}
  }).length,0);
  assert.equal(project({...c,rules_version:'2024'}).bonuses.length,0);
 }
});
