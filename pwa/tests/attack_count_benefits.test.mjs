import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {collectStructuredFeatures} from '../structured_effects.js';
import {attackCountBenefits,attacksPerActionFromBenefits} from '../attack_count_benefits.js';
import {addBenefitPatch,removeBenefitPatch,restoreBenefitPatch} from '../trait_benefit_editor.js';
import {traitBenefitGroups} from '../trait_benefits.js';
import {attacksPerAction} from '../action_economy.js';

const featureRules=JSON.parse(readFileSync(new URL('../../vtt/data/feature_timing_recovery_rules.json',import.meta.url),'utf8'));
const classFeatures={class_features:[
 {class_name:'Fighter',class_source:'PHB',level:5,name:'Extra Attack'},
 {class_name:'Fighter',class_source:'PHB',level:11,name:'Extra Attack (2)'},
 {class_name:'Fighter',class_source:'PHB',level:20,name:'Extra Attack (3)'},
 {class_name:'Barbarian',class_source:'PHB',level:5,name:'Extra Attack'},
 {class_name:'Fighter',class_source:'XPHB',level:5,name:'Extra Attack'},
 {class_name:'Warlock',class_source:'XPHB',level:12,name:'Devouring Blade'}
 ],subclass_features:[
 {class_name:'Artificer',class_source:'TCE',subclass_name:'Battle Smith',level:5,name:'Extra Attack'},
 {class_name:'Bard',class_source:'PHB',subclass_name:'College of Valor',level:6,name:'Extra Attack'}
 ]};
const project=record=>collectStructuredFeatures(record,{classFeatures,featureRules});
const evaluate=record=>{
 const features=project(record),benefits=attackCountBenefits(record,features);
 return {features,benefits,count:attacksPerActionFromBenefits(benefits)};
};

test('class and subclass catalogs grant typed attack counts on their specific traits',()=>{
 const fighter=evaluate({classes:[{name:'Fighter',source:'PHB',level:20}]});
 assert.deepEqual(fighter.features.map(f=>[f.name,f.attacks_per_action]),[
  ['Extra Attack',2],['Extra Attack (2)',3],['Extra Attack (3)',4]]);
 assert.equal(fighter.count,4);
 assert.equal(fighter.benefits.length,3,'All contributing features retain their own benefit');
 assert(fighter.benefits.every(row=>row.origin_id.startsWith('feature:class|phb|fighter')));
 const artificer=evaluate({classes:[{name:'Artificer',source:'TCE',level:5,subclass:'Battle Smith'}]});
 assert.equal(artificer.count,2);
 const bard=evaluate({classes:[{name:'Bard',source:'PHB',level:6,subclass:'College of Valor'}]});
 assert.equal(bard.count,2);
 assert.equal(evaluate({classes:[{name:'Bard',source:'PHB',level:6}]}).count,1,
  'Subclass benefits never spill into another or the base class');
 assert.equal(evaluate({classes:[{name:'Warlock',source:'XPHB',level:12}]}).count,3);
});

test('multiclass, disabled traits and removed benefits choose the highest active grant',()=>{
 const record={classes:[{name:'Fighter',source:'PHB',level:11},{name:'Barbarian',source:'PHB',level:5}]};
 const computed=evaluate(record);
 assert.deepEqual(computed.benefits.map(row=>row.attacks_per_action).sort(),[2,2,3]);
 assert.equal(computed.count,3,'Extra Attack 3 and Extra Attack 2 do not add or multiply');
 const best=computed.features.find(f=>f.name==='Extra Attack (2)');
 const trait={key:best.key,feature_origin:best.origin_id,origin_key:best.origin_key};
 assert.equal(evaluate({...record,trait_enabled:{[best.key]:false}}).count,2);
 assert.equal(evaluate({...record,origin_enabled:{[best.origin_key]:false}}).count,2,
  'Disabling one class origin leaves a separately owned class feature');
 const suppress=removeBenefitPatch(record,trait,{type:'attack_count',id:'attack_count:feature:'+best.origin_id});
 assert.equal(evaluate({...record,...suppress}).count,2);
 const restored=restoreBenefitPatch({...record,...suppress},trait);
 assert.equal(evaluate({...record,...restored}).count,3);
});

test('custom trait benefits can be added, displayed, removed and do not stack',()=>{
 const trait={key:'custom|blade|trait',origin_key:'custom|blade',name:'Velocità di combattimento'};
 const record={attack_count_grants:[]};
 const created=addBenefitPatch(record,trait,'attack_count',{attacks_per_action:'5'},'trait:attack-count-0001');
 const active={...record,...created};
 const grants=attackCountBenefits(active,[]);
 assert.equal(attacksPerActionFromBenefits(grants),5);
 const groups=traitBenefitGroups(trait,active,{attack_count_benefits:grants});
 assert.deepEqual(groups.map(g=>g.type),['attack_count']);
 assert.deepEqual(groups[0].items.map(i=>[i.label,i.value]),[['Attacchi disponibili','×5']]);
 assert.equal(groups[0].items[0].id,'attack_count:trait:attack-count-0001');
 const removed=removeBenefitPatch(active,trait,{type:'attack_count',id:groups[0].items[0].id});
 assert.deepEqual(removed.attack_count_grants,[]);
 assert.equal(attacksPerActionFromBenefits(attackCountBenefits({...active,...removed},[])),1);
 assert.equal(attacksPerActionFromBenefits(attackCountBenefits({...active,trait_enabled:{[trait.key]:false}},[])),1);
 assert.throws(()=>addBenefitPatch(record,trait,'attack_count',{attacks_per_action:0},'trait:attack-count-0002'),/non valido/);
 assert.throws(()=>addBenefitPatch(record,trait,'attack_count',{attacks_per_action:'2.5'},'trait:attack-count-0003'),/non valido/);
 const doubled={...active,attack_count_grants:[...active.attack_count_grants,
  {...active.attack_count_grants[0],id:'trait:attack-count-0002',attacks_per_action:2}]};
 assert.equal(attacksPerAction(doubled,{}),5);
});

test('old monster multiattack is projected into a trait benefit; typed count takes precedence',()=>{
 const record={kind:'monster',stat_block:{action:[{name:'Multiattack',entries:[
  'The dragon makes three attacks: one with its bite and two with its claws.'
 ]}]}};
 const first=evaluate(record);
 assert.equal(first.count,3);
 assert.equal(first.benefits.length,1);
 assert.equal(first.benefits[0].origin_id,first.features[0].origin_id);
 const typed=evaluate({...record,stat_block:{action:[{name:'Multiattack',attacks_per_action:4,entries:['Three attacks.'] }]}});
 assert.equal(typed.count,4);
});
