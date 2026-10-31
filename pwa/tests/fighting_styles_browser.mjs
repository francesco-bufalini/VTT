// Regression: generic Fighting Style learning must use the same fully
// scrollable catalog list and search behavior as Artificer infusion learning.
import assert from 'node:assert/strict';
import {browserFixture} from './browser_fixture.mjs';

const f=await browserFixture();
const {page,origin,sheet}=f;
const progression='optional:class:phb:ranger:fs-r';

try{
 await page.goto(origin);
 await page.locator('[data-act="library-add"]').waitFor();
 await page.evaluate(async()=>{
  const {createCreature,saveCreature}=await import('/creatures.js');
  const saved=await createCreature('character','Ranger fighting style layout');
  await saveCreature({...saved.data,rules_version:'2014',
   class:'Ranger',class_source:'PHB',level:2,
   classes:[{name:'Ranger',source:'PHB',level:2},{name:'Artificer',source:'TCE',level:2}],
   attack_ability:'dex',inventory:['main','off'].map(slot=>({id:'blade-'+slot,name:'Lama '+slot,
    custom_item_type:'weapon',type:'M',weapon_category:'simple',properties:['L','F'],damage:'1d6',quantity:1,equipped_slots:[slot]})),
   abilities:{str:12,dex:16,con:13,int:10,wis:14,cha:8}},'default',saved.revision);
 });
 await page.reload();
 await page.locator('[data-act="open"]').click();
 await sheet('magic');

 const opener=page.locator('#sheet-play-view [data-act="power-selection-open"]'+
  '[data-power-selection-id="'+progression+'"][data-power-stage="learned"]');
 const openPicker=()=>opener.click();
 const snapshot=()=>page.evaluate(async()=>{
  const {listCreatures}=await import('/creatures.js');
  const {calculateSheet,loadRuleCatalogs}=await import('/sheet_rules.js');
  const record=(await listCreatures())[0].creature;
  const calculated=calculateSheet(record,await loadRuleCatalogs());
  return {record,offhand:calculated.attacks.find(row=>row.id==='item:off:blade-off')?.damage};
 });
 for(const [width,height] of [[390,844],[1440,900]]){
  await page.setViewportSize({width,height});
  await openPicker();
  const dialog=page.locator('#power-selection-dialog');
  await dialog.waitFor({state:'visible'});
  assert.equal(await dialog.locator('.benefit-custom-option, [data-power-custom-name]').count(),0,
    'No homebrew creator below the known-options list');
  assert.equal(await dialog.locator('[data-act="power-selection-close"]').count(),1,
    'The header close control is sufficient; no footer follows the list');
  const results=dialog.locator('.learning-picker-results');
  const geometry=await results.evaluate(root=>{
   const r=root.getBoundingClientRect(),rows=[...root.querySelectorAll('.magic-catalog-row')];
   const first=rows[0]?.getBoundingClientRect();
   const levels=[...root.querySelectorAll('.magic-level')].map(row=>row.getBoundingClientRect().height);
   return {count:rows.length,clientHeight:root.clientHeight,scrollHeight:root.scrollHeight,
    firstVisible:!!first&&first.height>=30&&first.top>=r.top-1&&first.bottom<=r.bottom+1,
    rowHeights:rows.map(row=>row.getBoundingClientRect().height),levels,
    fitsWidth:r.left>=0&&r.right<=innerWidth+1};
  });
  assert(geometry.count>=6,'All style options must appear, not a truncated first row');
  assert(geometry.firstVisible,'The first complete style must be visible');
  assert(geometry.rowHeights.every(n=>n>=30),'No style row may collapse or be cropped');
  assert(geometry.fitsWidth,'The result list must fit the viewport');
  assert(geometry.levels.every(n=>n>=40),'Grouped styles must not shrink below their contents');

  await results.evaluate(root=>{root.scrollTop=root.scrollHeight;});
  const lastVisible=await results.evaluate(root=>{
   const row=[...root.querySelectorAll('.magic-catalog-row')].at(-1);
   const rr=root.getBoundingClientRect(),r=row?.getBoundingClientRect();
   return !!r&&r.height>=30&&r.top>=rr.top-1&&r.bottom<=rr.bottom+1;
  });
  assert(lastVisible,'Scrolling must reveal the complete last style');

  const query=dialog.locator('[data-power-search]');
  await query.fill('Two-Weapon Fighting');
  assert.equal(await results.locator('.magic-catalog-row').count(),1,
   'Search must repaint the list, just as infusion learning does');
  const label=await results.locator('.magic-catalog-name').innerText();
  assert.match(label,/Two-Weapon Fighting/);

  if(width===390){
   await results.locator('[data-act="power-selection-toggle"]').click();
   // The picker saves and renders asynchronously before reopening. Waiting for
   // the previous dialog's open flag would race the actual persistence.
   await page.waitForFunction(async id=>{
    const {listCreatures}=await import('/creatures.js');
    return !!(await listCreatures())[0]?.creature?.power_selections?.[id]?.learned?.length;
   },progression);
   // Persistence is the contract: collapsed source cards need not expose
   // their learned labels until expanded.
   assert((await snapshot()).record.power_selections?.[progression]?.learned?.length>=1);
   await page.locator('#power-selection-dialog [data-act="power-selection-close"]').last().click();
  }else await dialog.locator('[data-act="power-selection-close"]').last().click();
 }
 // Learning does not apply effects. The learned entry is the same clickable
 // card row as an infusion and exposes application without an object picker.
 await page.setViewportSize({width:390,height:844});
 const style=page.locator('#sheet-play-view [data-act="benefit-option-open"]');
 assert.equal(await style.count(),1);
 const styleCard=style.locator('xpath=ancestor::section[contains(@class,"play-card")][1]');
 const infusionCard=page.locator('#sheet-play-view .play-infusion-card').filter({has:page.getByRole('heading',{name:'Infusioni',exact:true})});
 assert.equal(await styleCard.getAttribute('class'),await infusionCard.getAttribute('class'));
 assert.equal((await snapshot()).offhand,'1d6');
 assert.equal((await snapshot()).record.optional_features_catalog.length,0,'Learning creates no separate optional trait');
 await style.click();
 const action=page.locator('#benefit-option-dialog');
 await action.waitFor({state:'visible'});
 assert.equal(await action.locator('input,select,[data-infusion-object-search]').count(),0);
 await action.locator('[data-act="benefit-option-apply"]').click();
 await action.waitFor({state:'detached'});
 assert.equal((await snapshot()).offhand,'1d6 + 3');
 assert.equal((await snapshot()).record.power_applications[progression].length,1);
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('magic');
 assert.equal(await style.locator('.play-infusion-state.is-active').count(),1);
 await style.click();
 assert.equal(await action.locator('[data-act="benefit-option-apply"]').innerText(),'Disattiva');
 await action.locator('[data-act="benefit-option-apply"]').click();await action.waitFor({state:'detached'});
 assert.equal((await snapshot()).offhand,'1d6');
 assert.equal((await snapshot()).record.power_selections[progression].learned.length,1);
 assert.equal((await snapshot()).record.power_applications[progression].length,0);
 const featureOpenerClass=await opener.getAttribute('class');
 await f.shot('fighting-style-infusion-shared-mobile');
 await page.setViewportSize({width:1440,height:900});await f.shot('fighting-style-infusion-shared-desktop');
 // A separate Wizard checks the spell picker without changing Fighting Style data.
 await page.goto(origin);
 await page.evaluate(async()=>{
  const {createCreature,saveCreature}=await import('/creatures.js');
  const saved=await createCreature('character','Spell learner layout');
  await saveCreature({...saved.data,rules_version:'2014',class:'Wizard',class_source:'PHB',
   level:5,classes:[{name:'Wizard',source:'PHB',level:5}],
   abilities:{str:10,dex:14,con:12,int:18,wis:12,cha:10}},'default',saved.revision);
 });
 await page.reload();
 await page.locator('[data-act="open"][aria-label="Apri scheda di Spell learner layout"]').click();
 await sheet('magic');
 // The visible sheet proxies the native spell action via data-act=sheet-proxy.
 const spellOpen=page.locator('#sheet-play-view .play-magic-class-card:not(.play-infusion-card) .play-magic-selection .play-button')
  .filter({hasText:/Gestisci incantesimi conosciuti|Impara.*incantesimi/i}).first();
 assert.equal(await spellOpen.getAttribute('class'),featureOpenerClass,
  'Spells and optional features use the same opener button styling');
 await spellOpen.click();
 const spellPicker=page.locator('#magic-tools-dialog');
 await spellPicker.waitFor({state:'visible'});
 assert.equal(await spellPicker.locator('.learning-picker-results').count(),1,
  'Spells use the same grouped, scrolling learning list');
 assert.equal(await spellPicker.locator('#spell-search').count(),1);
 assert.equal(await spellPicker.locator('#spell-learn-filter').count(),1);
 assert.equal(await spellPicker.locator('.magic-tools-body > .actions').count(),0,
  'The spell learner has no footer below the choices');
 await spellPicker.locator('[data-act="magic-tool-close"]').first().click();
 assert.deepEqual(f.errors,[]);assert.deepEqual(f.missing,[]);
 console.log('PASS: Fighting Styles and infusions share visible cards and learners; manual application changes real effects, persists and needs no object');
}finally{await f.close();}
