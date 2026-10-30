import test from 'node:test';
import assert from 'node:assert/strict';
import {equipSlot} from '../item_controls.js';

const weapon=(id,slots=[],properties=[])=>({id,name:id,custom_item_type:'weapon',type:'M',
 quantity:1,properties,equipped_slots:slots,equipped:slots.length>0});

test('equipment slot changes synchronize legacy flags on every displaced copy',()=>{
 const owned=[weapon('sword',['main']),weapon('dagger',['off']),weapon('greatsword',[],['2H'])];
 let rows=equipSlot(owned,'main',2);
 assert.deepEqual(rows.map(row=>row.equipped_slots),[[],[],['main']]);
 assert.deepEqual(rows.map(row=>row.equipped),[false,false,true]);
 rows=equipSlot(rows,'main',-1);
 assert.deepEqual(rows.map(row=>row.equipped_slots),[[],[],[]]);
 assert.deepEqual(rows.map(row=>row.equipped),[false,false,false]);
 rows=equipSlot(rows,'main',0);
 assert.deepEqual(rows.map(row=>row.equipped),[true,false,false]);
 assert.deepEqual(owned.map(row=>row.equipped),[true,true,false],
  'Equipment updates must not modify the original array');
});
