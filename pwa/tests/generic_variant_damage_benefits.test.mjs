import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet,applicableDiceBonuses} from '../sheet_rules.js';
import {genericVariantPatch,genericVariantActivationPatch} from '../item_controls.js';
const catalog=JSON.parse(readFileSync(new URL('../catalog/generic_item_variants.json',import.meta.url),'utf8'));
const authored=JSON.parse(readFileSync(new URL('../../scripts/data/generic_variant_damage_benefits.json',import.meta.url),'utf8'));
const get=(name,source='DMG')=>{
 const found=catalog.variants.find(row=>row.name===name&&row.source===source);
 assert(found,name+' ('+source+')');return found;
};
const sword=(id='longsword',slot='main',instance='blade-1')=>({
 id,instance_id:instance,name:'Longsword',source:'PHB',type:'M',damage:'1d8',
 properties:['V'],quantity:1,active:true,equipped_slots:[slot]});
const creature=(inventory)=>({id:'hero',kind:'character',level:4,rules_version:'2014',
 abilities:{str:16,dex:14,con:12,int:10,wis:10,cha:10},inventory});
const install=(item,variant)=>{
 const copy=genericVariantPatch({inventory:[item]},0,variant).inventory[0];
 return {...copy,attuned:true,attuned_count:1};
};
const options=(record,target)=>{
 const calculated=calculateSheet(record,{genericItemVariants:catalog});
 return {calculated,rows:applicableDiceBonuses(record,target,[],calculated)};
};

test('all hand-authored damage variants match distinct 5eTools sources and existing benefit kinds',()=>{
 const keys=new Set();let count=0;
 for(const row of authored.variants){
  for(const source of row.sources){
   const key=row.name+'|'+source;assert(!keys.has(key),key);keys.add(key);count++;
   const variant=get(row.name,source);
   assert(variant.effects?.some(e=>e.type==='dice'||e.type==='actions'),key);
   for(const effect of row.effects){
    assert(['dice','actions'].includes(effect.type),key);
    if(effect.type==='dice'){
     assert.equal(effect.target,'attack_damage');
     assert(effect.dice||Number.isSafeInteger(effect.flat_bonus));
    }
   }
  }
 }
 assert(count>=30);
});

test('Flame Tongue has a bonus-action control and 2d6 fire only while its own effect is activated',()=>{
 const variant=get('Flame Tongue');
 let item=install(sword(),variant),record=creature([item]);
 let result=options(record,'attack_damage:item:longsword');
 assert.equal(result.rows.filter(r=>r.dice==='2d6'&&r.damage_type==='fire').length,0);
 assert(result.calculated.selection_record.action_grants.some(r=>
   r.name.includes('Flame Tongue')&&r.action_type==='bonus'));
 const turnedOn=genericVariantActivationPatch(record,0,variant,true);
 item=turnedOn.inventory[0];record=creature([item]);
 result=options(record,'attack_damage:item:longsword');
 assert.equal(result.rows.filter(r=>r.dice==='2d6'&&r.damage_type==='fire').length,1);
 assert.match(result.rows.find(r=>r.dice==='2d6').condition_label,/fiamme.*accese/);
 assert.equal(options(record,'attack_damage:unarmed').rows.some(r=>r.dice==='2d6'),false);
 item=genericVariantActivationPatch(record,0,variant,false).inventory[0];
 assert.equal(options(creature([item]),'attack_damage:item:longsword').rows.length,0);
});

test('one enchanted copy in the off hand cannot donate damage dice to the main hand',()=>{
 const variant=get('Frost Brand');
 const main=sword('longsword','main','main-instance');
 const off=install(sword('longsword','off','off-instance'),variant);
 const record=creature([main,off]);
 assert.equal(options(record,'attack_damage:item:longsword').rows.some(r=>r.dice==='1d6'&&r.damage_type==='cold'),false);
 const second=options(record,'attack_damage:item:off:longsword');
 assert(second.rows.some(r=>r.dice==='1d6'&&r.damage_type==='cold'));
 const inactive=creature([{...main},{...off,equipped_slots:[]}]);
 assert.equal(options(inactive,'attack_damage:item:off:longsword').rows.length,0);
});

test('critical-only flat damage stays optional rather than modifying ordinary attack damage',()=>{
 const item=install(sword(),get('Vicious Weapon'));
 const record=creature([item]),out=options(record,'attack_damage:item:longsword');
 assert(out.rows.some(r=>r.flat_bonus===7&&/20 naturale/.test(r.condition_label)));
 const attack=out.calculated.attacks.find(r=>r.id==='item:longsword');
 assert(attack);
 assert(!attack.damage.includes('+ 7'),'The conditional extra 7 damage must never become permanent');
});

test('conditional slayer dice are scoped to their own weapon, with the target restriction visible',()=>{
 const item=install(sword(),get('Dragon Slayer'));
 const {rows}=options(creature([item]),'attack_damage:item:longsword');
 assert(rows.some(r=>r.dice==='3d6'&&/drago/.test(r.condition_label)));
 assert.equal(options(creature([item]),'attack_damage:item:off:longsword').rows.length,0);
});

test('Starshot bonus is gated by activation, using the existing tracker-bound action',()=>{
 const crossbow={id:'crossbow',instance_id:'star-1',name:'Heavy Crossbow',source:'PHB',
  type:'R',damage:'1d10',quantity:1,active:true,equipped_slots:['main']};
 const variant=get('Starshot Crossbow','BMT');
 const item=install(crossbow,variant),record=creature([item]);
 let out=options(record,'attack_damage:item:crossbow');
 assert.equal(out.rows.filter(r=>r.dice==='2d8').length,0);
 assert(out.calculated.selection_record.action_grants.some(r=>
   r.name.includes('Flames')&&r.tracker_id&&r.tracker_cost===1));
 const on=genericVariantActivationPatch(record,0,variant,true).inventory[0];
 out=options(creature([on]),'attack_damage:item:crossbow');
 assert(out.rows.some(r=>r.dice==='2d8'&&r.damage_type==='fire'&&r.condition_label.includes('prossimo turno')));
});
