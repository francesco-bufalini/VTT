// Exercise actual UI handlers with two commands in one event-loop turn.
// Each browser context is isolated from the user's installation and game.
import assert from 'node:assert/strict';
import {browserFixture,seedPlayCreature} from './browser_fixture.mjs';
const f=await browserFixture();
const {page,context,origin,sheet,errors,writes}=f;
async function waitForBrowser(predicate,arg,{timeout=15000}={}){
 const end=Date.now()+timeout;
 while(Date.now()<end){
  if(await page.evaluate(predicate,arg))return;
  await page.waitForTimeout(20);
 }
 throw Error('Browser state did not reach the expected persisted revision');
}
try{
 await seedPlayCreature(page,origin);
 await page.evaluate(async()=>{
  const {listCreatures,saveCreature}=await import('/creatures.js');
  const row=(await listCreatures())[0];
  await saveCreature({...row.creature,resource_trackers:[
   {id:'rapid_a',name:'Risorsa A',max:5,recharge:'manual'},
   {id:'rapid_b',name:'Risorsa B',max:5,recharge:'turn'}],
   resource_tracker_spent:{rapid_a:1,rapid_b:1},spell_slots_spent:Array(10).fill(0)},'default',row.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();
 await page.locator('#sheet-play-view').waitFor();await sheet('battle');
 await page.locator('[data-battle-action="resources"] > summary').click();
 await page.locator('[data-resource-tracker="rapid_a"] .play-resource-info').click();
 await page.locator('#sheet-context-dialog[open]').waitFor();
 for(const act of ['tracker-more','tracker-less'])assert(await page.locator('#sheet-context-dialog [data-act="'+act+'"][data-tracker-id="rapid_a"]:visible').count());
 const revision=()=>page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].revision;});
 const before=await revision();
 await page.evaluate(()=>{
  for(const act of ['tracker-more','tracker-less'])document.querySelector('#sheet-context-dialog [data-act="'+act+'"][data-tracker-id="rapid_a"]').click();
 });
 await waitForBrowser(async base=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].revision>=base+2;},before);
 const record=()=>page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature;});
 assert.deepEqual((await record()).resource_tracker_spent,{rapid_a:1,rapid_b:1});
 await f.dismiss();
 await waitForBrowser(async()=> (await navigator.serviceWorker.getRegistration())?.active?.state==='activated',null,{timeout:30000});
 await context.setOffline(true);await page.reload();
 await page.locator('[data-act="open"]').click();await page.locator('#sheet-play-view').waitFor();
 assert.deepEqual((await record()).resource_tracker_spent,{rapid_a:1,rapid_b:1});
 assert.deepEqual((await record()).spell_slots_spent.slice(1,3),[0,0]);
 assert.deepEqual(errors,[]);assert.deepEqual(writes,[]);
 console.log('PASS: visible resource controls preserve rapid use/recovery and their saved values after offline reload.');
}finally{await f.close();}
