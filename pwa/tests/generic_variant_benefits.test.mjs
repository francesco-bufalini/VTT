import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {genericVariantPatch,hydrateGenericVariants,resolveOwnedItem,requiresAttunement,
 itemOptionNumericBonuses,infusionChargeTrackers} from '../item_controls.js';
import {projectItemOptionBenefits} from '../power_selection.js';
import {calculateSheet} from '../sheet_rules.js';
import {BENEFIT_TYPES} from '../trait_benefit_editor.js';
const catalog=JSON.parse(readFileSync(new URL('../catalog/generic_item_variants.json',import.meta.url),'utf8'));
const variants=catalog.variants;
const pick=(name,source='DMG')=>{
 const row=variants.find(v=>v.name===name&&v.source===source);
 assert(row,name+'|'+source+' missing');return row;
};
const weapon=()=>({id:'weapon:longsword',instance_id:'sword_1',name:'Longsword',source:'PHB',
 type:'M',damage:'1d8',properties:[],quantity:1,active:true,equipped_slots:['main']});
const armor=()=>({id:'armor:chain_mail',instance_id:'armor_1',name:'Chain Mail',
 type:'HA',source:'PHB',strength:13,stealth:true,quantity:1,active:true,equipped_slots:['body']});
const installed=(item,variant)=>genericVariantPatch({inventory:[item]},0,variant).inventory[0];
const calculated=(item)=>({id:'test',kind:'character',name:'Test',rules_version:'2014',level:1,
 abilities:{str:12,dex:12,con:12,int:12,wis:12,cha:12},inventory:[item]});
const definitions={genericItemVariants:catalog,spells:[{id:'phb2014_jump',name:'Jump',source:'PHB',level:1},
 {id:'phb2014_levitate',name:'Levitate',source:'PHB',level:2}]};

test('generic variants declare only existing primitive benefit kinds, with no prose inference',()=>{
 // The editor's public menu omits 'dice', but dice_bonuses is an existing
 // primitive benefit (used by optional attack damage and other effects).
 const supported=new Set(BENEFIT_TYPES.map(([type])=>type));
 // Dice bonuses already exist in the shared effect projection, even though
 // the manual benefit editor does not expose this primitive in its menu.
 supported.add('dice');
 assert.equal(variants.length,230);
 for(const variant of variants){
  for(const effect of variant.effects||[])assert(supported.has(effect.type),variant.name+': '+effect.type);
 }
 assert.equal(variants.filter(v=>v.numeric_item_bonuses).length>50,true);
 assert.equal(variants.filter(v=>v.effects?.some(effect=>effect.type==='defenses')).length>25,true);
 assert.equal(variants.filter(v=>v.effects?.some(effect=>effect.type==='spells')).length>=10,true);
});

test('numeric item bonuses and defenses are from the same item-bound benefit schema',()=>{
 const sword=installed(weapon(),pick('+1 Weapon'));
 assert.equal(itemOptionNumericBonuses(calculated(sword),sword).bonus_weapon,1);
 const resistant=installed(armor(),pick('Armor of Acid Resistance'));
 const unattuned=projectItemOptionBenefits(calculated(resistant),definitions);
 assert.equal(unattuned.damage_defense_entries?.length||0,0);
 const ready={...resistant,attuned:true,attuned_count:1};
 const effect=projectItemOptionBenefits(calculated(ready),definitions);
 assert.deepEqual(effect.damage_defense_entries.map(row=>[row.rank,row.key]),[[1,'acid']]);
 assert.match(effect.damage_defense_entries[0].origin_id,/^item-option:/);
 assert.equal(effect.formula_bonuses?.length||0,0);
 const sheet=calculateSheet(calculated(ready),definitions);
 assert.equal(sheet.damage_defense_entries.filter(x=>x.key==='acid'&&x.rank===1).length,1,
   'No duplicate legacy defense projection');
 const disabled=projectItemOptionBenefits(calculated({...ready,equipped_slots:[]}),definitions);
 assert.deepEqual(disabled.damage_defense_entries||[],[]);
});

test('saving throws, exact spell costs and charges use existing bonus/spell/tracker benefits',()=>{
 const blade=installed(weapon(),pick('Luck Blade'));
 const bonus=projectItemOptionBenefits(calculated({...blade,attuned:true,attuned_count:1}),definitions);
 assert(bonus.formula_bonuses.some(row=>row.target==='saving_throw'&&row.expression==='+1'));
 assert.equal((bonus.origin_spell_grants||[]).length,0,'Random Wish charges are not invented');
 const added=installed(armor(),pick('Armor of Weightlessness','BMT'));
 const ready={...added,attuned:true,attuned_count:1};
 const record=calculated(ready),benefits=projectItemOptionBenefits(record,definitions);
 const spells=benefits.origin_spell_grants;
 assert.deepEqual(spells.map(row=>[row.spell_id,row.tracker_cost]),[
  ['phb2014_jump',1],['phb2014_levitate',2]]);
 const tracker=infusionChargeTrackers(record);
 assert.equal(tracker.length,1);
 assert(spells.every(row=>row.tracker_id===tracker[0].id&&row.payment_mode==='tracker'));
});

test('old saved instances obtain new typed effects without changing saved data',()=>{
 const original=installed(armor(),pick('Armor of Acid Resistance'));
 const previous={...original,option_extensions:original.option_extensions.map(row=>({
  ...row,definition:{id:row.id,inherits:row.definition.inherits}
 }))};
 const record=calculated({...previous,attuned:true,attuned_count:1});
 const hydrated=hydrateGenericVariants(record,catalog);
 assert.equal(record.inventory[0].option_extensions[0].definition.effects,undefined);
 assert(hydrated.inventory[0].option_extensions[0].definition.effects.some(x=>x.type==='defenses'));
 const sheet=calculateSheet(record,definitions);
 assert(sheet.damage_defense_entries.some(x=>x.key==='acid'&&x.rank===1));
});

test('existing armor mechanics interpret typed stealth and strength field overrides',()=>{
 const mithral=installed(armor(),pick('Mithral Armor'));
 const effective=resolveOwnedItem(mithral);
 assert.equal(effective.stealth,false);
 assert.equal(effective.strength,0);
 assert.equal(requiresAttunement(effective),false);
});
