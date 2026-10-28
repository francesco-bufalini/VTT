import assert from 'node:assert/strict';
import {browserFixture,seedPlayCreature} from './browser_fixture.mjs';
const f=await browserFixture();
const {page,origin,sheet,popup,dismiss}=f;
const record=()=>page.evaluate(async()=>{
 const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature;
});
try{
 await seedPlayCreature(page,origin);
 const before=await record();
 await sheet('inventory');
 await popup('item:0');
 const quantity=page.locator('#sheet-context-dialog [data-item-key="quantity"]');
 assert.equal(await quantity.inputValue(),'1','Opening item details preserves the owned quantity');
 for(const width of [320,390,768,1440]){
  await page.setViewportSize({width,height:900});
  assert(await quantity.isVisible());
  assert(await quantity.evaluate(n=>n.clientWidth-parseFloat(getComputedStyle(n).paddingLeft)-parseFloat(getComputedStyle(n).paddingRight)>=30),'Quantity has room for readable digits');
 }
 await dismiss();await popup('item:1');
 assert.equal(await page.locator('#sheet-context-dialog [data-item-key="quantity"]').inputValue(),'2');
 await dismiss();
 assert.deepEqual(await record(),before,'Opening numeric editors never changes inventory');
 const wanted=await page.evaluate(async()=>{
  const {catalogEntries}=await import('/catalog_data.js');
  return (await catalogEntries('items')).find(row=>row.name?.length>=10&&row.id);
 });
 assert(wanted);
 await page.locator('#sheet-play-view [data-play-search]').fill(wanted.name);
 await page.locator('#inventory-search-results .inventory-search-result:has(.is-add)').first().click();
 await page.locator('#inventory-search-add-dialog[open]').waitFor();
 assert.equal(await page.locator('#inventory-search-add-quantity').inputValue(),'1','Catalog additions default to one item');
 await page.locator('#inventory-search-add-dialog [data-act="inventory-search-add-close"]').first().click();

 await sheet('battle');await popup('rests');
 await page.locator('#sheet-context-dialog [data-act="tracker-short"]').click();
 const dice=page.locator('[data-rest-die="6"]');
 assert.equal(await dice.inputValue(),'1','A short rest starts with one available Hit Die');
 assert(await page.locator('[data-rest-roll-controls]').isVisible());
 assert.deepEqual(await record(),before,'Default Hit Die is only a preview');
 await dice.fill('0');await dice.dispatchEvent('change');
 assert.equal(await page.locator('[data-rest-roll-controls]').isVisible(),false);
 await dismiss();
 await page.evaluate(async()=>{
  const {listCreatures,saveCreature}=await import('/creatures.js');const saved=(await listCreatures())[0];
  await saveCreature({...saved.creature,hit_dice_spent:{d6:5}},'default',saved.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('battle');await popup('rests');
 await page.locator('#sheet-context-dialog [data-act="tracker-short"]').click();
 assert.equal(await page.locator('[data-rest-die="6"]').inputValue(),'0','Exhausted pools show zero');
 assert.deepEqual(f.errors,[]);
 console.log('PASS numeric values survive inventory dialogs; short-rest defaults respect available dice');
}finally{await f.close();}
