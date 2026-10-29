import test from 'node:test';
import assert from 'node:assert/strict';
import {availableXpLevels,levelUpSteps} from '../level_up.js';

const record=(level,xp)=>({kind:'character',class:'Fighter',level,
 classes:[{name:'Fighter',source:'PHB',level}],xp});
test('available XP can cover multiple character levels at once',()=>{
 assert.equal(availableXpLevels(record(2,6500)),3);
 assert.equal(availableXpLevels(record(2,899)),0);
 assert.equal(availableXpLevels(record(19,355000)),1);
 assert.equal(availableXpLevels(record(20,999999)),0);
 assert.equal(availableXpLevels({...record(2,6500),kind:'monster'}),0);
 assert.equal(availableXpLevels({...record(1,6500),
   classes:[{name:'Fighter',level:1},{name:'Rogue',level:1}]}),3);
});
test('multilevel summary groups class features and their pending decisions per level',()=>{
 const calculated={features:[
   {name:'Action Surge',level:2,origin_key:'class|phb|fighter',origin_id:'f2'},
   {name:'Martial Archetype',level:3,origin_key:'class|phb|fighter',origin_id:'f3'},
   {name:'ASI',level:4,origin_key:'class|phb|fighter',origin_id:'f4'},
   {name:'Arcane Recovery',level:4,origin_key:'class|phb|wizard',origin_id:'w4'},
   {name:'Extra Attack',level:5,origin_key:'class|phb|fighter',origin_id:'f5'},
 ],pending_choices:[
   {id:'subclass:0',kind:'subclass',class_index:0,unlock_level:3,remaining:1},
   {id:'asi:4',origin_id:'f4',remaining:1},
   {id:'other',origin_id:'w4',remaining:1}
 ]};
 const rows=levelUpSteps(calculated,{className:'Fighter',classSource:'PHB',
   classIndex:0,fromLevel:2,toLevel:5,fromTotal:4});
 assert.deepEqual(rows.map(row=>row.level),[3,4,5]);
 assert.deepEqual(rows.map(row=>row.totalLevel),[5,6,7]);
 assert.deepEqual(rows.map(row=>row.features.map(f=>f.name)),
   [['Martial Archetype'],['ASI'],['Extra Attack']]);
 assert.deepEqual(rows.map(row=>row.choices.map(c=>c.id)),
   [['subclass:0'],['asi:4'],[]]);
});
test('subclass choice owed before a batch is shown at its first acquired level',()=>{
 const rows=levelUpSteps({pending_choices:[{id:'sub',kind:'subclass',
   class_index:1,unlock_level:3,remaining:1}]},
   {className:'Rogue',classSource:'PHB',classIndex:1,fromLevel:4,toLevel:6});
 assert.deepEqual(rows.map(row=>row.choices.map(choice=>choice.id)),[['sub'],[]]);
 assert.deepEqual(levelUpSteps({}, {className:'Rogue',fromLevel:6,toLevel:6}),[]);
});

test('class dice, half-up averages and Constitution are applied per level',async()=>{
 const {classHitDieFaces,averageHitDie,hpGainForLevels,levelUpHpPatch}=
   await import('../level_up.js');
 assert.equal(classHitDieFaces({hd:{number:1,faces:10}}),10);
 assert.equal(classHitDieFaces({hit_die:'d8'}),8);
 assert.equal(classHitDieFaces({name:'Unknown'}),0);
 assert.equal(averageHitDie(10),6);
 assert.equal(averageHitDie(6),4);
 assert.equal(hpGainForLevels([6,6,6],2),24);
 assert.equal(hpGainForLevels([1,1],-3),2);
 assert.deepEqual(levelUpHpPatch({max_hp_base:26,current_hp:21},[6,6],2),
   {max_hp_base:42,current_hp:37});
 assert.deepEqual(levelUpHpPatch({max_hp_base:1,current_hp:1},[10],2,
   {firstCharacterLevel:true}),{max_hp_base:12,current_hp:12});
 assert.throws(()=>hpGainForLevels([0],2),/non validi/);
});
