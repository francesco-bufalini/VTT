import assert from 'node:assert/strict';
import {browserFixture} from './browser_fixture.mjs';
const f=await browserFixture(),{page,origin,sheet}=f;
const styleId='optional:class:phb:ranger:fs-r';
const snapshot=()=>page.evaluate(async()=>{
 const {listCreatures}=await import('/creatures.js');
 const {calculateSheet,loadRuleCatalogs}=await import('/sheet_rules.js');
 const record=(await listCreatures())[0].creature;
 return {record,attacks:calculateSheet(record,await loadRuleCatalogs()).attacks};
});
try{
 await page.goto(origin);await page.locator('[data-act="library-add"]').waitFor();
 await page.evaluate(async()=>{
  const {createCreature,saveCreature}=await import('/creatures.js');
  const saved=await createCreature('character','Benefici comuni');
  await saveCreature({...saved.data,rules_version:'2014',level:10,
   classes:[{name:'Ranger',source:'PHB',level:2},{name:'Artificer',source:'TCE',level:8,subclass:'Armorer',subclass_source:'TCE'}],
   abilities:{str:12,dex:14,con:14,int:18,wis:12,cha:10},attack_ability:'int',
   inventory:[{id:'test:armor',name:'Armatura bersaglio',type:'MA',ac:14,quantity:1,equipped_slots:['body']}]
  },'default',saved.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('magic');
 const learner=page.locator('#power-selection-dialog');
 let dialogClass='';
 for(const [id,search,name] of [[styleId,'Two-Weapon','Two-Weapon Fighting'],['artificer_infusions','Enhanced Defense','Enhanced Defense']]){
  await page.locator('#sheet-play-view [data-act="power-selection-open"][data-power-selection-id="'+id+'"]').click();
  await learner.waitFor({state:'visible'});
  assert.equal(await learner.getAttribute('data-benefit-type'),'option_selection');
  if(dialogClass)assert.equal(await learner.getAttribute('class'),dialogClass);
  dialogClass=await learner.getAttribute('class');
  await learner.locator('[data-power-search]').fill(search);
  assert.equal(await learner.locator('.magic-catalog-name').innerText(),name);
  await learner.locator('[data-act="power-selection-toggle"]').click();
  await page.waitForFunction(id=>document.querySelector('#power-selection-dialog [aria-pressed="true"]')!==null,id);
  await learner.locator('[data-act="power-selection-close"]').last().click();
 }
 const action=page.locator('#benefit-option-dialog');
 const open=async(id,option)=>{
  await page.locator('#sheet-play-view [data-act="benefit-option-open"][data-power-selection-id="'+id+'"]'+
   (option?'[data-power-option-id="'+option+'"]':'')).click();
  await action.waitFor({state:'visible'});
  assert.equal(await action.getAttribute('data-benefit-type'),'option_selection');
 };
 await open(styleId);
 assert.equal(await action.locator('[data-benefit-target-search]').count(),0);
 await action.locator('[data-act="benefit-option-close"]').first().click();
 await open('artificer_infusions');
 assert.equal(await action.locator('[data-benefit-target-search]').count(),1);
 assert(await action.locator('[data-act="benefit-option-apply"]').isDisabled());
 await action.locator('[data-act="benefit-target-choose"][data-index="0"]').click();
 await action.locator('[data-act="benefit-option-apply"]').click();await action.waitFor({state:'detached'});
 assert.equal((await snapshot()).record.inventory[0].infusion.name,'Enhanced Defense');
 await open('armor_model','armor_model:guardian');
 assert.equal(await action.locator('[data-benefit-target-search]').count(),1);
 assert(await action.locator('[data-act="benefit-option-apply"]').isDisabled());
 await action.locator('[data-act="benefit-target-choose"][data-index="0"]').click();
 await action.locator('[data-act="benefit-option-apply"]').click();await action.waitFor({state:'detached'});
 let after=await snapshot();assert.equal(after.record.trait_state_selection.armor_model,'armor_model:guardian');
 assert(after.attacks.some(row=>row.id==='class_feature:thunder_gauntlets'));
 await open('armor_model','armor_model:infiltrator');
 await action.locator('[data-act="benefit-target-choose"][data-index="0"]').click();
 await action.locator('[data-act="benefit-option-apply"]').click();await action.waitFor({state:'detached'});
 after=await snapshot();assert.equal(after.record.trait_state_selection.armor_model,'armor_model:infiltrator');
 assert(after.attacks.some(row=>row.id==='class_feature:lightning_launcher'));
 assert(!after.attacks.some(row=>row.id==='class_feature:thunder_gauntlets'));
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('magic');
 await open('armor_model','armor_model:infiltrator');
 await action.locator('[data-act="benefit-option-remove"]').click();await action.waitFor({state:'detached'});
 assert.equal((await snapshot()).record.trait_state_selection.armor_model,'');
 for(const width of [390,1440]){
  await page.setViewportSize({width,height:900});await open('armor_model','armor_model:guardian');
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  await f.shot('benefit-option-armor-'+width);
  await action.locator('[data-act="benefit-option-close"]').first().click();
 }
 assert.deepEqual(f.errors,[]);assert.deepEqual(f.missing,[]);
 console.log('PASS: one learner and one application dialog for styles, infusions and Arcane Armor; data-defined targets, exclusive armor effects and reload');
}finally{await f.close();}
