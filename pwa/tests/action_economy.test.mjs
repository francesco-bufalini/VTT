import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,existsSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import {sessionSpellEntries} from '../spell_selection.js';
import {collectStructuredFeatures} from '../structured_effects.js';
import {battleResourcePowers,persistentBattleAbility,spellCastingTimeLabel} from '../sheet_rules_view.js';
import {actionEntries as project,actionEconomyView as view,battleActionPanels,groupActionEntries,topSkillEntries,spellActionEntries,attacksPerAction,offhandActionAvailable,nativeClassFeatureActions,loadGeneralActionSupplements,actionVariants} from '../action_economy.js';
const catalog=JSON.parse(readFileSync(new URL('../../vtt/data/combat_actions_5etools.json',import.meta.url),'utf8'));
const featureRules=JSON.parse(readFileSync(new URL('../../vtt/data/feature_timing_recovery_rules.json',import.meta.url),'utf8'));
const classFeatures=JSON.parse(readFileSync(new URL('../catalog/classes.json',import.meta.url),'utf8'));
const projection=record=>({feature_rules:featureRules,features:collectStructuredFeatures(record,{classFeatures,featureRules})});
const actionEntries=(record={},calculated={},spells=[],overrides=[],rules=catalog.actions,enabled=[])=>project(record,{...projection(record),...calculated},spells,overrides,rules,enabled);
const actionEconomyView=(record={},calculated={},spells=[],overrides=[],rules=catalog.actions,enabled=[])=>view(record,{...projection(record),...calculated},spells,overrides,rules,enabled);
const find=(rows,id)=>rows.find(row=>row.id===id);
const doc=html=>new JSDOM(html).window.document;

test('battle panels reuse calculated attacks, optional manoeuvres and timed movement',()=>{
 const calculated={attacks:[{id:'item:sword',name:'Spada',slot:'main',melee:true,range_feet:5,hit:5,damage:'1d8'},
  {id:'item:off:dagger',name:'Pugnale',slot:'off',melee:false,range_feet:20,long_range_feet:60,offhand_bonus:true,hit:4,damage:'1d4'},
  {id:'shield:improvised:off:sh',name:'Scudo · arma improvvisata',slot:'shield',melee:true,hit:2,damage:'1d4 + 2'}],skills:{athletics:3}};
 const panels=battleActionPanels({rules_version:'2014',inventory:[
  {id:'sword',name:'Spada',type:'M',properties:['L'],equipped_slots:['main']},
  {id:'dagger',name:'Pugnale',type:'M',properties:['L'],equipped_slots:['off']}]
 },calculated,[],[],catalog.actions,['disarm_dmg','overrun_dmg']);
 const attacks=doc(panels.attacks),movement=doc(panels.others);
 assert(attacks.querySelector('[data-target="attack_hit:shield:improvised:off:sh"]'));
 assert(attacks.querySelector('[data-target="attack_hit:item:sword"]'));
 const sword=attacks.querySelector('[data-attack-id="item:sword"]');
 assert(sword);assert.equal(sword.querySelector('details').open,false);
 assert.match(sword.querySelector('.play-battle-roll-formula').textContent,/1d20 \+ 5 · Mischia/);
 assert.equal(sword.querySelector('.play-battle-attack-roll b').textContent,'+5');
 assert.equal(sword.querySelector('.play-battle-attack-roll').dataset.target,'attack_hit:item:sword');
 assert(sword.querySelector('[data-act="battle-damage-roll"]'));
 assert.equal(sword.querySelector('.play-battle-attack-range').textContent,'Portata 5 ft');
 assert.equal(sword.querySelector('[data-act="battle-attack-map"]').dataset.mapAttackId,'item:sword');
 assert.equal(sword.querySelector('[data-damage-formula]').dataset.damageFormula,'1d8');
 assert.equal(sword.querySelectorAll('.play-battle-effect').length,1);
 assert(!sword.querySelector('.play-battle-attack-chevron'));

 assert(sword.querySelector('.play-battle-attack-expanded').textContent.includes('The most common action'));
 const dagger=movement.querySelector('[data-attack-id="two_weapon"]');
 assert.equal(dagger.querySelector('.play-battle-attack-roll'),null,
  'Azione secondaria is a generic action, not a weapon attack');
 assert.equal(dagger.querySelector('.play-battle-attack-range'),null);
 assert.equal(dagger.querySelector('[data-act="battle-attack-map"]'),null);
 assert.equal(dagger.closest('[data-action-timing]').dataset.actionTiming,'bonus',
  'The secondary-hand strike is in bonus actions');
 assert.match(dagger.querySelector('.play-battle-attack-expanded').textContent,/When you take the Attack action/);
 assert.equal(attacks.querySelectorAll('[data-attack-id="item:sword"]').length,1);
 assert(!attacks.querySelector('[data-attack-id="item:off:dagger"]'),
  'The offhand strike does not appear twice in the physical attack catalogue');
 assert(![...attacks.querySelectorAll('.play-battle-attack-copy strong')].some(node=>/^(Attaccare|Combattere con due armi)$/.test(node.textContent)));
 const grapple=attacks.querySelector('[data-attack-id="grapple"]');
 assert.match(grapple.querySelector('.play-battle-roll-formula').textContent,/1d20 \+ 3 · Atletica/);
 assert.equal(grapple.querySelector('[data-target="skill:athletics"]').tagName,'BUTTON');
 assert.equal(grapple.querySelector('.play-battle-effect').dataset.effectKind,'condition');
 assert.match(grapple.querySelector('.play-battle-effect').textContent,/Afferrato/);
 assert.match(attacks.querySelector('[data-attack-id="prone"] .play-battle-effect').textContent,/Prono/);
 assert.equal(movement.querySelector('[data-attack-id="dash"] .play-battle-effect').dataset.effectKind,'movement');
 assert([...movement.querySelectorAll('[data-action-timing="movement"] .play-battle-attack-entry')]
  .every(node=>node.querySelector('.play-battle-effect')));

 assert(attacks.querySelector('[data-attack-id="disarm"] .play-battle-attack-roll'));
 assert.equal(movement.querySelector('[data-action-timing="action"] summary>.vtt-action-glyph')?.tagName,'SPAN');
 assert.equal(movement.querySelector('[data-action-timing="movement"] summary>.vtt-action-glyph')?.tagName,'SPAN');
 assert(movement.querySelector('[data-action-timing="reaction"]').textContent.includes('Attacco di opportunità'));
 const opportunity=movement.querySelector('[data-attack-id="opportunity"]');
 assert(opportunity,'The opportunity reaction is available');
 assert.equal(opportunity.querySelector('.play-battle-attack-copy strong').textContent,'Attacco di opportunità');
 assert(!opportunity.querySelector('[data-act="battle-damage-roll"]'),
  'Opportunity shows the generic action, not the main-hand weapon roll');
 assert.equal(opportunity.querySelector('.play-battle-attack-copy strong').textContent,'Attacco di opportunità');
 const shove=attacks.querySelector('[data-attack-id="shove"]');
 assert.match(shove.querySelector('.play-battle-effect').textContent,/Spinto di 5 ft/);
 assert(!shove.querySelector('.play-battle-effect').textContent.includes('Prono'));
 const actionGroup=movement.querySelector('[data-action-timing="action"]');
 assert.equal(actionGroup.tagName,'DETAILS');
 assert.equal(actionGroup.open,true,'Azioni timing groups start expanded');
 assert.equal(actionGroup.querySelector('.play-battle-action-heading').tagName,'SUMMARY');
 assert(!actionGroup.querySelector('.play-battle-action-heading .play-chevron'));
 const rollLine=sword.querySelector('.play-battle-attack-roll-line');
 assert.match(rollLine.querySelector('.play-battle-roll-formula').textContent,/1d20 \+ 5 · Mischia/);
 assert(rollLine.querySelector('button.play-battle-attack-roll'));
 assert(attacks.body.textContent.includes('Disarmare'));
 assert(!attacks.body.textContent.includes('Scattare'));
 assert(movement.querySelector('[data-action-timing="action"]').textContent.includes('Scattare'));
 assert(movement.querySelector('[data-action-timing="bonus"]').textContent.includes('Travolgere'));
 assert(movement.querySelector('[data-action-timing="movement"]').textContent.includes('Muoversi'));
 assert(!movement.body.textContent.includes('Afferrare una creatura'));
 assert(!doc(battleActionPanels({},calculated,[],[],catalog.actions).attacks).body.textContent.includes('Disarmare'));
});

test('flat Attacks retain unarmed and equipped weapons; the basic actions are timed',()=>{
 const unarmed={id:'unarmed',name:'Colpo senz’armi',slot:'main',melee:true,range_feet:5,hit:5,damage:'4'};
 const off={id:'unarmed:off',name:'Colpo senz’armi · secondaria',slot:'off',
  offhand_bonus:true,melee:true,range_feet:5,hit:5,damage:'4'};
 const record={rules_version:'2014'};
 const projected=battleActionPanels(record,{attacks:[unarmed,off],
  features:[{name:'Extra Attack',attacks_per_action:2}]},[],[],catalog.actions,[],[],true);
 const attacks=doc(projected.attacks),others=doc(projected.others);
 assert(attacks.querySelector('[data-attack-id="unarmed"]'));
 assert(!attacks.querySelector('[data-action-timing]'));
 assert(!attacks.querySelector('[data-attack-id="opportunity"]'));
 assert(!attacks.querySelector('[data-attack-id="unarmed:off"]'));
 assert(others.querySelector('[data-action-timing="action"] [data-attack-id="attack"]'));
 assert(others.querySelector('[data-action-timing="reaction"] [data-attack-id="opportunity"]'));
 assert.equal(others.querySelector('[data-attack-id="attack"] .play-battle-attacks-per-action'),null,
  'Only basic rules show the linked multiattack multiplier');
 assert.equal(projected.basicActions.find(row=>row.id==='attack').name,'Azione di attacco');
 assert.equal(projected.basicActions.find(row=>row.id==='attack').attack_count,2);
 assert.equal(projected.basicActions.find(row=>row.id==='two_weapon').available,false);
 assert(others.querySelector('[data-attack-id="two_weapon"]'),
  'Offhand action stays visible even when unavailable');
 assert.match(others.querySelector('[data-attack-id="two_weapon"]').textContent,/Equipaggia/);
 assert(!doc(battleActionPanels(record,{attacks:[unarmed,off],features:[
  {name:'Extra Attack',attacks_per_action:2,disabled:true}]},[],[],catalog.actions).others)
  .querySelector('.play-battle-attacks-per-action'));
});


test('multiattack counter uses active structured features or a monster multiattack',()=>{
 assert.equal(attacksPerAction({}, {features:[{name:'Extra Attack (2)',attacks_per_action:3}]}),3);
 assert.equal(attacksPerAction({}, {features:[{name:'Extra Attack (3)',attacks_per_action:4,inactive:true}]}),1);
 const monster={stat_block:{action:[{name:'Multiattack',entries:[
  'The creature makes three attacks: one with its bite and two with its claws.'
 ]}]}};
 const projectedMonster=collectStructuredFeatures({...monster,kind:'monster'});
 assert.equal(attacksPerAction(monster,{features:projectedMonster}),3);
 const typedMonster={kind:'monster',stat_block:{action:[{name:'Multiattack',attacks_per_action:4}]}};
 assert.equal(attacksPerAction(typedMonster,{features:collectStructuredFeatures(typedMonster)}),4);
 const attack={id:'monster:action:0',name:'Bite',melee:true,hit:6,damage:'1d8'};
 const html=doc(battleActionPanels(monster,{attacks:[attack],features:projectedMonster},[],[],catalog.actions,[],[],true).others);
 assert.equal(html.querySelector('[data-attack-id="attack"] .play-battle-attacks-per-action'),null);
 assert.equal(battleActionPanels(monster,{attacks:[attack],features:projectedMonster},[],[],catalog.actions).basicActions.find(row=>row.id==='attack').attack_count,3);
});

test('flat attacks order equipped weapons first; typed Azioni prioritize Attack, offhand and opportunity',()=>{
 const main={id:'item:blade',name:'Lama principale',slot:'main',melee:true,hit:6,damage:'1d8'};
 const off={id:'item:off:dagger',name:'Pugnale secondario',slot:'off',melee:true,
  offhand_bonus:true,hit:4,damage:'1d4'};
 const monster={id:'monster:action:0',name:'Artiglio',melee:true,hit:5,damage:'1d4'};
 const result=battleActionPanels({rules_version:'2014',inventory:[
  {id:'blade',name:'Lama principale',type:'M',properties:['L'],equipped_slots:['main']},
  {id:'dagger',name:'Pugnale',type:'M',properties:['L'],equipped_slots:['off']}]
 },{attacks:[monster,off,main]},[],[],catalog.actions);
 const flat=doc(result.attacks),others=doc(result.others);
 const ids=[...flat.querySelectorAll('.play-battle-attack-entry')].map(n=>n.dataset.attackId);
 assert.equal(ids[0],'item:blade');
 assert(ids.includes('monster:action:0'),'Monster attack choices remain available');
 assert(!ids.includes('item:off:dagger'),'Offhand weapon attacks live in the bonus-action entry');
 assert(ids.includes('unarmed'),'Unarmed is always available');
 assert(!flat.querySelector('[data-action-timing]'));
 assert.equal(others.querySelector('[data-action-timing="action"] .play-battle-attack-entry').dataset.attackId,'attack');
 assert.equal(others.querySelector('[data-action-timing="bonus"] .play-battle-attack-entry').dataset.attackId,'two_weapon');
 assert.equal(others.querySelector('[data-action-timing="reaction"] .play-battle-attack-entry').dataset.attackId,'opportunity');
 assert.equal(others.querySelector('[data-action-timing="movement"] [data-attack-id="movement"]')!==null,true);
 assert.equal(result.movement,'');
});


test('spell casting times show structured values for tracker spells instead of privilege placeholder',()=>{
 const spells=[
  {id:'action',name:'Azione',time:[{number:1,unit:'action'}]},
  {id:'bonus',name:'Bonus',time:[{number:1,unit:'bonus'}]},
  {id:'reaction',name:'Reazione',time:[{number:1,unit:'reaction'}]},
  {id:'ritual',name:'Rituale',time:[{number:10,unit:'minute'}]}
 ];
 const calculated={trackers:[{id:'focus',name:'Focus',max:4,spent:0}],
  origin_spells:spells.map(spell=>({id:'grant:'+spell.id,spell_id:spell.id,
   tracker_id:'focus',payment_mode:'tracker'}))};
 const rows=battleResourcePowers(calculated,[],[],spells);
 assert.deepEqual(rows.map(row=>row.casting_time_label),['Azione','Azione bonus','Reazione','10 minuti']);
 assert.deepEqual(rows.map(row=>row.timing),['action','bonus','reaction','contextual']);
 assert.equal(spellCastingTimeLabel({time:[{number:2,unit:'hour'}]}),'2 ore');
 assert.equal(spellCastingTimeLabel({casting_time:'bonus action'}),'Azione bonus');
 assert.equal(spellCastingTimeLabel({}), '');
});

test('combat spells are sorted by level within action, bonus and reaction and open Magia dialog',()=>{
 const spells=[
  {id:'action3',name:'Tempesta',level:3,time:[{number:1,unit:'action'}],entries:['SECRET DESCRIPTION 3']},
  {id:'action0',name:'Luce',level:0,time:[{number:1,unit:'action'}],entries:['SECRET DESCRIPTION 0']},
  {id:'action1',name:'Scudo arcano',level:1,time:[{number:1,unit:'action'}],entries:['SECRET DESCRIPTION 1']},
  {id:'bonus2',name:'Passo fatato',level:2,time:[{number:1,unit:'bonus'}],entries:['SECRET DESCRIPTION BONUS']},
  {id:'reaction1',name:'Scudo',level:1,time:[{number:1,unit:'reaction'}],entries:['SECRET DESCRIPTION REACTION']},
  {id:'slow',name:'Rituale lento',level:4,time:[{number:1,unit:'minute'}],entries:['SECRET DESCRIPTION SLOW']},
  {id:'long',name:'Lancio complesso',level:5,time:[{number:2,unit:'action'}],entries:['SECRET DESCRIPTION LONG']}
 ];
 const record={rules_version:'2014',prepared_spells:spells.slice(0,3)};
 const calc={casting_classes:[],origin_spells:[
  {id:'spellbonus',spell_id:'bonus2',payment_mode:'tracker',tracker_id:'mana'},
  {id:'spellreact',spell_id:'reaction1',payment_mode:'free'},
  {id:'spellslow',spell_id:'slow',payment_mode:'free'},
  {id:'spelllong',spell_id:'long',payment_mode:'free'}
 ],trackers:[{id:'mana',name:'Mana',max:2,spent:0}]};
 const rows=spellActionEntries(record,calc,spells);
 const entries=time=>rows.filter(row=>row.time===time)
  .sort((a,b)=>(a.level??99)-(b.level??99));
 assert.deepEqual(entries('action').map(row=>row.spell_id),['action0','action1','action3']);
 assert.deepEqual(entries('bonus').map(row=>row.spell_id),['bonus2']);
 assert.deepEqual(entries('reaction').map(row=>row.spell_id),['reaction1']);
 assert(!rows.some(row=>['slow','long'].includes(row.spell_id)));
 assert.equal(entries('bonus')[0].grant_id,'spellbonus');
 assert.equal(entries('reaction')[0].grant_id,'spellreact');
 assert.equal(entries('bonus')[0].spell_mode,'tracker');
 assert.equal(entries('reaction')[0].spell_mode,'free');
 assert.equal(battleActionPanels(record,calc,spells,[],[]).spells,'',
  'Spellcasting has moved entirely to Powers');

});

test('catalog casting time wins over stale saved spell data (Absorb Elements is a reaction)',()=>{
 const spell={id:'phb2014_absorb_elements',name:'Absorb Elements',level:1,time:[{number:1,unit:'reaction'}]};
 const creature={prepared_spells:[{id:spell.id,name:spell.name,level:1,time:[{number:1,unit:'action'}]}]};
 const rows=spellActionEntries(creature,{casting_classes:[],origin_spells:[]},[spell]);
 assert(!rows.some(row=>row.time==='action'&&row.spell_id===spell.id));
 const reaction=rows.find(row=>row.time==='reaction'&&row.spell_id===spell.id);
 assert(reaction,'Absorb Elements must still use its current catalog time in Powers');
});

test('unified battle shows every canonical skill and pure ability check grouped by ability',()=>{
 const abilityNames=['Forza','Destrezza','Costituzione','Intelligenza','Saggezza','Carisma'];
 const calculated={values:{'ability_mod:str':3,'skill:athletics':7,'ability_mod:con':2},
  abilities:{str:{modifier:3},con:{modifier:2}},skills:{athletics:7}};
 const checks=doc(battleActionPanels({},calculated,[],[],catalog.actions).checks);
 const groups=[...checks.querySelectorAll('.play-battle-action-group')];
 assert.deepEqual(groups.map(row=>row.dataset.actionAbility),['str','dex','con','int','wis','cha']);
 assert.deepEqual(groups.map(row=>row.querySelector('summary').textContent.includes('Prova di')?'?':
   row.querySelector('summary span:nth-child(2)').textContent),abilityNames);
 assert.equal(checks.querySelectorAll('.play-battle-attack-entry').length,24);
 for(const group of groups){
  assert.equal(group.tagName,'DETAILS');
  assert.equal(group.open,false,'Ability checks start collapsed');
  const first=group.querySelector('.play-battle-attack-entry');
  assert.equal(first.dataset.attackId,'ability_check:'+group.dataset.actionAbility);
  assert.equal(first.querySelector('.play-battle-attack-expanded'),null);
  assert.equal(first.querySelector('.play-battle-effect'),null);
 }
 assert.equal(checks.querySelector('[data-attack-id="ability_check:str"] .play-battle-roll-formula').textContent,'1d20 + 3 · Forza');
 assert.equal(checks.querySelector('[data-attack-id="skill:athletics"] .play-battle-roll-formula').textContent,'1d20 + 7 · Atletica');
 assert.equal(checks.querySelector('[data-attack-id="skill:athletics"] [data-act="sheet-roll"]').dataset.target,'skill:athletics');
 assert.equal(checks.querySelector('[data-action-ability="con"] .play-battle-attack-entry').dataset.attackId,'ability_check:con');
 assert.equal(checks.querySelectorAll('[data-attack-id^="skill:"]').length,18);
});

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
 assert(document.querySelector('[data-timing="action"] [data-action-group="skill-checks"] [data-target="skill:stealth"]'));
 assert(!document.querySelector('[data-timing="free"] .action-economy-skills'));
 assert.equal(document.querySelectorAll('.action-economy-skills').length,1);
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
 const calc={features:[rage,{...make('Extra Attack','Fighter'),attacks_per_action:2}],trackers:[{id:'rage-1',name:'Rages',max:3,spent:1,origin_class:'Barbarian'}]};
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
 assert.equal(find(actionEntries(fighter,calc),'attack').attack_count,2);
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
  {name:'Extra Attack',origin_key:'class|phb|fighter',attacks_per_action:2,requirements:{class_name:'Fighter'}}]}));
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

test('quick skill checks remain with the action skill group when the catalog is unavailable',()=>{
 const root=doc(actionEconomyView({}, {skills:{stealth:7,athletics:5,arcana:4,perception:3}}, [],[],[]));
 const checks=root.querySelector('[data-timing="action"] [data-action-group="skill-checks"]');
 assert(checks);assert.equal(checks.querySelectorAll('[data-target^="skill:"]').length,4);
 assert(!root.querySelector('[data-timing="free"] [data-target^="skill:"]'));
});

test('battle spells use the same timed disclosure sections without requiring slots to render',()=>{
 const spell={id:'test_spell',name:'Dardo magico',level:1,time:[{number:1,unit:'action'}]};
 const result=battleActionPanels({rules_version:'2014',prepared_spells:[spell]},{
  casting_classes:[{id:'class|phb|wizard',level:3,spellcasting_ability:'int',prepared:true}],
  origin_spells:[],trackers:[]
 },[spell],[],catalog.actions);
 assert.equal(typeof result.spells,'string');
 assert(!result.spells.includes('undefined'));
 assert.equal(result.attacks.includes('Prova di Atletica'),false);
});


test('battle projects all unported actions without duplicating weapons, movement or class powers',()=>{
 const record={rules_version:'2014',action_grants:[
  {id:'surge',name:'Impeto di battaglia',action_type:'bonus',
   origin_id:'feature:class|phb|fighter|surge',tracker_id:'surge',tracker_cost:2},
  {id:'personal',name:'Talento personalizzato',action_type:'reaction'}]};
 const calculated={skills:{athletics:5,acrobatics:4,perception:3,investigation:2},
  trackers:[{id:'surge',name:'Cariche guerriero',max:4,spent:1}]};
 const activated=[{id:'inspire',name:'Ispirazione',origin:'Classe · bard · PHB',action_type:'bonus',
  resource_cost:1,tracker_id:'inspire',tracker_name:'Ispirazioni'}];
 const result=battleActionPanels(record,calculated,[],[],catalog.actions,[],activated);
 const others=doc(result.others),movement=others;
 const powers=battleResourcePowers(calculated,result.abilityEntries,activated);
 const surge=powers.find(row=>row.id==='surge');
 assert(others.body.textContent.includes('Cercare'));
 assert(others.body.textContent.includes('Schivare'));
 assert(others.body.textContent.includes('Talento personalizzato'));
 assert(others.body.textContent.includes('Azione di attacco'));
 assert(others.body.textContent.includes('Scattare'));
 assert(!others.body.textContent.includes('Impeto di battaglia'));
 const search=others.querySelector('[data-attack-id="search"]');
 assert(search.querySelector('[data-target="skill:perception"]'));
 assert(search.querySelector('[data-target="skill:investigation"]'));
 assert.equal(search.querySelectorAll('.play-battle-roll-formula').length,2);
 const escape=movement.querySelector('[data-attack-id="escape_grapple"]');
 assert(escape);
 assert(escape.querySelector('[data-target="skill:athletics"]'));
 assert(escape.querySelector('[data-target="skill:acrobatics"]'));
 assert.equal(escape.querySelector('[data-multiple-rolls="true"] .play-battle-attack-roll').dataset.target,'skill:athletics');
 assert.equal(escape.querySelectorAll('[data-multiple-rolls="true"] .play-battle-attack-roll').length,2);
 assert(surge);
 assert.equal(surge.key,'tracker:surge');
 assert.equal(surge.cost,2);
 assert.equal(surge.timing,'bonus');
 assert(powers.some(row=>row.name==='Ispirazione'&&row.key==='missing'));
 assert.equal(result.abilityEntries.length,2);
 const exhausted=battleActionPanels(record,{...calculated,trackers:[{id:'surge',name:'Cariche guerriero',max:4,spent:3}]},
  [],[],catalog.actions);
 assert.equal(battleResourcePowers({trackers:[{id:'surge',max:4,spent:3}]},
   exhausted.abilityEntries).find(row=>row.id==='surge')?.cost,2);
 assert(!doc(exhausted.others).body.textContent.includes('Impeto di battaglia'));
 assert.equal(others.querySelector('[data-attack-id="help"] .play-battle-effect'),null,'Do not render unknown placeholder effects');
 assert.equal(others.querySelector('[data-attack-id="dodge"] .play-battle-effect'),null);
});

test('Battle resources deduplicate Wild Shape in favor of catalog popup and group paid/free spells',()=>{
 const classes=[{id:'class_feature:druid:wild_shape',name:'Forma selvatica',
  origin_id:'feature:class|phb|druid|wild_shape',rule_action_id:'wild_shape',
  tracker_id:'wild_shape',cost:1,time:'action'},
  {id:'arcane_pulse',name:'Impulso arcano',tracker_id:'focus',cost:2,time:'bonus',
   description:'Attiva un impulso'},
  {id:'arcane_pulse',name:'Impulso arcano',tracker_id:'focus',cost:2,time:'bonus',
   description:'Duplicato da action_grant'}];
 const powers=[{id:'vtt_wild_shape',name:'Wild Shape',feature_id:'feature:class|phb|druid|wild_shape',
  tracker_id:'wild_shape',resource_cost:1,action_type:'action',description:'Diventa una bestia'},
  {id:'optional',name:'Aura senza costo',resource_cost:0,action_type:'free'}];
 const calculated={trackers:[{id:'wild_shape',name:'Wild Shape',max:2,spent:0},
  {id:'focus',name:'Focus',max:4,spent:1}],
  origin_spells:[{id:'grant_fire',spell_id:'spell:fire',tracker_id:'focus',payment_mode:'tracker',tracker_cost:2},
   {id:'grant_light',spell_id:'spell:light',payment_mode:'free'},
   {id:'grant_slot',spell_id:'spell:shield',payment_mode:'slot'}]};
 const rows=battleResourcePowers(calculated,classes,powers,
  [{id:'spell:fire',name:'Fiamma'},{id:'spell:light',name:'Luce'}]);
 assert.equal(rows.filter(row=>row.kind==='ability'&&/shape|selvatica/i.test(row.name)).length,1);
 assert.equal(rows.find(row=>row.id==='activated:vtt_wild_shape')?.key,'tracker:wild_shape');
 assert.equal(rows.find(row=>row.id==='activated:vtt_wild_shape')?.source,'activated');
 assert.equal(rows.find(row=>row.id==='arcane_pulse')?.key,'tracker:focus');
 assert.equal(rows.filter(row=>row.id==='arcane_pulse').length,1);
 assert.equal(rows.find(row=>row.id==='grant_fire')?.key,'tracker:focus');
 assert.equal(rows.find(row=>row.id==='grant_fire')?.name,'Fiamma');
 assert.equal(rows.find(row=>row.id==='grant_light')?.key,'free');
 assert(!rows.some(row=>row.id==='grant_slot'));
 assert(rows.some(row=>row.name==='Aura senza costo'&&row.key==='free'));
});

test('Battle nests general free actions under Other Actions, without duplicate resource rows',()=>{
 const data=battleActionPanels({rules_version:'2014'},{
  skills:{athletics:2,perception:3},trackers:[]},[],[],catalog.actions);
 assert.equal(data.freeActions,undefined,'No separate free action block belongs beneath Resources');
 const others=doc(data.others);
 const free=others.querySelector('[data-action-timing="free"]');
 assert(free,'Free general actions have a dedicated timing group in Other Actions');
 assert(free.hasAttribute('open'),'Azioni timing subsections start expanded');
 const ids=[...free.querySelectorAll('[data-attack-id]')].map(node=>node.dataset.attackId);
 assert(ids.length>0,'At least one free general action is offered');
 assert.equal(new Set(ids).size,ids.length,'Free general actions cannot be duplicated');
 const attacks=doc(data.attacks);
 for(const id of ids)assert(!attacks.querySelector('[data-attack-id="'+id+'"]'));
 const checks=doc(data.checks);
 assert.equal(checks.querySelectorAll('[data-action-ability][open]').length,0,
  'Characteristics in skill checks start collapsed as well');
});
test('Only explicit persistent self-powers toggle, not conditions inflicted on targets',()=>{
 assert(persistentBattleAbility({power:{id:'vtt_wild_shape'}}));
 assert(persistentBattleAbility({classAction:{class_feature_id:'rage'}}));
 assert(persistentBattleAbility({power:{effects:[{kind:'condition',target:'self',condition:'invisible'}]}}));
 assert(!persistentBattleAbility({power:{effects:[{kind:'condition',target:'target',condition:'prone'}]}}));
 assert(!persistentBattleAbility({classAction:{name:'Attacco ordinario'}}));
});
test('Resource-granted spells carry the casting time from actual spell metadata',()=>{
 const data=battleResourcePowers({trackers:[{id:'focus',max:3,spent:0}],origin_spells:[
  {id:'quick',spell_id:'bonus_spell',payment_mode:'tracker',tracker_id:'focus',tracker_cost:1},
  {id:'ordinary',spell_id:'normal_spell',payment_mode:'free'}
 ]},[],[],[{id:'bonus_spell',name:'Furia',time:[{unit:'bonus',number:1}]},
  {id:'normal_spell',name:'Luce',time:[{unit:'action',number:1}]}]);
 assert.equal(data.find(x=>x.id==='quick').timing,'bonus');
 assert.equal(data.find(x=>x.id==='ordinary').timing,'action');
});

test('basic action availability derives from melee, spell slots and a real dual-wield loadout',()=>{
 const unarmed={id:'unarmed',name:'Colpo senz’armi',slot:'main',melee:true};
 const main={id:'item:sword',name:'Spada',slot:'main',melee:true};
 const off={id:'item:off:dagger',name:'Pugnale',slot:'off',melee:true,offhand_bonus:true};
 const base={rules_version:'2014',inventory:[
  {id:'sword',name:'Spada',type:'M',properties:['L'],equipped_slots:['main']},
  {id:'dagger',name:'Pugnale',type:'M',properties:['L'],equipped_slots:['off']} ]};
 const calc={attacks:[unarmed,main,off],spell_slots:[{level:1,total:2}],trackers:[]};
 assert(offhandActionAvailable(base,calc),'Two equipped light weapons grant bonus attack');
 const result=battleActionPanels(base,calc,[],[],catalog.actions,[],[],true);
 assert.equal(result.basicActions.find(a=>a.id==='opportunity').available,true);
 assert.equal(result.basicActions.find(a=>a.id==='two_weapon').available,true);
 assert.equal(result.basicActions.find(a=>a.id==='spell_cast').available,true);
 const actions=doc(result.others);
 assert.equal(actions.querySelector('[data-action-timing="action"] .play-battle-attack-entry').dataset.attackId,'attack');
 assert.equal(actions.querySelector('[data-action-timing="bonus"] .play-battle-attack-entry').dataset.attackId,'two_weapon');
 assert.equal(actions.querySelector('[data-action-timing="reaction"] .play-battle-attack-entry').dataset.attackId,'opportunity');
 const naked=battleActionPanels(base,{attacks:[unarmed],spell_slots:[]},[],[],catalog.actions);
 assert.equal(naked.basicActions.find(a=>a.id==='two_weapon').available,false);
 assert(doc(naked.others).querySelector('[data-attack-id="two_weapon"]'));
 assert.equal(naked.basicActions.find(a=>a.id==='spell_cast').available,false);
 const withShield={...base,inventory:[
  {...base.inventory[0],properties:[]},
  {id:'shield',name:'Scudo',type:'S',equipped_slots:['off']}]};
 const shieldCalc={attacks:[unarmed,main,{id:'shield:improvised:off:shield',slot:'shield',hand:'off',melee:true}]};
 assert.equal(offhandActionAvailable(withShield,shieldCalc),false);
 assert.equal(offhandActionAvailable({...withShield,feats_catalog:[{name:'Dual Wielder'}]},shieldCalc),true,
  'Dual Wielder 2014 makes an equipped improvised shield eligible');
 assert.equal(offhandActionAvailable({...base,rules_version:'2024'},calc),true);
});

test('Cunning Action keeps its owning trait and changed timing for resource grouping',()=>{
 const record={rules_version:'2014',class:'Rogue',class_source:'PHB',level:2,
  classes:[{name:'Rogue',source:'PHB',level:2}]};
 const feature={name:'Cunning Action',origin_key:'class|phb|rogue',
  origin_id:'feature:class|phb|rogue|cunning-action'};
 const projected={features:[feature],feature_rules:featureRules};
 const result=battleActionPanels(record,projected,[],[],catalog.actions,[],[],false);
 assert(result.overriddenActions.some(a=>a.id==='dash'&&a.time==='bonus'&&
  a.action_change_origin===feature.origin_id&&a.original_time==='action'));
 const bonus=doc(result.others).querySelector('[data-action-timing="bonus"]');
 assert(bonus.querySelector('[data-attack-id="dash"]'),'Cunning Action Dash belongs to bonus actions');
});

test('extra attack stays next to the Attack row; the flat list never repeats it',()=>{
 const calculated={features:[
  {name:'Extra Attack',attacks_per_action:2,origin_id:'feature:one'},
  {name:'Extra Attack (2)',attacks_per_action:3,origin_id:'feature:two'}]};
 const result=battleActionPanels({},calculated,[],[],catalog.actions,[],[],true);
 const actions=doc(result.others),attack=actions.querySelector('[data-attack-id="attack"]');
 assert.equal(attack.querySelector('.play-battle-attacks-per-action'),null);
 assert.match(attack.textContent,/Azione di attacco/);
 assert.equal(result.basicActions.find(row=>row.id==='attack').attack_count,3);
 assert(!result.attacks.includes('play-battle-attacks-per-action'));
 assert(doc(result.attacks).querySelector('[data-attack-id="unarmed"]'));
});

test('improvised shield strike remains among Attacchi while the offhand action is separate',()=>{
 const shield={id:'shield:improvised:off:shield',name:'Scudo · arma improvvisata',
  slot:'shield',hand:'off',melee:true,hit:3,damage:'1d4'};
 const result=battleActionPanels({rules_version:'2014'},
  {attacks:[shield,{id:'unarmed',name:'Colpo senz’armi',melee:true,hit:2,damage:'1'}]},[],[],catalog.actions);
 const attacks=doc(result.attacks),actions=doc(result.others);
 assert.equal(attacks.querySelectorAll('[data-attack-id="improvised"]').length,1);
 assert.match(attacks.querySelector('[data-attack-id="improvised"] .play-battle-attack-copy strong').textContent,/^Arma improvvisata$/);
 assert(actions.querySelector('[data-attack-id="two_weapon"]'));
 assert(!actions.querySelector('[data-attack-id="improvised"]'));
 assert.match(actions.querySelector('[data-attack-id="two_weapon"]').textContent,/Equipaggia/);
 assert(!actions.querySelector('[data-attack-id="opportunity"] .play-battle-attack-roll'));
});

test('spellcasting action opens Powers directly without an intermediary dialog',()=>{
 const record={rules_version:'2014'};
 const result=battleActionPanels(record,{spell_slots:[{level:1,total:2}]},[],[],catalog.actions);
 const dom=doc(result.others);
 const cast=dom.querySelector('[data-attack-id="spell_cast"]');
 assert(cast);
 assert.equal(cast.querySelector('[data-act="action-open-spells"]').tagName,'BUTTON');
 assert(!cast.querySelector('details'),'No intermediate disclosure is required');
 assert.equal(result.spells,'','The separate battle spell section has been removed');
});

test('all equipped improvised strikes collapse into one hand-neutral attack',()=>{
 const shieldMain={id:'shield:improvised:main:s1',name:'Scudo · arma improvvisata',slot:'shield',
  hand:'main',melee:true,hit:3,damage:'1d4'};
 const shieldOff={id:'shield:improvised:off:s2',name:'Scudo · arma improvvisata · secondaria',
  slot:'shield',hand:'off',melee:true,hit:3,damage:'1d4'};
 const handOff={id:'improvised:off',name:'Arma improvvisata · secondaria',slot:'off',
  melee:true,hit:3,damage:'1d4'};
 for(const real of [[shieldOff],[shieldMain],[handOff],[shieldMain,shieldOff,handOff]]){
  const panels=battleActionPanels({}, {attacks:real},[],[],catalog.actions);
  const root=doc(panels.attacks);
  assert.equal(root.querySelectorAll('[data-attack-id="improvised"]').length,1);
  assert.equal(root.querySelectorAll('[data-attack-id^="shield:improvised"]').length,0);
  const strike=root.querySelector('[data-attack-id="improvised"]');
  assert.equal(strike.querySelector('.play-battle-attack-copy strong').textContent,'Arma improvvisata');
  assert(strike.querySelector('[data-target^="attack_hit:"]'));
 }
 assert.equal(doc(battleActionPanels({}, {attacks:[]},[],[],catalog.actions).attacks)
  .querySelector('[data-attack-id="improvised"]'),null,
  'Do not offer an improvised attack without an equipped source');
});

test('Dual Wielder grants a separate capacity without unlocking the base Light rule',()=>{
 const main={id:'item:main',slot:'main',melee:true,hit:5},off={id:'item:off:second',slot:'off',melee:true,hit:4};
 const record={rules_version:'2014',inventory:[
  {id:'main',name:'Spada',type:'M',properties:[],equipped_slots:['main']},
  {id:'second',name:'Mazza',type:'M',properties:[],equipped_slots:['off']}
 ],feats_catalog:[{id:'dual-wielder',name:'Dual Wielder',origin_id:'feat|phb|dual-wielder'}]};
 const before=battleActionPanels({...record,feats_catalog:[]},{attacks:[main,off]},[],[],catalog.actions);
 assert.equal(before.offhandEligibility.base_available,false);
 assert.equal(before.offhandEligibility.feat_available,false);
 const result=battleActionPanels(record,{attacks:[main,off]},[],[],catalog.actions);
 assert.equal(result.offhandEligibility.available,true);
 assert.equal(result.offhandEligibility.base_available,false);
 assert.equal(result.offhandEligibility.feat_available,true);
 assert.equal(result.basicActions.find(row=>row.id==='two_weapon').available,false,
  'Base-rule row must stay blocked despite the feat');
 const action=doc(result.others).querySelector('[data-attack-id="two_weapon"]');
 assert(action&&!action.classList.contains('play-battle-attack-unavailable'));
 assert.equal(action.querySelector('.play-battle-attack-roll'),null);
 assert.equal(action.querySelector('.play-battle-attack-range'),null);
 const light={...record,inventory:record.inventory.map(row=>({...row,properties:['L']}))};
 assert.equal(battleActionPanels(light,{attacks:[main,off]},[],[],catalog.actions)
  .basicActions.find(row=>row.id==='two_weapon').available,true);
});

test('improvised shield offhand is usable through feat only in 2014 rules',()=>{
 const main={id:'item:main',slot:'main',melee:true,hit:4};
 const shield={id:'shield:improvised:off:shield',slot:'shield',hand:'off',melee:true,hit:3};
 const record={rules_version:'2014',inventory:[
  {id:'main',name:'Spada',type:'M',properties:[],equipped_slots:['main']},
  {id:'shield',name:'Scudo',type:'S',equipped_slots:['off']}
 ],feats_catalog:[{name:'Dual Wielder'}]};
 const result=battleActionPanels(record,{attacks:[main,shield]},[],[],catalog.actions);
 assert.equal(result.basicActions.find(row=>row.id==='two_weapon').available,false);
 assert.equal(result.offhandEligibility.feat_available,true);
 assert.equal(battleActionPanels({...record,rules_version:'2024'},
  {attacks:[main,shield]},[],[],catalog.actions).offhandEligibility.feat_available,false);
});
