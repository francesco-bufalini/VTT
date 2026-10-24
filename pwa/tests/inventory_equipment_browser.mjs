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
const waitSlots=async(index,expected)=>page.waitForFunction(async({index,expected})=>{
 const {listCreatures}=await import('/creatures.js');
 const slots=(await listCreatures())[0].creature.inventory[index].equipped_slots||[];
 return JSON.stringify(slots)===JSON.stringify(expected);
},{index,expected});
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
 await waitSlots(3,['main']);
 assert.equal(await popup().getAttribute('data-context'),'item:3',
   'Equipping must not open the equipment dialog');
 await popup().locator('.inventory-equip-action[data-slot="main"]').click();
 await waitSlots(3,[]);
 assert.equal((await record()).inventory[3].equipped,false,'Unequipped weapons have no stale equipped flag');
 assert.equal(await popup().getAttribute('data-context'),'item:3');
 await popup().locator('.inventory-equip-action[data-slot="main"]').click();
 await waitSlots(3,['main']);
 await close();

 await page.locator('#sheet-play-view [data-sheet-context="equipment"]').click();
 await page.locator('#sheet-context-dialog[data-context="equipment"]').waitFor();
 const override=popup().locator('[data-field="hand_off_with_two_handed"]');
 assert.equal(await override.isChecked(),false,'Two-handed offhand override must default to off');
 assert(await popup().locator('[data-equip-slot="off"]').isDisabled());
 const label=popup().locator('.equipment-offhand-override');
 assert.equal(await label.evaluate(node=>getComputedStyle(node).borderTopWidth),'0px',
   'The offhand override uses the same unboxed style as other settings');
 assert.equal(await label.evaluate(node=>getComputedStyle(node).whiteSpace),'nowrap');
 await override.check();
 await page.waitForFunction(async()=>{
   const {listCreatures}=await import('/creatures.js');
   return (await listCreatures())[0].creature.hand_off_with_two_handed===true;
 });
 assert.equal(await popup().locator('[data-equip-slot="off"]').isDisabled(),false);
 await close();

 // One-handed offhand weapon: equip and unequip without replacing the item popup.
 await open(0);
 await popup().locator('.inventory-equip-action[data-slot="off"]').click();
 await waitSlots(0,['off']);
 assert.deepEqual((await record()).inventory[3].equipped_slots,['main']);
 assert.equal(await popup().getAttribute('data-context'),'item:0');
 await popup().locator('.inventory-equip-action[data-slot="off"]').click();
 await waitSlots(0,[]);
 await close();

 // Shields use the same toggle and preserve the two-handed weapon when unlocked.
 await open(5);
 await popup().locator('.inventory-equip-action[data-slot="off"]').click();
 await waitSlots(5,['off']);
 assert.equal(await popup().getAttribute('data-context'),'item:5');
 let current=await record();
 assert.deepEqual(current.inventory[3].equipped_slots,['main']);
 await popup().locator('.inventory-equip-action[data-slot="off"]').click();
 await waitSlots(5,[]);
 await popup().locator('.inventory-equip-action[data-slot="off"]').click();
 await waitSlots(5,['off']);
 await close();

 await page.locator('#sheet-play-view [data-sheet-context="equipment"]').click();
 await page.locator('#sheet-context-dialog[data-context="equipment"]').waitFor();
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
 await waitSlots(4,['body']);
 assert.equal(await popup().getAttribute('data-context'),'item:4');
 await popup().locator('.inventory-equip-action[data-slot="body"]').click();
 await waitSlots(4,[]);
 await popup().locator('.inventory-equip-action[data-slot="body"]').click();
 await waitSlots(4,['body']);
 current=await record();
 assert.deepEqual(current.inventory[3].equipped_slots,['main']);
 assert.deepEqual(f.errors,[]);assert.deepEqual(f.missing,[]);assert.deepEqual(f.writes,[]);
 console.log('PASS: gear buttons toggle without navigation; unboxed offhand override; 2H restrictions.');
}finally{await f.close();}
