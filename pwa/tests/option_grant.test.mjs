import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {powerSelectionModels,powerSelectionPatch,powerApplicationPatch,projectSelectionBenefits} from '../power_selection.js';
import {resolveSpellSlotProfile} from '../spell_slot_profiles.js';
import {spellProgression} from '../sheet_rules.js';
import {collectTraitRows} from '../trait_projection.js';
import {traitBenefitGroups} from '../trait_benefits.js';

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
 const state=traits.find(trait=>trait.category==='stati'&&trait.name==='Aura di prova');
 assert(state);
 assert.equal(state.benefits.length,1);
 assert.equal(state.grant_origin_id,'feature:choice');
 const stateGroups=traitBenefitGroups(state,calculated,
  {bonuses:calculated.formula_bonuses});
 assert.equal(stateGroups.find(g=>g.type==='bonus')?.items.length,1,
  'The applied capability owns its benefit in States');
 const sourceGroups=traitBenefitGroups({name:'Favored Enemy',feature_origin:'feature:choice',rank:2},
  calculated,{bonuses:calculated.formula_bonuses});
 assert.equal(sourceGroups.some(g=>g.type==='bonus'),false,
  'The grantor must not duplicate the selected capability benefits');
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

test('a homebrew trait can grant fixed passive choices with no selection stages',()=>{
 const catalog=customCatalog({});
 const trait=catalog.optionGrants.entries[0].benefit.option_grant;
 trait.owner={trait:'Homebrew Aura'};
 trait.fixed=['test:passive'];
 let record={kind:'character',id:'homebrew',rules_version:'2014',level:3,inventory:[]};
 const feature={name:'Homebrew Aura',source:'HOMEBREW',origin_id:'feat:homebrew-aura'};
 const calculated={features:[feature]};
 const model=powerSelectionModels(record,calculated,catalog)[0];
 assert.deepEqual(Object.keys(model.layers),[]);
 assert.deepEqual(model.fixed,['test:passive']);
 const projected=projectSelectionBenefits(record,{powerSelections:catalog},[feature]);
 assert.equal(projected.selection_traits.length,1);
 assert.equal(projected.formula_bonuses.length,1);
 const without=projectSelectionBenefits(record,{powerSelections:catalog},[]);
 assert.equal(without.selection_traits.length,0,'Lost source feature removes the derived trait');
});

test('spell option grant selects and casts through a separate canonical grant origin',()=>{
 const catalog=customCatalog({learned:{limit:2},prepared:{limit:1}});
 const rule=catalog.optionGrants.entries[0].benefit.option_grant;
 rule.option_kind='spell';
 rule.source={type:'inline',options:[{id:'spell:shield|phb',name:'Shield',level:1}]};
 rule.payment={tracker:{id:'arcane_charge',cost:1,cast_level:3},slot:{min_level:2}};
 let record=basis();
 let model=powerSelectionModels(record,context,catalog)[0];
 assert.equal(model.option_kind,'spell');
 assert.deepEqual(Object.keys(model.layers),['learned','prepared']);
 record={...record,...powerSelectionPatch(record,context,catalog,model.id,'learned','spell:shield|phb')};
 let unprepared=projectSelectionBenefits(record,{powerSelections:catalog},context.features);
 assert.equal(unprepared.origin_spell_grants.length,0);
 record={...record,...powerSelectionPatch(record,context,catalog,model.id,'prepared','spell:shield|phb')};
 let projection=projectSelectionBenefits(record,{powerSelections:catalog},context.features);
 const grant=projection.origin_spell_grants[0];
 assert.equal(grant.spell_id,'spell:shield|phb');
 assert.equal(grant.payment_mode,'tracker');
 assert.equal(grant.slot_alternative,true);
 assert.equal(grant.tracker_cast_level,3);
 assert.equal(grant.slot_min_level,2);
 assert.equal(grant.option_grant_id,model.id);
 record={...record,...powerSelectionPatch(record,context,catalog,model.id,'prepared','spell:shield|phb')};
 projection=projectSelectionBenefits(record,{powerSelections:catalog},context.features);
 assert.equal(projection.origin_spell_grants.length,0,'Removing preparation removes spell grant');
});

test('spell grants with applied stage cannot be cast until activated',()=>{
 const catalog=customCatalog({learned:{limit:1},applied:{limit:1}});
 const rule=catalog.optionGrants.entries[0].benefit.option_grant;
 rule.option_kind='spell';rule.source={type:'inline',options:[{id:'spell:shield|phb',level:1,name:'Shield'}]};
 let record=basis();const id=rule.id,option='spell:shield|phb';
 record={...record,...powerSelectionPatch(record,context,catalog,id,'learned',option)};
 let projection=projectSelectionBenefits(record,{powerSelections:catalog},context.features);
 assert.equal(projection.origin_spell_grants.length,0,'Known but unapplied spells are not castable');
 record={...record,...powerApplicationPatch(record,context,catalog,id,option,true)};
 projection=projectSelectionBenefits(record,{powerSelections:catalog},context.features);
 assert.equal(projection.origin_spell_grants.length,1);
 record={...record,...powerApplicationPatch(record,context,catalog,id,option,false)};
 projection=projectSelectionBenefits(record,{powerSelections:catalog},context.features);
 assert.equal(projection.origin_spell_grants.length,0);
});

test('multiple Metamagic feature instances have their own selection boxes and retain legacy choices',()=>{
 for(const [sourceCode,version,levels,limits] of [
  ['PHB','2014',[3,10,17],[2,1,1]],['XPHB','2024',[2,10,17],[2,2,2]]
 ]){
  const ruleId='optional:class:'+sourceCode.toLowerCase()+':sorcerer:mm';
  const record={kind:'character',rules_version:version,level:17,
   classes:[{name:'Sorcerer',source:sourceCode,level:17}],inventory:[]};
  const features=levels.map(level=>({name:'Metamagic',level,
   class_name:'Sorcerer',class_source:sourceCode,
   origin_key:'class|'+sourceCode.toLowerCase()+'|sorcerer',
   origin_id:'feature:metamagic:'+level,key:'metamagic:'+level}));
  const catalog={...source,optionalFeatureProgressions:optional};
  const models=powerSelectionModels(record,{features},catalog).filter(row=>row.id.startsWith(ruleId));
  assert.deepEqual(models.map(m=>m.id),[ruleId,ruleId+':level:10',ruleId+':level:17']);
  assert.deepEqual(models.map(m=>m.layers.learned.limit),limits);
  assert.deepEqual(models.map(m=>m.origin_id),features.map(f=>f.origin_id));
  const ids=models[0].options.slice(0,limits.reduce((a,b)=>a+b,0)).map(o=>o.id);
  assert.equal(ids.length,limits.reduce((a,b)=>a+b,0));
  const stored={...record,power_selections:{[ruleId]:{learned:ids}}};
  const migrated=powerSelectionModels(stored,{features},catalog).filter(m=>m.id.startsWith(ruleId));
  assert.deepEqual(migrated.map(m=>m.layers.learned.used),limits);
  assert.deepEqual(migrated.flatMap(m=>m.layers.learned.selected),ids);
  const projected=projectSelectionBenefits(stored,{powerSelections:catalog},features);
  assert.equal(projected.selection_traits.length,ids.length);
  const allIds=projected.selection_traits.map(t=>t.selection_id);
  assert.deepEqual(allIds.sort(),models.flatMap((m,i)=>Array.from({length:limits[i]},()=>m.id)).sort());
  const narrowed=powerSelectionModels(stored,{features:[features[1],features[2]]},catalog)
   .filter(m=>m.id.startsWith(ruleId));
  assert.deepEqual(narrowed.map(m=>m.id),[ruleId+':level:10',ruleId+':level:17']);
  assert.deepEqual(narrowed.map(m=>m.layers.learned.limit),limits.slice(1));
  const firstChoice=ids[0];
  let selected=record;
  selected={...selected,...powerSelectionPatch(selected,{features},catalog,ruleId,'learned',firstChoice)};
  assert.throws(()=>powerSelectionPatch(selected,{features},catalog,
    ruleId+':level:10','learned',firstChoice),/già scelta/);

 }
});
