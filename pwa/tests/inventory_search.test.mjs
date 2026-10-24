import test from 'node:test';
import assert from 'node:assert/strict';
import {inventorySearchResults} from '../inventory_search.js';

test('one owned result sums copies across sections and hides matching catalog result',()=>{
 const inventory=[
  {id:'item:sword',name:'Spada lunga',source:'PHB',quantity:2},
  {id:'item:sword',name:'Spada lunga',source:'PHB',quantity:1,container_id:'chest'},
  {id:'tool:rope',name:'Corda',source:'PHB',quantity:4}
 ];
 const catalog=[{id:'item:sword',name:'Spada lunga',source:'PHB'},
  {id:'other:dagger',name:'Pugnale',source:'PHB'}];
 assert.deepEqual(inventorySearchResults(inventory,catalog,'spada'),
  [{kind:'owned',name:'Spada lunga',source:'PHB',quantity:3,indices:[0,1]}]);
 assert.equal(inventorySearchResults(inventory,catalog,'pug')[0].kind,'catalog');
 assert.equal(inventorySearchResults(inventory,catalog,'pug')[0].catalogIndex,1);
 assert.deepEqual(inventorySearchResults(inventory,catalog,''),[]);
});
test('catalog entries match by name, source and accent; quantity is independent of item position',()=>{
 const rows=inventorySearchResults(
  [{name:'Pozióne curativa',source:'DMG',quantity:5}],
  [{id:'potion',name:'Pozione curativa',source:'DMG'},
   {id:'potion2',name:'Pozione curativa',source:'XGE'}],
  'pozione');
 assert.equal(rows.length,2);
 assert.equal(rows[0].quantity,5);
 assert.equal(rows[1].kind,'catalog');
});
