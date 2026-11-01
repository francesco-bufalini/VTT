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
  await saveCreature({...saved.data,rules_version:'2014',class:'Ranger',class_source:'PHB',level:10,
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
  assert.equal(await learner.getAttribute('data-benefit-type'),'option_grant');
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
  assert.equal(await action.getAttribute('data-benefit-type'),'option_grant');
 };
 await open(styleId);
 assert.equal(await action.locator('[data-benefit-target-search]').count(),0);
 await action.locator('[data-act="benefit-option-close"]').first().click();
 await open('artificer_infusions');
 assert.equal(await action.locator('[data-benefit-target-search]').count(),1);
 assert(await action.locator('[data-act="benefit-option-apply"]').isDisabled());
 assert.equal((await snapshot()).record.power_applications?.artificer_infusions?.length||0,0);
 await action.locator('[data-act="benefit-option-close"]').first().click();
 assert.equal((await snapshot()).record.power_applications?.artificer_infusions?.length||0,0,'Cancel creates no application or trait');
 await open('artificer_infusions');
 await action.locator('[data-act="benefit-target-choose"][data-index="0"]').click();
 await action.locator('[data-act="benefit-option-apply"]').click();await action.waitFor({state:'detached'});
 assert.equal((await snapshot()).record.inventory[0].infusion,undefined);
 assert.equal((await snapshot()).record.inventory[0].option_extensions[0].name,'Enhanced Defense');
 await page.evaluate(async()=>{const {listCreatures,saveCreature}=await import('/creatures.js');const saved=(await listCreatures())[0];
 const record=saved.creature;record.inventory.push({id:'free-target',name:'Oggetto libero',custom_item_type:'other',quantity:1});
 await saveCreature(record,'default',saved.revision);});
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('magic');
 await open('arcane_armor','arcane_armor');
 assert.equal(await action.locator('[data-benefit-target-search]').count(),1);
 await action.locator('[data-act="benefit-target-choose"][data-index="1"]').click();
 await action.locator('[data-act="benefit-option-apply"]').click();await action.waitFor({state:'detached'});
 await open('armor_model','armor_model:guardian');
 assert.equal(await action.locator('[data-benefit-target-search]').count(),0);
 await action.locator('[data-act="benefit-option-apply"]').click();await action.waitFor({state:'detached'});
 let after=await snapshot();assert.equal(after.record.power_applications.armor_model[0].id,'armor_model:guardian');
 assert(after.attacks.some(row=>row.id==='class_feature:thunder_gauntlets'));
 await open('armor_model','armor_model:infiltrator');
 await action.locator('[data-act="benefit-option-apply"]').click();await action.waitFor({state:'detached'});
 after=await snapshot();assert.equal(after.record.power_applications.armor_model[0].id,'armor_model:infiltrator');
 assert(after.attacks.some(row=>row.id==='class_feature:lightning_launcher'));
 assert(!after.attacks.some(row=>row.id==='class_feature:thunder_gauntlets'));
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('magic');
 await sheet('info');
 const objectTrait=page.locator('#sheet-play-view .trait-row').filter({has:page.locator('.trait-title',{hasText:'Oggetto libero - Armatura Arcana'})});
 assert.equal(await objectTrait.locator('[data-act="trait-benefits-open"]').count(),1,
  'The original trait opens its benefits instead of embedding another selection picker');
 await sheet('magic');
 await open('armor_model','armor_model:infiltrator');
 await action.locator('[data-act="benefit-option-apply"]').click();await action.waitFor({state:'detached'});
 assert.equal((await snapshot()).record.power_applications.armor_model.length,0);
 for(const width of [390,1440]){
  await page.setViewportSize({width,height:900});await open('armor_model','armor_model:guardian');
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  await f.shot('benefit-option-armor-'+width);
  await action.locator('[data-act="benefit-option-close"]').first().click();
 }
 await sheet('conditions');
 await page.locator('#sheet-play-view [data-act="item-option-remove"][data-selection-id="arcane_armor"]').click();
 await page.waitForFunction(async()=>{
  const {listCreatures}=await import('/creatures.js');
  return (await listCreatures())[0]?.creature.power_applications?.arcane_armor?.length===0;
 },null,{timeout:5000});
 assert.equal((await snapshot()).record.power_applications.arcane_armor.length,0);
 assert(!(await snapshot()).record.inventory[1].option_extensions.some(effect=>effect.selection_id==='arcane_armor'));
 assert.deepEqual(f.errors,[]);assert.deepEqual(f.missing,[]);
 console.log('PASS: one learner and one application dialog for styles, infusions and Arcane Armor; data-defined targets, exclusive armor effects and reload');
}finally{await f.close();}
