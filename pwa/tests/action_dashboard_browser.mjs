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
  const revision='a'.repeat(40);
  if(path==='/__vtt_version'){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({revision}));return;}
  if(path==='/sw.js'){res.setHeader('Content-Type','text/javascript; charset=utf-8');res.end((await readFile(new URL('pwa/sw.js',root),'utf8')).replaceAll('__VTT_COMMIT_SHA__',revision));return;}
  if(path.startsWith('/api/')){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({protocol:1,desktop_online:false}));return;}
  if(path==='/catalog/spells/selected'&&req.method==='POST'){
   for await(const _chunk of req){} // No known spells in this isolated fixture.
   res.setHeader('Content-Type','application/json');res.end(JSON.stringify({version:1,spells:[]}));return;
  }
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
  await saveCreature({...saved.data,class:'Rogue',class_source:'PHB',level:2,xp:300,rules_version:'2014',abilities:{str:12,dex:16,con:14,int:12,wis:14,cha:10},
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
    assert.equal(await page.locator('[data-act="battle-toggle-class-only"]').count(),0,
      'Class-only filtering was removed');
    const checks=page.locator('[data-battle-action="checks"]');
    assert.equal(await checks.count(),1);
    assert.equal(await checks.locator('[data-action-ability]').count(),6);
    assert.equal(await checks.locator('.play-battle-attack-entry').count(),24);
    assert.equal(await page.locator('.page-head [data-act="action-variants"]').count(),1);
    assert.equal(await page.locator('#sheet-navigation [data-sheet="actions"]').count(),0);
    // The old global expand/collapse buttons were removed: independently
    // expandable action groups are the current Battle navigation.
    assert.equal(await page.locator('[data-act="battle-expand-all"],[data-act="battle-collapse-all"]').count(),0);
    const resources=page.locator('[data-battle-action="resources"]');
    const actionSection=page.locator('[data-battle-action="others"]');
    const attacks=page.locator('[data-battle-action="attacks"]');
    assert(await resources.locator(':scope > summary').isVisible(),'Resources keeps its counter list');
    assert.equal(await attacks.count(),1,'Attacchi is restored as a separate table');
    assert.equal(await attacks.locator('[data-attack-id="unarmed"]').count(),1,'Unarmed is in Attacchi');
    assert.equal(await resources.locator('[data-attack-id="unarmed"]').count(),0,'Unarmed never appears in Risorse');
    assert.equal(await resources.locator('[data-rule-action],[data-action-benefit]').count(),0,
      'Resources contains no generic actions or benefit subgroups');
    assert.equal(await resources.locator('[data-resource-tracker="charge"]').count(),1);
    assert.equal(await resources.locator('[data-resource-privilege]').count(),0);
    assert.match(await actionSection.locator('summary.play-battle-summary').textContent(),/^Azioni$/);
    const attackGroup=actionSection.locator('[data-action-benefit="attacks"]');
    const abilityGroup=actionSection.locator('[data-action-benefit="abilities"]');
    const otherGroup=actionSection.locator('[data-action-benefit="other"]');
    assert.equal(await attackGroup.count(),1);
    assert.equal(await abilityGroup.count(),1);
    assert.equal(await otherGroup.count(),1);
    assert.equal(await attackGroup.locator('[data-attack-id="attack"]').count(),0,
      'The default Attack action is not listed as an attack-granting capability');
    assert.equal(await attackGroup.locator('[data-act="battle-attack-map"],.play-battle-attack-range').count(),0,
      'Attack actions cannot show weapon range or map controls');
    assert.equal(await attackGroup.locator('.play-attack-action-cost').count()>0,true,
      'Each attack-granting action shows its action-economy cost');
    assert.equal(await attackGroup.locator('[data-attack-id="opportunity"]').count(),1);
    assert.equal(await attackGroup.locator('[data-attack-id="two_weapon"]').count(),1);
    assert(await otherGroup.getByText('Scattare').count()>0);
    assert.equal(await abilityGroup.locator('[data-ability-id],[data-attack-id]').count()>0,true);
    const paid=abilityGroup.locator('.play-resource-power-row,.play-battle-attack-entry').filter({hasText:'Capacità di prova'}).first();
    assert.equal(await paid.locator('.play-action-tracker').count(),1);
    assert.match(await paid.locator('.play-action-tracker').textContent(),/Cariche.*2\/3/);
    const chipStyle=await paid.locator('.play-action-tracker-name').evaluate(node=>
     ({overflow:getComputedStyle(node).overflow,ellipsis:getComputedStyle(node).textOverflow}));
    assert.equal(chipStyle.overflow,'hidden');
    assert.equal(chipStyle.ellipsis,'ellipsis');
    assert.equal(await actionSection.locator('[data-action-timing]').count(),0,
      'Actions group by benefit, never by action timing');
    if(width===360){
     const groups=actionSection.locator('.play-battle-action-group[data-action-benefit]');
     assert.equal(await groups.count(),await actionSection.locator('.play-battle-action-group[open]').count(),
       'Benefit groups start expanded');
     const first=groups.first();await first.locator(':scope > summary').click();
     assert.equal(await first.getAttribute('open'),null);
     await first.locator(':scope > summary').click();
     assert.notEqual(await first.getAttribute('open'),null);
    }
    const rangedAttack=page.locator('[data-battle-action="attacks"] [data-act="battle-attack-map"]').first();
    assert(await rangedAttack.count(),'Each computed weapon has a map range action');
    assert(await rangedAttack.getAttribute('aria-label'),'Map range action has an accessible label');
    assert.equal(await page.locator('[data-battle-action="spells"]').count(),0,
      'Battle no longer renders a second spell list');
    if(width===390||width===1440)await page.screenshot({path:fileURLToPath(new URL('actions-'+width+'.png',artifacts))});
   }
   if(width===390&&['info','inventory'].includes(key))await page.screenshot({path:fileURLToPath(new URL('sheet-'+key+'-390.png',artifacts))});
  }
 }
 await page.setViewportSize({width:390,height:900});await section('battle');
 const resourcesPanel=page.locator('#sheet-play-view [data-battle-action="resources"]');
 if(await resourcesPanel.getAttribute('open')===null)
  await resourcesPanel.locator(':scope > summary.play-battle-summary').click();
 const checksSection=page.locator('#sheet-play-view [data-battle-action="checks"]');
 if(await checksSection.getAttribute('open')===null)await checksSection.locator(':scope > summary').click();
 assert.equal(await checksSection.getAttribute('open'),'','Checks disclosure remains available independently');
 for(const group of await checksSection.locator('[data-action-ability]').all())
  if(await group.getAttribute('open')===null)await group.locator(':scope > summary').click();
 assert.equal(await checksSection.locator('[data-action-ability][open]').count(),6);
 await section('magic');await section('battle');
 assert.equal(await checksSection.getAttribute('open'),'','Expanded checks survive sheet rerender');
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
 assert((await page.locator('#app').textContent()).includes('Disarmare'));
 await page.reload();await page.locator('[data-act="open"]').click();await section('battle');
 assert((await page.locator('#app').textContent()).includes('Disarmare'),'Variant choice persists on reload');
 await page.locator('.play-battle-disclosure[data-battle-action="others"] > summary').click();
 assert.equal(await page.locator('[data-battle-action="others"] .play-battle-action-group:has([data-attack-id="stealth_movement"])').getAttribute('open'),'',
  'Stealth movement is visible automatically when its parent opens');
 await page.locator('[data-attack-id="stealth_movement"] [data-target="skill:stealth"]').click();
 await page.locator('#sheet-roll-dialog').waitFor();assert((await page.locator('#sheet-roll-dialog h2').textContent()).includes('Furtività'));
 await page.locator('[data-act="close-sheet-roll"]').click();
 await page.waitForFunction(()=> !!navigator.serviceWorker.controller);
 await context.setOffline(true);await page.reload();await page.locator('[data-act="open"]').click();await section('battle');
 assert((await page.locator('#app').textContent()).includes('Movimento furtivo'));
 assert.deepEqual(errors,[]);assert.deepEqual(missing,[]);assert.deepEqual(writes,[]);
 console.log('PASS: PWA battle layout at 360/390/768/1440px, always-visible actions, no duplicate spells, variants, stealth dice and offline reload');
}finally{await browser.close();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
