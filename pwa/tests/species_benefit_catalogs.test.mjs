import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {speciesRollModesFromBenefits,speciesRollBonusesFromBenefits} from '../species_benefit_catalogs.js';
import {projectSpeciesRollModes} from '../tools/species_roll_modes.mjs';
const read=relative=>JSON.parse(readFileSync(new URL(relative,import.meta.url),'utf8'));
const rollMode=read('../../vtt/enrichment/benefits/roll_mode.json');
const rollBonus=read('../../vtt/enrichment/benefits/roll_bonus.json');
const source=read('../../vtt/data/creature_references_5etools.json');
test('164 racial roll modes reproduce the full previous source-qualified rules',()=>{
 const actual=speciesRollModesFromBenefits(rollMode,{races:source.races});
 assert.deepEqual(actual,projectSpeciesRollModes(source.races));
 assert.equal(rollMode.entries.length,164);
});
test('23 racial roll bonuses retain owner and mechanical identity, without duplicated prose',()=>{
 const output=speciesRollBonusesFromBenefits(rollBonus);
 assert.equal(rollBonus.entries.length,23);
 assert.equal(output.races.flatMap(r=>r.bonuses).length,23);
 assert.equal(new Set(rollBonus.entries.map(e=>e.id)).size,23);
 assert(rollBonus.entries.every(e=>e.granted_by.kind==='5etools'&&
   e.granted_by.ref.category==='species_trait'&&
   e.benefit.type==='roll_bonus'&&!e.benefit.bonus.description));
 assert(output.races.some(r=>r.name==='Half-Elf'&&r.subrace_source==='ERLW'));
});
test('wrong per-type catalog and benefit identity are rejected',()=>{
 assert.throws(()=>speciesRollModesFromBenefits({...rollMode,schema_version:1}),/Catalogo tipizzato/);
 assert.throws(()=>speciesRollBonusesFromBenefits({...rollBonus,benefit_type:'roll_mode'}),/Catalogo tipizzato/);
 assert.throws(()=>speciesRollModesFromBenefits({...rollMode,entries:[{...rollMode.entries[0],benefit:{type:'bonus',roll_modes:[]}}]}),/Tipo di beneficio/);
});
