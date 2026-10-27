import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {pendingCharacterChoices,savePendingChoice} from '../pending_choices.js';
const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const catalog=read('../catalog/proficiency_grants.json');
const native=read('../../vtt/data/proficiency_grants_5etools.json');
const catalogs={proficiencyGrants:catalog,classMechanics:read('../catalog/class_mechanics.json'),
 classFeatures:read('../catalog/classes.json'),abilityGrants:read('../catalog/ability_grants.json')};
const ch=(name,level=1,sub='',book='')=>({kind:'character',rules_version:'2014',
 level,class:name,class_source:'PHB',subclass:sub,subclass_source:book,
 classes:[{name,source:'PHB',level,subclass:sub,subclass_source:book}],
 abilities:{str:10,dex:12,con:12,int:12,wis:14,cha:14},inventory:[]});
const sheet=r=>calculateSheet(r,catalogs);
const trait=(r,name)=>sheet(r).features.find(x=>x.name===name);
const choices=r=>pendingCharacterChoices(r,sheet(r),catalogs).filter(x=>
 x.kind==='proficiency'&&['language','mixed'].includes(x.proficiency_kind));
const own=(r,language,feature)=>{
 const s=sheet(r),f=trait(r,feature);
 assert(f,'Missing trait: '+feature);
 assert(s.proficiencies.includes('language:'+language),'Missing '+language);
 assert(s.proficiency_sources['language:'+language]?.some(x=>x.id===f.origin_id),
   language+' is not linked to '+feature);
 return f;
};
test('native and PWA feature language indexes stay identical',()=>{
 for(const key of ['classFeature','subclassFeature'])assert.deepEqual(catalog[key],native[key]);
 for(const [name,level,book] of [
  ['Favored Enemy',1,'PHB'],['Favored Enemy and Natural Explorer improvements',6,'PHB'],
  ['Favored Enemy improvement',14,'PHB'],['Deft Explorer',1,'TCE'],
  ['Dragon Ancestor',1,'PHB'],['Blessings of Knowledge',1,'PHB'],
  ['Draconic Disciple',3,'FTD'],['Giant Power',3,'BGG']
 ])assert([...catalog.classFeature,...catalog.subclassFeature]
   .some(x=>x.name===name&&x.level===level&&x.source===book),name);
});
test('Favored Enemy adds one ranger language at levels 1, 6 and 14',()=>{
 for(const [level,expected] of [[1,1],[5,1],[6,2],[13,2],[14,3]]){
  const r=ch('Ranger',level),picks=choices(r).filter(x=>x.proficiency_kind==='language');
  assert.equal(picks.length,expected,'Level '+level);
  assert(picks.every(x=>x.count===1&&!x.options.includes('druidic')));
  assert.equal(new Set(picks.map(x=>x.origin_id)).size,expected);
 }
 const r=ch('Ranger',6),pick=choices(r)[0];
 const saved={...r,...savePendingChoice(r,pick,['sylvan'])};
 assert(sheet(saved).proficiencies.includes('language:sylvan'));
 assert(!sheet({...saved,classes:[{...saved.classes[0],level:0}]})
   .proficiencies.includes('language:sylvan'));
});
test('Knowledge cleric learns two choices and Draconic Bloodline learns Draconic',()=>{
 const r=ch('Cleric',1,'Knowledge','PHB'),[p]=choices(r);
 assert(p&&p.count===2&&p.options.includes('quori'));
 const saved={...r,...savePendingChoice(r,p,['sylvan','celestial'])};
 own(saved,'sylvan','Blessings of Knowledge');
 assert(!sheet({...saved,classes:[{...saved.classes[0],subclass:'Life'}]})
   .proficiencies.includes('language:sylvan'));
 const sorcerer=ch('Sorcerer',1,'Draconic','PHB');
 const owner=own(sorcerer,'draconic','Dragon Ancestor');
 assert(!sheet({...sorcerer,origin_enabled:{[owner.origin_id]:false}})
   .proficiencies.includes('language:draconic'));
});
test('Rune Knight grants Giant, dragon subclasses choose languages at level 3',()=>{
 own(ch('Fighter',3,'Rune Knight','TCE'),'giant','Bonus Proficiencies');
 assert(!sheet(ch('Fighter',2,'Rune Knight','TCE')).proficiencies.includes('language:giant'));
 for(const [klass,sub,book,name] of [
  ['Monk','Ascendant Dragon','FTD','Draconic Disciple'],
  ['Ranger','Drakewarden','FTD','Draconic Gift']]){
  const below=ch(klass,2,sub,book);assert(!trait(below,name));
  const r=ch(klass,3,sub,book),owner=trait(r,name);
  assert(owner);
  const p=choices(r).find(x=>x.origin_id===owner.origin_id);
  assert(p&&p.count===1&&p.options.includes('draconic'));
  own({...r,...savePendingChoice(r,p,['draconic'])},'draconic',name);
 }
});
test('Cavalier and Samurai get exactly one skill OR one language',()=>{
 for(const [sub,yes,no] of [
  ['Cavalier','animal handling','arcana'],['Samurai','history','animal handling']]){
  const r=ch('Fighter',3,sub,'XGE'),owner=trait(r,'Bonus Proficiency');
  assert(owner);
  const p=choices(r).find(x=>x.origin_id===owner.origin_id);
  assert(p&&p.proficiency_kind==='mixed'&&p.count===1);
  assert(p.options.includes('skill:'+yes));
  assert(!p.options.includes('skill:'+no));
  assert(p.options.includes('language:draconic'));
  assert(!p.options.includes('language:druidic'));
  assert.throws(()=>savePendingChoice(r,p,['skill:'+yes,'language:draconic']));
  const learned={...r,...savePendingChoice(r,p,['language:draconic'])};
  own(learned,'draconic','Bonus Proficiency');
  const switched={...learned,...savePendingChoice(learned,p,['skill:'+yes])};
  assert(!sheet(switched).proficiencies.includes('language:draconic'));
  assert(sheet(switched).proficiencies.includes('skill:'+yes));
  assert(!sheet({...switched,classes:[{...r.classes[0],subclass:'Champion',subclass_source:'PHB'}]})
   .proficiencies.includes('skill:'+yes));
 }
});
test('Path of the Giant replaces a redundant known Giant with a language choice',()=>{
 const r=ch('Barbarian',3,'Giant','BGG');
 own(r,'giant','Giant Power');
 const withGiant={...r,species:'Human',species_source:'PHB',proficiency_choices:[
  {kind:'language',key:'giant',origin_id:'race|phb|human',origin_name:'Human'}]};
 const owner=trait(withGiant,'Giant Power');
 const p=choices(withGiant).find(x=>x.origin_id===owner.origin_id);
 assert(p&&!p.options.includes('giant')&&p.options.includes('sylvan'));
 own({...withGiant,...savePendingChoice(withGiant,p,['sylvan'])},'sylvan','Giant Power');
});
test('optional Deft Explorer does not silently give every ranger two languages',()=>{
 const r=ch('Ranger',1),f=trait(r,'Deft Explorer');
 assert(f);
 assert(!choices(r).some(x=>x.origin_id===f.origin_id));
 const enabled={...r,origin_enabled:{[f.origin_id]:true}};
 const p=choices(enabled).find(x=>x.origin_id===f.origin_id);
 assert(p&&p.count===2);
 const chosen={...enabled,...savePendingChoice(enabled,p,['sylvan','draconic'])};
 own(chosen,'sylvan','Deft Explorer');
 assert(!sheet({...chosen,origin_enabled:{[f.origin_id]:false}})
  .proficiencies.includes('language:sylvan'));
});
test('Mastermind generic language choices exclude Druidic and Thieves Cant',()=>{
 const r=ch('Rogue',3,'Mastermind','XGE'),f=trait(r,'Master of Intrigue');
 const p=choices(r).find(x=>x.origin_id===f.origin_id&&x.proficiency_kind==='language');
 assert(p&&p.count===2);
 assert(!p.options.includes('druidic')&&!p.options.includes("thieves' cant"));
});
