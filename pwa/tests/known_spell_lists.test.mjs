import {test} from 'node:test';
import assert from 'node:assert/strict';
import {knownClassSpellIds,knownClassCantripIds,knownSpellProgress,sessionSpellEntries,classSelectionCount,
  changeKnownClassSpell,addSelectedSpell,removeSelectedSpell} from '../spell_selection.js';

const cleric={id:'class|phb|cleric',name:'Cleric',mode:'Preparati',max_level:3,book:false};
const wizard={id:'class|phb|wizard',name:'Wizard',mode:'Preparati',max_level:3,book:true,known_limit:12};
const bard={id:'class|phb|bard',name:'Bard',mode:'Conosciuti',max_level:3,book:false};
const catalog=[
 {id:'cure',name:'Cure Wounds',source:'PHB',level:1,classes:['Cleric']},
 {id:'shield',name:'Shield',source:'PHB',level:1,classes:['Wizard']},
 {id:'light',name:'Light',source:'PHB',level:0,classes:['Cleric','Wizard']}
];

test('preparing casters initially know their class list without changing saved sheets',()=>{
 const record={rules_version:'2014',prepared_spells:[],spells:[]};
 assert.deepEqual([...knownClassSpellIds(record,cleric,catalog)].sort(),['cure']);
 assert.deepEqual(knownClassSpellIds(record,wizard,catalog),new Set(),
   'cantrips must be explicitly learned, not automatically taken from the entire class list');
 assert.equal(record.known_spell_overrides,undefined);
});

test('known-spell overrides can remove class spells and add non-class spells',()=>{
 let record={rules_version:'2014',prepared_spells:[],spells:[]};
 record={...record,...changeKnownClassSpell(record,cleric,catalog[0],false,catalog)};
 assert.equal(knownClassSpellIds(record,cleric,catalog).has('cure'),false);
 record={...record,...changeKnownClassSpell(record,cleric,catalog[1],true,catalog)};
 assert.equal(knownClassSpellIds(record,cleric,catalog).has('shield'),true);
 record={...record,...addSelectedSpell(record,catalog[1],'prepared_spells',
   {member:cleric,classes:[cleric],catalog})};
 assert.equal(record.prepared_spells[0].id,'shield');
 assert.deepEqual(record.spells,record.prepared_spells,'legacy desktop spells remain synchronized');
 record={...record,...removeSelectedSpell(record,'prepared_spells',0,
   {classId:cleric.id,classes:[cleric],catalog})};
 assert.equal(record.prepared_spells.length,0);
 assert.equal(knownClassSpellIds(record,cleric,catalog).has('shield'),true,
   'unpreparing does not delete the known-spell choice');
 record={...record,...changeKnownClassSpell(record,cleric,catalog[1],false,catalog)};
 assert.equal(knownClassSpellIds(record,cleric,catalog).has('shield'),false);
});

test('wizard spellbook stays the source of known spells and known-only preparation',()=>{
 const base={rules_version:'2014',prepared_spells:[],spellbook_spells:[]};
 assert.throws(()=>addSelectedSpell(base,catalog[1],'prepared_spells',
   {member:wizard,classes:[wizard],catalog}),/libro/);
 const book=addSelectedSpell(base,catalog[1],'spellbook_spells',
   {member:wizard,classes:[wizard],catalog});
 let record={...base,...book};
 assert.equal(knownClassSpellIds(record,wizard,catalog).has('shield'),true);
 record={...record,...addSelectedSpell(record,catalog[1],'prepared_spells',
   {member:wizard,classes:[wizard],catalog})};
 assert.equal(record.prepared_spells.length,1);
});

test('wizard cantrips can be learned and forgotten without changing the spellbook',()=>{
 let c={rules_version:'2014',prepared_spells:[],spellbook_spells:[]};
 assert.equal(knownClassSpellIds(c,wizard,catalog).has('light'),false);
 c={...c,...changeKnownClassSpell(c,wizard,catalog[2],true,catalog)};
 assert.equal(knownClassSpellIds(c,wizard,catalog).has('light'),true);
 c={...c,...changeKnownClassSpell(c,wizard,catalog[2],false,catalog)};
 assert.equal(knownClassSpellIds(c,wizard,catalog).has('light'),false);
 assert.deepEqual(c.spellbook_spells,[]);
});

test('known-spell overrides never alter spontaneous casters',()=>{
 const record={prepared_spells:[{...catalog[0],casting_classes:[bard.id]}]};
 assert.equal(knownClassSpellIds(record,bard,catalog).has('cure'),true);
 assert.throws(()=>changeKnownClassSpell(record,bard,catalog[0],false,catalog),/non è modificabile/);
});

test('learned cantrips for preparing classes are immediately castable without preparation',()=>{
 let c={rules_version:'2014',prepared_spells:[],spells:[],spellbook_spells:[]};
 c={...c,...changeKnownClassSpell(c,cleric,catalog[2],true,catalog)};
 assert.equal(knownClassCantripIds(c,cleric,catalog).has('light'),true);
 assert.equal(availableCount(c,cleric),1);
 assert.equal(c.prepared_spells.length,0,'Learning does not prepare or duplicate cantrips in saved spells');
 const calculated={casting_classes:[cleric],origin_spells:[]};
 assert.deepEqual(sessionSpellEntries(c,calculated,catalog).map(spell=>spell.id),['light']);
 assert.throws(()=>addSelectedSpell(c,catalog[2],'prepared_spells',
   {member:cleric,classes:[cleric],catalog}),/non si preparano/);
 c={...c,...changeKnownClassSpell(c,cleric,catalog[2],false,catalog)};
 assert.deepEqual(sessionSpellEntries(c,calculated,catalog),[],
   'Forgetting a known cantrip removes the automatic casting option');
});

test('cantrips already saved by old preparation remain ready, without duplicate casts',()=>{
 const old={rules_version:'2014',prepared_spells:[{...catalog[2],casting_classes:[cleric.id]}],
   spells:[{...catalog[2],casting_classes:[cleric.id]}]};
 const calculated={casting_classes:[cleric],origin_spells:[]};
 assert.equal(knownClassCantripIds(old,cleric,catalog).has('light'),true);
 assert.equal(availableCount(old,cleric),1);
 const entries=sessionSpellEntries(old,calculated,catalog);
 assert.equal(entries.length,1);
 assert.equal(entries[0].id,'light');
 const newer={...old,...changeKnownClassSpell(old,cleric,catalog[2],false,catalog)};
 assert.equal(knownClassCantripIds(newer,cleric,catalog).has('light'),false);
});

function availableCount(record,member){
 return classSelectionCount(record,member,[member],catalog).cantrips;
}

test('known-spell limits appear for spontaneous casters; wizard book is the known list',()=>{
 const sorcerer={id:'class|phb|sorcerer',name:'Sorcerer',mode:'Conosciuti',
  limit:4,level:5,max_level:3,cantrips:4};
 const sorcery={id:'chaos',name:'Chaos Bolt',source:'PHB',level:1,classes:['Sorcerer']};
 const sc={prepared_spells:[{...sorcery,casting_classes:[sorcerer.id]}]};
 assert.deepEqual(knownSpellProgress(sc,sorcerer,[sorcerer],[sorcery]),{known:1,minimum:4});
 const wc={spellbook_spells:[catalog[1]],prepared_spells:[]};
 assert.deepEqual(knownSpellProgress(wc,{...wizard,level:4},[wizard],catalog),{known:1,minimum:12});
});
test('preparing a spell granted by another origin cannot duplicate it',()=>{
 const c={prepared_spells:[],spells:[]};
 assert.throws(()=>addSelectedSpell(c,catalog[0],'prepared_spells',
  {member:cleric,classes:[cleric],catalog,grantedSpells:[{spell_id:'cure',origin_name:'Divine Domain'}]}),
  /sempre disponibile/);
 assert.equal(c.prepared_spells.length,0);
});
test('unfiltered learning may add off-class spells without changing normal class eligibility',()=>{
 const sc={id:'class|phb|sorcerer',name:'Sorcerer',mode:'Conosciuti',max_level:3};
 const rogueSpell=catalog[0];
 assert.throws(()=>addSelectedSpell({},rogueSpell,'prepared_spells',
   {member:sc,classes:[sc],catalog}),/non conosciuto/);
 const r=addSelectedSpell({},rogueSpell,'prepared_spells',
   {member:sc,classes:[sc],catalog,allowNonClass:true});
 assert.equal(r.prepared_spells[0].id,'cure');
});
