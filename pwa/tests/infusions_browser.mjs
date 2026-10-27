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
 await page.locator('#sheet-play-view [data-sheet-context="infusions"]').click();
 await page.locator('#infusion-available').selectOption({label:'Enhanced Arcane Focus'});
 await page.locator('[data-act="infusion-learn"]').click();
 await page.locator('[data-act="infusion-prepare"]').waitFor();
 await page.locator('#sheet-context-dialog [data-act="sheet-context-close"]').click();
 const infusion=page.locator('#sheet-play-view [data-act="infusion-open"]');
 assert.equal(await infusion.count(),1,'Known infusions appear as one spell-style row');
 assert.equal(await page.locator('#sheet-play-view .play-infusion-card .casting-statistics').count(),0);
 assert.equal(await infusion.locator('.play-infusion-state').getAttribute('title'),'Non preparata');
 await infusion.click();
 const actionDialog=page.locator('#infusion-action-dialog');
 await actionDialog.waitFor({state:'visible'});
 assert(await actionDialog.locator('[data-act="infusion-dialog-activate"]').isDisabled());
 await actionDialog.locator('[data-act="infusion-dialog-prepare"]').click();
 await infusion.click();
 assert.equal(await infusion.locator('.play-infusion-state').getAttribute('title'),'Preparata');
 assert.equal(await actionDialog.locator('[data-act="infusion-dialog-activate"]').innerText(),'Attiva');
 await actionDialog.locator('#infusion-item-target').selectOption('0');
 await actionDialog.locator('[data-act="infusion-dialog-activate"]').click();
 assert.equal(await infusion.locator('.play-infusion-state').getAttribute('title'),'Attiva');
 await infusion.click();
 assert.equal(await actionDialog.locator('[data-act="infusion-dialog-remove"]').count(),1);
 await actionDialog.locator('[data-act="infusion-dialog-close"]').click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return !!(await listCreatures())[0].creature.inventory[0].infusion;});
 const inspect=()=>page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');const {calculateSheet,loadRuleCatalogs}=await import('/sheet_rules.js');const c=(await listCreatures())[0].creature;return {c,d:calculateSheet(c,await loadRuleCatalogs())};});
 assert.equal((await inspect()).d.values.spell_attack,0);
 await page.evaluate(async()=>{const {listCreatures,saveCreature}=await import('/creatures.js');const s=(await listCreatures())[0];s.creature.inventory[0].attuned=true;await saveCreature(s.creature,'default',s.revision);});
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('conditions');
 assert.equal((await inspect()).d.values.spell_attack,2);
 assert.match(await page.locator('#sheet-play-view').textContent(),/Capacità magiche attive/);
 assert.match(await page.locator('#sheet-play-view').textContent(),/Enhanced Arcane Focus/);
 for(const width of [390,1440]){await page.setViewportSize({width,height:1000});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await shot('infusions-'+width);}
 await page.evaluate(async()=>{const {listCreatures,saveCreature}=await import('/creatures.js');const {calculateSheet,loadRuleCatalogs}=await import('/sheet_rules.js');const s=(await listCreatures())[0];const d=calculateSheet(s.creature,await loadRuleCatalogs());s.creature.origin_enabled={[d.features.find(f=>f.name==='Infuse Item').origin_id]:false};await saveCreature(s.creature,'default',s.revision);});
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('conditions');
 assert.equal((await inspect()).d.values.spell_attack,0);
 assert.equal(await page.locator('#sheet-play-view').getByText('Capacità magiche attive',{exact:true}).count(),0);
 assert.deepEqual(f.errors,[]);assert.deepEqual(f.missing,[]);assert.deepEqual(f.writes,[]);
 console.log('PASS: Chrome infusion learn/prepare/item targeting, attunement bonus, active conditions, trait disabling, 390/1440px');
}finally{await f.close();}
