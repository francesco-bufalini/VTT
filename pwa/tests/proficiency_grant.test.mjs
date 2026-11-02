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


import {readFileSync} from 'node:fs';
import {pendingCharacterChoices,savePendingChoice,choicesForTrait} from '../pending_choices.js';

const skilledCatalog=JSON.parse(readFileSync(new URL('../../vtt/enrichment/benefits/proficiency_grant.json',import.meta.url),'utf8'));
const proficiencyIndex=JSON.parse(readFileSync(new URL('../catalog/proficiency_grants.json',import.meta.url),'utf8'));
const skilledRecord=source=>({...record(),proficiency_choices:[],rules_version:source==='XPHB'?'2024':'2014',
  feats_catalog:[{name:'Skilled',source}]});
const permanentChoices=character=>{
 const models=proficiencyGrantModels(character,{features:[]},skilledCatalog);
 return {models,choices:pendingCharacterChoices(character,{features:[],proficiency_grants:models},
  {proficiencyGrants:proficiencyIndex})};
};

test('PHB and XPHB Skilled use one permanent choice, three skill/tool picks, and no legacy selector',()=>{
 for(const source of ['PHB','XPHB']){
  const creature=skilledRecord(source),{models,choices}=permanentChoices(creature);
  assert.equal(models.length,1);
  assert.equal(models[0].permanent,true);
  assert.equal(models[0].trigger,'');
  assert.equal(models[0].slots.length,3);
  const typed=choices.filter(row=>row.proficiency_grant_id===models[0].id);
  assert.equal(typed.length,1);
  const choice=typed[0];
  assert.equal(choice.count,3);
  assert.equal(choice.remaining,3);
  assert(choice.options.includes('skill:arcana'));
  assert(choice.options.includes("tool:smith's tools"));
  assert.equal(choices.filter(row=>row.kind==='proficiency').length,1);
  assert.equal(choicesForTrait({rank:0,category:'talenti',
    origin_key:'feat|skilled|'+source.toLowerCase(),key:'skilled-card'},creature,choices)
    .filter(row=>row.id===choice.id).length,1);
  const patch=savePendingChoice(creature,choice,['skill:arcana','skill:perception',"tool:smith's tools"]);
  const saved={...creature,...patch};
  assert.equal(saved.proficiency_choices.length,3);
  assert(saved.proficiency_choices.every(row=>row.proficiency_grant_id===models[0].id));
  assert(fixedProficiencies(saved,proficiencyIndex,[]).has('skill:arcana'));
  const edited=permanentChoices(saved).choices.find(row=>row.id===choice.id);
  assert.equal(edited.remaining,0);
  assert.equal(edited.selected.length,3);
  const changed=savePendingChoice(saved,edited,['skill:history']);
  assert.equal(changed.proficiency_choices.length,1);
  assert.equal(changed.proficiency_choices[0].key,'history');
  assert.equal(proficiencyGrantModels({...saved,origin_enabled:{[models[0].root_id]:false}},
    {features:[]},skilledCatalog).length,0);
 }
});

test('Skilled legacy saved choices remain visible and migrate without touching another origin',()=>{
 const creature=skilledRecord('PHB');
 creature.proficiency_choices.push(
  {kind:'skill',key:'arcana',origin_id:'feat|phb|skilled'},
  {kind:'tool',key:"smith's tools",origin_id:'feat|phb|skilled'},
  {kind:'save',key:'wis',origin_id:'background|test|one'});
 const {models,choices}=permanentChoices(creature);
 assert.equal(models[0].selected.length,2);
 const pending=choices.find(row=>row.proficiency_grant_id===models[0].id);
 assert.equal(pending.remaining,1);
 assert(pending.selected.includes('skill:arcana'));
 const patch=savePendingChoice(creature,pending,['skill:arcana','skill:history',"tool:smith's tools"]);
 assert.equal(patch.proficiency_choices.length,4);
 assert.equal(patch.proficiency_choices.filter(row=>row.origin_id==='feat|phb|skilled').length,3);
 assert.equal(patch.proficiency_choices.filter(row=>row.proficiency_grant_id===models[0].id).length,3);
 assert(patch.proficiency_choices.some(row=>row.origin_id==='background|test|one'));
});

test('permanent level-up grants have group-specific picks and no rest selector or Poteri panel',()=>{
 const generic={...catalog,entries:[{...catalog.entries[0],benefit:{
  ...catalog.entries[0].benefit,
  proficiency_grant:{...catalog.entries[0].benefit.proficiency_grant,trigger:'level_up'}}}]};
 const creature=record(),models=proficiencyGrantModels(creature,{features:[feature]},generic);
 assert.equal(models.length,1);
 assert.equal(models[0].permanent,true);
 assert(!powerRestSelections(creature,{features:[feature],proficiency_grants:models})
  .some(row=>row.id===models[0].id));
 const choices=pendingCharacterChoices(creature,{features:[feature],proficiency_grants:models},{});
 const typed=choices.filter(row=>row.proficiency_grant_id===models[0].id);
 assert.equal(typed.length,2);
 assert.deepEqual(typed.map(row=>row.count),[1,1]);
 assert(!typed[0].options.includes('skill:perception'));
 const saved={...creature,...savePendingChoice(creature,typed[0],['skill:arcana'])};
 assert(saved.proficiency_choices.some(row=>row.granting_feature_origin_id===feature.origin_id));
 const changed=savePendingChoice(saved,typed[1],["tool:smith's tools"]);
 assert.equal(changed.proficiency_choices.length,3);
 assert.throws(()=>savePendingChoice(saved,typed[0],['skill:perception']),/Selezione/);
 const ui=readFileSync(new URL('../ui.js',import.meta.url),'utf8');
 assert(ui.includes('filter(model=>!model.permanent)'));
});
