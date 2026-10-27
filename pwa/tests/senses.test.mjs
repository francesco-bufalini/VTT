import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSenses,senseLightRows} from '../sense_rules.js';
import {addBenefitPatch,removeBenefitPatch} from '../trait_benefit_editor.js';
import {traitBenefitGroups} from '../trait_benefits.js';
const catalog=JSON.parse(readFileSync(new URL('../catalog/sense_grants.json',import.meta.url),'utf8'));
test('2014 race and subrace ranges respect explicit source and light levels',()=>{
 const elf=calculateSenses({species:'Elf',species_source:'PHB'},[],catalog);
 assert.equal(elf.distances.darkvision,60);
 assert.match(elf.rows.find(row=>row.type==='darkvision').dark,/luce fioca/);
 assert.equal(elf.rows.find(row=>row.type==='darkvision').magical,'Nessuna');
 assert.equal(calculateSenses({species:'Elf',species_source:'PHB',subrace:'Drow',subrace_source:'PHB'},[],catalog).distances.darkvision,120);
 assert.equal(calculateSenses({species:'Elf',species_source:'XPHB'},[],catalog).distances.darkvision,undefined);
});
test('truesight, blind sight and tremorsense are independent of visible light',()=>{
 const rows=senseLightRows({darkvision:60,blindsight:10,truesight:30,tremorsense:40,devils_sight:120});
 assert.equal(rows[0].dark,'Nessuna');
 assert.match(rows.find(row=>row.type==='tremorsense').dark,/vibrazioni/);
 assert.match(rows.find(row=>row.type==='devils_sight').magical,/120 ft/);
 assert.equal(rows.find(row=>row.type==='darkvision').magical,'Nessuna');
});
test('each manual sense remains owned by the trait and can be disabled or removed',()=>{
 const trait={key:'example|feature',name:'Test',feature_origin:'feature:test',origin_key:'class|phb|wizard'};
 const patch=addBenefitPatch({},trait,'senses',{sense_type:'truesight',range_feet:'30'},'trait:abcd1234');
 const record={...patch};
 const sensed=calculateSenses(record,[],catalog);
 assert.equal(sensed.distances.truesight,30);
 assert.equal(traitBenefitGroups(trait,record,{senses:sensed})[0].items[0].label,'Vista pura');
 assert.equal(calculateSenses({...record,trait_enabled:{[trait.key]:false}},[],catalog).distances.truesight,undefined);
 const removed=removeBenefitPatch(record,trait,{type:'senses',id:'sense:trait:abcd1234'});
 assert.deepEqual(removed.sense_grants,[]);
 assert.throws(()=>addBenefitPatch({},trait,'senses',{sense_type:'blindsight',range_feet:'0'},'trait:abcd1234'),/Portata/);
});
test('a feature only grants its own sense while active',()=>{
 const f={name:'Eyes of the Dark',key:'sorcerer|eyes',origin_id:'feature:eyes',
  origin_key:'class|xge|sorcerer',requirements:{class_name:'Sorcerer',class_source:'XGE'}};
 assert.equal(calculateSenses({},[f],catalog).distances.darkvision,120);
 assert.equal(calculateSenses({trait_enabled:{[f.key]:false}},[f],catalog).distances.darkvision,undefined);
});
test('Gloom Stalker raises existing darkvision and grants a baseline without it',()=>{
 const f={name:'Umbral Sight',key:'ranger|umbral',origin_id:'feature:umbral',
  origin_key:'class|xge|ranger|subclass|gloom stalker|xge',
  requirements:{class_name:'Ranger',class_source:'XGE'}};
 assert.equal(calculateSenses({species:'Elf',species_source:'PHB'},[f],catalog).distances.darkvision,90);
 assert.equal(calculateSenses({},[f],catalog).distances.darkvision,60);
});
