import assert from 'node:assert/strict';
import {browserFixture} from './browser_fixture.mjs';
const f=await browserFixture(),{page,origin,sheet,popup,dismiss,shot}=f;
const record=()=>page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures()).find(r=>r.creature.kind==='character').creature;});
const waitForm=id=>page.waitForFunction(async id=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures()).find(r=>r.creature.kind==='character').creature.current_form_id===id;},id);
const forms=async()=>{await page.locator('[data-act="creature-variants"]').click();await page.locator('#creature-variants-dialog[open]').waitFor();};
const closeForms=async()=>{await page.locator('[data-act="variant-close"]').click();await page.locator('#creature-variants-dialog').waitFor({state:'detached'});};
const create=async(name,preset)=>{await page.locator('[data-variant-new]').click();await page.locator('[data-variant-name]').fill(name);await page.locator('[data-variant-preset]').selectOption(preset);};
try{
 await page.route('**/catalog/bestiary.json',route=>route.fulfill({contentType:'application/json',body:JSON.stringify({version:1,monsters:[]})}));
 await page.goto(origin);await page.locator('[data-act="library-add"]').waitFor();
 await page.evaluate(async()=>{
  const {createCreature,saveCreature}=await import('/creatures.js');
  const saved=await createCreature('character','Lyria base');
  await saveCreature({...saved.data,current_hp:30,max_hp_base:40,temporary_hp:0,default_miniature_id:'ape',current_miniature_id:'ape'},'default',saved.revision);
  const wolf=await createCreature('monster','Lupo di prova');
  await saveCreature({...wolf.data,current_hp:11,max_hp_base:11,abilities:{str:16,dex:14,con:12,int:3,wis:12,cha:6},stat_block:{name:'Wolf',source:'MM',type:'beast',cr:'1/4'},default_miniature_id:'wolf',current_miniature_id:'wolf'},'default',wolf.revision);
 });
 await page.reload();await page.getByRole('button',{name:'Apri scheda di Lyria base',exact:true}).click();await page.locator('#sheet-play-view').waitFor();
 assert.equal(await page.locator('.topbar #creature-forms:visible').count(),1);assert.equal(await page.locator('#app [data-act="creature-variants"],.variant-bar').count(),0);
 await forms();await create('Identità segreta','alias');await page.locator('[data-variant-save]').click();
 await page.locator('.variant-list article').filter({hasText:'Identità segreta'}).getByRole('button',{name:'Usa forma'}).click();
 await closeForms();await popup('identity');
 await page.locator('#sheet-context-dialog [data-identity-value="names"]').fill('Ombra');await dismiss();
 await page.waitForFunction(()=>document.querySelector('#creature-name')?.textContent==='Ombra');
 let c=await record();const aliasId=c.current_form_id;assert.equal(c.name,'Lyria base');assert.equal(c.variants[0].values.name,'Ombra');
 assert.equal(await page.locator('#sheet-play-view .play-identity [data-read-field="name"]').textContent(),'Ombra');
 await forms();assert(await page.locator('#creature-variants-dialog .variant-list article').count());assert.match(await page.locator('.variant-list [aria-current="true"] .variant-copy small').textContent(),/Alias/);
 await page.locator('[data-variant-edit="'+aliasId+'"]').click();await page.locator('[data-variant-name]').fill('Ombra della luna');await page.locator('[data-variant-save]').click();await closeForms();
 await page.waitForFunction(()=>document.querySelector('#creature-name')?.textContent==='Ombra della luna');
 assert.equal(await page.locator('#sheet-play-view .play-identity [data-read-field="name"]').textContent(),'Ombra della luna');
 for(const tab of ['battle','magic','inventory','info']){await sheet(tab);assert.equal(await page.locator('#creature-name').textContent(),'Ombra della luna');assert.equal(await page.locator('#app [data-act="creature-variants"],.variant-bar').count(),0);}
 await page.locator('#creature-back').click();await page.getByRole('button',{name:'Apri scheda di Lyria base',exact:true}).waitFor();assert.equal(await page.locator('#creature-forms:visible').count(),0);
 await page.getByRole('button',{name:'Apri scheda di Lyria base',exact:true}).click();await page.locator('#sheet-play-view').waitFor();

 await sheet('battle');await page.locator('#sheet-play-view [data-act="hp-damage"]').click();await page.locator('#hp-adjust-amount').fill('5');await page.locator('#hp-adjust-confirm').click();
 await page.waitForFunction(()=>document.querySelector('[data-read-field="current_hp"]')?.textContent==='25');assert.equal((await record()).current_hp,25);
 await forms();await create('Lupo','custom');
 await page.locator('[data-variant-section="hp"]').check();await page.locator('[data-variant-section="str"]').check();
 await page.locator('[data-variant-load]').click();await page.locator('[data-variant-source-key]').filter({hasText:'Lupo di prova'}).click();
 await page.locator('[data-variant-import]').click();await page.locator('[data-variant-save]').click();
 await page.locator('.variant-list article').filter({hasText:'Lupo'}).getByRole('button',{name:'Usa forma'}).click();await closeForms();
 const wolfId=(await record()).current_form_id;
 await page.waitForFunction(()=>document.querySelector('[data-read-field="current_hp"]')?.textContent==='11');
 await page.locator('#sheet-play-view [data-act="hp-damage"]').click();await page.locator('#hp-adjust-amount').fill('15');await page.locator('#hp-adjust-confirm').click();
 await page.locator('#form-depleted-dialog[open]').waitFor();assert.equal((await record()).current_hp,25);
 assert((await page.locator('#form-depleted-dialog').textContent()).includes('4 danni'));
 await page.locator('[data-form-keep]').click();assert.equal((await record()).current_form_id,wolfId);
 await popup('hp');await page.locator('#sheet-context-dialog [data-field="current_hp"]').fill('7');await dismiss();
 await page.locator('#sheet-play-view [data-act="hp-damage"]').click();await page.locator('#hp-adjust-amount').fill('10');await page.locator('#hp-adjust-confirm').click();await page.locator('#form-depleted-dialog[open]').waitFor();
 await page.locator('[data-form-restore]').click();await waitForm('');assert.equal((await record()).current_hp,22);
 await forms();await page.locator('[data-variant-switch="'+aliasId+'"]').click();await closeForms();
 assert.equal(await page.locator('#creature-name').textContent(),'Ombra della luna');
 await page.reload();await page.getByRole('button',{name:'Apri scheda di Lyria base',exact:true}).click();await page.locator('#sheet-play-view').waitFor();
 assert.equal(await page.locator('#creature-name').textContent(),'Ombra della luna');assert.equal((await record()).variants.length,2);
 await forms();assert(await page.locator('[data-variant-new]').evaluate(n=>n.getBoundingClientRect().height<=64));assert(await page.locator('#creature-variants-dialog .vtt-action-glyph').evaluateAll(nodes=>nodes.every(n=>n.getBoundingClientRect().width<=32)));await shot('creature-variants-list');await page.locator('[data-variant-edit="'+wolfId+'"]').click();
 for(const width of [360,390,768,1440]){
  await page.setViewportSize({width,height:950});
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Horizontal layout at '+width);
  assert(await page.locator('#creature-variants-dialog').evaluate(n=>n.scrollWidth<=n.clientWidth+1),'Dialog layout at '+width);
  const small=await page.locator('#creature-variants-dialog button').evaluateAll(ns=>ns.filter(n=>n.getBoundingClientRect().height>0&&n.getBoundingClientRect().height<47).map(n=>n.textContent));assert.deepEqual(small,[]);
 }
 await page.setViewportSize({width:390,height:950});await shot('creature-variants');
 await closeForms();
 await page.evaluate(async()=>{
  const {listCreatures,openCreatureEditor}=await import('/creatures.js');
  const c=(await listCreatures()).find(r=>r.creature.kind==='character').creature,editor=await openCreatureEditor(c.id);
  await editor.update({current_form_id:''});
  await editor.update({class:'Druid',class_source:'PHB',level:5,classes:[{name:'Druid',source:'PHB',level:5}],resource_tracker_spent:{},current_hp:22});await editor.flush();
 });
 await page.reload();await page.getByRole('button',{name:'Apri scheda di Lyria base',exact:true}).click();await sheet('battle');
 const resources=page.locator('[data-battle-action="resources"]');if(!await resources.evaluate(n=>n.open))await resources.locator(':scope > summary.play-battle-summary').click();
 await page.locator('[data-act="battle-use-ability"]').filter({hasText:/Attiva/}).first().click();
 await page.locator('[data-miniature-search]').fill('wolf');await page.locator('[data-miniature-id="wolf"]').click();
 assert.deepEqual((await record()).resource_tracker_spent,{});
 await page.locator('[data-form-hp]').fill('11');await page.locator('[data-form-confirm]').click();await page.locator('.miniature-dialog').waitFor({state:'detached'});
 c=await record();assert.equal(c.current_hp,22);assert.equal(c.variants.find(v=>v.id===c.current_form_id).values.current_hp,11);assert.equal(Object.values(c.resource_tracker_spent)[0],1);
 await page.locator('#sheet-play-view [data-act="hp-damage"]').click();await page.locator('#hp-adjust-amount').fill('15');await page.locator('#hp-adjust-confirm').click();await page.locator('#form-depleted-dialog[open]').waitFor();
 assert.equal((await record()).current_hp,22);await page.locator('[data-form-restore]').click();await waitForm('');assert.equal((await record()).current_hp,18);assert.equal(Object.values((await record()).resource_tracker_spent)[0],1);
 assert.deepEqual(f.errors,[]);assert.equal(f.writes.length,0);
 console.log('PASS: Chrome variants, normal alias editing, shared damage, bestiary section import, independent HP, both overflow decisions, reload and responsive 360/390/768/1440 layouts.');
}finally{await f.close();}
