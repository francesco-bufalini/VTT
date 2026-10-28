import assert from 'node:assert/strict';
import {browserFixture} from './browser_fixture.mjs';

const f=await browserFixture();
const {page,origin,errors}=f;
try{
 await page.setViewportSize({width:390,height:844});
 await page.goto(origin);
 await page.locator('[data-act="library-add"]').waitFor();
 const id=await page.evaluate(async()=>{
  const {createCreature,saveCreature}=await import('/creatures.js');
  const row=await createCreature('character','Druida della Costa');
  await saveCreature({...row.data,rules_version:'2014',class:'Druid',class_source:'PHB',
   subclass:'Circle of the Land',subclass_source:'PHB',level:3,
   classes:[{name:'Druid',source:'PHB',subclass:'Circle of the Land',subclass_source:'PHB',level:3}],
   abilities:{str:10,dex:14,con:12,int:10,wis:16,cha:10}},'default',row.revision);
  return row.data.id;
 });
 await page.reload();
 await page.locator('[data-act="open"]').click();
 await page.locator('#sheet-play-view').waitFor();
 const choice=await page.evaluate(async id=>{
  const {loadCreature}=await import('/creatures.js');
  const {calculateSheet,loadRuleCatalogs}=await import('/sheet_rules.js');
  const sheet=calculateSheet((await loadCreature(id)).data,await loadRuleCatalogs());
  if(sheet.origin_spells.some(row=>row.origin_name==='Circle Spells'))throw Error('Unchosen terrain granted spells');
  return sheet.origin_spell_variant_choices[0];
 },id);
 // Open the same pending-choice action used by the trait card and sheet notice.
 await page.evaluate(choice=>{
  const button=document.createElement('button');button.dataset.act='pending-choice-open';
  button.dataset.choiceId=choice.id;document.querySelector('#app').append(button);button.click();button.remove();
 },choice);
 await page.locator('#pending-choice-dialog').waitFor();
 await page.locator('#pending-choice-dialog input[value="coast"]').check();
 await page.locator('#pending-choice-dialog [data-act="pending-choice-save"]').click();
 await page.locator('#pending-choice-dialog').waitFor({state:'detached'});
 const verify=()=>page.evaluate(async({id,owner})=>{
  const {loadCreature}=await import('/creatures.js');
  const {calculateSheet,loadRuleCatalogs}=await import('/sheet_rules.js');
  const record=(await loadCreature(id)).data;
  return {selected:record.origin_spell_variants?.[owner],spells:calculateSheet(record,await loadRuleCatalogs())
   .origin_spells.filter(row=>row.origin_id===owner).map(row=>({id:row.spell_id,payment:row.payment_mode}))};
 },{id,owner:choice.origin_id});
 await page.waitForFunction(async({id,owner})=>{
  const {loadCreature}=await import('/creatures.js');
  return (await loadCreature(id)).data.origin_spell_variants?.[owner]==='coast';
 },{id,owner:choice.origin_id});
 const saved=await verify();
 assert.deepEqual(saved.spells.map(row=>row.id).sort(),['phb2014_mirror_image','phb2014_misty_step']);
 assert(saved.spells.every(row=>row.payment==='slot'));
 await page.reload();await page.locator('[data-act="open"]').click();
 await page.locator('#sheet-play-view').waitFor();
 assert.deepEqual(await verify(),saved);
 assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
 assert.deepEqual(errors,[]);
 console.log('PASS: mobile trait option picker persists one terrain and correct slot-paid spells across reload');
}finally{await f.close();}
