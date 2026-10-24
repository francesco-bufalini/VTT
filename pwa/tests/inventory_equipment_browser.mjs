import assert from 'node:assert/strict';
import {browserFixture,seedPlayCreature} from './browser_fixture.mjs';

const f=await browserFixture();
const {page,origin,sheet}=f;
const popup=()=>page.locator('#sheet-context-dialog[open]');
const record=()=>page.evaluate(async()=>{
 const {listCreatures}=await import('/creatures.js');
 return (await listCreatures())[0].creature;
});
const open=async index=>{
 await page.locator('#sheet-play-view [data-sheet-context="item:'+index+'"]').click();
 await page.locator('#sheet-context-dialog[data-context="item:'+index+'"]').waitFor();
};
const close=async()=>{
 await popup().locator('[data-act="sheet-context-close"]').click();
 await page.locator('#sheet-context-dialog').waitFor({state:'detached'});
};
try{
 await seedPlayCreature(page,origin);
 await page.evaluate(async()=>{
  const {listCreatures,saveCreature}=await import('/creatures.js');
  const saved=(await listCreatures())[0];
  const extra=[
   {id:'local_greatsword',name:'Spadone a due mani',custom_item_type:'weapon',type:'M',damage:'2d6',
    properties:['2H'],quantity:1,equipped_slots:[]},
   {id:'local_armor',name:'Corazza di prova',custom_item_type:'armor',type:'HA',ac:16,
    quantity:1,equipped_slots:[]},
   {id:'local_shield',name:'Scudo di prova',custom_item_type:'shield',type:'S',ac:2,
    quantity:1,equipped_slots:[]}
  ];
  await saveCreature({...saved.creature,inventory:[...saved.creature.inventory,...extra]},'default',saved.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('inventory');
 await open(3);
 assert.equal(await popup().locator('.inventory-equip-action').count(),2);
 assert(await popup().locator('.inventory-equip-action[data-slot="off"]').isDisabled(),
   'Two-handed weapons cannot be put into the offhand slot');
 await popup().locator('.inventory-equip-action[data-slot="main"]').click();
 await page.locator('#sheet-context-dialog[data-context="equipment"]').waitFor();
 assert.deepEqual((await record()).inventory[3].equipped_slots,['main']);
 const override=popup().locator('[data-field="hand_off_with_two_handed"]');
 assert.equal(await override.isChecked(),false,'Two-handed offhand override must default to off');
 assert(await popup().locator('[data-equip-slot="off"]').isDisabled());
 await override.check();
 await page.waitForFunction(async()=>{
  const {listCreatures}=await import('/creatures.js');
  return (await listCreatures())[0].creature.hand_off_with_two_handed===true;
 });
 assert.equal(await popup().locator('[data-equip-slot="off"]').isDisabled(),false);
 await close();
 await open(5);
 await popup().locator('.inventory-equip-action[data-slot="off"]').click();
 await page.locator('#sheet-context-dialog[data-context="equipment"]').waitFor();
 let current=await record();
 assert.deepEqual(current.inventory[3].equipped_slots,['main']);
 assert.deepEqual(current.inventory[5].equipped_slots,['off']);
 await popup().locator('[data-field="hand_off_with_two_handed"]').uncheck();
 await page.waitForFunction(async()=>{
  const {listCreatures}=await import('/creatures.js');
  const c=(await listCreatures())[0].creature;
  return c.hand_off_with_two_handed===false&&!c.inventory[5].equipped_slots.length;
 });
 await close();
 await open(4);
 assert.equal(await popup().locator('.inventory-equip-action').count(),1);
 await popup().locator('.inventory-equip-action[data-slot="body"]').click();
 await page.locator('#sheet-context-dialog[data-context="equipment"]').waitFor();
 current=await record();
 assert.deepEqual(current.inventory[4].equipped_slots,['body']);
 assert.deepEqual(current.inventory[3].equipped_slots,['main']);
 assert.deepEqual(f.errors,[]);assert.deepEqual(f.missing,[]);assert.deepEqual(f.writes,[]);
 console.log('PASS: main/offhand/armor popup buttons, 2H offhand lock and persisted opt-in.');
}finally{await f.close();}
