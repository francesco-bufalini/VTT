import {test} from 'node:test';
import assert from 'node:assert/strict';
import {calculateSheet} from '../sheet_rules.js';
import {initialCreature} from '../character_core.js';
import {sheetRollOriginSegments,sheetRollOriginHtml,sheetRollOriginLabel,damageRollSegments,rollDamageName,rollOptionalDice,attackGrantOrigin} from '../sheet_roll_origin.js';
import {classFeatureRollSources,resolveClassRollMode,classFeatureRollAdvantage} from '../feature_mechanics.js';
import {rollSheetDice,rollBattleDamage} from '../sheet_rules_view.js';
import {collectTraitRows} from '../trait_projection.js';

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
test('changes to scores stay inside Mod.Characteristic while modifier-only grants remain distinct',()=>{
 const c={...character(),formula_bonuses:[
   {id:'score',target:'ability:str',expression:'2',origin_id:'feature:score',origin_name:'Punteggio'},
   {id:'mod',target:'ability_mod:str',expression:'1',origin_id:'feature:mod',origin_name:'Modificatore'}
 ]};
 const calculated=calculateSheet(c);
 const terms=sheetRollOriginSegments(c,calculated,'skill:athletics');
 assert.equal(terms.find(t=>t.originId==='feature:score'),undefined);
 assert.equal(terms.find(t=>t.kind==='base')?.formula,'1d20 + Mod.FOR');
 assert.equal(terms.find(t=>t.kind==='base')?.expanded,'1d20 +5');
 assert.equal(terms.find(t=>t.originId==='feature:mod')?.expanded,'+1');
 assert.equal(terms.reduce((sum,t)=>sum+(t.value||0),0),calculated.values['skill:athletics']);
 const toHit={...calculated,attacks:[{id:'main',ability:'str',proficient:true}],
   values:{...calculated.values,'attack_hit:main':calculated.values['ability_mod:str']+2}};
 const attackTerms=sheetRollOriginSegments(c,toHit,'attack_hit:main');
 assert.equal(attackTerms.find(row=>row.kind==='base')?.expanded,'1d20 +5');
 assert(!attackTerms.some(row=>row.originId==='feature:score'),
   'Score increases must never create an extra attack bonus segment');
 assert.equal(attackTerms.reduce((sum,row)=>sum+(row.value||0),0),toHit.values['attack_hit:main']);
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

test('short provenance labels remove generic prefixes without changing navigation data',()=>{
 assert.equal(sheetRollOriginLabel('Oggetto - Stone of Good Luck'),'Stone of Good Luck');
 assert.equal(sheetRollOriginLabel('Oggetto · Stone of Good Luck'),'Stone of Good Luck');
 assert.equal(sheetRollOriginLabel('Tratto · Fortunato'),'Fortunato');
 assert.equal(sheetRollOriginLabel('Privilegio: Ira'),'Ira');
 assert.equal(sheetRollOriginLabel('Condizione · Avvelenato'),'Condizione · Avvelenato');
 assert.equal(sheetRollOriginLabel('Oggetto'),'Oggetto');
 const html=sheetRollOriginHtml([{
   kind:'formula',key:'stone',formula:'+1',expanded:'+1',
   originId:'item:stone-of-good-luck',originName:'Oggetto - Stone of Good Luck',
 }],text=>text);
 assert.match(html,/>Stone of Good Luck<\/span>/);
 assert.match(html,/title="Oggetto - Stone of Good Luck"/);
 assert.match(html,/data-origin-id="item:stone-of-good-luck"/);
});

test('damage base dice and modifier share a section; only different types create more sections',()=>{
 const roll=rollBattleDamage('1d6+3+2d4',()=>1);
 const rows=damageRollSegments(roll,'slashing; fire');
 assert.deepEqual(rows.map(row=>row.formula),['1d6 + Modificatore',' + 2d4']);
 assert.deepEqual(rows.map(row=>row.damageType),['slashing','fire']);
 assert.equal(rows[0].value,3);
 const html=sheetRollOriginHtml(rows,x=>x);
 assert.equal((html.match(/class="sheet-roll-origin-damage-type"/g)||[]).length,2);
 assert(html.indexOf('sheet-roll-origin-symbol')<html.indexOf('sheet-roll-origin-damage-type'));
 assert(html.indexOf('sheet-roll-origin-damage-type')<html.indexOf('sheet-roll-origin-name'));
 const oneType=damageRollSegments(roll,'slashing');
 assert.deepEqual(oneType.map(row=>row.formula),['1d6 + 2d4 + Modificatore']);
 assert.equal(oneType[0].damageType,'slashing');
 const ambiguous=damageRollSegments(roll,'slashing; fire; cold');
 assert(ambiguous.every(row=>row.damageType===''),'An ambiguous mixture must not invent damage types');
});
test('a genuine weapon attack uses Mod.FOR in the base damage section',()=>{
 const c={...character(),inventory:[{id:'test-sword',name:'Test sword',
   custom_item_type:'weapon',type:'M',weapon_category:'simple',damage:'1d8',quantity:1,
   equipped_slots:['main']}]};
 const calculated=calculateSheet(c);
 const attack=calculated.attacks.find(row=>row.id==='item:test-sword');
 assert(attack,'Weapon must be available from the real attack calculation');
 assert.equal(attack.damage_ability_modifier,4);
 const roll=rollBattleDamage(attack.damage,()=>1);
 const rows=damageRollSegments(roll,'slashing',attack);
 assert.equal(rows.length,1);
 assert.equal(rows[0].formula,'1d8 + Mod.FOR');
 assert.equal(rows[0].damageType,'slashing');
 assert.equal(rows[0].value,roll.modifier);
});
test('mixed typed damages show only verifiable source-derived characteristic and extra modifiers',()=>{
 const roll=rollBattleDamage('1d6+2+2d4+4',()=>1);
 const attack={ability:'str',damage:'1d6+2+2d4+4',
   damage_base_formula:'1d6+2+2d4',damage_ability_modifier:4,damage_extra_modifier:0};
 const grouped=damageRollSegments(roll,'slashing;fire',attack);
 assert.equal(grouped[0].formula,'1d6 + Mod.FOR + 2');
 assert.equal(grouped[1].formula,' + 2d4');
 assert.deepEqual(grouped.map(row=>row.damageType),['slashing','fire']);
 const incorrect={...attack,damage_base_formula:'1d6+2d4',
   damage_extra_modifier:2};
 assert.equal(damageRollSegments(roll,'slashing;fire',incorrect)[0].formula,
   '1d6 + Modificatore','Inconsistent sources must not claim an ability modifier');
});
test('fixed proficiency provenance has its own navigable class trait when no feature owns it',async()=>{
 const record=character(),calculated=calculateSheet(record);
 const source='class|phb|barbarian';
 const training=sheetRollOriginSegments(record,calculated,'skill:athletics')
   .find(row=>row.kind==='training');
 assert.equal(training?.originId,source);
 const rows=await collectTraitRows(record,calculated,{entries:async()=>[]});
 const trait=rows.find(row=>row.proficiency_origin===source);
 assert.equal(trait?.category,'classi');
 assert.equal(trait?.name,'Competenze');
 assert.match(String(trait?.entries),/Atletica/);
 assert.equal(trait?.origin_key,source);
 assert.equal(rows.filter(row=>row.proficiency_origin===source).length,1);
});

test('Lightning Launcher abbreviation renders as full Lightning damage and optional bonus links its tracker',()=>{
 assert.equal(rollDamageName('L'),'Fulmine');
 assert.equal(rollDamageName('T'),'Tuono');
 const html=sheetRollOriginHtml([{kind:'base',formula:'1d6',damageType:'L',
   originName:'Lightning Launcher'}],x=>x);
 assert.match(html,/>Fulmine<\/span>/);
 assert.doesNotMatch(html,/>L<\/span>/);
 const record=character(),calculated={trackers:[{
   id:'feature:lightning_launcher:extra_damage',name:'Lightning Launcher · danno aggiuntivo',
   max:1,spent:0,origin_id:'feature:class|tce|artificer|lightning_launcher'
 }]};
 const options=rollOptionalDice(record,calculated,[],{
   kind:'damage',attackId:'class_feature:lightning_launcher'});
 assert.equal(options.length,1);
 assert.equal(options[0].dice,'1d6');
 assert.equal(rollDamageName(options[0].damage_type),'Fulmine');
 assert.equal(options[0].tracker_cost,1);
 assert.equal(options[0].remaining,1);
 const exhausted=rollOptionalDice(record,{trackers:[{...calculated.trackers[0],spent:1}]},[],{
   kind:'damage',attackId:'class_feature:lightning_launcher'});
 assert.equal(exhausted.length,1,'An exhausted tracker must remain explicitly usable');
 assert.equal(exhausted[0].remaining,0);
 assert.equal(rollOptionalDice(record,calculated,[],{
   kind:'damage',attackId:'item:normal_weapon'}).length,0);
});
test('generic optional die keeps exhausted tracked sources selectable and identifies weapon damage',()=>{
 const bonus={id:'extra',target:'attack_damage:item:sword',dice:'1d6',
  damage_type:'lightning',tracker_id:'focus',tracker_cost:1,origin_name:'Fonte'};
 const calculated={trackers:[{id:'focus',name:'Focus',max:2,spent:1}]};
 const available=rollOptionalDice(character(),calculated,[bonus],{
   kind:'damage',attackId:'item:sword'});
 assert.equal(available.length,1);
 assert.equal(available[0].remaining,1);
 assert.equal(available[0].spent,1);
 const out=rollOptionalDice(character(),{trackers:[{...calculated.trackers[0],spent:2}]},[bonus],{
   kind:'damage',attackId:'item:sword'});
 assert.equal(out.length,1);
 assert.equal(out[0].remaining,0);
});

test('the base hit and damage terms resolve to the granting equipped-item trait',()=>{
 const attack={id:'item:test-sword',name:'Test sword',ability:'str',proficient:true,
   damage:'1d8+4',damage_base_formula:'1d8',damage_ability_modifier:4,damage_extra_modifier:0};
 const calculated={values:{'attack_hit:item:test-sword':6,proficiency:2},
   attacks:[attack],proficiencies:[],roll_components:{}};
 assert.equal(attackGrantOrigin(calculated,attack.id),'item:test-sword');
 const hit=sheetRollOriginSegments(character(),calculated,'attack_hit:'+attack.id);
 assert.equal(hit.find(row=>row.kind==='base').originId,'item:test-sword');
 assert.match(sheetRollOriginHtml(hit,x=>x),/data-origin-id="item:test-sword"/);
 const damage=damageRollSegments(rollBattleDamage(attack.damage,()=>1),'slashing',
   {...attack,origin_id:attackGrantOrigin(calculated,attack.id)});
 assert.equal(damage[0].originId,'item:test-sword');
 assert.match(sheetRollOriginHtml(damage,x=>x),/data-act="roll-origin-open"/);
});
