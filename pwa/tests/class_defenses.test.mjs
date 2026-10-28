import test from 'node:test';
import assert from 'node:assert/strict';
import {classDefenseEntries,classDefenseChoices,CLASS_DEFENSE_RULES} from '../class_defenses.js';
import {calculateSheet} from '../sheet_rules.js';
import {characterDefenseSummary} from '../defense_summary.js';
import {traitBenefitGroups} from '../trait_benefits.js';
import {pendingCharacterChoices,savePendingChoice} from '../pending_choices.js';

const abilities={str:10,dex:10,con:10,int:10,wis:10,cha:10};
const feature=(name,owner,source,level,subclass='',subsource='')=>({
 id:'typed:'+name.toLowerCase().replaceAll(' ','-'),name,
 class_name:owner,class_source:source,subclass_name:subclass||undefined,
 subclass_source:subsource||undefined,level
});
const char=(owner,source,level,subclass='',subsource='',entries=[])=>({
 kind:'character',rules_version:'2014',class:owner,class_source:source,
 subclass,subclass_source:subsource,level,abilities,inventory:[],
 classes:[{name:owner,source,level,subclass,subclass_source:subsource}],
 _features:entries
});
const sheet=r=>calculateSheet(r,{
 classFeatures:{class_features:r._features.filter(f=>!f.subclass_name),
  subclass_features:r._features.filter(f=>f.subclass_name)},originDetails:{}
});
const automatic=r=>sheet(r).damage_defense_entries.filter(d=>d.automatic);
const values=r=>automatic(r).map(d=>d.rank+':'+d.key).sort();

test('Chemical Mastery belongs only to a TCE Alchemist at artificer level 15',()=>{
 const original=char('Artificer','TCE',14,'Alchemist','TCE',[
  feature('Chemical Mastery','Artificer','TCE',15,'Alchemist','TCE')
 ]);
 assert.deepEqual(values(original),[]);
 const upgraded={...original,level:15,classes:[{...original.classes[0],level:15}]};
 assert.deepEqual(values(upgraded),['1:acid','1:poison','3:poisoned']);
 const result=sheet(upgraded);
 const trait=result.features.find(f=>f.name==='Chemical Mastery');
 assert(trait);
 assert(automatic(upgraded).every(d=>d.origin_id===trait.origin_id));
 const benefit=traitBenefitGroups({
  name:trait.name,feature_origin:trait.origin_id,origin_key:trait.origin_key,
  category:'classi',rank:2
 },upgraded,result).find(group=>group.type==='defenses');
 assert.deepEqual(benefit?.items.map(i=>i.value),['Acido','Veleno','Avvelenato']);
 const summary=characterDefenseSummary(upgraded,result);
 assert.equal(summary.count,3);
 assert.deepEqual(values({...upgraded,rules_version:'2024'}),[]);
 assert.deepEqual(values({...upgraded,classes:[{...upgraded.classes[0],subclass:'Artillerist'}]}),[]);
 assert.deepEqual(values({...upgraded,classes:[{...upgraded.classes[0],source:'EFA'}]}),[]);
});

test('defenses disappear when the owning trait, subclass, or origin is disabled',()=>{
 const base=char('Artificer','TCE',15,'Alchemist','TCE',[
  feature('Chemical Mastery','Artificer','TCE',15,'Alchemist','TCE')
 ]);
 const owned=sheet(base).features.find(f=>f.name==='Chemical Mastery');
 assert(owned);
 assert.deepEqual(values({...base,origin_enabled:{[owned.origin_id]:false}}),[]);
 assert.deepEqual(values({...base,origin_enabled:{[owned.origin_key]:false}}),[]);
 assert.deepEqual(values({...base,origin_enabled:{'class|tce|artificer':false}}),[]);
 assert.deepEqual(values({...base,trait_enabled:{[owned.key]:false}}),[]);
 assert.deepEqual(values({...base,trait_benefit_removed:{
  [owned.key]:['defense:class:'+owned.origin_id+':1:acid']
 }}),['1:poison','3:poisoned']);
});

test('multiclass levels do not unlock features from other classes',()=>{
 const base=char('Artificer','TCE',14,'Alchemist','TCE',[
  feature('Chemical Mastery','Artificer','TCE',15,'Alchemist','TCE')
 ]);
 const multi={...base,level:20,classes:[
  {...base.classes[0],level:14},
  {name:'Wizard',source:'PHB',level:6}
 ]};
 assert.deepEqual(values(multi),[]);
});

test('all curated grants use the existing defense categories and unique feature owners',()=>{
 assert(CLASS_DEFENSE_RULES.length>=15);
 for(const r of CLASS_DEFENSE_RULES.filter(rule=>!rule.choice)){
  assert(r.owner&&r.feature&&r.entries.length);
  assert(r.entries.every(e=>[-1,1,2,3].includes(e.rank)&&e.key));
  const label=r.subclass||'';
  const source=r.class_source||'PHB';
  const subsource=r.subclass_source||'';
  const record=char(r.owner,source,20,label,subsource,[
   feature(r.feature,r.owner,source,20,label,subsource)
  ]);
  if(r.active)record.active_class_features={[r.active]:{name:r.active}};
  const grants=automatic(record);
  assert.equal(grants.length,r.entries.length,r.owner+' / '+r.feature);
  assert.equal(new Set(grants.map(g=>g.benefit_id)).size,grants.length);
 }
});

test('aura and rage conditional immunity is never projected while unavailable',()=>{
 const aura=char('Paladin','PHB',10,'','',[
  feature('Aura of Courage','Paladin','PHB',10)
 ]);
 assert.deepEqual(values(aura),['3:frightened']);
 assert.deepEqual(values({...aura,conditions:['unconscious']}),[]);
 assert.deepEqual(values({...aura,conditions:[{name:'incapacitated'}]}),[]);
 const rage=char('Barbarian','PHB',6,'Path of the Berserker','PHB',[
  feature('Mindless Rage','Barbarian','PHB',6,'Path of the Berserker','PHB')
 ]);
 assert.deepEqual(values(rage),[]);
 assert.deepEqual(values({...rage,active_class_features:{rage:{name:'Rage'}}}),
  ['3:charmed','3:frightened']);
});

test('unrelated named traits and 2024 classes never inherit 2014 defense rules',()=>{
 const original=char('Wizard','PHB',14,'School of Necromancy','PHB',[
  feature('Inured to Undeath','Wizard','PHB',10,'School of Necromancy','PHB')
 ]);
 assert.deepEqual(values(original),['1:necrotic']);
 const wrong={...original,class:'Cleric',classes:[{name:'Cleric',source:'PHB',level:14}]};
 assert.deepEqual(values(wrong),[]);
 assert.deepEqual(classDefenseEntries({rules_version:'2024'},[{
  name:'Chemical Mastery',origin_key:'class|tce|artificer|subclass|alchemist|tce'
 }]),[]);
});

test('Fiendish Resilience choices grant only the selected type to the actual trait',()=>{
 const base=char('Warlock','PHB',10,'The Fiend','PHB',[
  feature('Fiendish Resilience','Warlock','PHB',10,'The Fiend','PHB')
 ]);
 const calculated=sheet(base);
 const choice=classDefenseChoices(base,calculated.features)[0];
 assert(choice);
 assert.equal(choice.remaining,1);
 assert.deepEqual(values(base),[]);
 assert.equal(choice.options.length,13);
 const sameFromPopup=pendingCharacterChoices(base,calculated,{})
  .find(row=>row.id===choice.id);
 assert(sameFromPopup);
 const updated={...base,...savePendingChoice(base,choice,['fire'])};
 const result=sheet(updated);
 assert.deepEqual(values(updated),['1:fire']);
 assert.match(automatic(updated)[0].condition_label,/armi magiche/i);
 const own=result.features.find(f=>f.name==='Fiendish Resilience');
 const other={...updated,classes:[{name:'Warlock',source:'PHB',level:10,
  subclass:'The Great Old One',subclass_source:'PHB'}]};
 assert.deepEqual(values(other),[]);
 assert.equal(automatic(updated)[0].origin_id,own.origin_id);
 assert.deepEqual(values({...updated,origin_enabled:{[own.origin_id]:false}}),[]);
 assert.deepEqual(values({...updated,origin_defense_choices:{[own.origin_id]:'invalid'}}),[]);
});

test('Storm Herald, Genie and Bear Totem selections remain exclusive to their origins',()=>{
 for(const [owner,level,subclass,subsource,name,choice,expected] of [
  ['Barbarian',6,'Path of the Storm Herald','XGE','Storm Soul','lightning',['1:lightning']],
  ['Warlock',6,'The Genie','TCE','Elemental Gift','thunder',['1:thunder']],
  ['Barbarian',3,'Path of the Totem Warrior','PHB','Totem Spirit','bear',null]
 ]){
  const base=char(owner,'PHB',level,subclass,subsource,[
   feature(name,owner,'PHB',level,subclass,subsource)
  ]);
  const pending=classDefenseChoices(base,sheet(base).features);
  assert.equal(pending.length,1,subclass);
  const chosen={...base,...savePendingChoice(base,pending[0],[choice])};
  if(choice==='bear')chosen.active_class_features={rage:{name:'Rage'}};
  const entries=values(chosen);
  if(expected)assert.deepEqual(entries,expected);
  else{
   assert.equal(entries.length,12);
   assert(!entries.includes('1:psychic'));
  }
  const disabled={...chosen,origin_enabled:{[pending[0].origin_id]:false}};
  assert.deepEqual(values(disabled),[]);
  const cleared={...chosen,...savePendingChoice(chosen,pending[0],[])};
  assert.deepEqual(values(cleared),[]);
 }
});

test('Bear Totem cannot grant resistance before raging or when another animal is chosen',()=>{
 const base=char('Barbarian','PHB',3,'Path of the Totem Warrior','PHB',[
  feature('Totem Spirit','Barbarian','PHB',3,'Path of the Totem Warrior','PHB')
 ]);
 const choice=classDefenseChoices(base,sheet(base).features)[0];
 const bear={...base,...savePendingChoice(base,choice,['bear'])};
 assert.deepEqual(values(bear),[]);
 assert.equal(values({...bear,active_class_features:{rage:{name:'Rage'}}}).length,12);
 const eagle={...bear,...savePendingChoice(bear,choice,['eagle']),
  active_class_features:{rage:{name:'Rage'}}};
 assert.deepEqual(values(eagle),[]);
});
