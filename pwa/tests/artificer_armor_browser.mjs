import assert from 'node:assert/strict';
import {browserFixture} from './browser_fixture.mjs';
const f=await browserFixture();const {page,origin,sheet,shot}=f;
const record=()=>page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature;});
try{
 await page.goto(origin);await page.locator('[data-act="library-add"]').waitFor();
 await page.evaluate(async()=>{
  const {createCreature,saveCreature}=await import('/creatures.js');const saved=await createCreature('character','Ore - verifica Armorer');
  await saveCreature({...saved.data,class:'Artificer',class_source:'TCE',level:8,
   classes:[{name:'Artificer',source:'TCE',level:8,subclass:'Armorer',subclass_source:'TCE'}],
   abilities:{str:18,dex:14,con:14,int:19,wis:12,cha:10},trait_state_selection:{armor_model:'armor_model:infiltrator'},attack_ability:'int',
   current_hp:62,max_hp_base:62,inventory:[{id:'test:armor',name:'Celebrum Armor',type:'MA',ac:14,quantity:1,equipped_slots:['body']}]
  },'default',saved.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('info');
 // The Armor Model trait must list both activatable modes, including the inactive one.
 const armorTrait=page.locator('.trait-row').filter({has:page.locator('.trait-title', {hasText:'Armor Model'})});
 await armorTrait.locator('[data-act="trait-benefits-open"]').first().click();
 const capabilities=page.locator('#trait-benefits-dialog .trait-capability');
 await capabilities.first().waitFor();
 assert.equal(await capabilities.count(),2,'both armor models remain inspectable in the granting trait');
 assert.equal(await capabilities.filter({hasText:'Modello armatura · Guardiano'}).count(),1);
 assert.match(await capabilities.filter({hasText:'Modello armatura · Infiltratore'}).innerText(),/Lightning Launcher/);
 assert.match(await capabilities.filter({hasText:'Modello armatura · Infiltratore'}).innerText(),/Azione gratuita|Nessun costo/);
 await page.locator('#trait-benefits-dialog [data-act="trait-benefits-close"]').click();
 await sheet('battle');
 // A selected model must expose its actual attack in the Actions list.
 await page.locator('#sheet-play-view [data-attack-id="class_feature:lightning_launcher"]').waitFor({state:"attached"});
 assert.equal(await page.locator('#sheet-play-view [data-attack-id="class_feature:thunder_gauntlets"]').count(),0);

 const resources=page.locator('[data-battle-action="resources"]');
 if(!await resources.evaluate(n=>n.open))await resources.locator('summary.play-battle-summary').click();
 const flashResource=page.locator('#sheet-play-view [data-resource-tracker="class:artificer:tce:flash_of_genius"]');
 assert.match(await flashResource.locator('.play-resource-bonus-row').innerText(),/\+4.*Lampo di genio[\s\S]*Prove di caratteristica.*Tiri salvezza/);
 assert.equal(await flashResource.locator('[data-act="battle-use-ability"]').count(),0,
  'roll bonuses are listed under trackers instead of duplicated as ability buttons');
 const lightningResource=page.locator('#sheet-play-view [data-resource-tracker="feature:lightning_launcher:extra_damage"]');
 assert.match(await lightningResource.locator('.play-resource-bonus-row').innerText(),/\+1d6[\s\S]*Danni/);
 // The rest label does not block an immediate model switch.
  assert.equal(await page.locator('#sheet-play-view [data-resource-tracker="feature:armor_model:activation"]').count(),0);
 // Armor Models use the same option-benefit card and application dialog.
 await sheet('magic');
 const modelCard=page.locator('#sheet-play-view .play-infusion-card').filter({has:page.getByRole('heading',{name:'Modelli di armatura',exact:true})});
 assert.equal(await modelCard.locator('[data-act="benefit-option-open"]').count(),2);
 const guardian=modelCard.locator('[data-power-option-id="armor_model:guardian"]');
 const infiltrator=modelCard.locator('[data-power-option-id="armor_model:infiltrator"]');
 assert.equal(await infiltrator.locator('.play-infusion-state').evaluate(node=>String(node.classList.contains('is-active'))),'true');
 assert.equal(await guardian.locator('.play-infusion-state').evaluate(node=>String(node.classList.contains('is-active'))),'false');
 await guardian.click();
 const modelDialog=page.locator('#benefit-option-dialog');
 await modelDialog.locator('[data-act="benefit-option-apply"]').waitFor();
 assert.equal((await record()).trait_state_selection?.armor_model,'armor_model:infiltrator','No switch before confirmation');
 assert.match(await modelDialog.locator('.magic-spell-description').innerText(),/Guardiano|guanti|Campo difensivo/i);
 assert.equal(await modelDialog.locator('.infusion-dialog-active p').count(),2);
 assert.equal(await modelDialog.locator('[data-ability-payment]').count(),0,'No activation tracker is offered');
 assert.match(await modelCard.innerText(),/Riposo breve/i);
  assert.doesNotMatch(await modelCard.innerText(),/Modello applicato/i);
  assert.equal(await modelDialog.locator('[data-benefit-target-search]').count(),0);
 assert.equal(await modelDialog.locator('[data-act="benefit-option-apply"]').isEnabled(),true);
 await modelDialog.locator('[data-act="benefit-option-apply"]').click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');
   return (await listCreatures())[0].creature.trait_state_selection?.armor_model==='armor_model:guardian';});
 assert.equal((await record()).resource_tracker_spent?.['feature:armor_model:activation'],undefined);
 assert.equal((await record()).rest_selection_available?.armor_model,undefined);
 assert.equal(await guardian.locator('.play-infusion-state').evaluate(node=>String(node.classList.contains('is-active'))),'true');
 assert.equal(await infiltrator.locator('.play-infusion-state').evaluate(node=>String(node.classList.contains('is-active'))),'false');
 await sheet('battle');
 await page.locator('#sheet-play-view [data-attack-id="class_feature:thunder_gauntlets"]').waitFor({state:"attached"});
 assert.equal(await page.locator('#sheet-play-view [data-attack-id="class_feature:lightning_launcher"]').count(),0);

 if(!await resources.evaluate(n=>n.open))await resources.locator('summary.play-battle-summary').click();
 await page.getByRole('button',{name:'Usa Campo difensivo',exact:true}).click();
 await page.locator('[data-feature-confirm]').click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.temporary_hp===8;});
 assert.equal((await record()).resource_tracker_spent['class:artificer:tce:defensive_field'],1);
 // Flash of Genius appears only as an optional bonus on the eligible roll.
 await sheet('info');
 const saveButton=page.locator('#sheet-play-view [data-act="sheet-roll"][data-target="save:dex"]').first();
 await saveButton.click();
 const rollDialog=page.locator('#sheet-roll-dialog');
 const flashRow=rollDialog.locator('.sheet-roll-bonus-item').filter({hasText:'Flash of Genius'});
 await flashRow.locator('[data-act="sheet-roll-use-bonus"]').waitFor();
 assert.match(await flashRow.innerText(),/\+4/);
 const flashTracker='class:artificer:tce:flash_of_genius',beforeFlash=(await record()).resource_tracker_spent?.[flashTracker]||0;
 await flashRow.locator('[data-act="sheet-roll-use-bonus"]').click();
 const flashDialog=page.locator('#class-feature-dialog');
 await flashDialog.locator('[data-feature-confirm]').waitFor();
 assert.equal((await record()).resource_tracker_spent?.[flashTracker]||0,beforeFlash);
 assert.equal(await flashDialog.locator('[data-ability-payment] option').count(),2);
 await flashDialog.locator('[data-feature-confirm]').click();
 await page.waitForFunction(async id=>{
  const {listCreatures}=await import('/creatures.js');
  return ((await listCreatures())[0].creature.resource_tracker_spent?.[id]||0)===1;
 },flashTracker);
 assert.match(await rollDialog.locator('[data-roll-formula]').textContent(),/\+4/);
 const modifier=Number((await rollDialog.locator('.sheet-roll-math strong').first().textContent()).trim());
 await rollDialog.locator('[data-act="roll-sheet-confirm"]').click();
 const total=Number(await rollDialog.locator('.dice-result').textContent());
 const firstD20=Number(await rollDialog.locator('.sheet-roll-dice-group').first().locator('.sheet-roll-die-value').first().textContent());
 assert.equal(total,firstD20+modifier+4,'Flash of Genius applies its flat Intelligence modifier');
 assert.equal(await flashRow.locator('[data-act="sheet-roll-use-bonus"]').textContent(),'Usato',
  'each reaction applies to one roll only');
 // A fresh roll may choose the no-tracker payment without spending another use.
 await page.locator('[data-act="close-sheet-roll"]').click();
 await saveButton.click();
 await flashRow.locator('[data-act="sheet-roll-use-bonus"]').click();
 await flashDialog.locator('[data-ability-payment]').selectOption('');
 await flashDialog.locator('[data-feature-confirm]').click();
 assert.equal((await record()).resource_tracker_spent?.[flashTracker]||0,1);
 assert.match(await rollDialog.locator('[data-roll-formula]').textContent(),/\+4/);
 await rollDialog.locator('[data-act="close-sheet-roll"]').click();
 await sheet('battle');
 await shot('ore-armorer-390');
 await page.setViewportSize({width:1440,height:1000});await shot('ore-armorer-1440');
 assert.deepEqual(f.errors,[]);console.log('PASS: Armor Models in Powers; exclusive selection, tracker payment, Defensive Field and HP at 390/1440px');
}finally{await f.close();}
