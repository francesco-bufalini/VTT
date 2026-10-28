// Real browser, native asset routes and isolated IndexedDB: exercise the
// migrated catalog actions through the same UI and saves used on a phone.
import assert from 'node:assert/strict';
import {browserFixture} from './browser_fixture.mjs';
const f=await browserFixture(),{page,origin,sheet}=f;
const actionId='barbarian:2014:magic-awareness';
const snapshot=()=>page.evaluate(async()=>{
 const {listCreatures}=await import('/creatures.js');
 const {calculateSheet,loadRuleCatalogs}=await import('/sheet_rules.js');
 const record=(await listCreatures())[0].creature;
 const calculated=calculateSheet(record,await loadRuleCatalogs());
 const action=calculated.actions.find(row=>row.id==='barbarian:2014:magic-awareness');
 const tracker=calculated.trackers.find(row=>row.id===action?.tracker_id);
 return {record,action,tracker,proficiencies:calculated.proficiencies};
});
try{
 await page.goto(origin);await page.locator('[data-act="library-add"]').waitFor();
 await page.evaluate(async()=>{
  const {createCreature}=await import('/creatures.js');
  const {putRecord}=await import('/storage.js');
  const saved=await createCreature('character','Audit · Barbaro');
  const record={...saved.data,class:'Barbarian',class_source:'PHB',level:6,
   classes:[{name:'Barbarian',source:'PHB',level:6,subclass:'Wild Magic',subclass_source:'TCE'}],
   abilities:{str:16,dex:14,con:14,int:10,wis:12,cha:10},
   proficiency_choices:[{kind:'skill',key:'athletics'},{kind:'expertise',key:'athletics'},{kind:'save',key:'str'}],resource_tracker_spent:{}};
  await putRecord('default','creature',record.id,record,saved.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('battle');
 const before=await snapshot();
 assert(before.record.proficiency_choices.some(row=>row.kind==='expertise'&&row.key==='athletics'));
 assert(before.proficiencies.includes('skill:athletics'));
 assert(before.proficiencies.includes('expertise:athletics'));
 assert.equal(before.action.id,actionId);assert.equal(before.tracker.max,3);
 const resources=page.locator('[data-battle-action="resources"]');
 if(!await resources.evaluate(node=>node.open))await resources.locator('summary.play-battle-summary').click();
 const use=page.locator('[data-act="battle-use-ability"][data-ability-id="'+actionId+'"]');
 await use.click();await page.locator('[data-ability-cancel]').click();
 assert.equal((await snapshot()).tracker.spent,0,'cancel never spends a use');
 await use.click();await page.locator('[data-ability-confirm]').click();
 await page.waitForFunction(async id=>{
  const {listCreatures}=await import('/creatures.js');
  return (await listCreatures())[0].creature.resource_tracker_spent?.[id]===1;
 },before.tracker.id);
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('battle');
 const after=await snapshot();
 assert.equal(after.action.id,actionId);assert.equal(after.tracker.id,before.tracker.id);
 assert.equal(after.tracker.spent,1,'uses retain the same identity after reopening');
 await page.evaluate(async origin=>{
  const {listCreatures,saveCreature}=await import('/creatures.js');
  const saved=(await listCreatures())[0];
  await saveCreature({...saved.creature,origin_enabled:{[origin]:false}},'default',saved.revision);
 },after.action.origin_id);
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('battle');
 const disabled=await snapshot();assert.equal(disabled.action,undefined);
 assert.equal(await page.locator('[data-act="battle-use-ability"][data-ability-id="'+actionId+'"]').count(),0);
 await sheet('info');
 const trait=page.locator('.trait-row').filter({has:page.locator('.trait-title',{hasText:'Magic Awareness'})});
 await trait.locator('[data-act="trait-benefits-open"]').first().click();
 const capability=page.locator('#trait-benefits-dialog .trait-capability').filter({hasText:'Magic Awareness'});
 assert.match(await capability.innerText(),/Tratto disattivato/);
 assert.match(await capability.innerText(),/1 utilizzo.*Magic Awareness/);
 assert.deepEqual(f.errors,[]);
 // The static test fixture omits the native host's dynamic fingerprint route.
 assert.deepEqual(f.missing.filter(url=>new URL(url).pathname!=='/__vtt_version'),[]);
 assert.deepEqual(f.writes,[]);
 console.log('PASS: canonical choices persist; catalog action cancellation, payment, stable IDs and disabled trait persist in real Chrome');
}finally{await f.close();}
