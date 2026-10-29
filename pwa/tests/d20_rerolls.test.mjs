import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {initialCreature,spendTrackerUses} from '../character_core.js';
import {calculateSheet,featMechanicGrants} from '../sheet_rules.js';
import {availableD20Rerolls,rerollTargetMatches,offerD20Reroll,chooseD20Reroll} from '../d20_rerolls.js';
import {addBenefitPatch,removeBenefitPatch} from '../trait_benefit_editor.js';
import {traitBenefitGroups} from '../trait_benefits.js';
const data=JSON.parse(readFileSync(new URL('../catalog/ability_grants.json',import.meta.url),'utf8'));

test('new characters activate Party by default, monsters do not',()=>{
 const hero=initialCreature('character','Lyria','char-1','owner-1');
 const monster=initialCreature('monster','Idra','monster-1','owner-1');
 assert.equal(hero.party_id,'Party');
 assert.deepEqual(hero.identity_factions,[{value:'Party',active:true}]);
 assert.equal(monster.party_id,'');
 assert.deepEqual(monster.identity_factions,[]);
});
test('typed Lucky grants a paid d20 reroll without any feature-name branch in roll logic',()=>{
 const creature=initialCreature('character','Lyria','char-2','owner-2');
 creature.feats_catalog=[{name:'Lucky',source:'PHB'}];
 const grants=featMechanicGrants(creature,data);
 assert.equal(grants.rerolls.length,1);
 const sheet=calculateSheet(creature,{abilityGrants:data});
 assert.equal(sheet.feat_d20_rerolls.length,1);
 assert.equal(sheet.feat_d20_rerolls[0].tracker_id,'feat:phb:lucky:luck-points');
 const before=availableD20Rerolls(creature,sheet,'save:dex');
 assert.equal(before.length,1);
 assert.equal(availableD20Rerolls(creature,sheet,'damage_roll').length,0);
 const spent=spendTrackerUses(creature,before[0].tracker_id,1,sheet.trackers);
 const after=calculateSheet({...creature,...spent},{abilityGrants:data});
 assert.equal(availableD20Rerolls(creature,after,'save:dex').length,1);
 assert.equal(after.trackers.find(row=>row.id===before[0].tracker_id).spent,1);
});
test('inspiration is a one-use source for all d20 categories and not damage',()=>{
 const hero={inspiration:true};
 const sources=availableD20Rerolls(hero,{},'attack_hit:sword');
 assert.equal(sources[0].payment_mode,'inspiration');
 assert.equal(availableD20Rerolls(hero,{},'skill:stealth').length,1);
 assert.equal(availableD20Rerolls(hero,{},'attack_damage:sword').length,0);
 assert.equal(availableD20Rerolls({...hero,inspiration:false},{},'save:con').length,0);
 assert.equal(rerollTargetMatches('ability_check','initiative'),true);
});
test('additional d20 is preserved, old/new choice changes only the d20 contribution',()=>{
 const outcome={sides:20,count:1,modifier:5,rolls:[4],total:11,notation:'1d20+5+2',
  detail:'d20 [4] = 4 · bonus [2] = 2 · modificatore +5 · totale 11',
  parts:[{name:'d20',notation:'1d20',rolls:[4],subtotal:4},
    {name:'bonus',notation:'+2',rolls:[],subtotal:2,kind:'flat',flat:2}]};
 const offered=offerD20Reroll(outcome,()=>17,{id:'id',origin_name:'Fonte'});
 assert.deepEqual(offered.parts[0].rolls,[4,17]);
 assert.equal(offered.total,11);
 const picked=chooseD20Reroll(offered,'new');
 assert.equal(picked.total,24);
 assert.equal(picked.parts[1].subtotal,2);
 assert.equal(chooseD20Reroll(picked,'previous').total,11);
 assert.throws(()=>offerD20Reroll(outcome,()=>21),/Nuovo d20/);
 assert.equal(outcome.total,11,'Original dice history is immutable');
});
test('a reusable trait can grant an on-one d20 reroll, removed by its own benefit ID',()=>{
 const trait={key:'race|phb|halfling|lucky',name:'Fortuna',origin_key:'species|halfling|phb'};
 const patch=addBenefitPatch({},trait,'d20_reroll',
  {target:'any_d20',trigger:'on_one'},'trait:0123abcd');
 assert.equal(patch.d20_reroll_grants[0].trigger,'on_one');
 const record={...patch};
 const eligible={feat_d20_rerolls:patch.d20_reroll_grants};
 assert.equal(availableD20Rerolls(record,eligible,'save:wis',{parts:[{rolls:[1],subtotal:1}]}).length,1);
 assert.equal(availableD20Rerolls(record,eligible,'save:wis',{parts:[{rolls:[5],subtotal:5}]}).length,0);
 assert(traitBenefitGroups(trait,record,eligible).some(group=>group.type==='d20_rerolls'));
 const removed=removeBenefitPatch(record,trait,{type:'d20_rerolls',id:'d20_reroll:trait:0123abcd'});
 assert.deepEqual(removed.d20_reroll_grants,[]);
});
