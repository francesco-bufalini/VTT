import test from 'node:test';
import assert from 'node:assert/strict';
import {collectTraitRows,groupTraitRows} from '../trait_projection.js';
import {traitBenefitGroups} from '../trait_benefits.js';
import {nativeSection} from '../native_sheet.js';
import {calculateSheet} from '../sheet_rules.js';
import {classFeatureRollSources} from '../feature_mechanics.js';
import {sheetScoreOriginSegments} from '../sheet_roll_origin.js';

test('a sheet with zero talents still offers the talent catalog',()=>{
 const record={kind:'character',name:'Eroe',feats_catalog:[],abilities:{str:10,dex:10,con:10,int:10,wis:10,cha:10}};
 const markup=nativeSection(record,'info',{
  field:()=>'',area:()=>'',panel:(_title,body)=>body,
  catalogs:{},calculated:calculateSheet(record)
 });
 assert.match(markup,/Nessun talento registrato/);
 assert.match(markup,/data-act="feat-catalog"/);
});
test('active conditions, spells and persistent class effects have independent source-bound state traits',async()=>{
 const record={kind:'character',conditions:['poisoned'],proficiency_origins:[
  {id:'spell:bless',group:'spell',name:'Incantesimo · Bless',applied:true}
 ]};
 const calculated={active_feature_effects:[
  {key:'rage',name:'Ira',origin_id:'feature:rage',effective:true},
  {key:'trait_state:armor_model:infiltrator',name:'Infiltratore',
   origin_id:'feature:armor-model',summary:'Lanciatore di Fulmini',effective:true},
  {key:'inactive',name:'Disattivato',effective:false}
 ]};
 const rows=await collectTraitRows(record,calculated,{conditionLabel:id=>id==='poisoned'?'Avvelenato':id});
 const active=rows.filter(row=>row.category==='stati');
 assert.equal(active.length,4);
 assert.ok(active.every(row=>row.readonly&&!row.inactive));
 assert.equal(active.find(row=>row.name==='Infiltratore')?.state_id,'armor_model:infiltrator');
 assert.equal(active.find(row=>row.name==='Incantesimo · Bless')?.spell_id,'bless');
 assert.equal(active.find(row=>row.condition_id==='poisoned')?.name,'Avvelenato');
 assert.equal(groupTraitRows(rows)[0].id,'stati');
});
test('source-bound benefits include attacks and data-defined advantage/disadvantage',()=>{
 const trait={key:'feature:test',feature_origin:'feature:blaster',category:'classi',rank:2};
 const record={};
 const calculated={
  attacks:[{id:'blaster',name:'Lancia energia',origin_id:'feature:blaster',
   damage:'1d8 + 2',damage_type:'force',range_feet:90,melee:false}],
  features:[{origin_id:'feature:blaster',name:'Lancia energia',
   roll_modes:[{mode:'advantage',target:'attack_roll'},
    {mode:'disadvantage',target:'saving_throw'}]}],
  bonuses:[{id:'ca',target:'ac',expression:'2',origin_id:'feature:blaster'}]
 };
 const groups=traitBenefitGroups(trait,record,calculated);
 assert.equal(groups.find(g=>g.type==='attacks')?.items[0].label,'Lancia energia');
 assert.match(groups.find(g=>g.type==='attacks').items[0].value,/90 ft/);
 assert.equal(groups.find(g=>g.type==='bonus')?.items[0].label,'Classe armatura');
 assert.deepEqual(groups.find(g=>g.type==='roll_modes')?.items.map(i=>i.value),
  ['Vantaggio','Svantaggio']);
});
test('state privileges expose their own attacks and speed grants, not sibling states',()=>{
 const state={key:'state|trait_state:armor_model:infiltrator',state_id:'armor_model:infiltrator',
  feature_origin:'feature:armor-model',category:'stati',rank:0,readonly:true};
 const calculated={
  trait_state_catalog:[
   {id:'armor_model:infiltrator',attacks:[{id:'launcher'}]},
   {id:'armor_model:guardian',attacks:[{id:'gauntlets'}]}],
  attacks:[{id:'launcher',name:'Lightning Launcher',damage:'1d6',range_feet:90},
   {id:'unrelated',name:'Spada',damage:'1d8'},
   {id:'gauntlets',name:'Thunder Gauntlets',damage:'1d8'}],
  automatic_bonuses:[{id:'trait_state:armor_model:infiltrator:powered_steps',
   origin_id:'feature:steps',target:'speed',expression:'5'}]
 };
 const groups=traitBenefitGroups(state,{},calculated);
 assert.deepEqual(groups.find(g=>g.type==='attacks').items.map(row=>row.label),['Lightning Launcher']);
 assert.equal(groups.find(g=>g.type==='bonus').items[0].value,'+5');
});
test('an equipped armor trait lists AC even without a formula grant',()=>{
 const armor={id:'armor',name:'Corazza',type:'HA',ac:18,quantity:1,equipped_slots:['body']};
 const trait={origin_key:'item:armor',category:'oggetti',rank:0};
 const groups=traitBenefitGroups(trait,{inventory:[armor]},{});
 assert.deepEqual(groups.find(g=>g.type==='armor_class')?.items.map(row=>row.value),['CA base 18']);
});
test('a condition trait identifies disadvantage coming from the roll rules',()=>{
 const trait={key:'state|condition:poisoned',condition_id:'poisoned',category:'stati',rank:0};
 const calculated={features:[],attacks:[]};
 const groups=traitBenefitGroups(trait,{conditions:['poisoned']},calculated);
 assert.ok(groups.find(g=>g.type==='roll_modes')?.items.some(row=>row.value==='Svantaggio'));
});

test('saved roll modes apply to real d20 rolls and stop with their granting trait',()=>{
 const grant={id:'trait:mode1000',origin_id:'feature:trait:mode-card',parent_origin:'feature:owned',
  trait_key:'mode-card',mode:'disadvantage',target:'saving_throw',origin_name:'Tratto personalizzato'};
 const record={roll_mode_grants:[grant]};
 const calculated={features:[],attacks:[]};
 assert.ok(classFeatureRollSources(record,calculated,'save:dex').some(row=>row.mode==='disadvantage'&&row.origin_id===grant.origin_id));
 assert.ok(!classFeatureRollSources(record,calculated,'initiative').some(row=>row.origin_id===grant.origin_id));
 assert.ok(!classFeatureRollSources({...record,trait_enabled:{'mode-card':false}},calculated,'save:dex').some(row=>row.origin_id===grant.origin_id));
 assert.ok(!classFeatureRollSources({...record,origin_enabled:{'feature:owned':false}},calculated,'save:dex').some(row=>row.origin_id===grant.origin_id));
});
test('a once-rolled static bonus changes HP and links back to the real origin',()=>{
 const bonus={id:'trait:hp1000',origin_id:'feature:trait:hp-card',origin_name:'Dono',
  target:'hp',expression:'3',dice_notation:'1d4',disabled:false};
 const record={kind:'character',max_hp_base:10,abilities:{str:10,dex:10,con:10,int:10,wis:10,cha:10},
  formula_bonuses:[bonus]};
 const calculated=calculateSheet(record);
 assert.equal(calculated.values.hp,13);
 const sources=sheetScoreOriginSegments(record,calculated,'hp');
 assert.ok(sources.some(row=>row.originId===bonus.origin_id&&row.formula.includes('1d4')&&row.expanded==='+3'));
});
