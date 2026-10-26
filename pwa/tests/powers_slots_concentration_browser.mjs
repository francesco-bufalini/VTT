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
 assert.equal(await page.locator('#sheet-play-view .play-slots>.play-button').count(),9,
   'Nine slot levels remain visible even if a level has no slots');
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
 const before=Number((await record()).spell_slots_spent?.[1]||0);
 await page.locator('#magic-tools-dialog .magic-slot-manager-row').first().locator('[data-act="slot-use"]').click();
 await page.waitForFunction(previous=>Number(document.querySelector('.magic-slot-manager-row .magic-tracker-count strong')?.textContent)===2, before);
 assert.equal(Number((await record()).spell_slots_spent?.[1]||0),before+1);
 assert.equal(await page.locator('#magic-tools-dialog[open]').count(),1,
   'Slot editor remains open after consumption');
 await page.locator('#magic-tools-dialog .magic-slot-manager-row').first().locator('[data-act="slot-recover"]').click();
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
 assert.equal(await page.locator('#sheet-play-view .play-slots>.play-button').count(),9);
 assert.match(await page.locator('#sheet-play-view .play-slots>.play-button').first().textContent(),/0\s*\/\s*4/);
 assert.deepEqual(errors,[],'No browser exceptions');
 assert.deepEqual(missing,[],'No missing PWA assets');
}finally{
 await f.close();
}
