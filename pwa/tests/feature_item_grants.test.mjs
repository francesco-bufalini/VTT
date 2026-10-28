import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {infusionLimits} from '../item_controls.js';
import {featureItemGrants,claimFeatureItemPatch} from '../feature_item_grants.js';
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
 assert.equal(first.active,6);
 assert.equal(first.known,8,'Armor Modifications does not grant two extra infusions known');
 let character=at9;
 for(const item of grant.items){
  character={...character,...claimFeatureItemPatch(character,
   calculateSheet(character,catalogs),grant.id,item.id)};
 }
 assert.equal(character.inventory.length,4);
 assert.throws(()=>claimFeatureItemPatch(character,calculateSheet(character,catalogs),
   grant.id,'armor-boots'),/già concesso/i);
 const worn=calculateSheet({...at9,inventory:[armor]},catalogs);
 assert.equal(infusionLimits({...at9,inventory:[armor]},mechanics,worn.features).active,6);
 const muted={...at9,origin_enabled:{[grant.origin_id]:false}};
 const disabled=calculateSheet(muted,catalogs);
 assert.equal(disabled.feature_item_grants.some(g=>g.id===grant.id),false);
 assert.equal(infusionLimits(muted,mechanics,disabled.features).active,4);
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
 assert.throws(()=>claimFeatureItemPatch(next,calculateSheet(next,catalogs),cannon.id,'protector',
  {activationActionId:'eldritch_cannon'}),/precedente oggetto/);
 assert.equal(calculateSheet(art(2,'Artillerist'),catalogs).feature_item_grants.some(g=>g.id===cannon.id),false);
});

test('Armorer model applies source-bound Stealth advantage and has the Thunder Gauntlets hit effect',()=>{
 const record={...art(9),inventory:[armor]},guardian=calculateSheet(record,catalogs);
 const gauntlets=guardian.attacks.find(a=>a.id==='class_feature:thunder_gauntlets');
 assert.ok(gauntlets);assert.equal(gauntlets.on_hit_effects?.[0]?.mode,'disadvantage');
 assert.equal(gauntlets.on_hit_effects[0].target,'attack_roll');
 const infiltrator={...record,artificer_armor_model:'infiltrator'};
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
