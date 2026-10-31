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
   assert.equal(attack?.proficient,true,row.name);
   const key='weapon:'+row.name.toLowerCase();
   assert(active.proficiencies.includes(key),row.name);
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
