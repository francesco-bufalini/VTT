import {test} from 'node:test';
import assert from 'node:assert/strict';
import {calculateSheet} from '../sheet_rules.js';
import {sheetRollFormula,rollSheetDice,formulaReadout,sheetRollChatFields,sheetModifierBreakdown,isPersistentSpell,fastestMovement,trackerRecoveryText} from '../sheet_rules_view.js';
import {hitPointPatch,rowsFor,collectionPatch,nativeRowPatch,miniaturePatch,speciesCreatureType,nativeRows,identityPatch,primaryClassLevel,totalClassLevel,nativeSection} from '../native_sheet.js';
import {referencePatch,rowReferencePatch} from '../native_sheet.js';
import {castingClasses,resourceTrackers} from '../sheet_rules.js';
import {slotUsePatch,recoveryPatch} from '../native_sheet.js';
import {addSelectedSpell,removeSelectedSpell} from '../spell_selection.js';
import {readFileSync,existsSync} from 'node:fs';
const mechanics=JSON.parse(readFileSync(new URL('../catalog/class_mechanics.json',import.meta.url),'utf8'));
const catalogs={classMechanics:mechanics};

test('resource recovery caption reflects each tracker recovery rule',()=>{
 assert.equal(trackerRecoveryText({recharge:'short_rest'}),'Recupero: riposo breve');
 assert.equal(trackerRecoveryText({recharge:'long_rest'}),'Recupero: riposo lungo');
 assert.equal(trackerRecoveryText({recharge:'turn'}),'Recupero: inizio turno');
 assert.equal(trackerRecoveryText({recharge:'manual'}),'Recupero: manuale');
 assert.equal(trackerRecoveryText({recharge:'d6',recharge_min:5}),'Ricarica: d6 · 5+');
 assert.equal(trackerRecoveryText({recharge:'d6'}),'Ricarica: d6 · 6+');
 assert.equal(trackerRecoveryText({recharge:'custom'}),'Recupero: non specificato');
});

test('miniature choices mirror native base/current identity and size rules',()=>{
 const profile={id:'adult_brass_dragon_updated',size_name:'Huge',footprint:3};
 assert.deepEqual(miniaturePatch({default_miniature_id:'old',current_miniature_id:'old'},profile,'base'),
  {default_miniature_id:profile.id,current_miniature_id:profile.id,size_name:'Huge',footprint:3});
 assert.deepEqual(miniaturePatch({default_miniature_id:'old',current_miniature_id:'transformed'},profile,'base'),
  {default_miniature_id:profile.id,size_name:'Huge',footprint:3});
 assert.deepEqual(miniaturePatch({size_name:'Small'},profile,'current'),{current_miniature_id:profile.id});
 assert.throws(()=>miniaturePatch({}, {id:''}, 'base'));
});

test('damage consumes temporary, transformed and normal HP in native order; healing respects effective maximum',()=>{
 const c={temporary_hp:4,second_form_hp:8,current_hp:20,max_hp_base:25,formula_bonuses:[{target:'hp',expression:'5'}]};
 const out=calculateSheet(c);
 assert.deepEqual(hitPointPatch(c,-15,out),{temporary_hp:0,second_form_hp:0,current_hp:17});
 assert.deepEqual(hitPointPatch(c,50,out),{current_hp:30});
 assert.deepEqual(hitPointPatch(c,-100,out),{temporary_hp:0,second_form_hp:0,current_hp:0});
 assert.equal(c.current_hp,20);
 assert.throws(()=>hitPointPatch(c,NaN,out));
});
test('legacy class becomes editable without losing primary class or subclass references',()=>{
 const c={class:'Wizard',class_source:'PHB',class_id:'wizard',subclass:'Evocation',subclass_id:'evocation',level:5};
 const rows=rowsFor(c,'classes');
 assert.equal(rows[0].subclass_id,'evocation');
 rows.push({name:'Fighter',source:'PHB',level:2});
 const patch=collectionPatch(c,'classes',rows);
 assert.equal(patch.level,7);
 assert.equal(patch.class_id,'wizard');
 assert.equal(nativeRowPatch({...c,...patch},'classes',1,'level',3).level,8);
 assert.throws(()=>nativeRowPatch({...c,...patch},'classes',1,'level',19),/20/);
});
test('Info derives species creature type from references, including implicit Humanoid and subraces',()=>{
 const races=[{id:'elf',name:'Elf',source:'PHB'},
  {id:'hybrid',name:'Changeling',source:'ERLW',creatureTypes:['fey']},
  {id:'variant',name:'Elf (Other)',source:'PHB',creatureTypes:['fey','humanoid']}];
 assert.equal(speciesCreatureType({kind:'character',species:'Elf',species_source:'PHB'}, {races}),'Umanoide');
 assert.equal(speciesCreatureType({kind:'character',species:'Changeling',species_source:'ERLW'}, {races}),'Folletto');
 assert.equal(speciesCreatureType({kind:'character',species:'Elf',species_source:'PHB',subrace:'Other',subrace_source:'PHB'}, {races}),'Folletto, Umanoide');
 assert.equal(speciesCreatureType({kind:'character',species:'Unknown'}, {races}),'—');
 assert.equal(speciesCreatureType({kind:'monster',stat_block:{type:{type:'dragon'}}}, {races}),'dragon');
});
test('secondary classes show only non-primary entries, with source from selected catalog',()=>{
 const c={class:'Wizard',class_source:'PHB',classes:[{name:'Wizard',source:'PHB',level:4},
  {name:'Fighter',source:'PHB',level:1,subclass:'Champion',subclass_source:'PHB'}]};
 const html=nativeRows(c,'classes',{},1);
 assert.match(html,/data-native-list="classes" data-index="1" data-key="level"/);
 assert.doesNotMatch(html,/data-native-list="classes" data-index="0"/);
 assert.match(html,/native-readonly-source/);
 assert.doesNotMatch(html,/data-key="source"/);
 assert.throws(()=>nativeRowPatch(c,'classes',1,'source','DMG'),/catalogo/);
 assert.throws(()=>nativeRowPatch(c,'classes',1,'subclass_source','DMG'),/catalogo/);
 const patch=rowReferencePatch(c,'classes',1,'name',{id:'fighter_xphb',name:'Fighter',source:'XPHB'});
 assert.equal(patch.classes[1].source,'XPHB');
 assert.equal(patch.classes[1].id,'fighter_xphb');
 assert.equal(patch.class_source,'PHB');
});
test('statistics layout keeps six aligned, individually editable ability rows',()=>{
 const creature={kind:'character',abilities:{str:17,dex:14,con:12,int:10,wis:11,cha:8}};
 const calculated=calculateSheet(creature);
 const opts={
  field:()=>'',area:()=>'',panel:(title,body,className='')=>
   '<section class="'+className+'"><h2>'+title+'</h2>'+body+'</section>',
  catalogs:{},calculated,
 };
 const markup=nativeSection(creature,'info',opts);
 assert.equal(nativeSection(creature,'stats',opts),null,'The former standalone skills screen was retired');
 assert.equal((markup.match(/class="native-ability-row"/g)||[]).length,6);
 assert.match(markup,/class="native-abilities-header" role="row"/);
 for(const ability of ['str','dex','con','int','wis','cha']){
  assert.equal((markup.match(new RegExp('data-ability-row="'+ability+'"','g'))||[]).length,1);
  assert.equal((markup.match(new RegExp('data-ability-key="'+ability+'"','g'))||[]).length,1);
  assert.doesNotMatch(markup,new RegExp('data-ability="'+ability+'"'));
  for(const target of ['ability:','ability_mod:','save:']){
   assert.match(markup,new RegExp('data-calculated="'+target+ability+'"'));
  }
 }
 assert.match(markup,/stats-abilities-panel/);
 assert.match(markup,/stats-skills-panel/);
 assert.match(markup,/Altre competenze/);
 assert.doesNotMatch(markup,/data-detail="proficiency_choices"/,'The removed origin editor has no shortcut');
 assert.doesNotMatch(markup,/<summary>Base<\/summary>/);
 assert.doesNotMatch(markup,/Modifica i valori di base o usa ±/);
 const css=readFileSync(new URL('../mobile_metal_theme.css',import.meta.url),'utf8');
 assert.match(css,/\.stats-abilities-panel \.native-ability-row/);
 assert.match(css,/\.stats-abilities-panel \.native-ability-score \.score-editor-trigger/);
 assert.match(css,/\.stats-skills-panel \.native-summary > div/);
});
test('roll preview never rolls automatically; explicit roll returns full dice breakdown',()=>{
 const modifier=5,bonuses=[{dice:'1d4',origin_name:'Benedizione'},
  {dice:'2d6+1',origin_name:'Ispirazione'}];
 assert.equal(sheetRollFormula(modifier), '1d20 + 5');
 assert.equal(sheetRollFormula(-2,bonuses),'1d20 − 2 + 1d4 + 2d6+1');
 const draws=[14,3,2,5],sides=[];
 const result=rollSheetDice(modifier,bonuses,side=>{sides.push(side);return draws.shift();});
 assert.deepEqual(sides,[20,4,6,6]);
 assert.deepEqual(result.rolls,[14]);
 assert.equal(result.total,30); // d20 14 + 5 + d4 3 + (2d6 [2,5] + 1)
 assert.equal(result.parts.length,3);
 assert.match(result.detail,/d20 \[14\] = 14/);
 assert.match(result.detail,/Benedizione \[3\] = 3/);
 assert.match(result.detail,/Ispirazione \[2, 5\] \+ 1 = 8/);
 assert.match(result.detail,/totale 30/);
 const combined=sheetRollChatFields(result);
 assert.equal(combined.die,'formula');
 assert.equal(combined.count,4);
 assert.equal(combined.modifier,6);
 assert.equal(combined.terms.length,3);
 assert.deepEqual(combined.terms.map(row=>row.sides),[20,4,6]);
 assert.deepEqual(combined.terms.map(row=>row.rolls),[[14],[3],[2,5]]);
 assert.equal(combined.terms.reduce((n,row)=>n+row.rolls.reduce((a,b)=>a+b,0),combined.modifier),30);
 const standalone=rollSheetDice(2,[],()=>12);
 assert.deepEqual([sheetRollChatFields(standalone).die,sheetRollChatFields(standalone).total],['d20',14]);
 assert.throws(()=>rollSheetDice(2,[{dice:'1d3'}],()=>1),/Dadi bonus/);
 const score=formulaReadout({values:{'ability:dex':16}},'ability:dex','Destrezza',{scoreAbility:'dex'});
 assert.match(score,/data-act="edit-score"/);
 assert.doesNotMatch(score,/data-act="sheet-roll"/);
 const save=formulaReadout({values:{'save:dex':4}},'save:dex','TS Destrezza',{signed:true});
 assert.match(save,/data-act="sheet-roll"/);
});
test('fastest visible speed selects the highest calculated movement mode',()=>{
 const stats={values:{speed:30,'speed:fly':60,'speed:swim':20,'speed:climb':15,'speed:burrow':0}};
 assert.deepEqual(fastestMovement(stats),{key:'speed:fly',label:'Volo',value:60});
 assert.deepEqual(fastestMovement({values:{...stats.values,'speed:swim':60}}),{key:'speed:swim',label:'Nuoto',value:60});
 assert.deepEqual(fastestMovement({stats:{speeds:{walk:35,fly:0,swim:15}}}),{key:'speed',label:'Camminata',value:35});
 assert.deepEqual(fastestMovement({values:{speed:0,'speed:burrow':10}}),{key:'speed:burrow',label:'Scavo',value:10});
 const ac=formulaReadout({values:{ac:16}},'ac','Classe armatura',{showBonus:false});
 assert.match(ac,/data-calculated="ac"/);assert.doesNotMatch(ac,/formula-bonus|data-act="edit-bonus"/);
});
test('saving throw preview explains ability modifier, proficiency and extra origin bonuses',()=>{
 const record={kind:'character',abilities:{dex:18},
  proficiency_choices:[{kind:'save',key:'dex'}],
  formula_bonuses:[{id:'boost',target:'save:dex',expression:'2',origin_name:'Sigillo'}]};
 const data=calculateSheet(record);
 assert.equal(data.values['save:dex'],8);
 const breakdown=sheetModifierBreakdown(data,'save:dex');
 assert.match(breakdown,/Mod\. DEX \+4/);
 assert.match(breakdown,/Competenza \+2/);
 assert.match(breakdown,/Altri bonus \+2/);
 assert.match(data.explanations['save:dex'],/Sigillo/);
});
test('species type index retains official edition-specific non-humanoid types',()=>{
 const typed=JSON.parse(readFileSync(new URL('../catalog/species_types.json',import.meta.url),'utf8'));
 const base=[{name:'Fairy',source:'WBtW'},{name:'Autognome',source:'AAG'},
  {name:'Plasmoid',source:'AAG'},{name:'Satyr',source:'MOT'},{name:'Satyr',source:'MPMM'}];
 const races=base.map(row=>({...row,...(
   typed.races.find(t=>t.name===row.name&&t.source===row.source)?
    {creatureTypes:typed.races.find(t=>t.name===row.name&&t.source===row.source).creatureTypes}:{})}));
 assert.equal(speciesCreatureType({species:'Autognome',species_source:'AAG'}, {races}),'Costrutto');
 assert.equal(speciesCreatureType({species:'Fairy',species_source:'WBtW'}, {races}),'Folletto');
 assert.equal(speciesCreatureType({species:'Plasmoid',species_source:'AAG'}, {races}),'Melma');
 assert.equal(speciesCreatureType({species:'Satyr',species_source:'MOT'}, {races}),'Umanoide');
 assert.equal(speciesCreatureType({species:'Satyr',species_source:'MPMM'}, {races}),'Folletto');
});
test('primary class level can be edited but total is recomputed and cannot be edited',()=>{
 const c={kind:'character',class:'Wizard',class_source:'PHB',level:6,
  classes:[{name:'Wizard',source:'PHB',level:4},{name:'Fighter',source:'PHB',level:2}]};
 assert.equal(primaryClassLevel(c),4);
 assert.equal(totalClassLevel(c),6);
 const patch=identityPatch(c,'primary_class_level',7);
 assert.equal(patch.classes[0].level,7);
 assert.equal(patch.level,9);
 assert.equal(c.classes[0].level,4);
 assert.throws(()=>identityPatch(c,'primary_class_level',19),/somma dei livelli/);
 assert.throws(()=>identityPatch(c,'level',10),/calcolato automaticamente/);
 const html=nativeSection(c,'info',{field:(name,key,value)=>'<input data-field="'+key+'" value="'+value+'">',
   area:()=>'',panel:(_title,body)=>body,catalogs:{},calculated:{stats:{},values:{}}});
 assert.match(html,/data-field="primary_class_level"/);
 assert.doesNotMatch(html,/data-field="level"/);
 assert.match(html,/Liv\. totale\s*<output aria-label="Livello totale automatico">6<\/output>/);
 assert.doesNotMatch(html,/data-field="level"/);
});
test('all sheet readouts expose effective values and native bonus targets, including legacy HP alias',()=>{
 const out=calculateSheet({abilities:{dex:14},max_hp_base:10,formula_bonuses:[
  {target:'ability:dex',expression:'2',origin_name:'Scelta'},
  {target:'skill:stealth',expression:'1'}, {target:'max_hp',expression:'3'}]});
 assert.equal(out.values['ability:dex'],16);
 assert.equal(out.values['ability_mod:dex'],3);
 assert.equal(out.values['skill:stealth'],4);
 assert.equal(out.values.ac,13);
 assert.equal(out.values.initiative,3);
 assert.equal(out.values.hp,13);
 assert.match(out.explanations['ability:dex'],/Scelta.*2/);
});
test('native casting tables preserve editions, class ownership, cantrip limits and wizard spellbook',()=>{
 const c={rules_version:'2014',classes:[{name:'Wizard',source:'PHB',level:5},{name:'Warlock',source:'PHB',level:3}],abilities:{int:16,cha:14}};
 const members=castingClasses(c,mechanics,{int:3,cha:2});
 const [wizard,warlock]=members;
 assert.deepEqual([wizard.limit,wizard.cantrips,wizard.max_level,wizard.book],[8,4,3,true]);
 assert.deepEqual([warlock.limit,warlock.max_level],[4,2]);
 const modern=castingClasses({...c,rules_version:'2024',classes:[{name:'Wizard',source:'XPHB',level:5}]},mechanics,{int:5});
 assert.equal(modern[0].limit,9,'2024 uses its table rather than ability + level');
 const spell={id:'spell:shield|phb',name:'Shield',source:'PHB',level:1,classes:['Wizard','Warlock']};
 const options={member:wizard,classes:members,catalog:[spell]};
 assert.throws(()=>addSelectedSpell(c,spell,'prepared_spells',options),/libro/);
 const book=addSelectedSpell(c,spell,'spellbook_spells',options);
 const prepared=addSelectedSpell({...c,...book},spell,'prepared_spells',options);
 assert.deepEqual(prepared.prepared_spells[0].casting_classes,[wizard.id]);
 const shared=addSelectedSpell({...c,...prepared},spell,'prepared_spells',{...options,member:warlock});
 assert.deepEqual(shared.prepared_spells[0].casting_classes,[wizard.id,warlock.id]);
 const removed=removeSelectedSpell({...c,...shared},'prepared_spells',0,{classId:warlock.id,classes:members,catalog:[spell]});
 assert.deepEqual(removed.prepared_spells[0].casting_classes,[wizard.id]);
 assert.equal(shared.prepared_spells[0].casting_classes.length,2,'input never mutated');
});
test('slot counters distinguish class/pact, keep manual totals and recover without changing spell selections',()=>{
 const c={class:'Wizard',level:5,classes:[{name:'Wizard',level:5},{name:'Warlock',level:3}],spell_slots_spent:[0,1],pact_slots_spent:1,prepared_spells:[{id:'keep'}]};
 const out=calculateSheet(c,catalogs);
 assert.equal(out.spell_slots[0].total,4);
 assert.equal(out.pact_slots.total,2);
 assert.equal(slotUsePatch(c,1,1,out).spell_slots_spent[1],2);
 assert.deepEqual(slotUsePatch(c,0,-1,out),{pact_slots_spent:0});
 assert.throws(()=>slotUsePatch({...c,pact_slots_spent:2},0,1,out),/Nessuno/);
 assert.deepEqual(c.prepared_spells,[{id:'keep'}]);
 const manual=calculateSheet({...c,spell_slots_manual:true,spell_slots_total:[0,7],pact_slots_total:4,formula_bonuses:[{target:'slot:1',expression:'2'}]},catalogs);
 assert.equal(manual.spell_slots[0].base,7);
 assert.equal(manual.spell_slots[0].total,9);
 assert.equal(manual.pact_slots.total,4);
});
test('resources use native IDs, formulas, subclass gating and explicit rest recovery',()=>{
 const c={class:'Bard',class_source:'PHB',level:5,abilities:{cha:16},resource_trackers:[{id:'custom',name:'Personal',max:1,max_formula:'proficiency + 1',recharge:'manual'}],resource_tracker_spent:{'class:bard:phb:bardic_inspiration':2,custom:1,unknown:4}};
 const out=calculateSheet(c,{...catalogs,classFeatures:JSON.parse(readFileSync(new URL('../catalog/classes.json',import.meta.url),'utf8'))});
 const inspiration=out.trackers.find(t=>t.id==='class:bard:phb:bardic_inspiration');
 assert.ok(inspiration);
 assert.equal(inspiration.max,3);
 assert.equal(inspiration.recharge,'short_rest');
 assert.equal(out.trackers.find(t=>t.id==='custom').max,4);
 assert.deepEqual(recoveryPatch(c,'short_rest',out.trackers).resource_tracker_spent,{custom:1,unknown:4});
 const monk=resourceTrackers({class:'Monk',class_source:'PHB',level:6,subclass:'Way of Shadow'},mechanics);
 assert.equal(monk.some(t=>t.name==='Wholeness of Body'),false);
 const monster=resourceTrackers({kind:'monster',stat_block:{legendaryActions:3,action:[{name:'Breath {@recharge 5}'}]}},mechanics);
 assert.deepEqual(monster.map(t=>[t.id,t.max,t.recharge]),[['legendary_actions',3,'turn'],['recharge:action:0',1,'d6']]);
});
test('species speeds resolve from native identity, replacing stale snapshots and keeping explicit special overrides',()=>{
 const out=calculateSheet({kind:'character',species:'Aarakocra',species_source:'EEPC',speed_base:99,species_speed:{walk:99},movement_speeds:{swim:15}},catalogs);
 assert.equal(out.stats.speeds.walk,25);
 assert.equal(out.stats.speeds.fly,50);
 assert.equal(out.stats.speeds.swim,15);
});
test('equipped attacks calculate proficiency, finesse, offhand damage, thrown range and native enhancement IDs',()=>{
 const weapon={id:'shortsword',name:'Shortsword',type:'M',weapon_category:'martial',damage:'1d6',properties:['F','L'],quantity:2,equipped_slots:['main','off']};
 const c={kind:'character',level:5,class:'Fighter',abilities:{str:12,dex:18},attack_ability:'dex',inventory:[weapon],proficiency_choices:[{kind:'weapon',key:'martial'}],formula_bonuses:[{target:'attack_hit:item:shortsword',expression:'1'}]};
 const out=calculateSheet(c,catalogs);
 assert.deepEqual(out.attacks.map(a=>[a.id,a.hit,a.damage]),[['item:shortsword',8,'1d6 + 4'],['item:off:shortsword',7,'1d6']]);
 assert.equal(out.attacks[1].offhand_bonus,true);
 const style=calculateSheet({...c,two_weapon_fighting:true},catalogs);
 assert.equal(style.attacks[1].damage,'1d6 + 4');
 const thrown=calculateSheet({...c,inventory:[{...weapon,id:'dagger',properties:['F','L','T'],range:'20/60',equipped_slots:['main']}]},catalogs);
 assert.deepEqual(thrown.attacks.map(a=>[a.id,a.range_feet,a.long_range_feet]),[['item:dagger',5,0],['item:throw:main:dagger',20,60]]);
 const monster=calculateSheet({kind:'monster',abilities:{str:20},stat_block:{action:[{name:'Bite',entries:['{@atk mw} {@hit 7} reach 10 ft. {@damage 2d6 + 5} damage.']}]}},catalogs);
 assert.equal(monster.attacks[0].hit,7);
 assert.equal(monster.attacks[0].damage,'2d6 + 5');
});
test('shared equipment rules support every attack ability, finesse scope, off-hand style and versatile two-hand lock',()=>{
 const longsword={id:'blade',name:'Longsword',type:'M',weapon_category:'martial',damage:'1d8',
   versatile_damage:'1d10',properties:['V'],quantity:1,equipped_slots:['main']};
 const dagger={id:'dagger',name:'Dagger',type:'M',weapon_category:'simple',damage:'1d4',
   properties:['F','L'],quantity:1,equipped_slots:['off']};
 const creature={kind:'character',abilities:{str:12,dex:14,con:10,int:10,wis:18,cha:10},
   attack_ability:'wis',attack_ability_finesse_only:false,
   inventory:[longsword,dagger],hand_grip_two_handed:false,
   proficiency_choices:[{kind:'weapon',key:'martial'},{kind:'weapon',key:'simple'}]};
 const both=calculateSheet(creature,catalogs);
 assert.equal(both.attacks.find(a=>a.id==='item:blade').ability,'wis');
 assert.equal(both.attacks.find(a=>a.id==='item:off:dagger').ability,'wis');
 const finesseOnly=calculateSheet({...creature,attack_ability_finesse_only:true},catalogs);
 assert.equal(finesseOnly.attacks.find(a=>a.id==='item:blade').ability,'str');
 assert.equal(finesseOnly.attacks.find(a=>a.id==='item:off:dagger').ability,'wis');
 const versatile=calculateSheet({...creature,hand_grip_two_handed:true},catalogs);
 assert.equal(versatile.attacks.find(a=>a.id==='item:blade').damage,'1d8 + 4',
   'Stale occupied offhand prevents versatile damage until the slot is cleared');
 assert.equal(versatile.attacks.some(a=>a.id==='item:off:dagger'),false,
   'Offhand attacks cannot survive two-hand versatile grip, even for imported stale slots');
 const freeHand=calculateSheet({...creature,hand_grip_two_handed:true,inventory:[longsword]},catalogs);
 assert.equal(freeHand.attacks.find(a=>a.id==='item:blade').damage,'1d10 + 4');
 const twin={...creature,hand_grip_two_handed:false,
   inventory:[{...dagger,equipped_slots:['main']},{...dagger,id:'off-dagger',equipped_slots:['off']}]};
 const withoutStyle=calculateSheet(twin,catalogs);
 const withStyle=calculateSheet({...twin,two_weapon_fighting:true},catalogs);
 assert.equal(withoutStyle.attacks.find(a=>a.slot==='off').damage,'1d4');
 assert.equal(withStyle.attacks.find(a=>a.slot==='off').damage,'1d4 + 4');
 for(const ability of ['str','dex','con','int','wis','cha']){
   const selected=calculateSheet({...creature,attack_ability:ability},catalogs);
   assert.equal(selected.attacks.find(a=>a.id==='item:blade').ability,ability);
 }
});

test('class and subclass catalog edits keep legacy fields and multi-class IDs coherent',()=>{
 const c={class:'Wizard',class_id:'old',class_source:'PHB',subclass:'Evoker',subclass_source:'PHB',subclass_id:'oldsub',level:5,
  classes:[{id:'old',name:'Wizard',source:'PHB',level:5,subclass:'Evoker',subclass_source:'PHB',subclass_id:'oldsub'}]};
 const patch=referencePatch(c,'class',{id:'new',name:'Wizard',source:'XPHB'});
 assert.deepEqual([patch.class_id,patch.class_source,patch.classes[0].id,patch.classes[0].source],['new','XPHB','new','XPHB']);
 assert.equal(patch.subclass,'');assert.equal(patch.classes[0].subclass_id,'');
 const row=rowReferencePatch(c,'classes',0,'subclass',{name:'Abjurer',source:'XPHB',id:'abjurer'});
 assert.equal(row.subclass_id,'abjurer');assert.equal(row.classes[0].subclass_source,'XPHB');
 assert.equal(c.subclass_id,'oldsub');
});
test('manual origin powers follow origin toggles and automatic bonus switches keep native IDs',()=>{
 const id='custom_origin';
 const c={kind:'character',level:3,proficiency_origins:[{id,name:'Chosen',disabled:false}],origin_spell_grants:[{id:'grant',origin_id:id,spell_id:'shield',payment_mode:'free'},{id:'duplicate',origin_id:id,spell_id:'shield'}]};
 assert.equal(calculateSheet(c,catalogs).origin_spells.length,1,'duplicate origin/spell pairs are projected once');
 assert.equal(calculateSheet({...c,origin_enabled:{[id]:false}},catalogs).origin_spells.length,0);
 assert.equal(c.origin_spell_grants.length,2,'projection never rewrites imported rows');
});
test('bundled PWA native tables and resource definitions are generated without divergence',t=>{
 const nativePath=new URL('../../vtt/data/class_mechanics_5etools.json',import.meta.url);
 const overridesPath=new URL('../../vtt/data/class_resource_overrides.json',import.meta.url);
 if(!existsSync(nativePath)||!existsSync(overridesPath))
   return t.skip('Source comparison requires full checkout; browser-assets checks out only pwa/.');
 const native=JSON.parse(readFileSync(nativePath,'utf8'));
 const overrides=JSON.parse(readFileSync(overridesPath,'utf8'));
 assert.deepEqual(mechanics.classes,native.classes);
 const sourceKeys=new Set(overrides.classes.map(row=>row.class+'|'+row.source));
 assert.deepEqual(mechanics.resource_overrides.filter(row=>sourceKeys.has(row.class+'|'+row.source)),overrides.classes);
 const normalized=mechanics.resource_overrides.filter(row=>!sourceKeys.has(row.class+'|'+row.source));
 assert(normalized.every(row=>row.source==='XPHB'));
 assert.deepEqual(normalized.map(row=>row.class).sort(),['Fighter','Paladin','Sorcerer','Wizard']);
 // The runtime normalization is compared to Godot in compare_native_features.
 const paladin=normalized.find(row=>row.class==='Paladin').resources.find(row=>row.name==='Lay on Hands');
 assert.equal(paladin.steps.length,20);
 assert.equal(paladin.steps[8].value,'45');
});

test('removing a spell assigned to another class cannot delete it',()=>{
 const wizard='class|phb|wizard',warlock='class|phb|warlock';
 const spell={id:'shield',name:'Shield',level:1,casting_classes:[wizard]};
 const c={prepared_spells:[spell],spells:[spell]};
 assert.throws(()=>removeSelectedSpell(c,'prepared_spells',0,{
  classId:warlock,classes:[{id:wizard,name:'Wizard'},{id:warlock,name:'Warlock'}]
 }),/non assegnato alla classe/);
 assert.deepEqual(c.prepared_spells,[spell]);
 const removed=removeSelectedSpell(c,'prepared_spells',0,{classId:wizard});
 assert.deepEqual(removed.prepared_spells,[]);
 const shared={...c,prepared_spells:[{...spell,casting_classes:[wizard,warlock]}]};
 const onlyWizard=removeSelectedSpell(shared,'prepared_spells',0,{classId:warlock});
 assert.deepEqual(onlyWizard.prepared_spells[0].casting_classes,[wizard]);
});

test('classes header displays non-editable total level and editable XP on one line',()=>{
 const c={kind:'character',class:'Wizard',level:5,xp:1250,classes:[{name:'Wizard',level:3},{name:'Fighter',level:2}]};
 const markup=nativeSection(c,'info',{
  field:(label,key,value)=>'<label>'+label+'<input data-field="'+key+'" value="'+value+'"></label>',
  area:()=>'',panel:(title,body,cls='')=>'<section class="panel '+cls+'"><h2>'+title+'</h2>'+body+'</section>',
  catalogs:{},calculated:calculateSheet(c)
 });
 assert(markup.includes('class="panel classes-progression-panel"'));
 assert(markup.includes('class="progression-summary"'));
 assert(markup.includes('<output aria-label="Livello totale automatico">5</output>'));
 assert(markup.includes('data-field="xp" value="1250"'));
 assert(!markup.includes('Livello totale<input'));
});

test('battle context separates movement from identity and displays the equipped AC formula without hiding fields',()=>{
 const armor={id:'chain-shirt',name:'Cotta di maglia',type:'MA',ac:14,quantity:1,equipped_slots:['body']};
 const creature={kind:'character',abilities:{str:12,dex:16,con:12,int:10,wis:10,cha:10},
  armor_natural_formula:'12 + dex_mod',inventory:[armor]};
 const panel=(title,body,className='')=>'<section class="'+className+'"><h2>'+title+'</h2>'+body+'</section>';
 const view=(c,section)=>nativeSection(c,section,{panel,field:()=>'',area:()=>'',armor:'<label>Armatura indossata<select data-equip-slot="body"></select></label>',equipment:'',resources:'',attacks:'',calculated:calculateSheet(c,catalogs)});
 const battle=view(creature,'battle');
 assert.match(battle,/class="battle-movement-panel"/);
 assert.match(battle,/class="battle-defense-panel"/);
 assert.match(battle,/data-equip-slot="body"/);
 assert.match(battle,/Formula armatura indossata/);
 assert.match(battle,/14 \+ \(2 DES\)/);
 assert.doesNotMatch(battle,/data-field="armor_natural_formula"/);
 assert.doesNotMatch(battle,/<summary>Armatura e CA naturale<\/summary>/);
 assert.doesNotMatch(battle,/data-calculated="initiative"/);
 assert.doesNotMatch(battle,/data-act="sheet-details" data-detail="formula_bonuses"/);
 assert.doesNotMatch(view(creature,'info'),/<h3>Velocità<\/h3>/);
 const natural=view({...creature,inventory:[]},'battle');
 assert.match(natural,/Formula CA naturale/);
 assert.match(natural,/12 \+ dex_mod/);
 assert.doesNotMatch(natural,/Formula armatura indossata/);
});

test('only spells with duration can remain applied on the conditions sheet',()=>{
 assert(isPersistentSpell({has_duration:true}));
 assert(!isPersistentSpell({has_duration:false,duration:'1 hour'}));
 assert(isPersistentSpell({duration:[{type:'timed',duration:{type:'minute',amount:1}}]}));
 assert(!isPersistentSpell({duration:[{type:'instant'}]}));
 assert(isPersistentSpell({duration:'Concentration, up to 1 minute'}));
 assert(!isPersistentSpell({duration:'Instantaneous'}));
 assert(!isPersistentSpell({duration:''}));
});
