import assert from 'node:assert/strict';
import {browserFixture,seedPlayCreature} from './browser_fixture.mjs';
const f=await browserFixture({live:true});const {page,context,origin,errors,missing,writes,sheet,popup,dismiss,shot}=f;
const record=()=>page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature;});
try{
 await seedPlayCreature(page,origin);
 for(const viewport of [{width:320,height:740},{width:360,height:800},{width:390,height:844},{width:430,height:932},{width:844,height:390}]){
  await page.setViewportSize(viewport);
  for(const key of ['info','stats','battle','actions','magic','inventory','traits','conditions','origins']){
   await sheet(key);assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),key+' overflow at '+viewport.width);
   assert.equal(await page.locator('#sheet-play-view input:not([type=search]),#sheet-play-view select,#sheet-play-view textarea').count(),0,'Edits belong in contextual windows: '+key);
   if(viewport.width===390)await shot(key);
  }
 }
 await page.setViewportSize({width:390,height:844});
 await sheet('info');await popup('identity');await page.locator('#sheet-context-dialog [data-field="name"]').fill('Lyria, guardiana della Luna');
 await page.keyboard.press('Escape');await page.locator('#sheet-context-dialog').waitFor({state:'detached'});
 assert.equal((await record()).name,'Lyria, guardiana della Luna');assert.match(await page.locator('.play-identity h2').textContent(),/guardiana/);
 await sheet('battle');
 const weaponPanel=page.locator('#sheet-play-view [data-battle-action="attacks"]');
 const movementPanel=page.locator('#sheet-play-view [data-battle-action="movement"]');
 assert.equal(await weaponPanel.count(),1);assert.equal(await weaponPanel.getAttribute('open'),'');
 assert.match(await weaponPanel.locator('summary.play-battle-summary').textContent(),/Attacchi fisici/);
 const mainAttack=weaponPanel.locator('[data-attack-id="item:local_sword"]');
 assert.equal(await mainAttack.count(),1);
 assert.equal(await mainAttack.locator('details').getAttribute('open'),null);
 assert.match(await mainAttack.locator('.play-battle-attack-copy small').textContent(),/1d20 \\+ [0-9]+ · Mischia/);
 assert.equal(await weaponPanel.locator('[data-attack-id="item:local_sword"]').count(),1);
 assert.equal(await weaponPanel.locator('.play-battle-attack-copy strong').filter({hasText:/^Attaccare$/}).count(),0);
 await mainAttack.locator('summary').click();
 assert.equal(await mainAttack.locator('details').getAttribute('open'),'');
 assert.match(await mainAttack.locator('.play-battle-attack-expanded').textContent(),/The most common action/);
 await mainAttack.locator('summary').click();
 await mainAttack.locator('[data-target="attack_hit:item:local_sword"]').click();
 assert.equal(await mainAttack.locator('details').getAttribute('open'),null,'Dice trigger must not expand description');
 assert.match(await page.locator('#sheet-roll-dialog [data-roll-formula]').textContent(),/1d20/);
 await page.locator('#sheet-roll-dialog [data-act="close-sheet-roll"]').click();
 assert.equal(await movementPanel.getAttribute('open'),null);
 await movementPanel.locator('summary.play-battle-summary').click();
 assert(await movementPanel.locator('[data-action-timing="action"]').textContent().then(t=>t.includes('Scattare')));
 assert(await movementPanel.locator('[data-action-timing="movement"]').textContent().then(t=>t.includes('Muoversi')));
 await sheet('stats');await sheet('battle');
 assert.equal(await page.locator('#sheet-play-view [data-battle-action="movement"]').getAttribute('open'),'');
 await page.locator('#sheet-play-view [data-act="hp-damage"]').click();await page.locator('#hp-adjust-amount').fill('10');await page.locator('#hp-adjust-confirm').click();
 await page.waitForFunction(()=>document.querySelector('#sheet-play-view [data-read-field="current_hp"]')?.textContent==='37');
 assert.deepEqual([(await record()).temporary_hp,(await record()).second_form_hp,(await record()).current_hp],[0,0,37]);
 await page.locator('#sheet-play-view [data-tracker-id="focus"]').click();await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.resource_tracker_spent.focus===3;});
 const speedCard=page.locator('#sheet-play-view [data-sheet-context="movement"]');
 assert.equal(await speedCard.locator('.vtt-action-glyph--pack-1.vtt-action-glyph--slot-9').count(),1,'Movement dash icon');
 assert.equal(await movementPanel.locator('summary.play-battle-summary .vtt-action-glyph--pack-1.vtt-action-glyph--slot-9').count(),1);
 assert.match(await speedCard.textContent(),/Camminata/);
 await popup('movement');assert.match(await page.locator('#sheet-context-dialog .sheet-context-body').textContent(),/Salti|Camminata/);await dismiss();
 await popup('defense');assert.match(await page.locator('#sheet-context-dialog .sheet-context-body').textContent(),/Formula CA naturale/);assert.doesNotMatch(await page.locator('#sheet-context-dialog .sheet-context-body').textContent(),/Iniziativa/);
 assert.equal(await page.locator('#sheet-context-dialog footer,#sheet-context-dialog .formula-bonus,#sheet-context-dialog .hint').count(),0);
 assert.equal(await page.locator('#sheet-context-dialog .battle-ac-manage').count(),1);
 await dismiss();
 await page.locator('#sheet-play-view [data-target="initiative"]').click();
 assert.equal(await page.locator('#sheet-roll-dialog .sheet-roll-provenance').count(),0);
 assert.equal(await page.locator('#sheet-roll-dialog [data-roll-chat-status]:visible').count(),0);
 await page.locator('#sheet-roll-dialog [data-act="close-sheet-roll"]').click();
 await popup('rests');await page.locator('#sheet-context-dialog [data-act="tracker-short"]').click();await dismiss();assert.equal((await record()).resource_tracker_spent.focus,undefined);
 await sheet('stats');await page.locator('[data-play-search]').fill('furt');assert.equal(await page.locator('.play-skills [data-play-filter]:visible').count(),1);
 await page.locator('#sheet-play-view [data-target="skill:stealth"]').click();await page.locator('[data-act="roll-sheet-confirm"]').click();assert(Number(await page.locator('.dice-result').textContent())>0);await page.locator('[data-act="close-sheet-roll"]').click();
 await sheet('inventory');await page.locator('[data-play-search]').fill('pozione');await popup('item:1');await page.locator('#sheet-context-dialog [data-item-key="quantity"]').fill('5');await dismiss();assert.equal((await record()).inventory[1].quantity,5);assert.match(await page.locator('#sheet-play-view [data-sheet-context="item:1"]').textContent(),/×5/);
 assert.equal(await page.locator('[data-play-search]').inputValue(),'pozione');assert.equal(await page.locator('#sheet-play-view [data-play-filter]:visible').count(),1);await page.locator('[data-play-search]').fill('');
 await popup('item:0');assert(await page.locator('#sheet-context-dialog .inventory-description').isVisible());await shot('item-popup');await dismiss();
 await popup('inventory-add');await page.locator('#sheet-context-dialog [data-act="document-add"]').click();await page.locator('#sheet-context-dialog .document-edit > summary').click();await page.locator('#sheet-context-dialog [data-document-part="title"]').fill('Lettera della Luna');await page.locator('#sheet-context-dialog [data-document-part="body"]').fill('Raggiungete il tempio al tramonto.');await dismiss();
 assert(await page.locator('#sheet-play-view').textContent().then(t=>t.includes('Lettera della Luna')));
 await sheet('conditions');assert.match(await page.locator('#sheet-play-view').textContent(),/Avvelenato/);assert.match(await page.locator('#sheet-play-view').textContent(),/Livello 2/);await popup('conditions');await page.locator('#sheet-context-dialog [data-condition="poisoned"]').uncheck();await dismiss();assert.equal((await record()).conditions.includes('poisoned'),false);
 await popup('apply-spell');await page.locator('#condition-spell-picker').selectOption('phb2014_light');await page.locator('#sheet-context-dialog [data-act="condition-add-spell"]').click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.proficiency_origins?.some(r=>r.id==='spell:phb2014_light'&&r.applied===true);});
 await page.waitForFunction(()=>/Incantesimi applicati[\s\S]*Light/.test(document.querySelector('#sheet-play-view')?.textContent||''));
 assert.match(await page.locator('#sheet-play-view').textContent(),/Incantesimi applicati[\s\S]*Light/);
 await sheet('battle');assert.match(await page.locator('.play-status-strip').textContent(),/Light/);
 await sheet('conditions');await page.locator('[data-act="condition-remove-spell"][data-spell-id="phb2014_light"]').click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return !(await listCreatures())[0].creature.proficiency_origins?.some(r=>r.id==='spell:phb2014_light');});
 await sheet('magic');await popup('magic-tools');assert.equal(await page.locator('#sheet-context-dialog .magic-toolbar button:visible').count(),6);await page.locator('#sheet-context-dialog [data-magic-tool="slots"]').click();await page.locator('#magic-tools-dialog').waitFor();assert.equal(await page.locator('#sheet-context-dialog').count(),0);await page.locator('[data-act="magic-tool-close"]').click();
 await sheet('traits');await popup('trait-notes');await page.locator('#sheet-context-dialog textarea').fill('Una promessa mantenuta.');await dismiss();assert.equal((await record()).additional_traits,'Una promessa mantenuta.');
 // All primary context links must resolve on populated and empty sections.
 for(const key of ['info','stats','battle','inventory','traits','conditions']){
  await sheet(key);const keys=await page.locator('#sheet-play-view [data-sheet-context]').evaluateAll(nodes=>nodes.map(n=>n.dataset.sheetContext));
  for(const contextKey of keys){await popup(contextKey);assert(await page.locator('.sheet-context-body').textContent().then(t=>t.trim().length>0),key+': '+contextKey);await dismiss();}
 }
 await sheet('actions');await page.locator('[data-timing-choice="reaction"]').click();assert.match(await page.locator('#sheet-play-view').textContent(),/Incantesimi/);await page.locator('.play-card .play-list-row').first().click();await page.locator('#sheet-context-dialog').waitFor();await shot('action-popup');await dismiss();
 await page.waitForFunction(()=>!!navigator.serviceWorker.controller,null,{timeout:30000});await context.setOffline(true);await page.reload();await page.locator('[data-act="open"]').click();await sheet('inventory');assert.match(await page.locator('#sheet-play-view').textContent(),/Lettera della Luna/);
 assert.deepEqual(errors,[]);assert.deepEqual(missing,[]);assert.deepEqual(writes,[]);
 console.log('PASS: 9 play sheets at 320/360/390/430px and landscape, contextual editing, HP, tracker recovery, skills, inventory descriptions/quantity, documents, conditions, spell tools, every context link and offline persistence.');
}finally{await f.close();}
