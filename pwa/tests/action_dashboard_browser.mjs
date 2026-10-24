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
 await page.goto(origin);await page.locator('[data-act="library-add"]').waitFor();
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
 const section=async key=>{
  if(await page.locator('#sheet-context-dialog[open]').count())
   await page.locator('#sheet-context-dialog [data-act="sheet-context-close"]').first().click();
  if(key==='conditions'){
   await page.evaluate(tab=>{
    const button=document.createElement('button');
    button.type='button';button.dataset.act='sheet';button.dataset.sheet=tab;
    document.body.append(button);button.click();button.remove();
   },key);
  }else await page.locator('#sheet-navigation [data-sheet="'+key+'"]').click();
  await page.waitForFunction(tab=>document.querySelector('#app').dataset.renderedSheet===tab,key);
 };
 for(const width of [360,390,768,1440]){
  await page.setViewportSize({width,height:900});
  for(const key of ['info','battle','magic','inventory','conditions']){
   await section(key);
   assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),key+' overflow at '+width);
   if(key==='battle'){
    const classFilter=page.locator('[data-act="battle-toggle-class-only"]');
    assert.equal(await classFilter.count(),1,'Class-only filter should always be available');
    if(width===360)assert.equal(await classFilter.getAttribute('aria-pressed'),'true',
      'The initial filter shows character privileges only');
    if(await classFilter.getAttribute('aria-pressed')==='true')await classFilter.click();
    const checks=page.locator('[data-battle-action="checks"]');
    assert.equal(await checks.count(),1);
    assert.equal(await checks.locator('[data-action-ability]').count(),6);
    assert.equal(await checks.locator('.play-battle-attack-entry').count(),24);
    assert.equal(await page.locator('.page-head [data-act="action-variants"]').count(),1);
    assert.equal(await page.locator('#sheet-navigation [data-sheet="actions"]').count(),0);
    const expand=page.locator('[data-act="battle-expand-all"]');
    const collapse=page.locator('[data-act="battle-collapse-all"]');
    assert(await expand.isVisible()&&await collapse.isVisible(),'Global list controls appear above attacks');
    if(width===360){
     const physical=page.locator('[data-battle-action="attacks"]');
     assert.match(await physical.locator('summary.play-battle-summary').textContent(),/^Attacchi$/);
     assert.equal(await physical.locator('[data-action-timing]').count(),0,'Attacks are not divided by action cost');
     assert.equal(await physical.locator('[data-attack-id="unarmed"]').count(),1,'Unarmed is always available');
     const resources=page.locator('[data-battle-action="resources"]');
     assert.equal(await resources.locator('[data-resource-privilege="basic-rules"]').count(),1);
     assert.equal(await resources.locator('[data-resource-privilege="basic-rules"] [data-rule-action]').count(),3);
     assert.equal(await resources.locator('[data-ability-resource="free"]').count(),0,
      'Unlimited abilities are not placed in a fake free tracker');
     const actionSection=page.locator('[data-battle-action="others"]');
     assert.match(await actionSection.locator('summary.play-battle-summary').textContent(),/^Azioni$/);
     assert.equal(await actionSection.locator('[data-action-timing="action"] .play-battle-attack-entry').first().getAttribute('data-attack-id'),'attack');
     assert.equal(await actionSection.locator('[data-action-timing="reaction"] .play-battle-attack-entry').first().getAttribute('data-attack-id'),'opportunity');
     assert.equal(await page.locator('[data-battle-action="movement"]').count(),0);
     const movement=page.locator('[data-battle-action="others"]');
     await movement.locator('summary.play-battle-summary').click();
     const groups=movement.locator('.play-battle-action-group[data-action-timing]');
     assert(await groups.count()>0,'Movement has action-timing subsections');
     assert.equal(await movement.locator('.play-battle-action-group[data-action-timing][open]').count(),await groups.count(),
      'Opening an action category automatically opens every timing subsection');
     const group=groups.first();
     const styles=await group.locator('.play-battle-action-rows').evaluate(node=>({
      rail:getComputedStyle(node).borderLeftStyle,
      branch:getComputedStyle(node.querySelector('.play-battle-attack-entry'),'::before').content
     }));
     assert.equal(styles.rail,'none','Nested action lists use a minimal layout without an index rail');
     assert.equal(styles.branch,'none','Action rows have no index branches');
     await group.locator('summary.play-battle-action-heading').click();
     assert.equal(await group.getAttribute('open'),null,
      'A timing subsection may still be collapsed independently');
     await movement.locator('summary.play-battle-summary').click();
     await movement.locator('summary.play-battle-summary').click();
     assert.equal(await movement.locator('.play-battle-action-group[data-action-timing][open]').count(),await groups.count(),
      'Reopening a category re-expands all timing subsections');
     await expand.click();
     assert.equal(await page.locator('#sheet-play-view .play-battle-disclosure:not([open]), #sheet-play-view .play-battle-action-group:not([open])').count(),0);
     await collapse.click();
     assert.equal(await page.locator('#sheet-play-view .play-battle-disclosure[open], #sheet-play-view .play-battle-action-group[open]').count(),0);
    }
    const rangedAttack=page.locator('[data-battle-action="attacks"] [data-act="battle-attack-map"]').first();
    assert(await rangedAttack.count(),'Each computed weapon has a map range action');
    assert(await rangedAttack.getAttribute('aria-label'),'Map range action has an accessible label');
    // Cast stays at the far right of the spell row, not underneath its title.
    await page.locator('.play-battle-disclosure[data-battle-action="spells"]').evaluate(node=>{node.open=true;});
    await page.locator('[data-battle-action="spells"] .play-battle-action-group').evaluateAll(groups=>groups.forEach(node=>{node.open=true;}));
    const spellRows=await page.locator('[data-battle-action="spells"] .play-battle-spell-entry').evaluateAll(rows=>rows.map(row=>{
     const label=row.querySelector('.play-battle-spell-open').getBoundingClientRect();
     const cast=row.querySelector('.play-battle-spell-cast').getBoundingClientRect();
     const bounds=row.getBoundingClientRect();
     return {direction:getComputedStyle(row).flexDirection,height:bounds.height,
      labelCenter:label.top+label.height/2,castCenter:cast.top+cast.height/2,
      labelRight:label.right,castLeft:cast.left,castRight:cast.right,rowRight:bounds.right};
    }));
    assert.equal(spellRows.length,3,'The action, bonus and reaction spell rows must render');
    for(const row of spellRows){
     assert.equal(row.direction,'row','Spell buttons must share one horizontal line');
     assert(row.castLeft>=row.labelRight-1,'Cast control must sit to the right of the spell name');
     assert(Math.abs(row.castCenter-row.labelCenter)<=8,'Cast must be vertically centered with the spell');
     assert(row.castRight<=row.rowRight+1,'Cast must fit inside the spell box');
     assert(row.height<=56,'Spell row must remain compact (max 56px)');
    }
    if(width===390||width===1440)await page.screenshot({path:fileURLToPath(new URL('actions-'+width+'.png',artifacts))});
   }
   if(width===390&&['info','inventory'].includes(key))await page.screenshot({path:fileURLToPath(new URL('sheet-'+key+'-390.png',artifacts))});
  }
 }
 await page.setViewportSize({width:390,height:900});await section('battle');
 const showGeneral=async()=>{
  const filter=page.locator('#sheet-play-view [data-act="battle-toggle-class-only"]');
  if(await filter.getAttribute('aria-pressed')==='true')await filter.click();
  await page.locator('#sheet-play-view [data-battle-action="checks"]').waitFor();
 };
 const before=await page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return JSON.stringify((await listCreatures())[0].creature);});
 await page.getByRole('button',{name:'Varianti alle regole',exact:true}).click();
 assert.equal(await page.locator('.variant-list input[type=checkbox]').count(),78);
 await page.locator('[data-variant-search]').fill('Disarmare');
 await page.locator('input[value="disarm_dmg"]').check();await page.locator('[data-save-variants]').click();
 await page.locator('.variant-list').waitFor({state:'detached'});
 const after=await page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return JSON.stringify((await listCreatures())[0].creature);});
 const {action_variants_2014:oldVariants,...beforeRest}=JSON.parse(before);
 const {action_variants_2014:chosen,...afterRest}=JSON.parse(after);
 assert(chosen.includes('disarm_dmg'),'Variant selection is saved to this character');
 assert.deepEqual(afterRest,beforeRest,'Variant preferences do not change unrelated creature properties');
 await showGeneral();
 assert((await page.locator('#app').textContent()).includes('Disarmare'));
 await page.reload();await page.locator('[data-act="open"]').click();await section('battle');
 await showGeneral();
 assert((await page.locator('#app').textContent()).includes('Disarmare'),'Variant choice persists on reload');
 await page.locator('.play-battle-disclosure[data-battle-action="others"] > summary').click();
 assert.equal(await page.locator('[data-battle-action="others"] .play-battle-action-group:has([data-attack-id="stealth_movement"])').getAttribute('open'),'',
  'Stealth movement is visible automatically when its parent opens');
 await page.locator('[data-attack-id="stealth_movement"] [data-target="skill:stealth"]').click();
 await page.locator('#sheet-roll-dialog').waitFor();assert((await page.locator('#sheet-roll-dialog h2').textContent()).includes('Furtività'));
 await page.locator('[data-act="close-sheet-roll"]').click();
 await page.waitForFunction(()=> !!navigator.serviceWorker.controller);
 await context.setOffline(true);await page.reload();await page.locator('[data-act="open"]').click();await section('battle');
 await showGeneral();
 assert((await page.locator('#app').textContent()).includes('Movimento furtivo'));
 assert.deepEqual(errors,[]);assert.deepEqual(missing,[]);assert.deepEqual(writes,[]);
 console.log('PASS: 6 styled PWA sections at 360/390/768/1440px, compact groups without tree rails, three spell groups, native routes, stealth dice, persistent variants and offline reload');
}finally{await browser.close();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
