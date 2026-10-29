import assert from 'node:assert/strict';
import {browserFixture,seedPlayCreature} from './browser_fixture.mjs';
const f=await browserFixture();const {page,sheet,shot}=f;
const record=()=>page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature;});
try{
 await seedPlayCreature(page,f.origin);await sheet('battle');
 await page.locator('#sheet-play-view .play-health').click();
 const dialog=page.locator('#hp-adjust-dialog');await dialog.waitFor({state:'visible'});
 assert.equal(await dialog.locator('#hp-adjust-confirm').count(),0);
 assert.equal(await page.evaluate(()=>document.activeElement?.tagName),'BUTTON');
 const current=dialog.locator('#hp-adjust-current'),temp=dialog.locator('#hp-adjust-temporary');
 await current.fill('20');await page.waitForTimeout(100);await current.fill('21');
 await page.waitForTimeout(150);assert.equal((await record()).current_hp,40);
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.current_hp===21;});
 assert(await dialog.isVisible());assert(await current.evaluate(el=>el===document.activeElement));
 await temp.fill('8');await temp.press('Enter');
 assert.equal(await temp.evaluate(el=>el===document.activeElement),false);
 assert(await dialog.isVisible());
 await dialog.locator('[data-act="hp-adjust-cancel"]').click();
 await dialog.waitFor({state:'hidden'});
 assert.equal((await record()).temporary_hp,8,'Closing flushes a pending numeric edit');
 await page.locator('#sheet-play-view .play-health').click();
 await current.fill('22');
 await dialog.locator('[data-act="hp-adjust-restore"]').click();
 await page.waitForFunction(()=>document.querySelector('#hp-adjust-current')?.value==='40');
 assert.equal((await record()).current_hp,40);assert.equal((await record()).temporary_hp,8);
 assert.equal(await current.inputValue(),'40');assert(await dialog.isVisible());
 await current.fill('');await page.waitForTimeout(600);assert.equal((await record()).current_hp,40);
 await current.fill('30');
 await dialog.locator('#hp-adjust-amount').fill('2');
 await dialog.locator('[data-hp-mode="heal"]').click();
 await dialog.waitFor({state:'hidden'});
 assert.equal((await record()).current_hp,32,'Quick heal consumes the most recent pending HP edit');
 await page.locator('#sheet-play-view .play-health').click();
 for(const width of [390,1440]){
  await page.setViewportSize({width,height:1000});
  const boxes=await dialog.locator('#hp-adjust-current,#hp-adjust-temporary,[data-act="hp-adjust-max"],[data-act="hp-adjust-restore"]').evaluateAll(nodes=>nodes.map(n=>{const r=n.getBoundingClientRect();return {y:r.y,height:r.height};}));
  assert.equal(boxes.length,4);assert(boxes.every(b=>Math.abs(b.height-48)<1));
  assert(boxes.every(b=>Math.abs(b.y-boxes[0].y)<1));
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  await shot('hp-autosave-'+width);
 }
 await dialog.locator('[data-act="hp-adjust-cancel"]').click();
 await page.evaluate(()=>{const input=document.createElement('textarea');input.id='keyboard-check';document.body.append(input);input.focus();});
 await page.locator('#keyboard-check').press('Enter');
 assert.equal(await page.evaluate(()=>document.activeElement?.id),'');
 assert.deepEqual(f.errors,[]);assert.deepEqual(f.missing,[]);
 console.log('PASS: debounced HP autosave, immediate close/restore/heal, no input autofocus, Enter dismisses editing, aligned 48px controls');
}finally{await f.close();}
