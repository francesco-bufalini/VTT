import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet,castingClasses,spellProgression,formulaValue} from '../sheet_rules.js';
import {spellEligible,knownSpellProgress,knownClassSpellIds,changeKnownClassSpell,
  addSelectedSpell,removeSelectedSpell} from '../spell_selection.js';

const load=name=>JSON.parse(readFileSync(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const catalogs={
  classFeatures:load('classes'),classMechanics:load('class_mechanics'),
  spellcastingBenefits:load('spellcasting_benefits')
};
const record=(name,level,extras={})=>({
  kind:'character',rules_version:'2014',level,class:name,class_source:name==='Artificer'?'TCE':'PHB',
  abilities:{str:10,dex:12,con:12,int:16,wis:16,cha:16},
  spell_slots_automatic:true,...extras
});
const member=(name,level,extras={})=>{
  const calculated=calculateSheet(record(name,level,extras),catalogs);
  assert.equal(calculated.casting_classes.length,1,name+' has one owned casting feature');
  return [calculated,calculated.casting_classes[0]];
};

test('2014 caster types, lists, ability and preparation come from their active benefit',()=>{
 const [wizard,w]=member('Wizard',5);
 assert.equal(w.spell_list_class_name,'Wizard');
 assert.equal(w.level_class_name,'Wizard');
 assert.equal(w.ability,'int');
 assert.equal(w.knowledge_mode,'prepared');
 assert.equal(w.selection_layers.learned.mode,'manual');
 assert.equal(w.selection_layers.learned.storage,'known_spell_overrides');
 assert.equal(w.learned_limit,14);
 assert.equal(w.limit,8);
 assert.deepEqual(wizard.spell_slots.slice(0,3).map(s=>s.total),[4,3,2]);
 assert.equal(formulaValue('class_level_wizard + int_mod',wizard),8);
 const [,cleric]=member('Cleric',5);
 assert.equal(cleric.knowledge_mode,'prepared');
 assert.equal(cleric.limit,8);
 const [,bard]=member('Bard',5);
 assert.equal(bard.knowledge_mode,'known');
 assert.equal(bard.limit,8);
 const [,artificer]=member('Artificer',3);
 assert.equal(artificer.slot_progression.divisor,2);
 assert.equal(artificer.limit,4,'class level / 2 rounded down plus intelligence');
 const [warlock,k]=member('Warlock',11);
 assert.equal(k.slot_progression.pool,'pact');
 assert.equal(warlock.pact_slots.total,3);
 assert.equal(warlock.pact_slots.level,5);
 assert.equal(warlock.spell_slots[0].total,0);
});

test('a class and level alone never create spell slots without a live feature benefit',()=>{
 const base=record('Wizard',5);
 const fromClassAlone=calculateSheet(base,{classMechanics:catalogs.classMechanics});
 assert.equal(fromClassAlone.casting_classes.length,0);
 assert.ok(fromClassAlone.spell_slots.every(s=>s.total===0));
 const [calculated,casting]=member('Wizard',5);
 const muted=calculateSheet({...base,
   origin_enabled:{[casting.granting_trait_id]:false}},catalogs);
 assert.deepEqual(muted.casting_classes,[]);
 assert.ok(muted.spell_slots.every(s=>s.total===0));
});

test('half and one-third caster progressions include only their subclass benefit',()=>{
 const [ranger,r]=member('Ranger',2);
 assert.equal(r.knowledge_mode,'known');
 assert.equal(r.limit,2);
 assert.equal(ranger.spell_slots[0].total,2);
 const paladinBefore=calculateSheet(record('Paladin',1),catalogs);
 assert.equal(paladinBefore.casting_classes.length,0);
 const [paladin]=member('Paladin',2);
 assert.equal(paladin.spell_slots[0].total,2);
 const fighter=record('Fighter',7,{subclass:'Eldritch Knight',subclass_source:'PHB'});
 const fk=calculateSheet(fighter,catalogs);
 assert.equal(fk.casting_classes.length,1);
 assert.equal(fk.casting_classes[0].spell_list_class_name,'Wizard');
 assert.equal(fk.casting_classes[0].level_class_name,'Fighter');
 assert.equal(fk.casting_classes[0].learned_limit,5);
 assert.equal(fk.spell_slots[0].total,4);
 assert.equal(fk.spell_slots[1].total,2);
 assert.equal(spellEligible({id:'s',name:'Shield',level:1,classes:['Wizard']},
   fk.casting_classes[0]),true);
 const [rogue,at]=member('Rogue',3,{subclass:'Arcane Trickster',subclass_source:'PHB'});
 assert.equal(at.spell_list_class_name,'Wizard');
 assert.equal(at.cantrips,3);
 assert.equal(rogue.spell_slots[0].total,2);
 const noSub=calculateSheet(record('Fighter',7),catalogs);
 assert.equal(noSub.casting_classes.length,0);
});

test('multiclass rounds 2014 third and half casters down, but preserves separate pact slots',()=>{
 const c={
   ...record('Wizard',11),
   level:11,
   classes:[{name:'Wizard',source:'PHB',level:3},
     {name:'Fighter',source:'PHB',level:7,subclass:'Eldritch Knight',subclass_source:'PHB'},
     {name:'Warlock',source:'PHB',level:1}]
 };
 const r=calculateSheet(c,catalogs);
 assert.equal(r.casting_classes.length,3);
 assert.equal(r.spell_slots[0].total,4);
 assert.equal(r.spell_slots[1].total,3);
 assert.equal(r.spell_slots[2].total,2,'3 + floor(7/3) = caster 5');
 assert.equal(r.pact_slots.total,1);
 assert.equal(r.pact_slots.level,1);
 assert.equal(formulaValue('class_level_wizard + class_level_fighter',r),10);
 const w=r.casting_classes.find(m=>m.name==='Wizard');
 assert.deepEqual(knownSpellProgress({spellbook_spells:[]},w,r.casting_classes,[]),
   {known:0,minimum:10});
});

test('custom class and foreign 5eTools spell list require no named-class branches',()=>{
 const record={classes:[{name:'Scholar',source:'HB',level:7}],abilities:{wis:14}};
 const benefit={type:'spell_selection',level_class_name:'Scholar',spell_list_class_name:'Wizard',
   source:{type:'spell_catalog',class_name:'Wizard'},ability:'wis',knowledge_mode:'known',
   slot_progression:{pool:'shared',divisor:4,single_round:'ceil',multiclass_round:'floor'},
   layers:{learned:{limit:{formula:'2 + class_level_scholar'},trigger:'level_up'}},
   cantrips:{limit:{by_class_level:[[1,1],[5,2]]}}};
 const trait={name:'Academic Spellcasting',key:'scholar',origin_key:'class|hb|scholar',
   origin_id:'feature:scholar',benefits:[benefit]};
 const [caster]=castingClasses(record,null,{wis:2},[trait]);
 assert.equal(caster.level_class_name,'Scholar');
 assert.equal(caster.spell_list_class_name,'Wizard');
 assert.equal(caster.learned_limit,9);
 assert.equal(caster.cantrips,2);
 assert.equal(caster.ability,'wis');
 assert.equal(spellProgression(record,[caster]).caster_level,2);
 assert.equal(spellEligible({id:'shield',name:'Shield',classes:['Wizard'],level:1},caster),true);
 assert.equal(spellEligible({id:'guidance',name:'Guidance',classes:['Cleric'],level:0},caster),false);
 assert.equal(castingClasses(record,null,{wis:2},[]).length,0,
   'a class without the spell-selection benefit cannot cast');
});

test('prepared spell minimum is read from benefit data, not a caster name',()=>{
 const original=catalogs.spellcastingBenefits.grants.find(g=>
   g.owner.class_name==='Cleric'&&g.owner.class_source==='PHB');
 const trait={name:'Spellcasting',key:'caster',origin_key:'class|phb|cleric',
   origin_id:'feature:caster',benefits:[original.benefit]};
 const [caster]=castingClasses({classes:[{name:'Cleric',source:'PHB',level:1}],abilities:{wis:1}},
   null,{wis:-5},[trait]);
 assert.equal(caster.limit,1);
});

test('learned and prepared spells share class-agnostic operations without a book',()=>{
 const [,caster]=member('Wizard',5);
 const [,automatic]=member('Cleric',5);
 const catalog=Array.from({length:18},(_,i)=>({
   id:'test_spell_'+i,name:'Test spell '+i,source:'PHB',level:1,classes:['Wizard','Cleric']
 }));
 let saved={rules_version:'2014',prepared_spells:[],spells:[],known_spell_overrides:{}};
 assert.deepEqual([...knownClassSpellIds(saved,caster,catalog)],[]);
 assert.equal(knownClassSpellIds(saved,automatic,catalog).size,18);
 for(const spell of catalog.slice(0,16))
   saved={...saved,...changeKnownClassSpell(saved,caster,spell,true,catalog)};
 assert.equal(knownClassSpellIds(saved,caster,catalog).size,16);
 assert.deepEqual(knownSpellProgress(saved,caster,[caster],catalog),{known:16,minimum:14},
   'learned limits remain advisory');
 assert.equal(saved.spellbook_spells,undefined,'learning never creates a book');
 saved={...saved,...addSelectedSpell(saved,catalog[0],'prepared_spells',
   {member:caster,classes:[caster],catalog})};
 assert.equal(saved.prepared_spells.length,1);
 assert.deepEqual(saved.prepared_spells,saved.spells);
 assert.throws(()=>addSelectedSpell(saved,catalog[17],'prepared_spells',
   {member:caster,classes:[caster],catalog}),/non conosciuto/);
 saved={...saved,...changeKnownClassSpell(saved,caster,catalog[0],false,catalog)};
 saved={...saved,...removeSelectedSpell(saved,'prepared_spells',0,
   {classId:caster.id,classes:[caster],catalog})};
 assert.equal(knownClassSpellIds(saved,caster,catalog).has(catalog[0].id),false);
 assert.equal(saved.prepared_spells.length,0);
});

test('legacy saved book entries remain learnable through the generic manual layer',()=>{
 const [,caster]=member('Wizard',5);
 const spell={id:'shield_legacy',name:'Shield',level:1,source:'PHB',classes:['Wizard']};
 const catalog=[spell];
 let saved={rules_version:'2014',spellbook_spells:[spell],
   known_spell_overrides:{},prepared_spells:[]};
 assert.equal(knownClassSpellIds(saved,caster,catalog).has(spell.id),true);
 saved={...saved,...changeKnownClassSpell(saved,caster,spell,false,catalog)};
 assert.equal(knownClassSpellIds(saved,caster,catalog).has(spell.id),false);
 saved={...saved,...changeKnownClassSpell(saved,caster,spell,true,catalog)};
 assert.equal(knownClassSpellIds(saved,caster,catalog).has(spell.id),true);
 assert.equal(saved.spellbook_spells.length,1,'legacy data remains untouched');
});
