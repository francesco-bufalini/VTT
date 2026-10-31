import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {genericVariantMatches,genericVariantPatch,ownedItemDisplayName,resolveOwnedItem,
 itemOptionNumericBonuses,requiresAttunement} from '../item_controls.js';
const catalog=JSON.parse(readFileSync(new URL('../catalog/generic_item_variants.json',import.meta.url),'utf8'));
const choice=(name,source='DMG')=>catalog.variants.find(row=>row.name===name&&row.source===source);
const sword=()=>({id:'weapon:longsword',instance_id:'blade-1',name:'Longsword',
 source:'PHB',type:'M',weapon_category:'martial',damage:'1d8',quantity:3,active:true,equipped_slots:['main']});
const armor=()=>({id:'armor:chain',instance_id:'chain-1',name:'Chain Mail',
 source:'PHB',type:'HA',quantity:1,active:true,equipped_slots:['body']});

test('all 5eTools generic variants are packaged with explicit source and inheritance',()=>{
 assert.equal(catalog.version,1);
 assert(catalog.variants.length>=200);
 assert.equal(new Set(catalog.variants.map(row=>row.id)).size,catalog.variants.length);
 assert(choice('+1 Weapon'));assert(choice('+1 Armor'));
 assert(catalog.variants.some(row=>row.name==='All-Seeing Blade of the Guardian'&&row.inherits.namePrefix==='All-Seeing '));
});

test('5eTools requires/excludes are evaluated against the item before extending',()=>{
 assert(genericVariantMatches(sword(),choice('+1 Weapon')));
 assert(!genericVariantMatches(armor(),choice('+1 Weapon')));
 assert(genericVariantMatches(armor(),choice('+1 Armor')));
 assert(!genericVariantMatches({...sword(),name:'Net'},choice('+1 Weapon')));
 assert(!genericVariantMatches(sword(),{requires:[{type:'M|XPHB'}]}));
 assert(genericVariantMatches(sword(),{requires:[{weapon:true},{armor:true}],excludes:{net:true}}));
 assert(!genericVariantMatches(sword(),{requires:[{name:'Rapier',source:'PHB'}]}));
});

test('variant application splits one physical stack, adds multiple extensions and preserves the base object',()=>{
 const original=sword(),record={inventory:[original,armor()]};
 const first=genericVariantPatch(record,0,choice('+1 Weapon'),true);
 assert.equal(first.index,1);
 assert.equal(first.inventory.length,3);
 assert.equal(first.inventory[0].quantity,2);
 assert.equal(first.inventory[1].quantity,1);
 assert.notEqual(first.inventory[1].instance_id,original.instance_id);
 assert.deepEqual(first.inventory[1].equipped_slots,['main']);
 assert.equal(record.inventory[0].quantity,3);
 assert.equal(itemOptionNumericBonuses({...record,inventory:[first.inventory[1]]},first.inventory[1]).bonus_weapon,1);
 const second=genericVariantPatch({inventory:first.inventory},first.index,choice('+2 Weapon'),true);
 const applied=second.inventory[1];
 assert.equal(applied.option_extensions.length,2);
 assert.match(ownedItemDisplayName(applied),/Longsword - .*\+1 Weapon.*\+2 Weapon/);
 assert.throws(()=>genericVariantPatch({inventory:second.inventory},1,choice('+1 Weapon'),true),/già applicata/);
 assert.equal(second.inventory[0].option_extensions?.length||0,0);
 const removed=genericVariantPatch({inventory:second.inventory},1,choice('+1 Weapon'),false);
 assert.deepEqual(removed.inventory[1].option_extensions.map(row=>row.name),['+2 Weapon']);
 assert.equal(removed.inventory[1].name,'Longsword');
 assert.equal(second.inventory[1].option_extensions.length,2);
});

test('item variant extensions reuse per-instance attunement, property and numeric rules',()=>{
 const prototype={id:'generic-variant:test',name:'Test blade',source:'PHB',
  requires:[{weapon:true}],inherits:{bonusWeaponAttack:'+2',bonusWeaponDamage:'+1',
   propertyAdd:['F'],propertyRemove:['H'],reqAttune:true}};
 const item={...sword(),quantity:1,properties:['H'],attuned:false};
 const changed=genericVariantPatch({inventory:[item]},0,prototype,true).inventory[0];
 assert.equal(requiresAttunement(changed),true);
 assert.deepEqual(resolveOwnedItem(changed).properties,['F']);
 assert.deepEqual(itemOptionNumericBonuses({inventory:[changed]},changed),{});
 const tuned={...changed,attuned:true,attuned_count:1};
 assert.deepEqual(itemOptionNumericBonuses({inventory:[tuned]},tuned),{
  bonus_weapon_attack:2,bonus_weapon_damage:1
 });
});
