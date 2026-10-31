import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {initialCreature} from '../character_core.js';
import {sheetRollOriginSegments,sheetScoreOriginSegments,sheetRollOriginHtml,sheetRollOriginLabel,damageRollSegments,rollDamageName,rollOptionalDice,attackGrantOrigin} from '../sheet_roll_origin.js';
import {classFeatureRollSources,resolveClassRollMode,classFeatureRollAdvantage} from '../feature_mechanics.js';
import {rollSheetDice,rollBattleDamage} from '../sheet_rules_view.js';
import {collectTraitRows} from '../trait_projection.js';
import {traitBenefitSources,traitBenefitGroups} from '../trait_benefits.js';

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
 assert.deepEqual(rows.map(row=>row.expanded),['1d6 + 3',''],
  'The evaluated base modifier must be visible below the symbolic formula');
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
test('numeric base damage expansion has its own divider before the damage type',()=>{
 const css=readFileSync(new URL('../mobile_metal_theme.css',import.meta.url),'utf8');
 assert.match(css,/\.sheet-roll-dialog \.sheet-roll-origin-term\.is-base:has\(\.sheet-roll-origin-damage-type\)\s+\.sheet-roll-origin-value\s*\{[^}]*border-top:1px/,
  'The numeric row must be separated from the symbolic formula by a line');
});
test('negative base damage ability modifiers expand without including detached benefits',()=>{
 const attack={ability:'str',damage:'1d6 − 1',damage_base_formula:'1d6',
  damage_ability_modifier:-3,damage_extra_modifier:2,damage_ability_applies:true,
  damage_bonus_components:[{value:2,origin_id:'feature:style',origin_name:'Bonus'}]};
 const rows=damageRollSegments(rollBattleDamage(attack.damage,()=>1),'slashing',attack);
 assert.deepEqual(rows.map(row=>row.formula),['1d6 + Mod.FOR','+2']);
 assert.deepEqual(rows.map(row=>row.expanded),['1d6 − 3','+2']);
 assert.equal(rows.reduce((sum,row)=>sum+row.value,0),-1);
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
 assert.equal(rows[0].expanded,'1d8 + 4');
 const html=sheetRollOriginHtml(rows,x=>x);
 assert.match(html,/<span class="sheet-roll-origin-symbol">1d8 \+ Mod\.FOR<\/span><span class="sheet-roll-origin-value">1d8 \+ 4<\/span>/,
  'The expanded base damage appears directly beneath the symbolic formula');
 assert.equal(rows[0].damageType,'slashing');
 assert.equal(rows[0].value,roll.modifier);
});
test('base weapon damage keeps +Mod.FOR with a genuine zero ability modifier',()=>{
 const c={...character(),abilities:{str:10,dex:16,con:12,int:10,wis:10,cha:10},
  inventory:[{id:'zero-sword',name:'Sword',custom_item_type:'weapon',type:'M',
    weapon_category:'simple',damage:'1d8',damage_type:'slashing',quantity:1,
    equipped_slots:['main']}]};
 const calculated=calculateSheet(c);
 const attack=calculated.attacks.find(row=>row.id==='item:zero-sword');
 assert(attack);
 assert.equal(attack.damage_ability_modifier,0);
 assert.equal(attack.damage_ability_applies,true);
 const rows=damageRollSegments(rollBattleDamage(attack.damage,()=>1),attack.damage_type,attack);
 assert.deepEqual(rows.map(row=>row.formula),['1d8 + Mod.FOR']);
 assert.equal(rows[0].expanded,'1d8 + 0',
  'The numeric expansion must remain visible even for a +0 modifier');
});
test('separated damage bonuses do not remove +Mod from base or invent it for offhand',()=>{
 const style={id:'style',value:2,origin_id:'feature:style',origin_name:'Stile'};
 const main={id:'item:sword',ability:'str',damage:'1d8 + 2',
  damage_base_formula:'1d8',damage_ability_modifier:0,damage_extra_modifier:2,
  damage_ability_applies:true,damage_bonus_components:[style]};
 const mainRows=damageRollSegments(rollBattleDamage(main.damage,()=>1),'slashing',main);
 assert.deepEqual(mainRows.map(row=>row.formula),['1d8 + Mod.FOR','+2']);
 assert.deepEqual(mainRows.map(row=>row.expanded),['1d8 + 0','+2']);
 assert.equal(mainRows.reduce((sum,row)=>sum+row.value,0),2);
 assert.deepEqual(mainRows.map(row=>row.damageType),['slashing','slashing']);
 const off={...main,id:'item:off:dagger',damage:'1d6 + 2',
  damage_base_formula:'1d6',damage_ability_applies:false};
 const offRows=damageRollSegments(rollBattleDamage(off.damage,()=>1),'piercing',off);
 assert.deepEqual(offRows.map(row=>row.formula),['1d6','+2'],
  'Offhand damage has no base ability bonus; its Fighting Style bonus remains distinct');
 assert.equal(offRows[0].expanded,'','An offhand strike must not invent a base modifier');
 assert.deepEqual(offRows.map(row=>row.damageType),['piercing','piercing']);
});
test('automatic numeric damage bonuses get their own origin boxes and inherit the base damage type',()=>{
 const attack={id:'item:sword',ability:'str',origin_id:'item:sword',damage:'1d8 + 1 + 6',
   damage_base_formula:'1d8+1',damage_ability_modifier:2,damage_extra_modifier:4,
   damage_bonus_components:[
    {id:'style:a',value:2,origin_id:'feature:dueling',origin_name:'Dueling',expression:'2'},
    {id:'style:b',value:2,origin_id:'feature:other',origin_name:'Altro bonus',expression:'2'}
   ]};
 const roll=rollBattleDamage(attack.damage,()=>4);
 const rows=damageRollSegments(roll,'slashing',attack);
 assert.deepEqual(rows.map(row=>row.formula),['1d8 + Mod.FOR + 1','+2','+2']);
 assert.deepEqual(rows.map(row=>row.expanded),['1d8 + 3','+2','+2'],
  'Numeric expansion excludes both detached damage bonuses');
 assert.deepEqual(rows.map(row=>row.originName),['Danno base','Dueling','Altro bonus']);
 assert(rows.every(row=>row.damageType==='slashing'),'Flat bonuses use the base damage type');
 assert.deepEqual(rows.map(row=>row.value),[3,2,2]);
 assert.equal(rows.reduce((sum,row)=>sum+row.value,0),roll.modifier,
  'Separating the bonus is visual only: the roll does not double-count it');
 const markup=sheetRollOriginHtml(rows,x=>x);
 assert.match(markup,/data-origin-id="feature:dueling"/);
 assert.match(markup,/data-origin-id="feature:other"/);
 assert.equal((markup.match(/>Tagliente<\/span>/g)||[]).length,3,
  'Each separate bonus box displays the weapon damage type');
 assert.equal(roll.total,11,'The unchanged damage formula is rolled only once');
});
test('numeric damage grants follow the first damage type in mixed weapon damage',()=>{
 const attack={ability:'dex',damage:'1d6 + 2d4 + 5',
   damage_base_formula:'1d6+2d4',damage_ability_modifier:3,damage_extra_modifier:2,
   damage_bonus_components:[{id:'style',value:2,origin_id:'feature:style',origin_name:'Stile'}]};
 const roll=rollBattleDamage(attack.damage,()=>1);
 const rows=damageRollSegments(roll,'piercing;fire',attack);
 assert.deepEqual(rows.map(row=>row.damageType),['piercing','fire','piercing']);
 assert.equal(rows[0].formula,'1d6 + Mod.DES');
 assert.equal(rows[0].expanded,'1d6 + 3');
 assert.equal(rows[2].formula,'+2');
 assert.equal(rows.reduce((sum,row)=>sum+row.value,0),roll.modifier);
 const changed=damageRollSegments(rollBattleDamage('1d6+2d4+4',()=>1),
  'piercing;fire',attack);
 assert.equal(changed.length,2,'Do not project stale bonuses onto a changed formula');
 assert.equal(changed[0].formula,'1d6 + Modificatore');
});
test('mixed typed damages show only verifiable source-derived characteristic and extra modifiers',()=>{
 const roll=rollBattleDamage('1d6+2+2d4+4',()=>1);
 const attack={ability:'str',damage:'1d6+2+2d4+4',
   damage_base_formula:'1d6+2+2d4',damage_ability_modifier:4,damage_extra_modifier:0};
 const grouped=damageRollSegments(roll,'slashing;fire',attack);
 assert.equal(grouped[0].formula,'1d6 + Mod.FOR + 2');
 assert.equal(grouped[0].expanded,'1d6 + 6');
 assert.equal(grouped[1].formula,' + 2d4');
 assert.deepEqual(grouped.map(row=>row.damageType),['slashing','fire']);
 const incorrect={...attack,damage_base_formula:'1d6+2d4',
   damage_extra_modifier:2};
 assert.equal(damageRollSegments(roll,'slashing;fire',incorrect)[0].formula,
   '1d6 + Modificatore','Inconsistent sources must not claim an ability modifier');
});
test('fixed proficiency provenance opens the existing class overview, never a fabricated trait',async()=>{
 const record=character(),calculated=calculateSheet(record);
 const source='class|phb|barbarian';
 const training=sheetRollOriginSegments(record,calculated,'skill:athletics')
   .find(row=>row.kind==='training');
 assert.equal(training?.originId,source);
 const rows=await collectTraitRows(record,calculated,{entries:async category=>
   category==='classes'?[{name:'Barbarian',source:'PHB',entries:['Descrizione della classe']}]:[]});
 const trait=rows.find(row=>row.category==='classi'&&row.rank===0&&
   row.origin_key===source);
 assert(trait,'Original class overview should own fixed proficiencies');
 assert(!rows.some(row=>row.name==='Competenze'||row.key.startsWith('proficiency:')),
   'Never add a duplicated generated proficiency trait');
 assert(traitBenefitSources(trait,record).has(source));
 assert(traitBenefitGroups(trait,record,calculated).some(group=>
   group.type==='proficiency'&&group.items.some(item=>item.value==='Atletica')));
});

test('Lightning Launcher abbreviation renders as full Lightning damage and optional bonus links its tracker',()=>{
 assert.equal(rollDamageName('L'),'Fulmine');
 assert.equal(rollDamageName('T'),'Tuono');
 const html=sheetRollOriginHtml([{kind:'base',formula:'1d6',damageType:'L',
   originName:'Lightning Launcher'}],x=>x);
 assert.match(html,/>Fulmine<\/span>/);
 assert.doesNotMatch(html,/>L<\/span>/);
 const record=character(),calculated={trait_state_optional_dice:[{
   id:'lightning-launcher:extra',attack_id:'class_feature:lightning_launcher',
   tracker_id:'feature:lightning_launcher:extra_damage',dice:'1d6',damage_type:'lightning',
   origin_name:'Lightning Launcher',tracker_cost:1
 }],trackers:[{
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
 const exhausted=rollOptionalDice(record,{...calculated,trackers:[{...calculated.trackers[0],spent:1}]},[],{
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

test('passive perception is a source-backed deterministic score with no d20',()=>{
 const c={...character(),formula_bonuses:[...character().formula_bonuses,
   {id:'passive',target:'passive_perception',expression:'2',
    origin_id:'feature:passive',origin_name:'Sensi acuti'}]};
 const calc=calculateSheet(c),rows=sheetScoreOriginSegments(c,calc,'passive_perception');
 assert(!rows.some(row=>/d20/.test(row.formula)), 'A passive score cannot generate a roll');
 assert(rows.some(row=>row.formula.startsWith('10 + Mod.SAG')));
 assert.equal(rows.filter(row=>row.kind==='training').length,0,'no training from untrained Perception');
 assert.equal(rows.find(row=>row.originId==='feature:passive')?.expanded,'+2');
 assert.equal(rows.reduce((sum,row)=>sum+(row.value||0),0),calc.values.passive_perception);
});
test('HP maximum and ability score formula tiles preserve explicit origin bonuses',()=>{
 const c={...character(),max_hp_base:19,
   formula_bonuses:[
     {id:'hp',target:'hp',expression:'3',origin_id:'feature:hp',origin_name:'Robustezza'},
     {id:'str',target:'ability:str',expression:'2',origin_id:'feature:str',origin_name:'Forza'}
   ]},calc=calculateSheet(c);
 const hp=sheetScoreOriginSegments(c,calc,'hp');
 assert.equal(hp.find(row=>row.kind==='base')?.value,19);
 assert.equal(hp.find(row=>row.originId==='feature:hp')?.expanded,'+3');
 assert.equal(hp.reduce((sum,row)=>sum+row.value,0),calc.values.hp);
 const strength=sheetScoreOriginSegments(c,calc,'ability:str');
 assert.equal(strength.find(row=>row.kind==='base')?.value,18);
 assert.equal(strength.find(row=>row.originId==='feature:str')?.value,2);
 assert.equal(strength.reduce((sum,row)=>sum+row.value,0),calc.values['ability:str']);
 const html=sheetRollOriginHtml(hp,x=>x);
 assert.match(html,/data-origin-id="feature:hp"/);
 assert.doesNotMatch(html,/1d20|data-roll-mode/);
});
test('unattributed proficiency stays in the Info summary without a fabricated trait',async()=>{
 const c={...character(),proficiency_choices:[{kind:'skill',key:'athletics',origin_id:''}]};
 const calc=calculateSheet(c),training=sheetRollOriginSegments(c,calc,'skill:athletics')
   .find(row=>row.kind==='training');
 assert.equal(training?.originId,'proficiency:unattributed');
 assert(calc.proficiencies.includes('skill:athletics'));
 const traits=await collectTraitRows(c,calc,{entries:async()=>[]});
 assert(!traits.some(row=>row.name==='Competenze'||row.proficiency_origin===
   'proficiency:unattributed'),'Unattributed proficiency is a character fact, not a trait');
});
test('concrete proficiency IDs belong to their original grant, not a cloned Competenze trait',async()=>{
 const c=character(),calc=calculateSheet(c);
 const source='class|phb|barbarian';
 const rows=await collectTraitRows(c,calc,{entries:async category=>
   category==='classes'?[{name:'Barbarian',source:'PHB',entries:['Origine della classe']}]:[]});
 const trait=rows.find(row=>row.rank===0&&row.origin_key===source);
 assert(trait,'Must locate original class');
 assert(traitBenefitSources(trait,c).has(source));
 assert(traitBenefitGroups(trait,c,calc).some(group=>group.type==='proficiency'));
 assert(!rows.some(row=>row.key==='proficiency:'+source));
});

test('only explicitly owned base score terms gain a base-edit control',()=>{
 const c=character(),calc=calculateSheet(c);
 for(const target of ['ability:str','hp','second_max']){
   const rows=sheetScoreOriginSegments(c,calc,target);
   const enabled=rows.map(row=>row.kind==='base'?{...row,editBaseTarget:target}:row);
   const html=sheetRollOriginHtml(enabled,x=>x);
   assert.match(html,/data-act="sheet-score-edit-base"/);
   assert.match(html,/data-score-base-target="/);
   assert.equal((html.match(/data-act="sheet-score-edit-base"/g)||[]).length,1);
 }
 for(const target of ['ability_mod:str','passive_perception','proficiency']){
   const html=sheetRollOriginHtml(sheetScoreOriginSegments(c,calc,target),x=>x);
   assert.doesNotMatch(html,/data-act="sheet-score-edit-base"/);
 }
});

test('confirmed flat roll benefits add a constant, not a die or a permanent score modifier',()=>{
 const c=character(),calculated=calculateSheet(c);
 const bonus={id:'class_feature:flash_of_genius',selectionId:'reaction:flash',
  flat_bonus:4,origin_id:'feature:artificer:flash',origin_name:'Tratto · Flash of Genius'};
 const before=calculated.values['save:dex'];
 const segments=sheetRollOriginSegments(c,calculated,'save:dex',{diceBonuses:[bonus]});
 assert(segments.some(row=>row.originId===bonus.origin_id&&row.formula==='+4'));
 const result=rollSheetDice(before,[bonus],()=>12);
 assert.equal(result.total,12+before+4);
 assert.deepEqual(result.rolls,[12]);
 assert.equal(result.parts.length,2);
 assert.equal(result.parts[1].subtotal,4);
 assert.equal(calculated.values['save:dex'],before,'roll bonus does not mutate base calculation');
 const withDice=rollSheetDice(0,[bonus,{dice:'1d4',origin_name:'Benedizione'}],()=>3);
 assert.equal(withDice.total,3+4+3);
});
