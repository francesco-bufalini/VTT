import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,existsSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import {sessionSpellEntries} from '../spell_selection.js';
import {actionEntries as project,actionEconomyView as view,groupActionEntries,topSkillEntries,spellActionEntries,nativeClassFeatureActions,loadGeneralActionSupplements,actionVariants} from '../action_economy.js';
const catalog=JSON.parse(readFileSync(new URL('../../vtt/data/combat_actions_5etools.json',import.meta.url),'utf8'));
const featureRules=JSON.parse(readFileSync(new URL('../../vtt/data/feature_timing_recovery_rules.json',import.meta.url),'utf8'));
const actionEntries=(record={},calculated={},spells=[],overrides=[],rules=catalog.actions,enabled=[])=>project(record,{feature_rules:featureRules,...calculated},spells,overrides,rules,enabled);
const actionEconomyView=(record={},calculated={},spells=[],overrides=[],rules=catalog.actions,enabled=[])=>view(record,{feature_rules:featureRules,...calculated},spells,overrides,rules,enabled);
const find=(rows,id)=>rows.find(row=>row.id===id);
const doc=html=>new JSDOM(html).window.document;

test('source catalogue keeps editions distinct and optional rules opt-in',()=>{
 const old=actionEntries({rules_version:'2014'}),modern=actionEntries({rules_version:'2024'});
 assert(find(old,'use_object'));assert(!find(old,'study'));assert(find(modern,'study'));assert(find(modern,'influence'));
 assert(find(old,'dash').description.startsWith('When you take the Dash action'));
 assert(!find(old,'disarm'));
 const enabled=actionEntries({}, {},[],[],catalog.actions,['disarm_dmg','overrun_dmg','tumble_dmg']);
 assert.equal(find(enabled,'disarm').parent_action,'attack');
 for(const id of ['overrun','tumble']){
  assert.equal(enabled.filter(row=>row.id===id).length,1);
  assert.equal(find(enabled,id).time,'bonus');assert(find(enabled,id).alternate_action);
 }
 assert(!find(actionEntries({rules_version:'2024'}, {},[],[],catalog.actions,['disarm_dmg']),'disarm'));
});

test('Cunning Action moves only granted actions to bonus without duplicates',()=>{
 const entries=actionEntries({rules_version:'2014',class:'Rogue',class_source:'PHB',level:2});
 for(const id of ['dash','disengage','hide']){
  assert.equal(entries.filter(row=>row.id===id).length,1);
  assert.equal(find(entries,id).time,'bonus');assert(find(entries,id).alternate_action);
 }
 assert.equal(find(entries,'search').time,'action');
 const mixed=actionEntries({action_grants:[{id:'mixed',name:'Capacità',action_type:[{unit:'action'},{unit:'bonus'}]}]});
 assert.equal(find(mixed,'mixed').time,'bonus');assert(find(mixed,'mixed').alternate_action);
});

test('nested weapon attacks, action checks and movement preserve stable dice targets',()=>{
 const calculated={attacks:[{id:'item:main',name:'Spada',hit:5,damage:'1d6'},
  {id:'item:off:dagger',name:'Pugnale',hit:5,offhand_bonus:true,damage:'1d4'}],skills:{stealth:7,perception:5,athletics:4,arcana:3}};
 const roots=groupActionEntries(actionEntries({},calculated));
 assert(find(roots,'attack').children.some(row=>row.id==='item:main'));
 assert(find(roots,'attack').children.some(row=>row.id==='grapple'));
 assert(find(roots,'two_weapon').children.some(row=>row.id==='item:off:dagger'));
 const checks=find(roots,'ability_checks').children;
 assert(find(checks,'hide'));assert(find(checks,'search'));assert(!find(checks,'grapple'));
 assert(find(find(roots,'movement_options_movement').children,'stealth_movement'));
 assert(find(find(roots,'movement_options_action').children,'dash'));
 const html=actionEconomyView({},calculated),document=doc(html);
 assert.equal(document.querySelectorAll('.action-economy-section').length,5);
 assert(document.querySelector('.action-tree ol li [data-target="attack_hit:item:off:dagger"]'));
 assert(document.querySelector('[data-timing="action"] .action-economy-skills [data-target="skill:stealth"]'));
 assert(!document.querySelector('[data-timing="free"] .action-economy-skills'));
 const skillChecks=document.querySelector('[data-timing="action"] .action-economy-row:has(.action-group-label strong)');
 assert(skillChecks && skillChecks.nextElementSibling?.classList.contains("action-economy-skills"),
  "Quick rolls follow the action skill-checks group");
 assert(document.querySelector('.action-dice'));
});

test('bonus movement is grouped independently and keeps alternate-cost marker by title',()=>{
 const document=doc(actionEconomyView({class:'Rogue',class_source:'PHB',level:2},{skills:{stealth:6}}));
 const bonus=document.querySelector('[data-timing="bonus"]');
 assert(bonus.textContent.includes('Spostamento'));
 assert(bonus.querySelector('.action-tree').textContent.includes('Scattare'));
 const marker=bonus.querySelector('.action-alternate');
 assert.equal(marker.previousElementSibling.tagName,'STRONG');
 assert(marker.nextElementSibling.classList.contains('action-economy-chevron'));
});

test('base projection stays separate from conditional spell groups and resource counters',()=>{
 const record={prepared_spells:['spell_a'],action_grants:[{name:'Ispirazione',action_type:'bonus',tracker_id:'bardic'}]};
 const calculated={trackers:[{id:'bardic',name:'Ispirazione bardica',max:3,spent:1}],origin_spells:[{spell_id:'spell_a',tracker_id:'bardic'}]};
 const spells=[{id:'spell_a',name:'Fulmine',level:3,time:'action',entries:['Raggio']}];
 const rows=actionEntries(record,calculated,spells),html=actionEconomyView(record,calculated,spells);
 assert(!rows.some(row=>row.type==='Incantesimo'||row.name==='Fulmine'||row.name==='Lanciare un incantesimo'));
 assert(html.includes('Incantesimi disponibili'));assert(!html.includes('action-open-spells'));
 assert(html.includes('data-spell-id="spell_a"'));
 assert(html.includes('data-act="tracker-more" data-tracker-id="bardic"'));
 assert(html.includes('data-act="tracker-less" data-tracker-id="bardic"'));assert(html.includes('2 / 3'));
});

test('passive traits stay excluded, escaping and descriptions remain safe',()=>{
 const record={action_grants:[{name:'<script>',action_type:'action',description:'<b>Hello</b>'}],selected_features:[{name:'Passive Armor',entries:['passive']}]};
 const rows=actionEntries(record),html=actionEconomyView(record);
 assert(!rows.some(row=>row.name==='Passive Armor'));
 assert(html.includes('&lt;script&gt;'));assert(!html.includes('<script>'));assert(html.includes('&lt;b&gt;Hello&lt;/b&gt;'));
 assert(html.includes('https://5e.tools/actions.html#'));
 assert.deepEqual(topSkillEntries({skills:{stealth:8,arcana:8,perception:5,athletics:4,acrobatics:2}}).map(row=>row.bonus),[8,8,5,4]);
});

test('all 98 generated golden icons are shared, discoverable and cached offline',()=>{
 const manifest=JSON.parse(readFileSync(new URL('../icons/gold_generated/manifest.json',import.meta.url),'utf8'));
 assert.equal(manifest.groups.length,4);
 const keys=manifest.groups.flatMap(group=>group.keys);
 assert.equal(keys.length,98);
 assert.equal(new Set(keys).size,98);
 for(const key of ['grapple','prone_alt','wild_shape','bardic_inspiration','spell_cast','break_concentration',
                    'stealth_check','athletics','reaction_trigger','flight','weapon']){
   assert(keys.includes(key),'Missing generated glyph '+key);
 }
 const css=readFileSync(new URL('../styles.css',import.meta.url),'utf8');
 const js=readFileSync(new URL('../action_economy.js',import.meta.url),'utf8');
 const worker=readFileSync(new URL('../sw.js',import.meta.url),'utf8');
 const hostURL=new URL('../../network/pwa_host.gd',import.meta.url);
 const host=existsSync(hostURL)?readFileSync(hostURL,'utf8'):null;
 const nativeURL=new URL('../../vtt/creature_sheet_style.gd',import.meta.url);
 const native=existsSync(nativeURL)?readFileSync(nativeURL,'utf8'):null;
 for(const [index,group] of manifest.groups.entries()){
   const path='/icons/gold_generated/'+group.name;
   const svg=readFileSync(new URL('../icons/gold_generated/'+group.name,import.meta.url),'utf8');
   assert(svg.startsWith('<svg ')&&svg.includes('</svg>'));
   assert(svg.includes('linearGradient id="gold"')&&svg.includes('linearGradient id="rose"'));
   assert.equal(svg.split('<g transform="translate(').length-1,group.count);
   assert(css.includes(path),'CSS references missing image '+path);
   assert(js.includes('vtt-action-glyph--pack-'));
   assert(worker.includes('"'+path+'"'),'PWA offline shell must cache '+path);
   if(host!==null)assert(host.includes('"'+path+'"'),'Native PWA host must serve '+path);
   if(native!==null)assert(native.includes('res://pwa'+path),'Godot must use '+path);
 }
 const html=actionEconomyView({
    rules_version:'2014',
    action_grants:[
      {name:'Forma selvatica',action_type:'bonus'},
      {name:'Ispirazione bardica',action_type:'bonus'},
      {name:'Afferrare una creatura',action_type:'action'},
      {name:'Mandare prono',action_type:'action'}]
 },{skills:{athletics:6,stealth:5,arcana:4,perception:3}});
 assert(html.includes('vtt-action-glyph--pack-0'));
 assert(html.includes('vtt-action-glyph--pack-1'));
 assert(html.includes('vtt-action-glyph--pack-2'));
 assert(html.includes('vtt-action-glyph--pack-3'));
 assert(!html.includes('>⚔<'));
 assert(html.includes('data-target="skill:athletics"'));
});

test('multiclass spell groups preserve independent casting class choices',()=>{
 const wizard='class|phb|wizard',warlock='class|phb|warlock';
 const spell={id:'shield',name:'Shield',level:1,
  casting_classes:[wizard,warlock]};
 const record={prepared_spells:[spell],spells:[spell]};
 const calculated={casting_classes:[
  {id:wizard,name:'Wizard',ability:'int'},
  {id:warlock,name:'Warlock',ability:'cha'}
 ],origin_spells:[],trackers:[]};
 const catalog=[{id:'shield',name:'Shield',level:1,classes:['Wizard','Warlock'],
   time:[{unit:'reaction',number:1}],entries:['Protezione']}];
 const choices=sessionSpellEntries(record,calculated,catalog).filter(row=>row.id==='shield');
 assert.equal(choices.length,2);
 assert.deepEqual(choices.map(row=>row.casting_class),[wizard,warlock]);
 assert.equal(actionEntries(record,calculated,catalog).filter(row=>row.spell_id==='shield').length,0);
 const markup=actionEconomyView(record,calculated,catalog);
 assert.equal((markup.match(/data-spell-id="shield"/g)||[]).length,2);
 assert(markup.includes('data-casting-class="'+wizard+'"'));assert(markup.includes('data-casting-class="'+warlock+'"'));
});

test('only nonempty action, bonus and reaction spell groups appear with the actual payment',()=>{
 const make=(id,unit)=>({id,name:id,level:1,time:[{unit,number:1}],entries:['Testo di prova']});
 const record={prepared_spells:[make('action','action'),make('bonus','bonus'),make('reaction','reaction'),make('slow','minute')],spellbook_spells:[make('book','action')]};
 const document=doc(actionEconomyView(record));
 assert.equal(document.querySelectorAll('.action-tree').length>0,true);
 for(const key of ['action','bonus','reaction']){
  const section=document.querySelector('[data-timing="'+key+'"]');
  assert(section.textContent.includes('Incantesimi disponibili'));
  assert(section.querySelector('[data-spell-id="'+key+'"]'));
  assert(section.textContent.includes('Slot · liv. 1+'));
 }
 assert(!document.querySelector('[data-spell-id="slow"]'));assert(!document.querySelector('[data-spell-id="book"]'));
 assert(!actionEconomyView({}).includes('Incantesimi disponibili'));
 const rows=spellActionEntries({}, {origin_spells:[{id:'grant',spell_id:'reaction',payment_mode:'tracker',tracker_id:'wand'}],trackers:[{id:'wand',name:'Cariche',max:3}]},[make('reaction','reaction')]);
 assert.equal(rows.length,1);assert.equal(rows[0].tracker_id,'wand');assert.equal(rows[0].grant_id,'grant');assert.equal(rows[0].tracker,'Cariche');
});

test('native class activations use eligible collected features, edition and local tracker',()=>{
 const make=(name,owner)=>({name,origin_key:'class|phb|'+owner.toLowerCase(),
  requirements:{class_name:owner},entries:[name+' description']});
 const rage=make('Rage','Barbarian');
 const calc={features:[rage,make('Extra Attack','Fighter')],trackers:[{id:'rage-1',name:'Rages',max:3,spent:1,origin_class:'Barbarian'}]};
 const barbarian={class:'Barbarian',class_source:'PHB',level:5};
 let actions=nativeClassFeatureActions(barbarian,calc);
 assert.equal(actions.length,1);assert.equal(actions[0].name,'Ira');
 assert.equal(actions[0].tracker_id,'rage-1');assert.equal(actions[0].time,'bonus');
 assert.equal(actions[0].description,'Rage description');
 assert(!nativeClassFeatureActions(barbarian,{...calc,features:[{...rage,disabled:true}]}).length);
 const markup=actionEconomyView(barbarian,calc);
 assert(markup.includes('Ira'));assert(markup.includes('2 / 3'));
 assert(!actionEconomyView(barbarian,{features:[],trackers:[]}).includes('>Ira<'));
 const fighter={class:'Fighter',class_source:'PHB',level:5};
 assert(find(actionEntries(fighter,calc),'attack').name.includes('×2'));
 const revised={rules_version:'2024'};
 const paladin={...make('Lay on Hands','Paladin'),origin_key:'class|xphb|paladin'};
 const ability=nativeClassFeatureActions(revised,{features:[paladin],trackers:[]});
 assert.equal(ability[0].time,'bonus');
});

test('variant healing surge bonus timing mirrors desktop and picker is visible',()=>{
 const healing=actionEntries({}, {},[],[],catalog.actions,['healing_surges_bonus_dmg']);
 assert.equal(find(healing,'healing_surge')?.time,'bonus');
 const document=doc(actionEconomyView({}));
 assert(document.querySelector('[data-act="action-variants"]').textContent.includes('Regole varianti'));
 assert(document.querySelector('[data-act="action-expand-all"]'));
 const fighter=doc(actionEconomyView({class:'Fighter',level:5},{features:[
  {name:'Extra Attack',origin_key:'class|phb|fighter',requirements:{class_name:'Fighter'}}]}));
 assert(fighter.querySelector('[data-timing="action"] .action-economy-count').textContent.length>0);
});

test('load both native catalogs without duplicating, auto-enabling or dropping variants',async()=>{
 const supplementary=JSON.parse(readFileSync(new URL('../../vtt/data/combat_action_supplements_5etools.json',import.meta.url),'utf8'));
 const original=globalThis.fetch;
 try{
  globalThis.fetch=async url=>({
   ok:true,json:async()=>url.includes('supplements')?supplementary:catalog
  });
  const entries=await loadGeneralActionSupplements();
  assert.equal(entries.filter(row=>row.id==='attack'&&row.edition==='2014').length,1);
  assert.equal(entries.filter(row=>row.id==='wake'&&row.edition==='2014').length,1);
  assert.equal(entries.filter(row=>row.id==='disarm'&&row.edition==='2014').length,1);
  assert.equal(actionVariants().length,78);
  assert(!actionEntries({}, {},[],[],entries).some(row=>row.id==='disarm'));
  assert(actionEntries({}, {},[],[],entries).some(row=>row.id==='wake'));
 }finally{globalThis.fetch=original;}
});
