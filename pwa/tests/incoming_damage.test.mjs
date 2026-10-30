import test from 'node:test';
import assert from 'node:assert/strict';
import {incomingDamageOptions,resolveIncomingDamage} from '../defense_summary.js';
import {addBenefitPatch,removeBenefitPatch} from '../trait_benefit_editor.js';
import {calculateSheet} from '../sheet_rules.js';

const mk=(mods=[],defenses=[],trackers=[])=>({
 incoming_damage_modifiers:mods,damage_defense_entries:defenses,trackers
});
const trait={key:'damage-ward',name:'Protective Ward',rank:1,category:'classi',
 origin_key:'class|phb|wizard'};
const benefit=(id,expression,optional=false,rest={})=>({
 id,origin_id:'feature:trait:damage-ward',origin_name:'Protective Ward',
 expression,optional,...rest
});

test('damage-taken modifiers are stored as trait-owned benefits and can be removed',()=>{
 const first=addBenefitPatch({},trait,'incoming_damage',{
  mode:'permanent',expression:'-proficiency',damage_type:'fire'},'trait:protective1');
 assert.equal(first.incoming_damage_modifiers[0].parent_origin,trait.origin_key);
 assert.equal(first.incoming_damage_modifiers[0].trait_key,trait.key);
 assert.equal(first.incoming_damage_modifiers[0].optional,false);
 assert.equal(first.incoming_damage_modifiers[0].damage_type,'fire');
 const limited=addBenefitPatch({},trait,'incoming_damage',{
  mode:'optional',expression:'-1d6',tracker_id:'ward',tracker_cost:'2'},'trait:protective2');
 assert.equal(limited.incoming_damage_modifiers[0].tracker_id,'ward');
 assert.equal(limited.incoming_damage_modifiers[0].tracker_cost,2);
 assert.deepEqual(removeBenefitPatch(limited,trait,{
  type:'incoming_damage',id:'incoming_damage:trait:protective2'}).incoming_damage_modifiers,[]);
 assert.throws(()=>addBenefitPatch({},trait,'incoming_damage',{
  mode:'permanent',expression:'-2',tracker_id:'ward'},'trait:protective3'),/Tracker/);
 assert.throws(()=>addBenefitPatch({},trait,'incoming_damage',{
  mode:'optional',expression:'-1d7'},'trait:protective4'),/Formula/);
});

test('permanent reduction applies first and defenses are applied once per damage type',()=>{
 const computed=mk([benefit('flat','-2')],[
  {key:'fire',rank:1,origin_name:'A'}, {key:'fire',rank:1,origin_name:'B'},
  {key:'fire',rank:-1,origin_name:'C'}]);
 const record={};
 assert.equal(resolveIncomingDamage(record,computed,{amount:11,damage_type:'fire'}).damage,8);
 assert.equal(resolveIncomingDamage(record,computed,{amount:11,damage_type:'cold'}).damage,9);
 assert.equal(resolveIncomingDamage(record,computed,{
  amount:11,damage_type:'fire',ignore_permanent:true}).damage,11);
 assert.equal(resolveIncomingDamage(record,mk([],[
  {key:'fire',rank:2},{key:'fire',rank:-1}]),{amount:11,damage_type:'fire'}).damage,0);
 assert(incomingDamageOptions(record,computed,'fire').some(row=>row.kind==='defense'&&row.rank===1));
});

test('optional damage dice can spend a tracker while permanent effects are ignored',()=>{
 const record={resource_tracker_spent:{ward:0}};
 const tracker={id:'ward',name:'Ward',max:2,spent:0};
 const computed=mk([
  benefit('always','-3'),
  benefit('ward-die','-1d6',true,{formula:'1d6',sign:-1,tracker_id:'ward',tracker_cost:1}),
  benefit('fire-only','-2',true,{damage_type:'fire',value:-2})
 ],[],[tracker]);
 // Numeric bonuses have their resolved values in the computed sheet.
 computed.incoming_damage_modifiers[0].value=-3;
 const resolved=resolveIncomingDamage(record,computed,{
  amount:15,damage_type:'cold',ignore_permanent:true,selected_ids:['ward-die']
 },()=>4);
 assert.equal(resolved.damage,11);
 assert.equal(resolved.resource_patch.resource_tracker_spent.ward,1);
 assert.equal(record.resource_tracker_spent.ward,0,'Planning a payment does not mutate the original sheet');
 assert.throws(()=>resolveIncomingDamage(record,computed,{
  amount:10,damage_type:'cold',selected_ids:['fire-only']
 }),/non disponibile/);
 assert.equal(resolveIncomingDamage(record,computed,{amount:10,damage_type:'cold'}).damage,7);
});

test('multiple optional bonuses share a tracker atomically and reject exhaustion',()=>{
 const record={resource_tracker_spent:{ward:0}};
 const two=[benefit('a','-1',true,{value:-1,tracker_id:'ward',tracker_cost:1}),
  benefit('b','-2',true,{value:-2,tracker_id:'ward',tracker_cost:1})];
 const computed=mk(two,[],[{id:'ward',max:1,spent:0}]);
 assert.throws(()=>resolveIncomingDamage(record,computed,{
  amount:10,selected_ids:['a','b']}),/insufficiente/);
 assert.deepEqual(record.resource_tracker_spent,{ward:0});
 assert.equal(resolveIncomingDamage(record,computed,{
  amount:10,selected_ids:['a']}).resource_patch.resource_tracker_spent.ward,1);
 assert.throws(()=>resolveIncomingDamage({...record,resource_tracker_spent:{ward:1}},computed,{
  amount:10,selected_ids:['a']}),/non disponibile/);
});

test('calculated incoming modifiers observe source and individual trait activation',()=>{
 const record={kind:'character',level:1,abilities:{str:10,dex:10,con:10,int:10,wis:10,cha:10},
  incoming_damage_modifiers:[benefit('active','-2'),benefit('disabled','-5',false,{disabled:true})]};
 const projected=calculateSheet(record,{});
 assert(projected.incoming_damage_modifiers.some(row=>row.id==='active'&&row.value===-2));
 assert(!projected.incoming_damage_modifiers.some(row=>row.id==='disabled'));
 const off=calculateSheet({...record,trait_enabled:{'damage-ward':false}},{});
 assert.equal(off.incoming_damage_modifiers.length,0);
});
