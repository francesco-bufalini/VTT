// Real Chrome, native HTTP routes, isolated IndexedDB. No user archive/session.
import assert from 'node:assert/strict';
import {browserFixture} from './browser_fixture.mjs';
const f=await browserFixture();const {page,origin,sheet,shot}=f;
const record=()=>page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature;});
const resources=async()=>{
 const panel=page.locator('[data-battle-action="resources"]');
 if(!await panel.evaluate(n=>n.open))await panel.locator('summary.play-battle-summary').click();
};
const seed=async(name,extra={})=>{
 await page.goto(origin);await page.locator('[data-act="create"]').waitFor();
 await page.evaluate(async({name,extra})=>{
  const {listCreatures,createCreature,saveCreature,removeCreature}=await import('/creatures.js');
  for(const row of await listCreatures())await removeCreature(row.creature.id,'default',row.revision);
  const saved=await createCreature('character','Prova '+name);
  await saveCreature({...saved.data,class:name,class_source:'PHB',level:5,classes:[{name,source:'PHB',level:5}],
   abilities:{str:18,dex:14,con:14,int:16,wis:16,cha:16},current_hp:10,max_hp_base:50,
   inventory:[{id:'axe',name:'Ascia di prova',custom_item_type:'weapon',type:'M',damage:'1d6',quantity:1,equipped_slots:['main']}],
   default_miniature_id:'ape',current_miniature_id:'ape',...extra},'default',saved.revision);
 },{name,extra});
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('battle');
 await resources();
};
const use=name=>page.getByRole('button',{name,exact:true});
try{
 await seed('Barbarian');
 await use('Attiva Ira').click();
 await page.waitForFunction(()=>document.querySelector('[aria-label="Disattiva Ira"]'));
 assert.equal(Object.values((await record()).resource_tracker_spent)[0],1);
 const calculated=await page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');const {calculateSheet,loadRuleCatalogs}=await import('/sheet_rules.js');return calculateSheet((await listCreatures())[0].creature,await loadRuleCatalogs());});
 assert.equal(calculated.attacks[0].damage,'1d6 + 6');
 const strength=page.locator('#sheet-play-view [data-target="ability_mod:str"]').first();
 for(const selector of ['[data-battle-action="checks"]','[data-action-ability="str"]']){
  const group=page.locator(selector);if(!await group.evaluate(n=>n.open))await group.locator(':scope > summary').click();
 }
 await strength.click();
 assert.match(await page.locator('[data-roll-formula]').textContent(),/2d20kh1/);
 await page.locator('[data-act="roll-sheet-confirm"]').click();
 assert.match(await page.locator('[data-roll-result]').textContent(),/vantaggio/);
 await page.locator('[data-act="close-sheet-roll"]').click();
 await sheet('conditions');assert.match(await page.locator('.feature-effect-summary').textContent(),/resistenza.*taglienti/);
 for(const width of [320,390,768]){
  await page.setViewportSize({width,height:844});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
 }
 await page.setViewportSize({width:390,height:844});await shot('rage-effects');
 await sheet('battle');await use('Disattiva Ira').click();
 await page.waitForFunction(()=>document.querySelector('[aria-label="Attiva Ira"]'));
 assert.equal(Object.values((await record()).resource_tracker_spent)[0],1);
 await seed('Fighter');await use('Usa Recuperare energie').click();
 const before=await record();await page.locator('[data-feature-cancel]').click();assert.deepEqual((await record()).resource_tracker_spent,before.resource_tracker_spent);
 await use('Usa Recuperare energie').click();await page.locator('[data-feature-confirm]').click();
 await page.locator('#class-feature-dialog').waitFor({state:'detached'});
 assert((await record()).current_hp>=16);assert.equal(Object.values((await record()).resource_tracker_spent)[0],1);
 await seed('Druid');
 const wild=page.locator('[data-act="battle-use-ability"]').filter({hasText:/Attiva/});
 await wild.first().click();await page.locator('.miniature-dialog').waitFor();
 assert.deepEqual((await record()).resource_tracker_spent,{});
 await page.locator('[data-miniature-close]').click();assert.deepEqual((await record()).resource_tracker_spent,{});
 await wild.first().click();await page.locator('[data-miniature-search]').fill('wolf');await page.locator('[data-miniature-id="wolf"]').click();
 assert.deepEqual((await record()).resource_tracker_spent,{},'selecting a preview cannot spend a use');
 await page.locator('[data-form-hp]').fill('11');await page.locator('[data-form-confirm]').click();
 await page.locator('.miniature-dialog').waitFor({state:'detached'});
 assert.equal((await record()).current_miniature_id,'wolf');assert.equal((await record()).second_form_hp,11);
 assert.equal(Object.values((await record()).resource_tracker_spent)[0],1);
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('battle');
 await resources();
 assert(await use('Disattiva Wild Shape').count()||await use('Disattiva Forma selvatica').count());
 await page.locator('#sheet-play-view [data-act="hp-damage"]').click();
 await page.locator('#hp-adjust-amount').fill('13');await page.locator('#hp-adjust-confirm').click();
 await page.locator('#form-depleted-dialog').waitFor();assert.equal((await record()).current_hp,8);
 await page.locator('[data-form-restore]').click();await page.locator('#form-depleted-dialog').waitFor({state:'detached'});
 assert.equal((await record()).current_miniature_id,'ape');assert.equal((await record()).second_form_max_hp,0);
 assert.equal(Object.values((await record()).resource_tracker_spent)[0],1);
 await seed('Druid');await wild.first().click();await page.locator('[data-miniature-search]').fill('wolf');await page.locator('[data-miniature-id="wolf"]').click();
 await page.setViewportSize({width:320,height:740});
 assert(await page.locator('.miniature-dialog').evaluate(n=>n.scrollWidth<=n.clientWidth));
 await shot('wild-shape-picker');await page.locator('[data-miniature-close]').click();
 assert.deepEqual(f.errors,[]);assert.deepEqual(f.missing,[]);assert.deepEqual(f.writes,[]);
 console.log('PASS: Chrome privilege effects, real advantage dice, cancellation without spending, healing, transformation preview/confirm, reload, second-form overflow and original appearance restoration.');
}catch(error){await shot('feature-failure');console.error((await page.locator('body').innerText()).slice(0,5000));throw error;}
finally{await f.close();}
