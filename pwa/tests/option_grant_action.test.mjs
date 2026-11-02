import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import {
 powerSelectionModels,powerApplicationPatch,projectSelectionBenefits,
 optionGrantActionTrigger,optionGrantDeactivationTrigger
} from '../power_selection.js';
import {abilitiesForCreature} from '../activated_abilities.js';
import {battleActionPanels} from '../action_economy.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const typed=read('../../vtt/enrichment/benefits/option_grant.json');
const armor=typed.entries.find(e=>e.benefit?.option_grant?.id==='arcane_armor')?.benefit.option_grant;

test('Arcane Armor derives its action from its option grant, without duplicate metadata',()=>{
 assert.ok(armor);
 assert.equal(armor.layers.applied.trigger,'action');
 assert.ok(!Object.hasOwn(armor,'activation_action'));
 assert.equal(armor.title,'Armatura Arcana');
});

function scenario(deactivation='reaction'){
 const grant={id:'test:focus',title:'Focus',owner:{class_name:'Fighter',class_source:'PHB',trait:'Focus'},
  benefit_type:'option_grant',option_kind:'capability',
  source:{type:'inline',options:[{id:'focus',name:'Focus',
   effects:[{type:'bonus',target:'speed',expression:'5'}]}]},
  layers:{applied:{limit:1,trigger:'bonus',...(deactivation?{deactivation_trigger:deactivation}:{})}},
  application:{destination:'origin'}};
 const catalog={optionGrants:{entries:[{granted_by:{ref:{category:'class_feature',name:'Focus',source:'PHB'}},
  benefit:{type:'option_grant',option_grant:grant}}]},optionLists:{entries:[]}};
 const feature={name:'Focus',origin_id:'feature:class|phb|fighter|focus',origin_key:'class|phb|fighter',
  class_name:'Fighter',class_source:'PHB',level:1};
 const record={rules_version:'2014',classes:[{name:'Fighter',source:'PHB',level:1}],
  inventory:[],power_applications:{},power_selections:{}};
 const calculated={features:[feature],trackers:[],attacks:[],spell_slots:[],pact_slots:{}};
 return {record,calculated,catalog};
}
const actionFor=(record,calculated,catalog)=>{
 const models=powerSelectionModels(record,calculated,catalog);
 const abilities=abilitiesForCreature(record,[],{...calculated,power_selections:models});
 return {models,abilities,action:abilities.find(x=>x.option_grant_id==='test:focus')};
};
const actionRow=(record,calculated,abilities)=>{
 const panels=battleActionPanels(record,calculated,[],[],[],[],abilities);
 return new JSDOM(panels.others).window.document.querySelector(
  '[data-attack-id="activated:option-grant-action:test:focus"]');
};

test('application is only allowed through its action; benefits belong to the generated trait',()=>{
 const {record,calculated,catalog}=scenario();
 const {models}=actionFor(record,calculated,catalog);
 assert.equal(optionGrantActionTrigger(models[0]),true);
 assert.equal(optionGrantDeactivationTrigger(models[0]),'reaction');
 assert.throws(()=>powerApplicationPatch(record,calculated,catalog,models[0].id,'focus',true),
  /soltanto usando la sua azione/);
 const applied=powerApplicationPatch(record,calculated,catalog,models[0].id,'focus',true,{viaAction:true});
 assert.deepEqual(applied.power_applications[models[0].id].map(row=>row.id),['focus']);
 const active={...record,...applied};
 const projected=projectSelectionBenefits(active,{powerSelections:catalog},calculated.features);
 assert.equal(projected.selection_traits[0]?.name,'Focus');
 assert.equal(projected.selection_traits[0]?.selection_id,models[0].id);
 assert.throws(()=>powerApplicationPatch(active,calculated,catalog,models[0].id,'focus',true,{viaAction:true}),
  /Disattiva prima/);
 assert.throws(()=>powerApplicationPatch(active,calculated,catalog,models[0].id,'focus',false),
  /soltanto usando la sua azione/);
 const off=powerApplicationPatch(active,calculated,catalog,models[0].id,'focus',false,{viaAction:true});
 assert.deepEqual(off.power_applications[models[0].id],[]);
});

test('the same action changes to Disattiva with its declared deactivation cost',()=>{
 const {record,calculated,catalog}=scenario('reaction');
 const inactive=actionFor(record,calculated,catalog);
 assert.equal(inactive.action.name,'Focus');
 assert.equal(inactive.action.option_grant_active,false);
 assert.equal(inactive.action.action_type,'bonus');
 const initialRow=actionRow(record,calculated,inactive.abilities);
 assert.ok(initialRow,'The option grant action appears among normal actions');
 assert.equal(initialRow.querySelector('.play-battle-attack-copy small')?.textContent,'Azione bonus');
 assert.equal(initialRow.querySelector('.play-action-use-verb')?.textContent,'Usa');

 const applied=powerApplicationPatch(record,calculated,catalog,'test:focus','focus',true,{viaAction:true});
 const activeRecord={...record,...applied};
 const active=actionFor(activeRecord,calculated,catalog);
 assert.equal(active.action.option_grant_active,true);
 assert.equal(active.action.action_type,'reaction');
 const activeRow=actionRow(activeRecord,calculated,active.abilities);
 assert.ok(activeRow);
 assert.equal(activeRow.querySelector('.play-battle-attack-copy small')?.textContent,'Reazione');
 assert.equal(activeRow.querySelector('.play-action-use-verb')?.textContent,'Disattiva');
});

test('deactivation without an explicit trigger defaults to a free action',()=>{
 const {record,calculated,catalog}=scenario(null);
 const applied=powerApplicationPatch(record,calculated,catalog,'test:focus','focus',true,{viaAction:true});
 const activeRecord={...record,...applied};
 const active=actionFor(activeRecord,calculated,catalog);
 assert.equal(optionGrantDeactivationTrigger(active.models[0]),'free');
 assert.equal(active.action.action_type,'free');
 const row=actionRow(activeRecord,calculated,active.abilities);
 assert.equal(row.querySelector('.play-battle-attack-copy small')?.textContent,'Azione gratuita');
 assert.equal(row.querySelector('.play-action-use-verb')?.textContent,'Disattiva');
});

test('a deactivation trigger is permitted only for action-triggered grants',()=>{
 const {record,calculated,catalog}=scenario();
 const grant=catalog.optionGrants.entries[0].benefit.option_grant;
 grant.layers.applied.deactivation_trigger='short_rest';
 assert.throws(()=>powerSelectionModels(record,calculated,catalog),/Trigger di disattivazione non valido/);
 grant.layers.applied.deactivation_trigger='bonus';
 grant.layers.applied.trigger='long_rest';
 assert.throws(()=>powerSelectionModels(record,calculated,catalog),/Trigger di disattivazione non valido/);
});
