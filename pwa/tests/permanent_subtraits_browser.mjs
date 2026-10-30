import assert from 'node:assert/strict';
import {browserFixture} from './browser_fixture.mjs';
const f=await browserFixture(),{page,origin,sheet}=f;
const snapshot=()=>page.evaluate(async()=>{
 const {listCreatures}=await import('/creatures.js');
 const {calculateSheet,loadRuleCatalogs}=await import('/sheet_rules.js');
 const record=(await listCreatures())[0].creature;
 return {record,scores:calculateSheet(record,await loadRuleCatalogs()).abilities};
});
try{
 await page.goto(origin);await page.locator('[data-act="library-add"]').waitFor();
 await page.evaluate(async()=>{
  const {createCreature,saveCreature}=await import('/creatures.js');
  const saved=await createCreature('character','Sottotratti');
  await saveCreature({...saved.data,rules_version:'2014',class:'Ranger',class_source:'PHB',level:6,
   classes:[{name:'Ranger',source:'PHB',level:6}],
   abilities:{str:10,dex:10,con:10,int:10,wis:10,cha:10}},'default',saved.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('info');
 const asi=page.locator('.trait-subtrait[data-choice-id^="advancement-mode:"]').first();
 await asi.click();
 assert.equal(await page.locator('#power-selection-dialog').count(),0);
 await page.locator('#pending-choice-dialog input[value="ability:0"]').check();
 await page.locator('#pending-choice-dialog [data-act="pending-choice-save"]').click();
 await page.locator('#pending-choice-dialog input[value="str"]').check();
 await page.locator('#pending-choice-dialog [data-act="pending-choice-save"]').click();
 await page.locator('#pending-choice-dialog').waitFor({state:'detached'});
 const after=await snapshot();assert.equal(after.scores.str.score,12);
 assert.equal(after.record.origin_ability_choices?.length||0,0);
 assert(after.record.formula_bonuses.some(row=>row.target==='ability:str'&&row.expression==='2'));
 await sheet('magic');
 const id='ranger_favored_enemy_phb';
 const opener=page.locator('#sheet-play-view [data-act="power-selection-open"][data-power-selection-id="'+id+'"][data-power-stage="learned"]');
 await opener.click();
 let dialog=page.locator('#power-selection-dialog');
 await dialog.waitFor({state:'visible'});
 const races=dialog.locator('[data-power-option="humanoid_races:1"] select');
 assert.equal(await races.count(),2);
 await races.nth(0).selectOption('orc');await races.nth(1).selectOption('goblin');
 await dialog.locator('[data-act="power-selection-toggle"][data-power-option-id="humanoid_races:1"]').click();
 await page.waitForFunction(async()=>{
  const {listCreatures}=await import('/creatures.js');
  return (await listCreatures())[0]?.creature?.power_selections?.ranger_favored_enemy_phb?.learned?.length===1;
 });
 dialog=page.locator('#power-selection-dialog');
 await dialog.locator('[data-power-option="monster_types:2"] select').selectOption('dragons');
 await dialog.locator('[data-act="power-selection-toggle"][data-power-option-id="monster_types:2"]').click();
 await page.waitForFunction(async()=>{
  const {listCreatures}=await import('/creatures.js');
  return (await listCreatures())[0]?.creature?.power_selections?.ranger_favored_enemy_phb?.learned?.length===2;
 });
 assert.deepEqual((await snapshot()).record.power_selections.ranger_favored_enemy_phb.learned,[
  {id:'humanoid_races:1',subchoices:['orc','goblin']},{id:'monster_types:2',subchoices:['dragons']}
 ]);
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('magic');
 assert.match(await page.locator('#sheet-play-view .benefit-option-list[data-selection-id="'+id+'"]').innerText(),/Orc, Goblin/);
 await page.locator('#sheet-play-view [data-act="power-selection-open"][data-power-selection-id="'+id+'"][data-power-stage="learned"]').click();
 assert.equal(await page.locator('#power-selection-dialog [data-power-option="humanoid_races:1"] select').first().inputValue(),'orc');
 await page.locator('#power-selection-dialog [data-act="power-selection-close"]').click();
 await f.shot('ranger-choice-packages-mobile');
 await page.setViewportSize({width:1280,height:900});
 await f.shot('ranger-choice-packages-desktop');

 assert.deepEqual(f.errors,[]);assert.deepEqual(f.missing,[]);
 console.log('PASS: ASI and Ranger alternative option packages persist across reloads in the shared picker');
}finally{await f.close();}
