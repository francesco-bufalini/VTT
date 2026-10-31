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
 const use=id=>page.locator('#sheet-play-view [data-act="battle-use-ability"][data-ability-id="activated:'+id+'"]');
 for(const id of ['first','second']){
  const button=use(id);
  assert.equal(await button.count(),1,'The shared-tracker action remains in Resources');
  const details=button.locator('xpath=ancestor::details[1]');
  if(await details.count()&&!(await details.getAttribute('open')))
   await details.locator(':scope > summary').click();
  assert(await button.isVisible(),'The action is visible when its resource details are expanded');
 }
 const before=await page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].revision;});
 // The popup opens without charging the tracker and each confirmed use
 // commits its own atomic payment, even when two abilities share one pool.
 for(const [index,id] of ['first','second'].entries()){
  await use(id).click();
  const dialog=page.locator('#other-ability-dialog');
  await dialog.locator('[data-ability-confirm]').waitFor();
  assert.equal(await dialog.locator('[data-ability-payment] option').count(),2);
  const spent=await page.evaluate(async()=>{
   const {listCreatures}=await import('/creatures.js');
   return (await listCreatures())[0].creature.resource_tracker_spent.focus||0;
  });
  assert.equal(spent,index*2);
  await dialog.locator('[data-ability-confirm]').click();
  await dialog.waitFor({state:'detached'});
  await waitFor(async amount=>{
   const {listCreatures}=await import('/creatures.js');
   return (await listCreatures())[0].creature.resource_tracker_spent.focus===amount;
  },2*(index+1));
 }
 await waitFor(async base=>{const {listCreatures}=await import('/creatures.js');const row=(await listCreatures())[0];return row.revision>=base+2&&row.creature.resource_tracker_spent.focus===4;},before);
 await waitFor(async()=> (await navigator.serviceWorker.getRegistration())?.active?.state==='activated',null,30000);
 await context.setOffline(true);await page.reload();
 await page.locator('[data-act="open"]').click();await page.locator('#sheet-play-view').waitFor();
 const spent=await page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.resource_tracker_spent.focus;});
 assert.equal(spent,4);assert.deepEqual(errors,[]);assert.deepEqual(writes,[]);
 console.log('PASS: two visible ability buttons atomically pay multi-use costs and persist after offline reload.');
}finally{await f.close();}
