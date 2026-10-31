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
  if(path==='/__vtt_version'){
   res.setHeader('Content-Type','application/json');res.end(JSON.stringify({revision:'a'.repeat(40)}));return;
  }
  if(path==='/sw.js'){
   res.setHeader('Content-Type','text/javascript; charset=utf-8');
   res.end((await readFile(new URL('pwa/sw.js',root),'utf8')).replaceAll('__VTT_COMMIT_SHA__','a'.repeat(40)));return;
  }
  if(path.startsWith('/api/')){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({protocol:1,desktop_online:false}));return;}
  if(path==='/catalog/spells.json'){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({version:1,spells:[]}));return;}
  if(path==='/catalog/bestiary.json'){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({monsters:[{name:'Wolf',source:'MM',id:'bestiary:wolf:mm'}]}));return;}
  if(path==='/catalog/bestiary/Wolf/MM.json'){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({name:'Wolf',source:'MM',cr:'1/4',type:'beast',size:['M'],hp:{average:11},ac:[13],speed:{walk:40},str:12,dex:15,con:12,int:3,wis:12,cha:6,skill:{prc:'+3'},resist:['cold'],immune:['poison'],conditionImmune:['frightened']}));return;}
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
  if(key==='conditions'){
    // Exercise the existing conditions panel without creating new sheet controls.
    await page.evaluate(tab=>{
      const button=document.createElement('button');
      button.type='button';button.dataset.act='sheet';button.dataset.sheet=tab;
      document.body.append(button);button.click();button.remove();
    },key);
  }else await page.locator('#sheet-navigation [data-sheet="'+key+'"]').click();
  await page.waitForFunction(k=>document.querySelector('#app').dataset.renderedSheet===k,key);
 };
 const globalPage=async key=>{
  const back=page.locator('#creature-back');
  if(key==='library'&&await back.isVisible())await back.click();
  else {
    const fromCreature=await page.locator('#mobile-tabs').evaluate(n=>n.classList.contains('has-creature'));
    if(fromCreature&&key==='catalog')await back.click();
    const target=fromCreature&&key==='session'?page.locator('#dock-session'):page.locator('#nav [data-nav="'+key+'"]');
    await target.click();
  }
  await page.waitForFunction(k=>document.querySelector('#app').dataset.page===k,key);
 };
 await page.goto(origin);await page.locator('[data-act="library-add"]').waitFor();
 assert.equal(await page.locator('.play-dock .btn:visible').count(),3);
 assert.equal(await page.locator('[data-act="import"]').isVisible(),false);
 await page.locator('[data-act="library-add"]').click();
 assert.equal(await page.locator('[data-act="import"]').count(),0,'Creation no longer offers import');
 assert.equal(await page.locator('#library-create-name').getAttribute('placeholder'),'Nuova creatura');
 assert.equal(await page.locator('[data-act="library-create-kind"]').count(),2,'Character and monster creation are available');
 assert(await page.locator('[data-act="library-create-kind"][data-kind="monster"]').isEnabled(),'Bestiary monster creation is enabled');
 assert(await page.locator('.library-miniature-option[aria-pressed="true"]').count()>=1,'A base miniature is always selected');
 const miniatureSearch=page.locator('#library-miniature-search');
 assert(await miniatureSearch.evaluate(input=>{
  const r=input.getBoundingClientRect();
  const outer=input.closest('.library-miniature-search').getBoundingClientRect();
  return r.width>=100&&r.height>=38&&r.height<=47&&
   r.left>=outer.left&&r.right<=outer.right+1&&r.top>=outer.top-1&&r.bottom<=outer.bottom+1;
 }), 'Miniature search fits properly inside its compact field');
 const moreMiniatures=page.locator('[data-act="library-miniature-more"]');
 await moreMiniatures.waitFor({state:'visible'});
 const initialMiniatures=await page.locator('.library-miniature-option').count();
 assert.equal(initialMiniatures,36,'First miniature page shows 36 entries');
 const initialProgress=await page.locator('.library-miniature-progress').textContent();
 const totalMiniatures=Number(initialProgress.match(/di (\d+)/)?.[1]);
 assert(totalMiniatures>initialMiniatures,'Catalog has additional browseable miniatures');
 await moreMiniatures.click();
 assert.equal(await page.locator('.library-miniature-option').count(),
   Math.min(initialMiniatures+36,totalMiniatures),'Show more reveals additional miniatures without search');
 await miniatureSearch.fill('___no_matching_miniature___');
 assert(await moreMiniatures.isHidden(),'Show more hides for empty search results');
 await miniatureSearch.fill('');
 assert.equal(await page.locator('.library-miniature-option').count(),36,
   'Clearing search restarts browsing from the first page');
 await page.locator('[data-act="library-create-close"]').first().click();await shot('library');
 await page.locator('[data-act="library-add"]').click();
 await page.locator('[data-act="create"]').click();
 await page.locator('[data-sheet-context="identity"]').waitFor();
 assert(await page.evaluate(async()=>{
   const {listCreatures}=await import('/creatures.js');
   const c=(await listCreatures())[0].creature;
   return !!c.default_miniature_id&&c.default_miniature_id===c.current_miniature_id;
 }), 'New creature starts with a saved base miniature');
 await page.locator('[data-sheet-context="identity"]').click();await page.locator('#sheet-context-dialog [data-identity-value="names"]').first().fill('Lyria · Sentinella delle stelle');
 // Changing destination immediately must flush the focused name field.
 await sheet('battle');
 assert.equal(await page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.name;}),'Lyria · Sentinella delle stelle');
 assert.deepEqual(await page.locator('#sheet-navigation [data-sheet]').evaluateAll(nodes=>nodes.map(n=>n.dataset.sheet)),['info','battle','magic','inventory']);
 assert(await page.locator('#dock-session').isVisible(),'Partita stays in the creature dock');
 assert.equal(await page.locator('#dock-catalog').count(),0,'Catalogo belongs to the archive');
 assert.equal(await page.locator('.play-dock .btn:visible').count(),5);
 assert.equal(await page.locator('#dock-session .destination-label').textContent(),'Partita');
 assert(await page.locator('#sheet-navigation [data-sheet="inventory"]').evaluate(node=>
   parseFloat(getComputedStyle(node).borderRightWidth)>0),'Zaino and Partita remain visually separated');
 assert.equal(await page.locator('#more-navigation').count(),0);
 assert(await page.locator('#creature-back').isVisible(),'Back replaces the portrait');
 assert.equal(await page.locator('#creature-symbol').count(),0);
 assert.equal(await page.locator('[data-sheet="actions"]').count(),0);
 await sheet('magic');
 await page.goBack();await page.waitForFunction(()=>document.querySelector('#app').dataset.renderedSheet==='battle');
 await page.goForward();await page.waitForFunction(()=>document.querySelector('#app').dataset.renderedSheet==='magic');
 await sheet('battle');await shot('actions');
 const resources=page.locator('#sheet-play-view [data-battle-action="resources"]');
 if(await resources.getAttribute('open')===null)
   await resources.locator(':scope > summary.play-battle-summary').click();
 const offhandResource=resources.locator('[data-rule-action="two_weapon"] [data-act="battle-action-jump"]');
 assert.equal(await offhandResource.count(),1,'Secondary attack is always in base rules');
 assert.equal(await offhandResource.isEnabled(),true,'Blocked secondary attack still links to Azioni');
 await offhandResource.click();
 const secondary=page.locator('#sheet-play-view [data-battle-action="others"] [data-attack-id="two_weapon"]');
 assert.equal(await secondary.count(),1);
 assert.equal(await page.locator('[data-battle-action="others"]').getAttribute('open'),'',
  'Selecting offhand base rule reveals its matching action');
 await resources.locator('[data-rule-action="spell_cast"] [data-act="action-open-spells"]').click();
 await page.waitForFunction(()=>document.querySelector('#app').dataset.renderedSheet==='magic');
 await sheet('battle');
 assert.equal(await page.locator('#sheet-play-view [data-battle-action="spells"]').count(),0);
 assert.equal(await page.locator('#sheet-play-view [data-act="battle-toggle-class-only"]').count(),0,
  'Class-only filtering no longer exists');
 const checks=page.locator('#sheet-play-view [data-battle-action="checks"]');
 assert.equal(await checks.count(),1,'Generic ability checks belong in the unified Actions tab');
 await checks.locator('summary.play-battle-summary').click();
 assert.equal(await checks.locator('[data-action-ability]').count(),6);
 for(const viewport of [{width:320,height:740},{width:360,height:800},{width:390,height:844},{width:430,height:932},{width:844,height:390}]){
  await page.setViewportSize(viewport);
  for(const key of ['battle','magic','inventory','conditions','info']){
   await sheet(key);
   assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),key+' overflows '+viewport.width);
   const dock=await page.locator('.play-dock .btn:visible').evaluateAll(nodes=>nodes.map(n=>({h:n.getBoundingClientRect().height,w:n.getBoundingClientRect().width,label:n.textContent.trim(),bottom:n.getBoundingClientRect().bottom})));
   assert.equal(dock.length,5);
   assert(dock.every(n=>n.h>=48&&n.w>=48&&n.label&&n.bottom<=viewport.height),'Labeled touch targets remain reachable at '+viewport.width);
   assert.equal(await page.locator('#app h1').count(),1);
  }
 }
 await page.setViewportSize({width:390,height:844});await sheet('conditions');
 assert.equal(await page.locator('.sheet-quick-links').count(),0,'No new controls above sheets');
 assert.equal(await page.locator('#navigation-dialog').count(),0);
 await shot('tools');
 await sheet('conditions');
 await sheet('info');
 assert.equal(await page.locator('#sheet-navigation [data-sheet="stats"],#secondary-sheet-navigation [data-sheet="stats"]').count(),0);
 assert.equal(await page.locator('#sheet-play-view .play-abilities .play-ability').count(),6);
 assert.equal(await page.locator('#sheet-play-view .play-skills [data-play-filter]').count(),18);
 assert.equal(await page.locator('#sheet-play-view .play-competences > .play-section-divider').count(),0,'No duplicate Competenze heading');
 assert.equal(await page.locator('#sheet-play-view .play-competences.play-card').count(),0,'Competenze uses line dividers, not an enclosing card');
 assert.equal(await page.locator('#sheet-play-view .play-identity-mark').count(),0,'Info contains no creature icon');
 assert.equal(await page.locator('#sheet-play-view .play-info-traits > h2.play-section-divider').textContent(),'Tratti',
  'Tratti uses the same permanent heading as Competenze');
 assert.equal(await page.locator('#sheet-play-view .play-traits-disclosure').count(),0,
  'Tratti must not be an expandable section');
 assert(await page.locator('#sheet-play-view .play-info-traits-content').isVisible(),
  'The Tratti section is immediately visible even if this creature has no traits');
 assert.equal(await page.locator('#sheet-play-view .play-skills-disclosure').getAttribute('open'),null);
 await page.locator('#sheet-play-view .play-skills-disclosure > summary').click();
 assert.equal(await page.locator('#sheet-play-view .play-skills-disclosure').getAttribute('open'),'');
 assert(await page.locator('#sheet-play-view [data-play-search]').isVisible());
 await sheet('battle');
 assert.equal(await page.locator('#sheet-play-view [data-act="battle-competences-open"]').innerText().then(s=>s.includes('Competenze')),true);
 await page.locator('#sheet-play-view [data-act="battle-competences-open"]').click();
 assert.match(await page.locator('#sheet-context-dialog').innerText(),/Strumenti/);
 assert.match(await page.locator('#sheet-context-dialog').innerText(),/Armi/);
 assert.match(await page.locator('#sheet-context-dialog').innerText(),/Armature/);
 await page.locator('#sheet-context-dialog [data-act="sheet-context-close"]').click();
 assert.equal(await page.locator('.disclosure-panel[open]').count(),0);
 await sheet('battle');await sheet('info');
 assert.equal(await page.locator('#sheet-play-view .play-skills-disclosure').getAttribute('open'),'','Expanded skills survive a return to Info');
 assert(await page.locator('#sheet-play-view .play-info-traits-content').isVisible(),
  'Tratti stays visible on return to Info');
 await page.locator('#sheet-play-view [data-sheet-context]').filter({hasText:'Aspetto'}).click();
 await sheet('battle');await sheet('info');
 assert.equal(await page.locator('[data-miniature-kind="base"]').isVisible(),false,'Leaving a section closes its editor');
 await sheet('magic');
 assert.equal(await page.locator('[data-magic-tool="slots"]').isVisible(),false);
 assert.equal(await page.locator('#app').getAttribute('data-rendered-sheet'),'magic',
  'Power details are rendered in the dedicated Powers tab');
 assert(await page.locator('#sheet-play-view').isVisible());
 assert.equal(await page.locator('#sheet-play-view [data-sheet-context="magic-tools"]').count(),0,
  'The legacy all-in-one tools popup has been replaced by contextual controls');
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
 assert.equal(await page.locator('#creature-back').isVisible(),false,'Archive hides character back');
 assert(await page.locator('#nav [data-nav="library"]').isVisible(),'Archive dock is restored');
 assert.equal(await page.locator('#sheet-navigation').isVisible(),false,'Character dock is hidden');
 assert.equal(await page.locator('#creature-name').textContent(),'VTT Mobile');
 assert.equal(await page.locator('#creature-classes').isVisible(),false);
 assert.equal(await page.locator('.library-index h1').count(),1,'The archive has one heading');
 assert.equal(await page.locator('#library-search').count(),0,'No search bar on the home');
 assert(await page.locator('.library-home-hero .library-rows').isVisible(),'Roster belongs inside the hero');
 assert.equal(await page.locator('.library-home-hero .library-hero-crest').count(),1,
  'Original diamond emblem decorates the home background');
 assert(await page.locator('.library-hero-crest-inner').evaluate(node=>
  getComputedStyle(node).transform!=='none'),'Diamond is rotated above the hero gradient');
 assert.equal(await page.locator('.library-home-shortcuts button').count(),2,'Only create and import actions remain');
 assert.equal(await page.locator('.library-list-header').isVisible(),false,'Selection controls are initially hidden');
 for(const width of [320,360,390,430,768]){
  await page.setViewportSize({width,height:820});
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),
   'Creature home must not overflow '+width);
 }
 await page.setViewportSize({width:390,height:844});
 const firstCard=page.locator('.library-creature-entry .creature-open').first();
 await firstCard.dispatchEvent('pointerdown',{pointerId:1,button:0,clientX:10,clientY:10});
 await page.waitForTimeout(610);
 await firstCard.dispatchEvent('pointerup',{pointerId:1,button:0,clientX:10,clientY:10});
 assert(await page.locator('.library-list-header').isVisible(),'Long press enters selection mode');
 assert(await page.locator('[data-act="library-export"]').isVisible(),'Bulk actions appear on selection');
 assert.match(await page.locator('.library-list-header [data-selection-last]').textContent(),/Ultima selezione/);
 assert.equal(await page.locator('.library-list-header [data-selection-count]').textContent(),'1 selezionato');
 assert(await page.locator('.library-list-header').evaluate(el=>el.getBoundingClientRect().bottom<=innerHeight),
   'Creature selection actions remain visible at the viewport bottom');
 assert(await page.locator('.library-list-header [data-library-select-all]').evaluate(input=>{
  const indicator=input.nextElementSibling;
  const r=indicator.getBoundingClientRect();
  return input.type==='checkbox'&&r.width>=23&&r.height>=23&&
   getComputedStyle(indicator).borderStyle==='solid';
 }), 'Select-all has a properly sized custom control');
 assert.equal(await page.locator('.library-list-header .library-bulk-button').count(),3,
  'Export, send and delete use styled controls in one selection toolbar');
 assert.equal(await page.locator('.library-list-header .library-selection-count').count(),0,
  'No selection count is shown');
 for(const width of [320,360,390,430,768]){
  await page.setViewportSize({width,height:820});
  const metrics=await page.locator('.library-list-header').evaluate(header=>{
   const items=[header.querySelector('.library-select-master'),...header.querySelectorAll('.library-bulk-button')];
   return {box:header.getBoundingClientRect().toJSON(),
    elements:items.map(n=>n.getBoundingClientRect().toJSON())};
  });
  assert.equal(metrics.elements.length,4,'Select-all and three bulk actions');
  assert(metrics.elements.every(item=>item.width>0&&item.height>0&&
    item.left>=metrics.box.left-1&&item.right<=metrics.box.right+1),
    'Selection controls fit the toolbar, including responsive wrapping at '+width);
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),
    'Selection toolbar must not overflow at '+width);
 }
 await page.setViewportSize({width:390,height:844});
 assert.equal(await page.locator('.library-creature-entry .library-batch-check:visible').count(),1);
 await page.locator('[data-library-select-all]').uncheck();
 assert.equal(await page.locator('.library-list-header').isVisible(),false,'Selection mode exits after deselect');
 await page.locator('[data-act="open"]').click();await sheet('battle');
 await page.waitForFunction(()=>!!navigator.serviceWorker.controller);
 await context.setOffline(true);await page.reload();await page.locator('[data-act="open"]').click();await sheet('battle');
 assert.equal(await page.locator('.play-dock .btn:visible').count(),5);
 assert(await page.locator('#creature-back').isVisible());
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
 assert.equal(await page.locator('#sheet-navigation [data-sheet]').count(),4);
 // Archive cards preserve species and class details without creature portraits.
 await globalPage('library');
 await page.evaluate(async()=>{
  const {listCreatures,openCreatureEditor,createCreature}=await import('/creatures.js');
  const rows=await listCreatures(),character=rows.find(row=>row.creature.kind==='character').creature;
  await (await openCreatureEditor(character.id)).update({species:'Elfo'});
  const monster=await createCreature('monster','Orco del crepuscolo');
  await (await openCreatureEditor(monster.data.id)).update({species:'Orco'});
 });
 // Direct IndexedDB fixture edits are outside the UI editor: reload the archive
 // before inspecting it rather than racing an already-active library page.
 await page.reload();await page.locator('.creature-card').filter({hasText:'Lyria · Sentinella delle stelle'}).waitFor();
 const elfCard=page.locator('.creature-card').filter({hasText:'Lyria · Sentinella delle stelle'});
 assert.match(await elfCard.locator('.creature-details').textContent(),/Elfo/);
 assert.doesNotMatch(await elfCard.locator('.creature-details').textContent(),/Personaggio|Mostro/);
 assert.equal(await elfCard.locator('.creature-face').count(),0);
 assert.match(await elfCard.locator('.creature-classes').textContent(),/Guerriero 3 · Mago 2/);
 const orcCard=page.locator('.creature-card').filter({hasText:'Orco del crepuscolo'});
 assert.match(await orcCard.locator('.creature-details').textContent(),/Orco/);
 assert.equal(await orcCard.locator('.creature-face').count(),0);
 assert.equal(await page.locator('.library-creature-emblem').count(),2,'Cards display existing VTT glyphs');
 assert.equal(await page.locator('.library-creature-entry .library-batch-check:visible').count(),0);
 await page.locator('[data-act="library-filter"][data-kind="monster"]').click();
 assert.equal(await elfCard.isVisible(),false);
 assert(await orcCard.isVisible(),'Monster filter shows monster cards');
 await page.locator('[data-act="library-filter"][data-kind="character"]').click();
 assert(await elfCard.isVisible());
 assert.equal(await orcCard.isVisible(),false);
 await page.locator('[data-act="library-filter"][data-kind="all"]').click();
 assert(await orcCard.isVisible()&&await elfCard.isVisible());
 await orcCard.locator('[data-act="open"]').click();
 assert.equal(await page.locator('#creature-symbol').count(),0);
 await sheet('info');
 assert.equal(await page.locator('.play-identity-mark').count(),0,'No portrait icon appears on Info');
 // Independent monsters are created from an actual bestiary choice, not a blank sheet.
 await context.setOffline(false);
 await page.locator('#creature-back').click();
 await page.locator('[data-act="library-add"]').click();
 await page.locator('[data-act="library-create-kind"][data-kind="monster"]').click();
 assert(await page.locator('#library-create-bestiary').isVisible());
 assert.equal(await page.locator('[data-act="create"]').isEnabled(),false,'A bestiary source is required');
 await page.locator('#library-bestiary-search').fill('Wolf');
 await page.locator('[data-act="library-bestiary-select"]').first().waitFor();
 await page.locator('[data-act="library-bestiary-select"]').first().click();
 assert(await page.locator('[data-act="create"]').isEnabled());
 await page.locator('#library-create-name').fill('Lupo guardiano');
 await page.locator('[data-act="create"]').click();
 await page.locator('[data-sheet-context="identity"]').waitFor();
 assert(await page.evaluate(async()=>{
  const {listCreatures}=await import('/creatures.js');
  const monster=(await listCreatures()).find(row=>row.creature.name==='Lupo guardiano')?.creature;
  return monster?.kind==='monster'&&!monster?.parent_creature_id&&
    monster.species==='Wolf'&&monster.bestiary_ref?.source==='MM'&&
    monster.stat_block?.skill?.prc==='+3'&&monster.stat_block?.immune?.[0]==='poison';
 }), 'The new monster retains its full bestiary statistics as an independent sheet');
 // The existing Classi popup must let a bestiary monster gain a class level.
 await page.locator('#sheet-play-view [data-sheet-context]').filter({hasText:'Classi'}).click();
 await page.locator('#sheet-context-dialog [data-act="level-up-open"]').click();
 const levelDialog=page.locator('#class-level-up-dialog');
 await levelDialog.waitFor({state:'visible'});
 const classSelect=levelDialog.locator('[data-level-up-class]');
 const firstNew=classSelect.locator('option[value^="new:"]').first();
 const chosen=await firstNew.textContent();
 const chosenValue=await firstNew.getAttribute('value');
 assert(chosenValue,'The class catalog offers at least one new class for the monster');
 await classSelect.selectOption(chosenValue);
 const hpInput=levelDialog.locator('[data-level-up-hp]').first();
 await hpInput.waitFor({state:'visible'});
 await page.waitForFunction(()=>
   !document.querySelector('#class-level-up-dialog [data-level-up-confirm]')?.disabled);
 const hpDie=Number(await hpInput.getAttribute('value'));
 assert(hpDie>=1,'Monster class level uses the class hit die');
 assert.equal(await levelDialog.locator('[data-level-up-xp-note]').innerText().then(t=>t.includes('GS')),true);
 await levelDialog.locator('[data-level-up-confirm]').click();
 await levelDialog.waitFor({state:'detached'});
 assert(await page.evaluate(async()=>{
   const {listCreatures}=await import('/creatures.js');
   const monster=(await listCreatures()).find(row=>row.creature.name==='Lupo guardiano')?.creature;
   return monster?.kind==='monster' && monster.classes?.length===1 && monster.level===1 &&
     monster.stat_block?.cr==='1/4' && monster.stat_block?.hp?.average===11 &&
     monster.stat_block?.skill?.prc==='+3' && monster.stat_block?.immune?.[0]==='poison' &&
     monster.max_hp_base>11 && monster.current_hp>11;
 }), 'Adding a class preserves monster statblock, CR, skills, immunities and base HP');
 await page.locator('[data-level-up-close]').click();
 // Advancing a bestiary monster from class level 1 to 2 must apply its XP floor.
 await page.locator('#sheet-context-dialog [data-act="level-up-open"]').click();
 await levelDialog.waitFor({state:'visible'});
 assert.equal(await levelDialog.locator('[data-level-up-class]').inputValue(),'owned:0');
 await page.waitForFunction(()=>
   !document.querySelector('#class-level-up-dialog [data-level-up-confirm]')?.disabled);
 assert.match(await levelDialog.locator('[data-level-up-xp-note]').innerText(),/300/);
 await levelDialog.locator('[data-level-up-confirm]').click();
 await levelDialog.waitFor({state:'detached'});
 assert(await page.evaluate(async()=>{
   const {listCreatures}=await import('/creatures.js');
   const c=(await listCreatures()).find(row=>row.creature.name==='Lupo guardiano')?.creature;
   return c?.kind==='monster' && c.level===2 && c.classes?.[0]?.level===2 &&
     c.xp===300 && c.stat_block?.cr==='1/4' && c.stat_block?.hp?.average===11;
 }), 'A monster at two class levels receives at least 300 XP while its CR stays unchanged');
 await page.locator('[data-level-up-close]').click();
 const monsterXpField=page.locator('#sheet-context-dialog [data-field="xp"]');
 assert.equal(await monsterXpField.inputValue(),'300','The Classi editor displays the new XP floor');
 assert.equal(await monsterXpField.getAttribute('min'),'300','The Classi editor enforces the XP floor');
 await page.locator('#sheet-context-dialog [data-act="sheet-context-close"]').click();
 // The score editor proposes HP changes only when the effective modifier changes.
 const conCard=page.locator('#sheet-play-view [data-act="sheet-score-formula"][data-target="ability:con"]');
 const scoreFormula=page.locator('#sheet-score-formula-dialog');
 const scoreEditor=page.locator('#sheet-score-dialog');
 const conDialog=page.locator('#constitution-hp-dialog');
 const editCon=async score=>{
   await conCard.click();
   await scoreFormula.locator('[data-act="sheet-score-edit-base"]').click();
   await scoreEditor.locator('#sheet-score-input').fill(String(score));
   await scoreEditor.locator('[data-act="save-score"]').click();
 };
 const monsterBeforeCon=await page.evaluate(async()=>{
   const {listCreatures}=await import('/creatures.js');
   return (await listCreatures()).find(row=>row.creature.name==='Lupo guardiano')?.creature;
 });
 assert.equal(monsterBeforeCon.abilities.con,12);
 await editCon(13);
 await scoreFormula.waitFor({state:'visible'});
 assert.equal(await conDialog.count(),0,'No prompt when 12 → 13 keeps modifier +1');
 await scoreFormula.locator('[data-act="close-score-formula"]').click();
 const hpBefore=await page.evaluate(async()=>{
   const {listCreatures}=await import('/creatures.js');
   const c=(await listCreatures()).find(row=>row.creature.name==='Lupo guardiano')?.creature;
   return {max:c.max_hp_base,current:c.current_hp};
 });
 await editCon(14);
 await conDialog.waitFor({state:'visible'});
 assert.match(await conDialog.textContent(),/\+1/);
 assert.equal((await page.locator('#sheet-score-formula-dialog').count()),0,
   'The modifier confirmation takes precedence over the formula dialog');
 await conDialog.locator('[data-con-hp-apply]').click();
 await scoreFormula.waitFor({state:'visible'});
 assert(await page.evaluate(async expected=>{
   const {listCreatures}=await import('/creatures.js');
   const c=(await listCreatures()).find(row=>row.creature.name==='Lupo guardiano')?.creature;
   return c.abilities.con===14&&c.max_hp_base===expected.max+1&&
     c.current_hp===expected.current+1&&c.stat_block.hp.average===11&&c.stat_block.cr==='1/4';
 },hpBefore),'Applying +1 CON modifier changes max and current HP, never bestiary stats');
 await scoreFormula.locator('[data-act="close-score-formula"]').click();
 await editCon(10);
 await conDialog.waitFor({state:'visible'});
 assert.match(await conDialog.textContent(),/−2|-2/);
 await conDialog.locator('[data-con-hp-keep]').click();
 await scoreFormula.waitFor({state:'visible'});
 assert(await page.evaluate(async expected=>{
   const {listCreatures}=await import('/creatures.js');
   const c=(await listCreatures()).find(row=>row.creature.name==='Lupo guardiano')?.creature;
   return c.abilities.con===10&&c.max_hp_base===expected.max+1&&c.current_hp===expected.current+1;
 },hpBefore),'Keeping HP commits Constitution but leaves the HP values unchanged');
 await scoreFormula.locator('[data-act="close-score-formula"]').click();
 await page.locator('#creature-back').click();
 await page.locator('[data-act="library-filter"][data-kind="monster"]').click();
 assert(await page.locator('.creature-card').filter({hasText:'Lupo guardiano'}).isVisible());
 assert.deepEqual(errors,[]);assert.deepEqual(missing,[]);assert.deepEqual(writes,[]);
 console.log('PASS: six direct creature destinations at 320/360/390/430px and landscape, header back restores archive bars, quick condition/origin links, pending saves, catalog, session, offline and disclosure regressions.');
 console.log('Screenshots: '+fileURLToPath(artifacts));
}finally{await browser?.close();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
