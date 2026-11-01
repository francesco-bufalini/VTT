import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {attackCategories,attackActionGrants,attackActionUsePatch,attackActionChoice,attackActionPayment,resolveAttackActionSteps} from '../attack_count_benefits.js';
import {multiattackSteps,normalizeMonsterStatBlock} from '../character_core.js';
import {collectStructuredFeatures} from '../structured_effects.js';
import {monsterActions,monsterActionCost,monsterActionName,lairOptions} from '../monster_traits.js';
import {actionEntries,battleActionPanels,attackActionCategory,battleAttackStepMarkup} from '../action_economy.js';
import {JSDOM} from 'jsdom';

const file=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const rules=file('../../vtt/data/feature_timing_recovery_rules.json');
const fixture=file('../../tests/fixtures/monster_traits.json');
const ki={id:'ki',name:'Ki Points',max:3,spent:0,origin_class:'Monk'};

test('attack categories use typed roll facts and support weapons, crossbows, unarmed and grapple checks',()=>{
 assert.deepEqual(attackCategories({id:'unarmed',melee:true}),['attack','melee','unarmed']);
 const crossbow=attackCategories({id:'item:crossbow',name:'Light Crossbow',melee:false,weapon_type:'ranged',weapon_category:'Simple'});
 for(const category of ['attack','ranged','weapon','ranged_weapon','crossbow'])assert.ok(crossbow.includes(category));
 assert.ok(attackCategories({id:'grapple',check_target:'skill:athletics'}).includes('grapple'));
});

test('a class attack action is granted by its actual feature, with timing, payment and a repeatable sequence',()=>{
 const record={class:'Monk',class_source:'PHB',level:3,rules_version:'2014',resource_tracker_spent:{}};
 const features=[
  {id:'martial',name:'Martial Arts',key:'martial',origin_key:'class|phb|monk',origin_id:'feature:martial'},
  {id:'flurry',name:'Flurry of Blows',key:'flurry',origin_key:'class|phb|monk',origin_id:'feature:flurry'}
 ];
 const grants=attackActionGrants(record,features,[ki],rules);
 assert.equal(grants.length,2);
 const martial=grants.find(a=>a.id==='attack_action:martial-arts-2014');
 assert.equal(martial.time,'bonus');assert.equal(martial.cost,0);
 assert.deepEqual(martial.steps,[{selector:{id:'unarmed'},count:1}]);
 const flurry=grants.find(a=>a.id==='attack_action:flurry-of-blows-2014');
 assert.equal(flurry.origin_id,'feature:flurry');
 assert.equal(flurry.time,'bonus');assert.equal(flurry.tracker_id,'ki');assert.equal(flurry.cost,1);
 assert.deepEqual(flurry.steps,[{selector:{id:'unarmed'},count:2}]);
 const targets=resolveAttackActionSteps(flurry,[{id:'unarmed',name:'Colpo senz’armi',melee:true}]);
 assert.equal(targets[0].options.length,1);
 assert.equal(targets[0].count,2);
 assert.deepEqual(attackActionUsePatch(record,{attack_actions:grants,trackers:[ki]},flurry.id),
  {resource_tracker_spent:{ki:1}});
 assert.throws(()=>attackActionUsePatch({...record,resource_tracker_spent:{ki:3}},
  {attack_actions:grants,trackers:[ki]},flurry.id),/insufficiente/i);
 assert.equal(attackActionGrants({...record,rules_version:'2024'},features,[ki],rules).length,0);
 assert.equal(attackActionGrants({...record,trait_enabled:{flurry:false}},features,[ki],rules).length,1);
});

test('the classic multiattack models any two attacks with one action',()=>{
 const stat={action:[{name:'Multiattack',entries:['The creature makes two attacks.']}]};
 const normalized=normalizeMonsterStatBlock(stat);
 const action=normalized.action[0].attack_action;
 assert.equal(action.time,'action');
 assert.deepEqual(action.steps,[{selector:{category:'attack'},count:2}]);
 assert.equal(normalized.action[0].attacks_per_action,2);
 assert.equal(normalizeMonsterStatBlock(normalized),normalized);
});

test('a dragon multiattack preserves named steps and one special use, without treating it as a hit',()=>{
 const normalized=normalizeMonsterStatBlock(fixture.stat_block);
 const row=normalized.action[0];
 assert.equal(row.attacks_per_action,3);
 assert.equal(row.vtt_attack_sequence_count,3);
 assert.equal(row.vtt_special_sequence_count,1);
 assert.deepEqual(multiattackSteps(row),[
  {selector:{kind:'ability',name:'Frightful Presence'},count:1},
  {selector:{kind:'attack',name:'bite'},count:1},
  {selector:{kind:'attack',name:'claw'},count:2}
 ]);
 const monster={...fixture,stat_block:normalized};
 const features=collectStructuredFeatures(monster);
 const routine=attackActionGrants(monster,features,[],{}).find(action=>action.monster_action);
 assert.equal(routine.origin_id,features.find(feature=>feature.monster_role==='multiattack').origin_id);
 const steps=resolveAttackActionSteps(routine,
  [{id:'monster:action:1',name:'Bite',melee:true},{id:'claws',name:'Claws',melee:true}],
  [{id:'monster:action:2',name:'Frightful Presence',monster_action:true}]);
 assert.deepEqual(steps.map(step=>step.options.length),[1,1,1]);
 const calculated={features,trackers:[],attack_actions:[routine],
  attacks:[{id:'monster:action:1',name:'Bite',hit:10,melee:true},{id:'claws',name:'Claws',hit:10,melee:true}]};
 const panel=battleActionPanels(monster,calculated);
 assert.match(panel.others,/Multiattack/);
 assert.match(panel.others,/Lista di azioni, attacchi e tiri/);
 assert.match(panel.others,/Frightful Presence/);
 assert.match(panel.others,/claw/);
 assert.doesNotMatch(panel.others,/data-attack-id="attack"/);
});

test('a typed attack action is a battle action rather than a synthetic attack in the attack table',()=>{
 const record={class:'Monk',class_source:'PHB',level:3,rules_version:'2014'};
 const features=[{name:'Flurry of Blows',key:'flurry',origin_key:'class|phb|monk',origin_id:'feature:flurry'}];
 const grants=attackActionGrants(record,features,[ki],rules);
 const calculated={features,trackers:[ki],attacks:[{id:'unarmed',name:'Colpo senz’armi',melee:true,hit:5}],attack_actions:grants};
 const entries=actionEntries(record,calculated);
 assert(entries.some(row=>row.name==='Flurry of Blows'&&row.type==='Azione di attacco'));
 const panels=battleActionPanels(record,calculated);
 assert.match(panels.others,/Flurry of Blows/);
 assert.match(panels.others,/data-attack-action-id="attack_action:flurry-of-blows-2014"/);
 assert.doesNotMatch(panels.attacks,/Flurry of Blows/);
});

test('Cunning Action grants exactly one of Dash, Disengage or Hide as a bonus action',()=>{
 const features=[{name:'Cunning Action',key:'cunning',origin_key:'class|phb|rogue',origin_id:'feature:cunning'}];
 const rogue={class:'Rogue',class_source:'PHB',level:2,rules_version:'2014'};
 const grant=attackActionGrants(rogue,features,[],rules).find(row=>row.id==='attack_action:cunning-action-phb');
 assert(grant);
 assert.equal(grant.time,'bonus');assert.equal(grant.cost,0);
 assert.deepEqual(grant.steps[0].one_of.map(choice=>choice.selector.id),['dash','disengage','hide']);
 assert.equal(attackActionCategory(grant),'other');
 assert.equal(attackActionChoice(grant,'hide').label,'Nascondersi');
 assert.throws(()=>attackActionUsePatch(rogue,{attack_actions:[grant]},grant.id),/Scegli/i);
 assert.deepEqual(attackActionUsePatch(rogue,{attack_actions:[grant],action_entries:[{id:'hide',name:'Nascondersi',type:'Generale'}]},grant.id,'hide'),{});
 const options=[{id:'dash',name:'Scattare',type:'Generale'},
  {id:'disengage',name:'Disimpegnarsi',type:'Generale'},
  {id:'hide',name:'Nascondersi',type:'Generale'}];
 const steps=resolveAttackActionSteps(grant,[],options);
 assert.equal(steps.length,1);assert.equal(steps[0].one_of.length,3);
 assert.deepEqual(steps[0].one_of.map(row=>row.options[0].id),['dash','disengage','hide']);
 const dom=new JSDOM(battleAttackStepMarkup([], {attacks:[],action_entries:options},grant));
 const doc=dom.window.document;
 assert.equal(doc.querySelectorAll('[data-action-option-id]').length,3);
 assert.equal(doc.querySelectorAll('[data-act="battle-action-jump"]').length,3);
 assert.deepEqual([...doc.querySelectorAll('[data-act="battle-action-jump"]')].map(node=>node.dataset.actionId),
  ['dash','disengage','hide']);
 dom.window.close();
 assert.equal(rules.actions.filter(row=>row.feature==='Cunning Action').length,0);
 assert.equal(attackActionGrants({...rogue,level:1},features,[],rules).length,0);
 assert.equal(attackActionGrants({...rogue,trait_enabled:{cunning:false}},features,[],rules).length,0);
});

test('a check or an ability check is a first-class alternative alongside attacks',()=>{
 const action={id:'homebrew:options',name:'Tattiche',steps:[{one_of:[
  {id:'look',label:'Osservare',selector:{kind:'check',target:'skill:perception'}},
  {id:'force',label:'Forza',selector:{kind:'check',target:'ability_check:str'}},
  {id:'strike',label:'Colpire',selector:{kind:'attack',category:'melee'}}
 ]}]};
 const attacks=[{id:'unarmed',name:'Colpo senz’armi',melee:true}];
 const steps=resolveAttackActionSteps(action,attacks,[]);
 assert.deepEqual(steps[0].one_of.map(option=>option.options[0].id),
  ['check:skill:perception','check:ability_check:str','unarmed']);
 const dom=new JSDOM(battleAttackStepMarkup([],{attacks},action));
 const document=dom.window.document;
 assert.deepEqual([...document.querySelectorAll('[data-act="battle-action-roll"]')].map(node=>node.dataset.actionRollTarget),
  ['skill:perception','ability_check:str']);
 assert.equal(document.querySelectorAll('[data-act="battle-attack-jump"]').length,1);
 assert.equal(document.querySelector('[data-act="battle-attack-jump"]').dataset.attackTargetId,'unarmed');
 dom.window.close();
 assert.deepEqual(attackActionUsePatch({}, {attack_actions:[action]},action.id,'look'),{});
});

test('a legendary action pool is one OR with independent costs and reusable checks',()=>{
 const tracker={id:'legendary_actions',name:'Azioni leggendarie',max:3,spent:0};
 const record={...fixture,resource_tracker_spent:{}};
 const grants=attackActionGrants(record,[],[tracker],rules);
 const action=grants.find(row=>row.id==='monster:legendary:choices');
 assert(action,'monster legendary pool must be projected from data');
 assert.equal(action.time,'free');assert.equal(action.tracker_id,tracker.id);
 assert.equal(attackActionCategory(action),'other');
 const alternatives=action.steps[0].one_of;
 assert.deepEqual(alternatives.map(option=>[option.id,option.tracker_cost,option.selector.kind]),[
  ['monster:legendary:0',1,'check'],
  ['monster:legendary:1',2,'ability']
 ]);
 assert.equal(alternatives[0].selector.target,'skill:perception');
 assert.equal(alternatives[0].label,'Prova di Percezione');
 assert.equal(attackActionPayment(action,'monster:legendary:1').cost,2);
 assert.throws(()=>attackActionUsePatch(record,{attack_actions:grants,trackers:[tracker]},action.id),/Scegli/i);
 assert.deepEqual(attackActionUsePatch(record,{attack_actions:grants,trackers:[tracker]},action.id,'monster:legendary:1'),
  {resource_tracker_spent:{legendary_actions:2}});
 assert.deepEqual(attackActionUsePatch(record,{attack_actions:grants,trackers:[tracker]},action.id,'monster:legendary:0'),
  {resource_tracker_spent:{legendary_actions:1}});
 assert.throws(()=>attackActionUsePatch(record,{attack_actions:grants,trackers:[tracker]},
  action.id,'fake'),/Scegli/i);
 const exhausted={...record,resource_tracker_spent:{legendary_actions:2}};
 assert.throws(()=>attackActionUsePatch(exhausted,{attack_actions:grants,trackers:[tracker]},
  action.id,'monster:legendary:1'),/insufficiente/i);
 const dom=new JSDOM(battleAttackStepMarkup([],{trackers:[tracker]},action));
 const buttons=[...dom.window.document.querySelectorAll('[data-act="attack-action-use"]')];
 assert.deepEqual(buttons.map(button=>button.dataset.attackActionOptionId),
  ['monster:legendary:0','monster:legendary:1']);
 assert.match(dom.window.document.body.textContent,/Prova di Percezione/);
 assert.doesNotMatch(dom.window.document.body.textContent,/Detect/);
 assert.match(dom.window.document.body.textContent,/Wing Attack/);
 dom.window.close();
});

test('lair choices are a free OR list and costly legendary names resolve to existing attacks',()=>{
 const legendaryTracker={id:'legendary_actions',name:'Azioni leggendarie',max:3,spent:0};
 const lairTracker={id:'lair_actions',name:'Azioni di tana',max:1,spent:0};
 const record={...fixture,resource_tracker_spent:{}};
 const grants=attackActionGrants(record,[],[legendaryTracker,lairTracker],rules);
 const lair=grants.find(row=>row.id==='monster:lairActions:choices');
 assert(lair);
 assert.equal(lair.time,'free');
 assert.deepEqual(lair.steps[0].one_of.map(row=>row.label),['Lava','Smoke','Frozen Floor']);
 assert.deepEqual(lair.steps[0].one_of.map(row=>row.tracker_cost),[1,1,1]);
 assert.equal(lairOptions(record.stat_block.lairActions).length,3);
 assert.deepEqual(attackActionUsePatch(record,{attack_actions:grants,trackers:[lairTracker]},
  lair.id,'monster:lairActions:2'),{resource_tracker_spent:{lair_actions:1}});
 assert.equal(monsterActionName('Tail Attack (Costs 2 Actions)'),'Tail Attack');
 assert.equal(monsterActionName('Tail Attack (Cost 2)'),'Tail Attack');
 assert.equal(monsterActionCost({name:'Tail Attack (Cost 2)'}),2);
 const named=structuredClone(record);
 named.stat_block.action.push({name:'Tail',entries:['{@atk mw} {@hit 10} to hit. {@damage 2d6} damage.']});
 named.stat_block.legendary.push({name:'Tail Attack (Cost 2)',entries:['The monster attacks with its tail.']});
 const enhanced=attackActionGrants(named,[],[legendaryTracker,lairTracker],rules)
  .find(row=>row.id==='monster:legendary:choices');
 const tail=enhanced.steps[0].one_of.at(-1);
 assert.equal(tail.label,'Tail Attack');
 assert.deepEqual(tail.selector,{kind:'attack',id:'monster:action:'+(named.stat_block.action.length-1)});
 assert.equal(tail.tracker_cost,2);
});

test('class feature and homebrew data share one typed OR projection',()=>{
 const feature={name:'Interventi',key:'one',origin_key:'class|phb|fighter',origin_id:'feature:one',
  action_sequence:{name:'Interventi',time:'reaction',steps:[{one_of:[
   {id:'probe',selector:{kind:'check',target:'skill:insight'}},
   {id:'move',selector:{kind:'action',id:'dash'}}
  ]}]}};
 const record={class:'Fighter',class_source:'PHB',level:2,rules_version:'2014',
  action_grants:[{id:'manual',name:'Azione homebrew',time:'bonus',steps:[
   {selector:{kind:'action',id:'disengage'}}]}]};
 const grants=attackActionGrants(record,[feature],[],rules);
 assert(grants.some(row=>row.id==='attack_action:feature:one'));
 assert(grants.some(row=>row.id==='attack_action:grant:manual'));
 assert.equal(grants.find(row=>row.id==='attack_action:feature:one').time,'reaction');
});

test('subclass and edition gates keep conditional attack sequences scoped to the right feature',()=>{
 const ranger={class:'Ranger',class_source:'PHB',level:11,rules_version:'2014'};
 const features=[
  {key:'hunter',name:'Volley',origin_key:'class|phb|ranger|subclass|hunter|phb',origin_id:'feature:volley'},
  {key:'other',name:'Whirlwind Attack',origin_key:'class|phb|ranger|subclass|gloom stalker|xge',origin_id:'feature:whirlwind'}
 ];
 const grants=attackActionGrants(ranger,features,[],rules);
 assert(grants.some(row=>row.id==='attack_action:hunter-volley-2014'));
 assert(!grants.some(row=>row.id==='attack_action:hunter-whirlwind-2014'));
 assert.equal(grants.find(row=>row.id==='attack_action:hunter-volley-2014').steps[0].repeat,'per_target');
 assert.equal(attackActionGrants({...ranger,rules_version:'2024'},features,[],rules).length,0);
});

test('legendary entries refer to concrete operations; native actions consume their own pool exactly once',()=>{
 const tracker={id:'legendary_actions',name:'Azioni leggendarie',max:3,spent:0};
 const record={...fixture,resource_tracker_spent:{}};
 const grants=attackActionGrants(record,[],[tracker],rules);
 const action=grants.find(row=>row.id==='monster:legendary:choices');
 const wing=action.steps[0].one_of.find(row=>row.id==='monster:legendary:1');
 const source=monsterActions(record,[tracker]).find(row=>row.id===wing.selector.id);
 assert(source,'Wing Attack must refer to an existing monster ability');
 assert.equal(source.time,'free');assert.equal(source.cost,2);
 assert.equal(wing.selector.kind,'ability');
 assert.deepEqual(attackActionUsePatch(record,{attack_actions:grants,trackers:[tracker]},
  action.id,wing.id),{resource_tracker_spent:{legendary_actions:2}});
 const tailored=structuredClone(record);
 tailored.stat_block.legendary[0].vtt_action_selector={kind:'check',target:'skill:insight'};
 const revised=attackActionGrants(tailored,[],[tracker],rules).find(row=>row.id===action.id);
 assert.equal(revised.steps[0].one_of[0].label,'Prova di Intuizione');
 assert.equal(revised.steps[0].one_of[0].selector.target,'skill:insight');
 const invalid=structuredClone(tailored);
 invalid.stat_block.legendary[0].vtt_action_selector={kind:'ability',id:'invented:action'};
 const wrong=attackActionGrants(invalid,[],[tracker],rules).find(row=>row.id===action.id);
 assert.throws(()=>attackActionUsePatch(invalid,{attack_actions:[wrong],trackers:[tracker]},
  wrong.id,'monster:legendary:0'),/non disponibile/i);
 const invalidCheck=structuredClone(tailored);
 invalidCheck.stat_block.legendary[0].vtt_action_selector={kind:'check',target:'skill:not-a-skill'};
 const missing=attackActionGrants(invalidCheck,[],[tracker],rules).find(row=>row.id===action.id);
 assert.throws(()=>attackActionUsePatch(invalidCheck,{attack_actions:[missing],trackers:[tracker]},
  missing.id,'monster:legendary:0'),/non disponibile/i);
});
