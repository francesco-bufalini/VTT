import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {featureActionEntries,modifyFeatureTrackers,optionalRecoveryPatch} from '../feature_mechanics.js';
import {calculateSheet} from '../sheet_rules.js';
import {actionEntries} from '../action_economy.js';
import {recoveryPatch} from '../native_sheet.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const rules=read('../../vtt/data/feature_timing_recovery_rules.json');
const mechanics=read('../catalog/class_mechanics.json');
const catalogs={classMechanics:mechanics,abilityGrants:read('../catalog/ability_grants.json'),
 proficiencyGrants:read('../catalog/proficiency_grants.json'),featureRules:rules};
const creature=(name,edition,level,subclass='')=>({
 kind:'character',rules_version:edition,class:name,class_source:edition==='2024'?'XPHB':'PHB',
 level,subclass,abilities:{str:10,dex:10,con:10,int:10,wis:16,cha:16}
});
test('typed supplement tracks feature, class source, level and subclass without prose heuristics',()=>{
 assert.equal(rules.version,1);
 assert(rules.actions.length>=12);
 assert(rules.recoveries.length>=17);
 const basic=creature('Druid','2014',2);
 const moon={...basic,subclass:'Circle of the Moon'};
 const other={...basic,subclass:'Circle of the Land'};
 const newDruid=creature('Druid','2024',2);
 const activation=(row)=>featureActionEntries(row,calculateSheet(row,catalogs).trackers,rules).filter(a=>a.rule_id.includes('wild_shape'));
 assert.equal(activation(basic)[0].time,'action');
 assert.equal(activation(other)[0].time,'action');
 assert.equal(activation(moon)[0].time,'bonus');
 assert.equal(activation(newDruid)[0].time,'bonus');
 assert.equal(activation({...basic,level:1}).length,0);
 const out=calculateSheet(moon,catalogs),choices=actionEntries(moon,out);
 assert(choices.some(a=>a.name==='Forma selvatica'&&a.time==='bonus'&&a.tracker==='Wild Shape'));
 assert(!choices.some(a=>a.name==='Forma selvatica'&&a.time==='action'));
 assert(featureActionEntries(creature('Rogue','2014',2),[],rules).filter(a=>a.time==='bonus').length>=3);
 assert.equal(featureActionEntries(creature('Rogue','2014',2),[],rules).some(a=>a.name.includes('Mani veloci')),false);
 assert(featureActionEntries(creature('Rogue','2024',3,'Thief'),[],rules).some(a=>a.name.includes('Mani veloci')));
 assert(!featureActionEntries(creature('Ranger','2014',13),[],rules).some(a=>a.name.includes('Svanire')));
 assert(featureActionEntries(creature('Ranger','2014',14),[],rules).some(a=>a.name.includes('Svanire')));
});

test('2024 short rest recovers one use, long rest recovers all, without modifying counters in stored sheet',()=>{
 for(const [name,level,res] of [['Barbarian',3,'Rages'],['Cleric',4,'Channel Divinity'],
  ['Druid',5,'Wild Shape'],['Fighter',3,'Second Wind'],['Paladin',5,'Channel Divinity']]){
  const row=creature(name,'2024',level),result=calculateSheet(row,catalogs);
  const tracker=result.trackers.find(t=>t.name===res);
  assert(tracker, name+' '+res+' missing');
  assert.equal(tracker.recharge,'long_rest',name+' must not fully recover on short rest');
  assert(tracker.partial_recoveries?.some(x=>x.mode==='partial'&&x.amount===1));
  const spent={...row,resource_tracker_spent:{[tracker.id]:Math.min(tracker.max,3)}};
  const newState=recoveryPatch(spent,'short_rest',result.trackers);
  assert.equal(newState.resource_tracker_spent[tracker.id]||0,Math.min(tracker.max,3)-1);
  const long=recoveryPatch(spent,'long_rest',result.trackers);
  assert.equal(long.resource_tracker_spent[tracker.id],undefined);
 }
});

test('Font of Inspiration upgrades full Bardic Inspiration reset only at level five',()=>{
 for(const edition of ['2014','2024']){
  const four=calculateSheet(creature('Bard',edition,4),catalogs).trackers.find(t=>t.name==='Bardic Inspiration');
  const five=calculateSheet(creature('Bard',edition,5),catalogs).trackers.find(t=>t.name==='Bardic Inspiration');
  assert(four&&five);
  assert.equal(four.recharge,'long_rest');assert.equal(five.recharge,'short_rest');
 }
});

test('2014 Sorcerous Restoration regains only four spent points, from level twenty',()=>{
 const high=creature('Sorcerer','2014',20);
 const tracker=calculateSheet(high,catalogs).trackers.find(x=>x.name==='Sorcery Points');
 assert(tracker.partial_recoveries?.some(x=>x.amount===4));
 const state={...high,resource_tracker_spent:{[tracker.id]:12}};
 assert.equal(recoveryPatch(state,'short_rest',calculateSheet(high,catalogs).trackers).resource_tracker_spent[tracker.id],8);
 assert(!calculateSheet(creature('Sorcerer','2014',19),catalogs).trackers.find(x=>x.name==='Sorcery Points').partial_recoveries);
});

test('2024 Sorcerous Restoration is offered after rest and consumed once per long rest',()=>{
 const sorc=creature('Sorcerer','2024',7);
 const tracker=calculateSheet(sorc,catalogs).trackers.find(x=>x.name==='Sorcery Points');
 const id=tracker.partial_recoveries.find(x=>x.mode==='optional_partial')?.id;
 assert(id);
 const c={...sorc,resource_tracker_spent:{[tracker.id]:6}};
 const afterRest=recoveryPatch(c,'short_rest',[tracker]);
 assert.equal(afterRest.resource_tracker_spent[tracker.id],6,'optional recovery must not be silently applied');
 assert.equal(afterRest.resource_recovery_ready[id],true);
 const first=optionalRecoveryPatch({...c,...afterRest},id,[tracker]);
 assert.equal(first.resource_tracker_spent[tracker.id],3,'half of sorcerer level, rounded down');
 assert.equal(first.resource_recovery_used[id],true);
 assert.equal(optionalRecoveryPatch({...c,...first},id,[tracker]),null);
 const another=recoveryPatch({...c,...first},'short_rest',[tracker]);
 assert.equal(another.resource_recovery_ready[id],undefined,'no second use after another short rest');
 const long=recoveryPatch({...c,...first},'long_rest',[tracker]);
 assert.deepEqual(long.resource_recovery_used,{});
 assert.deepEqual(long.resource_recovery_ready,{});
 assert.equal(long.resource_tracker_spent[tracker.id],undefined);
});

test('a multiclass member never inherits the primary class subclass',()=>{
 const rogue={kind:'character',rules_version:'2014',class:'Rogue',
  class_source:'PHB',subclass:'Thief',level:5,classes:[
   {name:'Rogue',source:'PHB',level:3,subclass:'Thief'},
   {name:'Druid',source:'PHB',level:2}
  ]};
 const actions=featureActionEntries(rogue,[],rules);
 assert(actions.some(row=>row.rule_id==='rogue_phb_use_object'));
 assert(actions.some(row=>row.rule_id==='druid_phb_wild_shape'&&row.time==='action'));
 assert(!actions.some(row=>row.rule_id==='druid_phb_wild_shape'&&row.time==='bonus'));
 const primaryLegacy={...rogue,class:'Druid',subclass:'Circle of the Moon',
  classes:[{name:'Druid',source:'PHB',level:2},{name:'Rogue',source:'PHB',level:3}]};
 const legacyActions=featureActionEntries(primaryLegacy,[],rules);
 assert(legacyActions.some(row=>row.rule_id==='druid_phb_wild_shape'&&row.time==='bonus'));
 assert(!legacyActions.some(row=>row.rule_id==='rogue_phb_use_object'));
});

test('disabled class and subclass feature origins cannot grant alternate actions',()=>{
 const base=creature('Druid','2014',2,'Circle of the Moon');
 const classOrigin='class|phb|druid';
 const combat={name:'Combat Wild Shape',origin_key:classOrigin+'|subclass|circle of the moon|phb',
   origin_id:'feature:'+classOrigin+'|subclass|circle of the moon|phb|combat_wild_shape',
   disabled:false};
 const plain={name:'Wild Shape',origin_key:classOrigin,
   origin_id:'feature:'+classOrigin+'|wild_shape',disabled:false};
 const selected=features=>featureActionEntries(base,[],rules,features);
 assert.equal(selected([plain,combat]).find(x=>x.rule_action_id==='wild_shape')?.time,'bonus');
 assert.equal(selected([plain,{...combat,disabled:true}]).find(x=>x.rule_action_id==='wild_shape')?.time,'action');
 assert.equal(selected([{...plain,disabled:true},{...combat,disabled:true}]).some(x=>x.rule_action_id==='wild_shape'),false);
 assert.equal(selected([plain,combat]).find(x=>x.rule_action_id==='wild_shape')?.origin_id,combat.origin_id);
 const classDisabled={...base,origin_enabled:{[classOrigin]:false}};
 assert(!featureActionEntries(classDisabled,[],rules,[plain,combat]).some(x=>x.rule_action_id==='wild_shape'));
});
