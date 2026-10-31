import test from 'node:test';
import assert from 'node:assert/strict';
import {attackRangeLabel,inventoryRangeLabel} from '../attack_range.js';
import {inventoryReadout} from '../sheet_rules_view.js';
import {formatGuiDistanceText,setDistanceUnit} from '../distance_units.js';

test('ranged attacks show both the short and long distance bands, not only the first',()=>{
 const bow={melee:false,range_feet:150,long_range_feet:600};
 assert.equal(attackRangeLabel(bow),'Gittata corta 150 ft · lunga 600 ft');
 assert.equal(attackRangeLabel({melee:false,range_feet:20,long_range_feet:60}),
  'Gittata corta 20 ft · lunga 60 ft');
 assert.equal(attackRangeLabel({melee:false,range_feet:120,long_range_feet:0}),
  'Gittata 120 ft','A ranged spell with one limit must not invent a long range');
 assert.equal(attackRangeLabel({melee:true,range_feet:10,long_range_feet:60}),
  'Portata 10 ft','A melee attack has reach, not a long range');
 assert.equal(attackRangeLabel({melee:false,range_feet:0,long_range_feet:0}),'');
});

test('inventory item ranges use the same clear short and long labels',()=>{
 assert.equal(inventoryRangeLabel('150/600'),'Gittata corta 150 ft · lunga 600 ft');
 assert.equal(inventoryRangeLabel('20/60'),'Gittata corta 20 ft · lunga 60 ft');
 assert.equal(inventoryRangeLabel('120'),'Gittata 120 ft');
 const bow=inventoryReadout({id:'longbow',name:'Longbow',type:'R',range:'150/600',
  damage:'1d8',quantity:1});
 const range=bow.facts.find(row=>row.label==='Gittata');
 assert.equal(range?.value,'corta 150 ft · lunga 600 ft');
});

test('both visible distance bands respect the existing metres GUI preference',()=>{
 try{
  setDistanceUnit('meters');
  assert.equal(formatGuiDistanceText(attackRangeLabel({
   melee:false,range_feet:20,long_range_feet:60})),
   'Gittata corta 6 m · lunga 18 m');
 }finally{setDistanceUnit('feet');}
});
