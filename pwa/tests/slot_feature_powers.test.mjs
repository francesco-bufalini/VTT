import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {slotFeaturePowers,slotFeaturePaymentOptions,slotFeatureUsePatch} from '../slot_feature_powers.js';

const catalog=JSON.parse(readFileSync(new URL('../catalog/slot_feature_powers.json',import.meta.url),'utf8'));
const features=[
 {name:'Primeval Awareness',origin_id:'feature:ranger',origin_key:'class|phb|ranger'},
 {name:'Combat Wild Shape',origin_id:'feature:moon',
  origin_key:'class|phb|druid|subclass|circle of the moon|phb'}
];
const stats=(count=2,spent=0)=>({
 features,spell_slots:[{level:1,total:count,spent},...Array.from({length:8},(_,n)=>({level:n+2,total:0,spent:0}))],
 pact_slots:{level:2,total:0,spent:0}
});
const ranger=(level=3)=>({id:'ranger',classes:[{name:'Ranger',source:'PHB',level}],
 spell_slots_spent:Array(10).fill(0),active_class_features:{}});
const moon=()=>({...ranger(3),classes:[{name:'Druid',source:'PHB',level:2}],
 current_form_id:'wild:owl',active_class_features:{wild_shape:{name:'Forma selvatica'}},
 current_hp:12,max_hp:20,
 variants:[{id:'wild:owl',name:'Forma selvatica',preset:'wild_shape',sections:['hp'],
 values:{current_hp:7,max_hp:16,max_hp_base:16,temporary_hp:0}}]});
test('Primeval Awareness appears only with its PHB Ranger feature',()=>{
 const d=stats(),r=ranger();
 assert.equal(slotFeaturePowers(r,d,catalog)[0].id,'ranger_primeval_awareness_phb');
 assert.deepEqual(slotFeaturePowers(ranger(2),d,catalog),[]);
 assert.deepEqual(slotFeaturePowers(r,{...d,features:[]},catalog),[]);
 assert.deepEqual(slotFeaturePowers({...r,origin_enabled:{'feature:ranger':false}},d,catalog),[]);
 assert.deepEqual(slotFeaturePowers({...r,classes:[{name:'Ranger',source:'XPHB',level:3}]},d,catalog),[]);
});
test('Same spell-slot choices and bounded consumption as ordinary spells',()=>{
 const r=ranger(),d=stats(),power=slotFeaturePowers(r,d,catalog)[0];
 assert.deepEqual(slotFeaturePaymentOptions(power,d).map(row=>row.id),['slot:1']);
 const applied=slotFeatureUsePatch(r,d,catalog,power.id,'slot:1');
 assert.equal(applied.patch.spell_slots_spent[1],1);
 assert.equal(applied.level,1);
 assert.equal(applied.healed,0);
 assert.throws(()=>slotFeatureUsePatch(r,d,catalog,power.id,'slot:3'),/Slot/);
 assert.throws(()=>slotFeatureUsePatch({...r,spell_slots_spent:applied.patch.spell_slots_spent},
  stats(2,2),catalog,power.id,'slot:1'),/Slot/);
});
test('Combat Wild Shape slot healing operates on form HP, not original HP',()=>{
 const r=moon(),d=stats(),power=slotFeaturePowers(r,d,catalog)[0];
 assert.equal(power.id,'druid_combat_wild_shape_healing_phb');
 assert.equal(power.action,'bonus');
 const result=slotFeatureUsePatch(r,d,catalog,power.id,'slot:1',[5]);
 assert.equal(result.healed,5);
 assert.equal(result.patch.current_hp,12);
 assert.equal(result.patch.spell_slots_spent[1],1);
 assert.equal(r.current_hp,12,'base HP unchanged until variant-aware editor patch');
 assert.throws(()=>slotFeatureUsePatch(r,d,catalog,power.id,'slot:1',[9]),/cura/);
});
test('Combat Wild Shape requires transformation and tracks manual healing when form HP are not overridden',()=>{
 const r=moon(),d=stats();
 const off={...r,active_class_features:{}};
 assert.equal(slotFeaturePowers(off,d,catalog)[0].available,false);
 assert.throws(()=>slotFeatureUsePatch(off,d,catalog,'druid_combat_wild_shape_healing_phb','slot:1',[3]),/Forma selvatica/);
 const untracked={...r,variants:[{...r.variants[0],sections:['appearance']}]};
 const result=slotFeatureUsePatch(untracked,d,catalog,'druid_combat_wild_shape_healing_phb','slot:1',[3]);
 assert.equal(result.patch.current_hp,undefined);
 assert.equal(result.manual_healing,3);
});
