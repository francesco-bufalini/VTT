// Isolated browser smoke test. Never attaches to a user's browser profile or
// desktop game; API responses below deliberately represent an offline host.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';
const root=new URL('../',import.meta.url),native=new URL('../../vtt/data/',import.meta.url);
const artifacts=new URL('../.test-artifacts/',import.meta.url);
await mkdir(artifacts,{recursive:true});
const spells={version:1,spells:[{id:'spell:shield|phb',name:'Shield',source:'PHB',level:1,classes:['Wizard'],entries:['Test reference.']},{id:'spell:light|phb',name:'Light',source:'PHB',level:0,classes:['Bard','Wizard']}]};
const aliases={'/catalog/action_feature_overrides.json':'action_feature_overrides.json','/catalog/combat_action_supplements_5etools.json':'combat_action_supplements_5etools.json','/catalog/player.json':'player_5etools_catalog.json','/catalog/features.json':'compendium_features_5etools.json','/catalog/backgrounds.json':'compendium_backgrounds_5etools.json','/catalog/items.json':'compendium_items_5etools.json'};
const server=createServer(async(req,res)=>{
 try{
  const path=new URL(req.url,'http://localhost').pathname;
  res.setHeader('Cache-Control','no-store');
  if(path.startsWith('/api/')){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({protocol:1,desktop_online:false}));return;}
  if(path==='/catalog/spells.json'){res.setHeader('Content-Type','application/json');res.end(JSON.stringify(spells));return;}
  if(!/^\/(?:[a-z_0-9.-]+|catalog\/[a-z_0-9.-]+)?$/.test(path)){res.writeHead(404);res.end();return;}
  const location=aliases[path]?new URL(aliases[path],native):new URL(path==='/'?'index.html':path.slice(1),root);
  const body=await readFile(location);
  const type=path.endsWith('.js')?'text/javascript':path.endsWith('.css')?'text/css':path.endsWith('.json')?'application/json':path.endsWith('.png')?'image/png':path.endsWith('.svg')?'image/svg+xml':path.endsWith('.webmanifest')?'application/manifest+json':'text/html';
  res.setHeader('Content-Type',type);res.end(body);
 }catch{res.writeHead(404);res.end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const origin=process.env.VTT_PWA_TEST_ORIGIN||'http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({headless:true,...(process.platform==='win32'?{executablePath:process.env.CHROME_PATH||'C:/Program Files/Google/Chrome/Application/chrome.exe'}:{})});
try{
 const context=await browser.newContext({viewport:{width:390,height:844},deviceScaleFactor:1,hasTouch:true,isMobile:true});
 const page=await context.newPage(),errors=[],apiWrites=[];
 page.setDefaultTimeout(10000);
 page.on('pageerror',error=>errors.push(error.message));
 page.on('request',req=>{if(req.url().startsWith(origin+'/api/')&&req.method()!=='GET')apiWrites.push(req.url());});
 await page.goto(origin);
 await page.locator('[data-act="create"]').waitFor();
 await page.evaluate(async()=>{
  const {createCreature,saveCreature}=await import('/creatures.js');
  const saved=await createCreature('character','Scheda di prova');
  await saveCreature({...saved.data,classes:[{name:'Bard',source:'PHB',level:5},{name:'Wizard',source:'PHB',level:5}],class:'Bard',class_source:'PHB',level:10,
   species:'Elf',species_source:'PHB',abilities:{str:12,dex:14,con:14,int:16,wis:12,cha:16},current_hp:40,max_hp_base:40,temporary_hp:3,second_form_hp:4,
   spell_slots_automatic:true,spell_slots_spent:[0,1],attack_ability:'dex',proficiency_choices:[{kind:'weapon',key:'martial'}],
   feats_catalog:[{name:'Fey Touched',source:'TCE'}],
   resource_trackers:[{id:'focus',name:'Concentrazione di prova',max:7,max_formula:'cha_mod + proficiency',recharge:'short_rest'},{id:'turn',name:'Turno',max:3,recharge:'turn'},{id:'manual',name:'Manuale',max:3,recharge:'manual'}],resource_tracker_spent:{focus:2,turn:1,manual:2},
   formula_bonuses:[{id:'focus_bonus',target:'tracker:focus',expression:'2',origin_id:''},{id:'initiative_bonus',target:'initiative',expression:'cha_mod',origin_id:''}],
   dice_bonuses:[{id:'blessing',target:'saving_throw',dice:'1d4',origin_name:'Benedizione',origin_id:''}],
   inventory:[{id:'weapon:shortsword|phb',name:'Shortsword',type:'M',weapon_category:'martial',damage:'1d6',properties:['F','L'],quantity:2,equipped_slots:['main','off']},
    {id:'armor:half_plate|phb',name:'Half Plate',type:'MA',ac:15,quantity:1,equipped_slots:['body']}]},'default',saved.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();
 await page.locator('[data-field="name"]').waitFor();
 const names={info:'Info',stats:'Caratteristiche e abilità',battle:'Battaglia',magic:'Poteri',inventory:'Inventario',traits:'Tratti',conditions:'Condizioni',origins:'Modifica personaggio'};
 const section=async key=>{await page.locator('#section-menu').evaluate(node=>node.open=true);await page.locator('[data-sheet="'+key+'"]').click();await page.waitForFunction(name=>document.querySelector('.current-section')?.textContent===name,names[key]);};
 for(const width of [360,390,768,1440]){
  await page.setViewportSize({width,height:844});
  for(const key of ['info','stats','battle','magic','inventory','traits','conditions','origins']){
   await section(key);
   await page.waitForFunction(()=>document.querySelector('#save-state'));
   const size=await page.evaluate(()=>({width:innerWidth,content:document.documentElement.scrollWidth}));
   assert.ok(size.content<=width,`${key} overflows at ${width}px: ${size.content}`);
   if(width===360&&['info','stats','battle','magic'].includes(key)){
    const touch=await page.evaluate(()=>{
     const control=document.querySelector('input:not([type=checkbox]):not([type=file]), select');
     const summary=document.querySelector('.native-summary > div');
     return {control:control?.getBoundingClientRect().height||0,summary:summary?.getBoundingClientRect().height||0};
    });
    assert.ok(touch.control>=48,`${key} exposes 48px phone controls`);
    if(touch.summary)assert.ok(touch.summary>=48,`${key} keeps summary rows tappable on phone`);
   }
   if(key==='traits'){
     assert.ok(await page.locator('.trait-card > summary').filter({hasText:/^Font of Inspiration(?: ·|$)/}).count(),'level 5 Bard feature must be visible');
     assert.equal(await page.locator('.trait-card > summary').filter({hasText:/^Countercharm(?: ·|$)/}).count(),0,'level 6 Bard feature must not be visible at level 5');
   }
   if(width===390&&['stats','battle','magic','info'].includes(key))await page.screenshot({path:fileURLToPath(new URL(key+'-390.png',artifacts)),fullPage:true});
  }
 }
 await page.setViewportSize({width:390,height:844});
 await section('stats');
 await page.locator('[data-act="sheet-roll"][data-target="save:dex"]').click();
 await page.locator('#sheet-roll-dialog').waitFor();
 assert.match(await page.locator('#sheet-roll-dialog h2').textContent(),/Scheda di prova.*Tiro salvezza/);
 const baseRoll=Number(await page.locator('#sheet-roll-dialog .dice-result').textContent());
 await page.locator('[data-roll-bonus="0"]').check();await page.getByRole('button',{name:'Applica bonus',exact:true}).click();
 const bonusRoll=Number(await page.locator('#sheet-roll-dialog .dice-result').textContent());assert.ok(bonusRoll>baseRoll&&bonusRoll<=baseRoll+4);
 await page.locator('[data-act="close-sheet-roll"]').click();
 assert.equal(await page.locator('.current-section').textContent(),names.stats);
 await section('battle');
 assert.equal(await page.locator('[data-calculated="ac"]').textContent(),'17');
 await page.locator('#hp-amount').fill('10');await page.locator('[data-act="hp-damage"]').click();
 await page.waitForFunction(()=>document.querySelector('[data-field="current_hp"]')?.value==='37');
 assert.equal(await page.locator('[data-calculated="tracker:focus"]').textContent(),'9');
 await page.locator('[data-act="tracker-more"][data-tracker-id="focus"]').click();
 await page.locator('[data-act="tracker-turn"]').click();
 const counts=()=>page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.resource_tracker_spent;});
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.resource_tracker_spent.focus===3;});
 assert.deepEqual(await counts(),{focus:3,manual:2});
 await page.locator('[data-act="tracker-short"]').click();await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return !(await listCreatures())[0].creature.resource_tracker_spent.focus;});
 assert.deepEqual(await counts(),{manual:2});
 await section('origins');await page.locator('#native-details').selectOption('resources');
 await page.locator('[data-tracker-field="max_formula"][data-tracker-id="focus"]').fill('1 + cha_mod');
 await page.locator('[data-tracker-field="max_formula"][data-tracker-id="focus"]').press('Tab');
 await page.waitForFunction(()=>document.querySelector('[data-calculated="tracker:focus"]')?.textContent==='6');
 const gate=page.locator('[data-benefit-tracker="focus"][data-requirement="min_level"]');
 await gate.locator('xpath=ancestor::details').evaluate(node=>node.open=true);await gate.fill('11');await gate.press('Tab');
 await page.getByText('Non attivo: origine disattivata o requisito non soddisfatto.',{exact:false}).waitFor();
 await page.locator('[data-benefit-tracker="focus"][data-requirement="min_level"]').locator('xpath=ancestor::details').evaluate(node=>node.open=true);
 await page.locator('[data-benefit-tracker="focus"][data-requirement="min_level"]').fill('0');await page.locator('[data-benefit-tracker="focus"][data-requirement="min_level"]').press('Tab');
 await page.waitForFunction(()=>document.querySelector('[data-calculated="tracker:focus"]')?.textContent==='6');
 await section('magic');
 assert.ok(await page.locator('[data-act="origin-choice-pick"]').count(),'Fey Touched must offer an explicit choice');
 const originPicker=page.locator('[data-origin-choice]').first();
 const choiceOptions=await originPicker.locator('option').evaluateAll(rows=>rows.map(row=>row.value).filter(Boolean));
 assert.ok(choiceOptions.length);await originPicker.selectOption(choiceOptions[0]);
 const ability=page.locator('[data-choice-ability]').first();if(await ability.count())await ability.selectOption('int');
 await page.locator('[data-act="origin-choice-pick"]').first().click();
 await page.locator('[data-act="origin-choice-remove"]').waitFor();
 const innate=page.locator('[data-act="origin-spend"]').first();assert.ok(await innate.count());await innate.click();
 await page.waitForFunction(async()=>{const {listCreatures}=await import('/creatures.js');return Object.keys((await listCreatures())[0].creature.resource_tracker_spent).some(id=>id.startsWith('5espell:'));});
 await page.locator('#spell-class').selectOption('class|phb|wizard');
 await page.locator('#spell-target').selectOption('spellbook_spells');
 await page.locator('#spell-search').fill('Shield');await page.locator('[data-act="spell-pick"]').filter({has:page.getByText('Shield',{exact:true})}).click();
 await page.waitForFunction(()=>document.querySelector('[data-act="remove-spell"][data-key="spellbook_spells"]'));
 await page.locator('#spell-target').selectOption('prepared_spells');
 await page.locator('[data-act="spell-pick"]').filter({has:page.getByText('Shield',{exact:true})}).click();
 await page.waitForFunction(()=>document.querySelector('[data-act="remove-spell"][data-key="prepared_spells"]'));
 await page.locator('[data-act="slot-use"][data-level="1"]').click();
 await page.waitForFunction(()=>document.querySelector('[data-slot="1"]')?.value==='2');
 await page.waitForFunction(async()=> (await navigator.serviceWorker.getRegistration())?.active?.state==='activated');
 await context.setOffline(true);await page.reload();
 await page.locator('[data-act="open"]').click();await page.locator('[data-field="name"]').waitFor();
 await section('magic');assert.equal(await page.locator('[data-slot="1"]').inputValue(),'2');
 assert.match(await page.locator('#app').textContent(),/Shield/);
 assert.deepEqual(errors,[]);
 assert.deepEqual(apiWrites,[],'sheet edits and tests must not execute desktop game commands');
 assert.equal((await counts()).manual,2,'rests and reopening must preserve manual counters');
 console.log('PASS: 8 sections at 360/390/768/1440px; optional dice, formula trackers, level gates, recovery, origin choices/charges, spellbook/slots and offline persistence.');
 console.log('Screenshots: '+fileURLToPath(artifacts));
}finally{await browser.close();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
