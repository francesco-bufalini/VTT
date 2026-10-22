import test from 'node:test';
import assert from 'node:assert/strict';
import {addBenefitPatch,removeBenefitPatch,restoreBenefitPatch,traitOriginId,
 removedBenefitIds} from '../trait_benefit_editor.js';
import {traitBenefitGroups} from '../trait_benefits.js';
import {fixedProficiencies} from '../structured_effects.js';

const trait={key:'feature:arcane|3|gift',name:'Arcane Gift',origin_key:'class|phb|wizard',
 feature_origin:'feature:arcane',category:'classi',level:3};

test('adding a benefit is an explicit pure patch, not a draft autosave',()=>{
 const creature={name:'Wizard',formula_bonuses:[]};
 const patch=addBenefitPatch(creature,trait,'bonus',{target:'initiative',expression:'2'},'trait:0000abcd');
 assert.deepEqual(creature.formula_bonuses,[]);
 assert.equal(patch.formula_bonuses.length,1);
 assert.deepEqual(patch.formula_bonuses[0].origin_id,'feature:trait:'+trait.key);
 assert.deepEqual(patch.formula_bonuses[0].target,'initiative');
 assert.equal(patch.formula_bonuses[0].expression,'2');
 assert.throws(()=>addBenefitPatch(creature,trait,'bonus',{target:'initiative',expression:''},'trait:1234'),/expression/);
});
test('remove needs a stable identity; created rows are removed while original grants are recoverable',()=>{
 const own=addBenefitPatch({},trait,'dice',{target:'ability_check',dice:'1d4'},'trait:abcd1234').dice_bonuses[0];
 const current={dice_bonuses:[own]};
 const removed=removeBenefitPatch(current,trait,{type:'dice',id:'dice:trait:abcd1234'});
 assert.deepEqual(removed.dice_bonuses,[]);
 assert.deepEqual(current.dice_bonuses,[own]);
 const base={formula_bonuses:[{id:'auto|test',automatic:true,target:'initiative',expression:'1'}]};
 const hidden=removeBenefitPatch(base,trait,{type:'bonus',id:'bonus:auto|test'});
 assert.deepEqual(hidden.trait_benefit_removed[trait.key],['bonus:auto|test']);
 assert.deepEqual(base.formula_bonuses[0].id,'auto|test');
 const restored=restoreBenefitPatch({...base,...hidden},trait);
 assert.deepEqual(removedBenefitIds({...base,...restored}),new Set());
});
test('proficiency from the origin is suppressed independently and restored',()=>{
 const source='class|phb|wizard';
 const record={classes:[{name:'Wizard',source:'PHB',level:3}]};
 const index={class:[{name:'Wizard',source:'PHB',
  startingProficiencies:{weapons:['simple','martial']}}]};
 const before=fixedProficiencies(record,index);
 assert.ok(before.has('weapon:simple'));
 assert.ok(before.has('weapon:martial'));
 const removed=removeBenefitPatch(record,trait,{type:'proficiency',
  id:'proficiency:'+source+':weapon:martial'});
 const after=fixedProficiencies({...record,...removed},index);
 assert.ok(after.has('weapon:simple'));
 assert.ok(!after.has('weapon:martial'));
 const restored=fixedProficiencies({...record,...restoreBenefitPatch({...record,...removed},trait)},index);
 assert.ok(restored.has('weapon:martial'));
});
test('all editable benefit types validate their required base inputs',()=>{
 for(const [kind,values,field] of [
  ['proficiency',{proficiency_kind:'weapon',key:'firearms'},'proficiency_choices'],
  ['defenses',{rank:'2',key:'fire'},'damage_defense_entries'],
  ['resources',{name:'Charges',max:'3',recharge:'long_rest'},'resource_trackers'],
  ['spells',{spell_id:'light',payment_mode:'free'},'origin_spell_grants'],
  ['actions',{name:'Hide',action_type:'bonus'},'action_grants']]){
  const patch=addBenefitPatch({},trait,kind,values,'trait:1234abcdef');
  assert.equal(patch[field].length,1);
  assert.equal(patch[field][0].origin_id,'feature:trait:'+trait.key);
 }
 assert.throws(()=>addBenefitPatch({},trait,'resources',{name:'Empty',max:'-1'},'trait:1234'),/massimi/);
});
test('traits with no grant still have no benefit groups; suppression affects its own popup only',()=>{
 const empty={...trait,key:'empty'};
 assert.deepEqual(traitBenefitGroups(empty,{},{}),[]);
 const calculated={bonuses:[{id:'base',origin_id:'feature:trait:'+trait.key,target:'initiative',expression:'1'}]};
 const group=traitBenefitGroups(trait,{},calculated);
 assert.equal(group[0].items[0].id,'bonus:base');
 const record={trait_benefit_removed:{[trait.key]:['bonus:base']}};
 assert.deepEqual(traitBenefitGroups(trait,record,calculated),[]);
 assert.deepEqual(traitBenefitGroups(empty,record,calculated),[],'Sibling trait never inherits this manual bonus');
});
test('a manually added racial benefit belongs to the individual trait, not all species features',()=>{
 const own={...trait,feature_origin:'',category:'razza',origin_key:'species|race-elf|phb'};
 const record={species:'Elf',species_source:'PHB'};
 assert.equal(traitOriginId(own,record),'feature:trait:'+trait.key);
});

test('manual bonuses are visible on their owning individual trait, not on sibling class features',()=>{
 const card={...trait,feature_origin:'',rank:2};
 const sibling={...card,key:card.key+'|sibling',name:'Other Gift'};
 const row=addBenefitPatch({},card,'bonus',{target:'initiative',expression:'2'},'trait:1234abcd').formula_bonuses[0];
 const computed={bonuses:[row]};
 assert.deepEqual(traitBenefitGroups(card,{formula_bonuses:[row]},computed)[0].items.map(item=>item.value),['+2']);
 assert.deepEqual(traitBenefitGroups(sibling,{},computed),[]);
});
