// Isolated native-route browser verification; never opens a user profile/archive.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';
const root=new URL('../../',import.meta.url),artifacts=new URL('../.test-artifacts/',import.meta.url);
await mkdir(artifacts,{recursive:true});
const routes=new Map([...String(await readFile(new URL('network/pwa_host.gd',root))).matchAll(/"([^"\n]+)":\s*\["res:\/\/([^"\n]+)",\s*"([^"\n]+)"\]/g)].map(m=>[m[1],[m[2],m[3]]]));
const server=createServer(async(req,res)=>{
 try{
  const path=new URL(req.url,'http://localhost').pathname;
  if(path.startsWith('/api/')){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({protocol:1,desktop_online:false}));return;}
  if(path==='/catalog/spells.json'){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({version:1,spells:[]}));return;}
  const route=routes.get(path);if(!route){res.writeHead(404);res.end();return;}
  res.setHeader('Content-Type',route[1]);res.end(await readFile(new URL(route[0],root)));
 }catch{res.writeHead(404);res.end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const origin='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({headless:true,...(process.platform==='win32'?{executablePath:process.env.CHROME_PATH||'C:/Program Files/Google/Chrome/Application/chrome.exe'}:{})});
try{
 const context=await browser.newContext({viewport:{width:390,height:900}}),page=await context.newPage();
 const errors=[],missing=[],writes=[];
 page.on('pageerror',error=>errors.push(error.message));
 page.on('response',res=>{if(res.status()===404)missing.push(res.url());});
 page.on('request',req=>{if(req.method()!=='GET'&&req.url().includes('/api/'))writes.push(req.url());});
 await page.goto(origin);await page.locator('[data-act="create"]').waitFor();
 await page.evaluate(async()=>{
  const {createCreature,saveCreature}=await import('/creatures.js');
  const saved=await createCreature('character','Esploratrice di prova');
  await saveCreature({...saved.data,class:'Rogue',class_source:'PHB',level:2,rules_version:'2014',abilities:{str:12,dex:16,con:14,int:12,wis:14,cha:10},
   inventory:[{id:'shortsword',name:'Shortsword',source:'PHB',type:'M',damage:'1d6',weapon_category:'martial',properties:['L','F'],equipped_slots:['main','off'],quantity:2}],
   prepared_spells:['action','bonus','reaction'].map(unit=>({id:'test_spell_'+unit,name:'Incantesimo '+unit,level:1,time:[{unit,number:1}],entries:['Testo della selezione di prova']})),
   action_grants:[{id:'resource_demo',name:'Capacità di prova',action_type:'bonus',tracker_id:'charge'}],
   resource_trackers:[{id:'charge',name:'Cariche',max:3,recharge:'long_rest'}],resource_tracker_spent:{charge:1}},'default',saved.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();
 const names={info:'Info',stats:'Caratteristiche e abilità',battle:'Battaglia',actions:'Cosa posso fare?',magic:'Poteri',inventory:'Inventario',traits:'Tratti',conditions:'Condizioni',origins:'Modifica personaggio'};
 const section=async key=>{const target=page.locator('[data-sheet="'+key+'"]');if(!await target.isVisible())await page.locator('[data-act="navigation-open"]').click();await target.click();await page.waitForFunction(tab=>document.querySelector('[data-sheet="'+tab+'"]')?.getAttribute('aria-pressed')==='true'&&document.querySelector('#app').dataset.renderedSheet===tab,key);};
 for(const width of [360,390,768,1440]){
  await page.setViewportSize({width,height:900});
  for(const key of ['info','stats','battle','actions','magic','inventory','traits','conditions','origins']){
   await section(key);
   assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),key+' overflow at '+width);
   if(key==='actions'){
    assert.equal(await page.locator('.action-economy-section').count(),5);
    assert(await page.locator('[data-act="action-expand-all"]').isVisible());
    assert(await page.locator('[data-act="action-variants"]').textContent().then(t=>t.includes('Regole varianti')));
    if(width===390){
     await page.locator('[data-act="action-expand-all"]').click();
     assert.equal(await page.locator('.action-tree:not([open])').count(),0);
     await page.locator('[data-act="action-expand-all"]').click();
     assert(await page.locator('.action-tree:not([open])').count()>0);
    }
    assert.equal(await page.locator('.action-group-label').filter({hasText:'Incantesimi'}).count(),3);
    for(const time of ['action','bonus','reaction'])assert(await page.locator('[data-timing="'+time+'"] [data-spell-id="test_spell_'+time+'"]').count());
    const bonus=page.locator('[data-timing="bonus"]');
    assert((await bonus.textContent()).includes('Spostamento'));
    assert.equal(await page.locator('[data-act="action-open-spells"]').count(),0);
    const heights=await page.locator('.action-group-label').evaluateAll(nodes=>nodes.map(node=>node.getBoundingClientRect().height));
    assert(heights.every(height=>height<100),'Aggregate glyphs must not stretch their cards');
    assert.equal(await page.locator('.action-economy-section').evaluateAll(nodes=>new Set(nodes.map(n=>n.getBoundingClientRect().x)).size),1,'Mobile action categories stay in one readable column');
    await page.locator('.action-economy-section').evaluateAll(nodes=>nodes.forEach(node=>node.open=true));
    await page.locator('.action-tree > summary').evaluateAll(nodes=>nodes.forEach(node=>node.parentElement.open=true));
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Expanded trees overflow at '+width);
    if(width===390||width===1440)await page.screenshot({path:fileURLToPath(new URL('actions-'+width+'.png',artifacts))});
   }
   if(width===390&&['info','stats','inventory'].includes(key))await page.screenshot({path:fileURLToPath(new URL('sheet-'+key+'-390.png',artifacts))});
  }
 }
 await page.setViewportSize({width:390,height:900});await section('actions');
 const before=await page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return JSON.stringify((await listCreatures())[0].creature);});
 await page.locator('[data-act="action-variants"]').click();
 assert.equal(await page.locator('.variant-list input[type=checkbox]').count(),78);
 await page.locator('[data-variant-search]').fill('Disarmare');
 await page.locator('input[value="disarm_dmg"]').check();await page.locator('[data-save-variants]').click();
 assert((await page.locator('#app').textContent()).includes('Disarmare'));
 const after=await page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return JSON.stringify((await listCreatures())[0].creature);});assert.equal(after,before,'Variant preferences must not rewrite creature data');
 await page.reload();await page.locator('[data-act="open"]').click();await section('actions');
 assert((await page.locator('#app').textContent()).includes('Disarmare'),'Variant choice persists on reload');
 await page.locator('[data-timing="movement"] > summary').click();
 await page.locator('[data-timing="movement"] .action-tree > summary').click();
 await page.locator('[data-timing="movement"] .action-economy-entry > summary').filter({hasText:'Movimento furtivo'}).click();
 await page.locator('[data-timing="movement"] [data-target="skill:stealth"]').click();
 await page.locator('#sheet-roll-dialog').waitFor();assert((await page.locator('#sheet-roll-dialog h2').textContent()).includes('Furtività'));
 await page.locator('[data-act="close-sheet-roll"]').click();
 await page.waitForFunction(()=> !!navigator.serviceWorker.controller);
 await context.setOffline(true);await page.reload();await page.locator('[data-act="open"]').click();await section('actions');
 assert((await page.locator('#app').textContent()).includes('Movimento furtivo'));
 assert.deepEqual(errors,[]);assert.deepEqual(missing,[]);assert.deepEqual(writes,[]);
 console.log('PASS: 9 styled PWA sections at 360/390/768/1440px, expanded trees, three spell groups, native routes, stealth dice, persistent variants and offline reload');
}finally{await browser.close();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
