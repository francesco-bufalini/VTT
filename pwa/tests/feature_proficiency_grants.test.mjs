import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {fixedProficiencies,selectedSources} from '../structured_effects.js';
import {pendingCharacterChoices,savePendingChoice,choicesForTrait} from '../pending_choices.js';
import {traitBenefitGroups} from '../trait_benefits.js';
const read=name=>JSON.parse(readFileSync(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const catalogs={classMechanics:read('class_mechanics'),classFeatures:read('classes'),
 abilityGrants:read('ability_grants'),proficiencyGrants:read('proficiency_grants')};
const armorer=(level=3,source='TCE')=>({kind:'character',rules_version:source==='TCE'?'2014':'2024',
 level,classes:[{name:'Artificer',source,level,subclass:'Armorer',subclass_source:source}],
 abilities:{str:10,dex:14,con:14,int:16,wis:10,cha:10},inventory:[]});
const traitOf=c=>c.features.find(f=>f.name==='Tools of the Trade');
const featureChoices=(r,c=calculateSheet(r,catalogs))=>pendingCharacterChoices(r,c,catalogs)
 .filter(choice=>choice.origin_id===traitOf(c)?.origin_id);

test('unreprinted XGE training belongs to eight individual 2014 subclass traits',()=>{
 const legacy=(klass,subclass,level,source='PHB')=>({kind:'character',
  rules_version:source==='PHB'?'2014':'2024',class:klass,class_source:source,
  level,subclass,subclass_source:'XGE',
  classes:[{name:klass,source,level,subclass,subclass_source:'XGE'}],
  abilities:{str:10,dex:14,con:10,int:12,wis:14,cha:14},inventory:[]});
 const cases=[
  ['Bard','College of Swords',3,'Bonus Proficiencies',['armor:medium','weapon:scimitar']],
  ['Cleric','Forge Domain',1,'Bonus Proficiency',['armor:heavy',"tool:smith's tools"]],
  ['Druid','Circle of the Shepherd',2,'Speech of the Woods',['language:sylvan']],
  ['Monk','Way of the Drunken Master',3,'Bonus Proficiencies',['skill:performance',"tool:brewer's supplies"]],
  ['Rogue','Mastermind',3,'Master of Intrigue',['tool:disguise kit','tool:forgery kit']],
  ['Rogue','Scout',3,'Survivalist',['skill:nature','skill:survival','expertise:nature','expertise:survival']],
  ['Sorcerer','Storm Sorcery',1,'Wind Speaker',['language:primordial']],
  ['Warlock','The Hexblade',1,'Hex Warrior',['armor:medium','armor:shield','weapon:martial']]
 ];
 for(const [klass,subclass,level,name,keys] of cases){
  const r=legacy(klass,subclass,level),c=calculateSheet(r,catalogs);
  const trait=c.features.find(f=>f.name===name);
  assert(trait,`${klass}: ${name} must be an owned trait`);
  for(const key of keys){
   assert(c.proficiencies.includes(key),`${klass}: ${key}`);
   assert(c.proficiency_sources[key]?.some(row=>row.id===trait.origin_id),`${name} must grant ${key}`);
   const muted=calculateSheet({...r,origin_enabled:{[trait.origin_id]:false}},catalogs);
   assert(!muted.proficiency_sources[key]?.some(row=>row.id===trait.origin_id));
   const revised=calculateSheet(legacy(klass,subclass,level,'XPHB'),catalogs);
   assert(!revised.proficiency_sources[key]?.some(row=>row.id===trait.origin_id));
  }
  if(level>1){
   const below=legacy(klass,subclass,level-1);
   assert(!calculateSheet(below,catalogs).features.some(f=>f.name===name));
  }
 }
 const m=legacy('Rogue','Mastermind',3),c=calculateSheet(m,catalogs);
 const trait=c.features.find(f=>f.name==='Master of Intrigue');
 const choices=pendingCharacterChoices(m,c,catalogs).filter(choice=>choice.origin_id===trait.origin_id);
 assert(choices.some(choice=>choice.proficiency_kind==='tool'&&choice.count===1&&choice.options.includes('dice set')));
 assert(choices.some(choice=>choice.proficiency_kind==='language'&&choice.count===2));
});

test('2014 Kensei offers exactly one tool from its own Path trait',()=>{
 const sheet=(level,source='PHB',subclass='Way of the Kensei')=>({kind:'character',
  rules_version:source==='PHB'?'2014':'2024',class:'Monk',class_source:source,
  level,subclass,subclass_source:'XGE',classes:[{name:'Monk',source,level,subclass,subclass_source:'XGE'}],
  abilities:{str:10,dex:16,con:10,int:10,wis:14,cha:10},inventory:[]});
 const r=sheet(3),c=calculateSheet(r,catalogs);
 const trait=c.features.find(f=>f.name==='Path of the Kensei');
 assert(trait?.origin_id.includes('|subclass|'));
 const choices=pendingCharacterChoices(r,c,catalogs).filter(choice=>choice.origin_id===trait.origin_id);
 assert.equal(choices.length,1);
 assert.equal(choices[0].proficiency_kind,'tool');
 assert.equal(choices[0].remaining,1);
 assert.deepEqual(choices[0].options,["calligrapher's supplies","painter's supplies"]);
 assert(!c.proficiencies.includes("tool:calligrapher's supplies"));
 assert(!c.proficiencies.includes("tool:painter's supplies"));
 const picked={...r,...savePendingChoice(r,choices[0],["painter's supplies"])};
 const chosen=calculateSheet(picked,catalogs);
 assert(chosen.proficiency_sources["tool:painter's supplies"]?.some(row=>row.id===trait.origin_id));
 assert(!calculateSheet({...picked,origin_enabled:{[trait.origin_id]:false}},catalogs).proficiencies.includes("tool:painter's supplies"));
 assert(!calculateSheet(sheet(2),catalogs).features.some(f=>f.name==='Path of the Kensei'));
 assert(!calculateSheet(sheet(3,'PHB','Way of the Drunken Master'),catalogs).features.some(f=>f.name==='Path of the Kensei'));
 assert(!calculateSheet(sheet(3,'XPHB'),catalogs).proficiency_sources["tool:painter's supplies"]?.some(row=>row.id===trait.origin_id));
});

test('a subclass feature can grant proficiency with a non-catalogue homebrew weapon',()=>{
 const weaponName='Clockwork Emitter';
 const record={...armorer(3),inventory:[{id:'custom-emitter',name:weaponName,
  type:'R',custom_item_type:'weapon',weapon_category:'homebrew',damage:'1d8',
  damage_type:'force',range:'30/120',quantity:1,equipped_slots:['main']}]};
 const original=calculateSheet(record,catalogs);
 const ordinary=original.attacks.find(attack=>attack.id==='item:custom-emitter');
 assert(ordinary,'The custom weapon should produce a normal attack');
 assert.equal(ordinary.proficient,false,
  'No catalog weapon type or class proficiency makes this weapon trained');
 const index=structuredClone(catalogs.proficiencyGrants);
 const feature=index.subclassFeature.find(row=>row.name==='Lightning Launcher'&&
   row.class_source==='TCE');
 assert(feature,'Source-bound feature weapon training is included in the index');
 feature.weaponProficiencies=[...feature.weaponProficiencies,weaponName];
 const trained=calculateSheet(record,{...catalogs,proficiencyGrants:index});
 const key='weapon:clockwork emitter',attack=trained.attacks.find(row=>row.id==='item:custom-emitter');
 assert(trained.proficiencies.includes(key),'Multiword homebrew weapon names work as data grants');
 assert(trained.proficiency_sources[key]?.some(row=>row.name.includes('Lightning Launcher')),
  'The added training retains its exact granting feature');
 assert.equal(attack?.proficient,true);
 assert.equal(attack.hit,ordinary.hit+trained.values.proficiency,
  'The custom weapon gains exactly the normal proficiency bonus');
 const without={...record,origin_enabled:{[trained.proficiency_sources[key][0].id]:false}};
 assert.equal(calculateSheet(without,{...catalogs,proficiencyGrants:index})
  .attacks.find(row=>row.id==='item:custom-emitter')?.proficient,false,
  'Disabling the granting source withdraws the custom weapon training');
});
test('Armorer grants heavy armor and smith tools at level 3 on its actual trait in both editions',()=>{
 for(const source of ['TCE','EFA']){
  const before=calculateSheet(armorer(2,source),catalogs);
  assert(!before.proficiencies.includes('armor:heavy'));
  assert(!before.proficiencies.includes("tool:smith's tools"));
  const r=armorer(3,source),c=calculateSheet(r,catalogs),f=traitOf(c);
  for(const key of ['armor:heavy',"tool:smith's tools"]){
   assert(c.proficiencies.includes(key));
   assert.equal(c.proficiency_sources[key][0].id,f.origin_id);
  }
  const trait={key:f.key,feature_origin:f.origin_id,origin_key:f.origin_key};
  const groups=traitBenefitGroups(trait,r,c);
  assert.equal(groups.find(g=>g.type==='proficiency')?.items.length,2);
  assert.equal(featureChoices(r,c).length,0);
  assert(fixedProficiencies(r,catalogs.proficiencyGrants).has('armor:heavy'),'offline compact catalog');
  const {classFeatures,...withoutDescriptions}=catalogs;
  assert(calculateSheet(r,withoutDescriptions).proficiencies.includes('armor:heavy'),'metadata-only class features');
 }
});

test('class, subclass, trait and benefit switches suppress only the corresponding grants',()=>{
 const r=armorer(),c=calculateSheet(r,catalogs),f=traitOf(c);
 for(const id of [f.origin_id,f.origin_key,'class|tce|artificer']){
  const next=calculateSheet({...r,origin_enabled:{[id]:false}},catalogs);
  assert(!next.proficiencies.includes('armor:heavy'));
 }
 assert(!calculateSheet({...r,trait_enabled:{[f.key]:false}},catalogs).proficiencies.includes('armor:heavy'));
 const removed='proficiency:'+f.origin_id+':armor:heavy';
 const next=calculateSheet({...r,trait_benefit_removed:{[f.key]:[removed]}},catalogs);
 assert(!next.proficiencies.includes('armor:heavy'));
 assert(next.proficiencies.includes("tool:smith's tools"));
 assert(calculateSheet({...r,classes:[{...r.classes[0],subclass:'Alchemist'}]},catalogs)
  .proficiencies.includes("tool:alchemist's supplies"));
 assert(!calculateSheet({...r,classes:[{...r.classes[0],subclass:'Alchemist'}]},catalogs)
  .proficiencies.includes('armor:heavy'));
});

test('duplicate smith tools open one artisan choice, preserve it, and withdraw it when no longer eligible',()=>{
 const r={...armorer(),proficiency_choices:[{kind:'tool',key:"smith's tools",origin_id:'class|tce|artificer'}]};
 const c=calculateSheet(r,catalogs),f=traitOf(c),[choice]=featureChoices(r,c);
 assert.equal(choice.remaining,1);
 assert.equal(choice.count,1);
 assert(!choice.options.includes("smith's tools"));
 assert(!choice.options.includes("tinker's tools"));
 assert(choice.options.includes("carpenter's tools"));
 assert.throws(()=>savePendingChoice(r,choice,["__custom__:smith's tools"]),/Selezione/);
 assert.throws(()=>savePendingChoice(r,choice,["__custom__:tinker's tools"]),/Selezione/);
 assert.equal(choicesForTrait({feature_origin:f.origin_id},r,[choice]).length,1);
 const chosen={...r,...savePendingChoice(r,choice,["carpenter's tools"])};
 assert.equal(featureChoices(chosen)[0].remaining,0);
 assert(calculateSheet(chosen,catalogs).proficiencies.includes("tool:carpenter's tools"));
 const withdrawn={...chosen,proficiency_choices:chosen.proficiency_choices.filter(row=>row.origin_id===f.origin_id)};
 assert.equal(featureChoices(withdrawn).length,0);
 assert(!calculateSheet(withdrawn,catalogs).proficiencies.includes("tool:carpenter's tools"));
 assert(calculateSheet(withdrawn,catalogs).proficiencies.includes("tool:smith's tools"));
 const changed={...chosen,classes:[{...r.classes[0],subclass:'Alchemist'}]};
 assert(!calculateSheet(changed,catalogs).proficiencies.includes("tool:carpenter's tools"));
 assert(!calculateSheet({...chosen,origin_enabled:{[f.origin_id]:false}},catalogs)
  .proficiencies.includes("tool:carpenter's tools"));
 assert.equal(featureChoices({...chosen,origin_enabled:{'class|tce|artificer':false}}).length,0);
});

test('disabled or removed prior grants do not trigger replacement, nor does the trait own saved automatic copy',()=>{
 const r=armorer(),f=traitOf(calculateSheet(r,catalogs));
 for(const saved of [
  {kind:'tool',key:"smith's tools",origin_id:'class|tce|artificer',disabled:true},
  {kind:'tool',key:"smith's tools",origin_id:f.origin_id,automatic:true},
  {kind:'tool',key:"smith's tools",origin_id:'class|phb|fighter'}
 ])assert.equal(featureChoices({...r,proficiency_choices:[saved]}).length,0);
 const previous={kind:'tool',key:"smith's tools",origin_id:'class|tce|artificer'};
 const removed='proficiency:class|tce|artificer:tool:smith\'s tools';
 assert.equal(featureChoices({...r,proficiency_choices:[previous],trait_benefit_removed:{starting:[removed]}}).length,0);
});

test('multiclass levels and source identity determine feature eligibility',()=>{
 const r=armorer(2);r.level=8;r.classes.unshift({name:'Fighter',source:'PHB',level:6});
 assert(!calculateSheet(r,catalogs).proficiencies.includes("tool:smith's tools"));
 r.classes[1].level=3;
 const c=calculateSheet(r,catalogs);
 assert(c.proficiencies.includes("tool:smith's tools"));
 const mismatch={...armorer(),classes:[{...armorer().classes[0],subclass_source:'EFA'}]};
 assert(!calculateSheet(mismatch,catalogs).proficiencies.includes('armor:heavy'));
});

test('class feature grants keep their existing canonical trait identities',()=>{
 for(const [name,key] of [['Druid','druidic'],['Rogue',"thieves' cant"]]){
  const r={...armorer(1),classes:[{name,source:'PHB',level:1}]},c=calculateSheet(r,catalogs);
  assert(c.proficiencies.includes('language:'+key));
  const f=c.features.find(f=>f.name===(name==='Druid'?'Druidic':"Thieves' Cant"));
  assert.equal(c.proficiency_sources['language:'+key][0].id,f.origin_id);
  assert(!calculateSheet({...r,origin_enabled:{[f.origin_id]:false}},catalogs).proficiencies.includes('language:'+key));
 }
});

test('upstream typed feature choices use the ordinary pending-choice flow without a prose rule',()=>{
 const row={id:'fixture:trained',name:'Training',class_name:'Fighter',class_source:'PHB',source:'PHB',level:4,
  skillProficiencies:[{choose:{from:['arcana','history'],count:1}}]};
 const index={classFeature:[row]},r={kind:'character',classes:[{name:'Fighter',source:'PHB',level:4}]};
 const choice=pendingCharacterChoices(r,{}, {proficiencyGrants:index})[0];
 assert.deepEqual(choice.options,['arcana','history']);
 assert.equal(choice.remaining,1);
 const selected={...r,...savePendingChoice(r,choice,['arcana'])};
 assert(fixedProficiencies(selected,index).has('skill:arcana'));
 assert.equal(selectedSources({...r,classes:[{...r.classes[0],level:3}]},index).length,0);
});
