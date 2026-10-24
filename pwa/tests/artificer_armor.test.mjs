import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {classFeatureActivationPatch,classFeatureEntries} from '../feature_mechanics.js';
import {traitStateActivationPatch} from '../trait_state_rules.js';
const read=name=>JSON.parse(readFileSync(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const catalogs={classMechanics:read('class_mechanics'),classFeatures:read('classes'),
 abilityGrants:read('ability_grants'),proficiencyGrants:read('proficiency_grants'),
 traitStates:read('trait_states').states};
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
 const infiltrator=calculateSheet({...r,artificer_armor_model:'infiltrator',attack_ability:'int'},catalogs);
 assert.equal(infiltrator.attacks[0].id,'class_feature:lightning_launcher');
 assert.equal(infiltrator.attacks[0].damage,'1d6 + 4');
 assert.equal(infiltrator.values.speed,35);
 const c=calculateSheet(r,catalogs),patch=classFeatureActivationPatch(r,c,'defensive_field');
 assert.equal(patch.temporary_hp,8);
 assert.equal(classFeatureActivationPatch({...r,temporary_hp:12},c,'defensive_field').temporary_hp,12);
});

test('Armor Model is a source-bound, reversible and exclusive state privilege',()=>{
 const r=sheet('Artificer',8,'TCE','Armorer');
 r.inventory=[{id:'armor',type:'HA',ac:18,quantity:1,equipped_slots:['body']}];
 const catalog=catalogs.traitStates;
 let calculated=calculateSheet(r,catalogs);
 assert.ok(calculated.state_actions.some(row=>row.state_id==='armor_model:guardian'));
 let next={...r,...traitStateActivationPatch(r,calculated.features,catalog,'armor_model:infiltrator')};
 calculated=calculateSheet(next,catalogs);
 assert.equal(calculated.attacks[0].id,'class_feature:lightning_launcher');
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
 next={...next,...traitStateActivationPatch(next,calculated.features,catalog,'armor_model:guardian')};
 calculated=calculateSheet(next,catalogs);
 assert.equal(calculated.attacks[0].id,'class_feature:thunder_gauntlets');
 assert.equal(calculated.trait_state_optional_dice.length,0);
 assert.equal(calculated.active_trait_state_ids.length,1);
 const disabled={...next,inventory:[]};
 assert.equal(calculateSheet(disabled,catalogs).attacks.some(row=>row.id==='class_feature:thunder_gauntlets'),false);
});
