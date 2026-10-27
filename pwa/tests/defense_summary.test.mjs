import test from 'node:test';
import assert from 'node:assert/strict';
import {characterDefenseSummary} from '../defense_summary.js';

test('resistances, condition immunities and vulnerabilities use active calculated entries',()=>{
 const record={origin_enabled:{'feature:disabled':false}};
 const calculated={values:{ac:17},damage_defense_entries:[
  {rank:1,key:'poison',origin_id:'race|phb|dwarf',origin_name:'Dwarven Resilience'},
  {rank:2,key:'fire',origin_id:'item:ring',origin_name:'Anello'},
  {rank:3,key:'frightened',origin_id:'trait:brave',origin_name:'Coraggio'},
  {rank:-1,key:'cold',origin_id:'curse',origin_name:'Maledizione'},
  {rank:1,key:'acid',origin_id:'feature:disabled',origin_name:'Tratto disattivato'},
  {rank:1,key:'necrotic',origin_id:'inactive',disabled:true}
 ]};
 const model=characterDefenseSummary(record,calculated);
 assert.equal(model.armor_class,17);
 assert.equal(model.count,4);
 assert.deepEqual(model.groups.map(g=>g.items.map(i=>i.label)),[
  ['Veleno'],['Fuoco'],['Spaventato'],['Freddo']
 ]);
 assert.equal(model.groups[0].items[0].origin_name,'Dwarven Resilience');
});
test('active rage and item effects are displayed once and disabled trait origins suppressed',()=>{
 const calculated={feature_damage_resistances:['bludgeoning','piercing','slashing'],
  item_damage_resistances:[{damage_type:'psychic',origin_name:'Anello della mente'}],
  damage_defense_entries:[{rank:1,key:'bludgeoning',origin_name:'Ira'}]};
 const model=characterDefenseSummary({},calculated);
 assert.equal(model.count,4);
 assert.deepEqual(model.groups[0].items.map(r=>r.label),['Contundenti','Perforanti','Psichici','Taglienti']);
 const record={trait_enabled:{'trait:key':false}};
 const no=characterDefenseSummary(record,{damage_defense_entries:[
  {rank:1,key:'fire',origin_id:'feature:trait:trait:key'}]});
 assert.equal(no.count,0);
});
test('suppressed automatic defense benefit is not shown',()=>{
 const benefitId='defense:race|phb|dwarf:1:poison';
 const record={trait_benefit_removed:{'dwarven-resilience':[benefitId]}};
 const summary=characterDefenseSummary(record,{damage_defense_entries:[
  {rank:1,key:'poison',benefit_id:benefitId,origin_id:'race|phb|dwarf'}]});
 assert.equal(summary.count,0);
});
