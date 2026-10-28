import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {dragonbornFtdProfile,dragonbornFtdChoice,dragonbornFtdSaveChoice,
  dragonbornFtdProjection,dragonbornFtdResistances} from '../dragonborn_ftd.js';
import {selectedSpeciesDefenseRules} from '../species_defenses.js';
import {pendingCharacterChoices,savePendingChoice} from '../pending_choices.js';
import {calculateSheet} from '../sheet_rules.js';
import {abilitiesForCreature} from '../activated_abilities.js';
import {battleAbilityEntries} from '../action_economy.js';
import {persistentBattleAbility} from '../sheet_rules_view.js';
import {abilityAreaPolygon,pointInAbilityArea,abilityAreaPreview} from '../ability_areas.js';

const powers=JSON.parse(readFileSync(new URL('../catalog/species_powers.json',import.meta.url),'utf8'));
const defenses=JSON.parse(readFileSync(new URL('../catalog/species_defenses.json',import.meta.url),'utf8'));
const base={kind:'character',rules_version:'2014',level:5,
 abilities:{str:12,dex:12,con:16,int:10,wis:10,cha:10},
 resource_tracker_spent:{},active_class_features:{}};
const build=(variant,level=5,flattened=false,extra={})=>({
 ...base,level,
 ...(flattened?{species:'Dragonborn ('+variant+')',species_source:'FTD',
   species_id:'5etools:races:ftd:dragonborn%20%28'+variant.toLowerCase()+'%29'}:
  {species:'Dragonborn',species_source:'PHB',
   species_id:'5etools:races:phb:dragonborn',subrace:variant,subrace_source:'FTD'}),
 ...extra});
const chosen=(record,name)=>{
 const choice=dragonbornFtdChoice(record,powers);
 assert(choice,'choice available');
 return {...record,...dragonbornFtdSaveChoice(record,choice,[name])};
};
const own=(record)=>{
 const projected=dragonbornFtdProjection(record,powers);
 return {...projected,defenses:dragonbornFtdResistances(record,powers,projected.features)};
};
test('one source-qualified ancestry replaces both independent PHB and FTD resistance choices',()=>{
 for(const variant of ['Chromatic','Metallic','Gem']){
  const record=build(variant);
  assert.deepEqual(selectedSpeciesDefenseRules(record,defenses),[]);
  const pending=pendingCharacterChoices(record,{}, {speciesPowers:powers,speciesDefenses:defenses})
    .filter(x=>['defense','draconic_ancestry'].includes(x.kind));
  assert.equal(pending.length,1);
  assert.equal(pending[0].kind,'draconic_ancestry');
  assert.equal(pending[0].remaining,1);
  const name=variant==='Gem'?'amethyst':variant==='Metallic'?'bronze':'red';
  const saved={...record,...savePendingChoice(record,pending[0],[name])};
  const calculated=own(saved);
  assert.equal(calculated.defenses.length,1);
  const type=variant==='Gem'?'force':variant==='Metallic'?'lightning':'fire';
  assert.equal(calculated.defenses[0].key,type);
  assert.equal(calculated.defenses[0].origin_parent_id,pending[0].origin_id);
  assert.equal(own(record).defenses.length,0,'unselected ancestry must not guess a resistance');
  assert.equal(dragonbornFtdProfile({...saved,subrace:variant==='Gem'?'Chromatic':'Gem'},powers)?.ancestry,null);
 }
});
test('FTD flattened race has same mechanics without a PHB parent',()=>{
 const record={...build('Gem',5,true),subrace:'Crystal',subrace_source:'FTD'};
 assert.equal(dragonbornFtdProfile(record,powers).ancestry.damage_type,'radiant');
 assert.deepEqual(selectedSpeciesDefenseRules(record,defenses),[]);
 assert.equal(own(record).defenses[0].key,'radiant');
 assert.equal(own(record).abilities[0].area_shape,'cone');
});
test('wrong ancestry and stale source selections are rejected',()=>{
 const c=build('Chromatic'),choice=dragonbornFtdChoice(c,powers);
 assert.throws(()=>dragonbornFtdSaveChoice(c,choice,['amethyst']),/non valida/);
 assert.throws(()=>dragonbornFtdSaveChoice({...c,subrace:'Gem'},choice,['red']),/non valida/);
 assert.equal(dragonbornFtdChoice({...c,rules_version:'2024'},powers),null);
});
test('breath is PB/long rest, CON-based Dexterity save, geometry and 1-4d10 scaling',()=>{
 for(const [level,dice,max] of [[1,'1d10',2],[5,'2d10',3],[11,'3d10',4],[17,'4d10',6]]){
  const c=chosen(build('Chromatic',level),'blue'),p=own(c),breath=p.abilities[0];
  assert.equal(breath.mode,'save_area');
  assert.equal(breath.attack_replacement,true);
  assert.equal(breath.damage_formula,dice);
  assert.equal(breath.damage_type,'lightning');
  assert.equal(breath.area_shape,'line');
  assert.equal(breath.area_length_feet,30);
  assert.equal(breath.area_width_feet,5);
  assert.equal(breath.save_ability,'dex');
  assert.equal(breath.save_base,'constitution');
  assert.equal(p.trackers[0].max,max);
  assert.equal(p.trackers[0].recharge,'long_rest');
 }
});
test('metallic cone shares one additional 5th-level use with two save modes',()=>{
 const below=own(chosen(build('Metallic',4),'gold'));
 assert.equal(below.abilities.length,1);
 const p=own(chosen(build('Metallic',5),'gold'));
 assert.equal(p.abilities.length,2);
 assert.equal(p.abilities[0].area_shape,'cone');
 const extra=p.abilities[1];
 assert.equal(extra.mode,'choice_area');
 assert.equal(extra.attack_replacement,true);
 assert.equal(extra.area_radius_feet,15);
 assert.deepEqual(extra.options.map(x=>x.save_ability),['con','str']);
 assert.deepEqual(extra.options.map(x=>x.effect),['incapacitated','push_prone']);
 assert.equal(p.trackers[1].max,1);
 assert.notEqual(p.trackers[0].id,p.trackers[1].id);
});
test('warding grants temporary matching immunity, and reverts when removed or source is disabled',()=>{
 const record=chosen(build('Chromatic'),'red'),p=own(record),special=p.abilities[1];
 assert.equal(special.mode,'temporary_defense');
 assert.equal(p.defenses[0].rank,1);
 const active={...record,active_class_features:{
  [special.persistent_key]:{origin_id:special.persistent_origin_id,name:special.name}}};
 assert.deepEqual(own(active).defenses.map(x=>x.rank),[1,2]);
 assert.deepEqual(own(active).defenses.map(x=>x.key),['fire','fire']);
 assert.deepEqual(own(record).defenses.map(x=>x.rank),[1]);
 assert.equal(own({...active,origin_enabled:{[special.origin_id]:false}}).defenses.some(x=>x.rank===2),false);
});
test('Gem Flight begins at level 5, persists for 10 rounds, and matches walk speed only while active',()=>{
 const c=chosen(build('Gem',5),'topaz'),p=own(c),flight=p.abilities[1];
 assert.equal(flight.mode,'temporary_flight');
 assert.equal(flight.action_type,'bonus');
 assert.equal(flight.duration_rounds,10);
 const catalogs={speciesPowers:powers,classMechanics:{races:[{
  name:'Dragonborn',source:'PHB',speed:30}],additional_spells:[]}};
 const idle=calculateSheet(c,catalogs);
 assert.equal(idle.stats.speeds.fly,0);
 const active={...c,active_class_features:{
   [flight.persistent_key]:{name:flight.name,origin_id:flight.persistent_origin_id,duration_rounds:10}}};
 const flying=calculateSheet(active,catalogs);
 assert.equal(flying.stats.speeds.fly,flying.stats.speeds.walk);
 assert.equal(flying.stats.hovering,true);
 assert.equal(calculateSheet({...active,active_class_features:{}},catalogs).stats.speeds.fly,0);
 assert.equal(own(chosen(build('Gem',4),'topaz')).abilities.length,1);
});
test('activated abilities retain typed modes through battle projection',()=>{
 const c=chosen(build('Gem'),'amethyst'),p=own(c);
 const projection={features:p.features,trackers:p.trackers,facilities:[],
   racial_abilities:p.abilities,feature_rules:{}};
 const abilities=abilitiesForCreature(c,[],projection);
 const battle=battleAbilityEntries(c,projection,[],abilities);
 assert.equal(battle.length,2);
 const flight=battle.find(x=>x.mode==='temporary_flight');
 assert(flight);
 assert(persistentBattleAbility({power:abilities.find(a=>a.mode==='temporary_flight')}));
 assert.equal(flight.persistent_key,'racial:dragonborn_ftd:flight');
});
test('cone and line tactical previews exclude self and include only intersected token markers',()=>{
 const snapshot={width:1000,field_feet:100,
   markers:[{id:'me',x:100,y:100,radius:5},{id:'near',x:200,y:100,radius:5},
    {id:'far',x:500,y:100,radius:5},{id:'aside',x:200,y:250,radius:5}]};
 const line=abilityAreaPreview(snapshot,'me',[300,100],{shape:'line',length_feet:30,width_feet:5});
 assert.deepEqual(line.affected_ids,['near']);
 const cone=abilityAreaPreview(snapshot,'me',[300,100],{shape:'cone',radius_feet:15});
 assert.deepEqual(cone.affected_ids,['near']);
 assert(pointInAbilityArea([200,100],cone.points));
 assert(!pointInAbilityArea([200,300],cone.points));
 assert.equal(abilityAreaPolygon([0,0],[0,0],{shape:'line',length_feet:30,width_feet:5},10).length,0);
});


test('FTD Dragonborn use color subraces instead of a second ancestry picker',()=>{
 for(const [variant,color,type] of [['Chromatic','Red','fire'],['Gem','Amethyst','force'],['Metallic','Silver','cold']]){
  const record={...build(variant,5,true),subrace:color,subrace_source:'FTD'};
  assert.equal(dragonbornFtdChoice(record,powers),null);
  const profile=dragonbornFtdProfile(record,powers);
  assert.equal(profile.ancestry.damage_type,type);
  assert.equal(own(record).abilities[0].damage_type,type);
 }
});
