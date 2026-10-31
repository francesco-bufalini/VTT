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
    assert.equal(await page.locator('[data-act="battle-toggle-class-only"]').count(),0,
      'Class-only filtering was removed');
    const checks=page.locator('[data-battle-action="checks"]');
    assert.equal(await checks.count(),1);
    assert.equal(await checks.locator('[data-action-ability]').count(),6);
    assert.equal(await checks.locator('.play-battle-attack-entry').count(),24);
    assert.equal(await page.locator('.page-head [data-act="action-variants"]').count(),1);
    assert.equal(await page.locator('#sheet-navigation [data-sheet="actions"]').count(),0);
    assert.equal(await page.locator('[data-act="battle-expand-all"],[data-act="battle-collapse-all"]').count(),0,
      'Each Battle category controls its own expansion, without global toggles');
    if(width===360){
     const physical=page.locator('[data-battle-action="attacks"]');
     assert.match(await physical.locator('summary.play-battle-summary').textContent(),/^Attacchi$/);
     assert.equal(await physical.locator('[data-action-timing]').count(),0,'Attacks are not divided by action cost');
     assert.equal(await physical.locator('[data-attack-id="unarmed"]').count(),1,'Unarmed is always available');
     const resources=page.locator('[data-battle-action="resources"]');
      assert.notEqual(await resources.getAttribute('open'),null,'Risorse starts expanded by default');
     assert.equal(await resources.locator('[data-resource-privilege="basic-rules"]').count(),1);
     assert.equal(await resources.locator('[data-resource-privilege="basic-rules"] [data-rule-action]').count(),5);
     assert.equal(await resources.locator('[data-resource-privilege="basic-rules"] [data-rule-action="ability_checks"] .play-resource-power-open strong').textContent(),'Prova abilità');
     const expectedSkillGlyph=await page.evaluate(async()=>{
      const {actionGlyph}=await import('/action_economy.js');
      const node=document.createElement('div');node.innerHTML=actionGlyph('skill');
      return node.firstElementChild?.className;
     });
     const resourceSkillGlyph=resources.locator('[data-rule-action="ability_checks"] .vtt-action-glyph').first();
     assert.equal(await resourceSkillGlyph.getAttribute('class'),expectedSkillGlyph,
      'Prova abilità uses the exact same skill icon as Info → Competenze → Abilità');
     if(await resources.getAttribute('open')===null)
      await resources.locator(':scope > summary.play-battle-summary').click();
     const attackGlyph=resources.locator('[data-resource-privilege="basic-rules"] [data-rule-action="attack"] .vtt-action-glyph').first();
     const otherGlyph=resources.locator('[data-resource-privilege="basic-rules"] [data-rule-action="spell_cast"] .vtt-action-glyph').first();
     const x=await attackGlyph.evaluate(node=>node.getBoundingClientRect().left);
     const otherX=await otherGlyph.evaluate(node=>node.getBoundingClientRect().left);
     assert(Math.abs(x-otherX)<2,'Multiattack action icon aligns with neighboring resource rows');
     assert.equal(await resources.locator('[data-resource-privilege="basic-rules"] [data-rule-action="attack"] .play-resource-power-open strong').textContent(),'Azione di attacco');
     assert.equal(await resources.locator('[data-resource-privilege="basic-rules"] [data-rule-action="spell_cast"] small').textContent(),'Slot');
     assert.equal(await resources.locator('[data-ability-resource="free"]').count(),0,
      'Unlimited abilities are not placed in a fake free tracker');
     const actionSection=page.locator('[data-battle-action="others"]');
     assert.match(await actionSection.locator('summary.play-battle-summary').textContent(),/^Azioni$/);
     // The standard theme has nested, tinted panels. Keep the original
     // background gradients on table shells and rows instead of flattening them.
     const naturalSurfaces=await actionSection.evaluate(panel=>{
      const card=panel.closest('.play-card'),heading=panel.querySelector('.play-battle-action-heading'),
       entry=panel.querySelector('.play-battle-attack-entry');
      return [card,heading,entry].map(node=>({
       color:getComputedStyle(node).backgroundColor,
       image:getComputedStyle(node).backgroundImage
      }));
     });
     assert(naturalSurfaces.every(surface=>surface.image!=='none'),
      'Original panel, heading and action-row gradients must be restored');
     assert(naturalSurfaces.every(surface=>surface.color!=='rgb(0, 0, 0)'),
      'The old flat-black experiment must remain disabled');
     assert.equal(await actionSection.locator('[data-action-timing="action"] .play-battle-attack-entry').first().getAttribute('data-attack-id'),'attack');
     assert.equal(await actionSection.locator('[data-action-timing="reaction"] .play-battle-attack-entry').first().getAttribute('data-attack-id'),'opportunity');
     assert.equal(await page.locator('[data-battle-action="movement"]').count(),0);
     assert.equal(await actionSection.locator('[data-attack-id="two_weapon"]').count(),1,
      'Secondary attack always remains in Azioni');
     const secondary=actionSection.locator('[data-attack-id="two_weapon"]');
     const unavailable=await secondary.locator('.play-battle-unavailable-reason').count();
     if(unavailable)assert.match(await secondary.locator('.play-battle-unavailable-reason').textContent(),/\S/,
      'Unavailable secondary attacks explain their unmet requirement');
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
     assert.equal(await movement.getAttribute('open'),'','A reopened category remains expanded');
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
 const checksLink=resourcesPanel.locator('[data-resource-privilege="basic-rules"] [data-rule-action="ability_checks"] button');
 await checksLink.click();
 const checksSection=page.locator('#sheet-play-view [data-battle-action="checks"]');
 assert.equal(await checksSection.getAttribute('open'),'','Checks jump expands its destination section');
 assert.equal(await checksSection.locator('[data-action-ability][open]').count(),6,
  'Checks jump expands all six ability groups');
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
