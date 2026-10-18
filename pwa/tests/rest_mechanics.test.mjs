import {test} from 'node:test';
import assert from 'node:assert/strict';
import {initialCreature,hitDicePools} from '../character_core.js';
import {completeRest} from '../native_sheet.js';

function character(version='2014'){
 const c=initialCreature('character','Esploratore','id','owner');
 Object.assign(c,{rules_version:version,hit_dice:'5d8 (Rogue)',max_hp:50,current_hp:25,
  temporary_hp:7,exhaustion:2,death_save_successes:1,death_save_failures:2,
  abilities:{...c.abilities,con:14},
  spell_slots_spent:[0,2,1,0,0,0,0,0,0,0],pact_slots_spent:2,
  resource_trackers:[{id:'short',max:3,recharge:'short_rest'},{id:'long',max:2,recharge:'long_rest'},{id:'manual',max:5,recharge:'manual'}],
  resource_tracker_spent:{short:2,long:1,manual:4},
  active_class_features:{rage:{active:true}},created_spell_slots:[{level:1}]});
 return c;
}
function calculated(c){
 return {stats:{max_hp:c.max_hp,hit_dice:c.hit_dice},abilities:{con:{modifier:(c.abilities.con-10)/2}},trackers:c.resource_trackers};
}

test('short rest spends selected Hit Dice and recovers HP, pact magic and short-rest features',()=>{
 const c=character();
 const before=structuredClone(c);
 assert.deepEqual(hitDicePools(c,calculated(c)),[{die:8,total:5,spent:0,available:5}]);
 let nextRoll=0;
 const r=completeRest(c,'short_rest',calculated(c),{d8:2},()=>[4,6][nextRoll++]);
 assert.equal(r.patch.current_hp,39);
 assert.equal(r.healed,14);
 assert.deepEqual(r.patch.hit_dice_spent,{d8:2});
 assert.deepEqual(r.rolls.map(x=>x.roll),[4,6]);
 assert.equal(r.patch.pact_slots_spent,0);
 assert.equal(r.patch.spell_slots_spent,undefined,'Class spell slots persist across a short rest');
 assert.equal(r.patch.resource_tracker_spent.short,undefined);
 assert.equal(r.patch.resource_tracker_spent.long,1);
 assert.equal(r.patch.resource_tracker_spent.manual,4);
 assert.deepEqual(r.patch.active_class_features,{});
 assert.equal(r.patch.temporary_hp,undefined,'Short rest keeps existing temporary HP');
 assert.deepEqual(c,before,'The domain operation must never mutate the record');
});

test('2014 long rest restores HP, class slots and only half the total Hit Dice',()=>{
 const c=character();c.hit_dice_spent={d8:4};
 const r=completeRest(c,'long_rest',calculated(c));
 assert.equal(r.patch.current_hp,50);
 assert.equal(r.healed,25);
 assert.equal(r.patch.temporary_hp,0);
 assert.equal(r.patch.exhaustion,1);
 assert.equal(r.patch.death_save_successes,0);
 assert.equal(r.patch.death_save_failures,0);
 assert.deepEqual(r.patch.hit_dice_spent,{d8:2});
 assert.equal(r.patch.pact_slots_spent,0);
 assert.deepEqual(r.patch.spell_slots_spent,Array(10).fill(0));
 assert.deepEqual(r.patch.created_spell_slots,[]);
 assert.equal(r.patch.resource_tracker_spent.short,undefined);
 assert.equal(r.patch.resource_tracker_spent.long,undefined);
 assert.equal(r.patch.resource_tracker_spent.manual,4);
 assert.deepEqual(r.patch.active_class_features,{});
});

test('2024 rest uses minimum 1 HP per spent die and long rest recovers all Hit Dice',()=>{
 const c=character('2024');c.abilities.con=2;c.hit_dice_spent={d8:3};
 assert.equal(completeRest(c,'short_rest',calculated(c),{d8:1},()=>2).patch.current_hp,26);
 const r=completeRest(c,'long_rest',calculated(c));
 assert.deepEqual(r.patch.hit_dice_spent,{});
 assert.equal(r.patch.current_hp,50);
 assert.equal(r.patch.exhaustion,1);
});

test('2014 negative CON roll never damages the character on a short rest',()=>{
 const c=character();c.abilities.con=2;
 assert.equal(completeRest(c,'short_rest',calculated(c),{d8:1},()=>2).patch.current_hp,25);
});

test('multiclass pools keep separate dice and recover highest dice first in 2014',()=>{
 const c=character();c.hit_dice='3d8 (Rogue), 2d10 (Fighter)';
 c.hit_dice_spent={d8:3,d10:2};
 assert.deepEqual(hitDicePools(c,calculated(c)).map(p=>p.available),[0,0]);
 assert.deepEqual(completeRest(c,'long_rest',calculated(c)).patch.hit_dice_spent,{d8:3});
});

test('invalid spend and unconscious rests are rejected before changing creature state',()=>{
 const c=character();
 for(const selected of [{d8:6},{d8:-1},{d8:1.5},{d10:1}]){
  assert.throws(()=>completeRest(c,'short_rest',calculated(c),selected),/Dadi Vita/);
 }
 assert.throws(()=>completeRest({...c,current_hp:0},'short_rest',calculated(c)),/almeno 1 PF/);
 assert.throws(()=>completeRest({...c,current_hp:0},'long_rest',calculated(c)),/almeno 1 PF/);
 assert.deepEqual(c.hit_dice_spent,{});
});

test('legacy manual Hit Dice string and no-class creatures remain supported',()=>{
 const c=character();c.hit_dice='2d6 + 1d10';c.hit_dice_spent={d6:1};
 const r=completeRest(c,'short_rest',calculated(c),{d6:1,d10:1},()=>3);
 assert.equal(r.patch.current_hp,35);
 assert.deepEqual(r.patch.hit_dice_spent,{d10:1,d6:2});
 const monster=initialCreature('monster','Guardiano','monster','owner');
 monster.current_hp=7;monster.max_hp=12;
 assert.deepEqual(hitDicePools(monster,{}),[]);
 assert.equal(completeRest(monster,'long_rest',{}).patch.current_hp,12);
});
