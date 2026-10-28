import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {pendingCharacterChoices} from '../pending_choices.js';
import {projectSpeciesSpellBindings} from '../tools/species_spell_bindings.mjs';
import {structuredSpellGrants,supplementalSpeciesSpellFeatures,originSpellId} from '../spell_selection.js';

const json=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const ability=json('../catalog/ability_grants.json');
const source=json('../../vtt/data/creature_references_5etools.json');
const sourceSpells=json('../../vtt/data/additional_spells_5etools.json');
const rules=json('../catalog/spell_grant_rules.json').rules;
const originDetails=json('../../vtt/data/compendium_features_5etools.json');
const scores={str:10,dex:10,con:10,int:10,wis:10,cha:10};
const character=(species,source,subrace='',subrace_source='',extra={})=>({
 kind:'character',rules_version:'2014',level:5,abilities:scores,
 species,species_source:source,subrace,subrace_source,...extra
});
const catalog={
 abilityGrants:ability,
 classMechanics:{additional_spells:sourceSpells.entries},
 originDetails:{races:originDetails.races},
 spellGrantRules:rules
};
const sheet=c=>calculateSheet(c,catalog);
const result=c=>Object.fromEntries(['str','dex','con','int','wis','cha'].map(x=>[x,sheet(c).abilities[x].score]));
const spellResult=c=>{
 const features=supplementalSpeciesSpellFeatures(c,rules,[]);
 return structuredSpellGrants(c,sourceSpells.entries,[],features,rules);
};

test('the checked-in spell rules mirror typed native 2014 source- and trait-ownership',()=>{
 const projected=projectSpeciesSpellBindings(source.races,sourceSpells.entries);
 const known=rules.filter(rule=>rule.kind==='subrace'||rule.generated_2014_species_spell);
 assert.deepEqual(known,projected.rules);
 assert.ok(projected.rules.length>=100);
 assert.ok(known.some(row=>row.name==='High'&&row.spell==='*choice*'));
});

test('PHB Human, Half-Elf and Warforged retain their distinctive 2014 score rules',()=>{
 assert.deepEqual(result(character('Human','PHB')),
  {str:11,dex:11,con:11,int:11,wis:11,cha:11});
 assert.deepEqual(result(character('Half-Elf','PHB')),
  {str:10,dex:10,con:10,int:10,wis:10,cha:12});
 const pending=pendingCharacterChoices(character('Half-Elf','PHB'),sheet(character('Half-Elf','PHB')),catalog);
 assert.ok(pending.some(choice=>choice.kind==='ability'&&choice.count===2));
 const selected=character('Half-Elf','PHB','','',{
  origin_ability_choices:[{origin_id:'race|phb|half-elf',variant:0,
   allocations:[{part:0,ability:'str'},{part:0,ability:'dex'}]}]
 });
 assert.deepEqual(result(selected),{str:11,dex:11,con:10,int:10,wis:10,cha:12});
 const warforged=character('Warforged','ERLW','','',{
  origin_ability_choices:[{origin_id:'race|erlw|warforged',variant:0,
   allocations:[{part:0,ability:'int'}]}]
 });
 assert.equal(result(warforged).con,12);
 assert.equal(result(warforged).int,11);
});

test('PHB dwarf ASIs add normally, full 2014 variant ASIs replace their parents',()=>{
 assert.equal(result(character('Dwarf','PHB','Hill','PHB')).con,12);
 assert.equal(result(character('Dwarf','PHB','Hill','PHB')).wis,11);
 const dispater=result(character('Tiefling','PHB','Dispater','MTF'));
 assert.equal(dispater.cha,12);
 assert.equal(dispater.dex,11);
 assert.equal(dispater.int,10);
 const chromatic=character('Dragonborn','PHB','Chromatic','FTD');
 assert.equal(result(chromatic).str,10);
 const pending=pendingCharacterChoices(chromatic,sheet(chromatic),catalog);
 assert.ok(pending.some(row=>row.kind==='ability_mode'&&row.origin_id==='subrace|ftd|chromatic'));
});

test('flexible 2014 source policies expose score selections rather than inventing them',()=>{
 for(const [species,book] of [['Aarakocra','MPMM'],['Aasimar','MPMM'],
  ['Astral Elf','AAG'],['Fairy','WBtW'],['Owlin','SCC']]){
  const c=character(species,book);
  const pending=pendingCharacterChoices(c,sheet(c),catalog);
  assert.ok(pending.some(choice=>choice.kind==='ability_mode'&&
   choice.origin_id==='race|'+book.toLowerCase()+'|'+species.toLowerCase()),species+' '+book);
  assert.ok(Object.values(result(c)).every(v=>v===10),species+' must not have unselected +scores');
 }
});

test('subrace cantrips and level-gated magic retain their source and granting trait',()=>{
 const drow=spellResult(character('Elf','PHB','Drow','PHB'));
 assert.deepEqual(drow.grants.map(g=>g.spell_id).sort(),
  ['phb2014_dancing_lights','phb2014_darkness','phb2014_faerie_fire']);
 assert.ok(drow.grants.every(g=>g.origin_name==='Drow Magic'&&g.origin_id.startsWith('feature:subrace|')));
 const high=spellResult(character('Elf','PHB','High','PHB'));
 assert.equal(high.grants.length,0);
 assert.equal(high.choices.length,1);
 assert.equal(high.choices[0].origin_name,'Cantrip');
 const flame=spellResult(character('Genasi','MPMM','Fire','MPMM'));
 assert.deepEqual(flame.grants.map(g=>g.spell_id).sort(),
  ['phb2014_burning_hands','phb2014_flame_blade','phb2014_produce_flame']);
 assert.ok(flame.grants.every(g=>g.origin_name==='Reach to the Blaze'));
 assert.equal(spellResult(character('Genasi','MPMM','Fire','MPMM',{level:1})).grants.length,1);
});

test('the original tiefling spells are replaced, not stacked, by its MTF lineage',()=>{
 const initial=spellResult(character('Tiefling','PHB'));
 assert.ok(initial.grants.some(g=>g.spell_id==='phb2014_hellish_rebuke'));
 const legacy=spellResult(character('Tiefling','PHB','Baalzebul','MTF'));
 assert.ok(!legacy.grants.some(g=>g.spell_id==='phb2014_hellish_rebuke'));
 assert.ok(legacy.grants.some(g=>g.spell_id==='phb2014_ray_of_sickness'));
 assert.equal(legacy.grants.filter(g=>g.cantrip).length,1);
 const winged=spellResult(character('Tiefling','PHB','Variant; Winged','SCAG'));
 assert.equal(winged.grants.length,0);
});

test('Astral Elf Astral Fire offers precisely one chosen cantrip',()=>{
 const c=character('Astral Elf','AAG');
 const x=spellResult(c);
 assert.deepEqual(x.grants,[]);
 assert.equal(x.choices.length,1);
 assert.deepEqual(x.choices[0].spell_options.sort(),
  ['phb2014_dancing_lights','phb2014_light','phb2014_sacred_flame']);
 assert.equal(x.choices[0].count,1);
 const computed=sheet(c);
 assert.ok(computed.origin_choices.some(choice=>choice.count===1&&choice.spell_options?.length===3));
});

test('cold sheets resolve fixed racial spells without prefetching the full spell catalogue',()=>{
 assert.equal(originSpellId('shape water|xge#c','2014',[]),'shape_water');
 assert.equal(originSpellId('mage hand#c','2014',[]),'phb2014_mage_hand');
 const genasi=spellResult(character('Genasi','EEPC','Water','EEPC'));
 assert.ok(genasi.grants.some(row=>row.spell_id==='shape_water'&&row.cantrip));
});

test('MPMM racial leveled spells retain the option to use spell slots',()=>{
 const c=character('Genasi','MPMM','Fire','MPMM');
 const sheet=spellResult(c);
 const leveled=sheet.grants.filter(g=>g.tracker_id);
 assert.equal(leveled.length,2);
 assert.ok(leveled.every(g=>g.slot_alternative));
 const triton=spellResult(character('Triton','MPMM'));
 assert.ok(triton.grants.filter(g=>g.tracker_id).every(g=>g.slot_alternative));
});

test('turning off a granting subrace trait suspends spells without deleting the choice',()=>{
 const c=character('Genasi','MPMM','Fire','MPMM');
 const initial=sheet(c);
 const feature=initial.features.find(row=>row.name==='Reach to the Blaze'&&
   row.origin_key==='subrace|mpmm|fire');
 assert.ok(feature);
 assert.ok(initial.origin_spells.some(row=>row.origin_id===feature.origin_id));
 const disabled=sheet({...c,trait_enabled:{[feature.key]:false}});
 assert.ok(!disabled.origin_spells.some(row=>row.origin_id===feature.origin_id));
 const restored=sheet(c);
 assert.ok(restored.origin_spells.some(row=>row.origin_id===feature.origin_id));
});

test('canonical species and subraces retain their own typed 2014 ASIs',()=>{
 assert.equal(result(character('Dwarf','PHB','Mountain','PHB')).con,12);
 assert.equal(result(character('Dwarf','PHB','Mountain','PHB')).str,12);
 assert.equal(result(character('Genasi','EEPC','Fire','EEPC')).con,12);
 assert.equal(result(character('Genasi','EEPC','Fire','EEPC')).int,11);
 assert.equal(result(character('Tiefling','PHB','Baalzebul','MTF')).cha,12);
 assert.equal(result(character('Tiefling','PHB','Baalzebul','MTF')).int,11);
});

test('canonical selected subraces retain feature-owned spells',()=>{
 for(const [race,source,subrace,book,names] of [
  ['Genasi','MPMM','Fire','MPMM',['phb2014_produce_flame','phb2014_burning_hands','phb2014_flame_blade']],
  ['Tiefling','PHB','Baalzebul','MTF',['phb2014_thaumaturgy','phb2014_ray_of_sickness','phb2014_crown_of_madness']],
  ['Elf','PHB','Drow','PHB',['phb2014_dancing_lights','phb2014_faerie_fire','phb2014_darkness']]
 ]){
  const projected=spellResult(character(race,source,subrace,book));
  assert.deepEqual(projected.grants.map(g=>g.spell_id).sort(),[...names].sort(),race+' '+subrace);
 }
});

test('there are no generated flattened-species ability records',()=>{
 assert.equal(ability.race.filter(row=>row.projected_flattened_species).length,0);
 assert.ok(!ability.race.some(row=>row.name==='Elf (High)'&&row.source==='PHB'));
});
