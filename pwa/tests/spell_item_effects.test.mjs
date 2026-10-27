import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {spellItemRules,spellItemTargetSelector,spellItemDamageTypes,itemSpellCastPatch,endItemSpellPatch} from '../spell_item_effects.js';
import {effectExtensionsFor} from '../effect_extensions.js';
import {concentrationEndPatch} from '../concentration_rules.js';
import {calculateSheet} from '../sheet_rules.js';
const catalog=JSON.parse(readFileSync(new URL('../catalog/effect_extensions.json',import.meta.url),'utf8')).extensions;
const sheet=record=>calculateSheet(record,{effectExtensions:catalog});
const weapon=(id,opts={})=>({id:'weapon:sword',instance_id:id,name:'Sword',type:'M',
  custom_item_type:'weapon',damage:'1d8',damage_type:'slashing',quantity:1,
  equipped_slots:[],rarity:'none',active:true,...opts});
const creature=()=>({id:'enchanter',kind:'character',name:'Enchanter',rules_version:'2014',
  abilities:{str:16,dex:12,con:12,int:16,wis:12,cha:10},classes:[],
  inventory:[weapon('one',{equipped_slots:['main']}),weapon('two')],
  conditions:[],concentrating_spell_id:'',active_item_spell_effects:[]});
const magic={id:'magic_weapon_phb',name:'Magic Weapon',source:'PHB',level:2,duration:[{concentration:true,duration:{type:'hour',amount:1}}]};
const fire={id:'homebrew_fire',name:'Arma Infuocata',source:'HB',level:2,requires_concentration:true};
const granted=(record,spell,slotLevel=2,damageType='')=>{
 const rules=spellItemRules(catalog,spell,'2014');
 const selection={id:spell.id,item_target:{inventory_index:0,item_id:'weapon:sword',instance_id:'one'},
  item_damage_type:damageType};
 return {...record,...itemSpellCastPatch(record,selection,spell,rules,slotLevel,{castId:'cast_1'})};
};

test('Magic Weapon automatically enchants only one physical item, including its attack and damage',()=>{
 const before=creature(),base=sheet(before);
 const rules=spellItemRules(catalog,magic,'2014');
 assert.equal(rules.length,2);
 assert.deepEqual(spellItemTargetSelector(magic,rules),{kinds:['weapon'],nonmagical:true});
 const record=granted(before,magic,2),calculated=sheet(record);
 const attack=calculated.attacks.find(row=>row.id==='item:weapon:sword');
 const previous=base.attacks.find(row=>row.id==='item:weapon:sword');
 assert.equal(attack.hit,previous.hit+1);
 assert.equal(attack.damage_extra_modifier,previous.damage_extra_modifier+1);
 assert.equal(attack.damage_extras?.length||0,0);
 assert.equal(calculated.effect_extensions.filter(row=>row.cast_id==='cast_1').length,2);
 assert.equal(effectExtensionsFor(calculated.effect_extensions,
  {kind:'item',id:'weapon:sword',inventory_index:1,instance_id:'two'}).length,0);
 assert.equal(record.inventory[1].instance_id,'two');
});

test('upcast Magic Weapon resolves the structured slot bonus and vanishes with concentration',()=>{
 const before=creature();
 const record=granted(before,magic,6),calculated=sheet(record);
 const baseline=sheet(before).attacks.find(row=>row.id==='item:weapon:sword');
 assert.equal(calculated.attacks.find(row=>row.id==='item:weapon:sword').hit,baseline.hit+3);
 const stopped={...record,...concentrationEndPatch(record)};
 assert.equal(stopped.active_item_spell_effects.length,0);
 assert.equal(sheet(stopped).attacks.find(row=>row.id==='item:weapon:sword').hit,baseline.hit);
});

test('elemental enchantment adds typed dice to the actual weapon damage roll',()=>{
 const record=creature();
 const spell={id:'elemental_weapon_phb',name:'Elemental Weapon',source:'PHB',level:3};
 const rules=spellItemRules(catalog,spell,'2014');
 assert.deepEqual(spellItemDamageTypes(rules),['acid','cold','fire','lightning','thunder']);
 assert.throws(()=>itemSpellCastPatch(record,{item_target:{inventory_index:0,item_id:'weapon:sword',instance_id:'one'}},spell,rules,3,{castId:'cast_e'}),/tipo di danno/);
 const enchanted={...record,...itemSpellCastPatch(record,{
  item_target:{inventory_index:0,item_id:'weapon:sword',instance_id:'one'},item_damage_type:'fire'
 },spell,rules,3,{castId:'cast_e'})};
 const attack=sheet(enchanted).attacks.find(row=>row.id==='item:weapon:sword');
 assert.equal(attack.damage_extras.length,1);
 assert.equal(attack.damage_extras[0].dice,'1d4');
 assert.equal(attack.damage_extras[0].damage_type,'fire');
 assert.match(attack.damage_roll_formula,/\+ 1d4$/);
 assert.equal(attack.hit,sheet(record).attacks.find(row=>row.id==='item:weapon:sword').hit+1);
});

test('Arma Infuocata has a catalog-driven fire extension, not a hardcoded spell check',()=>{
 const spell=fire,record=granted(creature(),spell);
 const attack=sheet(record).attacks.find(row=>row.id==='item:weapon:sword');
 assert.deepEqual(attack.damage_extras.map(row=>[row.dice,row.damage_type]),[['1d6','fire']]);
 const withoutConcentration={...record,conditions:[],concentrating_spell_id:''};
 assert.equal(sheet(withoutConcentration).attacks.find(row=>row.id==='item:weapon:sword').damage_extras?.length||0,0);
});

test('stacked targets split into independent inventory instances; unequipping does not spread a buff',()=>{
 const before=creature();before.inventory=[weapon('one',{quantity:3,equipped_slots:['main']})];
 const rules=spellItemRules(catalog,magic,'2014');
 const applied=itemSpellCastPatch(before,{item_target:{
  inventory_index:0,item_id:'weapon:sword',instance_id:'one'}},magic,rules,2,
  {castId:'cast_1',otherInstanceId:'other'});
 assert.equal(applied.inventory.length,2);
 assert.equal(applied.inventory[0].quantity,1);
 assert.equal(applied.inventory[1].quantity,2);
 assert.equal(applied.inventory[1].instance_id,'other');
 assert.deepEqual(applied.inventory[1].equipped_slots,[]);
 assert.equal(sheet({...before,...applied}).effect_extensions.length,2);
 const removed={...before,...applied,...endItemSpellPatch({...before,...applied},'cast_1')};
 assert.equal(sheet(removed).effect_extensions.length,0);
});

test('homebrew spells may declare inline typed enchantments and explicit item selector',()=>{
 const spell={id:'homebrew:owner:spells:custom',name:'Empowered Sword',level:1,
  item_target_selector:{kinds:['weapon']},item_effect_extensions:[
   {operation:'bonus_damage',value:'2d6',damage_type:'lightning',trigger:'on_hit'}
  ]};
 const rules=spellItemRules(catalog,spell,'2014');
 assert.equal(rules.length,1);
 const record=creature(),patch=itemSpellCastPatch(record,
  {item_target:{inventory_index:0,item_id:'weapon:sword',instance_id:'one'}},spell,rules,1,
  {castId:'homebrew'});
 assert.deepEqual(sheet({...record,...patch}).attacks.find(x=>x.id==='item:weapon:sword')
  .damage_extras.map(x=>x.dice),['2d6']);
 assert.throws(()=>itemSpellCastPatch(record,
  {item_target:{inventory_index:1,item_id:'weapon:sword',instance_id:'wrong'}},spell,rules,1,
  {castId:'bad'}),/bersaglio valido/);
});

test('only the concentration cast is replaced, and non-concentration effects remain',()=>{
 const source=creature();
 const spell={id:'non_conc',name:'Enduring Edge',level:1,item_target_selector:{kinds:['weapon']},
   item_effect_extensions:[{operation:'attack_bonus',value:'2'}]};
 const rule=spellItemRules([],spell,'2014');
 const enduring={...source,...itemSpellCastPatch(source,{item_target:{
  inventory_index:0,item_id:'weapon:sword',instance_id:'one'}},spell,rule,1,{castId:'lasting'})};
 const enhanced={...enduring,...itemSpellCastPatch(enduring,{item_target:{
  inventory_index:0,item_id:'weapon:sword',instance_id:'one'}},magic,
  spellItemRules(catalog,magic,'2014'),2,{castId:'concentrated'})};
 assert.equal(enhanced.active_item_spell_effects.length,2);
 const replaced={...enhanced,...itemSpellCastPatch(enhanced,{item_target:{
  inventory_index:0,item_id:'weapon:sword',instance_id:'one'}},fire,
  spellItemRules(catalog,fire,'2014'),2,{castId:'new_concentration'})};
 assert.deepEqual(replaced.active_item_spell_effects.map(row=>row.id),['lasting','new_concentration']);
});
