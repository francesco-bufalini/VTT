import assert from 'node:assert/strict';
import {browserFixture,seedPlayCreature} from './browser_fixture.mjs';

const f=await browserFixture();
const {page,origin,sheet,shot}=f;
const panel=key=>page.locator('#sheet-play-view .play-inventory-section[data-inventory-section-key="'+key+'"]');
const panels=()=>page.locator('#sheet-play-view .play-inventory-section');
const settings=()=>page.locator('#inventory-section-settings-dialog');
const dialog=()=>page.locator('#inventory-container-delete-dialog');
const record=()=>page.evaluate(async()=>{
 const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature;
});
const openSettings=async key=>{
 const section=panel(key),initial=await section.evaluate(node=>node.open);
 await section.locator('.inventory-section-title').click();
 await settings().waitFor({state:'visible'});
 assert.equal(await section.evaluate(node=>node.open),initial,'Title button does not collapse the section');
};
const saveSettings=async()=>{
 await settings().locator('[data-inventory-section-save]').click();
 await settings().waitFor({state:'detached'});
};
try{
 await seedPlayCreature(page,origin);
 await page.evaluate(async()=>{
  const {listCreatures,saveCreature}=await import('/creatures.js');
  const saved=(await listCreatures())[0],inventory=structuredClone(saved.creature.inventory);
  inventory[1].container_id='bag';inventory[1].weight=17;inventory[1].quantity=1;
  await saveCreature({...saved.creature,inventory,inventory_containers:[
   {id:'bag',name:'Borsa delle provviste per il viaggio'},
   {id:'case',name:'Custodia'},{id:'empty',name:'Vuota'}]},'default',saved.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('inventory');
 const initial=await record();
 await page.waitForFunction(()=>document.querySelectorAll('#sheet-play-view .play-inventory-section').length===6);
 assert.equal(await page.locator('#sheet-play-view .inventory-container-tabs').count(),0,'Top section management is gone');
 assert.equal(await page.locator('[data-act="inventory-toggle-all"]').count(),0,'No hide-all control remains');
 assert.deepEqual(await panels().evaluateAll(nodes=>nodes.map(node=>node.dataset.inventorySectionKey)),
  ['items','scrolls','documents','container:bag','container:case','container:empty']);
 assert.equal(await page.locator('#sheet-play-view [data-act="inventory-container-rename"]').count(),0);
 const add=page.locator('#sheet-play-view .inventory-section-add');
 assert.equal(await add.count(),1,'One add-section control lives below the last section');
 assert(await add.evaluate(node=>node.previousElementSibling?.dataset.inventorySectionKey==='container:empty'));
 assert.equal(await panel('scrolls').locator('summary .inventory-section-create').count(),1);
 assert.equal(await panel('documents').locator('summary .inventory-section-create').count(),1);
 assert.equal(await page.locator('.inventory-special-create').count(),0,'Old create buttons are removed');

 for(const width of [320,360,390,768,1440]){
  await page.setViewportSize({width,height:900});
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'No horizontal overflow at '+width);
  assert.equal(await panels().count(),6,'All sections remain present regardless of viewport');
  assert(await panel('items').locator('summary').evaluate(node=>node.getBoundingClientRect().height>=44));
 }
 await page.setViewportSize({width:390,height:844});
 const bag=panel('container:bag');
 assert.equal(await bag.evaluate(node=>node.open),true);
 await bag.locator('summary').click({position:{x:4,y:20}});
 assert.equal(await bag.evaluate(node=>node.open),false,'Clicking the heading collapses only this section');
 assert.equal(await panel('items').evaluate(node=>node.open),true);
 await openSettings('container:bag');
 await settings().locator('[data-inventory-section-name]').fill('Borsa rinominata');
 await settings().locator('[data-inventory-section-exclude-weight]').check();
 await saveSettings();
 assert.equal(await bag.evaluate(node=>node.open),false,'A rerender preserves the collapsed state');
 assert.match(await bag.locator('.inventory-section-title').textContent(),/Borsa rinominata/);
 assert.deepEqual((await record()).inventory_excluded_weight_sections,['container:bag']);
 assert.match(await panel('container:bag').locator('.inventory-section-metrics').textContent(),/Peso escluso/);
 await bag.locator('summary').click({position:{x:4,y:20}});
 assert.equal(await bag.evaluate(node=>node.open),true);
 await shot('inventory-sections');

 // Built-in sections also have a title popup, but cannot be renamed or deleted.
 await openSettings('items');
 assert.equal(await settings().locator('[data-inventory-section-name]').count(),0);
 assert.equal(await settings().locator('[data-inventory-section-delete]').count(),0);
 await settings().locator('[data-inventory-section-close]').last().click();
 await settings().waitFor({state:'detached'});

 // The scroll + reuses the existing creator popup; it does not collapse its row.
 await panel('scrolls').locator('.inventory-section-create').click();
 const scrollCreator=page.locator('#sheet-context-dialog[data-context="scroll-create"]');
 await scrollCreator.waitFor({state:'visible'});
 assert.equal(await panel('scrolls').evaluate(node=>node.open),true);
 await scrollCreator.locator('[data-act="sheet-context-close"]').click();
 await scrollCreator.waitFor({state:'detached'});

 // Item popups still move copies between sections.
 await bag.locator('[data-sheet-context="item:1"]').click();
 const itemDialog=page.locator('#sheet-context-dialog[data-context="item:1"]');
 await itemDialog.waitFor({state:'visible'});
 await itemDialog.locator('[data-item-container="1"]').selectOption('case');
 await page.waitForFunction(async()=>{
  const {listCreatures}=await import('/creatures.js');
  return (await listCreatures())[0]?.creature?.inventory?.[1]?.container_id==='case';
 });
 await itemDialog.locator('[data-item-container="1"]').selectOption('bag');
 await page.waitForFunction(async()=>{
  const {listCreatures}=await import('/creatures.js');
  return (await listCreatures())[0]?.creature?.inventory?.[1]?.container_id==='bag';
 });
 await itemDialog.locator('[data-act="sheet-context-close"]').click();

 await openSettings('container:bag');
 await settings().locator('[data-inventory-section-delete]').click();
 await dialog().waitFor({state:'visible'});
 assert(await dialog().locator('[data-container-delete-confirm]').isDisabled());
 assert.deepEqual(await dialog().locator('option').evaluateAll(nodes=>nodes.map(n=>n.value)),
  ['','backpack','case','empty']);
 await dialog().locator('[data-container-delete-cancel]').click();
 await dialog().waitFor({state:'detached'});
 assert.equal(await panel('container:bag').count(),1,'Cancel preserves the section');
 await openSettings('container:bag');
 await settings().locator('[data-inventory-section-delete]').click();
 await dialog().waitFor({state:'visible'});
 await dialog().locator('[data-container-destination]').selectOption('case');
 await shot('inventory-section-delete');
 await dialog().locator('[data-container-delete-confirm]').click();
 await panel('container:bag').waitFor({state:'detached'});
 const moved=await record();
 assert.deepEqual(moved.inventory,initial.inventory.map(row=>
  row.container_id==='bag'?{...row,container_id:'case'}:row));
 assert.deepEqual(moved.inventory_excluded_weight_sections,[],'Deleted section no longer excludes weight');

 // The bottom + adds a section; its title popup provides renaming and deletion.
 page.once('dialog',request=>request.accept('Nuova sezione'));
 await add.click();
 const newSection=panels().filter({has:page.locator('.inventory-section-title', {hasText:'Nuova sezione'})});
 await newSection.waitFor({state:'visible'});
 const newKey=await newSection.getAttribute('data-inventory-section-key');
 await openSettings(newKey);
 await settings().locator('[data-inventory-section-name]').fill('Cintura');
 await saveSettings();
 assert.match(await panel(newKey).locator('.inventory-section-title').textContent(),/Cintura/);
 await openSettings(newKey);
 await settings().locator('[data-inventory-section-delete]').click();
 await dialog().waitFor({state:'visible'});
 assert.equal(await dialog().locator('[data-container-destination]').count(),0);
 await dialog().locator('[data-container-delete-confirm]').click();
 await panel(newKey).waitFor({state:'detached'});

 // Documents creation is now attached exclusively to the document heading.
 const previousDocuments=(await record()).inventory.filter(item=>item.category==='documents').length;
 await panel('documents').locator('.inventory-section-create').click();
 await page.waitForFunction(async previous=>{
  const {listCreatures}=await import('/creatures.js');
  return (await listCreatures())[0].creature.inventory.filter(item=>item.category==='documents').length>previous;
 },previousDocuments);
 assert.equal(await page.locator('#sheet-play-view .inventory-special-create').count(),0);
 if(await page.locator('#sheet-context-dialog').count())
  await page.locator('#sheet-context-dialog [data-act="sheet-context-close"]').click();

 await page.reload();await page.locator('[data-act="open"]').click();await sheet('inventory');
 assert.equal(await panels().count(),5,'Removed sections remain deleted after reload');
 assert.deepEqual((await record()).inventory_containers.map(row=>row.id),['case','empty']);
 assert.deepEqual(f.errors,[]);assert.deepEqual(f.missing,[]);assert.deepEqual(f.writes,[]);
 console.log('PASS: collapsible inventory sections, title settings, weight exclusions, header + controls, deletion and reload persistence.');
}finally{await f.close();}
