import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {applyOriginSpellChoice} from '../spell_selection.js';
import {pendingCharacterChoices,savePendingChoice} from '../pending_choices.js';

const read=name=>JSON.parse(readFileSync(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const mechanics=read('class_mechanics');
const catalogs={classMechanics:mechanics,classFeatures:read('classes'),spells:mechanics.legacy_spells};
const character=(name,subclass,subclass_source,level=5)=>({kind:'character',rules_version:'2014',
 class:name,class_source:name==='Artificer'?'TCE':'PHB',subclass,subclass_source,level,
 classes:[{name,source:name==='Artificer'?'TCE':'PHB',subclass,subclass_source,level}],
 abilities:{str:10,dex:14,con:12,int:16,wis:16,cha:16}});
const feature=(sheet,name)=>sheet.features.find(row=>row.name===name);
const owned=(sheet,name)=>sheet.origin_spells.filter(row=>row.origin_id===feature(sheet,name)?.origin_id);

test('latest legacy spell progressions preserve their actual modes, owners and casting abilities',()=>{
 for(const [klass,subclass,source,trait,count,mode,ability] of [
  ['Artificer','Alchemist','TCE','Alchemist Spells',4,'prepared','int'],
  ['Artificer','Armorer','TCE','Armorer Spells',4,'prepared','int'],
  ['Cleric','Life Domain','PHB','Life Domain',6,'prepared','wis'],
  ['Druid','Circle of Spores','TCE','Circle Spells',5,'prepared','wis'],
  ['Druid','Circle of Wildfire','TCE','Circle Spells',6,'prepared','wis'],
  ['Paladin','Oath of the Crown','SCAG','Oath Spells',4,'prepared','cha'],
  ['Ranger','Horizon Walker','XGE','Horizon Walker Magic',2,'known','wis'],
  ['Ranger','Monster Slayer','XGE','Monster Slayer Magic',2,'known','wis'],
  ['Sorcerer','Aberrant Mind','TCE','Psionic Spells',7,'known','cha'],
  ['Sorcerer','Clockwork Soul','TCE','Clockwork Magic',6,'known','cha'],
  ['Warlock','The Celestial','XGE','Bonus Cantrips',2,'known','cha'],
 ]){
  const record=character(klass,subclass,source),sheet=calculateSheet(record,catalogs),spells=owned(sheet,trait);
  assert.equal(spells.length,count,`${subclass}: ${trait}`);
  for(const grant of spells){
   assert.equal(grant.mode,grant.cantrip?'known':mode,subclass);
   assert.equal(grant.payment_mode,grant.cantrip?'free':'slot',subclass);
   assert.equal(grant.spellcasting_ability,ability,subclass);
  }
  const owner=feature(sheet,trait);
  assert.equal(owned(calculateSheet({...record,origin_enabled:{[owner.origin_id]:false}},catalogs),trait).length,0);
  assert.equal(owned(calculateSheet({...record,trait_enabled:{[owner.key]:false}},catalogs),trait).length,0);
 }
});

test('multiclass gates use the owning class level and reject revised identities',()=>{
 const record=character('Ranger','Horizon Walker','XGE',3);
 record.level=17;record.classes.push({name:'Fighter',source:'PHB',level:14});
 assert.equal(owned(calculateSheet(record,catalogs),'Horizon Walker Magic').length,1);
 const revised={...record,rules_version:'2024',class_source:'XPHB',classes:[{...record.classes[0],source:'XPHB'}]};
 assert(!calculateSheet(revised,catalogs).origin_spells.some(row=>row.mechanic_source==='5etools.additionalSpells'));
});

test('Land and Divine Soul require an explicit option and never stack alternative lists',()=>{
 for(const [klass,subclass,source,trait,option,count] of [
  ['Druid','Circle of the Land','PHB','Circle Spells','Coast',4],
  ['Sorcerer','Divine Soul','XGE','Divine Magic','Good',1],
  ['Fighter','Arcane Archer','XGE','Arcane Archer Lore','1',1],
 ]){
  const record=character(klass,subclass,source),sheet=calculateSheet(record,catalogs);
  assert.equal(owned(sheet,trait).length,0);
  const choice=pendingCharacterChoices(record,sheet,catalogs).find(row=>row.kind==='spell_variant'&&row.origin_id===feature(sheet,trait).origin_id);
  assert(choice,subclass);
  const updated={...record,...savePendingChoice(record,choice,[option])};
  const selected=calculateSheet(updated,catalogs);
  assert.equal(owned(selected,trait).length,count,subclass);
  assert.equal(selected.origin_spell_variant_choices.find(row=>row.origin_id===choice.origin_id).remaining,0);
  assert.throws(()=>savePendingChoice(record,choice,['Invalid']),/consentita/);
 }
});

test('Arcane Initiate and Arcane Mastery have separate choices, class gates and slot costs',()=>{
 const record=character('Cleric','Arcana Domain','SCAG',17),sheet=calculateSheet(record,catalogs);
 const initiate=sheet.origin_choices.filter(row=>row.origin_id===feature(sheet,'Arcane Initiate').origin_id);
 const mastery=sheet.origin_choices.filter(row=>row.origin_id===feature(sheet,'Arcane Mastery').origin_id);
 assert.equal(initiate.length,1);assert.equal(initiate[0].count,2);
 assert.equal(mastery.length,4);
 const spell={id:'phb2014_globe_of_invulnerability',name:'Globe of Invulnerability',source:'PHB',level:6,classes:['Wizard']};
 const updated={...record,...applyOriginSpellChoice(record,mastery[0],spell)};
 const selected=calculateSheet(updated,{...catalogs,spells:[...catalogs.spells,spell]});
 assert.equal(owned(selected,'Arcane Mastery')[0].payment_mode,'slot');
 const lower={...updated,level:16,classes:[{...updated.classes[0],level:16}]};
 assert(!calculateSheet(lower,catalogs).origin_spells.some(row=>row.spell_id===spell.id));
 const changed={...updated,subclass:'Life Domain',subclass_source:'PHB',classes:[{...updated.classes[0],subclass:'Life Domain',subclass_source:'PHB'}]};
 assert(!calculateSheet(changed,catalogs).origin_spells.some(row=>row.spell_id===spell.id));
});

test('bonus cantrips absent from spell tables belong to their precise granting traits',()=>{
 for(const [klass,subclass,source,trait,spell] of [
  ['Cleric','Light Domain','PHB','Bonus Cantrip','phb2014_light'],
  ['Cleric','Grave Domain','XGE','Circle of Mortality','phb2014_spare_the_dying'],
  ['Druid','Circle of Spores','TCE','Circle Spells','phb2014_chill_touch'],
  ['Ranger','Drakewarden','FTD','Draconic Gift','phb2014_thaumaturgy'],
  ['Rogue','Arcane Trickster','PHB','Spellcasting','phb2014_mage_hand'],
  ['Monk','Way of Shadow','PHB','Shadow Arts','phb2014_minor_illusion'],
  ['Warlock','The Undying','SCAG','Among the Dead','phb2014_spare_the_dying'],
  ['Wizard','School of Illusion','PHB','Improved Minor Illusion','phb2014_minor_illusion'],
 ]){
  const sheet=calculateSheet(character(klass,subclass,source),catalogs);
  const grant=owned(sheet,trait).find(row=>row.spell_id===spell);
  assert(grant,`${subclass}: ${trait}`);assert.equal(grant.payment_mode,'free');
 }
});
