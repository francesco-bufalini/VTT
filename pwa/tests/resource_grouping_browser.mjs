import assert from 'node:assert/strict';
import {browserFixture} from './browser_fixture.mjs';
const f=await browserFixture();const {page,origin,sheet,shot}=f;
try{
 await page.goto(origin);await page.locator('[data-act="library-add"]').waitFor();
 await page.evaluate(async()=>{
  const {createCreature,saveCreature}=await import('/creatures.js');
  const saved=await createCreature('character','Resource grouping');
  const creator_id=saved.data.id;
  await saveCreature({...saved.data,class:'Artificer',class_source:'TCE',level:8,
   classes:[{name:'Artificer',source:'TCE',level:8,subclass:'Armorer',subclass_source:'TCE'}],
   abilities:{str:12,dex:14,con:14,int:18,wis:12,cha:10},
   temporary_hp:12,
   trait_state_selection:{armor_model:'armor_model:infiltrator'},
   resource_tracker_spent:{'feature:lightning_launcher:extra_damage':1},
   inventory:[{id:'armor',name:'Armor',type:'HA',ac:18,quantity:1,equipped_slots:['body']},
    {id:'heart',name:'Crystal',quantity:1,infusion:{id:'infusion|tce|homunculus servant',creator_id}},
    {id:'sword',name:'Sword',type:'M',damage:'1d8',quantity:1,equipped_slots:['main'],attuned:true,attuned_count:1,
     infusion:{id:'infusion|tce|radiant weapon',creator_id}}]
  },'default',saved.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('battle');
 const resources=page.locator('[data-battle-action="resources"]');
 if(!await resources.evaluate(n=>n.open))await resources.locator('summary.play-battle-summary').click();
 const extra=page.locator('#sheet-play-view [data-resource-tracker="feature:lightning_launcher:extra_damage"]');
 assert.equal(await extra.locator('[data-act="battle-use-ability"],[data-act="tracker-trait-use"]').count(),0);
 assert.match(await extra.innerText(),/1d6/);
 const launcher=page.locator('#sheet-play-view [data-resource-privilege]').filter({hasText:'Lightning Launcher'});
 assert.equal(await launcher.count(),1);
 const attack=launcher.locator('[data-act="battle-use-ability"]');
 assert.equal(await attack.count(),1);assert(await attack.isEnabled());
 await attack.click();
 await page.locator('#sheet-roll-dialog[open]').waitFor();
 assert.match(await page.locator('#sheet-roll-dialog').innerText(),/Lightning Launcher/);
 await page.keyboard.press('Escape');
 const servant=page.locator('#sheet-play-view [data-resource-privilege]').filter({hasText:'Comanda homunculus'});
 assert.equal(await servant.count(),1);
 assert.match(await servant.innerText(),/Azione bonus/);
 const before=await page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.resource_tracker_spent;});
 await servant.locator('[data-act="battle-use-ability"]').click();
 await page.locator('#other-ability-dialog[open]').waitFor();
 assert.equal(await page.locator('#other-ability-dialog [data-feature-companion]').count(),0,'Command does not summon another companion');
 const confirm=page.locator('#other-ability-dialog [data-ability-confirm]');
 await confirm.click();
 await page.locator('#other-ability-dialog').waitFor({state:'detached'});
 const after=await page.evaluate(async()=>{const {listCreatures}=await import('/creatures.js');return (await listCreatures())[0].creature.resource_tracker_spent;});
 assert.deepEqual(after,before,'Command does not consume any tracker');
 for(const width of [390,1440]){
  await page.setViewportSize({width,height:1000});
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  await page.locator('#sheet-play-view .play-health').scrollIntoViewIfNeeded();
  const hp=page.locator('#sheet-play-view .play-hp-reading'),temp=page.locator('#sheet-play-view .play-hp-temporary');
  const hpBox=await hp.boundingBox(),tempBox=await temp.boundingBox();
  assert(hpBox&&tempBox&&tempBox.x>hpBox.x&&Math.abs(tempBox.y-hpBox.y)<35);
  await shot('resource-grouping-'+width);
 }
 await sheet('magic');
 assert.equal(await page.locator('#sheet-play-view .play-infusion-card .infusion-power-row').count(),0);
 assert.equal(await page.locator('#sheet-play-view').getByText('Capacità degli oggetti infusi',{exact:true}).count(),0);
 // A command sourced from the same class trait as a summon must not reopen
 // the creature-creation controls or consume that trait's summoning resource.
 for(const config of [
  {name:'Bard',source:'PHB',subclass:'College of Creation',command:'Comanda oggetto animato',dialog:'other-ability-dialog',confirm:'data-ability-confirm'},
  {name:'Artificer',source:'TCE',subclass:'Battle Smith',command:"Comanda difensore d'acciaio",descriptive:true,dialog:'class-feature-dialog',confirm:'data-feature-confirm'}
 ]){
  await page.evaluate(async config=>{
   const {listCreatures,saveCreature}=await import('/creatures.js');
   const {calculateSheet,loadRuleCatalogs}=await import('/sheet_rules.js');
   const saved=(await listCreatures())[0];
   const creature={...saved.creature,class:config.name,class_source:config.source,
    classes:[{name:config.name,source:config.source,level:8,subclass:config.subclass,subclass_source:'TCE'}],
    inventory:[],trait_state_selection:{},resource_tracker_spent:{}};
   const computed=calculateSheet(creature,await loadRuleCatalogs());
   for(const tracker of computed.trackers)creature.resource_tracker_spent[tracker.id]=tracker.max;
   await saveCreature(creature,'default',saved.revision);
  },config);
  await page.reload();await page.locator('[data-act="open"]').click();await sheet('battle');
  const disclosure=page.locator('[data-battle-action="resources"]');
  if(!await disclosure.evaluate(n=>n.open))await disclosure.locator('summary.play-battle-summary').click();
  const free=page.locator('#sheet-play-view [data-resource-privilege]').filter({hasText:config.command});
  assert.equal(await free.count(),1);
  if(config.descriptive){
   assert.equal(await free.locator('[data-act="battle-use-ability"]').count(),0,
    'Preserve the descriptive-only command from concurrent main');
   await free.locator('[data-act="sheet-context"]').first().click();
   await page.locator('#sheet-context-dialog[open]').waitFor();
   assert.match(await page.locator('#sheet-context-dialog').innerText(),/Steel Defender|difensore/i);
   await page.locator('#sheet-context-dialog [data-act="sheet-context-close"]').first().click();
   continue;
  }
  await free.locator('[data-act="battle-use-ability"]').click();
  const dialog=page.locator('#'+config.dialog+'[open]');await dialog.waitFor();
  assert.equal(await dialog.locator('[data-feature-companion]').count(),0);
  await dialog.locator('['+config.confirm+']').click();
  await page.locator('#'+config.dialog).waitFor({state:'detached'});
  assert.equal(await page.evaluate(async()=>{
   const {listCreatures,listSubcreatures}=await import('/creatures.js');
   return (await listSubcreatures((await listCreatures())[0].creature.id)).length;
  }),0,'Issuing a command must not generate a creature');
 }
 assert.deepEqual(f.errors,[]);assert.deepEqual(f.missing,[]);assert.deepEqual(f.writes,[]);
 console.log('PASS: Chrome separates attack/extra damage, exposes free creator commands, and removes duplicate infused powers');
}finally{await f.close();}
