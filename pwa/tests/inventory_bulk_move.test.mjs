import test from 'node:test';
import assert from 'node:assert/strict';
import {moveInventoryItem,moveInventoryItems,inventoryContainers}
  from '../item_controls.js';

test('bulk move changes every selected item in one immutable inventory patch',()=>{
 const creature={inventory_containers:[{id:'chest',name:'Baule'},{id:'belt',name:'Cintura'}],
  inventory:[
   {id:'sword',name:'Spada',quantity:2,instance_id:'a',equipped:true},
   {id:'shield',name:'Scudo',quantity:1,instance_id:'b',container_id:'belt'},
   {id:'gem',name:'Gemma',quantity:7,instance_id:'c'}
  ]};
 const original=structuredClone(creature);
 assert.equal(inventoryContainers(creature).length,3);
 const moved=moveInventoryItems(creature,[1,0,1],'chest');
 assert.deepEqual(moved.inventory.map(x=>x.container_id),['chest','chest',undefined]);
 assert.equal(moved.inventory[0].quantity,2);
 assert.equal(moved.inventory[0].equipped,true);
 assert.equal(moved.inventory[1].instance_id,'b');
 assert.deepEqual(creature,original,'bulk movement does not mutate the source');
 const restored=moveInventoryItems({...creature,inventory:moved.inventory},[0,1],'backpack');
 assert.equal(Object.hasOwn(restored.inventory[0],'container_id'),false);
 assert.equal(Object.hasOwn(restored.inventory[1],'container_id'),false);
 assert.deepEqual(moveInventoryItem(creature,0,'chest').inventory[0],moved.inventory[0]);
});
test('bulk move is atomic when section, indices, or item kinds are invalid',()=>{
 const creature={inventory_containers:[{id:'chest',name:'Baule'}],inventory:[
  {name:'Spada',quantity:1},
  {id:'scroll',name:'Spell Scroll',type:'SC',quantity:1},
  {name:'Documento',category:'documents'}
 ]};
 const before=structuredClone(creature);
 assert.throws(()=>moveInventoryItems(creature,[0,8],'chest'),/Oggetto non trovato/);
 assert.throws(()=>moveInventoryItems(creature,[0,1],'chest'),/Pergamene/);
 assert.throws(()=>moveInventoryItems(creature,[2],'chest'),/documenti/);
 assert.throws(()=>moveInventoryItems(creature,[0],'bad'),/Contenitore/);
 assert.throws(()=>moveInventoryItems(creature,[],'chest'),/Seleziona/);
 assert.deepEqual(creature,before);
});
