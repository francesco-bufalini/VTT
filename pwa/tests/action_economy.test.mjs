import test from 'node:test';
import assert from 'node:assert/strict';
import {actionEntries,actionEconomyView,topSkillEntries} from '../action_economy.js';
import {readFileSync} from 'node:fs';

test('SRD editions expose the appropriate general actions',()=>{
 const basic=actionEntries({rules_version:'2014'},{});
 const modern=actionEntries({rules_version:'2024'},{});
 assert(basic.some(x=>x.name==='Usare un oggetto'));
 assert(!basic.some(x=>x.name==='Studiare'));
 assert(modern.some(x=>x.name==='Studiare'));
 assert(modern.some(x=>x.name==='Influenzare'));
 assert(modern.some(x=>x.name==='Utilizzare'));
 assert(modern.some(x=>x.time==='movement'));
 assert(modern.some(x=>x.time==='reaction'));
});

test('real equipped and monster attacks keep the proper action cost',()=>{
 const creature={stat_block:{bonus:[{name:'Ruggito',entries:['Abilità speciale']}],
   reaction:[{name:'Scudo',entries:['Attacco in reazione']}]}};
 const calculated={attacks:[
  {id:'item:a',name:'Spada',hit:5,damage:'1d8 + 3',range_feet:5},
  {id:'item:off:b',name:'Pugnale',offhand_bonus:true,damage:'1d4 + 3',range_feet:5},
  {id:'monster:reaction:0',name:'Scudo',hit:4,range_feet:5}
 ]};
 const all=actionEntries(creature,calculated);
 assert.equal(all.filter(x=>x.name==='Scudo').length,1);
 assert.equal(all.find(x=>x.name==='Pugnale').time,'bonus');
 assert.equal(all.find(x=>x.name==='Scudo').time,'reaction');
 assert.equal(all.find(x=>x.name==='Ruggito').time,'bonus');
 assert.equal(all.find(x=>x.name==='Spada').type,'Attacco');
});

test('prepared and origin granted spells use their own resource tracker',()=>{
 const record={prepared_spells:['spell_a'],spells:['spell_a'],
   action_grants:[{name:'Ispirazione',action_type:'bonus',tracker_id:'bardic'}]};
 const calculated={trackers:[{id:'bardic',name:'Ispirazione bardica',max:3,spent:1}],
   origin_spells:[{spell_id:'spell_b',tracker_id:'bardic',tracker_cost:2,payment_mode:'tracker'}]};
 const spells=[
  {id:'spell_a',name:'Fulmine',level:3,time:[{number:1,unit:'action'}],entries:['Raggio']},
  {id:'spell_b',name:'Difesa arcana',level:1,time:[{number:1,unit:'reaction'}],entries:['Protegge']}
 ];
 const entries=actionEntries(record,calculated,spells);
 assert.equal(entries.filter(x=>x.name==='Fulmine').length,1);
 assert.equal(entries.find(x=>x.name==='Fulmine').tracker,'Slot incantesimo');
 assert.equal(entries.find(x=>x.name==='Difesa arcana').time,'reaction');
 assert.equal(entries.find(x=>x.name==='Difesa arcana').cost,2);
 assert.equal(entries.find(x=>x.name==='Difesa arcana').tracker,'Ispirazione bardica');
 assert.equal(entries.find(x=>x.name==='Ispirazione').time,'bonus');
 const html=actionEconomyView(record,calculated,spells);
 assert(html.includes('action-resource-control'));
 assert(html.includes('Slot incantesimo'));
 assert(html.includes('Ispirazione bardica'));
 assert(!html.includes('Ispirazione bardica · Incantesimo'));
 assert(!html.includes('Nessuna risorsa · Capacità'));
});

test('passive traits are excluded and all descriptions are escaped',()=>{
 const entries=actionEntries({
   action_grants:[{name:'<script>',action_type:'action',description:'<b>Hello</b>'}],
   selected_features:[{name:'Passive Armor',entries:['passive']}]
 },{});
 assert(!entries.some(x=>x.name==='Passive Armor'));
 const html=actionEconomyView({action_grants:[{name:'<script>',action_type:'action',description:'<b>Hello</b>'}]},{});
 assert(html.includes('&lt;script&gt;'));
 assert(!html.includes('<script>'));
 assert(html.includes('&lt;b&gt;Hello&lt;/b&gt;'));
});

test('supplemented class privileges require the correct edition and level',()=>{
 const overrides=[
  {class_name:'Fighter',feature_name:'Second Wind',book:'PHB',min_level:1,
   activation:'bonus',display_name:'Recuperare energie',resource_name:'Second Wind',
   description:'Recupera punti ferita.'},
  {class_name:'Fighter',feature_name:'Action Surge',book:'PHB',min_level:2,
   activation:'free',display_name:"Impeto d'azione",resource_name:'Action Surge'}
 ];
 const old={rules_version:'2014',class:'Fighter',class_source:'PHB',level:1};
 const higher={...old,level:2};
 const newEdition={...higher,class_source:'XPHB',rules_version:'2024'};
 const opts=actionEntries(old,{trackers:[{name:'Second Wind'}]},[],overrides);
 assert(opts.some(x=>x.name==='Recuperare energie'&&x.time==='bonus'));
 assert(!opts.some(x=>x.name==="Impeto d'azione"));
 assert(actionEntries(higher,{},[],overrides).some(x=>x.name==="Impeto d'azione"));
 assert(!actionEntries(newEdition,{},[],overrides).some(x=>x.name==='Recuperare energie'));
});

test('basic combat actions show targeting buttons, both movement modes, and top four skill bonuses',()=>{
 const record={rules_version:'2024'};
 const calculated={skills:{stealth:8,athletics:4,arcana:8,acrobatics:2,perception:5}};
 const entries=actionEntries(record,calculated);
 assert.equal(entries.find(row=>row.name==='Aiutare').action_id,'help');
 assert.equal(entries.find(row=>row.name==='Spingere').action_id,'shove');
 assert.equal(entries.find(row=>row.name==='Buttare prono').action_id,'prone');
 assert(entries.some(row=>row.name==='Muoversi'&&row.time==='movement'));
 assert(entries.some(row=>row.name==='Movimento furtivo'&&row.time==='movement'));
 const skills=topSkillEntries(calculated);
 assert.equal(skills.length,4);
 assert.deepEqual(skills.map(x=>x.bonus),[8,8,5,4]);
 const html=actionEconomyView(record,calculated);
 assert(html.includes('data-mode="help"'));
 assert(html.includes('data-mode="shove"'));
 assert(html.includes('data-mode="prone"'));
 assert(html.includes('data-target="skill:stealth"'));
 assert(html.includes('data-target="skill:arcana"'));
 assert(html.indexOf('<h2>Azione</h2>')<html.indexOf('Prove abilità · 4 migliori'));
 assert(html.indexOf('Prove abilità · 4 migliori')<html.indexOf('<h2>Azione bonus</h2>'));
 assert(!html.startsWith('<section class="panel"><h2>Prova abilità'));
});

test('structured 5etools supplement covers all 17 previously unlisted actions',()=>{
 const catalog=JSON.parse(readFileSync(new URL('../../vtt/data/combat_action_supplements_5etools.json',import.meta.url),'utf8'));
 assert.equal(catalog.version,1);
 const ids=new Set(catalog.entries.map(row=>row.id));
 assert.equal(ids.size,17);
 const old=actionEntries({rules_version:'2014'},{},[],[],catalog.entries);
 const newer=actionEntries({rules_version:'2024'},{},[],[],catalog.entries);
 for(const name of ['Attivare un oggetto magico','Disarmare','Afferrare una creatura',
   'Liberarsi da una presa','Stabilizzare una creatura','Combattere con due armi',
   'Svegliare una creatura','Travolgere (attraversare lo spazio nemico)',
   'Passare con acrobazia attraverso un nemico']){
   assert(old.some(row=>row.name===name),'Missing legacy action '+name);
 }
 assert(!newer.some(row=>row.name==='Disarmare'),'2014 DMG optional rules must not leak into 2024');
 assert(newer.some(row=>row.name==='Afferrare una creatura'&&row.action_id==='grapple'));
 assert(newer.some(row=>row.name==='Interrompere concentrazione'&&row.time==='free'));
 assert(old.some(row=>row.name==='Identificare un incantesimo'&&row.time==='reaction'));
 assert(old.some(row=>row.name==='Identificare un incantesimo'&&row.time==='action'));
 assert(old.some(row=>row.name==='Travolgere (attraversare lo spazio nemico)'&&row.time==='bonus'));
 assert(old.some(row=>row.name==='Travolgere (attraversare lo spazio nemico)'&&row.time==='action'));
 assert(old.some(row=>row.name==='Impulso curativo'&&row.tracker==='Dadi Vita'));
 const html=actionEconomyView({rules_version:'2014'},{skills:{athletics:6,acrobatics:2,arcana:4}},[],[],catalog.entries);
 assert(html.includes('data-mode="grapple"'),'Grapple must target a token');
 assert(html.includes('data-target="skill:athletics"'));
 assert(html.includes('data-target="skill:acrobatics"'));
 assert(html.includes('Regola opzionale'));
 for(const entry of catalog.entries){
   assert(['2014','2024'].includes(entry.edition));
   assert(['DMG','PHB','XPHB','XGE'].includes(entry.source));
   assert(entry.page>0);
   assert(Array.isArray(entry.timings)&&entry.timings.length>0);
 }
 const keys=catalog.entries.flatMap(entry=>entry.timings.map(t=>[entry.edition,entry.id,t].join(':')));
 assert.equal(new Set(keys).size,keys.length,'No duplicate catalog actions per edition/timing');
});

test('action panel prioritizes common actions, skill checks, then personal abilities and spells',()=>{
 const creature={rules_version:'2014',
   action_grants:[{name:'Privilegio unico',action_type:'action',tracker_id:'charges'}]};
 const calculated={skills:{stealth:7,athletics:4,arcana:3,acrobatics:2,perception:6},
   trackers:[{id:'charges',name:'Cariche personali',max:3,spent:1}],
   attacks:[{id:'item:main:weapon',name:'Spada personale',hit:5,damage:'1d8'}]};
 const catalog=[{id:'disarm',edition:'2014',name:'Disarmare',timings:['action'],optional:true,
   source:'DMG',page:271,skills:['athletics'],description:'Disarma il nemico.'}];
 const items=actionEntries(creature,calculated,[],[],catalog);
 assert.equal(items.find(x=>x.name==='Scattare').origin,'general');
 assert.equal(items.find(x=>x.name==='Disarmare').origin,'general');
 assert.equal(items.find(x=>x.name==='Disarmare').optional,true);
 assert.equal(items.find(x=>x.name==='Privilegio unico').origin,'personal');
 assert.equal(items.find(x=>x.name==='Spada personale').origin,'personal');
 const html=actionEconomyView(creature,calculated,[],[],catalog);
 const action=html.split('<h2>Azione bonus</h2>')[0];
 const indices=['<h3 class="action-economy-group-title">Generali</h3>',
   'Attaccare','Disarmare','Prove abilità · 4 migliori',
   '<h3 class="action-economy-group-title">Dalla scheda</h3>','Spada personale','Privilegio unico']
    .map(marker=>action.indexOf(marker));
 assert(indices.every(x=>x>=0),JSON.stringify(indices));
 assert(indices.every((x,i)=>i===0||x>indices[i-1]),JSON.stringify(indices));
 assert.equal((action.match(/action-economy-group-title/g)||[]).length,2);
 assert(!action.includes('<h3>Regola opzionale</h3>'));
 assert(action.includes('Fonte: DMG'),'Optional source remains readable in details');
 assert(action.includes('data-tracker-id="charges"'));
 assert(action.includes('data-target="skill:stealth"'));
 assert(action.includes('data-target="skill:perception"'));
 assert(action.includes('data-target="skill:athletics"'));
 assert(!action.includes('data-target="skill:acrobatics"'));
});

test('dashboard groups all five action costs in bordered cards and keeps live resources visible',()=>{
 const c={rules_version:'2014',prepared_spells:['test_spell'],
  action_grants:[{name:'Manovra speciale',action_type:'bonus',tracker_id:'dice'}]};
 const calculated={trackers:[{id:'dice',name:'Dadi superiorità',max:4,spent:2}],skills:{arcana:5,stealth:2}};
 const spells=[{id:'test_spell',name:'Raggio di gelo',level:1,time:'action'}];
 const html=actionEconomyView(c,calculated,spells);
 for(const key of ['action','bonus','free','movement','reaction']){
  assert(html.includes('data-timing="'+key+'"'),'Action group missing: '+key);
 }
 assert(html.includes('class="action-economy-dashboard"'));
 assert(html.includes('class="action-economy-heading"'));
 assert(html.includes('data-act="tracker-more" data-tracker-id="dice"'));
 assert(html.includes('data-act="tracker-less" data-tracker-id="dice"'));
 assert(html.includes('2 / 4'));
 assert(html.includes('data-act="action-cast-spell" data-spell-id="test_spell"'));
 assert(html.includes('Slot incantesimo'));
 assert(html.includes('Lancia incantesimo'));
 assert(!html.includes('class="action-economy-column-head"'),'No obsolete tracker column headings');
 const entries=actionEntries(c,calculated,spells);
 assert.equal(entries.find(x=>x.name==='Raggio di gelo').spell_id,'test_spell');
 assert.equal(entries.find(x=>x.name==='Manovra speciale').tracker_id,'dice');
});

test('action layout exposes section counts, compact type icons and usable resource controls',()=>{
 const c={rules_version:'2014',prepared_spells:['test_spell'],
  action_grants:[{name:'Manovra speciale',action_type:'bonus',tracker_id:'dice'}]};
 const calculated={trackers:[{id:'dice',name:'Dadi superiorità',max:4,spent:2}],skills:{arcana:5,stealth:2}};
 const spells=[{id:'test_spell',name:'Raggio di gelo',level:1,time:'action'}];
 const html=actionEconomyView(c,calculated,spells);
 assert.equal((html.match(/class="action-economy-count"/g)||[]).length,5);
 assert(html.includes('class="action-economy-type-icon"'));
 assert(html.includes('data-origin="personal"'));
 assert(html.includes('data-origin="general"'));
 assert(html.includes('aria-label="'));
 assert(html.includes('data-act="tracker-more" data-tracker-id="dice"'));
 assert(html.includes('data-act="tracker-less" data-tracker-id="dice"'));
 assert(html.includes('data-act="action-cast-spell" data-spell-id="test_spell"'));
 assert(html.includes('Slot incantesimo'));
});


test('shared gradient action sprites match both UI clients and stay available offline',()=>{
 const html=actionEconomyView({rules_version:'2014'},{
   skills:{'sleight of hand':7,athletics:5,arcana:4,perception:3}
 });
 assert(html.includes('vtt-action-glyph--base'),'Core glyphs should use the shared atlas');
 assert(html.includes('vtt-action-glyph--extra'),'Additional skill/action glyphs should render');
 assert(html.includes('style="--glyph-position:'),'Sprite selection is deterministic');
 assert(!html.includes('>⚔<'),'OS-dependent pictogram emoji must not be used');
 const base=readFileSync(new URL('../icons/action_dashboard_gloss.svg',import.meta.url),'utf8');
 const extra=readFileSync(new URL('../icons/action_extras.svg',import.meta.url),'utf8');
 assert.equal((base.match(/<g transform=/g)||[]).length,20);
 assert.equal((extra.match(/<g transform=/g)||[]).length,16);
 for(const svg of [base,extra]){
   assert(svg.startsWith('<svg '));
   assert(svg.includes('linearGradient id="gold"'));
   assert(svg.includes('linearGradient id="rose"'));
   assert(svg.includes('</svg>'));
 }
 const native=readFileSync(new URL('../../vtt/creature_action_economy_tab.gd',import.meta.url),'utf8');
 assert(native.includes('res://pwa/icons/action_dashboard_gloss.svg'));
 assert(native.includes('res://pwa/icons/action_extras.svg'));
 const host=readFileSync(new URL('../../network/pwa_host.gd',import.meta.url),'utf8');
 const worker=readFileSync(new URL('../sw.js',import.meta.url),'utf8');
 for(const path of ['/icons/action_dashboard_gloss.svg','/icons/action_extras.svg']){
   assert(host.includes('"'+path+'"'),'PWA host must serve '+path);
   assert(worker.includes('"'+path+'"'),'PWA offline shell must cache '+path);
 }
});
