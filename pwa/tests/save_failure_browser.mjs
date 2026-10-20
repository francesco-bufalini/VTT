// A failed CAS must retain the user's draft in the real, visible HP dialog.
import assert from 'node:assert/strict';
import {browserFixture,seedPlayCreature} from './browser_fixture.mjs';
const f=await browserFixture();
const {page,origin,sheet,errors,writes}=f;
try{
 await seedPlayCreature(page,origin);await sheet('battle');
 await page.locator('#sheet-play-view [data-act="hp-damage"]').click();
 await page.locator('#hp-adjust-amount').fill('10');
 const before=await page.evaluate(async()=>{
  const {listCreatures,saveCreature}=await import('/creatures.js');
  const row=(await listCreatures())[0];
  await saveCreature({...row.creature,name:'Aggiornata da altra finestra'},'default',row.revision);
  return {id:row.creature.id,hp:row.creature.current_hp};
 });
 await page.locator('#hp-adjust-confirm').click();
 await page.locator('#save-state.error').waitFor({state:'attached'});
 await page.waitForFunction(()=>document.querySelector('#hp-adjust-confirm')?.disabled===false);
 assert(await page.locator('#hp-adjust-dialog').isVisible(),'Rejected saves must leave the dialog visible');
 assert.equal(await page.locator('#hp-adjust-amount').inputValue(),'10');
 const kept=await page.evaluate(async id=>{const {loadCreature}=await import('/creatures.js');return (await loadCreature(id)).data;},before.id);
 assert.equal(kept.current_hp,before.hp);
 assert.equal(kept.name,'Aggiornata da altra finestra');
 const restore=await page.evaluate(async id=>{
  const {openCreatureEditor,loadCreature}=await import('/creatures.js');
  const {exportBackup,importBackup}=await import('/storage.js');
  const stale=await openCreatureEditor(id),archive=await exportBackup();
  const active=await openCreatureEditor(id);await active.update({name:'Modificata dopo il backup'});
  const before=(await loadCreature(id)).revision;
  await importBackup(archive,{overwrite:true});
  let rejected=false;try{await stale.update({name:'Scrittura obsoleta'});}catch{rejected=true;}
  const current=await loadCreature(id);
  return {before,after:current.revision,name:current.data.name,rejected};
 },before.id);
 assert(restore.rejected,'Restoring a backup must not make an old editor valid again');
 assert(restore.after>restore.before);
 assert.equal(restore.name,'Aggiornata da altra finestra');
 assert.deepEqual(errors,[]);assert.deepEqual(writes,[]);
 console.log('PASS: rejected HP saves retain the visible draft; backup restoration invalidates stale editors in real IndexedDB.');
}finally{await f.close();}
