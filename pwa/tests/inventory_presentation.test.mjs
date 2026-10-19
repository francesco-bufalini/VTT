import {test} from 'node:test';
import assert from 'node:assert/strict';
import {inventoryReadout} from '../sheet_rules_view.js';
import {isSpellScroll,spellScrollName,spellScrollLevel} from '../item_controls.js';

test('inventory summaries resolve each owned copy and multiply only recorded unit data',()=>{
 const item={id:'local_blade',name:'Spada',custom_item_type:'weapon',damage:'1d6',weight:3,value:1500,quantity:2,equipped_slots:['main'],instance_overrides:{damage:'1d8',weight:4}};
 const before=structuredClone(item),info=inventoryReadout(item,'Accurata · Leggera');
 assert.equal(info.type,'Arma');assert.equal(info.weight,8);assert.equal(info.value,30);
 assert(info.facts.some(row=>row.label==='Danno'&&row.value==='1d8'));
 assert(info.facts.some(row=>row.label==='Peso totale'&&row.value==='8 lb'));
 assert.deepEqual(info.status,['Mano principale']);assert.deepEqual(item,before);
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
