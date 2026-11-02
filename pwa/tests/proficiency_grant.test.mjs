import test from 'node:test';
import assert from 'node:assert/strict';
import {proficiencyGrantModels,proficiencyGrantOptions,proficiencyGrantPatch} from '../proficiency_grant.js';
import {fixedProficiencies} from '../structured_effects.js';
import {powerRestSelections,powerRestChoicePatch} from '../trait_state_rules.js';

const catalog={schema_version:2,benefit_type:'proficiency_grant',entries:[{
 id:'homebrew:knowledge',granted_by:{kind:'homebrew',namespace:'demo',
  ref:{category:'feat',id:'demo:knowledge',name:'Knowledge Training'}},
 benefit:{type:'proficiency_grant',id:'demo:knowledge',
  proficiency_grant:{id:'demo:knowledge',trigger:'short_rest',groups:[
   {filter:{kinds:['skill'],include:['arcana','perception'],exclude:['skill:perception']},count:1},
   {filter:{kinds:['tool'],include:["smith's tools"]},count:1}
  ]}}
}]};
const feature={id:'demo:knowledge',name:'Knowledge Training',
 origin_id:'feature:demo:knowledge',origin_key:'feat|homebrew|knowledge'};
const record=()=>({kind:'character',id:'test',rules_version:'2014',level:5,
 proficiency_choices:[{kind:'save',key:'wis',origin_id:'background|test|one'}]});
const modelFor=record=>proficiencyGrantModels(record,{features:[feature]},catalog)[0];

test('homebrew proficiency grants use generic kind filters and preserve unrelated choices',()=>{
 const original=record(),model=modelFor(original);
 assert(model);
 assert.equal(model.title,'Knowledge Training');
 assert.equal(model.change_label,'Riposo breve');
 assert.deepEqual(model.slots.map(s=>s.filter.kinds),[['skill'],['tool']]);
 assert.deepEqual(proficiencyGrantOptions(model.slots[0],original,{}).map(x=>x.id),['skill:arcana']);
 assert.deepEqual(proficiencyGrantOptions(model.slots[1],original,{}).map(x=>x.id),["tool:smith's tools"]);
 const saved={...original,...proficiencyGrantPatch(original,model,
  ['skill:arcana',"tool:smith's tools"],{unavailable:[]})};
 assert.equal(saved.proficiency_choices.length,3);
 assert.equal(saved.proficiency_choices[0].origin_id,'background|test|one');
 assert.equal(saved.proficiency_choices[1].granting_feature_origin_id,feature.origin_id);
 assert.equal(modelFor(saved).selected.length,2);
 assert(fixedProficiencies(saved,{},[feature]).has('skill:arcana'));
 assert(fixedProficiencies(saved,{},[feature]).has("tool:smith's tools"));
});

test('selection validation rejects duplicate, filtered and already owned competencies',()=>{
 const original=record(),model=modelFor(original);
 assert.throws(()=>proficiencyGrantPatch(original,model,['skill:perception',"tool:smith's tools"]),
  /non valida/);
 assert.throws(()=>proficiencyGrantPatch(original,model,['skill:arcana','skill:arcana']),
  /non valida/);
 assert.throws(()=>proficiencyGrantPatch(original,model,['skill:arcana',"tool:smith's tools"],
  {unavailable:['skill:arcana']}),/non possiedi/);
 assert.throws(()=>proficiencyGrantPatch(original,model,['skill:arcana']),/tutte/);
});

test('short rest offers changing choices without silently deleting selected proficiencies',()=>{
 const original=record(),model=modelFor(original);
 const saved={...original,...proficiencyGrantPatch(original,model,
  ['skill:arcana',"tool:smith's tools"],{unavailable:[]})};
 const choices=powerRestSelections(saved,{features:[feature],proficiency_grants:[model]});
 assert.equal(choices.find(x=>x.id==='demo:knowledge').recovery,'short_rest');
 const rested={...saved,...powerRestChoicePatch(saved,'short_rest',
  {features:[feature],proficiency_grants:[model]})};
 assert.equal(rested.rest_selection_available['demo:knowledge'],true);
 assert.equal(rested.proficiency_choices.length,3);
 const disabled={...rested,origin_enabled:{[feature.origin_id]:false}};
 assert.equal(proficiencyGrantModels(disabled,{features:[feature]},catalog).length,0);
 assert.equal(fixedProficiencies(disabled,{},[feature]).has('skill:arcana'),false);
});
