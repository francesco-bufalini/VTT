import {test} from 'node:test';
import assert from 'node:assert/strict';
import {inventoryReadout} from '../sheet_rules_view.js';
import {addSpellScroll,isSpellScroll,spellScrollName,spellScrollLevel,armorDexterityLimit,armorDexterityBonus,armorDexterityLabel} from '../item_controls.js';
import {calculateSheet} from '../sheet_rules.js';

test('inventory summaries resolve each owned copy and multiply only recorded unit data',()=>{
 const item={id:'local_blade',name:'Spada',custom_item_type:'weapon',damage:'1d6',weight:3,value:1500,quantity:2,equipped_slots:['main'],instance_overrides:{damage:'1d8',weight:4}};
 const before=structuredClone(item),info=inventoryReadout(item,'Accurata · Leggera');
 assert.equal(info.type,'Arma');assert.equal(info.weight,8);assert.equal(info.value,30);
 assert(info.facts.some(row=>row.label==='Danno'&&row.value==='1d8'));
 assert(info.facts.some(row=>row.label==='Peso totale'&&row.value==='8 lb'));
 assert.deepEqual(info.status,['Mano principale']);assert.deepEqual(item,before);
});
test('armor labels match DEX limits used by AC calculation',()=>{
 const light={type:'LA',ac:11,equipped_slots:['body']};
 const medium={type:'MA',ac:14,equipped_slots:['body']};
 const heavy={type:'HA',ac:18,equipped_slots:['body']};
 assert.equal(armorDexterityLimit(light),null);
 assert.equal(armorDexterityLimit(medium),2);
 assert.equal(armorDexterityLimit(heavy),0);
 assert.equal(armorDexterityLabel(medium),'+ DES (max +2)');
 assert.equal(armorDexterityBonus(medium,4),2);
 assert.equal(armorDexterityBonus(medium,-2),-2);
 assert.equal(armorDexterityBonus(heavy,-2),0);
 const custom={...medium,dexterity_max:3};
 assert.equal(armorDexterityBonus(custom,4),3);
 assert.equal(armorDexterityLabel(custom),'+ DES (max +3)');
 assert(inventoryReadout(medium).facts.some(row=>row.label==='Destrezza alla CA'&&row.value==='+ DES (max +2)'));
 for(const [armor,dex,ac] of [[light,4,15],[medium,4,16],[heavy,-2,18],[custom,4,17]]){
  const record={kind:'character',level:1,
   abilities:{str:10,dex:10+dex*2,con:10,int:10,wis:10,cha:10},inventory:[armor]};
  assert.equal(calculateSheet(record).values.ac,ac);
 }
});

test('inventory distinguishes unknown data from explicitly recorded zero',()=>{
 const missing=inventoryReadout({weight:null,value_gp:'',value:null,ac:null});
 assert.equal(missing.weight,null);assert.equal(missing.value,null);assert.deepEqual(missing.facts,[]);
 const zero=inventoryReadout({weight:0,value:0});assert.equal(zero.weight,0);assert.equal(zero.value,0);
 assert(zero.facts.some(row=>row.value==='0 lb'));assert(zero.facts.some(row=>row.value==='0 mo'));
 const invalid=inventoryReadout({weight:-1,value:'non noto'});assert.equal(invalid.weight,null);assert.equal(invalid.value,null);
});
test('inventory preserves distinct attunement, activation and document states',()=>{
 const pending=inventoryReadout({id:'magic_item:ring',req_attune:true,active:false,value_gp:2.5,quantity:3});
 assert.equal(pending.value,7.5);assert.deepEqual(pending.status,['Richiede sintonia','Disattivato']);
 const active=inventoryReadout({req_attune:true,attuned:true,infusion:{id:'enhanced'}});
 assert.deepEqual(active.status,['In sintonia','Infuso']);
 const document=inventoryReadout({id:'homebrew:vttdoc:documents:doc_test',weight:1,value:100});
 assert.equal(document.kind,'document');assert.equal(document.weight,null);assert.equal(document.value,null);
 const scroll=inventoryReadout({type:'SC',spell_level:0});assert.equal(scroll.type,'Pergamena');assert(scroll.facts.some(row=>row.value==='Trucchetto'));
});

test('desktop parity: magic scrolls have a separate identity, level and spell label',()=>{
 const ordinary={name:'Pergamena con sigillo',custom_item_type:'other'};
 const documents={name:'Pergamena di incantesimo',category:'documents'};
 const generic={id:'item:scroll3',type:'SC|DMG',name:'Spell Scroll (3rd Level)',quantity:2};
 const italian={name:'Pergamena di incantesimo (4° livello)'};
 const named={name:'Spell Scroll (1st Level)',spell_name:{name:'Shield'},spell_level:1};
 assert.equal(isSpellScroll(ordinary),false);
 assert.equal(isSpellScroll(documents),false);
 assert.equal(isSpellScroll(generic),true);
 assert.equal(isSpellScroll(italian),true);
 assert.equal(spellScrollLevel(generic),'3');
 assert.equal(spellScrollLevel(italian),'4');
 assert.equal(spellScrollName(generic),'Incantesimo non specificato');
 assert.equal(spellScrollName(named),'Shield');
 assert.equal(spellScrollLevel(named),'1');
 assert.equal(spellScrollLevel({name:'Spell Scroll (Cantrip)',spell_level:0}),'0');
 assert.equal(spellScrollName({name:'Spell Scroll of Fireball'}),'Spell Scroll of Fireball');
});

test('new spell scrolls preserve selected casting level and stack identical copies',()=>{
 const shield={id:'spell:shield|phb',name:'Shield',level:1,source:'PHB',description:'A protective reaction'};
 const added=addSpellScroll([],shield,3,'pwa_scroll_1');
 assert.equal(added.index,0);
 assert.equal(added.inventory.length,1);
 const scroll=added.inventory[0];
 assert.equal(scroll.id,'local_spell_scroll:spell:shield|phb');
 assert.equal(scroll.type,'SC');
 assert.equal(scroll.spell_id,shield.id);
 assert.equal(scroll.spell_name,'Shield');
 assert.equal(scroll.spell_base_level,1);
 assert.equal(scroll.spell_level,3);
 assert.equal(scroll.quantity,1);
 assert.equal(scroll.description,shield.description);
 assert.equal(isSpellScroll(scroll),true);
 assert.equal(spellScrollName(scroll),'Shield');
 assert.equal(spellScrollLevel(scroll),'3');
 const doubled=addSpellScroll(added.inventory,shield,3,'pwa_scroll_2');
 assert.equal(doubled.index,0);
 assert.equal(doubled.inventory.length,1);
 assert.equal(doubled.inventory[0].quantity,2);
 assert.equal(added.inventory[0].quantity,1,'stack operations must be immutable');
 const other=addSpellScroll(doubled.inventory,shield,1,'pwa_scroll_3');
 assert.equal(other.inventory.length,2,'scrolls cast at different levels remain separate');
 assert.equal(other.inventory[1].spell_level,1);
 const cantrip=addSpellScroll([], {id:'spell:light',name:'Light',level:0},0,'pwa_scroll_4');
 assert.equal(cantrip.inventory[0].spell_level,0);
 for(const level of [0,10,-1,'wrong'])
  assert.throws(()=>addSpellScroll([],shield,level,'copy'),/livello valido/);
 assert.throws(()=>addSpellScroll([], {id:'spell:light',name:'Light',level:0},1,'copy'),/livello valido/);
 assert.throws(()=>addSpellScroll([],{id:'spell:ability',name:'Feature',level:1,internal_grant:true},1,'copy'),/livello valido/);
});

test('armor class appears once as a structured fact, not again in the properties line',()=>{
 const shield=inventoryReadout({id:'shield:test',name:'Shield',type:'S',ac:2},'CA +2 · Raro');
 assert.equal(shield.facts.filter(fact=>fact.label==='CA').length,1);
 assert.equal(shield.properties,'Raro');
 const armor=inventoryReadout({id:'armor:test',name:'Armor',type:'HA',ac:17},'CA 17');
 assert.equal(armor.facts.filter(fact=>fact.label==='CA').length,1);
 assert.equal(armor.properties,'');
 const sword=inventoryReadout({id:'weapon:test',name:'Sword',type:'M',damage:'1d8'},'Versatile');
 assert.equal(sword.properties,'Versatile');
});
