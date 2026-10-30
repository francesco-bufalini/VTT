import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {powerSelectionPatch,powerApplicationPatch,powerSelectionModels,projectSelectionBenefits} from '../power_selection.js';
import {requirementsAllow,calculateSheet} from '../sheet_rules.js';
import {classFeatureRollResourceBonuses} from '../feature_mechanics.js';

const optional=JSON.parse(readFileSync(new URL('../catalog/optional_feature_progressions.json',import.meta.url),'utf8'));
const rules=JSON.parse(readFileSync(new URL('../catalog/roll_bonus_rules.json',import.meta.url),'utf8'));
const selections={optionalFeatureProgressions:optional};
const fighterStyleId='optional:class:phb:fighter:fs-f';
const fighterManeuverId='optional:subclass:phb:fighter:phb:battle-master:mv-b';
const styleFeature={name:'Fighting Style',class_name:'Fighter',class_source:'PHB',
 origin_key:'class|phb|fighter',origin_id:'feature:style'};
const maneuverFeature={name:'Maneuvers',class_name:'Fighter',class_source:'PHB',
 origin_key:'class|phb|fighter|subclass|battle master',origin_id:'feature:maneuvers'};
const fighter=(level,subclass='')=>({id:'fighter',rules_version:'2014',class:'Fighter',
 class_source:'PHB',level,classes:[{name:'Fighter',source:'PHB',level,subclass,subclass_source:'PHB'}]});
const chosen=(record,feature,id)=>powerSelectionModels(record,{features:[feature]},selections).find(row=>row.id===id);

test('applied fighting style effects are projected only while active and never become new traits',()=>{
 let record={...fighter(3),inventory:[{id:'mail',name:'Armor',type:'LA',quantity:1,equipped_slots:['body']}]};
 const context={features:[styleFeature]},option='optional:phb:defense';
 record={...record,...powerSelectionPatch(record,context,selections,fighterStyleId,'learned',option)};
 let projected=projectSelectionBenefits(record,selections,context.features);
 assert.equal(projected.formula_bonuses.some(row=>row.expression==='1'&&row.target==='ac'),false);
 record={...record,...powerApplicationPatch(record,context,selections,fighterStyleId,option,true)};
 projected=projectSelectionBenefits(record,selections,context.features);
 const bonus=projected.formula_bonuses.find(row=>row.target==='ac'&&row.selection_origin_id===fighterStyleId);
 assert(bonus);
 assert.equal(requirementsAllow(projected,bonus),true);
 assert.equal(requirementsAllow({...projected,inventory:[]},bonus),false);
 assert(!projected.optional_features_catalog.some(row=>row.name==='Defense'&&!row.selection_origin_id));
 assert.equal(chosen(record,styleFeature,fighterStyleId).layers.learned.used,1);
 record={...record,...powerApplicationPatch(record,context,selections,fighterStyleId,option,false)};
 assert(!projectSelectionBenefits(record,selections,context.features).formula_bonuses.some(row=>row.selection_origin_id===fighterStyleId));
 assert.equal(chosen(record,styleFeature,fighterStyleId).layers.learned.used,1);
});

test('fighting styles declare typed weapon-scoped, sensory and unarmed alternatives',()=>{
 const by=id=>optional.options.find(row=>row.id==='optional:'+id)?.effects||[];
 assert.deepEqual(by('phb:archery')[0].attack_filter,{weapon_mode:'ranged'});
 assert.deepEqual(by('phb:dueling')[0].attack_filter,{weapon_mode:'melee',one_handed:true,no_other_weapon:true});
 assert.deepEqual(by('tce:thrown-weapon-fighting')[0].attack_filter,{weapon_mode:'thrown'});
 assert.deepEqual(by('tce:blind-fighting')[0].data,{type:'blindsight',range_feet:10});
 const overrides=by('tce:unarmed-fighting');
 assert.deepEqual(overrides.map(row=>row.expression),['1d6','1d8']);
 assert.equal(overrides[1].no_weapon_or_shield,true);
});

test('Battle Master maneuver bonuses are gated to chosen options and scale with Fighter level',()=>{
 const selected='optional:phb:precision-attack';
 for(const [level,expectedDie] of [[3,'1d8'],[10,'1d10'],[18,'1d12']]){
  let record=fighter(level,'Battle Master'),context={features:[maneuverFeature]};
  const calculate=()=>({features:context.features,roll_bonus_rules:rules.features,
   trackers:[{id:'superiority',name:'Superiority Dice',max:4,spent:0}],
   selection_models:powerSelectionModels(record,context,selections),values:{proficiency:2}});
  assert(!classFeatureRollResourceBonuses(record,calculate()).some(row=>row.name==='Precision Attack'));
  record={...record,...powerSelectionPatch(record,context,selections,fighterManeuverId,'learned',selected)};
  const active=calculate();
  const bonus=classFeatureRollResourceBonuses(record,active).find(row=>row.name==='Precision Attack');
  assert(bonus,'selected maneuver should expose a contextual roll bonus');
  assert.equal(bonus.dice,expectedDie);
  assert.equal(bonus.tracker_id,'superiority');
  assert.equal(bonus.tracker_cost,1);
  assert.deepEqual(bonus.targets,['attack_roll']);
  assert(!classFeatureRollResourceBonuses(record,active).some(row=>row.name==='Trip Attack'));
  record={...record,...powerSelectionPatch(record,context,selections,fighterManeuverId,'learned',selected)};
  assert(!classFeatureRollResourceBonuses(record,calculate()).some(row=>row.name==='Precision Attack'));
 }
});

test('a selected Feinting Attack exposes contextual advantage, not unconditional roll mode',()=>{
 let record=fighter(3,'Battle Master'),context={features:[maneuverFeature]};
 record={...record,...powerSelectionPatch(record,context,selections,fighterManeuverId,'learned','optional:phb:feinting-attack')};
 const calculated={features:context.features,roll_bonus_rules:rules.features,
  trackers:[{id:'superiority',name:'Superiority Dice',max:4,spent:0}],
  selection_models:powerSelectionModels(record,context,selections),values:{proficiency:2}};
 const advantage=classFeatureRollResourceBonuses(record,calculated).find(row=>row.name==='Feinting Attack');
 assert.equal(advantage.roll_mode,'advantage');
 assert.equal(advantage.tracker_cost,1);
 assert.deepEqual(advantage.targets,['attack_roll']);
});

const full=()=>({optionalFeatureProgressions:optional,powerSelections:{selections:[],templates:[]},
 classFeatures:JSON.parse(readFileSync(new URL('../catalog/classes.json',import.meta.url),'utf8')),
 classMechanics:JSON.parse(readFileSync(new URL('../catalog/class_mechanics.json',import.meta.url),'utf8')),
 abilityGrants:JSON.parse(readFileSync(new URL('../catalog/ability_grants.json',import.meta.url),'utf8')),
 proficiencyGrants:JSON.parse(readFileSync(new URL('../catalog/proficiency_grants.json',import.meta.url),'utf8')),
 traitStates:JSON.parse(readFileSync(new URL('../catalog/trait_states.json',import.meta.url),'utf8')).states});
const weapon=(id,type,properties=[])=>({id,name:id,type,custom_item_type:'weapon',weapon_category:'martial',
 damage:'1d8',quantity:1,properties,range:type==='R'?'150/600':'20/60',equipped_slots:['main']});
const play=(inventory)=>({...fighter(3),abilities:{str:16,dex:16,con:14,int:10,wis:12,cha:10},inventory});
const withStyle=(record,catalog,option)=>{
 let sheet=calculateSheet(record,catalog);
 assert(sheet.selection_models.some(model=>model.id===fighterStyleId),'Fighting Style owner must be present');
 record={...record,...powerSelectionPatch(record,sheet,selections,fighterStyleId,'learned',option)};
 sheet=calculateSheet(record,catalog);
 record={...record,...powerApplicationPatch(record,sheet,selections,fighterStyleId,option,true)};
 return calculateSheet(record,catalog);
};
test('applied styles change real ranged/melee/thrown hits and damage without affecting unrelated attacks',()=>{
 const catalog=full();
 const bow=play([weapon('bow','R',['2H'])]);
 const baseBow=calculateSheet(bow,catalog),archery=withStyle(bow,catalog,'optional:phb:archery');
 assert.equal(archery.attacks.find(a=>a.id==='item:bow').hit-baseBow.attacks.find(a=>a.id==='item:bow').hit,2);
 const sword=play([weapon('sword','M')]);
 const baseSword=calculateSheet(sword,catalog),dueling=withStyle(sword,catalog,'optional:phb:dueling');
 assert.equal(dueling.attacks.find(a=>a.id==='item:sword').damage_extra_modifier-
  baseSword.attacks.find(a=>a.id==='item:sword').damage_extra_modifier,2);
 const swordAndOff=play([weapon('sword','M'),{...weapon('dagger','M',['F','T']),equipped_slots:['off']}]);
 const blocked=withStyle(swordAndOff,catalog,'optional:phb:dueling');
 const blockedBase=calculateSheet(swordAndOff,catalog);
 assert.equal(blocked.attacks.find(a=>a.id==='item:sword').damage_extra_modifier,
  blockedBase.attacks.find(a=>a.id==='item:sword').damage_extra_modifier);
 const spear=play([weapon('spear','M',['T'])]);
 const baseSpear=calculateSheet(spear,catalog),thrown=withStyle(spear,catalog,'optional:tce:thrown-weapon-fighting');
 assert.equal(thrown.attacks.find(a=>a.id==='item:throw:main:spear').damage_extra_modifier-
  baseSpear.attacks.find(a=>a.id==='item:throw:main:spear').damage_extra_modifier,2);
 assert.equal(thrown.attacks.find(a=>a.id==='item:spear').damage_extra_modifier,
  baseSpear.attacks.find(a=>a.id==='item:spear').damage_extra_modifier);
});
test('passive defense, sight and unarmed base alternatives are reflected in sheet calculations',()=>{
 const catalog=full(),armor={id:'leather',name:'Leather armor',type:'LA',quantity:1,ac:11,equipped_slots:['body']};
 const worn=play([armor]),base=calculateSheet(worn,catalog),defense=withStyle(worn,catalog,'optional:phb:defense');
 assert.equal(defense.values.ac-base.values.ac,1);
 const blind=withStyle(play([]),catalog,'optional:tce:blind-fighting');
 assert.equal(blind.senses.distances.blindsight,10);
 const fists=withStyle(play([]),catalog,'optional:tce:unarmed-fighting');
 assert.equal(fists.attacks.find(row=>row.id==='unarmed').damage_base_formula,'1d8');
 const armed=withStyle(play([weapon('sword','M')]),catalog,'optional:tce:unarmed-fighting');
 assert.equal(armed.attacks.find(row=>row.id==='unarmed').damage_base_formula,'1d6');
});
