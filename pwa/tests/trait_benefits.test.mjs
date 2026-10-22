import test from 'node:test';
import assert from 'node:assert/strict';
import {signedTraitFormula,traitBenefitGroups} from '../trait_benefits.js';

test('signed formulas preserve negative signs and show a single positive prefix',()=>{
 assert.equal(signedTraitFormula('1 + proficiency'),'+1 + proficiency');
 assert.equal(signedTraitFormula('+1'),'+1');
 assert.equal(signedTraitFormula('-2'),'-2');
 assert.equal(signedTraitFormula('−2'),'−2');
 assert.equal(signedTraitFormula('1d4'),'+1d4');
});
test('benefits are grouped and attached only to their own trait',()=>{
 const trait={feature_origin:'feature:stone',origin_key:'item:stone',category:'oggetti',rank:0,
  granted_spells:[{id:'light',name:'Light',level:0}]};
 const record={dice_bonuses:[{origin_id:'feature:stone',target:'ability_check',dice:'1d4'}],
  damage_defense_entries:[{origin_id:'feature:stone',key:'fire',rank:1}],
  action_grants:[{origin_id:'feature:stone',name:'Azione speciale'}]};
 const calculated={
  bonuses:[{id:'b1',origin_id:'feature:stone',target:'saving_throw',expression:'1'},
   {id:'other',origin_id:'feature:else',target:'ac',expression:'10'}],
  automatic_bonuses:[{id:'b1',origin_id:'feature:stone',target:'saving_throw',expression:'1'}],
  proficiency_sources:{'skill:perception':[{id:'feature:stone'}],
   'language:elvish':[{id:'feature:stone'}],'skill:arcana':[{id:'feature:else'}]},
  trackers:[{id:'t',origin_id:'feature:stone',name:'Cariche',max:3,recharge:'long_rest'}]
 };
 const groups=traitBenefitGroups(trait,record,calculated);
 assert.deepEqual(groups.map(group=>group.type),[
  'bonus','dice','proficiency','resistance','resources','spells','actions']);
 assert.equal(groups[0].items.length,1);
 assert.equal(groups[0].items[0].value,'+1');
 assert.equal(groups[0].items[0].id,'b1','bonus rows keep their editor target');
 assert.equal(groups[1].items[0].value,'+1d4');
 assert.deepEqual(groups[2].items.map(item=>[item.label,item.value]),[
  ['Abilità','Percezione'],['Lingue','elvish']]);
 assert.equal(groups[3].items[0].label,'Fuoco');
 assert.equal(groups[4].items[0].value,'Max 3 · Riposo lungo');
 assert.ok(!JSON.stringify(groups).includes('Arcano'));
});
test('feature-granted numeric and active effects stay on exact feature; unrelated trait stays empty',()=>{
 const c={bonuses:[{id:'b',origin_id:'feature:rage',target:'damage_roll',expression:'-2'}],
  active_feature_effects:[{origin_id:'feature:rage',effective:true,name:'Ira',summary:'Resistenza'}]};
 assert.deepEqual(traitBenefitGroups({feature_origin:'feature:other'}, {},c),[]);
 const groups=traitBenefitGroups({feature_origin:'feature:rage'}, {},c);
 assert.equal(groups[0].items[0].value,'-2');
 assert.equal(groups[1].type,'effects');
});

test('all proficiencies share one group ordered by kind then name',()=>{
 const trait={feature_origin:'feature:training'};
 const calculated={proficiency_sources:{
  'language:draconic':[{id:'feature:training'}],
  'weapon:longsword':[{id:'feature:training'}],
  'skill:stealth':[{id:'feature:training'}],
  'save:dex':[{id:'feature:training'}],
  'skill:arcana':[{id:'feature:training'}],
  'tool:thieves tools':[{id:'feature:training'}],
  'expertise:perception':[{id:'feature:training'}],
  'armor:light':[{id:'feature:training'}]
 }};
 const group=traitBenefitGroups(trait,{},calculated);
 assert.equal(group.length,1);
 assert.equal(group[0].type,'proficiency');
 assert.deepEqual(group[0].items.map(row=>[row.label,row.value]),[
  ['Abilità','Arcano'],['Abilità','Furtività'],['Maestria','Percezione'],
  ['Tiri salvezza','Destrezza'],['Armi','longsword'],['Armature','light'],
  ['Strumenti','thieves tools'],['Lingue','draconic']
 ]);
});

test('species overview never includes subrace grants, and vice versa',()=>{
 const record={species:'Elf',species_source:'PHB',subrace:'High Elf',subrace_source:'PHB'};
 const calculated={
  bonuses:[{id:'base',origin_id:'race|phb|elf',target:'speed',expression:'5'},
   {id:'sub',origin_id:'subrace|phb|high elf',target:'ability:int',expression:'1'}],
  proficiency_sources:{
   'skill:perception':[{id:'race|phb|elf'}],
   'language:elvish':[{id:'subrace|phb|high elf'}]
  }
 };
 const species=traitBenefitGroups({category:'razza',rank:0,
  origin_key:'species|some-id|phb'},record,calculated);
 const subrace=traitBenefitGroups({category:'razza',rank:0,
  origin_key:'subrace|phb|high elf'},record,calculated);
 assert.equal(species.some(group=>group.items.some(item=>item.id==='sub'||item.value==='elvish')),false);
 assert.equal(subrace.some(group=>group.items.some(item=>item.id==='base'||item.value==='Percezione')),false);
 assert.equal(species.find(group=>group.type==='bonus').items[0].id,'base');
 assert.equal(subrace.find(group=>group.type==='bonus').items[0].id,'sub');
});