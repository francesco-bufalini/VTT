import {test} from 'node:test';
import assert from 'node:assert/strict';
import {calculateSheet} from '../sheet_rules.js';
import {initialCreature} from '../character_core.js';
import {sheetRollOriginSegments,sheetRollOriginHtml} from '../sheet_roll_origin.js';
import {classFeatureRollSources,resolveClassRollMode,classFeatureRollAdvantage} from '../feature_mechanics.js';
import {rollSheetDice} from '../sheet_rules_view.js';

function character(){
 const c=initialCreature('character','Guerriero','origin-test','local');
 return {...c,level:1,classes:[{name:'Barbarian',source:'PHB',level:1}],
   abilities:{str:18,dex:16,con:12,int:10,wis:10,cha:10},
   proficiency_choices:[{kind:'skill',key:'athletics',origin_id:'class|phb|barbarian',
     origin_name:'Barbarian',disabled:false}],
   inventory:[{id:'stone-of-good-luck',name:'Stone of Good Luck',quantity:1,
     req_attune:true,attuned:true,equipped:true,bonus_ability_check:1,bonus_saving_throw:1}],
   formula_bonuses:[{id:'feature-dex',target:'skill:athletics',expression:'dex_mod',
     origin_id:'feature:privilegio-a',origin_name:'PRIVILEGIO A'}]};
}
test('full athletic roll separates base, proficiency, category item and symbolic feature terms',()=>{
 const c=character(),calculated=calculateSheet(c);
 assert.equal(calculated.values['skill:athletics'],10);
 const terms=sheetRollOriginSegments(c,calculated,'skill:athletics',{mode:'advantage',
   modeSources:[{mode:'advantage',origin_id:'feature:rage',origin_name:'Ira'}]});
 assert.equal(terms[0].formula,'ADV');
 assert.equal(terms[1].formula,'1d20 + Mod.FOR');
 assert.equal(terms[1].expanded,'1d20 +4');
 assert.equal(terms[2].formula,'+Mod.Competenza');
 assert.equal(terms[2].expanded,'+2');
 assert.equal(terms[2].originId,'class|phb|barbarian');
 const stone=terms.find(t=>t.originId==='item:stone-of-good-luck');
 assert.ok(stone);assert.equal(stone.expanded,'+1');
 const feature=terms.find(t=>t.originId==='feature:privilegio-a');
 assert.ok(feature);assert.equal(feature.formula,'+Mod.DES');
 assert.equal(feature.expanded,'+3');
 assert.equal(terms.filter(t=>t.value!==undefined).reduce((sum,t)=>sum+t.value,0),
   calculated.values['skill:athletics']);
 const html=sheetRollOriginHtml(terms,x=>x);
 assert.match(html,/data-act="roll-origin-open"/);
 assert.match(html,/PRIVILEGIO A/);
 assert.doesNotMatch(html,/Calcolo del modificatore|Origini e bonus applicati/);
});
test('saving throw draws item saving_throw category but not ability_check',()=>{
 const c=character(),calculated=calculateSheet(c);
 const terms=sheetRollOriginSegments(c,calculated,'save:dex');
 assert.equal(terms.filter(t=>t.originId==='item:stone-of-good-luck').length,1);
 assert.equal(terms.reduce((sum,t)=>sum+(t.value||0),0),calculated.values['save:dex']);
});
test('initiative draws ability check item once, manual disadvantage and a dice grant',()=>{
 const c=character(),calculated=calculateSheet(c);
 const terms=sheetRollOriginSegments(c,calculated,'initiative',{mode:'disadvantage',
   diceBonuses:[{dice:'1d4',origin_id:'feature:bless',origin_name:'Bless'}]});
 assert.equal(terms[0].formula,'DIS');
 assert.equal(terms[0].expanded,'');
 assert.doesNotMatch(sheetRollOriginHtml(terms,x=>x),/2d20kh1|2d20kl1/);
 assert.equal(terms.filter(t=>t.originId==='item:stone-of-good-luck').length,1);
 assert.equal(terms.at(-1).formula,'+1d4');
 assert.equal(terms.at(-1).originId,'feature:bless');
});
test('changes to ability scores and ability modifiers remain independently attributable',()=>{
 const c={...character(),formula_bonuses:[
   {id:'score',target:'ability:str',expression:'2',origin_id:'feature:score',origin_name:'Punteggio'},
   {id:'mod',target:'ability_mod:str',expression:'1',origin_id:'feature:mod',origin_name:'Modificatore'}
 ]};
 const calculated=calculateSheet(c);
 const terms=sheetRollOriginSegments(c,calculated,'skill:athletics');
 assert.equal(terms.find(t=>t.originId==='feature:score')?.expanded,'+1');
 assert.equal(terms.find(t=>t.originId==='feature:mod')?.expanded,'+1');
 assert.equal(terms.reduce((sum,t)=>sum+(t.value||0),0),calculated.values['skill:athletics']);
});

test('spell attacks show casting modifier, proficiency and spell attack grants separately',()=>{
 const c=character(),calculated=calculateSheet(c);
 const terms=sheetRollOriginSegments(c,calculated,'casting_hit:str');
 assert.equal(terms[0].formula,'1d20 + Mod.FOR');
 assert.equal(terms.find(t=>t.kind==='training')?.expanded,'+2');
 assert.equal(terms.reduce((sum,t)=>sum+(t.value||0),0),calculated.values['casting_hit:str']);
});
test('weapon hit rolls preserve ability and proficiency without folding them into base',()=>{
 const c=character(),calculated={values:{'attack_hit:main':6,proficiency:2},
   attacks:[{id:'main',ability:'str',proficient:true}],proficiencies:[],
   roll_components:{}};
 const terms=sheetRollOriginSegments(c,calculated,'attack_hit:main');
 assert.equal(terms[0].formula,'1d20 + Mod.FOR');
 assert.equal(terms[0].expanded,'1d20 +4');
 assert.equal(terms.find(t=>t.kind==='training')?.expanded,'+2');
 assert.equal(terms.reduce((sum,t)=>sum+(t.value||0),0),6);
});

test('selected bonus dice merge into the same granting feature box',()=>{
 const c={...character(),dice_bonuses:[]};
 c.formula_bonuses=[
   {id:'first',target:'skill:athletics',expression:'1',origin_id:'feature:bless',origin_name:'Bless'},
   {id:'second',target:'skill:athletics',expression:'2',origin_id:'feature:bless',origin_name:'Bless'}];
 const calculated=calculateSheet(c);
 const terms=sheetRollOriginSegments(c,calculated,'skill:athletics',{
   diceBonuses:[{origin_id:'feature:bless',origin_name:'Bless',dice:'2d4'}]});
 const featureTerms=terms.filter(t=>t.originId==='feature:bless');
 assert.equal(featureTerms.length,1,'Each source must appear only once');
 assert.equal(featureTerms[0].formula,'+1 +2 +2d4');
 assert.equal(featureTerms[0].expanded,'+1 +2 +2d4');
 assert.equal(terms.reduce((sum,t)=>sum+(t.value||0),0),calculated.values['skill:athletics']);
});
test('an unexplained non-base modifier is never silently attributed to standard ability rules',()=>{
 const c=character(),calc=calculateSheet(c);
 const patched={...calc,values:{...calc.values,'skill:athletics':calc.values['skill:athletics']+5}};
 const terms=sheetRollOriginSegments(c,patched,'skill:athletics');
 assert.equal(terms.find(t=>t.kind==='base').expanded,'1d20 +4');
 assert.equal(terms.find(t=>t.kind==='rules').expanded,'+5');
});
test('the automatic Rage advantage segment is named Ira without an extra dice formula',()=>{
 const c=character(),calc=calculateSheet(c);
 const terms=sheetRollOriginSegments(c,calc,'skill:athletics',{mode:'advantage',
   modeSources:[{mode:'advantage',origin_id:'feature:rage',origin_name:'Ira'}]});
 assert.equal(terms[0].formula,'ADV');
 assert.equal(terms[0].originName,'Ira');
 assert.equal(terms[0].expanded,'');
});

test('two advantages never stack, and one disadvantage cancels both; the preview shows every origin',()=>{
 const c={...character(),active_class_features:{rage:{}},conditions:['poisoned']};
 const calc=calculateSheet(c);
 const fixtures=[
   {name:'Rage',origin_key:'class|phb|barbarian',origin_id:'feature:rage',class_name:'Barbarian',
     roll_modes:[{mode:'advantage',target:'skill:athletics'}]},
   {name:'Vigore arcano',origin_key:'class|phb|barbarian',origin_id:'feature:arcane',
     roll_modes:[{mode:'advantage',targets:['ability_check','skill:athletics']}]},
 ];
 const calculated={...calc,features:fixtures};
 const sources=classFeatureRollSources(c,calculated,'skill:athletics');
 assert.deepEqual(sources.filter(r=>r.mode==='advantage').map(r=>r.origin_name),
   ['Ira','Tratto · Vigore arcano']);
 assert.equal(sources.filter(r=>r.mode==='disadvantage').length,1);
 const state=resolveClassRollMode(sources);
 assert.equal(state.mode,'normal');
 assert.equal(state.cancelled,true);
 assert.equal(classFeatureRollAdvantage(c,calculated,'skill:athletics'),false);
 const segments=sheetRollOriginSegments(c,calculated,'skill:athletics',
   {mode:state.mode,modeSources:state.sources,cancelled:state.cancelled});
 assert.deepEqual(segments.slice(0,3).map(row=>row.formula),['ADV','ADV','DIS']);
 assert(segments.slice(0,3).every(row=>row.expanded==='Annullato'));
 assert.deepEqual(segments.slice(0,3).map(row=>row.originName),
   ['Ira','Tratto · Vigore arcano','Condizione · Avvelenato']);
 assert.doesNotMatch(sheetRollOriginHtml(segments,x=>x),/2d20kh1|2d20kl1/);
 let dice=[7,19];
 const neutral=rollSheetDice(calc.values['skill:athletics'],[],()=>dice.shift(),state.mode);
 assert.deepEqual(neutral.rolls,[7], 'Cancelled roll must consume one d20');
 assert.equal(dice.length,1);
 const withoutPoison=classFeatureRollSources({...c,conditions:[]},calculated,'skill:athletics');
 assert.equal(resolveClassRollMode(withoutPoison).mode,'advantage');
 let pairs=[6,17,2];
 const advantage=rollSheetDice(0,[],()=>pairs.shift(),resolveClassRollMode(withoutPoison).mode);
 assert.deepEqual(advantage.rolls,[6,17], 'Multiple advantages roll only two dice');
 assert.equal(advantage.total,17);
 assert.equal(resolveClassRollMode(withoutPoison,'disadvantage').mode,'normal',
   'Manual situational disadvantage also cancels automatic privilege advantage');
 const disabled=classFeatureRollSources({...c,origin_enabled:{'feature:arcane':false}},calculated,'skill:athletics');
 assert(!disabled.some(row=>row.origin_id==='feature:arcane'));
});
test('two disadvantages and one advantage still give a normal d20',()=>{
 const sources=[
   {mode:'disadvantage',origin_id:'feature:a',origin_name:'A'},
   {mode:'disadvantage',origin_id:'feature:b',origin_name:'B'},
   {mode:'advantage',origin_id:'feature:c',origin_name:'C'}
 ];
 assert.equal(resolveClassRollMode(sources).mode,'normal');
 assert.equal(resolveClassRollMode(sources.slice(0,2)).mode,'disadvantage');
 assert.equal(resolveClassRollMode(sources.slice(0,2),'advantage').mode,'normal');
 assert.equal(resolveClassRollMode(sources,'normal').mode,'normal');
});
