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
   abilities:{str:18,dex:14,con:14,int:19,wis:12,cha:10},artificer_armor_model:'infiltrator',attack_ability:'int',
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
 await page.getByRole('button',{name:'Attiva Modello armatura · Guardiano',exact:true}).click();
 const modelDialog=page.locator('#class-feature-dialog');
 await modelDialog.locator('[data-feature-confirm]').waitFor();
 assert.equal((await record()).artificer_armor_model,'infiltrator','no switch before confirmation');
 assert.equal(await modelDialog.locator('[data-ability-payment] option').count(),2);
 assert.equal(await modelDialog.locator('[data-ability-payment] option').last().innerText(),'Nessun tracker');
 await modelDialog.locator('[data-feature-confirm]').click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.artificer_armor_model==='guardian';});
 assert.equal((await record()).resource_tracker_spent['feature:armor_model:activation'],1);
 await page.locator('#sheet-play-view [data-attack-id="class_feature:thunder_gauntlets"]').waitFor({state:"attached"});
 assert.equal(await page.locator('#sheet-play-view [data-attack-id="class_feature:lightning_launcher"]').count(),0);

 if(!await resources.evaluate(n=>n.open))await resources.locator('summary.play-battle-summary').click();
 await page.getByRole('button',{name:'Usa Campo difensivo',exact:true}).click();
 await page.locator('[data-feature-confirm]').click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.temporary_hp===8;});
 assert.equal((await record()).resource_tracker_spent['class:artificer:tce:defensive_field'],1);
 await shot('ore-armorer-390');
 await page.setViewportSize({width:1440,height:1000});await shot('ore-armorer-1440');
 assert.deepEqual(f.errors,[]);console.log('PASS: real Chrome model switch, Defensive Field payment and temporary HP at 390/1440px');
}finally{await f.close();}
