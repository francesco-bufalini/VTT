// Real phone-navigation regression, served through the native host allowlist.
// Uses synthetic IndexedDB in a fresh Chrome profile, never a player's archive.
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
  res.setHeader('Cache-Control','no-store');
  if(path.startsWith('/api/')){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({protocol:1,desktop_online:false}));return;}
  if(path==='/catalog/spells.json'){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({version:1,spells:[]}));return;}
  const route=routes.get(path);if(!route){res.writeHead(404);res.end();return;}
  res.setHeader('Content-Type',route[1]);res.end(await readFile(new URL(route[0],root)));
 }catch{res.writeHead(404);res.end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const origin=process.env.VTT_PWA_TEST_ORIGIN||'http://127.0.0.1:'+server.address().port;
let browser;
try{
 browser=await chromium.launch({headless:true,...(process.platform==='win32'?{executablePath:process.env.CHROME_PATH||'C:/Program Files/Google/Chrome/Application/chrome.exe'}:{})});
 const context=await browser.newContext({viewport:{width:390,height:844},hasTouch:true,isMobile:true}),page=await context.newPage();
 const errors=[],missing=[],writes=[];
 page.on('pageerror',e=>errors.push(e.message));
 page.on('response',r=>{if(r.status()===404)missing.push(r.url());});
 page.on('request',r=>{if(r.method()!=='GET'&&r.url().includes('/api/'))writes.push(r.url());});
 page.setDefaultTimeout(15000);
 const shot=async name=>page.screenshot({path:fileURLToPath(new URL('navigation-'+name+'.png',artifacts))});
 const sheet=async key=>{
  if(await page.locator('#sheet-context-dialog[open]').count())await page.locator('#sheet-context-dialog [data-act="sheet-context-close"]').first().click();
  const target=page.locator('button[data-sheet="'+key+'"]').first();
  if(!await target.isVisible())await page.locator('#more-navigation').click();
  await target.click();await page.waitForFunction(k=>document.querySelector('#app').dataset.renderedSheet===k,key);
  assert.equal(await page.locator('#navigation-dialog').evaluate(n=>n.open),false);
 };
 const globalPage=async key=>{
  const target=page.locator('#nav [data-nav="'+key+'"]');
  if(!await target.isVisible())await page.locator('#more-navigation').click();
  await target.click();await page.waitForFunction(k=>document.querySelector('#app').dataset.page===k,key);
 };
 await page.goto(origin);await page.locator('[data-act="create"]').waitFor();
 assert.equal(await page.locator('.play-dock .btn:visible').count(),3);
 assert.equal(await page.locator('[data-act="import"]').isVisible(),false);
 await page.locator('.library-management > summary').click();
 assert(await page.locator('[data-act="import"]').isVisible());
 await page.locator('.library-management > summary').click();await shot('library');
 await page.locator('[data-act="create"]').click();await page.locator('[data-sheet-context="identity"]').click();await page.locator('[data-field="name"]').fill('Lyria · Sentinella delle stelle');
 // Changing destination immediately must flush the focused name field.
 await sheet('battle');
 assert.equal(await page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.name;}),'Lyria · Sentinella delle stelle');
 assert.deepEqual(await page.locator('#sheet-navigation [data-sheet]').evaluateAll(nodes=>nodes.map(n=>n.dataset.sheet)),['info','actions','battle','magic','inventory']);
 await sheet('actions');
 await page.goBack();await page.waitForFunction(()=>document.querySelector('#app').dataset.renderedSheet==='battle');
 await page.goForward();await page.waitForFunction(()=>document.querySelector('#app').dataset.renderedSheet==='actions');
 await shot('actions');
 assert.equal(await page.locator('.play-timing button').count(),5);
 await page.locator('.play-card .play-list-row').first().click();await page.locator('#sheet-context-dialog').waitFor();
 assert(await page.locator('#sheet-context-dialog .action-economy-row').first().isVisible());
 await sheet('battle');await shot('battle');
 for(const viewport of [{width:320,height:740},{width:360,height:800},{width:390,height:844},{width:430,height:932},{width:844,height:390}]){
  await page.setViewportSize(viewport);
  for(const key of ['actions','battle','magic','inventory','conditions','traits','info','origins']){
   await sheet(key);
   assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),key+' overflows '+viewport.width);
   const dock=await page.locator('.play-dock .btn:visible').evaluateAll(nodes=>nodes.map(n=>({h:n.getBoundingClientRect().height,w:n.getBoundingClientRect().width,label:n.textContent.trim(),bottom:n.getBoundingClientRect().bottom})));
   assert.equal(dock.length,6);
   assert(dock.every(n=>n.h>=48&&n.w>=48&&n.label&&n.bottom<=viewport.height),'Labeled touch targets remain reachable at '+viewport.width);
   assert.equal(await page.locator('#app h1').count(),1);
  }
 }
 await page.setViewportSize({width:390,height:844});await sheet('conditions');
 assert(await page.locator('#more-navigation').evaluate(n=>n.classList.contains('is-current')));
 await page.locator('#more-navigation').click();
 assert.equal(await page.locator('#navigation-dialog button:visible').count(),7);
 assert(await page.locator('#navigation-dialog').evaluate(n=>n.contains(document.activeElement)));
 assert(await page.locator('.navigation-row > .vtt-action-glyph').evaluateAll(nodes=>nodes.every(n=>n.getBoundingClientRect().width===24&&n.getBoundingClientRect().height===24)),'Menu glyphs keep their sprite dimensions');
 await shot('menu');await page.keyboard.press('Escape');
 await page.waitForFunction(()=>document.querySelector('#more-navigation')?.getAttribute('aria-expanded')==='false');
 await sheet('info');
 assert.equal(await page.locator('#sheet-navigation [data-sheet="stats"],#secondary-sheet-navigation [data-sheet="stats"]').count(),0);
 assert.equal(await page.locator('#sheet-play-view .play-abilities .play-ability').count(),6);
 assert.equal(await page.locator('#sheet-play-view .play-skills [data-play-filter]').count(),18);
 assert.equal(await page.locator('#sheet-play-view [data-sheet-context="tools"] .play-row-copy strong').innerText(),'Altre competenze');
 await page.locator('#sheet-play-view [data-sheet-context="tools"]').click();
 assert.match(await page.locator('#sheet-context-dialog').innerText(),/Strumenti/);
 assert.match(await page.locator('#sheet-context-dialog').innerText(),/Armi/);
 assert.match(await page.locator('#sheet-context-dialog').innerText(),/Armature/);
 await page.locator('#sheet-context-dialog [data-act="sheet-context-close"]').click();
 assert.equal(await page.locator('.disclosure-panel[open]').count(),0);
 await page.locator('#sheet-play-view [data-sheet-context]').filter({hasText:'Aspetto'}).click();
 await sheet('battle');await sheet('info');
 assert.equal(await page.locator('[data-miniature-kind="base"]').isVisible(),false,'Leaving a section closes its editor');
 await sheet('magic');
 assert.equal(await page.locator('[data-magic-tool="slots"]').isVisible(),false);
 await page.locator('#sheet-play-view [data-sheet-context="magic-tools"]').click();
 assert.equal(await page.locator('.magic-toolbar button:visible').count(),6);
 for(const kind of ['slots','book','catalog','choices','concentration']){
  if(!await page.locator('#sheet-context-dialog[open]').count())await page.locator('#sheet-play-view [data-sheet-context="magic-tools"]').click();
  await page.locator('[data-magic-tool="'+kind+'"]:visible').click();await page.locator('#magic-tools-dialog').waitFor();
  await page.locator('[data-act="magic-tool-close"]').click();
 }
 await shot('powers');
 await globalPage('catalog');
 await page.locator('.catalog-entry').first().click();await page.locator('[data-act="catalog-close"]').waitFor();
 assert.equal(await page.locator('#catalog-search').count(),0,'Selected detail gets its own focused screen');
 await page.locator('[data-act="catalog-close"]').click();await page.locator('#catalog-search').waitFor();
 assert.equal(await page.locator('#quick-name').isVisible(),false);
 await page.locator('.catalog-create > summary').click();assert(await page.locator('#quick-name').isVisible());
 await page.locator('.connection-link').click();await page.waitForFunction(()=>document.querySelector('#app').dataset.page==='session');
 assert(await page.locator('[data-session-content="connection"]').isVisible());
 assert.equal(await page.locator('.session-map-panel').isVisible(),false);
 await page.locator('[data-session-pane="chat"]').click();await page.locator('[data-act="open-chat-dice"]').click();
 await page.locator('#chat-dice-dialog [data-act="roll"]').click();await page.locator('.dice-result').waitFor();
 await page.locator('[data-act="close-chat-dice"]').click();await shot('chat');
 await page.locator('[data-session-pane="table"]').click();await page.locator('[data-session-content="table"]:visible').waitFor();assert(await page.locator('.session-map-panel').isVisible());
 assert.equal(await page.locator('#pair-form').isVisible(),false);
 await globalPage('library');
 await page.locator('.library-management > summary').click();await page.locator('[data-act="library-select-all"]').click();
 await page.locator('[data-act="library-export"]').waitFor();
 assert(await page.locator('.library-management').evaluate(n=>n.open),'Batch operations do not hide themselves after rerender');
 await page.locator('[data-act="open"]').click();await sheet('actions');
 await page.waitForFunction(()=>!!navigator.serviceWorker.controller);
 await context.setOffline(true);await page.reload();await page.locator('[data-act="open"]').click();await sheet('actions');
 assert.equal(await page.locator('.play-dock .btn:visible').count(),6);
 // Opening a multiclass character shows every class both in the persistent
 // header and directly below the name on the Info tab.
 await globalPage('library');
 await page.evaluate(async()=>{
   const {listCreatures,openCreatureEditor}=await import('/creatures.js');
   const id=(await listCreatures())[0].creature.id;
   const editor=await openCreatureEditor(id);
   await editor.update({class:'Guerriero',classes:[{name:'Guerriero',level:3},{name:'Mago',level:2}],level:5});
   await editor.flush();
 });
 await page.locator('[data-act="open"]').click();
 await page.waitForFunction(()=>document.querySelector('#app').dataset.renderedSheet==='info');
 assert.match(await page.locator('#creature-classes').textContent(),/Guerriero 3 · Mago 2/);
 assert.match(await page.locator('.play-identity-classes').textContent(),/Guerriero 3 · Mago 2 · Liv\. totale 5/);
 assert(await page.locator('#sheet-play-view [data-sheet-context]').filter({hasText:'Aspetto'}).count());
 assert.equal(await page.locator('#sheet-navigation [data-sheet]').count(),5);
 assert.deepEqual(errors,[]);assert.deepEqual(missing,[]);assert.deepEqual(writes,[]);
 console.log('PASS: all 9 destinations at 320/360/390/430px and landscape, 48px labeled navigation, modal focus/Escape, pending saves, disclosure memory, catalog creation, session panes, offline dice and offline reopening.');
 console.log('Screenshots: '+fileURLToPath(artifacts));
}finally{await browser?.close();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
