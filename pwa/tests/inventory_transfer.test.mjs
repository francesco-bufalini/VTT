import 'fake-indexeddb/auto';
import test from 'node:test';
import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
import {createCreature,openCreatureEditor,saveHomebrewDefinition,loadCreature} from '../creatures.js';
import {exportInventoryItems,importInventoryItems,parseInventoryPackage,INVENTORY_SHARE_FORMAT} from '../inventory_transfer.js';
Object.defineProperty(globalThis,'crypto',{value:webcrypto,configurable:true});

test('selected inventory stacks keep quantity, overrides and homebrew dependencies',async()=>{
  const unique=webcrypto.randomUUID().replaceAll('-','').slice(0,16);
  const id='homebrew:inventory_test:items:relic_'+unique;
  await saveHomebrewDefinition({id,name:'Reliquia',data:{description:'Magia test',rarity:'rare'}});
  const source=await createCreature('character','Mittente '+unique);
  const editor=await openCreatureEditor(source.id);
  await editor.update({inventory:[
    {id:'weapon:longsword|phb',name:'Spada lunga',source:'PHB',quantity:3,
      equipped:true,equipped_slots:['main'],instance_overrides:{damage:'2d6'}},
    {id,name:'Reliquia',source:'Homebrew',quantity:2,attuned:true,attuned_count:1,
      container_id:'bag',infusion:{id:'enhanced'}},
    {id:'scroll:shield',name:'Pergamena di Scudo',type:'SC',quantity:4}
  ]});
  await editor.flush();
  const payload=await exportInventoryItems(editor.read(),[1,0]);
  assert.equal(payload.format,INVENTORY_SHARE_FORMAT);
  assert.equal(payload.items.length,2);
  assert.deepEqual(payload.items.map(item=>item.quantity),[3,2]);
  assert.equal(payload.items[0].instance_overrides.damage,'2d6');
  assert.deepEqual(payload.definitions.map(def=>def.id),[id]);
  assert.deepEqual(parseInventoryPackage(JSON.stringify(payload)),{
    items:payload.items,definitions:payload.definitions
  });
  const target=await createCreature('character','Destinatario '+unique);
  assert.equal(await importInventoryItems(payload,target.id),2);
  const imported=(await loadCreature(target.id)).data.inventory;
  assert.deepEqual(imported.map(item=>item.quantity),[3,2]);
  assert.equal(imported[0].instance_overrides.damage,'2d6');
  assert.equal(imported[0].equipped,false);
  assert.deepEqual(imported[0].equipped_slots,[]);
  assert.equal(imported[1].attuned,false);
  assert.equal(imported[1].attuned_count,0);
  assert.equal(imported[1].container_id,'backpack');
  assert.equal(imported[1].infusion.id,'enhanced');
  assert.notEqual(imported[0].instance_id,imported[1].instance_id);
  assert.equal((await loadCreature(source.id)).data.inventory[0].equipped,true,
    'the sender must remain unchanged');
});

test('inventory packages reject malformed or out-of-range selections',async()=>{
  assert.throws(()=>parseInventoryPackage({
    format:INVENTORY_SHARE_FORMAT,version:1,
    items:[{name:'Invalid',quantity:-1}],definitions:[]
  }),/non valido/);
  assert.throws(()=>parseInventoryPackage({
    format:INVENTORY_SHARE_FORMAT,version:1,items:[],definitions:[]
  }),/non valido/);
  await assert.rejects(exportInventoryItems({inventory:[{name:'Oggetto'}]},[4]),
    /oggetti validi/);
});
