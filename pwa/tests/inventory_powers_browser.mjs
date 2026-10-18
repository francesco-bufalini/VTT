import assert from 'node:assert/strict';
import {browserFixture,seedPlayCreature} from './browser_fixture.mjs';
const f=await browserFixture();const {page,origin,sheet,popup,dismiss,shot}=f;
const record=()=>page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature;});
try{
 await seedPlayCreature(page,origin);
 await page.evaluate(async()=>{
  const {listCreatures,saveCreature}=await import('/creatures.js');const saved=(await listCreatures())[0];
  const inventory=structuredClone(saved.creature.inventory);
  Object.assign(inventory[0],{weight:3,value:1500,source:'PHB',instance_overrides:{damage:'1d8'}});
  Object.assign(inventory[1],{weight:0.5,value_gp:50,source:'HB'});
  Object.assign(inventory[2],{weight:null,req_attune:true,rarity:'rare',source:'HB'});
  inventory.push({id:'local_armor',name:'Corazza del viaggio',custom_item_type:'armor',ac:15,weight:45,value:75000,quantity:1,equipped_slots:['body']});
  await saveCreature({...saved.creature,inventory,origin_spell_grants:[{id:'astral',ability_id:'custom:astral',action_kind:'ability',origin_id:'custom:patto',origin_name:'Patto astrale',name:'Passo fra le stelle',description:'Attraversi un varco di luce.\n\nScegli una destinazione visibile prima di spostarti.',activation_mode:'bonus',tracker_id:'focus',tracker_cost:2},{id:'lunar',ability_id:'custom:lunar',action_kind:'ability',origin_id:'custom:moon',origin_name:'Benedizione lunare',name:'Sguardo lunare',description:'La luna guida la tua attenzione.',activation_mode:'contextual',tracker_cost:0}]},'default',saved.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('inventory');
 const before=JSON.stringify(await record());
 for(const viewport of [{width:320,height:740},{width:360,height:800},{width:390,height:844},{width:430,height:932}]){
  await page.setViewportSize(viewport);
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  const sword=page.locator('#sheet-play-view [data-sheet-context="item:0"]');
  assert.match(await sword.textContent(),/Arma.*PHB/);assert.match(await sword.textContent(),/1d8/);assert.match(await sword.textContent(),/3 lb/);assert.match(await sword.textContent(),/15 mo/);assert.match(await sword.textContent(),/Mano principale/);
  assert.match(await page.locator('.inventory-overview').textContent(),/49 lb/);assert.match(await page.locator('.inventory-overview').textContent(),/865 mo/);assert.match(await page.locator('.inventory-overview').textContent(),/Dati parziali/);
 }
 await page.setViewportSize({width:390,height:844});await shot('inventory-rich');
 await page.locator('[data-play-search]').fill('raro');assert.equal(await page.locator('#sheet-play-view [data-play-filter]:visible').count(),1);await page.locator('[data-play-search]').fill('');
 await popup('item:0');assert.equal(await page.locator('#sheet-context-title').textContent(),'Lama lunare');assert.match(await page.locator('.inventory-detail-facts').textContent(),/1d8/);await shot('inventory-detail-rich');await dismiss();
 assert.equal(JSON.stringify(await record()),before,'Reading and searching inventory cannot mutate the archive');
 await sheet('magic');
 const powers=page.locator('#sheet-play-view [data-sheet-context^="power:"]');
 assert(await powers.filter({hasText:'Focus arcano'}).textContent().then(t=>t.includes('1 potere')));
 await powers.filter({hasText:'Focus arcano'}).click();
 for(const width of [320,360,390,430]){
  await page.setViewportSize({width,height:844});
  assert(await page.locator('#sheet-context-dialog').evaluate(n=>n.scrollWidth<=n.clientWidth),'Privilege popup must fit '+width);
  assert(await page.locator('#sheet-context-dialog .power-privilege-description').isVisible());
  assert.match(await page.locator('#sheet-context-dialog .power-privilege').textContent(),/Patto astrale/);assert.match(await page.locator('#sheet-context-dialog .power-privilege-meta').textContent(),/Azione bonus · 2 per uso/);
  assert.match(await page.locator('#sheet-context-dialog .power-recovery').textContent(),/Riposo breve/);
 }
 await page.setViewportSize({width:390,height:844});await shot('privilege-popup');
 assert.equal(JSON.stringify(await record()),before,'Opening a privilege cannot consume its resource');
 await page.locator('#sheet-context-dialog [data-act="tracker-more"]').click();
 await page.waitForFunction(()=>document.querySelector('.power-resource-summary [data-tracker-remaining]')?.textContent==='4');assert.equal((await record()).resource_tracker_spent.focus,3);
 await page.locator('#sheet-context-dialog [data-act="tracker-less"]').click();await page.waitForFunction(()=>document.querySelector('.power-resource-summary [data-tracker-remaining]')?.textContent==='5');assert.equal((await record()).resource_tracker_spent.focus,2);
 await dismiss();
 // The origin link resolves the exact feature ID and never matches display names.
 await page.evaluate(async()=>{
  const {listCreatures,saveCreature}=await import('/creatures.js');const {calculateSheet,loadRuleCatalogs}=await import('/sheet_rules.js');const saved=(await listCreatures())[0],data=calculateSheet(saved.creature,await loadRuleCatalogs());
  const feature=data.features.find(row=>row.origin_id);if(!feature)throw Error('Fixture needs a real class feature');
  const grants=structuredClone(saved.creature.origin_spell_grants);grants[1].origin_id=feature.origin_id;
  await saveCreature({...saved.creature,origin_spell_grants:grants},'default',saved.revision);
 });await page.reload();await page.locator('[data-act="open"]').click();await sheet('magic');
 await page.locator('#sheet-play-view [data-sheet-context^="power:"]').filter({hasText:'Senza consumo'}).click();
 await page.locator('#sheet-context-dialog .power-origin-link').click();await page.waitForFunction(()=>document.querySelector('#app').dataset.renderedSheet==='traits');
 assert(await page.locator('#sheet-context-dialog .trait-card').isVisible(),'Open the precise origin trait in its detail popup');
 assert.deepEqual(f.errors,[]);assert.deepEqual(f.missing,[]);assert.deepEqual(f.writes,[]);
 console.log('PASS: structured inventory facts/totals/search at 320–430px; no writes on read; privilege origin, activation, cost, description, recovery, exact consumption and stable-ID origin detail.');
}finally{await f.close();}
