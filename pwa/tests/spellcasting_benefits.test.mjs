import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet,castingClasses,spellProgression} from '../sheet_rules.js';
import {spellEligible,knownSpellProgress} from '../spell_selection.js';
import {powerSelectionModels} from '../power_selection.js';

const load=name=>JSON.parse(readFileSync(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const catalog={classMechanics:load('class_mechanics'),classFeatures:load('classes'),
 spellcastingBenefits:load('spellcasting_benefits'),powerSelections:load('power_selections')};
const klass=(name,source,level,subclass='',subclassSource=source)=>({
 name,source,level,...(subclass?{subclass,subclass_source:subclassSource}:{})
});
const record=(classes,rules_version='2014')=>({kind:'character',rules_version,classes,
 level:classes.reduce((n,row)=>n+row.level,0),
 abilities:{str:10,dex:10,con:10,int:16,wis:16,cha:16},inventory:[]});
const sheet=(classes,edition='2014',extra={})=>calculateSheet(
 {...record(classes,edition),...extra},catalog);

test('a class earns spell slots only from its active feature-level benefit',()=>{
 const c=klass('Wizard','PHB',5),all=sheet([c]);
 assert.equal(all.casting_classes.length,1);
 const wizard=all.casting_classes[0];
 assert.equal(wizard.spell_list_class,'Wizard');
 assert.equal(wizard.ability,'int');
 assert.equal(wizard.granting_trait_name,'Spellcasting');
 assert.equal(wizard.book,true);
 assert.equal(wizard.known_limit,14);
 assert.equal(wizard.limit,8);
 assert.equal(wizard.cantrips,4);
 assert.deepEqual(all.spell_slots.slice(0,3).map(r=>r.total),[4,3,2]);
 const disabled=sheet([c],'2014',{origin_enabled:{[wizard.granting_trait_id]:false}});
 assert.equal(disabled.casting_classes.length,0);
 assert.deepEqual(disabled.spell_slots.slice(0,3).map(r=>r.total),[0,0,0]);
 assert.equal(sheet([c],'2014',{spell_slots_manual:true,spell_slots_total:[0,7]})
   .spell_slots[0].total,7,'manual slots remain independent of casting grants');
});

test('full, half-round-down, half-round-up and pact progression come only from data',()=>{
 const old=sheet([klass('Wizard','PHB',3),klass('Paladin','PHB',3)]);
 assert.equal(old.casting_classes.length,2);
 assert.equal(old.spell_slots[2].total,3,'2014 total caster level four has three level-two slots');
 const modern=sheet([klass('Wizard','XPHB',3),klass('Paladin','XPHB',3)],'2024');
 assert.equal(modern.spell_slots[2].total,3,'2024 half caster rounds up to caster level five');
 assert.equal(modern.spell_slots[3].total,0);
 assert.equal(modern.spell_slots[2].base,3);
 const pact=sheet([klass('Warlock','PHB',11)]);
 assert.equal(pact.pact_slots.total,3);
 assert.equal(pact.pact_slots.level,5);
 assert.equal(pact.spell_slots[0].total,0);
 const art=sheet([klass('Artificer','TCE',1)]);
 assert.equal(art.spell_slots[0].total,2,'Artificer has half-up progression from level one');
});

test('subclass spellcasting uses its parent level and an independent 5eTools spell list',()=>{
 const fighter=sheet([klass('Fighter','PHB',7,'Eldritch Knight','PHB')]);
 const caster=fighter.casting_classes[0];
 assert.equal(caster.name,'Fighter');
 assert.equal(caster.spell_list_class,'Wizard');
 assert.equal(caster.ability,'int');
 assert.equal(caster.max_level,2);
 assert.equal(caster.limit,5);
 assert.equal(caster.cantrips,2);
 assert.equal(fighter.spell_slots[0].total,4);
 assert.equal(fighter.spell_slots[1].total,2);
 assert.equal(spellEligible({id:'shield',level:1,classes:['Wizard']},caster),true);
 assert.equal(spellEligible({id:'cure',level:1,classes:['Cleric']},caster),false);
 const rogue=sheet([klass('Rogue','XPHB',3,'Arcane Trickster','XPHB')],'2024');
 assert.equal(rogue.casting_classes[0].spell_list_class,'Wizard');
 assert.equal(rogue.casting_classes[0].cantrips,3);
 const multiclass=sheet([klass('Fighter','PHB',6,'Eldritch Knight','PHB'),klass('Wizard','PHB',3)]);
 assert.equal(multiclass.spell_slots[2].total,2,'third-caster floors in multiclass');
});

test('spellcasting grant metadata controls progression even for a renamed spell list',()=>{
 const original=catalog.spellcastingBenefits;
 const altered=structuredClone(original);
 const wizard=altered.grants.find(row=>row.feature_id==='5etools:class_features:phb:spellcasting:wizard:1');
 wizard.benefit.spell_list_class='Druid';
 wizard.benefit.slot_progression={kind:'shared',fraction:0.5,single_rounding:'ceil',multiclass_rounding:'floor'};
 const custom={...catalog,spellcastingBenefits:altered};
 const result=calculateSheet(record([klass('Wizard','PHB',5)]),custom);
 assert.equal(result.casting_classes[0].spell_list_class,'Druid');
 assert.equal(result.spell_slots[2].total,0);
 assert.equal(spellEligible({level:1,classes:['Druid']},result.casting_classes[0]),true);
 assert.equal(spellEligible({level:1,classes:['Wizard']},result.casting_classes[0]),false);
});

test('class-specific levels participate in ordinary arithmetic formulas',()=>{
 const c=record([klass('Wizard','PHB',3),klass('Paladin','PHB',4)]);
 const out=calculateSheet({...c,formula_bonuses:[
  {id:'class-level-test',target:'initiative',expression:'class_level_wizard + class_level_paladin'}
 ]},catalog);
 assert.equal(out.values['class_level:wizard'],3);
 assert.equal(out.values['class_level:paladin'],4);
 assert.equal(out.stats.initiative,7);
});

test('spell selections expose typed learned/prepared layers and their data limits',()=>{
 const calculated=sheet([klass('Wizard','PHB',5)]);
 const models=powerSelectionModels(record([klass('Wizard','PHB',5)]),calculated,catalog.powerSelections);
 const magic=models.find(model=>model.benefit_type==='class_spellcasting');
 assert.ok(magic);
 assert.deepEqual(Object.keys(magic.layers),['learned','prepared']);
 assert.equal(magic.layers.learned.limit,null);
 assert.equal(magic.layers.prepared.limit,8);
 assert.equal(knownSpellProgress({spellbook_spells:[{id:'shield',level:1}]},
   calculated.casting_classes[0],calculated.casting_classes,[]).minimum,14);
});
