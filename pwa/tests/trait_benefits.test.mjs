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
  'bonus','dice','proficiency:skill','proficiency:language','resistance','resources','spells','actions']);
 assert.equal(groups[0].items.length,1);
 assert.equal(groups[0].items[0].value,'+1');
 assert.equal(groups[1].items[0].value,'+1d4');
 assert.equal(groups[3].items[0].label,'elvish');
 assert.equal(groups[4].items[0].label,'Fuoco');
 assert.equal(groups[5].items[0].value,'Max 3 · Riposo lungo');
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
