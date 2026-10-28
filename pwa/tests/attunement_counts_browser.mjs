import assert from 'node:assert/strict';
import {browserFixture,seedPlayCreature} from './browser_fixture.mjs';

const f=await browserFixture();
const {page,origin,sheet,popup,dismiss,shot}=f;
const control=index=>page.locator('#sheet-context-dialog [data-attunement-row="'+index+'"]');
const count=index=>control(index).locator('[data-item-key="attuned_count"]');
const step=(index,delta)=>control(index).locator('[data-act="inventory-attunement"][data-delta="'+delta+'"]');
const record=()=>page.evaluate(async()=>{
 const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature;
});
const waitCount=async(index,n)=>page.waitForFunction(([i,n])=>
 document.querySelector('#sheet-context-dialog [data-item-index="'+i+'"][data-item-key="attuned_count"]')?.value===String(n),[index,n]);
const stats=()=>page.evaluate(async()=>{
 const {listCreatures}=await import('/creatures.js');
 const {calculateSheet,loadRuleCatalogs}=await import('/sheet_rules.js');
 const c=(await listCreatures())[0].creature,catalogs=await loadRuleCatalogs();
 const active=calculateSheet(c,catalogs),base=calculateSheet({...c,inventory:[]},catalogs);
 return {initiative:active.stats.initiative-base.stats.initiative,save:active.saves.str-base.saves.str,
  perception:active.skills.perception-base.skills.perception,attunements:active.attunements};
});
try{
 await seedPlayCreature(page,origin);
 await page.evaluate(async()=>{
  const {listCreatures,saveCreature}=await import('/creatures.js'),saved=(await listCreatures())[0];
  await saveCreature({...saved.creature,attunement_max_base:3,inventory:[
   {id:'local_luckstone',name:'Stone of Good Luck',quantity:4,custom_item_type:'magic',req_attune:true,
    attuned:true,bonus_ability_check:1,bonus_saving_throw:1,description:'Una pietra portafortuna di prova.'},
   {id:'local_ring',name:'Anello della prova',quantity:1,custom_item_type:'magic',req_attune:true,attuned:false}
  ]},'default',saved.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('inventory');
 const legacy=await record();await popup('item:0');await waitCount(0,1);
 assert.equal(await count(0).getAttribute('max'),'3');
 assert.equal((await stats()).initiative,1,'One legacy attunement grants one bonus despite quantity four');
 assert.deepEqual(await record(),legacy,'Reading must preserve the legacy archive');
 await step(0,1).click();await waitCount(0,2);
 await step(0,1).click();await waitCount(0,3);
 assert(await step(0,1).isDisabled());
 const three=await stats();assert.equal(three.initiative,3);assert.equal(three.save,3);assert.equal(three.perception,3);
 assert.equal((await record()).inventory[0].quantity,4);
 for(const width of [320,360,390,768,1440]){
  await page.setViewportSize({width,height:844});
  assert(await control(0).evaluate(n=>n.scrollWidth<=n.clientWidth),'Attunement counter fits '+width);
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  for(const button of await control(0).locator('button').all()){
   const box=await button.boundingBox();assert(box.width>=48&&box.height>=48);
  }
 }
 await page.setViewportSize({width:390,height:844});await shot('attunement-three-copies');
 await count(0).fill('4');await count(0).dispatchEvent('change');await waitCount(0,3);
 assert.equal((await record()).inventory[0].attuned_count,3,'Typing cannot bypass the maximum');
 await page.locator('#sheet-context-dialog [data-act="inventory-open-trait"]').click();
 await page.locator('#trait-benefits-dialog').waitFor();
 assert.match(await page.locator('#trait-benefits-title').textContent(),/Stone of Good Luck.*×3/);
 assert.match(await page.locator('#trait-benefits-dialog .trait-activation-description').textContent(),/3 copie in sintonia/);
 assert.match(await page.locator('#trait-benefits-dialog .trait-benefits').textContent(),/×3/);
 await shot('attunement-trait-three');
 await page.locator('[data-act="trait-benefits-close"]').click();
 await sheet('inventory');await popup('item:1');await waitCount(1,0);
 assert(await step(1,1).isDisabled(),'The maximum is shared with other items');
 await dismiss();await popup('item:0');
 await step(0,-1).click();await waitCount(0,2);
 await step(0,-1).click();await waitCount(0,1);
 const one=await stats();assert.equal(one.initiative,1);assert.equal(one.save,1);
 await page.locator('#sheet-context-dialog [data-act="inventory-open-trait"]').click();
 await page.locator('#trait-benefits-dialog').waitFor();
 assert.match(await page.locator('#trait-benefits-title').textContent(),/Stone of Good Luck.*×1/);
 await page.locator('[data-act="trait-benefits-close"]').click();
 await sheet('inventory');await popup('item:1');
 await step(1,1).click();await waitCount(1,1);await dismiss();
 await popup('item:0');
 await step(0,1).click();await waitCount(0,2);
 assert(await step(0,1).isDisabled(),'Two stones and one ring fill the same three slots');
 const quantity=page.locator('#sheet-context-dialog [data-item-index="0"][data-item-key="quantity"]');
 await quantity.fill('1');await quantity.dispatchEvent('change');await waitCount(0,1);
 assert.equal((await record()).inventory[0].attuned_count,1);
 assert.equal(await count(0).getAttribute('max'),'1','Only one instance remains');
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('inventory');await popup('item:0');
 await waitCount(0,1);assert.equal((await stats()).initiative,1);
 await dismiss();
 const cap=page.locator('#sheet-play-view .inventory-attunement [data-act="sheet-score-formula"][data-target="attunement_max"]');
 assert.equal(await cap.count(),1,'Maximum attunements open the shared score formula');
 await cap.click();
 const formula=page.locator('#sheet-score-formula-dialog');
 assert.match(await formula.locator('[data-score-formula]').textContent(),/Sintonie di base/);
 await formula.locator('[data-act="sheet-score-edit-base"]').click();
 const score=page.locator('#sheet-score-dialog');
 assert.equal(await score.locator('#sheet-score-input').inputValue(),'3','Numeric base-score popups retain the current value');
 await score.locator('#sheet-score-input').fill('1');
 await score.locator('[data-act="save-score"]').click();
 assert.equal((await record()).attunement_max_base,3,'Occupied slots prevent lowering the base below actual capacity');
 assert.equal(await score.count(),1,'Rejected score edits leave the dialog open');
 await score.locator('#sheet-score-input').fill('2');
 await score.locator('[data-act="save-score"]').click();
 assert.equal((await record()).attunement_max_base,2,'Shared base-score editor persists a valid capacity');
 assert.equal((await stats()).attunements.maximum,2);
 await page.locator('#sheet-score-formula-dialog [data-act="close-score-formula"]').click();
 assert.deepEqual(f.errors,[]);assert.deepEqual(f.missing,[]);assert.deepEqual(f.writes,[]);
 console.log('PASS: four luckstones use one or three attunements; exact bonuses and trait ×N, shared cap, typed-value validation, quantity shrink, 48px controls at 320–1440px, and reload persistence.');
}finally{await f.close();}
