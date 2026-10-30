import {infusionLimits} from './fixtures/legacy_infusion_records.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';

import {featureItemGrants,claimFeatureItemPatch,featureItemPowers} from '../feature_item_grants.js';
import {classFeatureRollSources} from '../feature_mechanics.js';

const read=name=>JSON.parse(readFileSync(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const classFeatures=read('classes'),itemRules=read('feature_item_grants').grants;
const mechanics={...read('class_mechanics'),feature_item_grants:itemRules};
const catalogs={classFeatures,classMechanics:mechanics,featureItemGrants:itemRules,
 abilityGrants:read('ability_grants'),proficiencyGrants:read('proficiency_grants'),
 traitStates:read('trait_states').states,rollBonusRules:read('roll_bonus_rules').features};
const art=(level,subclass='Armorer')=>({
 kind:'character',rules_version:'2014',class:'Artificer',class_source:'TCE',level,
 classes:[{name:'Artificer',source:'TCE',level,subclass,subclass_source:'TCE'}],
 abilities:{str:12,dex:14,con:16,int:18,wis:10,cha:10},
 inventory:[]});
const armor={id:'plate',name:'Plate',type:'HA',ac:18,quantity:1,equipped_slots:['body']};

test('Armor Modifications is an owned source-bound item grant with +2 active infusions, not known',()=>{
 const before=art(8),at9=art(9),eight=calculateSheet(before,catalogs),nine=calculateSheet(at9,catalogs);
 assert.equal(featureItemGrants(before,eight.features,itemRules).some(g=>g.id==='artificer-armor-modifications'),false);
 const grant=nine.feature_item_grants.find(g=>g.id==='artificer-armor-modifications');
 assert.ok(grant);assert.equal(grant.origin_id.startsWith('feature:class|tce|artificer|'),true);
 assert.deepEqual(grant.items.map(i=>i.id),['armor-chest','armor-boots','armor-helmet','armor-special-weapon']);
 const first=infusionLimits(at9,mechanics,nine.features);
 assert.equal(first.active,5);
 assert.equal(first.known,6,'Armor Modifications does not grant two extra infusions known');
 let character=at9;
 for(const item of grant.items){
  character={...character,...claimFeatureItemPatch(character,
   calculateSheet(character,catalogs),grant.id,item.id)};
 }
 assert.equal(character.inventory.length,4);
 assert.throws(()=>claimFeatureItemPatch(character,calculateSheet(character,catalogs),
   grant.id,'armor-boots'),/già concesso/i);
 const worn=calculateSheet({...at9,inventory:[armor]},catalogs);
 assert.equal(infusionLimits({...at9,inventory:[armor]},mechanics,worn.features).active,5);
 const muted={...at9,origin_enabled:{[grant.origin_id]:false}};
 const disabled=calculateSheet(muted,catalogs);
 assert.equal(disabled.feature_item_grants.some(g=>g.id===grant.id),false);
 assert.equal(infusionLimits(muted,mechanics,disabled.features).active,3);
});

test('Eldritch Cannon uses the generic item-grant contract and its own paid ability',()=>{
 const record=art(5,'Artillerist'),projection=calculateSheet(record,catalogs);
 const cannon=projection.feature_item_grants.find(g=>g.id==='artificer-eldritch-cannon');
 assert.ok(cannon);assert.equal(cannon.max_owned,1);
 assert.equal(cannon.items.length,3);
 assert.throws(()=>claimFeatureItemPatch(record,projection,cannon.id,'force-ballista'),/usando la capacità/i);
 const next={...record,...claimFeatureItemPatch(record,projection,cannon.id,'force-ballista',
  {activationActionId:'eldritch_cannon'})};
 assert.equal(next.inventory[0].granted_by,cannon.origin_id);
 const replacement={...next,...claimFeatureItemPatch(next,calculateSheet(next,catalogs),cannon.id,'protector',
  {activationActionId:'eldritch_cannon'})};
 assert.equal(replacement.inventory.length,1);
 assert.equal(replacement.inventory[0].feature_item_option_id,'protector');
 assert.equal(calculateSheet(art(2,'Artillerist'),catalogs).feature_item_grants.some(g=>g.id===cannon.id),false);
});

test('Armorer model applies source-bound Stealth advantage and has the Thunder Gauntlets hit effect',()=>{
 const record={...art(9),inventory:[armor],trait_state_selection:{armor_model:'armor_model:guardian'}},guardian=calculateSheet(record,catalogs);
 const gauntlets=guardian.attacks.find(a=>a.id==='class_feature:thunder_gauntlets');
 assert.ok(gauntlets);assert.equal(gauntlets.on_hit_effects?.[0]?.mode,'disadvantage');
 assert.equal(gauntlets.on_hit_effects[0].target,'attack_roll');
 const infiltrator={...record,trait_state_selection:{armor_model:'armor_model:infiltrator'}};
 const stealth=calculateSheet(infiltrator,catalogs);
 assert.ok(stealth.trait_state_roll_modes.some(m=>m.target==='skill:stealth'&&m.mode==='advantage'));
 assert.ok(classFeatureRollSources(infiltrator,stealth,'skill:stealth').some(m=>m.mode==='advantage'));
 assert.equal(classFeatureRollSources(record,guardian,'skill:stealth').some(m=>m.mode==='advantage'),false);
 assert.equal(calculateSheet({...infiltrator,inventory:[]},catalogs).trait_state_roll_modes.length,0);
});

test('The Right Tool for the Job and Bard Performance of Creation reuse grants',()=>{
 const tool=calculateSheet(art(3,'Alchemist'),catalogs).feature_item_grants
   .find(g=>g.id==='artificer-right-tool');
 assert.ok(tool);assert.equal(tool.items[0].name,'Strumenti da artigiano creati');
 const bard={kind:'character',rules_version:'2014',level:3,classes:[
  {name:'Bard',source:'PHB',level:3,subclass:'College of Creation',subclass_source:'TCE'}],
  abilities:{str:10,dex:10,con:10,int:10,wis:10,cha:16},inventory:[]};
 const projection=calculateSheet(bard,catalogs);
 assert.ok(projection.feature_item_grants.some(g=>g.id==='bard-performance-of-creation'));
});

test('Fortified Position unlocks two cannon instances, including identical models, but never three',()=>{
 const record=art(15,'Artillerist');
 const projected=calculateSheet(record,catalogs);
 const cannon=projected.feature_item_grants.find(g=>g.id==='artificer-eldritch-cannon');
 assert.equal(cannon.max_owned,2);
 let updated={...record,...claimFeatureItemPatch(record,projected,cannon.id,'force-ballista',
  {activationActionId:'eldritch_cannon'})};
 updated={...updated,...claimFeatureItemPatch(updated,calculateSheet(updated,catalogs),
  cannon.id,'force-ballista',{activationActionId:'eldritch_cannon'})};
 assert.equal(updated.inventory.length,2);
 assert.notEqual(updated.inventory[0].id,updated.inventory[1].id);
 const powers=featureItemPowers(updated,calculateSheet(updated,catalogs),'command_cannon');
 assert.equal(powers.length,2);
 assert.equal(powers[0].mode,'spell_attack');
 assert.equal(powers[0].damage_dice,'2d8 + 1d8');
 assert.throws(()=>claimFeatureItemPatch(updated,calculateSheet(updated,catalogs),
  cannon.id,'protector',{activationActionId:'eldritch_cannon'}),/Rimuovi prima/i);
});

test('item-granted cannon powers scale from level 9 and vanish without the owned cannon',()=>{
 const before=art(8,'Artillerist'),after=art(9,'Artillerist');
 const first=calculateSheet(before,catalogs),second=calculateSheet(after,catalogs);
 const grant=first.feature_item_grants.find(x=>x.id==='artificer-eldritch-cannon');
 const saved1={...before,...claimFeatureItemPatch(before,first,grant.id,'flamethrower',
  {activationActionId:'eldritch_cannon'})};
 const saved2={...after,...claimFeatureItemPatch(after,second,grant.id,'flamethrower',
  {activationActionId:'eldritch_cannon'})};
 assert.equal(featureItemPowers(saved1,calculateSheet(saved1,catalogs),'command_cannon')[0].damage_dice,'2d8');
 const flame=featureItemPowers(saved2,calculateSheet(saved2,catalogs),'command_cannon')[0];
 assert.equal(flame.damage_dice,'2d8 + 1d8');
 assert.equal(flame.area_length_feet,15);
 assert.equal(featureItemPowers(after,second,'command_cannon').length,0);
 const protector={...after,...claimFeatureItemPatch(after,second,grant.id,'protector',
  {activationActionId:'eldritch_cannon'})};
 const power=featureItemPowers(protector,calculateSheet(protector,catalogs),'command_cannon')[0];
 assert.equal(power.mode,'temporary_hp_area');
 assert.equal(power.temp_hp,'1d8 + int_mod');
});
