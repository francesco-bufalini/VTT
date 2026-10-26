import assert from 'node:assert/strict';
import {browserFixture,seedPlayCreature} from './browser_fixture.mjs';

const f=await browserFixture();
const {page,origin,errors,missing,sheet}=f;
const record=()=>page.evaluate(async()=>{
 const {listCreatures}=await import('/creatures.js');
 return (await listCreatures())[0]?.creature;
});
try{
 await seedPlayCreature(page,origin);
 await sheet('magic');
 const slotButtons=page.locator('#sheet-play-view .play-slots>.play-button');
 const shown=await slotButtons.allTextContents();
 assert(shown.length>0&&shown.length<9,'Only granted spell levels are visible in this wizard fixture');
 assert(shown.every(row=>Number(row.match(/\/\s*(\d+)/)?.[1]||0)>0),
   'All visible slot levels have a positive maximum');
 assert.equal(shown.length,await page.locator('.magic-overview .magic-overview-slot').count(),
   'The visible Powers sheet uses the same slot filtering as its backing view');
 assert.equal(await page.locator('#sheet-play-view [data-sheet-context="magic-tools"]').count(),0,
   'The old settings gear must not appear');
 assert.equal(await page.locator('#sheet-play-view .play-magic-concentration').count(),1);
 assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),
   'Powers sheet stays within the mobile viewport');

 // Starting concentration without an assigned spell is a supported state.
 await page.locator('.play-magic-concentration-actions .play-button').first().click();
 await page.locator('#magic-tools-dialog[open] #concentration-spell').waitFor();
 assert.equal(await page.locator('#concentration-spell').inputValue(),'');
 await page.locator('#magic-tools-dialog [data-act="concentration-set"]').click();
 await page.waitForFunction(()=>document.querySelector('.play-magic-concentration-status')?.textContent.includes('nessun incantesimo'));
 assert((await record()).conditions.includes('concentrating'));
 assert.equal((await record()).concentrating_spell_id||'','');

 // An existing concentration can be replaced with a specific known spell.
 await page.locator('.play-magic-concentration-actions .play-button').first().click();
 await page.locator('#magic-tools-dialog[open] #concentration-spell').selectOption('spell:shield|phb');
 await page.locator('#magic-tools-dialog [data-act="concentration-set"]').click();
 await page.waitForFunction(()=>document.querySelector('.play-magic-concentration-status')?.textContent.includes('Shield'));
 assert.equal((await record()).concentrating_spell_id,'spell:shield|phb');
 await page.locator('.play-magic-concentration-actions .play-button').last().click();
 await page.waitForFunction(()=>document.querySelector('.play-magic-concentration-status')?.textContent.includes('Non attiva'));
 assert(!(await record()).conditions.includes('concentrating'));
 assert.equal((await record()).concentrating_spell_id,'');

 // The slot editor delegates to the same bounded resource mutation paths as
 // other trackers; it must remain open while adjusting spent counts.
 await page.locator('#sheet-play-view .play-card-head .play-button[title="Gestisci slot"]').click();
 await page.locator('#magic-tools-dialog[open] .magic-slot-manager-row').first().waitFor();
 assert.equal(await page.locator('#magic-tools-dialog .magic-slot-manager-row').count(),10,
   'All nine levels plus Pact Magic have tracker rows');
 assert.equal(await page.locator('#magic-tools-dialog .magic-slot-manager>.hint').count(),0,
   'No explanatory helper text in Gestisci slot');
 assert.equal(await page.locator('#magic-tools-dialog .magic-slot-settings').count(),0,
   'Massimi e progressione controls must not appear in the popup');
 assert.equal(await page.locator('#magic-tools-dialog [data-slot-total],#magic-tools-dialog [data-pact-total],#magic-tools-dialog [data-act="slots-automatic"]').count(),0,
   'Manual maxima and progression actions are no longer exposed');
 assert.equal(await page.locator('#magic-tools-dialog [data-act="slots-restore"]').count(),1,
   'Restore all slots remains available');
 const firstMax=page.locator('#magic-tools-dialog .magic-slot-manager-row').first()
   .locator('.magic-slot-maximum');
 assert.equal(await firstMax.getAttribute('data-calculated'),'slot:1');
 await firstMax.click();
 await page.locator('#sheet-score-formula-dialog[open]').waitFor();
 assert.equal(await page.locator('#sheet-score-formula-dialog').getAttribute('data-score-target'),'slot:1');
 assert.match(await page.locator('#sheet-score-formula-dialog').textContent(),/Formula del valore/);
 await page.locator('#sheet-score-formula-dialog [data-act="close-score-formula"]').click();
 assert.equal(await page.locator('#magic-tools-dialog[open]').count(),1,
   'Closing score details returns to the slot manager');
 const pactMax=page.locator('#magic-tools-dialog .magic-slot-manager-row').last()
   .locator('.magic-slot-maximum');
 assert.equal(await pactMax.getAttribute('data-calculated'),'pact_slot');
 await pactMax.click();
 assert.equal(await page.locator('#sheet-score-formula-dialog').getAttribute('data-score-target'),'pact_slot');
 await page.locator('#sheet-score-formula-dialog [data-act="close-score-formula"]').click();
 const before=Number((await record()).spell_slots_spent?.[1]||0);
 await page.locator('#magic-tools-dialog .magic-slot-manager-row').first().locator('[data-act="slot-use"]').click();
 await page.waitForFunction(previous=>Number(document.querySelector('.magic-slot-manager-row .magic-tracker-count strong')?.textContent)===2, before);
 assert.equal(Number((await record()).spell_slots_spent?.[1]||0),before+1);
 assert.equal(await page.locator('#magic-tools-dialog[open]').count(),1,
   'Slot editor remains open after consumption');
 await page.locator('#magic-tools-dialog .magic-slot-manager-row').first().locator('[data-act="slot-recover"]').click();
 const recoveryDeadline=Date.now()+15000;
 while(Number((await record()).spell_slots_spent?.[1]||0)!==before&&Date.now()<recoveryDeadline)
   await page.waitForTimeout(20);
 assert.equal(Number((await record()).spell_slots_spent?.[1]||0),before);
 await page.locator('#magic-tools-dialog [data-act="magic-tool-close"]').click();

 // Expend every first-level slot: its 0/4 readout must remain in the first card.
 await page.evaluate(async()=>{
   const {listCreatures,saveCreature}=await import('/creatures.js');
   const row=(await listCreatures())[0];
   const spent=[...(row.creature.spell_slots_spent||Array(10).fill(0))];
   while(spent.length<10)spent.push(0);
   spent[1]=4;
   await saveCreature({...row.creature,spell_slots_spent:spent},'default',row.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('magic');
 assert.equal(await page.locator('#sheet-play-view .play-slots>.play-button').count(),shown.length);
 assert.match(await page.locator('#sheet-play-view .play-slots>.play-button').first().textContent(),/0\s*\/\s*4/);

 // With every maximum at zero, the slot box and Manage action remain visible.
 await page.evaluate(async()=>{
   const {listCreatures,saveCreature}=await import('/creatures.js');
   const row=(await listCreatures())[0];
   await saveCreature({...row.creature,classes:[],class:'',subclass:'',
     spell_slots_manual:true,spell_slots_automatic:false,
     spell_slots_total:Array(10).fill(0),pact_slots_total:0,pact_slot_level:1,
     created_spell_slots:Array(10).fill(0),origin_spell_grants:[]},
     'default',row.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('magic');
 assert.equal(await page.locator('#sheet-play-view .play-slots>.play-button').count(),0);
 assert.equal(await page.locator('#sheet-play-view .play-slots-empty').count(),1);
 assert.equal(await page.locator('#sheet-play-view .play-card-head .play-button[title="Gestisci slot"]').count(),1);
 await page.locator('#sheet-play-view .play-card-head .play-button[title="Gestisci slot"]').click();
 await page.locator('#magic-tools-dialog .magic-slot-manager-row').first().locator('.magic-slot-maximum').click();
 await page.locator('#sheet-score-formula-dialog[open]').waitFor();
 assert.equal(await page.locator('#sheet-score-formula-dialog').getAttribute('data-score-target'),'slot:1');
 await page.locator('#sheet-score-formula-dialog [data-act="close-score-formula"]').click();
 assert.deepEqual(errors,[],'No browser exceptions');
 assert.deepEqual(missing,[],'No missing PWA assets');
}finally{
 await f.close();
}
