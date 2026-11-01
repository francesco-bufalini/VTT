import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {powerSelectionModels,powerSelectionPatch,powerApplicationPatch,projectSelectionBenefits} from '../power_selection.js';
import {resolveSpellSlotProfile} from '../spell_slot_profiles.js';
import {spellProgression} from '../sheet_rules.js';
import {collectTraitRows} from '../trait_projection.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const rules=read('../../vtt/enrichment/benefits/option_grant.json');
const optional=read('../catalog/optional_feature_progressions.json');
const old=read('../catalog/power_selections.json');
const source={...old,optionGrants:rules,optionalFeatureProgressions:optional};
const owner={class_name:'Ranger',class_source:'PHB',trait:'Favored Enemy'};
const feature={name:'Favored Enemy',origin_id:'feature:choice',origin_key:'class|phb|ranger',
 requirements:{class_name:'Ranger',class_source:'PHB'}};
const basis=()=>({kind:'character',id:'tester',rules_version:'2014',class:'Ranger',class_source:'PHB',
 level:6,classes:[{name:'Ranger',source:'PHB',level:6}],inventory:[]});
const context={features:[feature]};

function customCatalog(layers={learned:{limit:2},applied:{limit:1}}){
 const rule={id:'test:grant',owner,benefit_type:'option_grant',option_kind:'capability',
  source:{type:'list_refs',list_ids:['home:shared']},layers,application:{destination:'origin'}};
 return {...source,optionGrants:{entries:[{
  id:'benefit:test',granted_by:{kind:'homebrew',namespace:'test',ref:{category:'feat',id:'test'}},
  benefit:{type:'option_grant',id:'test:grant',option_grant:rule}
 }]},optionLists:{entries:[{
  id:'list:shared',benefit:{type:'option_list',id:'home:shared',option_list:{
   id:'home:shared',kind:'capability',options:[{id:'test:passive',name:'Aura di prova',
    description:'Tratto, non azione.',effects:[{type:'bonus',target:'ac',expression:'1'}]}]}}
 }]}};
}

test('class and subclass grants preserve source identifiers and declare only one selection mechanism',()=>{
 assert.equal(rules.benefit_type,'option_grant');
 assert.equal(rules.entries.length,41);
 assert.equal(new Set(rules.entries.map(row=>row.id)).size,rules.entries.length);
 assert(rules.entries.every(row=>row.granted_by?.kind==='5etools'&&row.granted_by.ref.class_source));
 assert(rules.entries.every(row=>row.benefit.type==='option_grant'));
 const ranger=powerSelectionModels(basis(),context,source).find(row=>row.id==='ranger_favored_enemy_phb');
 assert.equal(ranger.benefit_type,'option_grant');
 assert.equal(ranger.layers.learned.limit,2);
 assert.equal(ranger.options.length>0,true);
});

test('reusable typed list produces a passive state trait and removes all derived effects when unapplied',async()=>{
 const catalog=customCatalog(),id='test:grant',option='test:passive';
 let record=basis();
 assert.deepEqual(powerSelectionModels(record,context,catalog)[0].options.map(o=>o.id),[option]);
 assert.throws(()=>powerApplicationPatch(record,context,catalog,id,option,true),/prima imparare/);
 record={...record,...powerSelectionPatch(record,context,catalog,id,'learned',option)};
 record={...record,...powerApplicationPatch(record,context,catalog,id,option,true)};
 let calculated=projectSelectionBenefits(record,{powerSelections:catalog},context.features);
 assert.equal(calculated.selection_traits.length,1);
 assert.equal(calculated.selection_traits[0].name,'Aura di prova');
 assert.equal(calculated.formula_bonuses.filter(row=>row.selection_origin_id===id).length,1);
 const traits=await collectTraitRows(record,{selection_traits:calculated.selection_traits,features:[]},
  {entries:async()=>[]});
 assert(traits.some(trait=>trait.category==='stati'&&trait.name==='Aura di prova'));
 record={...record,...powerApplicationPatch(record,context,catalog,id,option,false)};
 calculated=projectSelectionBenefits(record,{powerSelections:catalog},context.features);
 assert.equal(calculated.selection_traits.length,0);
 assert.equal(calculated.formula_bonuses.filter(row=>row.selection_origin_id===id).length,0);
});

test('selection phases are optional, hierarchical and stage triggers remain separate',()=>{
 const catalog=customCatalog({
  learned:{limit:2,trigger:'level_up'},prepared:{limit:1,trigger:'long_rest'},
  applied:{limit:1,trigger:['short_rest','long_rest']}
 });
 let record=basis(),id='test:grant',option='test:passive';
 let model=powerSelectionModels(record,context,catalog)[0];
 assert.deepEqual(Object.keys(model.layers),['learned','prepared','applied']);
 assert.deepEqual(model.layers.applied.trigger,['short_rest','long_rest']);
 assert.throws(()=>powerSelectionPatch(record,context,catalog,id,'prepared',option),/prima imparare/);
 record={...record,...powerSelectionPatch(record,context,catalog,id,'learned',option)};
 assert.throws(()=>powerApplicationPatch(record,context,catalog,id,option,true),/prima preparare/);
 record={...record,...powerSelectionPatch(record,context,catalog,id,'prepared',option)};
 record={...record,...powerApplicationPatch(record,context,catalog,id,option,true)};
 assert.equal(powerSelectionModels(record,context,catalog)[0].layers.applied.selected.length,1);
});

test('slot profiles are generic and multiclass pools are resolved in the engine',()=>{
 assert.deepEqual(resolveSpellSlotProfile({profile:'half_caster_up'}).pool,'shared');
 const multi=spellProgression({},[
  {level:5,slot_progression:{profile:'full_caster'}},
  {level:4,slot_progression:{profile:'half_caster_down'}},
  {level:3,slot_progression:{profile:'pact_magic'}}
 ]);
 assert.equal(multi.caster_level,7);
 assert.equal(multi.pact_total,2);
 assert.equal(multi.pact_level,2);
 assert.deepEqual(multi.slots.slice(1,5),[4,3,3,1]);
});
