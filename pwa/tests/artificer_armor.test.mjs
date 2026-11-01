import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {classFeatureActivationPatch,classFeatureEntries,classFeatureRollBonuses} from '../feature_mechanics.js';
import {trackerRollBonusRows,trackerRollBonusTargets} from '../sheet_rules_view.js';
import {traitStateActivationPatch,powerRestSelections} from '../trait_state_rules.js';
import {traitBenefitGroups} from '../trait_benefits.js';
import {recoveryPatch,restRecoveryPreview,completeRest} from '../native_sheet.js';
const read=name=>JSON.parse(readFileSync(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const catalogs={classMechanics:read('class_mechanics'),classFeatures:read('classes'),
 abilityGrants:read('ability_grants'),proficiencyGrants:read('proficiency_grants'),
 traitStates:read('trait_states').states,rollBonusRules:read('roll_bonus_rules').features,
 featureActionOverrides:JSON.parse(readFileSync(new URL('../../vtt/data/action_feature_overrides.json',import.meta.url),'utf8')).entries};
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

test('Defensive Field requires guardian armor and keeps the larger temporary HP pool',()=>{
 const r=sheet('Artificer',8,'TCE','Armorer');
 assert.ok(!classFeatureEntries(r,calculateSheet(r,catalogs)).some(a=>a.class_feature_id==='defensive_field'));
 r.inventory=[{id:'armor',type:'HA',ac:18,quantity:1,equipped_slots:['body']}];
 const infiltrator=calculateSheet({...r,trait_state_selection:{armor_model:'armor_model:infiltrator'},attack_ability:'int'},catalogs);
 assert.equal(infiltrator.attacks.find(a=>a.id==='class_feature:lightning_launcher')?.id,'class_feature:lightning_launcher');
 assert.equal(infiltrator.attacks.find(a=>a.id==='class_feature:lightning_launcher')?.damage,'1d6 + 4');
 assert.equal(infiltrator.values.speed,35);
 const guardian={...r,trait_state_selection:{armor_model:'armor_model:guardian'}};
 const c=calculateSheet(guardian,catalogs),patch=classFeatureActivationPatch(guardian,c,'defensive_field');
 assert.equal(patch.temporary_hp,8);
 assert.equal(classFeatureActivationPatch({...guardian,temporary_hp:12},c,'defensive_field').temporary_hp,12);
});

test('Armor Model is a source-bound, reversible and exclusive state privilege',()=>{
 const r=sheet('Artificer',8,'TCE','Armorer');
 r.inventory=[{id:'armor',type:'HA',ac:18,quantity:1,equipped_slots:['body']}];
 r.power_applications={arcane_armor:[{id:'arcane_armor',target_item_id:'armor'}]};
 const catalog=catalogs.traitStates;
 let calculated=calculateSheet(r,catalogs);
 assert.ok(calculated.state_actions.some(row=>row.state_id==='armor_model:guardian'));
 assert.equal(calculated.trackers.some(row=>row.id==='feature:armor_model:activation'),false,
   'Armor Model is a rest-based choice, not a resource tracker');
 assert.equal(catalog.filter(row=>row.group==='armor_model').every(row=>row.selection_recovery==='short_rest'),true);
 let next={...r,...traitStateActivationPatch(r,calculated.features,catalog,'armor_model:infiltrator',calculated.trackers)};
 assert.equal(next.resource_tracker_spent,undefined);
 assert.equal(next.rest_selection_available,undefined);
 calculated=calculateSheet(next,catalogs);
 assert.equal(calculated.attacks.find(a=>a.id.startsWith('class_feature:'))?.id,'class_feature:lightning_launcher');
 assert.equal(calculated.values.speed,35);
 assert.equal(calculated.trait_state_optional_dice[0].dice,'1d6');
 const launcher=calculated.features.find(row=>row.name==='Lightning Launcher');
 assert.ok(launcher?.origin_id,'The launcher must be granted by its own trait');
 const suppressed=calculateSheet({...next,origin_enabled:{[launcher.origin_id]:false}},catalogs);
 assert.equal(suppressed.attacks.some(row=>row.id==='class_feature:lightning_launcher'),false);
 assert.equal(suppressed.trait_state_optional_dice.length,0);
 assert.equal(suppressed.trackers.some(row=>row.id==='feature:lightning_launcher:extra_damage'),false);
 assert.equal(calculated.trackers.find(row=>row.id==='feature:lightning_launcher:extra_damage')?.max,1);
 assert.equal(calculated.active_feature_effects.filter(row=>row.category==='stato').length,1);
 const changed=traitStateActivationPatch(next,calculated.features,catalog,'armor_model:guardian',calculated.trackers);
 assert.equal(changed.rest_selection_available,undefined);
 next={...next,...changed};
 assert.equal(next.resource_tracker_spent?.['feature:armor_model:activation'],undefined,
  'Changing Armor Model never spends an activation tracker, even if a rest normalized the spent map');
 calculated=calculateSheet(next,catalogs);
 assert.equal(calculated.attacks.find(a=>a.id.startsWith('class_feature:'))?.id,'class_feature:thunder_gauntlets');
 assert.equal(calculated.trait_state_optional_dice.length,0);
 assert.equal(calculated.active_trait_state_ids.length,1);
 const disabled={...next,inventory:[]};
 assert.equal(calculateSheet(disabled,catalogs).attacks.some(row=>row.id==='class_feature:thunder_gauntlets'),false);
});

test('state-created weapons receive source-bound training and use ordinary attack proficiency',()=>{
 for(const [state,attackId,weaponName] of [
  ['armor_model:infiltrator','class_feature:lightning_launcher','Lightning Launcher'],
  ['armor_model:guardian','class_feature:thunder_gauntlets','Thunder Gauntlets']
 ]){
  const r={...sheet('Artificer',8,'TCE','Armorer'),attack_ability:'int',
   inventory:[{id:'armor',type:'HA',ac:18,quantity:1,equipped_slots:['body']}],
   power_applications:{arcane_armor:[{id:'arcane_armor',target_item_id:'armor'}]},
   trait_state_selection:{armor_model:state}};
  const calculated=calculateSheet(r,catalogs),key='weapon:'+weaponName.toLowerCase();
  const attack=calculated.attacks.find(row=>row.id===attackId);
  const trait=calculated.features.find(row=>row.name===weaponName);
  assert(attack,attackId+' must be granted by its currently selected state');
  assert(trait?.origin_id,weaponName+' must have a real source trait');
  assert(calculated.proficiencies.includes(key),weaponName+' must grant its own named weapon training');
  assert(calculated.proficiency_sources[key]?.some(row=>row.id===trait.origin_id),
   'Weapon training must be attributed to the concrete granting trait');
  assert.equal(attack.weapon_category,'simple');
  assert.equal(attack.proficient,true);
  assert.equal(attack.hit,calculated.values['ability_mod:int']+calculated.values.proficiency,
   'A trained feature weapon gets exactly one proficiency bonus');
  const benefitGroups=traitBenefitGroups({key:trait.key,feature_origin:trait.origin_id,
   origin_key:trait.origin_key},r,calculated);
  assert(benefitGroups.some(group=>group.type==='proficiency'&&group.items.some(row=>
   String(row.value).toLowerCase().includes(weaponName.toLowerCase()))),
   'The source trait must list the granted proficiency');
  const muted=calculateSheet({...r,origin_enabled:{[trait.origin_id]:false}},catalogs);
  assert(!muted.proficiencies.includes(key),'Disabling the source revokes its proficiency');
  assert(!muted.attacks.some(row=>row.id===attackId),'Disabling the source also revokes its attack');
 }
});
test('Armor Model can be reselected before a rest with no resource payment',()=>{
 const r=sheet('Artificer',8,'TCE','Armorer');
 r.inventory=[{id:'armor',type:'HA',ac:18,quantity:1,equipped_slots:['body']}];
 r.trait_state_selection={armor_model:'armor_model:infiltrator'}; // Existing character already has a choice.
 let calculated=calculateSheet(r,catalogs),catalog=catalogs.traitStates;
 const changes=traitStateActivationPatch(r,calculated.features,catalog,'armor_model:guardian',calculated.trackers);
 assert.equal(changes.resource_tracker_spent,undefined);
 assert.equal(changes.rest_selection_available,undefined);
 const rested=recoveryPatch(r,'long_rest',calculated.trackers,calculated);
 assert.equal(rested.rest_selection_available.armor_model,true);
});
test('Powers selection rests are separate from tracker recovery and enumerate available changes',()=>{
 const record={...sheet('Artificer',8,'TCE','Armorer'),
   current_hp:20,inventory:[{id:'armor',type:'MA',ac:14,quantity:1,equipped_slots:['body']}]};
 const calc=calculateSheet(record,catalogs);
 const choices=powerRestSelections(record,calc);
 const armor=choices.find(row=>row.id==='armor_model');
 assert.equal(armor?.recovery,'short_rest');
 const magic=choices.filter(row=>row.id.startsWith('spells:'));
 assert(magic.every(row=>row.recovery==='long_rest'));
 assert(!calc.trackers.some(row=>row.id==='feature:armor_model:activation'));
 const short=restRecoveryPreview(record,'short_rest',calc);
 assert(short.entries.some(row=>row.group==='Scelte modificabili'&&row.name==='Armor Model'));
 assert(!short.entries.some(row=>row.group==='Scelte modificabili'&&row.name.includes('preparazione')));
 const long=restRecoveryPreview(record,'long_rest',calc);
 assert(long.entries.some(row=>row.group==='Scelte modificabili'&&row.name==='Armor Model'));
 for(const group of magic)assert(long.entries.some(row=>row.name===group.name));
 const completed=completeRest(record,'short_rest',calc);
 assert.equal(completed.patch.rest_selection_available.armor_model,true);
 assert.equal(completed.patch.resource_tracker_spent?.['feature:armor_model:activation'],undefined);
});
test('tracker resources describe both structured flat and attack-specific dice bonuses',()=>{
 const artificer=sheet('Artificer',8,'TCE','Armorer');
 artificer.inventory=[{id:'armor',type:'HA',ac:18,quantity:1,equipped_slots:['body']}];
 const record={...artificer,trait_state_selection:{armor_model:'armor_model:infiltrator'}};
 const calculated=calculateSheet(record,catalogs);
 const rows=trackerRollBonusRows(record,calculated);
 const flash=rows.find(row=>row.class_feature_id==='flash_of_genius');
 assert.equal(flash.flat_bonus,4);
 assert.equal(flash.tracker_id,'class:artificer:tce:flash_of_genius');
 assert.equal(trackerRollBonusTargets(flash,calculated),'Prove di caratteristica · Tiri salvezza');
 const lightning=rows.find(row=>row.tracker_id==='feature:lightning_launcher:extra_damage');
 assert.ok(lightning,JSON.stringify({optional_dice:calculated.trait_state_optional_dice,
  trackers:calculated.trackers.filter(r=>String(r.id).includes('lightning')),
  rows:rows.filter(r=>String(r.tracker_id).includes('lightning'))}));
 assert.equal(lightning.dice,'1d6');
 assert.match(trackerRollBonusTargets(lightning,calculated),/Danni · Lightning Launcher/);
 // The engine must also display a new data-defined bonus without bespoke JS.
 const custom={...catalogs,rollBonusRules:[...catalogs.rollBonusRules,{
  id:'test_check_bonus',class_name:'Artificer',class_source:'TCE',
  feature_name:'Flash of Genius',label:'Bonus sintetico',
  mode:'context',resource_name:'Flash of Genius',cost:1,
  bonus:{name:'Bonus sintetico',targets:['saving_throw'],dice:'1d4'}
 }]};
 const expanded=calculateSheet(record,custom);
 const extra=trackerRollBonusRows(record,expanded).find(row=>row.id==='class_feature:test_check_bonus');
 assert.equal(extra?.dice,'1d4');
 assert.equal(trackerRollBonusTargets(extra,expanded),'Tiri salvezza');
 assert.equal(classFeatureRollBonuses(record,expanded,'save:wis').some(row=>row.id===extra.id),true);
 assert.equal(classFeatureRollBonuses(record,expanded,'skill:arcana').some(row=>row.id===extra.id),false);
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
