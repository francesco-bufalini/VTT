import assert from 'node:assert/strict';
import {browserFixture,seedPlayCreature} from './browser_fixture.mjs';

const f=await browserFixture();
const {page,origin,sheet,shot}=f;
const nav=()=>page.locator('#sheet-play-view .inventory-container-tabs');
const toggle=key=>nav().locator('[data-subtab="'+key+'"]');
const remove=id=>nav().locator('.inventory-section-remove[data-container-id="'+id+'"]');
const panels=()=>page.locator('#sheet-play-view .play-inventory-section');
const dialog=()=>page.locator('#inventory-container-delete-dialog');
const record=()=>page.evaluate(async()=>{
 const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature;
});
const panelCount=async count=>page.waitForFunction(n=>
 document.querySelectorAll('#sheet-play-view .play-inventory-section').length===n,count);
try{
 await seedPlayCreature(page,origin);
 await page.evaluate(async()=>{
  const {listCreatures,saveCreature}=await import('/creatures.js');
  const saved=(await listCreatures())[0];
  const inventory=structuredClone(saved.creature.inventory);
  inventory[1].container_id='bag';
  await saveCreature({...saved.creature,inventory,inventory_containers:[
   {id:'bag',name:'Borsa delle provviste per il viaggio'},
   {id:'case',name:'Custodia'},{id:'empty',name:'Vuota'}]},'default',saved.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('inventory');
 const before=await record();
 const expected=['inventory-container-add','all','items','scrolls','documents','container:bag','container:case','container:empty'];
 for(const width of [320,360,390,768,1440]){
  await page.setViewportSize({width,height:900});
  assert.deepEqual(await nav().locator('[data-act="inventory-container-add"],[data-subtab]').evaluateAll(nodes=>nodes.map(n=>n.dataset.subtab||n.dataset.act)),expected);
  assert.equal(await remove('bag').count(),1);
  assert.equal(await nav().locator('.inventory-section-remove').count(),3);
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'No horizontal overflow at '+width);
  for(const button of await nav().locator('button').all()){
   const box=await button.boundingBox();
   assert(box.height>=48&&box.width>=48,'Section controls have a touch target of at least 48px');
  }
  await toggle('all').click();await panelCount(6);
  assert.equal(await toggle('all').getAttribute('aria-pressed'),'true');
  await toggle('scrolls').click();await panelCount(5);
  assert.equal(await toggle('all').getAttribute('aria-pressed'),'false');
  await toggle('all').click();await panelCount(6);
  await toggle('all').click();await panelCount(0);
  await toggle('items').click();await panelCount(1);
  await toggle('items').click();await panelCount(0);
  await toggle('items').click();await panelCount(1);
 }
 assert.deepEqual(await record(),before,'Section switches cannot write creature data');
 await page.setViewportSize({width:390,height:844});
 const inactiveBackground=await toggle('container:bag').evaluate(n=>getComputedStyle(n).backgroundImage);
 await toggle('container:bag').click();await panelCount(2);
 assert.notEqual(await toggle('container:bag').evaluate(n=>getComputedStyle(n).backgroundImage),inactiveBackground,
  'Active custom sections need the same visible pressed style as base sections');
 await shot('inventory-sections');
 await remove('bag').click();await dialog().waitFor({state:'visible'});
 assert.equal(await toggle('container:bag').getAttribute('aria-pressed'),'true');
 assert(await dialog().locator('[data-container-delete-confirm]').isDisabled());
 assert.deepEqual(await dialog().locator('option').evaluateAll(nodes=>nodes.map(n=>n.value)),['','backpack','case','empty']);
 for(const width of [320,390,768,1440]){
  await page.setViewportSize({width,height:844});
  assert(await dialog().evaluate(n=>n.scrollWidth<=n.clientWidth),'Delete popup fits at '+width);
 }
 await page.setViewportSize({width:390,height:844});
 await dialog().locator('[data-container-destination]').selectOption('case');
 await shot('inventory-section-delete');
 await dialog().locator('[data-container-delete-cancel]').click();
 await dialog().waitFor({state:'detached'});
 assert.deepEqual(await record(),before,'Cancel preserves sections and items');
 await remove('bag').click();await dialog().waitFor({state:'visible'});
 await page.keyboard.press('Escape');await dialog().waitFor({state:'detached'});
 assert.deepEqual(await record(),before,'Escape preserves sections and items');
 await remove('bag').click();await dialog().waitFor({state:'visible'});
 await dialog().locator('[data-container-destination]').selectOption('case');
 await dialog().locator('[data-container-delete-confirm]').click();
 await remove('bag').waitFor({state:'detached'});
 const moved=await record();
 assert.deepEqual(moved.inventory,before.inventory.map(row=>row.container_id==='bag'?{...row,container_id:'case'}:row));
 await remove('empty').click();await dialog().waitFor({state:'visible'});
 assert.equal(await dialog().locator('[data-container-destination]').count(),0);
 await dialog().locator('[data-container-delete-confirm]').click();
 await remove('empty').waitFor({state:'detached'});
 await remove('case').click();await dialog().waitFor({state:'visible'});
 await dialog().locator('[data-container-destination]').selectOption('backpack');
 await dialog().locator('[data-container-delete-confirm]').click();
 await remove('case').waitFor({state:'detached'});
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('inventory');
 const final=await record();
 assert.deepEqual(final.inventory,before.inventory.map(({container_id,...row})=>row));
 assert.deepEqual(final.inventory_containers,[]);
 assert.deepEqual(f.errors,[]);assert.deepEqual(f.missing,[]);assert.deepEqual(f.writes,[]);
 console.log('PASS: ordered inventory switches, all/none and independent boxes at 320–1440px; 48px touch targets; confirmed section deletion, cancel/Escape, item transfers and reload persistence.');
}finally{await f.close();}
