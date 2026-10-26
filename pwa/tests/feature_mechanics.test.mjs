import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {featureActionEntries,modifyFeatureTrackers,optionalRecoveryPatch} from '../feature_mechanics.js';
import {calculateSheet} from '../sheet_rules.js';
import {actionEntries} from '../action_economy.js';
import {recoveryPatch} from '../native_sheet.js';
import {collectStructuredFeatures} from '../structured_effects.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const rules=read('../../vtt/data/feature_timing_recovery_rules.json');
const mechanics=read('../catalog/class_mechanics.json');
const catalogs={classMechanics:mechanics,abilityGrants:read('../catalog/ability_grants.json'),
 proficiencyGrants:read('../catalog/proficiency_grants.json'),featureRules:rules,
 classFeatures:read('../catalog/classes.json')};
const actionsFor=(record,trackers=[])=>featureActionEntries(record,trackers,rules,
 collectStructuredFeatures(record,catalogs));
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
 const activation=(row)=>actionsFor(row,calculateSheet(row,catalogs).trackers).filter(a=>a.rule_id.includes('wild_shape'));
 assert.equal(activation(basic)[0].time,'action');
 assert.equal(activation(other)[0].time,'action');
 assert.equal(activation(moon)[0].time,'bonus');
 assert.equal(activation(newDruid)[0].time,'bonus');
 assert.equal(activation({...basic,level:1}).length,0);
 const out=calculateSheet(moon,catalogs),choices=actionEntries(moon,out);
 assert(choices.some(a=>a.name==='Forma selvatica'&&a.time==='bonus'&&a.tracker==='Wild Shape'));
 assert(!choices.some(a=>a.name==='Forma selvatica'&&a.time==='action'));
 assert(actionsFor(creature('Rogue','2014',2)).filter(a=>a.time==='bonus').length>=3);
 assert.equal(actionsFor(creature('Rogue','2014',2)).some(a=>a.name.includes('Mani veloci')),false);
 assert(actionsFor(creature('Rogue','2024',3,'Thief')).some(a=>a.name.includes('Mani veloci')));
 assert(!actionsFor(creature('Ranger','2014',13)).some(a=>a.name.includes('Svanire')));
 assert(actionsFor(creature('Ranger','2014',14)).some(a=>a.name.includes('Svanire')));
});

test('unreprinted 2014 Cleric domains expose only their own trait actions and shared counters',()=>{
 const nature=creature('Cleric','2014',17,'Nature');
 const tempest=creature('Cleric','2014',17,'Tempest');
 const selected=record=>actionsFor(record,calculateSheet(record,catalogs).trackers)
  .filter(row=>row.rule_id.startsWith('cleric_phb_nature_')||row.rule_id.startsWith('cleric_phb_tempest_'));
 const n=selected(nature),t=selected(tempest);
 assert.deepEqual(n.map(row=>row.time),['action','reaction','bonus']);
 assert.deepEqual(t.map(row=>row.time),['reaction','free']);
 assert(n.every(row=>row.origin_id.includes('subclass')));
 assert(t.every(row=>row.origin_id.includes('subclass')));
 assert.equal(n.find(row=>row.rule_id.endsWith('charm_animals_and_plants')).tracker,'Channel Divinity');
 assert.equal(t.find(row=>row.rule_id.endsWith('destructive_wrath')).tracker,'Channel Divinity');
 assert.equal(t.find(row=>row.rule_id.endsWith('wrath_of_the_storm')).tracker,'Wrath of the Storm');
 assert.equal(selected(creature('Cleric','2014',2)).length,0);
 assert.equal(selected(creature('Cleric','2024',17,'Tempest')).length,0);
 assert.deepEqual(selected(creature('Cleric','2014',2,'Nature')).map(row=>row.rule_id),
  ['cleric_phb_nature_charm_animals_and_plants']);
});

test('SCAG Undying counters stay attached to the selected 2014 Warlock patron',()=>{
 const undying=creature('Warlock','2014',14,'The Undying');
 const own=calculateSheet(undying,catalogs).trackers;
 const defy=own.find(row=>row.name==='Defy Death');
 const life=own.find(row=>row.name==='Indestructible Life');
 assert.equal(defy?.max,1);
 assert.equal(defy?.recharge,'long_rest');
 assert.equal(life?.max,1);
 assert.equal(life?.recharge,'short_rest');
 assert(defy.origin_id.includes('subclass'));
 assert(life.origin_id.includes('subclass'));
 const action=actionsFor(undying,own).find(row=>row.rule_id==='warlock_phb_undying_indestructible_life');
 assert.equal(action?.time,'bonus');
 assert.equal(action?.tracker_id,life.id);
 assert.equal(actionsFor(undying,own).some(row=>row.feature==='Defy Death'),false);
 assert.equal(calculateSheet(creature('Warlock','2014',5,'The Undying'),catalogs)
  .trackers.some(row=>row.name==='Defy Death'),false);
 assert.equal(calculateSheet(creature('Warlock','2014',14,'The Fiend'),catalogs)
  .trackers.some(row=>['Defy Death','Indestructible Life'].includes(row.name)),false);
 assert.equal(calculateSheet(creature('Warlock','2024',14,'The Undying'),catalogs)
  .trackers.some(row=>['Defy Death','Indestructible Life'].includes(row.name)),false);
});

test('non-reprinted SCAG Monk and Paladin actions require their own 2014 subclass traits',()=>{
 const longDeath=creature('Monk','2014',6,'Long Death');
 const hour=actionsFor(longDeath,calculateSheet(longDeath,catalogs).trackers)
  .find(row=>row.rule_id==='monk_phb_long_death_hour_of_reaping');
 assert.equal(hour?.time,'action');
 assert.equal(hour?.tracker_id,'');
 assert.equal(actionsFor(creature('Monk','2014',6,'Open Hand')).some(row=>row.rule_id===hour.rule_id),false);
 const crown=creature('Paladin','2014',20,'Oath of the Crown');
 const trackers=calculateSheet(crown,catalogs).trackers;
 const champion=trackers.find(row=>row.name==='Exalted Champion');
 assert.equal(champion?.max,1);
 assert.equal(champion?.recharge,'long_rest');
 assert(champion.origin_id.includes('subclass'));
 const actions=actionsFor(crown,trackers).filter(row=>row.rule_id.startsWith('paladin_phb_crown_'));
 assert.deepEqual(actions.map(row=>row.time),['bonus','bonus','reaction','action']);
 assert(actions.slice(0,2).every(row=>row.tracker==='Channel Divinity'&&row.tracker_id));
 assert.equal(actions[3].tracker_id,champion.id);
 assert.equal(actionsFor(creature('Paladin','2014',3,'Oath of the Crown'),calculateSheet(creature('Paladin','2014',3,'Oath of the Crown'),catalogs).trackers)
  .filter(row=>row.rule_id.startsWith('paladin_phb_crown_')).length,2);
 assert.equal(calculateSheet(creature('Paladin','2014',20,'Oath of Devotion'),catalogs).trackers
  .some(row=>row.name==='Exalted Champion'),false);
});

test('XGE Samurai and Cavalier counters use their own trait and limit only the special attack',()=>{
 const samurai=creature('Fighter','2014',18,'Samurai');
 const samuraiTrackers=calculateSheet(samurai,catalogs).trackers;
 const fighting=samuraiTrackers.find(row=>row.name==='Fighting Spirit');
 const strength=samuraiTrackers.find(row=>row.name==='Strength before Death');
 assert.equal(fighting?.max,3);
 assert.equal(strength?.max,1);
 assert([fighting,strength].every(row=>row.recharge==='long_rest'&&row.origin_id.includes('subclass')));
 const samuraiActions=actionsFor(samurai,samuraiTrackers).filter(row=>row.rule_id.startsWith('fighter_phb_samurai_'));
 assert.deepEqual(samuraiActions.map(row=>row.time),['bonus','reaction']);
 assert.equal(samuraiActions[0].tracker_id,fighting.id);
 const cavalier={...creature('Fighter','2014',7,'Cavalier'),abilities:{str:16,dex:10,con:16,int:10,wis:10,cha:10}};
 const cavalierTrackers=calculateSheet(cavalier,catalogs).trackers;
 const mark=cavalierTrackers.find(row=>row.name==='Unwavering Mark (Special Attack)');
 const ward=cavalierTrackers.find(row=>row.name==='Warding Maneuver');
 assert.equal(mark?.max,3);
 assert.equal(mark?.id,'class:fighter:phb:unwavering_mark_special_attack');
 assert.equal(mark?.origin_name,'Tratto · Unwavering Mark');
 assert.equal(ward?.max,3);
 assert.equal(actionsFor(cavalier,cavalierTrackers).find(row=>row.rule_id==='fighter_phb_cavalier_warding_maneuver')?.tracker_id,ward.id);
 assert.equal(calculateSheet(creature('Fighter','2014',18,'Champion'),catalogs).trackers
  .some(row=>['Fighting Spirit','Warding Maneuver'].includes(row.name)),false);
 assert.equal(calculateSheet(creature('Fighter','2024',18,'Samurai'),catalogs).trackers
  .some(row=>row.name==='Fighting Spirit'),false);
});

test('non-reprinted XGE Rogue traits own their actions and limited uses',()=>{
 const inquisitive=creature('Rogue','2014',13,'Inquisitive');
 const inquisitiveTrackers=calculateSheet(inquisitive,catalogs).trackers;
 const eye=inquisitiveTrackers.find(row=>row.name==='Unerring Eye');
 assert.equal(eye?.max,3);
 assert.equal(eye?.recharge,'long_rest');
 assert.equal(eye?.origin_name,'Tratto · Unerring Eye');
 const inquisitiveActions=actionsFor(inquisitive,inquisitiveTrackers)
  .filter(row=>row.rule_id.startsWith('rogue_phb_xge_inquisitive_'));
 assert.deepEqual(inquisitiveActions.map(row=>row.time),['bonus','bonus','action']);
 assert.equal(inquisitiveActions[2].tracker_id,eye.id);
 const swashbuckler=creature('Rogue','2014',17,'Swashbuckler');
 const swashTrackers=calculateSheet(swashbuckler,catalogs).trackers;
 const duelist=swashTrackers.find(row=>row.name==='Master Duelist');
 assert.equal(duelist?.max,1);
 assert.equal(duelist?.recharge,'short_rest');
 assert.equal(duelist?.origin_name,'Tratto · Master Duelist');
 assert.deepEqual(actionsFor(swashbuckler,swashTrackers)
  .filter(row=>row.rule_id.startsWith('rogue_phb_xge_swashbuckler_'))
  .map(row=>row.time),['action','bonus']);
 assert.equal(calculateSheet(creature('Rogue','2014',17,'Scout'),catalogs).trackers
  .some(row=>['Unerring Eye','Master Duelist'].includes(row.name)),false);
 assert.equal(calculateSheet(creature('Rogue','2024',17,'Swashbuckler'),catalogs).trackers
  .some(row=>row.name==='Master Duelist'),false);
});

test('non-reprinted XGE Ranger archetypes keep separate 2014 trait resources',()=>{
 const horizon=creature('Ranger','2014',15,'Horizon Walker');
 const horizonTrackers=calculateSheet(horizon,catalogs).trackers;
 const portal=horizonTrackers.find(row=>row.name==='Detect Portal');
 const step=horizonTrackers.find(row=>row.name==='Ethereal Step');
 assert.equal(portal?.max,1);
 assert.equal(step?.max,1);
 assert([portal,step].every(row=>row.recharge==='short_rest'&&row.origin_id.includes('subclass')));
 const horizonActions=actionsFor(horizon,horizonTrackers)
  .filter(row=>row.rule_id.startsWith('ranger_phb_xge_horizon_'));
 assert.deepEqual(horizonActions.map(row=>row.time),['action','bonus','bonus','reaction']);
 assert.equal(horizonActions[0].tracker_id,portal.id);
 assert.equal(horizonActions[2].tracker_id,step.id);
 const slayer=creature('Ranger','2014',15,'Monster Slayer');
 const slayerTrackers=calculateSheet(slayer,catalogs).trackers;
 const sense=slayerTrackers.find(row=>row.name==="Hunter's Sense");
 const nemesis=slayerTrackers.find(row=>row.name==="Magic-User's Nemesis");
 assert.equal(sense?.max,3);
 assert.equal(sense?.recharge,'long_rest');
 assert.equal(sense?.origin_name,"Tratto · Hunter's Sense");
 assert.equal(nemesis?.max,1);
 assert.equal(nemesis?.recharge,'short_rest');
 assert.deepEqual(actionsFor(slayer,slayerTrackers)
  .filter(row=>row.rule_id.startsWith('ranger_phb_xge_slayer_'))
  .map(row=>row.time),['action','bonus','reaction','reaction']);
 assert.equal(calculateSheet(creature('Ranger','2024',15,'Monster Slayer'),catalogs).trackers
  .some(row=>row.name==="Hunter's Sense"),false);
});

test('XGE Dreams and Shepherd retain class-level pools, shared uses and trait actions',()=>{
 const dreams=creature('Druid','2014',14,'Circle of Dreams');
 const own=calculateSheet(dreams,catalogs).trackers;
 const balm=own.find(row=>row.name==='Balm of the Summer Court');
 const paths=own.find(row=>row.name==='Hidden Paths');
 const walker=own.find(row=>row.name==='Walker in Dreams');
 assert.equal(balm?.max,14);
 assert.equal(paths?.max,3);
 assert.equal(walker?.max,1);
 assert([balm,paths,walker].every(row=>row.recharge==='long_rest'&&row.origin_id.includes('subclass')));
 const actions=actionsFor(dreams,own).filter(row=>row.rule_id.startsWith('druid_phb_dreams_'));
 assert.deepEqual(actions.map(row=>row.time),['bonus','action']);
 assert(actions.every(row=>row.tracker_id===paths.id));
 assert.equal(actionsFor(dreams,own).some(row=>row.feature==='Balm of the Summer Court'),false,
  'variable die spend must not become a fixed-cost action');
 const multiclass={...creature('Druid','2014',15,'Circle of Dreams'),classes:[
  {name:'Druid',source:'PHB',level:10,subclass:'Circle of Dreams',subclass_source:'XGE'},
  {name:'Fighter',source:'PHB',level:5}]};
 assert.equal(calculateSheet(multiclass,catalogs).trackers.find(row=>row.name==='Balm of the Summer Court')?.max,10);
 const shepherd=creature('Druid','2014',14,'Circle of the Shepherd');
 const flock=calculateSheet(shepherd,catalogs).trackers;
 assert.equal(flock.find(row=>row.name==='Spirit Totem')?.recharge,'short_rest');
 assert.equal(flock.find(row=>row.name==='Faithful Summons')?.max,1);
 assert.equal(actionsFor(shepherd,flock).find(row=>row.rule_id==='druid_phb_shepherd_spirit_totem')?.time,'bonus');
 assert.equal(flock.some(row=>row.name==='Balm of the Summer Court'),false);
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
 const actions=actionsFor(rogue);
 assert(actions.some(row=>row.rule_id==='rogue_phb_use_object'));
 assert(actions.some(row=>row.rule_id==='druid_phb_wild_shape'&&row.time==='action'));
 assert(!actions.some(row=>row.rule_id==='druid_phb_wild_shape'&&row.time==='bonus'));
 const primaryLegacy={...rogue,class:'Druid',subclass:'Circle of the Moon',
  classes:[{name:'Druid',source:'PHB',level:2},{name:'Rogue',source:'PHB',level:3}]};
 const legacyActions=actionsFor(primaryLegacy);
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

test('no class action without its trait, and disabling a trait preserves its spent counter',()=>{
 const record=creature('Druid','2014',2);
 assert.deepEqual(featureActionEntries(record,[],rules,[]),[]);
 const original=calculateSheet(record,catalogs),tracker=original.trackers.find(t=>t.name==='Wild Shape');
 const feature=original.features.find(f=>f.name==='Wild Shape');
 assert.equal(tracker.origin_id,feature.origin_id);
 const disabled={...record,resource_tracker_spent:{[tracker.id]:1},origin_enabled:{[feature.origin_id]:false}};
 const hidden=calculateSheet(disabled,catalogs);
 assert(!hidden.trackers.some(t=>t.id===tracker.id));
 assert(!actionEntries(disabled,hidden).some(a=>a.rule_action_id==='wild_shape'));
 const restored=calculateSheet({...disabled,origin_enabled:{}},catalogs).trackers.find(t=>t.id===tracker.id);
 assert.equal(restored.spent,1);
});
