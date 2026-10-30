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
 const ranger=page.locator('.trait-subtrait[data-choice-id="power:ranger_favored_enemy_phb:prepared"]').first();
 await ranger.click();
 await page.locator('#pending-choice-dialog input[value="humanoids"]').check();
 const details=page.locator('#pending-choice-dialog [data-pending-option="humanoids"]');
 assert.equal(await details.count(),2);
 await details.nth(0).fill('Orc');await details.nth(1).fill('Goblin');
 await page.locator('#pending-choice-dialog input[value="dragons"]').check();
 await page.locator('#pending-choice-dialog [data-act="pending-choice-save"]').click();
 await page.locator('#pending-choice-dialog').waitFor({state:'detached'});
 assert.deepEqual((await snapshot()).record.power_selections.ranger_favored_enemy_phb.prepared,
  ['dragons',{id:'humanoids',subchoices:['Orc','Goblin']}]);
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('info');
 assert.match(await ranger.innerText(),/Orc, Goblin/);
 assert.equal(await ranger.getAttribute('data-act'),'pending-choice-open');
 const geometry=await ranger.evaluate(node=>({height:node.getBoundingClientRect().height,
  background:getComputedStyle(node).backgroundImage}));
 assert(geometry.height<65,JSON.stringify(geometry));
 assert.equal(geometry.background,'none');
 await ranger.click();assert.equal(await details.nth(0).inputValue(),'Orc');
 await page.locator('[data-act="pending-choice-close"]').first().click();
 await f.shot('permanent-subtraits-mobile');
 await page.setViewportSize({width:1280,height:900});
 await f.shot('permanent-subtraits-desktop');
 assert.deepEqual(f.errors,[]);assert.deepEqual(f.missing,[]);
 console.log('PASS: ASI generic bonuses, Ranger shared picker, persisted humanoid details, compact mobile and desktop Info');
}finally{await f.close();}
