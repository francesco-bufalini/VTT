import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {racialPowerProjection,endTemporaryConditionPatch} from '../species_powers.js';
import {structuredSpellGrants,sessionSpellEntries} from '../spell_selection.js';
import {calculateSheet} from '../sheet_rules.js';
import {recoveryPatch} from '../native_sheet.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const powers=read('../catalog/species_powers.json');
const spellRules=read('../catalog/spell_grant_rules.json').rules;
const rawRaces=read('../../vtt/data/creature_references_5etools.json').races;
const base={kind:'character',rules_version:'2014',level:5,
 abilities:{str:10,dex:10,con:10,int:10,wis:10,cha:10},inventory:[]};
const firbolg={...base,species:'Firbolg',species_source:'MPMM',
 species_id:'5etools:races:mpmm:firbolg'};
const genasi={...base,species:'Genasi',species_source:'MPMM',
 species_id:'5etools:races:mpmm:genasi',subrace:'Earth',subrace_source:'MPMM'};
const feature=(record,name,subrace=false)=>{
 const origin_key=subrace?'subrace|mpmm|'+record.subrace.toLowerCase():
   'species|'+record.species_id+'|mpmm';
 return {name,origin_key,key:origin_key+'|1|'+name.toLowerCase(),
   origin_id:'feature:'+origin_key+'|1|'+name.toLowerCase()};
};

test('Firbolg Hidden Step uses a proficiency-sized tracker and one-turn invisibility',()=>{
 const projection=racialPowerProjection(firbolg,powers,[feature(firbolg,'Hidden Step')]);
 const ability=projection.abilities.find(row=>row.name==='Hidden Step');
 assert.equal(ability.action_type,'bonus');
 assert.equal(ability.effect_condition,'invisible');
 assert.equal(ability.duration_rounds,1);
 assert.equal(projection.trackers.find(row=>row.id===ability.tracker_id)?.max,3);
 const c={...firbolg,conditions:['invisible','poisoned'],
   active_class_features:{[ability.persistent_key]:{effect_condition:'invisible',added_condition:false}}};
 assert.deepEqual(endTemporaryConditionPatch(c).conditions,undefined);
 assert.deepEqual(Object.keys(endTemporaryConditionPatch(c).active_class_features),[]);
 const applied={...c,conditions:['invisible','poisoned'],
   active_class_features:{[ability.persistent_key]:{effect_condition:'invisible',added_condition:true}}};
 assert.deepEqual(endTemporaryConditionPatch(applied).conditions,['poisoned']);
 assert.deepEqual(recoveryPatch(applied,'turn',[],{}).conditions,['poisoned']);
});

test('Earth Genasi has a separate bonus-action Blade Ward counter',()=>{
 const projection=racialPowerProjection(genasi,powers,[feature(genasi,'Merge with Stone',true)]);
 const bonus=projection.origin_spells.find(row=>row.spell_id==='phb2014_blade_ward');
 assert.ok(bonus);
 assert.equal(bonus.payment_mode,'tracker');
 assert.equal(bonus.cast_action_type,'bonus');
 assert.equal(projection.trackers.find(row=>row.id===bonus.tracker_id)?.max,3);
 const definition={id:'phb2014_blade_ward',name:'Blade Ward',level:0};
 const grant={...bonus};
 const selections=sessionSpellEntries(genasi,{origin_spells:[grant],casting_classes:[]},[definition]);
 assert.equal(selections[0].casting_time,'Bonus Action');
 assert.equal(selections[0].grant_id,bonus.id);
});

test('native or supplemental Firbolg Magic has two independent daily uses',()=>{
 const stored=read('../../vtt/data/additional_spells_5etools.json').entries;
 const row=stored.find(row=>row.kind==='race'&&row.name==='Firbolg'&&row.source==='MPMM');
 const projected=structuredSpellGrants(firbolg,[row],[],[feature(firbolg,'Firbolg Magic')],spellRules,powers.races);
 assert.equal(projected.grants.length,2);
 assert.equal(projected.trackers.length,2);
 assert.ok(projected.trackers.every(row=>row.max===1&&row.recharge==='long_rest'));
 assert.ok(projected.grants.every(row=>row.tracker_id&&row.slot_alternative));
});

test('Earth Genasi Pass Without Trace consumes a daily counter and allows slots',()=>{
 const stored=read('../../vtt/data/additional_spells_5etools.json').entries;
 const row=stored.find(row=>row.kind==='subrace'&&row.name==='Earth'&&row.source==='MPMM');
 const projected=structuredSpellGrants(genasi,[row],[],[feature(genasi,'Merge with Stone',true)],spellRules,powers.races);
 const spell=projected.grants.find(row=>row.spell_id.endsWith('pass_without_trace'));
 assert.ok(spell?.tracker_id&&spell.slot_alternative);
 assert.equal(projected.trackers.find(row=>row.id===spell.tracker_id)?.max,1);
});

test('typed swim true inherits Genasi walking speed',()=>{
 const native=rawRaces.filter(row=>row.source==='MPMM'&&(row.name==='Genasi'||row.name==='Genasi (Water)'));
 const water={...genasi,subrace:'Water'};
 const result=calculateSheet(water,{classMechanics:{races:native,subraces:[]}});
 assert.equal(result.stats.speeds.walk,30);
 assert.equal(result.stats.speeds.swim,30);
});
