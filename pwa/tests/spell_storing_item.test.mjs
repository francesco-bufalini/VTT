import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {recoveryPatch} from '../native_sheet.js';
import {effectExtensionsFor} from '../effect_extensions.js';
import {eligibleSpellStoringItems,eligibleStoredSpells,storeSpellInItemPatch,
 useStoredSpellPatch,storedSpellExtension,storedSpellTrackerId,spellStoringArtificerLevel
} from '../spell_storing_item.js';

const read=name=>JSON.parse(readFileSync(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const catalogs={classFeatures:read('classes'),classMechanics:read('class_mechanics'),
 abilityGrants:read('ability_grants'),proficiencyGrants:read('proficiency_grants'),
 traitStates:read('trait_states').states,rollBonusRules:read('roll_bonus_rules').features,
 effectExtensions:read('effect_extensions').extensions};
const artificer=(level=11)=>({
 id:'artificer-11',kind:'character',rules_version:'2014',
 classes:[{name:'Artificer',source:'TCE',level}],class:'Artificer',class_source:'TCE',
 level,abilities:{str:10,dex:12,con:14,int:18,wis:10,cha:10},
 inventory:[{id:'longsword',name:'Longsword',type:'M',damage:'1d8',quantity:3},
 {id:'toolkit',name:'Smith\'s Tools',type:'AT',quantity:1},
 {id:'book',name:'Ordinary Book',type:'G',quantity:1}]
});
const spell=(id='absorb-elements')=>({
 id,name:'Spell Name',classes:['Artificer'],level:1,time:[{number:1,unit:'action'}],
 entries:['Full spell description.']
});
const store=(record,item=0,choice=spell())=>{
 const calculated=calculateSheet(record,catalogs);
 return {...record,...storeSpellInItemPatch(record,calculated,item,choice,'Full spell description.',
   'pwa_instance_unique_test')};
};

test('Artificer Spell-Storing Item requires its enabled 2014 TCE level 11 feature',()=>{
 assert.equal(spellStoringArtificerLevel(artificer(10)),10);
 assert.equal(spellStoringArtificerLevel({...artificer(11),rules_version:'2024'}),0);
 assert.throws(()=>store(artificer(10)),/livello 11/);
 assert.ok(calculateSheet(artificer(11),catalogs).features.some(row=>row.name==='Spell-Storing Item'));
});

test('only Artificer level 1/2 action spells, but no preparation requirement',()=>{
 const good=spell(),second={...spell('lv2'),level:2};
 const excluded=[{...spell('cantrip'),level:0},{...spell('third'),level:3},
  {...spell('wizard'),classes:['Wizard']},{...spell('bonus'),time:[{number:1,unit:'bonus'}]}];
 assert.deepEqual(eligibleStoredSpells([good,second,...excluded]).map(row=>row.id),['absorb-elements','lv2']);
 assert.deepEqual(eligibleSpellStoringItems(artificer()).map(row=>row.index),[0,1]);
});

test('stores full text on precisely one physical item copy; replaces instead of duplicating',()=>{
 const owner=artificer(),saved=store(owner);
 assert.equal(saved.inventory.length,4,'The original stack is split without creating any new item type');
 assert.equal(saved.inventory[0].quantity,1);
 assert.equal(saved.inventory[1].quantity,2);
 assert.equal(saved.inventory[0].id,saved.inventory[1].id);
 assert.equal(saved.effect_extensions.length,1);
 const ext=storedSpellExtension(saved);
 assert.equal(ext.operation,'grant_action');
 assert.equal(ext.spell_description,'Full spell description.');
 assert.equal(ext.target_instance_id,saved.inventory[0].instance_id);
 assert.equal(effectExtensionsFor([ext],{
  kind:'item',id:saved.inventory[0].id,instance_id:saved.inventory[0].instance_id,inventory_index:0}).length,1);
 assert.equal(effectExtensionsFor([ext],{
  kind:'item',id:saved.inventory[1].id,instance_id:saved.inventory[1].instance_id,inventory_index:1}).length,0);
 const newStore=store(saved,2,spell('second-spell'));
 assert.equal(newStore.inventory.length,4);
 assert.equal(newStore.effect_extensions.length,1);
 assert.equal(newStore.effect_extensions[0].spell_id,'second-spell');
});

test('uses a 2*INT charge tracker with minimum two, independent of spell slots',()=>{
 let owner=store(artificer());
 let calculated=calculateSheet(owner,catalogs);
 const id=storedSpellTrackerId(owner),t=calculated.trackers.find(row=>row.id===id);
 assert.ok(t);assert.equal(t.max,8);assert.equal(t.recharge,'manual');
 owner={...owner,...useStoredSpellPatch(owner,calculated,0)};
 assert.equal(owner.resource_tracker_spent[id],1);
 assert.equal(owner.spell_slots_spent,undefined);
 assert.throws(()=>useStoredSpellPatch(owner,calculated,2),/non contiene/);
 const reduced={...owner,abilities:{...owner.abilities,int:8}};
 assert.equal(calculateSheet(reduced,catalogs).trackers.find(row=>row.id===id).max,2);
 calculated=calculateSheet(owner,catalogs);
 for(let count=1;count<8;count++){
  owner={...owner,...useStoredSpellPatch(owner,calculated,0)};
  calculated=calculateSheet(owner,catalogs);
 }
 assert.throws(()=>useStoredSpellPatch(owner,calculated,0),/insufficiente/i);
});

test('long rest removes the enchantment and tracker; short rest preserves charges',()=>{
 let owner=store(artificer());
 let calculated=calculateSheet(owner,catalogs);
 owner={...owner,...useStoredSpellPatch(owner,calculated,0)};
 calculated=calculateSheet(owner,catalogs);
 const short=recoveryPatch(owner,'short_rest',calculated.trackers,calculated);
 assert.equal(short.effect_extensions,undefined);
 assert.equal(short.resource_tracker_spent[storedSpellTrackerId(owner)],1);
 const long=recoveryPatch(owner,'long_rest',calculated.trackers,calculated);
 assert.deepEqual(long.effect_extensions,[]);
 assert.equal(long.resource_trackers.some(row=>row.id===storedSpellTrackerId(owner)),false);
 assert.equal(long.resource_tracker_spent[storedSpellTrackerId(owner)],undefined);
 assert.equal(long.inventory,undefined,'A long rest must never remove the physical item');
});
