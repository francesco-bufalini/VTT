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
    assert.equal(await attacks.locator('[data-battle-basic="attacks"] [data-attack-id="unarmed"]').count(),1,
     'Unarmed belongs to the separate basic-attacks group');
    assert.equal(await attacks.locator('.play-action-origin-divider[aria-label="Attacchi di base"]').count(),1,
     'Basic attacks have the same visual separator as rule actions');
    const toolbar=page.locator('#sheet-play-view .play-battle-top-tools');
    assert.equal(await toolbar.count(),1,'Base visibility and equipment controls sit immediately above Attacchi');
    assert.equal(await attacks.locator('[data-sheet-context="equipment"]').count(),0,
     'The equipment shortcut is no longer inside the attack table');
    assert.equal(await toolbar.locator('[data-sheet-context="equipment"]').count(),1);
    const toggleBase=toolbar.locator('[data-act="battle-basics-toggle"]');
    assert.equal(await toggleBase.getAttribute('aria-pressed'),'true');
    assert.equal(await resources.locator('[data-attack-id="unarmed"]').count(),0,'Unarmed never appears in Risorse');
    assert.equal(await resources.locator('[data-rule-action],[data-action-benefit]').count(),0,
      'Resources contains no generic actions or benefit subgroups');
    assert.equal(await resources.locator('[data-resource-tracker="charge"]').count(),1);
    assert.equal(await resources.locator('[data-resource-privilege]').count(),0);
    assert.match(await actionSection.locator('summary.play-battle-summary').textContent(),/^Azioni$/);
    const ruleGroup=actionSection.locator('[data-action-source="rules"]');
    const privilegeGroup=actionSection.locator('.play-battle-privilege-rows[data-action-source="privileges"]');
    assert.equal(await ruleGroup.count(),1);
    assert.equal(await privilegeGroup.count(),1);
    assert.equal(await actionSection.locator('[data-action-benefit]').count(),0,
      'The Actions UI has no separate abilities/attack/other benefit categories');
    assert.equal(await ruleGroup.locator('[data-attack-id="attack"]').count(),1,
      'Ordinary Attack leads rule-defined actions unless a multiattack replaces it');
    assert.equal(await ruleGroup.locator('[data-attack-id="opportunity"]').count(),1);
    assert.equal(await ruleGroup.locator('[data-attack-id="two_weapon"]').count(),1);
    assert.equal(await ruleGroup.locator('[data-attack-id="opportunity"] .play-action-use-box, [data-attack-id="two_weapon"] .play-action-use-box').count(),0);
    assert.equal(await ruleGroup.locator('[data-act="battle-attack-map"],.play-battle-attack-range').count(),0,
      'Abstract actions show no weapon range or map controls');
    assert(await ruleGroup.getByText('Scattare').count()>0);
    assert.equal(await actionSection.locator('.play-action-origin-divider').count(),1,
      'A single origin line separates rule actions and granted actions');
    assert.deepEqual(await actionSection.locator('.play-battle-privilege-rows,[data-action-source="rules"]').evaluateAll(nodes=>
     nodes.map(node=>node.dataset.actionSource)),['privileges','rules'],
     'Privilege actions are above base actions');
    assert.equal(await actionSection.locator('.play-action-index-arrow,.play-action-list-parent-arrow').count(),0,
     'Indexed child actions no longer use direction arrows');
    if(width===390){
     const attackAction=ruleGroup.locator('[data-attack-id="attack"]');
     assert.equal(await attackAction.locator('.play-battle-attack-expanded').count(),0,
      'Actions with index children have no inline descriptions');
     await attackAction.locator('[data-act="sheet-context"]').click();
     const popup=page.locator('#sheet-context-dialog[open]');
     await popup.waitFor();
     assert.match(await popup.textContent(),/Descrizione.*(?:The most common action|Attaccare)/s,
      'Clicking the action opens the same detail dialog as capacities');
     await popup.locator('[data-act="sheet-context-close"]').click();
    }
    if(width===390){
     await toggleBase.click();
     assert.equal(await toggleBase.getAttribute('aria-pressed'),'false');
     assert.equal(await ruleGroup.isVisible(),false,'The toggle hides all rule-defined actions');
     assert.equal(await attacks.locator('[data-battle-basic="attacks"]').isVisible(),false,
      'The same toggle also hides basic attacks');
     assert.equal(await privilegeGroup.isVisible(),true,'Privilege actions remain visible');
     await section('magic');await section('battle');
     assert.equal(await toggleBase.getAttribute('aria-pressed'),'false',
      'Hidden base rows remain hidden after a sheet rerender');
     assert.equal(await ruleGroup.isVisible(),false);
     await toggleBase.click();
     assert.equal(await toggleBase.getAttribute('aria-pressed'),'true');
     assert.equal(await ruleGroup.isVisible(),true);
     assert.equal(await attacks.locator('[data-battle-basic="attacks"]').isVisible(),true);
     await toolbar.locator('[data-sheet-context="equipment"]').click();
     const equipmentPopup=page.locator('#sheet-context-dialog[open]');
     await equipmentPopup.waitFor();
     await equipmentPopup.locator('[data-act="sheet-context-close"]').click();
    }
    assert.equal(await privilegeGroup.locator('[data-ability-id],[data-attack-id]').count()>0,true);
    assert.equal(await ruleGroup.locator('[data-attack-id="attack"] .play-action-index-mode').textContent(),'tutte');
    const paid=privilegeGroup.locator('.play-resource-power-row,.play-battle-attack-entry').filter({hasText:'Capacità di prova'}).first();
    assert.equal(await paid.locator('button.play-action-use-box').count(),1);
    assert.match(await paid.locator('button.play-action-use-box').textContent(),/Cariche.*−1.*·.*2\/3/);
    assert.doesNotMatch(await paid.locator('button.play-action-use-box').textContent(),/Usa/);
    assert.match(await paid.locator('button.play-action-use-box').getAttribute('aria-label'),/Usa Capacità di prova/);
    assert.equal(await paid.locator('button.play-action-use-box .play-action-tracker-name').count(),1);
    const chipStyle=await paid.locator('.play-action-tracker-name').evaluate(node=>
     ({overflow:getComputedStyle(node).overflow,ellipsis:getComputedStyle(node).textOverflow}));
    assert.equal(chipStyle.overflow,'hidden');
    assert.equal(chipStyle.ellipsis,'ellipsis');
    assert.equal(await actionSection.locator('[data-action-timing]').count(),0,
      'Actions group by benefit, never by action timing');
    if(width===360){
     assert.equal(await actionSection.locator('.play-battle-action-group[data-action-benefit]').count(),0,
       'The unified list never reintroduces benefit-category disclosures');
    }
    assert.equal(await attacks.locator('.play-battle-attack-roll b').count(),0,
      'Roll buttons only contain the die; their modifiers remain in the adjacent formula');
    assert((await attacks.locator('.play-battle-attack-roll .action-dice').count())>0);
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
 const actionsDisclosure=page.locator('.play-battle-disclosure[data-battle-action="others"]');
 if(await actionsDisclosure.getAttribute('open')===null)await actionsDisclosure.locator(':scope > summary').click();
 assert.equal(await page.locator('[data-battle-action="others"] [data-action-source="rules"] [data-attack-id="stealth_movement"]').count(),1,
  'Stealth movement is visible within the rule-defined actions');
 await page.locator('[data-attack-id="stealth_movement"] [data-target="skill:stealth"]').click();
 await page.locator('#sheet-roll-dialog').waitFor();assert((await page.locator('#sheet-roll-dialog h2').textContent()).includes('Furtività'));
 await page.locator('[data-act="close-sheet-roll"]').click();
 await page.waitForFunction(()=> !!navigator.serviceWorker.controller);
 await context.setOffline(true);await page.reload();await page.locator('[data-act="open"]').click();await section('battle');
 assert((await page.locator('#app').textContent()).includes('Movimento furtivo'));
 assert.deepEqual(errors,[]);assert.deepEqual(missing,[]);assert.deepEqual(writes,[]);
 console.log('PASS: PWA battle layout at 360/390/768/1440px, always-visible actions, no duplicate spells, variants, stealth dice and offline reload');
}finally{await browser.close();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
