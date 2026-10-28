import test from 'node:test';
import assert from 'node:assert/strict';
import {onHitRollEffects,attackHitEffectPatch,attackHitRollSources,hitEffectExpired} from '../attack_hit_effects.js';

const attack={id:'class_feature:thunder_gauntlets',name:'Thunder Gauntlets',on_hit_effects:[{
 trigger:'on_hit',operation:'roll_mode',target:'attack_roll',mode:'disadvantage',
 duration:'until_start_of_next_turn',condition_label:'Attacchi contro altri bersagli'
}]};
const combat=(round,index)=>({combat:{active:true,round,active_index:index,entries:[
 {token_id:'guard',initiative:20},{token_id:'source',initiative:10},{token_id:'target',initiative:8}
]}});

test('a confirmed Thunder Gauntlets hit is target-scoped, never auto-assumed',()=>{
 assert.equal(onHitRollEffects(attack).length,1);
 const patch=attackHitEffectPatch({},attack,0,{
  source_token_id:'source',target_token_id:'target',source_name:'Artefice',
  source_creature_id:'owner',snapshot:combat(4,1)});
 const record={...patch};
 assert.equal(record.applied_hit_effects.length,1);
 assert.deepEqual(attackHitRollSources(record,'attack_hit:longsword','',combat(4,1)),[]);
 assert.deepEqual(attackHitRollSources(record,'attack_hit:longsword','attack_target:source',combat(4,1)),[]);
 const other=attackHitRollSources(record,'attack_hit:longsword','attack_target:guard',combat(4,2));
 assert.equal(other.length,1);
 assert.equal(other[0].mode,'disadvantage');
 assert.equal(attackHitRollSources(record,'casting_hit:int','attack_target:guard',combat(4,2)).length,1);
 assert.deepEqual(attackHitRollSources(record,'save:dex','attack_target:guard',combat(4,2)),[]);
});

test('source next turn expires conditional disadvantage without deleting saved sheet',()=>{
 const record=attackHitEffectPatch({},attack,0,{
  source_token_id:'source',target_token_id:'target',snapshot:combat(4,1)});
 const mark=record.applied_hit_effects[0];
 assert.equal(hitEffectExpired(mark,combat(4,2)),false);
 assert.equal(hitEffectExpired(mark,combat(5,0)),false);
 assert.equal(hitEffectExpired(mark,combat(5,1)),true);
 assert.equal(attackHitRollSources(record,'attack_hit:axe','attack_target:guard',combat(5,1)).length,0);
 assert.equal(hitEffectExpired(mark,combat(6,0)),true);
});

test('repeated hits refresh instead of stacking and invalid attacks cannot mark',()=>{
 const one=attackHitEffectPatch({},attack,0,{source_token_id:'source',target_token_id:'target',snapshot:combat(4,1)});
 const renewed=attackHitEffectPatch(one,attack,0,{source_token_id:'source',target_token_id:'target',snapshot:combat(5,1)});
 assert.equal(renewed.applied_hit_effects.length,1);
 assert.equal(renewed.applied_hit_effects[0].applied_round,5);
 assert.throws(()=>attackHitEffectPatch({}, {id:'empty'},0,{source_token_id:'source',target_token_id:'target'}));
});
