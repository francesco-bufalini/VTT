import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {racialPowerProjection,racialPowerSubraces,racialPowerSpellDefinitions,healingHandsPatch} from '../species_powers.js';
import {calculateSheet} from '../sheet_rules.js';
const index=JSON.parse(readFileSync(new URL('../catalog/species_powers.json',import.meta.url),'utf8'));
const id='5etools:races:mpmm:aasimar';
const base={kind:'character',rules_version:'2014',level:3,species:'Aasimar',
 species_source:'MPMM',species_id:id,
 abilities:{str:10,dex:12,con:12,int:10,wis:12,cha:14},
 current_hp:5,max_hp_base:20,resource_tracker_spent:{}};
const healing={name:'Healing Hands',origin_key:'species|'+id+'|mpmm',
 origin_id:'feature:species|'+id+'|mpmm|1|healing hands'};
test('MPMM Celestial Revelation produces exactly three typed subrace options',()=>{
 const subraces=racialPowerSubraces(index);
 assert.deepEqual(subraces.map(x=>x.name),['Necrotic Shroud','Radiant Consumption','Radiant Soul']);
 assert(subraces.every(row=>row.raceName==='Aasimar'&&row.raceSource==='MPMM'&&row.level===3));
 assert.equal(racialPowerProjection({...base,level:2,subrace:'Radiant Soul',subrace_source:'MPMM'},index,[healing]).origin_spells.length,0);
 const soul=racialPowerProjection({...base,subrace:'Radiant Soul',subrace_source:'MPMM'},index,[healing]);
 assert.equal(soul.origin_spells.length,1);
 assert.equal(soul.origin_spells[0].payment_mode,'tracker');
 assert.equal(soul.active_forms[0].fly_equals_walk,true);
 assert.equal(soul.trackers.length,2);
 const shroud=racialPowerProjection({...base,subrace:'Necrotic Shroud',subrace_source:'MPMM'},index,[healing]);
 assert.equal(shroud.origin_spells[0].spellcasting_ability,'cha');
 assert.equal(shroud.origin_spells[0].casting_ability_not_required,false);
 assert(!racialPowerSpellDefinitions(index).find(x=>x.id==='vtt_aasimar_necrotic_shroud').condition_inflict.length);
 assert(racialPowerSpellDefinitions(index).every(x=>x.follow_caster&&x.target_mode==='self_emanation'));
 assert.equal(racialPowerProjection({...base,rules_version:'2024'},index,[healing]).trackers.length,0);
});
test('Healing Hands rolls exactly proficiency d4, heals self and consumes one long-rest use',()=>{
 const power=racialPowerProjection(base,index,[healing]);
 const ability=power.abilities[0];
 assert.equal(ability.mode,'heal_dice');
 assert.equal(power.trackers[0].recharge,'long_rest');
 const computed={trackers:[{...power.trackers[0],spent:0}],stats:{proficiency:3,max_hp:20}};
 const rolled=healingHandsPatch(base,computed,ability,()=>4,'self');
 assert.deepEqual(rolled.dice,[4,4,4]);
 assert.equal(rolled.total,12);
 assert.equal(rolled.patch.current_hp,17);
 assert.equal(rolled.patch.resource_tracker_spent[ability.tracker_id],1);
 const other=healingHandsPatch(base,computed,ability,()=>2,null);
 assert.equal(other.patch.current_hp,undefined);
 assert.throws(()=>healingHandsPatch({...base,resource_tracker_spent:{[ability.tracker_id]:1}},computed,ability,()=>1,'self'),/esauriti/);
});
test('Radiant Soul flight follows walking speed only during its active subrace manifestation',()=>{
 const powers=racialPowerProjection({...base,subrace:'Radiant Soul',subrace_source:'MPMM'},index,[healing]);
 const form=powers.active_forms[0];
 const catalog={speciesPowers:index,
   classMechanics:{races:[{id,name:'Aasimar',source:'MPMM',speed:30}],additional_spells:[]},
   originDetails:{races:{'aasimar|mpmm':{entries:[
     {name:'Healing Hands',entries:['Heal']},
     {name:'Celestial Revelation',entries:['Revelation']}
   ]}}}};
 const selected={...base,subrace:'Radiant Soul',subrace_source:'MPMM'};
 const dormant=calculateSheet(selected,catalog);
 assert.equal(dormant.stats.speeds.fly,0);
 const active=calculateSheet({...selected,active_class_features:{
   [form.active_key]:{spell_id:form.spell_id,name:form.name}}},catalog);
 assert.equal(active.stats.speeds.fly,active.stats.speeds.walk);
 assert.equal(active.active_racial_damage_bonus.amount,active.stats.proficiency);
 const changed=calculateSheet({...selected,subrace:'Necrotic Shroud',active_class_features:{
   [form.active_key]:{spell_id:form.spell_id,name:form.name}}},catalog);
 assert.equal(changed.stats.speeds.fly,0);
});
