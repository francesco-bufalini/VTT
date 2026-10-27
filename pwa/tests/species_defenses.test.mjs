import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {projectSpeciesDefenses} from '../tools/species_defenses.mjs';
import {speciesDefenseEntries} from '../species_defenses.js';
import {calculateSheet} from '../sheet_rules.js';
import {traitBenefitGroups} from '../trait_benefits.js';

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
