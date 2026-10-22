import assert from 'node:assert/strict';
import {browserFixture,seedPlayCreature} from './browser_fixture.mjs';
const f=await browserFixture();
const {page,context,origin,sheet,errors,writes}=f;
async function waitFor(predicate,arg,timeout=15000){
 const end=Date.now()+timeout;
 while(Date.now()<end){if(await page.evaluate(predicate,arg))return;await page.waitForTimeout(20);}
 throw Error('Expected persisted ability payment did not arrive');
}
try{
 await seedPlayCreature(page,origin);
 await page.evaluate(async()=>{
  const {listCreatures,saveCreature}=await import('/creatures.js');
  const row=(await listCreatures())[0];
  await saveCreature({...row.creature,
   resource_trackers:[{id:'focus',name:'Focus',max:5,recharge:'manual'}],resource_tracker_spent:{},
   origin_spell_grants:['first','second'].map(id=>({ability_id:id,name:'Impulso '+id,
    action_kind:'ability',tracker_id:'focus',tracker_cost:2,activation_mode:'action'}))
  },'default',row.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();
 await page.locator('#sheet-play-view').waitFor();await sheet('battle');
 await page.locator('[data-battle-action="resources"] > summary').click();
 for(const id of ['first','second'])
  assert(await page.locator('#sheet-play-view [data-act="battle-use-ability"][data-ability-id="activated:'+id+'"]:visible').count());
 const before=await page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].revision;});
 await page.evaluate(()=>{
  for(const id of ['first','second'])document.querySelector('#sheet-play-view [data-act="battle-use-ability"][data-ability-id="activated:'+id+'"]').click();
 });
 await waitFor(async base=>{const {listCreatures}=await import('/creatures.js');const row=(await listCreatures())[0];return row.revision===base+2&&row.creature.resource_tracker_spent.focus===4;},before);
 await waitFor(async()=> (await navigator.serviceWorker.getRegistration())?.active?.state==='activated',null,30000);
 await context.setOffline(true);await page.reload();
 await page.locator('[data-act="open"]').click();await page.locator('#sheet-play-view').waitFor();
 const spent=await page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.resource_tracker_spent.focus;});
 assert.equal(spent,4);assert.deepEqual(errors,[]);assert.deepEqual(writes,[]);
 console.log('PASS: two visible ability buttons atomically pay multi-use costs and persist after offline reload.');
}finally{await f.close();}
