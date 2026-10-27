import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {projectSpeciesDefenses} from '../tools/species_defenses.mjs';
import {speciesDefenseEntries,selectedSpeciesDefenseRules} from '../species_defenses.js';
import {calculateSheet} from '../sheet_rules.js';
import {traitBenefitGroups} from '../trait_benefits.js';
import {pendingCharacterChoices,savePendingChoice} from '../pending_choices.js';
import {collectTraitRows} from '../trait_projection.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const source=read('../../vtt/data/creature_references_5etools.json');
const catalog=read('../catalog/species_defenses.json');
const find=(name,book)=>source.races.find(r=>r.name===name&&r.source===book);
const abilities={str:10,dex:10,con:10,int:10,wis:10,cha:10};
const creature=(name,book,changes={})=>({
 kind:'character',rules_version:'2014',level:1,abilities,inventory:[],
 species:name,species_source:book,species_id:find(name,book).id,...changes
});
const calculate=(record)=>calculateSheet(record,{speciesDefenses:catalog,
 originDetails:{races:{[record.species.toLowerCase()+'|'+record.species_source.toLowerCase()]:
  find(record.species,record.species_source)}}});
const effects=sheet=>sheet.damage_defense_entries.filter(r=>r.automatic);
const keys=sheet=>effects(sheet).map(r=>r.rank+':'+r.key).sort();

test('checked-in pre-2024 defense data exactly matches structured native race fields',()=>{
 assert.deepEqual(projectSpeciesDefenses(source.races),catalog);
 assert.equal(catalog.version,1);
 assert.ok(catalog.races.length>=70);
 assert.ok(catalog.races.every(row=>row.source!=='XPHB'));
 assert.ok(catalog.races.every(row=>row.entries.every(e=>e.trait&&[-1,1,2,3].includes(e.rank))));
 assert.ok(catalog.races.some(row=>row.name==='Aasimar'&&row.source==='MPMM'));
});

test('latest pre-2024 Aasimar grants radiant and necrotic resistance only to Celestial Resistance',()=>{
 const character=creature('Aasimar','MPMM');
 const sheet=calculate(character);
 assert.deepEqual(keys(sheet),['1:necrotic','1:radiant']);
 const grants=effects(sheet);
 assert.equal(new Set(grants.map(g=>g.origin_id)).size,1);
 const feature=sheet.features.find(row=>row.name==='Celestial Resistance');
 assert.ok(feature);
 assert.equal(grants[0].origin_id,feature.origin_id);
 const named=traitBenefitGroups({name:feature.name,feature_origin:feature.origin_id,
  origin_key:feature.origin_key,category:'razza',rank:2},character,sheet);
 assert.deepEqual(named.find(g=>g.type==='defenses')?.items.map(i=>i.value),['Necrotici','Radianti']);
 const overview=traitBenefitGroups({name:'Descrizione · Aasimar',
  origin_key:feature.origin_key,category:'razza',rank:0},character,sheet);
 assert.ok(!overview.some(g=>g.type==='defenses'),'do not collapse racial trait benefits to species overview');
});

test('turning off an owned trait, whole species or its entry removes automatic defenses',()=>{
 const character=creature('Aasimar','MPMM');
 const first=calculate(character);
 const feature=first.features.find(f=>f.name==='Celestial Resistance');
 assert.deepEqual(keys(calculate({...character,origin_enabled:{[feature.origin_id]:false}})),[]);
 assert.deepEqual(keys(calculate({...character,trait_enabled:{[feature.key]:false}})),[]);
 assert.deepEqual(keys(calculate({...character,
  origin_enabled:{'race|mpmm|aasimar':false}})),[]);
 const removed='defense:race|mpmm|aasimar:1:radiant';
 assert.deepEqual(keys(calculate({...character,trait_benefit_removed:{[feature.key]:[removed]}})),
  ['1:necrotic']);
 assert.deepEqual(keys(calculate(character)),['1:necrotic','1:radiant']);
});

test('automatic defenses remain source-qualified and do not contaminate other editions or species',()=>{
 const mpmm=creature('Aasimar','MPMM');
 assert.deepEqual(keys(calculate(mpmm)),['1:necrotic','1:radiant']);
 assert.deepEqual(speciesDefenseEntries({...mpmm,species:'Other'},catalog),[]);
 assert.deepEqual(speciesDefenseEntries({...mpmm,species_source:'XPHB',species_id:''},catalog),[]);
 assert.deepEqual(keys(calculate(creature('Yuan-Ti','MPMM'))),['1:poison']);
 assert.deepEqual(keys(calculate(creature('Warforged','ERLW'))),['1:poison','3:disease']);
 assert.deepEqual(keys(calculate(creature('Autognome','AAG'))),['1:poison','3:disease']);
});

test('damage immunity, condition immunity and vulnerability are distinct fixed grants',()=>{
 const sheet=calculate(creature('Skeleton','DMG'));
 assert.deepEqual(keys(sheet),['-1:bludgeoning','2:poison','3:exhaustion','3:poisoned']);
 assert.equal(effects(sheet).find(row=>row.rank===-1)?.granting_trait,'Brittle Bones');
 assert.equal(effects(sheet).find(row=>row.rank===2)?.granting_trait,'Undead Nature');
});

test('ancestry-choice resistance is never invented before a legal selected damage type',()=>{
 const defaultCharacter=creature('Dragonborn (Chromatic)','FTD');
 assert.deepEqual(keys(calculate(defaultCharacter)),[]);
 const selected={...defaultCharacter,
  origin_defense_choices:{'race|ftd|dragonborn (chromatic)':'fire'}};
 assert.deepEqual(keys(calculate(selected)),['1:fire']);
 assert.deepEqual(keys(calculate({...defaultCharacter,
  origin_defense_choices:{'race|ftd|dragonborn (chromatic)':'psychic'}})),[]);
});

test('inherited variant data remains attached to matching source and real trait',()=>{
 const hill=catalog.races.find(row=>row.name==='Dwarf (Hill)'&&row.source==='PHB');
 const fallen=catalog.races.find(row=>row.name==='Aasimar (Fallen)'&&row.source==='VGM');
 assert.deepEqual(hill.entries.map(x=>x.key),['poison']);
 assert.deepEqual(fallen.entries.map(x=>x.key).sort(),['necrotic','radiant']);
});

test('dragonborn resistance is chosen through the ordinary pending choice UI and persists',()=>{
 const character=creature('Dragonborn (Gem)','FTD');
 const sheet=calculate(character);
 const choice=pendingCharacterChoices(character,sheet,{speciesDefenses:catalog})
  .find(row=>row.kind==='defense');
 assert.ok(choice,'the source-qualified damage choice must be offered');
 assert.equal(choice.remaining,1);
 assert.ok(choice.options.includes('psychic'));
 const patch=savePendingChoice(character,choice,['psychic']);
 assert.equal(patch.origin_defense_choices['race|ftd|dragonborn (gem)'],'psychic');
 const saved={...character,...patch};
 assert.deepEqual(keys(calculate(saved)),['1:psychic']);
 const selected=pendingCharacterChoices(saved,calculate(saved),{speciesDefenses:catalog})
  .find(row=>row.kind==='defense');
 assert.deepEqual(selected.selected,['psychic']);
 const cleared=savePendingChoice(saved,selected,[]);
 assert.deepEqual(keys(calculate({...saved,...cleared})),[]);
});

test('2014 PHB Dwarf retains poison resistance with no subrace, Hill or Mountain',()=>{
 for(const subrace of ['', 'Hill', 'Mountain']){
  const record=creature('Dwarf','PHB',subrace?{subrace,subrace_source:'PHB',
   subrace_id:find('Dwarf ('+subrace+')','PHB').id}:{});
  const sheet=calculate(record);
  assert.deepEqual(keys(sheet),['1:poison'],'Dwarf '+(subrace||'base'));
  assert.equal(effects(sheet)[0].granting_trait,'Dwarven Resilience');
  assert.equal(effects(sheet)[0].origin_parent_id,'race|phb|dwarf',
   'the inherited PHB racial benefit must remain owned by the species');
  assert.equal(effects(sheet).length,1,'a flattened subrace must not duplicate parent defenses');
 }
});

test('Stout Halfling gains a subrace-only resistance and its actual visible trait',()=>{
 const character=creature('Halfling','PHB',{subrace:'Stout',subrace_source:'PHB',
  subrace_id:find('Halfling (Stout)','PHB').id});
 const sheet=calculate(character);
 assert.deepEqual(keys(sheet),['1:poison']);
 const grant=effects(sheet)[0];
 assert.equal(grant.granting_trait,'Stout Resilience');
 assert.equal(grant.origin_parent_id,'subrace|phb|stout');
 const trait=sheet.features.find(feature=>feature.origin_id===grant.origin_id);
 assert.ok(trait);
 assert.equal(trait.origin_key,'subrace|phb|stout');
 assert.match(JSON.stringify(trait.entries),/resistance against poison damage/i);
 assert.deepEqual(traitBenefitGroups({feature_origin:trait.origin_id,origin_key:trait.origin_key,
  name:trait.name,category:'razza',rank:2},character,sheet)
  .find(group=>group.type==='defenses')?.items.map(row=>row.value),['Veleno']);
 const base=traitBenefitGroups({origin_key:'species|'+character.species_id+'|phb',
  name:'Descrizione · Halfling',category:'razza',rank:0},character,sheet);
 assert.ok(!base.some(group=>group.type==='defenses'));
 assert.deepEqual(keys(calculate({...character,origin_enabled:{'subrace|phb|stout':false}})),[]);
 assert.deepEqual(keys(calculate({...character,origin_enabled:{[grant.origin_id]:false}})),[]);
 assert.deepEqual(keys(calculate({...character,subrace:'Lightfoot',subrace_id:''})),[]);
});

test('Genasi elemental subraces grant only their own source-qualified damage resistance',()=>{
 for(const [subrace,book,type] of [
  ['Fire','EEPC','fire'],['Water','EEPC','acid'],
  ['Air','MPMM','lightning'],['Fire','MPMM','fire'],['Water','MPMM','acid']
 ]){
  const character=creature('Genasi','EEPC',{subrace,subrace_source:book,
   subrace_id:find('Genasi ('+subrace+')',book).id});
  const sheet=calculate(character);
  assert.deepEqual(keys(sheet),['1:'+type],book+' Genasi ('+subrace+')');
  assert.equal(effects(sheet)[0].origin_parent_id,'subrace|'+book.toLowerCase()+'|'+subrace.toLowerCase());
 }
});

test('older Aasimar, Tiefling and Elf subraces inherit only the correct parent or variant trait',()=>{
 const checks=[
  ['Aasimar','VGM','Fallen','VGM',['1:necrotic','1:radiant'],'race|vgm|aasimar'],
  ['Tiefling','PHB','Asmodeus','MTF',['1:fire'],'race|phb|tiefling'],
  ['Elf','PHB','Shadar-kai','MTF',['1:necrotic'],'subrace|mtf|shadar-kai'],
  ['Dwarf','PHB','Duergar','MTF',['1:poison'],'race|phb|dwarf']
 ];
 for(const [species,source,subrace,subsource,expected,parent] of checks){
  const creatureRecord=creature(species,source,{subrace,subrace_source:subsource,
    subrace_id:find(species+' ('+subrace+')',subsource).id});
  const sheet=calculate(creatureRecord);
  assert.deepEqual(keys(sheet),expected,species+' ('+subrace+')');
  assert.ok(effects(sheet).every(row=>row.origin_parent_id===parent));
 }
});

test('all typed pre-2024 resistances and immunity are present in generated defenses',()=>{
 for(const race of source.races.filter(row=>row.source!=='XPHB')){
  const typed=['resist','immune','conditionImmune','vulnerable'].flatMap(field=>
   Array.isArray(race[field])?race[field]:[]);
  if(!typed.length)continue;
  const matching=catalog.races.find(row=>row.id===race.id);
  assert.ok(matching,race.name+' ('+race.source+') missing');
  assert.equal(matching.entries.length+matching.choices.length,typed.length,
   race.name+' ('+race.source+') missing or duplicated defenses');
 }
});

test('subrace-only resistances disappear when switching or disabling the subrace',()=>{
 const original=creature('Halfling','PHB',{subrace:'Stout',subrace_source:'PHB'});
 assert.equal(selectedSpeciesDefenseRules(original,catalog).length,1);
 const gone={...original,subrace:'Lightfoot'};
 assert.deepEqual(selectedSpeciesDefenseRules(gone,catalog),[]);
 assert.deepEqual(keys(calculate(gone)),[]);
});

test('rendered racial trait cards show PHB Dwarf and Stout subrace defenses',async()=>{
 for(const [species,subrace,expectedOrigin,expectedTrait] of [
  ['Dwarf','Hill','species|','Dwarven Resilience'],
  ['Halfling','Stout','subrace|phb|stout','Stout Resilience']
 ]){
  const character=creature(species,'PHB',{subrace,subrace_source:'PHB'});
  const calculated=calculate(character);
  const base=find(species,'PHB');
  const list=await collectTraitRows(character,calculated,{
   entries:async category=>category==='races'?[base]:[],
   detail:async(_category,row)=>row
  });
  const shown=list.find(t=>t.name===expectedTrait&&
   t.origin_key.startsWith(expectedOrigin));
  assert.ok(shown,species+' ('+subrace+') must render '+expectedTrait);
  const group=traitBenefitGroups(shown,character,calculated)
   .find(g=>g.type==='defenses');
  assert.deepEqual(group?.items.map(i=>i.value),['Veleno']);
 }
});
