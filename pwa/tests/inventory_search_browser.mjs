import assert from 'node:assert/strict';
import {browserFixture,seedPlayCreature} from './browser_fixture.mjs';

const f=await browserFixture(),{page,origin,sheet}=f;
const record=()=>page.evaluate(async()=>{
 const {listCreatures}=await import('/creatures.js');
 return (await listCreatures())[0].creature;
});
try{
 await seedPlayCreature(page,origin);
 await page.evaluate(async()=>{
  const {listCreatures,saveCreature}=await import('/creatures.js');
  const saved=(await listCreatures())[0],creature=saved.creature;
  const sword={...creature.inventory[0],weight:3,value_gp:10};
  const copy={...sword,instance_id:'test_sword_chest',quantity:2,container_id:'chest'};
  await saveCreature({...creature,
    inventory_containers:[{id:'chest',name:'Baule'}],
    inventory:[sword,...creature.inventory.slice(1),copy]},'default',saved.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('inventory');
 await page.locator('[data-act="inventory-toggle-all"]').click();
 const sections=page.locator('#sheet-play-view .play-inventory-section');
 assert(await sections.count()>=2,'Backpack and custom section must be visible');
 const totals=page.locator('#sheet-play-view .inventory-overview');
 assert.equal(await totals.count(),1,'Existing total cards are retained');
 assert.equal(await page.locator('#sheet-play-view .inventory-section-metrics').count(),2,
   'Both owned-item sections have weight/value subtotals');
 assert.equal(await page.locator('#sheet-play-view .inventory-section-metrics>span').count(),4);
 const search=page.locator('#sheet-play-view [data-play-search]');
 const layout=await page.evaluate(()=>{
  const a=document.querySelector('.inventory-overview').getBoundingClientRect();
  const b=document.querySelector('.inventory-search-area').getBoundingClientRect();
  const c=document.querySelector('.play-inventory-section').getBoundingClientRect();
  return {totalsEnd:a.bottom,searchStart:b.top,searchEnd:b.bottom,sectionStart:c.top};
 });
 assert(layout.totalsEnd<=layout.searchStart&&layout.searchEnd<=layout.sectionStart,
  'Search is between total cards and the first section');
 const originalCount=await page.locator('#sheet-play-view .inventory-play-item').count();
 await search.fill('Lama lunare');
 const owned=page.locator('#inventory-search-results .inventory-search-result').first();
 await owned.waitFor();
 assert.match(await owned.textContent(),/×3/);
 assert.equal(await page.locator('#sheet-play-view .inventory-play-item').count(),originalCount,
  'Typing in inventory search does not remove inventory rows');
 await owned.click();
 assert.equal(await page.locator('#sheet-play-view .inventory-search-highlight').count(),2,
  'The matching copies in two different sections are highlighted');
 assert.match(await page.locator('.play-inventory-page-title [data-act="inventory-toggle-all"]').textContent(),
  /Mostra solo zaino/);
 const wanted=await page.evaluate(async()=>{
  const {catalogEntries}=await import('/catalog_data.js');
  const entries=await catalogEntries('items');
  return entries.find(row=>row.name&&row.id&&
    !['Lama lunare','Pozione curativa','Anello stellare'].includes(row.name)&&
    row.name.length>=10);
 });
 assert(wanted,'Local item catalog must contain an item not already owned');
 await search.fill(wanted.name);
 const result=page.locator('#inventory-search-results .inventory-search-result:has(.is-add)').first();
 await result.waitFor();
 const addedName=(await result.locator('strong').textContent()).trim();
 await result.click();
 await page.locator('#inventory-search-add-dialog[open]').waitFor();
 await page.locator('#inventory-search-add-section').selectOption('chest');
 await page.locator('#inventory-search-add-quantity').fill('4');
 await page.locator('[data-act="inventory-search-add-confirm"]').click();
 await page.waitForFunction(async name=>{
  const {listCreatures}=await import('/creatures.js');
  return (await listCreatures())[0].creature.inventory.some(item=>
    item.name===name&&Number(item.quantity)===4&&item.container_id==='chest');
 },addedName);
 assert.equal(await page.locator('#inventory-search-add-dialog').count(),0);
 assert.equal((await record()).inventory.filter(row=>row.name===addedName&&row.container_id==='chest').length,1);
 assert.deepEqual(f.errors,[]);assert.deepEqual(f.missing,[]);assert.deepEqual(f.writes,[]);
 console.log('PASS: section totals, unified owned+catalog search, highlights and add-item dialog.');
}finally{await f.close();}
