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
const aliases={'/catalog/player.json':'player_5etools_catalog.json','/catalog/features.json':'compendium_features_5etools.json','/catalog/backgrounds.json':'compendium_backgrounds_5etools.json','/catalog/items.json':'compendium_items_5etools.json'};
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
   if(key==='traits'){
     assert.ok(await page.getByText('Font of Inspiration',{exact:true}).count(),'level 5 Bard feature must be visible');
     assert.equal(await page.getByText('Countercharm',{exact:true}).count(),0,'level 6 Bard feature must not be visible at level 5');
   }
   if(width===390&&['stats','battle','magic','info'].includes(key))await page.screenshot({path:fileURLToPath(new URL(key+'-390.png',artifacts)),fullPage:true});
  }
 }
 await page.setViewportSize({width:390,height:844});
 await section('stats');
 await page.locator('[data-act="sheet-roll"][data-target="save:dex"]').click();
 await page.locator('#sheet-roll-dialog').waitFor();
 assert.match(await page.locator('#sheet-roll-dialog h2').textContent(),/Scheda di prova.*Tiro salvezza/);
 await page.locator('[data-act="close-sheet-roll"]').click();
 assert.equal(await page.locator('.current-section').textContent(),names.stats);
 await section('battle');
 assert.equal(await page.locator('[data-calculated="ac"]').textContent(),'17');
 await page.locator('#hp-amount').fill('10');await page.locator('[data-act="hp-damage"]').click();
 await page.waitForFunction(()=>document.querySelector('[data-field="current_hp"]')?.value==='37');
 await section('magic');
 await page.locator('#spell-class').selectOption('class|phb|wizard');
 await page.locator('#spell-target').selectOption('spellbook_spells');
 await page.locator('#spell-search').fill('Shield');await page.locator('[data-act="spell-pick"]').filter({has:page.getByText('Shield',{exact:true})}).click();
 await page.waitForFunction(()=>document.querySelector('[data-act="remove-spell"][data-key="spellbook_spells"]'));
 await page.locator('#spell-target').selectOption('prepared_spells');
 await page.locator('[data-act="spell-pick"]').filter({has:page.getByText('Shield',{exact:true})}).click();
 await page.waitForFunction(()=>document.querySelector('[data-act="remove-spell"][data-key="prepared_spells"]'));
 await page.locator('[data-act="slot-use"][data-level="1"]').click();
 await page.waitForFunction(()=>document.querySelector('[data-slot="1"]')?.value==='2');
 await page.evaluate(()=>navigator.serviceWorker.ready);
 await context.setOffline(true);await page.reload();
 await page.locator('[data-act="open"]').click();await page.locator('[data-field="name"]').waitFor();
 await section('magic');assert.equal(await page.locator('[data-slot="1"]').inputValue(),'2');
 assert.match(await page.locator('#app').textContent(),/Shield/);
 assert.deepEqual(errors,[]);
 assert.deepEqual(apiWrites,[],'sheet edits and tests must not execute desktop game commands');
 console.log('PASS: 8 sheet sections at 360/390/768/1440px; HP layers, class spellbook/preparation, slot consumption and offline reload preserve data.');
 console.log('Screenshots: '+fileURLToPath(artifacts));
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
