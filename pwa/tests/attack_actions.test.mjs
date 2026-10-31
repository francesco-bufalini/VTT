import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {attackCategories,attackActionGrants,attackActionUsePatch,resolveAttackActionSteps} from '../attack_count_benefits.js';
import {multiattackSteps,normalizeMonsterStatBlock} from '../character_core.js';
import {collectStructuredFeatures} from '../structured_effects.js';
import {actionEntries,battleActionPanels} from '../action_economy.js';

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
 assert.match(panel.others,/Attacchi concessi/);
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
 assert(entries.some(row=>row.name==='Raffica di colpi'&&row.type==='Azione di attacco'));
 const panels=battleActionPanels(record,calculated);
 assert.match(panels.others,/Raffica di colpi/);
 assert.match(panels.others,/data-attack-action-id="attack_action:flurry-of-blows-2014"/);
 assert.doesNotMatch(panels.attacks,/Raffica di colpi/);
});
