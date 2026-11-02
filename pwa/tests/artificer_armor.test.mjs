import {classActionOverridesFromBenefits,classRollBonusRulesFromBenefits} from '../class_benefit_catalogs.js';
import {proficiencyTestIndex} from './proficiency_test_fixture.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {classFeatureActivationPatch,classFeatureEntries,classFeatureRollBonuses} from '../feature_mechanics.js';
import {trackerRollBonusRows,trackerRollBonusTargets} from '../sheet_rules_view.js';
import {powerRestSelections} from '../trait_state_rules.js';
import {powerApplicationPatch} from '../power_selection.js';
import {armorerSelectionCatalog,withArmorerGrants,applyArmorerModel} from './helpers/armorer_option_grants.mjs';
import {traitBenefitGroups} from '../trait_benefits.js';
import {recoveryPatch,restRecoveryPreview,completeRest} from '../native_sheet.js';
const read=name=>JSON.parse(readFileSync(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const catalogs={classMechanics:read('class_mechanics'),classFeatures:read('classes'),
 abilityGrants:read('ability_grants'),proficiencyGrants:proficiencyTestIndex(),
 traitStates:[],rollBonusRules:classRollBonusRulesFromBenefits(JSON.parse(readFileSync(new URL('../../vtt/enrichment/benefits/roll_bonus.json',import.meta.url),'utf8'))),
 featureActionOverrides:classActionOverridesFromBenefits(JSON.parse(readFileSync(new URL('../../vtt/enrichment/benefits/action.json',import.meta.url),'utf8')))};
const sheet=(name,level=5,source='PHB',subclass='')=>({kind:'character',rules_version:source==='XPHB'?'2024':'2014',level,
 classes:[{name,level,source,subclass,subclass_source:source}],abilities:{str:10,dex:14,con:18,int:18,wis:18,cha:18},
 inventory:[],armor_natural_formula:'10 + dex_mod'});
test('alternative AC respects traits, equipment, shields and editions',()=>{
 const b=sheet('Barbarian');assert.equal(calculateSheet(b,catalogs).values.ac,16);
 const m=sheet('Monk');assert.equal(calculateSheet(m,catalogs).values.ac,16);
 const shield={id:'shield',type:'S',ac:2,quantity:1,equipped_slots:['off']};
 assert.equal(calculateSheet({...m,inventory:[shield]},catalogs).values.ac,14);
 assert.equal(calculateSheet({...b,inventory:[shield]},catalogs).values.ac,18);
 const disabled=calculateSheet(b,catalogs).features.find(f=>f.name==='Unarmored Defense');
 assert.equal(calculateSheet({...b,proficiency_origins:[{id:disabled.origin_id,disabled:true}]},catalogs).values.ac,12);
 assert.equal(calculateSheet(sheet('Sorcerer',5,'PHB','Draconic Bloodline'),catalogs).values.ac,15);
 assert.equal(calculateSheet(sheet('Sorcerer',5,'XPHB','Draconic Sorcery'),catalogs).values.ac,16);
 assert.equal(calculateSheet(sheet('Bard',5,'XPHB','College of Dance'),catalogs).values.ac,16);
});
test('all four artificer specialists have source-backed Flash of Genius and exact payments',()=>{
 for(const sub of ['Armorer','Alchemist','Artillerist','Battle Smith']){
  const r=sheet('Artificer',15,'TCE',sub),c=calculateSheet(r,catalogs);
  const tracker=c.trackers.find(t=>t.name==='Flash of Genius');assert.equal(tracker?.max,4);
  assert.ok(tracker.origin_id.startsWith('feature:'));
  const patch=classFeatureActivationPatch(r,c,'flash_of_genius');
   assert.equal(patch.resource_tracker_spent[tracker.id],1);
   assert.equal(patch.active_class_features,undefined,'Lampo di genio must be a use, not a toggle');
   const waived=classFeatureActivationPatch(r,c,'flash_of_genius',{tracker_id:''});
   assert.equal(waived.resource_tracker_spent,undefined);
   assert.equal(waived.active_class_features,undefined);
   const stale={...r,active_class_features:{flash_of_genius:{name:'Lampo di genio'}}};
   assert.equal(classFeatureActivationPatch(stale,c,'flash_of_genius').active_class_features.flash_of_genius,undefined);
   assert.equal(c.values.attunement_max,5);
 }
});
test('PHB Fight Club counter aliases open the actual granting subclass trait',()=>{
 for(const [owner,subclass,level,name] of [
  ['Warlock','The Fiend',6,"Dark One's Own Luck"],
  ['Wizard','School of Illusion',10,'Illusory Self'],
  ['Wizard','School of Divination',10,'The Third Eye']
 ]){
  const calculated=calculateSheet(sheet(owner,level,'PHB',subclass),catalogs);
  const row=calculated.trackers.find(tracker=>tracker.name===name);
  assert.ok(row?.origin_id?.startsWith('feature:'),name);
  assert.equal(row.origin_name,'Tratto · '+name);
 }
});
test('Soul of Artifice counts dedicated copies rather than inventory rows',()=>{
 const record=sheet('Artificer',20,'TCE'),baseline=calculateSheet(record,catalogs);
 for(const count of [1,3]){
  const result=calculateSheet({...record,inventory:[{id:'luckstone',name:'Stone of Good Luck',
   quantity:4,req_attune:true,attuned:true,attuned_count:count}]},catalogs);
  assert.equal(result.attunements.used,count);
  for(const ability of ['str','dex','con','int','wis','cha'])
   assert.equal(result.saves[ability],baseline.saves[ability]+count);
 }
});

const armorerCatalogs=withArmorerGrants(catalogs);
const armorerRecord=()=>({...sheet('Artificer',8,'TCE','Armorer'),
 inventory:[{id:'armor',instance_id:'armor',type:'HA',name:'Plate Armor',
  ac:18,quantity:1,equipped_slots:['body']}]});
const modelFor=calculated=>calculated.selection_models.find(row=>row.id.startsWith('armor_model:from:'));
const replaceModel=(record,option)=>{
 const calculated=calculateSheet(record,armorerCatalogs),model=modelFor(calculated);
 assert(model,'Applied Arcane Armor must grant Armor Model');
 return {...record,...powerApplicationPatch(record,{features:calculated.features},
  armorerSelectionCatalog,model.id,option,true)};
};
test('Defensive Field belongs to applied Guardian and respects the temporary HP maximum',()=>{
 const bare=armorerRecord();
 assert(!classFeatureEntries(bare,calculateSheet(bare,armorerCatalogs))
  .some(row=>row.class_feature_id==='defensive_field'));
 const infiltrator=applyArmorerModel(bare,armorerCatalogs,'armor_model:infiltrator');
 const calculated=calculateSheet(infiltrator,armorerCatalogs);
 assert.equal(calculated.attacks.find(row=>row.id==='class_feature:lightning_launcher')?.id,
  'class_feature:lightning_launcher');
 assert.equal(calculated.values.speed,35);
 assert(!classFeatureEntries(infiltrator,calculated).some(row=>row.class_feature_id==='defensive_field'));
 const guardian=replaceModel(infiltrator,'armor_model:guardian');
 const c=calculateSheet(guardian,armorerCatalogs);
 assert(classFeatureEntries(guardian,c).some(row=>row.class_feature_id==='defensive_field'));
 assert.equal(classFeatureActivationPatch(guardian,c,'defensive_field').temporary_hp,8);
 assert.equal(classFeatureActivationPatch({...guardian,temporary_hp:12},c,'defensive_field').temporary_hp,12);
});
test('Armor Model has an exclusive, rest-changeable applied capability, not a separate tracker',()=>{
 let record=applyArmorerModel(armorerRecord(),armorerCatalogs,'armor_model:infiltrator');
 let calculated=calculateSheet(record,armorerCatalogs);
 const selected=modelFor(calculated);
 assert.equal(selected.layers.applied.limit,1);
 assert.equal(selected.layers.applied.trigger,'short_rest');
 assert.equal(selected.layers.applied.used,1);
 assert(!calculated.trackers.some(row=>row.id==='feature:armor_model:activation'));
 assert.equal(calculated.selection_traits[0].name,'Infiltrator');
 assert(calculated.attacks.some(row=>row.id==='class_feature:lightning_launcher'));
 record=replaceModel(record,'armor_model:guardian');
 calculated=calculateSheet(record,armorerCatalogs);
 assert.equal(modelFor(calculated).layers.applied.used,1);
 assert.equal(calculated.selection_traits[0].name,'Guardian');
 assert(calculated.attacks.some(row=>row.id==='class_feature:thunder_gauntlets'));
 assert(!calculated.attacks.some(row=>row.id==='class_feature:lightning_launcher'));
 assert(!calculated.selection_record?.trait_state_selection?.armor_model);
 const lost=calculateSheet({...record,inventory:[]},armorerCatalogs);
 assert(!lost.attacks.some(row=>row.id==='class_feature:thunder_gauntlets'));
 assert.equal(lost.selection_traits.length,0);
});
test('generated model attacks receive source-bound proficiency, withdrawn with their state',()=>{
 for(const [form,attackId,name] of [
  ['armor_model:infiltrator','class_feature:lightning_launcher','Lightning Launcher'],
  ['armor_model:guardian','class_feature:thunder_gauntlets','Thunder Gauntlets']
 ]){
  const record={...applyArmorerModel(armorerRecord(),armorerCatalogs,form),attack_ability:'int'};
  const calculated=calculateSheet(record,armorerCatalogs);
  const attack=calculated.attacks.find(row=>row.id===attackId);
  assert(attack,attackId);
  assert.equal(attack.proficient,true);
  assert.equal(attack.hit,calculated.values['ability_mod:int']+calculated.values.proficiency);
  assert(calculated.proficiencies.includes('weapon:'+name.toLowerCase()));
  const state=calculated.selection_traits.find(row=>row.name=== (form.endsWith('guardian')?'Guardian':'Infiltrator'));
  assert(state);
  assert.equal(calculated.selection_record.attack_grants.find(row=>row.id===attackId)?.origin_id,state.origin_id);
  const disabled=calculateSheet({...record,origin_enabled:{[state.origin_id]:false}},armorerCatalogs);
  assert(!disabled.attacks.some(row=>row.id===attackId));
 }
});
test('short and long rests offer changes to the nested Armor Model without spending resources',()=>{
 const record={...applyArmorerModel(armorerRecord(),armorerCatalogs,'armor_model:guardian'),current_hp:20};
 const c=calculateSheet(record,armorerCatalogs);
 const active=modelFor(c);
 const choice=powerRestSelections(record,c).find(row=>row.id===active.id);
 assert.equal(choice?.recovery,'short_rest');
 assert.equal(record.resource_tracker_spent,undefined);
 const short=restRecoveryPreview(record,'short_rest',c);
 assert(short.entries.some(row=>row.group==='Scelte modificabili'&&row.name.includes('Armor Model')));
 const long=restRecoveryPreview(record,'long_rest',c);
 assert(long.entries.some(row=>row.name.includes('Armor Model')));
 const rested=completeRest(record,'short_rest',c);
 assert.equal(rested.patch.rest_selection_available[active.id],true);
 assert.equal(rested.patch.resource_tracker_spent?.['feature:armor_model:activation'],undefined);
});
test('an applied Lightning Launcher exposes optional extra damage beside its own tracker',()=>{
 const record=applyArmorerModel(armorerRecord(),armorerCatalogs,'armor_model:infiltrator');
 const c=calculateSheet(record,armorerCatalogs);
 const bonus=c.selection_record.dice_bonuses.find(row=>row.attack_id==='class_feature:lightning_launcher');
 assert.equal(bonus?.dice,'1d6');
 assert(c.attacks.some(row=>row.id==='class_feature:lightning_launcher'));
 assert(c.trackers.some(row=>row.id==='feature:lightning_launcher:extra_damage'));
 const flash=trackerRollBonusRows(record,c).find(row=>row.class_feature_id==='flash_of_genius');
 assert(flash);
 assert.equal(flash.flat_bonus,4);
 assert.equal(trackerRollBonusTargets(flash,c),'Prove di caratteristica · Tiri salvezza');
});
test('Lampo di genio is an optional flat INT bonus only on checks and saves',()=>{
 const r=sheet('Artificer',7,'TCE','Armorer'),c=calculateSheet(r,catalogs);
 const expected=c.trackers.find(row=>row.name==='Flash of Genius');
 for(const target of ['skill:athletics','ability_check:int','ability_mod:str','initiative','save:dex','save:con']){
  const [bonus]=classFeatureRollBonuses(r,c,target);
  assert.equal(bonus.flat_bonus,4,target);
  assert.equal(bonus.origin_id,expected.origin_id,target);
  assert.equal(bonus.tracker_id,expected.id,target);
  assert.equal(bonus.class_feature_id,'flash_of_genius',target);
 }
 for(const target of ['attack_hit:unarmed','casting_hit:int','attack_damage:unarmed','spell_damage','hp','passive_perception']){
  assert.deepEqual(classFeatureRollBonuses(r,c,target),[],target);
 }
 const disabled={...r,origin_enabled:{[expected.origin_id]:false}};
 assert.deepEqual(classFeatureRollBonuses(disabled,calculateSheet(disabled,catalogs),'save:dex'),[]);
 const lowInt={...r,abilities:{...r.abilities,int:6}};
 assert.equal(classFeatureRollBonuses(lowInt,calculateSheet(lowInt,catalogs),'save:wis')[0].flat_bonus,1);
});
