import test from 'node:test';
import assert from 'node:assert/strict';
import {
  inventoryContainers,inventoryItemSection,inventoryExcludedWeightSections,
  inventoryCountsTowardCarriedWeight,createInventoryContainer,deleteInventoryContainer,
  moveInventoryItem
} from '../item_controls.js';

test('every inventory section stays addressable by stable id when excluding carried weight',()=>{
 const record={
  inventory_containers:[{id:'bag',name:'Borsa'},{id:'case',name:'Custodia'}],
  inventory_excluded_weight_sections:['container:bag','scrolls','container:gone','container:bag'],
  inventory:[{id:'rations',weight:5,container_id:'bag'},
   {id:'dagger',weight:1},{id:'scroll',type:'SC',weight:0.5},
   {id:'homebrew:vttdoc:documents:doc_1',weight:1}]
 };
 const containers=inventoryContainers(record);
 assert.deepEqual(inventoryExcludedWeightSections(record),['container:bag','scrolls']);
 assert.deepEqual(record.inventory.map(row=>inventoryItemSection(row,containers)),
  ['container:bag','items','scrolls','documents']);
 assert.deepEqual(record.inventory.map(row=>inventoryCountsTowardCarriedWeight(record,row)),
  [false,true,false,false]);
 // Names can be changed without invalidating saved section flags.
 const renamed={...record,inventory_containers:[{id:'bag',name:'Nuova borsa'},{id:'case',name:'Custodia'}]};
 assert.equal(inventoryCountsTowardCarriedWeight(renamed,renamed.inventory[0]),false);
 assert.equal(inventoryCountsTowardCarriedWeight(record,{weight:3,container_id:'case'}),true);
 assert.deepEqual(record.inventory_excluded_weight_sections,
  ['container:bag','scrolls','container:gone','container:bag'],'the source is immutable');
});

test('new, moved and deleted sections preserve weight rules without discarding objects',()=>{
 const original={inventory_containers:[],inventory_excluded_weight_sections:['items'],
  inventory:[{id:'sword',name:'Spada',weight:3}]};
 const created={...original,...createInventoryContainer(original,'chest','Baule')};
 const moved={...created,...moveInventoryItem(created,0,'chest')};
 assert.equal(inventoryCountsTowardCarriedWeight(original,original.inventory[0]),false);
 assert.equal(inventoryCountsTowardCarriedWeight(moved,moved.inventory[0]),true);
 const excluded={...moved,inventory_excluded_weight_sections:['items','container:chest']};
 assert.equal(inventoryCountsTowardCarriedWeight(excluded,excluded.inventory[0]),false);
 const deleted={...excluded,...deleteInventoryContainer(excluded,'chest','backpack')};
 assert.equal(deleted.inventory[0].id,'sword');
 assert.equal(Object.hasOwn(deleted.inventory[0],'container_id'),false);
 assert.deepEqual(deleted.inventory_containers,[]);
 assert.deepEqual(deleted.inventory_excluded_weight_sections,['items']);
 assert.equal(inventoryCountsTowardCarriedWeight(deleted,deleted.inventory[0]),false);
});
