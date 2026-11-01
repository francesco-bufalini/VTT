import {speciesPowerTestIndex} from './species_power_test_fixture.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {racialPowerProjection} from '../species_powers.js';
import {abilitiesForCreature} from '../activated_abilities.js';
import {abilityAttackRoll,battleAbilityEntries} from '../action_economy.js';

const index=speciesPowerTestIndex();
const root='species|5etools:races:mpmm:centaur|mpmm';
const feature={name:'Charge',origin_key:root,
 origin_id:'feature:'+root+'|1|charge',key:root+'|1|charge'};
const character=(extra={})=>({kind:'character',rules_version:'2014',
 species:'Centaur',species_source:'MPMM',level:3,...extra});
const hooves={id:'natural:5etools:races:mpmm:centaur:hooves',name:'Hooves',
 slot:'natural',melee:true,damage:'1d6+3',hit:5};
const projected=abilities=>({
 features:[feature],trackers:[],racial_abilities:abilities,attacks:[hooves],
 values:{['attack_hit:'+hooves.id]:5}
});
test('Centaur MPMM Charge is a no-cost bonus action with an existing natural attack',()=>{
 const powers=racialPowerProjection(character(),index,[feature]);
 assert.equal(powers.abilities.length,1);
 assert.equal(powers.trackers.length,0);
 assert.deepEqual(powers.abilities[0].roll_attack,
   {kind:'attack',trait:'Hooves',slot:'natural'});
 assert.equal(powers.abilities[0].action_type,'bonus');
 assert.equal(powers.abilities[0].resource_cost,0);
 assert.equal(powers.abilities[0].feature_id,feature.origin_id);
 const activated=abilitiesForCreature(character(),[],projected(powers.abilities));
 assert.equal(activated.length,1);
 const actions=battleAbilityEntries(character(),projected(powers.abilities),[],activated);
 assert.equal(actions.length,1);
 assert.equal(actions[0].time,'bonus');
 assert.deepEqual(actions[0].roll_attack,{kind:'attack',trait:'Hooves',slot:'natural'});
 assert.deepEqual(abilityAttackRoll(activated[0],projected(powers.abilities)),{
   target:'attack_hit:'+hooves.id,label:'Charge · Hooves'
 });
});
test('Charge respects its granting trait and pre-2024 edition',()=>{
 const grant=(extra,features=[feature])=>
   racialPowerProjection(character(extra),index,features).abilities;
 assert.deepEqual(grant({},[]),[]);
 assert.deepEqual(grant({},[{...feature,inactive:true}]),[]);
 assert.deepEqual(grant({trait_enabled:{[feature.key]:false}}),[]);
 assert.deepEqual(grant({origin_enabled:{[feature.origin_id]:false}}),[]);
 assert.deepEqual(grant({rules_version:'2024'}),[]);
 assert.deepEqual(grant({species_source:'GGR'}),[]);
});
test('generic action roll reference only accepts available calculated attacks',()=>{
 const action={name:'Prova',roll_attack:{kind:'attack',trait:'Hooves',slot:'natural'}};
 assert.equal(abilityAttackRoll(action,{attacks:[hooves],values:{}}),null);
 assert.equal(abilityAttackRoll(action,{attacks:[],values:{['attack_hit:'+hooves.id]:5}}),null);
 assert.equal(abilityAttackRoll({...action,roll_attack:{kind:'attack',trait:'Other'}},
   projected([])),null);
 assert.equal(abilityAttackRoll({name:'Passive'},projected([])),null);
 const source=readFileSync(new URL('../ui.js',import.meta.url),'utf8');
 assert.match(source,/abilityAttackRoll\(ability,calculated\)/);
 assert.match(source,/act:'sheet-roll',target:roll\.target/);
});
