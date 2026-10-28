import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {projectSpeciesRollModes} from '../tools/species_roll_modes.mjs';
import {selectedSpeciesRollModeRules,speciesRollModeEntries,speciesRollModeFeatures,
 speciesRollModeMatches,speciesRollModeTrackers,applicableSpeciesRollModes} from '../species_roll_modes.js';
import {calculateSheet} from '../sheet_rules.js';
import {classFeatureRollSources,resolveClassRollMode} from '../feature_mechanics.js';
import {rollSheetDice} from '../sheet_rules_view.js';
import {traitBenefitGroups,rollGrantTraitRow} from '../trait_benefits.js';
import {collectTraitRows} from '../trait_projection.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const refs=read('../../vtt/data/creature_references_5etools.json');
const catalog=read('../catalog/species_roll_modes.json');
const find=(name,source)=>refs.races.find(x=>x.name===name&&x.source===source);
const character=(species,source,extra={})=>({
 kind:'character',rules_version:'2014',level:5,
 species,species_source:source,species_id:find(species,source)?.id||'',
 abilities:{str:10,dex:10,con:10,int:10,wis:10,cha:10},...extra
});
const project=record=>{
 const features=speciesRollModeFeatures(record,catalog,[]);
 return {features,entries:speciesRollModeEntries(record,catalog,features)};
};

test('native pre-2024 racial roll modes regenerate exactly from reviewed traits',()=>{
 assert.deepEqual(projectSpeciesRollModes(refs.races),catalog);
 assert.equal(catalog.version,1);
 assert.ok(catalog.races.length>=95);
 assert.ok(catalog.races.every(x=>!['XPHB','XDMG','XMM','EFA','LFL','RHW'].includes(x.source)));
 const exceptions=new Set(['Hawkeyed','Firearms Mastery','Fey Gift','Taunt',
  'Grovel, Cower, and Beg','Timberwalk']);
 for(const race of refs.races.filter(x=>!['XPHB','XDMG','XMM','EFA','LFL','RHW','ABH','FRHOF','AU','SRD52','BQGT','FFOTR'].includes(x.source))){
  for(const trait of race.entries||[]){
   if(!/\badvantage\b|\bdisadvantage\b/i.test(JSON.stringify(trait.entries||[])))continue;
   if(exceptions.has(trait.name))continue; // Non-user advantage, or negation of normal long-range DIS.
   assert.ok(catalog.races.find(x=>x.name===race.name&&x.source===race.source)
    ?.rules.some(x=>x.trait===trait.name),race.name+' '+race.source+' '+trait.name);
  }
 }
});

test('Drow daylight disadvantages are manual, apply to all attacks and sight-based Perception',()=>{
 const c=character('Elf (Drow)','PHB');
 const {entries}=project(c),sun=entries.filter(x=>x.granting_trait==='Sunlight Sensitivity');
 assert.equal(sun.length,2);
 assert.ok(sun.every(x=>x.mode==='disadvantage'&&x.conditional&&x.condition_label.includes('solare diretta')));
 assert.equal(applicableSpeciesRollModes(c,{racial_roll_modes:entries},'casting_hit:int').length,1);
 assert.equal(applicableSpeciesRollModes(c,{racial_roll_modes:entries},'attack_hit:blade').length,1);
 assert.equal(applicableSpeciesRollModes(c,{racial_roll_modes:entries},'skill:perception').length,1);
 assert.equal(applicableSpeciesRollModes(c,{racial_roll_modes:entries},'save:wis').length,1);
 assert.ok(!classFeatureRollSources(c,{features:[],racial_roll_modes:entries},'attack_hit:blade')
  .some(x=>x.mode==='disadvantage'));
 const light=applicableSpeciesRollModes(c,{racial_roll_modes:entries},'attack_hit:blade')[0];
 assert.equal(resolveClassRollMode([{mode:'advantage'}, {mode:light.roll_mode}]).mode,'normal');
});

test('Kuo-Toa and Troglodyte sunlight penalties require self exposure',()=>{
 for(const species of ['Kuo-Toa','Troglodyte']){
  const clauses=project(character(species,'DMG')).entries.filter(row=>
   row.granting_trait==='Sunlight Sensitivity');
  assert.equal(clauses.length,2);
  assert.ok(clauses.every(row=>row.condition_label.includes('sei alla luce solare')||
   row.condition_label.includes('alla luce solare diretta')));
  assert.ok(!clauses.some(row=>row.condition_label.includes('bersaglio')));
 }
});

test('Elf plus selected Drow, and flattened Elf (Drow), both retain race and subrace modes',()=>{
 const flat=character('Elf (Drow)','PHB');
 const nested=character('Elf','PHB',{subrace:'Drow',subrace_source:'PHB'});
 const f=project(flat).entries,n=project(nested).entries;
 assert.equal(f.filter(x=>x.granting_trait==='Fey Ancestry').length,1);
 assert.equal(n.filter(x=>x.granting_trait==='Fey Ancestry').length,1);
 assert.equal(f.filter(x=>x.granting_trait==='Sunlight Sensitivity').length,2);
 assert.equal(n.filter(x=>x.granting_trait==='Sunlight Sensitivity').length,2);
 assert.deepEqual(new Set(f.map(x=>x.target)),new Set(n.map(x=>x.target)));
});

test('Dwarf, gnome, halfling and aasimar inherit only actual source-qualified benefits',()=>{
 const dwarf=project(character('Dwarf','PHB')).entries;
 assert.equal(dwarf.length,1);
 assert.match(dwarf[0].condition_label,/veleno/i);
 const hill=project(character('Dwarf','PHB',{subrace:'Hill',subrace_source:'PHB'})).entries;
 assert.equal(hill.length,1);
 assert.equal(project(character('Gnome','PHB')).entries.length,3);
 assert.deepEqual(project(character('Gnome','PHB')).entries.map(x=>x.target).sort(),
  ['save:cha','save:int','save:wis']);
 assert.equal(project(character('Halfling','PHB')).entries[0].target,'saving_throw');
 assert.equal(project(character('Aasimar','MPMM')).entries.length,0);
 assert.equal(project(character('Elf','PHB',{rules_version:'2024'})).entries.length,0);
});

test('unconditional Giff strength advantages are automatic but sunlight is not',()=>{
 const c=character('Giff','AAG');
 const {entries}=project(c);
 assert.equal(entries.length,2);
 assert.ok(entries.every(x=>!x.condition_label));
 const auto=classFeatureRollSources(c,{features:[],racial_roll_modes:entries},'save:str');
 assert.ok(auto.some(x=>x.mode==='advantage'));
 assert.equal(classFeatureRollSources(c,{features:[],racial_roll_modes:entries},'save:dex').length,0);
 assert.ok(speciesRollModeMatches(entries[0],'skill:athletics',{}));
 assert.ok(!speciesRollModeMatches(entries[0],'skill:stealth',{}));
});

test('disabling a named trait suppresses its modes and leaves the species intact',()=>{
 const c=character('Elf (Drow)','PHB');
 const original=project(c);
 const sunlight=original.features.find(x=>x.name==='Sunlight Sensitivity');
 assert.ok(sunlight);
 const disabled={...c,trait_enabled:{[sunlight.key]:false}};
 const after=project(disabled);
 assert.ok(after.entries.every(x=>x.granting_trait!=='Sunlight Sensitivity'));
 assert.ok(after.entries.some(x=>x.granting_trait==='Fey Ancestry'));
 const originalSource=original.entries.find(x=>x.granting_trait==='Sunlight Sensitivity');
 const suppressed=speciesRollModeEntries(c,catalog,original.features,new Set([originalSource.benefit_id]));
 assert.equal(suppressed.filter(x=>x.granting_trait==='Sunlight Sensitivity').length,1);
});

test('limited-use racial check advantages get a stable per-trait tracker',()=>{
 const c=character('Deep Gnome','MPMM');
 const {entries}=project(c);
 const camouflage=entries.find(x=>x.granting_trait==='Svirfneblin Camouflage');
 assert.ok(camouflage);
 assert.equal(camouflage.tracker_id,'species-roll:'+camouflage.origin_id);
 const tracker=speciesRollModeTrackers(c,entries,4).find(row=>row.id===camouflage.tracker_id);
 assert.equal(tracker.max,4);
 assert.equal(tracker.recharge,'long_rest');
 const kenku=project(character('Kenku','MPMM')).entries;
 const kenkuRule=kenku.find(x=>x.granting_trait==='Kenku Recall');
 assert.ok(kenkuRule?.tracker_id);
 assert.equal(applicableSpeciesRollModes({},{
  racial_roll_modes:kenku,proficiencies:['skill:arcana']},'skill:arcana')
  .filter(row=>row.granting_trait==='Kenku Recall').length,1);
 assert.equal(applicableSpeciesRollModes({},{
  racial_roll_modes:kenku,proficiencies:['skill:arcana']},'skill:stealth')
  .filter(row=>row.granting_trait==='Kenku Recall').length,0);
});

test('racial modes appear as attributed benefits, with conditions, on their own traits',()=>{
 const c=character('Elf (Drow)','PHB'),rules=project(c);
 const feature=rules.features.find(x=>x.name==='Sunlight Sensitivity');
 const summary=traitBenefitGroups({name:feature.name,feature_origin:feature.origin_id,
  origin_key:feature.origin_key,category:'razza',rank:2},c,{features:rules.features,
    racial_roll_modes:rules.entries,attacks:[],casting_classes:[]});
 const group=summary.find(x=>x.type==='roll_modes');
 assert.equal(group?.items.length,2);
 assert.ok(group.items.some(x=>x.value.includes('Svantaggio')&&x.value.includes('luce solare')));
 const sibling=traitBenefitGroups({name:'Fey Ancestry',feature_origin:'other',origin_key:feature.origin_key,
  category:'razza',rank:2},c,{features:rules.features,racial_roll_modes:rules.entries,
  attacks:[],casting_classes:[]});
 assert.ok(!sibling.some(x=>x.type==='roll_modes'&&
   x.items.some(y=>y.value.includes('luce solare'))));
});

test('calculated PWA sheets expose racial modes and real uses without custom roll toggles',()=>{
 const drow=character('Elf (Drow)','PHB');
 const original=find('Elf (Drow)','PHB');
 const calculated=calculateSheet(drow,{speciesRollModes:catalog,
  originDetails:{races:{'elf (drow)|phb':original}}});
 assert.equal(calculated.racial_roll_modes.filter(x=>x.granting_trait==='Sunlight Sensitivity').length,2);
 assert.ok(calculated.features.some(x=>x.name==='Sunlight Sensitivity'));
 assert.ok(!classFeatureRollSources(drow,calculated,'attack_hit:test').some(x=>x.mode==='disadvantage'));
 const kenku=character('Kenku','MPMM');
 const second=calculateSheet(kenku,{speciesRollModes:catalog,
  originDetails:{races:{'kenku|mpmm':find('Kenku','MPMM')}}});
 const roll=second.racial_roll_modes.find(row=>row.granting_trait==='Kenku Recall');
 assert.ok(roll?.tracker_id);
 const computedProficiency=Number(second.values.proficiency);
 assert.ok(second.trackers.some(tracker=>tracker.id===roll.tracker_id&&
  tracker.max===computedProficiency&&tracker.recharge==='long_rest'),
  'Kenku Recall recovers PB uses, using the PWA computed proficiency bonus');
});

test('confirming a situational racial disadvantage rolls two d20, not a numeric bonus',()=>{
 const c=character('Elf (Drow)','PHB'),projected=project(c).entries;
 const chosen=applicableSpeciesRollModes(c,{racial_roll_modes:projected},'attack_hit:blade')
  .map(row=>({mode:row.roll_mode,origin_id:row.origin_id,origin_name:row.origin_name}));
 assert.equal(chosen.length,1);
 const resolution=resolveClassRollMode(chosen);
 assert.equal(resolution.mode,'disadvantage');
 let i=0;const dice=[18,5];
 const rolled=rollSheetDice(3,[],sides=>sides===20?dice[i++]:1,resolution.mode);
 assert.deepEqual(rolled.rolls,[18,5]);
 assert.equal(rolled.total,8);
 assert.equal(rolled.count,2);
 assert.equal(resolveClassRollMode([{mode:'advantage'},...chosen]).mode,'normal');
});

test('mirino opens the specific Drow trait even for flattened or split race selections',async()=>{
 for(const record of [
  character('Elf (Drow)','PHB'),
  character('Elf','PHB',{subrace:'Drow',subrace_source:'PHB'})
 ]){
  const mode=project(record);
  const row=mode.entries.find(x=>x.granting_trait==='Sunlight Sensitivity');
  const traits=await collectTraitRows(record,{features:mode.features,origins:[]},{
   entries:async category=>category==='races'?
    [find('Elf','PHB'),find('Elf (Drow)','PHB')]:[],
   detail:async(_category,entry)=>entry
  });
  const exact=rollGrantTraitRow(traits,record,row.origin_id,{
   traitName:row.granting_trait,originKey:row.origin_key
  });
  assert.equal(exact?.name,'Sunlight Sensitivity');
  assert.equal(exact?.origin_key,row.origin_key);
  // A stale or differently projected feature id must still find the right
  // origin-qualified card, without falling back to the broad species header.
  const stale=rollGrantTraitRow(traits,record,'feature:legacy:stale',{
   traitName:row.granting_trait,originKey:row.origin_key
  });
  assert.equal(stale?.key,exact?.key);
  assert.notEqual(exact?.rank,0);
 }
});

test('roll target icon routes racial modes to trait, other bonuses to their trackers',()=>{
 const source=readFileSync(new URL('../ui.js',import.meta.url),'utf8');
 assert.match(source,/racialMode\?'roll-origin-open':'sheet-roll-open-tracker'/);
 assert.match(source,/data-origin-trait/);
 assert.match(source,/data-origin-key/);
 const css=readFileSync(new URL('../mobile_metal_theme.css',import.meta.url),'utf8');
 assert.match(css,/\.sheet-roll-bonus-condition-text\{/);
 assert.match(css,/\.sheet-roll-mode-symbol--disadvantage\{/);
});
