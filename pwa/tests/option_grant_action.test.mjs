import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {powerSelectionModels,powerApplicationPatch,projectSelectionBenefits,optionGrantActionTrigger} from '../power_selection.js';
import {abilitiesForCreature} from '../activated_abilities.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const typed=read('../../vtt/enrichment/benefits/option_grant.json');
const armor=typed.entries.find(e=>e.benefit?.option_grant?.id==='arcane_armor')?.benefit.option_grant;

test('Arcane Armor uses an ordinary action, not manual application',()=>{
 assert.ok(armor);
 assert.equal(armor.layers.applied.trigger,'action');
 assert.equal(armor.activation_action.action_type,'action');
 assert.equal(armor.activation_action.id,'arcane_armor');
});

function scenario(){
 const grant={id:'test:focus',title:'Focus',owner:{class_name:'Fighter',class_source:'PHB',trait:'Focus'},
  benefit_type:'option_grant',option_kind:'capability',
  source:{type:'inline',options:[{id:'focus',name:'Focus',effects:[{type:'bonus',target:'speed',expression:'5'}]}]},
  layers:{applied:{limit:1,trigger:'bonus'}},
  activation_action:{id:'focus',name:'Activate Focus',action_type:'bonus'},
  application:{destination:'origin'}};
 const catalog={optionGrants:{entries:[{granted_by:{ref:{category:'class_feature',name:'Focus',source:'PHB'}},
  benefit:{type:'option_grant',option_grant:grant}}]},optionLists:{entries:[]}};
 const feature={name:'Focus',origin_id:'feature:class|phb|fighter|focus',origin_key:'class|phb|fighter',
  class_name:'Fighter',class_source:'PHB',level:1};
 const record={rules_version:'2014',classes:[{name:'Fighter',source:'PHB',level:1}],
  inventory:[],power_applications:{},power_selections:{}};
 const calculated={features:[feature],trackers:[]};
 return {record,calculated,catalog};
}

test('applied options are managed only through their associated action',()=>{
 const {record,calculated,catalog}=scenario();
 const model=powerSelectionModels(record,calculated,catalog)[0];
 assert.ok(model);
 assert.equal(optionGrantActionTrigger(model),true);
 assert.throws(()=>powerApplicationPatch(record,calculated,catalog,model.id,'focus',true),
  /soltanto usando la sua azione/);
 const applied=powerApplicationPatch(record,calculated,catalog,model.id,'focus',true,{viaAction:true});
 assert.deepEqual(applied.power_applications[model.id].map(x=>x.id),['focus']);
 const active={...record,...applied};
 const projected=projectSelectionBenefits(active,{powerSelections:catalog},calculated.features);
 assert.equal(projected.selection_traits[0]?.name,'Focus');
 assert.equal(projected.selection_traits[0]?.selection_id,model.id);
 assert.throws(()=>powerApplicationPatch(active,calculated,catalog,model.id,'focus',false),
  /soltanto usando la sua azione/);
 const off=powerApplicationPatch(active,calculated,catalog,model.id,'focus',false,{viaAction:true});
 assert.deepEqual(off.power_applications[model.id],[]);
});

test('an option-grant action becomes an activatable battle ability',()=>{
 const {record,calculated,catalog}=scenario();
 const power_selections=powerSelectionModels(record,calculated,catalog);
 const abilities=abilitiesForCreature(record,[],{...calculated,power_selections});
 const action=abilities.find(x=>x.option_grant_id==='test:focus');
 assert.ok(action);
 assert.equal(action.action_type,'bonus');
 assert.equal(action.name,'Activate Focus');
});

test('invalid trigger/action mismatches are rejected before application',()=>{
 const {record,calculated,catalog}=scenario();
 catalog.optionGrants.entries[0].benefit.option_grant.activation_action.action_type='reaction';
 assert.throws(()=>powerSelectionModels(record,calculated,catalog),
  /Azione di applicazione non definita/);
});
