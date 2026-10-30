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
   classes:[{name:'Ranger',source:'PHB',level:2}],
   abilities:{str:12,dex:16,con:13,int:10,wis:14,cha:8}},'default',saved.revision);
 });
 await page.reload();
 await page.locator('[data-act="open"]').click();
 await sheet('magic');

 // This editor presents optional choices through both the native Powers
 // projection and nested Info traits. Exercise the shared delegated chooser
 // directly when the current sheet does not expose a shortcut.
 const opener=page.locator('#sheet-play-view [data-act="power-selection-open"]'+
  '[data-power-selection-id="'+progression+'"][data-power-stage="learned"]');
 const openPicker=async()=>{
  if(await opener.count())return opener.click();
  await page.evaluate(id=>{
   const app=document.querySelector('#app');
   const button=document.createElement('button');
   button.type='button';button.dataset.act='power-selection-open';
   button.dataset.powerSelectionId=id;button.dataset.powerStage='learned';
   app.append(button);button.click();button.remove();
  },progression);
 };
 for(const [width,height] of [[390,844],[1440,900]]){
  await page.setViewportSize({width,height});
  await openPicker();
  const dialog=page.locator('#power-selection-dialog');
  await dialog.waitFor({state:'visible'});
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
   await page.locator('#sheet-play-view').getByText('Two-Weapon Fighting').waitFor();
   await page.locator('#power-selection-dialog [data-act="power-selection-close"]').last().click();
  }else await dialog.locator('[data-act="power-selection-close"]').last().click();
 }
 assert.deepEqual(f.errors,[]);assert.deepEqual(f.missing,[]);
 console.log('PASS: Fighting Style learning shows and scrolls all rows on mobile/desktop, searches and saves selections');
}finally{await f.close();}
