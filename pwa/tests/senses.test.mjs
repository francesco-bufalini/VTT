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
  origin_key:'class|phb|sorcerer|subclass|shadow magic|xge',requirements:{class_name:'Sorcerer',class_source:'PHB'}};
 assert.equal(calculateSenses({},[f],catalog).distances.darkvision,120);
 assert.equal(calculateSenses({trait_enabled:{[f.key]:false}},[f],catalog).distances.darkvision,undefined);
});
test('Gloom Stalker raises existing darkvision and grants a baseline without it',()=>{
 const f={name:'Umbral Sight',key:'ranger|umbral',origin_id:'feature:umbral',
  origin_key:'class|phb|ranger|subclass|gloom stalker|xge',
  requirements:{class_name:'Ranger',class_source:'PHB'}};
 assert.equal(calculateSenses({species:'Elf',species_source:'PHB'},[f],catalog).distances.darkvision,90);
 assert.equal(calculateSenses({},[f],catalog).distances.darkvision,60);
});
test('item-granted senses require the exact active item, even with structured item IDs',()=>{
 const itemId='rod|tce|focus',trait={key:'item:'+itemId+'|0|sight',name:'Senso infuso'};
 const patch=addBenefitPatch({},trait,'senses',{sense_type:'blindsight',range_feet:'10'},'trait:abcd1235');
 const before={...patch};
 assert.equal(calculateSenses(before,[],catalog).distances.blindsight,undefined);
 const present={...before,inventory:[{id:itemId,name:'Rod',quantity:1}]};
 assert.equal(calculateSenses(present,[],catalog).distances.blindsight,10);
 const disabled={...present,trait_enabled:{[trait.key]:false}};
 assert.equal(calculateSenses(disabled,[],catalog).distances.blindsight,undefined);
});

test('every 2014 5etools race and subrace has its latest source-qualified senses audited',()=>{
 assert.equal(catalog.audit.races.length,134);
 assert.equal(catalog.audit.subraces.length,98);
 const vision=senses=>Object.fromEntries((senses||[]).map(v=>{
  const [type,feet]=v.split(':');return [type,Number(feet)];
 }));
 let verified=0;
 for(const race of catalog.audit.races){
  const character={species:race.name,species_source:race.source};
  const actual=calculateSenses(character,[],catalog).distances;
  const expected=vision(race.senses);
  for(const type of ['darkvision','blindsight']){
   // Custom Lineage requires the character's explicit choice.
   const optional=race.name==='Custom Lineage'&&race.source==='TCE'&&type==='darkvision';
   assert.equal(actual[type]||0,optional?0:expected[type]||0,
    'Race '+race.name+' · '+race.source+' · '+type);
  }
  verified++;
 }
 for(const sub of catalog.audit.subraces){
  const parent=catalog.audit.races.find(r=>r.name===sub.race_name&&r.source===sub.race_source);
  const expected=vision(parent?.senses),extra=vision(sub.senses);
  for(const [type,feet] of Object.entries(extra))expected[type]=Math.max(expected[type]||0,feet);
  const actual=calculateSenses({species:sub.race_name,species_source:sub.race_source,
   subrace:sub.name,subrace_source:sub.source},[],catalog).distances;
  for(const type of ['darkvision','blindsight'])
   assert.equal(actual[type]||0,expected[type]||0,
    'Subrace '+sub.race_name+' / '+sub.name+' · '+sub.source+' · '+type);
  verified++;
 }
 assert.equal(verified,232);
});
test('latest 2014 race variants, flattened subraces, and choice-only vision are correct',()=>{
 for(const [name,source,feet] of [
  ['Duergar','MPMM',120],['Deep Gnome','MPMM',120],['Shadar-Kai','MPMM',60],
  ['Sea Elf','MPMM',60],['Shifter','MPMM',60],['Triton','MPMM',60],
  ['Owlin','SCC',120],['Genasi (Air)','MPMM',60],['Elf (Drow)','PHB',120],
  ['Dwarf (Duergar)','MTF',120],['Dragonborn (Draconblood)','EGW',60],
  ['Dragonborn (Ravenite)','EGW',60],['Aasimar (Fallen)','VGM',60]
 ])assert.equal(calculateSenses({species:name,species_source:source},[],catalog).distances.darkvision,feet,name);
 assert.equal(calculateSenses({species:'Reborn',species_source:'VRGR'},[],catalog).distances.darkvision,undefined);
 assert.equal(calculateSenses({species:'Custom Lineage',species_source:'TCE'},[],catalog).distances.darkvision,undefined);
 assert.equal(calculateSenses({species:'Custom Lineage',species_source:'TCE',
  origin_sense_choices:{'race|tce|custom lineage':'darkvision'}},[],catalog).distances.darkvision,60);
 assert.equal(calculateSenses({species:'Custom Lineage',species_source:'TCE',
  origin_sense_choices:{'race|tce|custom lineage':'skill'}},[],catalog).distances.darkvision,undefined);
});
test('subrace senses respect book source and source activation',()=>{
 const elf={species:'Elf',species_source:'PHB',subrace:'Drow',subrace_source:'PHB'};
 assert.equal(calculateSenses(elf,[],catalog).distances.darkvision,120);
 assert.equal(calculateSenses({...elf,origin_enabled:{'subrace|phb|drow':false}},[],catalog).distances.darkvision,60);
 assert.equal(calculateSenses({...elf,subrace_source:'MTF'},[],catalog).distances.darkvision,60);
});
