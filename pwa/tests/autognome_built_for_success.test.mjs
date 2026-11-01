import {speciesPowerTestIndex} from './species_power_test_fixture.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {racialPowerProjection} from '../species_powers.js';
import {applicableDiceBonuses} from '../sheet_rules.js';
import {rollOptionalDice} from '../sheet_roll_origin.js';
import {rollSheetDice,appendRollBonus,sheetRollChatFields} from '../sheet_rules_view.js';
import {spendTrackerUses} from '../character_core.js';
import {recoveryPatch} from '../native_sheet.js';

const index=speciesPowerTestIndex();
const source=JSON.parse(readFileSync(new URL('../../vtt/data/compendium_features_5etools.json',import.meta.url),'utf8'));
const original={races:source.races};
const root='species|5etools:races:aag:autognome|aag';
const trait={name:'Built for Success',origin_key:root,
 origin_id:'feature:'+root+'|1|built for success',key:root+'|1|built for success'};
const hero=(level=5,extra={})=>({kind:'character',rules_version:'2014',
 species:'Autognome',species_source:'AAG',level,inventory:[],resource_tracker_spent:{},...extra});

test('AAG Autognome grants exactly the trait-owned 1d4 and proficiency uses',()=>{
 for(const [level,capacity] of [[1,2],[5,3],[9,4],[13,5],[17,6]]){
  const grants=racialPowerProjection(hero(level),index,[trait]);
  assert.equal(grants.trackers.length,1);
  assert.equal(grants.trackers[0].max,capacity);
  assert.equal(grants.trackers[0].recharge,'long_rest');
  assert.equal(grants.trackers[0].origin_id,trait.origin_id);
  assert.equal(grants.roll_bonuses.length,1);
  const bonus=grants.roll_bonuses[0];
  assert.equal(bonus.dice,'1d4');
  assert.equal(bonus.tracker_id,grants.trackers[0].id);
  assert.equal(bonus.tracker_cost,1);
  assert.equal(bonus.strict_tracker,true);
  assert.deepEqual(bonus.targets,['attack_roll','ability_check','saving_throw']);
  assert.equal(bonus.granting_trait,'Built for Success');
 }
});

test('Built for Success appears on attacks, saves and checks, but not damage',()=>{
 const grants=racialPowerProjection(hero(),index,[trait]);
 const calculated={racial_roll_bonuses:grants.roll_bonuses,trackers:grants.trackers};
 for(const target of ['attack_hit:item:sword','casting_hit:int','save:con',
   'skill:perception','ability_check:str','initiative']){
  const dice=applicableDiceBonuses(hero(),target,[],calculated);
  assert.equal(dice.length,1,target);
  assert.equal(dice[0].dice,'1d4',target);
  assert.equal(dice[0].target,target);
  assert.equal(rollOptionalDice(hero(),calculated,dice)[0].remaining,3);
 }
 assert.deepEqual(applicableDiceBonuses(hero(),'attack_damage:item:sword',[],calculated),[]);
});

test('origin toggles, removed trait and edition prevent racial bonus and tracker',()=>{
 assert.equal(racialPowerProjection(hero(),index,[]).trackers.length,0);
 assert.equal(racialPowerProjection(hero(),index,[{...trait,disabled:true}]).trackers.length,0);
 assert.equal(racialPowerProjection(hero(),index,[trait]).trackers.length,1);
 assert.equal(racialPowerProjection(hero(5,{origin_enabled:{[trait.origin_id]:false}}),index,[trait]).trackers.length,0);
 assert.equal(racialPowerProjection(hero(5,{trait_enabled:{[trait.key]:false}}),index,[trait]).trackers.length,0);
 assert.equal(racialPowerProjection(hero(5,{rules_version:'2024'}),index,[trait]).trackers.length,0);
});

test('payment is atomic and the 2014 bonus recovers on a long rest',()=>{
 const record=hero(1);
 const tracker=racialPowerProjection(record,index,[trait]).trackers[0];
 const first=spendTrackerUses(record,tracker.id,1,[tracker]);
 assert.equal(first.resource_tracker_spent[tracker.id],1);
 const second=spendTrackerUses({...record,...first},tracker.id,1,[tracker]);
 assert.equal(second.resource_tracker_spent[tracker.id],2);
 assert.throws(()=>spendTrackerUses({...record,...second},tracker.id,1,[tracker]),/insufficiente/i);
 assert.equal(recoveryPatch({...record,...second},'short_rest',[tracker]).resource_tracker_spent[tracker.id],2);
 assert.equal(recoveryPatch({...record,...second},'long_rest',[tracker]).resource_tracker_spent[tracker.id],undefined);
});

test('adding optional dice after seeing d20 keeps the original d20 result',()=>{
 const calls=[];
 const die=sides=>{calls.push(sides);return sides===20?17:4;};
 const original=rollSheetDice(3,[],die);
 assert.equal(original.total,20);
 assert.deepEqual(original.rolls,[17]);
 calls.length=0;
 const modified=appendRollBonus(original,{origin_name:'Built for Success',dice:'1d4'},die);
 assert.deepEqual(calls,[4],'only the new d4 may be rolled');
 assert.deepEqual(modified.rolls,[17]);
 assert.deepEqual(original.parts[0].rolls,[17]);
 assert.equal(modified.total,24);
 assert.equal(original.total,20,'original result must not be mutated');
 assert.equal(modified.parts.at(-1).subtotal,4);
 assert.match(modified.detail,/Built for Success/);
 const chat=sheetRollChatFields(modified);
 assert.equal(chat.total,24);
 assert.equal(chat.die,'formula');
 assert.equal(chat.terms.length,2);
 assert.deepEqual(chat.terms[0].rolls,[17]);
 assert.deepEqual(chat.terms[1].rolls,[4]);
});

test('post-result bonus also preserves advantage dice and handles fixed bonuses',()=>{
 const original=rollSheetDice(2,[],s=>s===20?8:1,'advantage');
 assert.deepEqual(original.rolls,[8,8]);
 const next=appendRollBonus(original,{dice:'1d4',origin_name:'Success'},()=>2);
 const fixed=appendRollBonus(next,{flat_bonus:1,origin_name:'Help'},()=>{throw Error('must not roll');});
 assert.deepEqual(fixed.rolls,[8,8]);
 assert.equal(fixed.total,13);
 assert.deepEqual(fixed.parts[0].rolls,[8,8]);
 assert.equal(fixed.parts.length,3);
});


test('MPMM Bugbear Surprise Attack is an optional untracked 2d6 on attack damage only',()=>{
 const origin='species|5etools:races:mpmm:bugbear|mpmm';
 const feature={name:'Surprise Attack',origin_key:origin,
   origin_id:'feature:'+origin+'|1|surprise attack',key:origin+'|1|surprise attack'};
 const character={...hero(),species:'Bugbear',species_source:'MPMM',
   species_id:'5etools:races:mpmm:bugbear'};
 const options=racialPowerProjection(character,index,[feature],original);
 assert.equal(options.trackers.length,0,'MPMM version has no charge tracker');
 assert.equal(options.roll_bonuses.length,1);
 const bonus=options.roll_bonuses[0];
 assert.equal(bonus.dice,'2d6');
 assert.equal(bonus.origin_id,feature.origin_id);
 assert.equal(bonus.granting_trait,'Surprise Attack');
 assert.deepEqual(bonus.targets,['attack_damage']);
 assert.equal(bonus.tracker_id,undefined);
 assert.match(bonus.description,/hasn't taken a turn yet in the current combat/i);
 assert.equal(bonus.condition_label,undefined,'trigger explanation comes from 5eTools, not a second translated label');
 const calc={racial_roll_bonuses:options.roll_bonuses,trackers:[]};
 for(const target of ['attack_damage:item:sword','attack_damage:unarmed',
   'attack_damage:item:bow']){
   const applied=applicableDiceBonuses(character,target,[],calc);
   assert.equal(applied.length,1,target);
   assert.equal(applied[0].target,target);
   const button=rollOptionalDice(character,calc,applied,{kind:'damage',attackId:target.slice(14)});
   assert.equal(button.length,1,target);
   assert.equal(button[0].tracker_cost,0);
 }
 for(const target of ['spell_damage','save:con','attack_hit:item:sword','spell_attack']){
   assert.deepEqual(applicableDiceBonuses(character,target,[],calc),[],target);
 }
 assert.equal(racialPowerProjection({...character,rules_version:'2024'},index,[feature]).roll_bonuses.length,0);
 assert.equal(racialPowerProjection(character,index,[{...feature,inactive:true}]).roll_bonuses.length,0);
 assert.equal(racialPowerProjection({...character,trait_enabled:{[feature.key]:false}},index,[feature]).roll_bonuses.length,0);
 assert.equal(racialPowerProjection({...character,origin_enabled:{[feature.origin_id]:false}},index,[feature]).roll_bonuses.length,0);
 assert.equal(racialPowerProjection({...character,species_source:'VGM'},index,[feature]).roll_bonuses.length,0);
});
