import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {fixedProficiencies,proficiencyGrantOrigins} from '../structured_effects.js';
import {pendingCharacterChoices,savePendingChoice} from '../pending_choices.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const catalog=read('../catalog/proficiency_grants.json');
const native=read('../../vtt/data/proficiency_grants_5etools.json');
const publishedLanguages=read('../../vtt/data/languages_5etools.json');
const catalogs={proficiencyGrants:catalog};
const char=(name,source,subrace='',subraceSource='')=>({
 kind:'character',rules_version:'2014',species:name,species_source:source,
 subrace,subrace_source:subraceSource,level:1,inventory:[],
 abilities:{str:10,dex:10,con:10,int:10,wis:10,cha:10}
});
const picks=(r)=>pendingCharacterChoices(r,calculateSheet(r,catalogs),catalogs)
 .filter(x=>x.kind==='proficiency'&&x.proficiency_kind==='language');
const has=(r,key)=>fixedProficiencies(r,catalog).has('language:'+key);
const row=(group,name,source,parent='')=>catalog[group].find(x=>x.name===name&&x.source===source&&
 (group!=='subrace'||x.raceName===parent));

test('2014 racial language catalog stays identical to native and reviewed generator manifest',()=>{
 for(const group of ['race','subrace']){
  assert.deepEqual(catalog[group],native[group],group+' language/proficiency parity');
  for(const entry of catalog[group]){
   for(const grant of entry.languageProficiencies||[]){
    assert(!Object.hasOwn(grant,'other'),entry.name+' cannot learn a literal language named other');
    assert(!grant.choose?.from?.includes('other'),entry.name+' requires a named or explicit choice');
   }
  }
 }
 // The existing PWA CI intentionally uses sparse checkout; verify critical
 // book-qualified cases without requiring the generator's source manifest here.
 for(const [group,name,book,parent,language] of [
  ['race','Aven','PSA','','aven'],['race','Aven','PSD','','aven'],
  ['race','Kalashtar','ERLW','','quori'],['race','Vedalken','GGR','','vedalken'],
  ['race','Grung','OGA','','grung'],['race','Gith','MTF','','gith'],
  ['race','Kender','DSotDQ','','common'],['race','Astral Elf','AAG','','common'],
  ['race','Hadozee','AAG','','common'],['race','Thri-kreen','AAG','','common'],
  ['subrace','Gem','FTD','Dragonborn','common'],
  ['subrace','Variant; Mark of Finding','ERLW','Half-Orc','goblin']
 ]){
  const entry=row(group,name,book,parent);
  assert(entry,name+' / '+book+' indexed');
  assert(entry.languageProficiencies.some(part=>part[language]===true),name+' missing '+language);
 }
});

test('complete typed 5etools language list is shared without adding another PWA request',()=>{
 assert.deepEqual(catalog.languages,native.languages);
 assert.deepEqual(catalog.languages,publishedLanguages.languages);
 assert(catalog.languages.length>=100);
 const [human]=picks(char('Human','PHB'));
 assert(human.options.includes('quori'),'exotic 2014 language is selectable');
 assert(human.options.includes('aven'),'named setting language is selectable');
 assert(!human.options.includes('druidic'),'class-only secret language is not freely selectable');
 assert(!human.options.includes(\"thieves' cant\"));
 assert(!human.options.includes('common sign language'),
   '2024 language introductions are not selectable by a 2014 character');
});

test('all indexed racial fixed languages project automatically and retain their source identity',()=>{
 for(const entry of catalog.race.filter(x=>Array.isArray(x.languageProficiencies))){
  const r=char(entry.name,entry.source),actual=fixedProficiencies(r,catalog);
  assert(!actual.has('language:other'));
  for(const grant of entry.languageProficiencies)
   for(const [name,value] of Object.entries(grant))
    if(value===true)assert(actual.has('language:'+name),
      entry.name+' ('+entry.source+') missing '+name);
 }
 assert(has(char('Grung','OGA'),'grung'));
 assert(!has(char('Grung','OGA'),'common'));
 assert(has(char('Kalashtar','ERLW'),'quori'));
 assert(has(char('Aven','PSD'),'aven'));
 assert(has(char('Aven','PSA'),'aven'));
});

test('PHB and later 2014 races use the same typed language picker, persistence and origin',()=>{
 for(const [name,source,count] of [
  ['Human','PHB',1],['Half-Elf','PHB',1],['Aasimar','MPMM',1],
  ['Kalashtar','ERLW',1],['Astral Elf','AAG',1],['Autognome','AAG',1],
  ['Owlin','SCC',1],['Plasmoid','AAG',1],['Hadozee','AAG',1],
  ['Thri-kreen','AAG',1],['Aetherborn','PSK',2]]){
  const r=char(name,source),rows=picks(r),sid='race|'+source.toLowerCase()+'|'+name.toLowerCase();
  assert.equal(rows.length,1,name+' / '+source+' needs one choice group');
  assert.equal(rows[0].origin_id,sid);
  assert.equal(rows[0].count,count);
  assert.equal(rows[0].remaining,count);
  const values=count===2?['draconic','dwarvish']:['draconic'];
  const chosen={...r,...savePendingChoice(r,rows[0],values)};
  assert.equal(picks(chosen)[0].remaining,0);
  assert(has(chosen,'draconic'),name+' selected language missing');
  const changed={...chosen,species:'Gnome',species_source:'PHB'};
  assert(!has(changed,'draconic'),name+' must not leak a saved racial language');
  assert(!has({...chosen,origin_enabled:{[sid]:false}},'draconic'));
 }
});

test('previously stored 5etools other placeholders never grant or fulfill a language choice',()=>{
 const record={...char('Kalashtar','ERLW'),proficiency_choices:[
  {kind:'language',key:'other',origin_id:'race|erlw|kalashtar',origin_name:'Languages'}]};
 assert(!has(record,'other'));
 assert(has(record,'quori'));
 const [choice]=picks(record);
 assert.equal(choice.remaining,1);
 assert(!choice.options.includes('other'));
 const selected={...record,...savePendingChoice(record,choice,['sylvan'])};
 assert(has(selected,'sylvan'));
 assert(!has(selected,'other'));
});

test('Simic Hybrid offers exactly Elvish or Vedalken; both are source-qualified',()=>{
 const r=char('Simic Hybrid','GGR'),[choice]=picks(r);
 assert(choice);
 assert.deepEqual(choice.options,['elvish','vedalken']);
 assert.throws(()=>savePendingChoice(r,choice,['dwarvish']),/Selezione/);
 const chosen={...r,...savePendingChoice(r,choice,['vedalken'])};
 assert(has(chosen,'vedalken'));
 assert(proficiencyGrantOrigins(chosen,catalog,'language','vedalken')
  .some(source=>source.id==='race|ggr|simic hybrid'||source.origin_parent_id==='race|ggr|simic hybrid'));
});

test('later Dragonborn subraces replace base languages rather than adding Draconic',()=>{
 for(const name of ['Chromatic','Gem','Metallic']){
  const r=char('Dragonborn','PHB',name,'FTD');
  assert(has(r,'common'));
  assert(!has(r,'draconic'),name+' has its own 2014-era language rules');
  const [picker]=picks(r);
  assert(picker&&picker.origin_id==='subrace|ftd|'+name.toLowerCase());
  const legacy={...r,proficiency_choices:[{kind:'language',key:'draconic',origin_id:'race|phb|dragonborn'}]};
  assert(!has(legacy,'draconic'),'legacy saved parent choice should be withdrawn');
  const selected={...legacy,...savePendingChoice(legacy,picker,['sylvan'])};
  assert(has(selected,'sylvan'));
  assert(!has(selected,'draconic'));
  assert(has({...legacy,subrace:'',subrace_source:''},'draconic'));
  assert(has({...legacy,origin_enabled:{['subrace|ftd|'+name.toLowerCase()]:false}},'draconic'));
 }
});

test('Mark of Finding changes ancestry languages, while ordinary High Elf adds one',()=>{
 for(const parent of ['Half-Orc','Human']){
  const r=char(parent,'PHB','Variant; Mark of Finding','ERLW');
  assert(has(r,'goblin'));assert(has(r,'common'));
  assert(!has(r,'orc'),'Mark of Finding replaces Half-Orc language');
 }
 const keldon=char('Human','PHB','Keldon','PSD');
 assert(has(keldon,'keldon'));
 assert.equal(picks(keldon).length,0,'Keldon replaces the Human free language choice');
 const high=char('Elf','PHB','High','PHB');
 assert(has(high,'elvish'));assert(has(high,'common'));
 assert.equal(picks(high).filter(x=>x.origin_id==='subrace|phb|high').length,1);
 const merfolk=char('Merfolk','PSZ','Ixalan; Blue','PSX');
 assert.equal(picks(merfolk).length,1,'Ixalan Merfolk must not duplicate parent language choice');
});
