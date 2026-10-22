import {test} from 'node:test';
import assert from 'node:assert/strict';
import {calculateSheet} from '../sheet_rules.js';
import {initialCreature} from '../character_core.js';
import {sheetRollOriginSegments,sheetRollOriginHtml} from '../sheet_roll_origin.js';

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
   autoAdvantage:true});
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
 const terms=sheetRollOriginSegments(c,calc,'skill:athletics',{mode:'advantage',autoAdvantage:true});
 assert.equal(terms[0].formula,'ADV');
 assert.equal(terms[0].originName,'Ira');
 assert.equal(terms[0].expanded,'');
});
