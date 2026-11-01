import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';

const read=name=>JSON.parse(readFileSync(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const ability=read('ability_grants'),states=read('trait_states').states,species=read('species_attacks');
const abilities={str:16,dex:14,con:12,int:16,wis:10,cha:10};

test('attack benefit training is explicit, optional, source-bound and not category-wide',()=>{
 const grant=proficient=>({feat_mechanics:[{name:'Training Test',source:'HOME',
   attacks:[{id:'test:bolt',name:'Custom Bolt',damage:'1d6',ability:'dex',melee:false,
     range_feet:30,weapon_category:'simple',grants_proficiency:proficient}]}]});
 const record={kind:'character',rules_version:'2014',level:5,abilities,
   feats_catalog:[{name:'Training Test',source:'HOME'}]};
 const plain=calculateSheet(record,{abilityGrants:grant(false)});
 const plainAttack=plain.attacks.find(a=>a.id==='test:bolt');
 assert.equal(plainAttack.proficient,false);
 assert.equal(plainAttack.hit,plain.abilities.dex.modifier);
 assert(!plain.proficiencies.includes('weapon:custom bolt'));
 const trained=calculateSheet(record,{abilityGrants:grant(true)});
 const attack=trained.attacks.find(row=>row.id==='test:bolt');
 assert.equal(attack.proficient,true);
 assert.equal(attack.hit,trained.abilities.dex.modifier+trained.values.proficiency);
 assert(trained.proficiencies.includes('weapon:custom bolt'));
 assert.deepEqual(trained.proficiency_sources['weapon:custom bolt'],
   [{id:'feat|home|training test',name:'Talento · Training Test'}]);
 assert(!trained.proficiencies.includes('weapon:simple'));
 const removed=calculateSheet({...record,feats_catalog:[]},{abilityGrants:grant(true)});
 assert(!removed.attacks.some(row=>row.id==='test:bolt'));
 assert(!removed.proficiencies.includes('weapon:custom bolt'));
});

test('all state-created weapons carry explicit proficiency with their source trait',()=>{
 const catalogs={classMechanics:read('class_mechanics'),classFeatures:read('classes'),
   traitStates:states,proficiencyGrants:read('proficiency_grants')};
 const record={kind:'character',rules_version:'2014',level:8,
   classes:[{name:'Artificer',source:'TCE',level:8,subclass:'Armorer',subclass_source:'TCE'}],
   abilities,inventory:[{id:'plate',type:'HA',ac:18,quantity:1,equipped_slots:['body']}],
   power_applications:{arcane_armor:[{id:'arcane_armor',target_item_id:'plate'}]}};
 for(const state of states.filter(row=>row.group==='armor_model')){
   const row=state.attacks[0];assert.equal(row.grants_proficiency,true);
   const active=calculateSheet({...record,trait_state_selection:{armor_model:state.id}},catalogs);
   const attack=active.attacks.find(item=>item.id===row.id);
   assert.equal(attack?.proficient,true,row.trait);
   const key='weapon:'+String(attack?.name||'').toLowerCase();
   assert(active.proficiencies.includes(key),attack?.name);
   assert(active.proficiency_sources[key]?.some(source=>source.id===attack.origin_id));
 }
 for(const state of states.filter(row=>row.group==='barbarian_beast_form'))
   assert(state.attacks.every(row=>row.grants_proficiency===true));
});

test('species natural strikes and Dragon Hide claws use explicit attack training',()=>{
 assert(species.races.flatMap(row=>row.attacks).every(attack=>attack.grants_proficiency===true));
 const race={kind:'character',level:5,rules_version:'2014',species:'Aarakocra',
   species_source:'EEPC',species_id:'5etools:races:eepc:aarakocra',abilities};
 const natural=calculateSheet(race,{speciesAttacks:species});
 const attack=natural.attacks.find(row=>row.id.startsWith('natural:'));
 assert.equal(attack?.proficient,true);
 assert(natural.proficiencies.includes('weapon:'+attack.name.toLowerCase()));
 assert(natural.proficiency_sources['weapon:'+attack.name.toLowerCase()]
   .some(source=>source.id===attack.origin_id));
 const record={kind:'character',level:5,rules_version:'2014',abilities,
   species:'Dragonborn',species_source:'PHB',feats_catalog:[{name:'Dragon Hide',source:'XGE'}]};
 const trained=calculateSheet(record,{abilityGrants:ability});
 const claws=trained.attacks.find(row=>row.id==='feat:xge:dragon-hide:claws');
 assert.equal(claws?.proficient,true);
 assert(trained.proficiency_sources['weapon:'+claws.name.toLowerCase()]
   .some(source=>source.id===claws.origin_id));
});


test('bestiary attacks automatically grant named attack training without double-counting the printed hit',()=>{
 const monster=JSON.parse(readFileSync(new URL('../../tests/fixtures/monster_traits.json',import.meta.url),'utf8'));
 monster.abilities={str:20,dex:12,con:16,int:10,wis:10,cha:10};
 monster.stat_block.cr='17';
 const calculated=calculateSheet(monster,{});
 const bite=calculated.attacks.find(row=>row.id==='monster:action:1');
 assert.equal(bite?.proficient,true);
 assert.equal(bite?.grants_proficiency,true);
 assert.equal(bite?.hit,10,'The printed +10 already includes proficiency');
 assert.match(bite?.explanation||'',/competenza già inclusa/);
 const key='attack:bite',owner=calculated.proficiency_sources[key];
 assert(calculated.proficiencies.includes(key));
 assert.equal(owner?.length,1);
 assert.equal(owner[0].id,bite.origin_id);
 assert.match(owner[0].name,/Mostro/);
 assert(!calculated.proficiencies.includes('weapon:bite'),
   'Monster attacks do not automatically grant weapon-category training');
 assert(!calculated.proficiencies.includes('attack:frightful presence'),
   'Saving throw actions must not become attacks or proficiency grants');
});

test('saved structured monster attacks acquire proficiency automatically, including spells, without changing hit totals',()=>{
 const base={kind:'monster',rules_version:'2014',abilities:{str:14,dex:12,con:12,int:18,wis:12,cha:12},
   stat_block:{name:'Test Mage',source:'TEST',cr:'9',action:[
     {name:'Arcane Bolt',vtt_attack:{attack_kind:'attack',base_hit:8,
       source_ability:'int',damage:'2d8',melee:false,range_feet:60}},
     {name:'Claw',vtt_attack:{attack_kind:'attack',base_hit:6,
       source_ability:'str',damage:'1d6',melee:true,range_feet:5}},
     {name:'Against Training',vtt_attack:{attack_kind:'attack',base_hit:5,
       source_ability:'dex',damage:'1d4',melee:false,grants_proficiency:false}},
     {name:'Saving Throw',vtt_attack:{attack_kind:'saving_throw',save_dc:15,damage:'4d6'}}
   ]}};
 const data=calculateSheet(base,{});
 for(const [index,hit,name] of [[0,8,'Arcane Bolt'],[1,6,'Claw']]){
   const row=data.attacks.find(attack=>attack.id==='monster:action:'+index);
   assert.equal(row?.hit,hit,name);
   assert.equal(row?.proficient,true,name);
   assert.equal(row?.grants_proficiency,true,name);
   assert(data.proficiencies.includes('attack:'+name.toLowerCase()));
   assert(data.proficiency_sources['attack:'+name.toLowerCase()].some(source=>source.id===row.origin_id));
 }
 const untrained=data.attacks.find(row=>row.id==='monster:action:2');
 assert.equal(untrained?.hit,5,'An explicit opt-out does not rewrite a published modifier');
 assert.equal(untrained?.proficient,false);
 assert(!data.proficiencies.includes('attack:against training'));
 assert(!data.attacks.some(row=>row.id==='monster:action:3'));
 assert(!data.proficiencies.includes('attack:saving throw'));
});
