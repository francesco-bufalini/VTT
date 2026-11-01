import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {attackActionSequence,attackActionCategory,battleAttackActionRow,battleActionPanels} from '../action_economy.js';

const doc=html=>new JSDOM(html).window.document;

test('attack actions expose one noninteractive sequence item per granted attack',()=>{
 const steps=attackActionSequence({id:'attack',attack_count:3});
 assert.deepEqual(steps,['Attacco','Attacco','Attacco']);
 assert.deepEqual(attackActionSequence({id:'two_weapon',available:true}),['Attacco con arma secondaria']);
 assert.deepEqual(attackActionSequence({id:'two_weapon',available:false}),[]);
 assert.deepEqual(attackActionSequence({id:'opportunity'}),['Attacco in mischia']);
 assert.deepEqual(attackActionSequence({attack_sequence:[{name:'Artiglio',count:2},{name:'Morso',count:1}]}),
  ['Artiglio','Artiglio','Morso']);
 assert.equal(attackActionCategory({id:'attack'}),'attacks');
 assert.equal(attackActionCategory({id:'other',type:'Capacità'}),'abilities');
 assert.equal(attackActionCategory({id:'dash',type:'Generale'}),'other');
});

test('multiattack is distinct from a normal attack and uses named monster strikes',()=>{
 const record={kind:'monster',rules_version:'2014',stat_block:{action:[
  {name:'Multiattack',attacks_per_action:4,
   entries:['The dragon makes four attacks: one with its bite, two with its claws, and one with its tail.']},
  {name:'Bite',vtt_attack:{attack_kind:'attack'}},
  {name:'Claw',vtt_attack:{attack_kind:'attack'}},
  {name:'Tail',vtt_attack:{attack_kind:'attack'}}
 ]}};
 const calculated={attacks:[
  {id:'monster:action:1',name:'Bite',melee:true,hit:7,damage:'1d10'},
  {id:'monster:action:2',name:'Claw',melee:true,hit:7,damage:'1d8'},
  {id:'monster:action:3',name:'Tail',melee:true,hit:7,damage:'1d8'}
 ],features:[{name:'Multiattack',attacks_per_action:4,origin_id:'feature:multi'}]};
 const panels=battleActionPanels(record,calculated,[],[],[]);
 const actions=doc(panels.others),resources=doc(panels.attacks);
 const sequence=actions.querySelector('[data-attack-id="monster:multiattack"] .play-attack-sequence');
 assert(sequence,'Multiattack has a descriptive sequence');
 assert.deepEqual([...sequence.children].map(node=>node.querySelector('.play-battle-roll-formula').textContent),['Bite','Claw','Claw','Tail']);
 assert.equal(sequence.querySelectorAll('.play-battle-roll-formula').length,4,
  'Each step appears under the same indexed parent');
 assert.match(sequence.closest('.play-action-index').textContent,/tutte/);
 assert.equal(sequence.querySelectorAll('[data-target],[data-damage-formula]').length,0);
 assert.equal(actions.querySelector('[data-action-source="rules"] [data-attack-id="attack"]'),null,
  'Multiattack replaces the generic Attack entry among rules');
 assert.equal(actions.querySelector('[data-action-source="privileges"] [data-attack-id="monster:multiattack"]')!==null,true);
 assert.equal(actions.querySelector('[data-action-source="privileges"] .play-battle-attack-entry:last-child')?.dataset.attackId,'monster:multiattack');
 assert.equal(sequence.closest('.play-battle-attack-action').querySelector('.play-battle-attack-range'),null);
 assert.equal(sequence.closest('.play-battle-attack-action').querySelector('[data-act="battle-attack-map"]'),null);
 assert.equal(sequence.closest('.play-battle-attack-action').querySelector('.play-battle-attacks-per-action'),null);
 assert.match(sequence.closest('.play-battle-attack-action').querySelector('.play-battle-attack-copy small').textContent,/Azione/);
 assert.equal(sequence.closest('.play-battle-attack-action').querySelector('.play-action-use-box'),null,
  'Multiattack with no tracker has no Use control');
 assert.equal(resources.querySelectorAll('[data-attack-id="monster:multiattack"]').length,0);
 assert(resources.querySelector('[data-attack-id="monster:action:1"]'));
});

test('Attacchi keeps all original attack rows and maneuvers without duplicates in Azioni',()=>{
 const rules=[
  {id:'grapple',edition:'2014',name:'Afferrare',parent_action:'attack',timings:['action'],description:'Afferrare una creatura.'},
  {id:'dash',edition:'2014',name:'Scattare',timings:['action'],description:'Muoversi più velocemente.'}
 ];
 const panels=battleActionPanels({rules_version:'2014'},{
  attacks:[{id:'unarmed',name:'Colpo senz’armi',melee:true,hit:3,damage:'1'}]},[],[],rules);
 const resources=doc(panels.attacks),actions=doc(panels.others);
 assert(resources.querySelector('[data-attack-id="unarmed"]'));
 assert(resources.querySelector('[data-attack-id="grapple"]'));
 assert(!actions.querySelector('[data-attack-id="grapple"]'));
 assert(actions.querySelector('[data-attack-id="dash"]'));
 assert(actions.querySelector('[data-action-source="rules"] [data-attack-id="attack"]'),
  'Ordinary Attack leads the rule-defined actions');
 assert(actions.querySelector('[data-action-source="rules"] [data-attack-id="opportunity"]'));
 assert.equal(actions.querySelectorAll('[data-action-benefit]').length,0);
 assert(!actions.querySelector('[data-action-timing]'),'Timing is metadata, never the grouping key');
});


test('attack-action row shows action type and tracker cost but no range, map tool or count badge',()=>{
 const document=doc(battleAttackActionRow({
  id:'monster:multiattack',name:'Multiattacco',time:'action',
  attack_count:4,attack_sequence:['Morso','Artiglio','Artiglio','Coda'],
  tracker_id:'charges',cost:2,description:'Quattro attacchi.'
 },{trackers:[{id:'charges',name:'Cariche del drago',max:5,spent:2}]}));
 const action=document.querySelector('[data-attack-id="monster:multiattack"]');
 assert.match(action.querySelector('.play-battle-attack-copy small').textContent,/Azione/);
 assert.equal(action.querySelector('.play-attack-action-cost'),null,
  'Attack-action timing reuses the regular capacity subtitle style');
 const use=action.querySelector('.play-action-use-box');
 assert(use,'The tracker cost and remaining charges share one actionable button');
 assert.match(use.querySelector('.play-action-tracker-name').textContent,/Cariche del drago/);
 assert.match(use.querySelector('.play-action-use-bottom').textContent,/−2.*·.*3\/5/);
 assert.doesNotMatch(use.textContent,/Usa/i,
  'The operative control does not visually repeat the word Usa');
 assert.match(use.getAttribute('aria-label'),/Usa Multiattacco/,
  'The control retains an accessible action name');
 assert.equal(action.querySelectorAll('.play-attack-sequence > li').length,4);
 for(const selector of ['.play-battle-attack-range','.play-battle-attacks-per-action',
  '[data-act="battle-attack-map"]','[data-target^="attack_hit:"]'])
  assert.equal(action.querySelector(selector),null,selector+' must be absent');
});
