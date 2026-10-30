import assert from 'node:assert/strict';
import {browserFixture} from './browser_fixture.mjs';
const f=await browserFixture();const {page,origin,sheet,shot}=f;
try{
 await page.goto(origin);await page.locator('[data-act="library-add"]').waitFor();
 await page.evaluate(async()=>{
  const {createCreature,saveCreature}=await import('/creatures.js');const saved=await createCreature('character','Infusion test');
  await saveCreature({...saved.data,class:'Artificer',class_source:'TCE',level:10,
   classes:[{name:'Artificer',source:'TCE',level:10}],abilities:{str:12,dex:10,con:12,int:18,wis:10,cha:10},
   inventory:[{id:'local_wand',name:'Arcane Wand',custom_item_type:'other',quantity:1,rarity:'none',active:true,equipped:true,attuned:false}]
  },'default',saved.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('magic');
 await page.locator('#sheet-play-view [data-act="power-selection-open"][data-power-selection-id="artificer_infusions"][data-power-stage="learned"]').click();
 const learner=page.locator('#power-selection-dialog');
 await learner.waitFor({state:'visible'});
 await learner.locator('[data-power-search]').fill('Enhanced Arcane Focus');
 await learner.locator('[data-act="power-selection-details"][data-power-option-id="optional:tce:enhanced-arcane-focus"]').click();
 assert.match(await page.locator('#benefit-option-dialog .magic-spell-description').innerText(),/spell|attack|bonus/i);
 await page.locator('#benefit-option-dialog [data-act="benefit-option-close"]').first().click();
 await learner.locator('[data-act="power-selection-toggle"][data-power-option-id="optional:tce:enhanced-arcane-focus"]').click();
 await learner.locator('[data-act="power-selection-close"]').first().click();
 const infusion=page.locator('#sheet-play-view [data-act="benefit-option-open"]');
 assert.equal(await infusion.count(),1,'Known infusion appears once with spell-like UI');
 assert.equal(await page.locator('#sheet-play-view .play-infusion-card .casting-statistics').count(),0);
 assert.equal(await infusion.locator('.play-infusion-state').getAttribute('title'),'Conosciuta');
 assert.equal(await page.locator('#sheet-play-view [data-mode="prepare"]').count(),0);
 await infusion.click();
 const actionDialog=page.locator('#benefit-option-dialog');
 await actionDialog.waitFor({state:'visible'});
 assert.match(await actionDialog.locator('.magic-spell-description').innerText(),/spell|attack|bonus/i);
 assert.equal((await actionDialog.locator('[data-act="benefit-option-apply"]').innerText()).trim(),'Applica');
 assert(await actionDialog.locator('[data-act="benefit-option-apply"]').isDisabled());
 assert(await actionDialog.locator('[data-act="benefit-option-apply"]').isDisabled());
 assert.equal(await actionDialog.locator('[data-act="benefit-target-choose"][data-index="0"]').count(),1,
   'All compatible owned items must be visible without searching');
 await page.setViewportSize({width:390,height:860});
 assert(await page.evaluate(()=>{
   const dialog=document.querySelector('#benefit-option-dialog');
   const search=dialog?.querySelector('.benefit-target-search input');
   const rect=search?.getBoundingClientRect(),bounds=dialog?.getBoundingClientRect();
   return !!rect&&!!bounds&&rect.left>=bounds.left-1&&rect.right<=bounds.right+1&&
     document.documentElement.scrollWidth<=innerWidth;
 }), 'Search must not overflow its dialog at 390px');
 await actionDialog.locator('[data-benefit-target-search]').fill('Arcane');
 await actionDialog.locator('[data-act="benefit-target-choose"][data-index="0"]').click();
 assert(await actionDialog.locator('[data-act="benefit-option-apply"]').isEnabled());
 await actionDialog.locator('[data-act="benefit-option-apply"]').click();
 await actionDialog.waitFor({state:'detached'});
 assert.equal(await infusion.locator('.play-infusion-state').getAttribute('title'),'Attiva');
 await infusion.click();
 assert.equal(await actionDialog.locator('[data-act="benefit-option-remove"]').count(),1);
 await actionDialog.locator('[data-act="benefit-option-close"]').first().click();
 await sheet('magic');
 // Replicate is learned as a separate infusion choice for each item type.
 await page.locator('#sheet-play-view [data-act="power-selection-open"][data-power-selection-id="artificer_infusions"][data-power-stage="learned"]').click();
 await learner.locator('[data-power-search]').fill('Replicate Magic Item');
 assert(await learner.locator('[data-power-option-id^="optional:tce:replicate-magic-item|"]').count()>10);
 assert.equal(await learner.locator('[data-power-option-id="optional:tce:replicate-magic-item"]').count(),0);
 await learner.locator('[data-act="power-selection-close"]').first().click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return !!(await listCreatures())[0].creature.inventory[0].option_extensions?.length;});
 const inspect=()=>page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');const {calculateSheet,loadRuleCatalogs}=await import('/sheet_rules.js');const c=(await listCreatures())[0].creature;return {c,d:calculateSheet(c,await loadRuleCatalogs())};});
 assert.equal((await inspect()).d.values.spell_attack,0);
 await page.evaluate(async()=>{const {listCreatures,saveCreature}=await import('/creatures.js');const s=(await listCreatures())[0];s.creature.inventory[0].attuned=true;await saveCreature(s.creature,'default',s.revision);});
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('conditions');
 assert.equal((await inspect()).d.values.spell_attack,2);
 assert.match(await page.locator('#sheet-play-view').textContent(),/Capacità/);
 assert.match(await page.locator('#sheet-play-view').textContent(),/Enhanced Arcane Focus/);
 for(const width of [390,1440]){await page.setViewportSize({width,height:1000});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await shot('infusions-'+width);}
 await page.evaluate(async()=>{const {listCreatures,saveCreature}=await import('/creatures.js');const {calculateSheet,loadRuleCatalogs}=await import('/sheet_rules.js');const s=(await listCreatures())[0];const d=calculateSheet(s.creature,await loadRuleCatalogs());s.creature.origin_enabled={[d.features.find(f=>f.name==='Infuse Item').origin_id]:false};await saveCreature(s.creature,'default',s.revision);});
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('conditions');
 assert.equal((await inspect()).d.values.spell_attack,0);
 assert.equal(await page.locator('#sheet-play-view').getByText('Enhanced Arcane Focus',{exact:true}).count(),0);
 assert.deepEqual(f.errors,[]);assert.deepEqual(f.missing,[]);assert.deepEqual(f.writes,[]);
 console.log('PASS: Chrome infusion learn/use, 5etools details, immediate compatible inventory, mobile overflow, attunement, trait disabling');
}finally{await f.close();}
