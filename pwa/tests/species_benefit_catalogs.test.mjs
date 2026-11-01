import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {speciesRollModesFromBenefits,speciesRollBonusesFromBenefits,speciesAttacksFromBenefits,speciesPowersFromBenefits} from '../species_benefit_catalogs.js';
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
 const racialEntries=rollBonus.entries.filter(e=>e.granted_by.ref.category==='species_trait'&&e.benefit.operation!=='racial_roll_bonus');
 assert.equal(racialEntries.length,23);
 assert.equal(output.races.flatMap(r=>r.bonuses).length,23);
 assert.equal(new Set(rollBonus.entries.map(e=>e.id)).size,rollBonus.entries.length);
 assert(racialEntries.every(e=>e.granted_by.kind==='5etools'&&
   e.benefit.type==='roll_bonus'&&!e.benefit.bonus.description));
 assert(output.races.some(r=>r.name==='Half-Elf'&&r.subrace_source==='ERLW'));
});
test('wrong per-type catalog and benefit identity are rejected',()=>{
 assert.throws(()=>speciesRollModesFromBenefits({...rollMode,schema_version:1}),/Catalogo tipizzato/);
 assert.throws(()=>speciesRollBonusesFromBenefits({...rollBonus,benefit_type:'roll_mode'}),/Catalogo tipizzato/);
 assert.throws(()=>speciesRollModesFromBenefits({...rollMode,entries:[{...rollMode.entries[0],benefit:{type:'bonus',roll_modes:[]}}]}),/Tipo di beneficio/);
});

test('typed species attacks and movement reject wrong type and invalid mechanics',()=>{
 const attacks=read('../../vtt/enrichment/benefits/attack.json');
 const movement=read('../../vtt/enrichment/benefits/movement.json');
 assert.throws(()=>speciesAttacksFromBenefits({...attacks,benefit_type:'movement'},movement),/Catalogo tipizzato/);
 assert.throws(()=>speciesAttacksFromBenefits(attacks,{...movement,benefit_type:'attack'}),/Catalogo tipizzato/);
 const wrong={...attacks,entries:[{...attacks.entries[0],benefit:{type:'movement',attack:attacks.entries[0].benefit.attack}}]};
 assert.throws(()=>speciesAttacksFromBenefits(wrong,movement),/Tipo di beneficio/);
});

test('species powers are sourced by benefit type and retain original trait mechanics',()=>{
 const base=read('../catalog/species_powers.json');
 const actions=read('../../vtt/enrichment/benefits/action.json');
 const resources=read('../../vtt/enrichment/benefits/resource.json');
 const all=speciesPowersFromBenefits(base,actions,resources,rollBonus);
 const speciesActions=actions.entries.filter(e=>e.benefit.operation==='racial_power');
 const speciesResources=resources.entries.filter(e=>e.benefit.operation==='racial_power');
 const speciesDice=rollBonus.entries.filter(e=>e.benefit.operation==='racial_roll_bonus');
 assert.equal(speciesActions.length,20);
 assert.equal(speciesResources.length,12);
 assert.equal(speciesDice.length,2);
 for(const r of base.races){
  for(const kind of ['healing','active_conditions','actions','tracked_actions','roll_bonus','roll_bonuses']){
   assert(!Object.hasOwn(r,kind),'Duplicate species source of '+kind);
  }
  if(r.name==='Dragonborn'&&r.source==='PHB')assert(!Object.hasOwn(r,'breath_weapon'));
 }
 const aasimar=all.races.find(r=>r.name==='Aasimar'&&r.source==='MPMM');
 assert.equal(aasimar.healing.trait,'Healing Hands');
 assert.equal(aasimar.healing.roll.count,'proficiency');
 const auto=all.races.find(r=>r.name==='Autognome'&&r.source==='AAG');
 assert.equal(auto.roll_bonus.dice,'1d4');
 assert.equal(auto.roll_bonus.tracker_id,'race:aag:autognome:built_for_success:uses');
 assert.equal(auto.roll_bonus.uses,'proficiency');
 const orc=all.races.find(r=>r.name==='Orc'&&r.source==='MPMM');
 assert.equal(orc.tracked_actions.length,2);
 assert(orc.tracked_actions.some(a=>a.damage_response?.effect==='retain_one_hp'));
 assert.equal(all.races.find(r=>r.name==='Dragonborn (Gem)').breath_weapon.shape,'cone');
});
test('missing or mismatched tracker fails rather than silently granting uses',()=>{
 const base=read('../catalog/species_powers.json');
 const actions=read('../../vtt/enrichment/benefits/action.json');
 const resources=read('../../vtt/enrichment/benefits/resource.json');
 const missing={...resources,entries:resources.entries.filter(e=>e.id!=='race:aag:autognome:built_for_success:uses')};
 assert.throws(()=>speciesPowersFromBenefits(base,actions,missing,rollBonus),/Tracker/);
 const malformed={...actions,entries:[...actions.entries,{id:'test:invalid',granted_by:{
  kind:'5etools',ref:{category:'species_trait',race:'Orc',race_source:'MPMM',source:'MPMM',name:'Adrenaline Rush'}},
  benefit:{type:'action',operation:'racial_power',activation:'bonus',action_runtime:{kind:'not_a_kind'}}}]};
 assert.throws(()=>speciesPowersFromBenefits(base,malformed,resources,rollBonus),/Azione razziale invalida/);
});
