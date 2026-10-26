import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {abilitiesForCreature} from '../activated_abilities.js';
import {battleResourcePowers,resourceLinkedSubclassTrait} from '../sheet_rules_view.js';
import {battleAbilityEntries} from '../action_economy.js';
import {recoveryPatch} from '../character_core.js';

const json=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const catalogs={
 classMechanics:json('../catalog/class_mechanics.json'),
 classFeatures:json('../catalog/classes.json'),
 abilityGrants:json('../catalog/ability_grants.json'),
 proficiencyGrants:json('../catalog/proficiency_grants.json'),
 featureRules:json('../../vtt/data/feature_timing_recovery_rules.json')
};
const bard=(level,subclass='College of Creation',source='PHB')=>({
 kind:'character',rules_version:source==='XPHB'?'2024':'2014',
 class:'Bard',class_source:source,level,
 subclass,subclass_source:'TCE',
 classes:[{name:'Bard',source,level,subclass,subclass_source:'TCE'}],
 abilities:{str:10,dex:12,con:12,int:10,wis:10,cha:16},
 current_hp:22,max_hp_base:22,resource_tracker_spent:{}
});

test('College of Creation 2014: distinct trait-owned long-rest trackers at the correct levels',()=>{
 for(const [level,expected] of [[2,[]],[3,['Performance of Creation']],[6,['Animating Performance','Performance of Creation']]]){
  const record=bard(level),projection=calculateSheet(record,catalogs);
  const own=projection.trackers.filter(t=>['Performance of Creation','Animating Performance'].includes(t.name));
  assert.deepEqual(own.map(t=>t.name).sort(),expected);
  for(const tracker of own){
   assert.equal(tracker.max,1);
   assert.equal(tracker.recharge,'long_rest');
   assert.equal(tracker.origin_subclass,'College of Creation');
   assert.equal(tracker.origin_subclass_source,'TCE');
   assert(tracker.origin_id.startsWith('feature:class|phb|bard|subclass|'));
  }
  const abilities=abilitiesForCreature(record,[],projection);
  const actions=battleAbilityEntries(record,projection,[],abilities);
  const resources=battleResourcePowers(projection,actions,abilities);
  for(const tracker of own){
   assert(!abilities.some(power=>power.name===tracker.name),
    'Do not infer an action or one-use cost solely from a tracker');
   const linked=resourceLinkedSubclassTrait(tracker,projection.features,resources);
   assert.equal(linked?.origin_id,tracker.origin_id);
   assert.equal(linked?.name,tracker.name);
  }
 }
 const other=bard(14,'College of Lore');
 const notGranted=calculateSheet(other,catalogs);
 assert(!notGranted.trackers.some(t=>t.name==='Animating Performance'||t.name==='Performance of Creation'));
 const active=bard(6);
 const before=calculateSheet(active,catalogs);
 const used={...active,resource_tracker_spent:Object.fromEntries(before.trackers.filter(t=>/of Creation|Animating Performance/.test(t.name)).map(t=>[t.id,1]))};
 const recovered=recoveryPatch(used,'long_rest',before.trackers);
 for(const id of Object.keys(used.resource_tracker_spent))assert.equal(recovered.resource_tracker_spent[id],undefined);
});

test('No subclass actions or free extra uses are fabricated from descriptive traits',()=>{
 const base=bard(6),projection=calculateSheet(base,catalogs);
 const lore=bard(6,'College of Lore'),loreProjection=calculateSheet(lore,catalogs);
 assert(!abilitiesForCreature(lore,[],loreProjection).some(p=>
  ['Animating Performance','Performance of Creation'].includes(p.name)));
 const hidden=projection.features.find(f=>f.name==='Animating Performance');
 assert(hidden);
 const disabled=calculateSheet({...base,origin_enabled:{[hidden.origin_id]:false}},catalogs);
 assert(!abilitiesForCreature({...base,origin_enabled:{[hidden.origin_id]:false}},[],disabled)
  .some(p=>p.name==='Animating Performance'));
 assert(!disabled.trackers.some(t=>t.name==='Animating Performance'),
  'Turning off the original trait suppresses its tracker, not saved usage counters');
 assert(!abilitiesForCreature(base,[],projection).some(p=>p.name==='Mote of Potential'),
  'A passive text entry must not be presented as a paid action');
 assert.equal(resourceLinkedSubclassTrait({id:'other',origin_id:'feature:class|phb|bard|x'},
  projection.features,[]),null,'Only actual subclass origins get linked');
});

test('Other 2014 subclasses use the same tracker-owned resource ability projection',()=>{
 const fighter={kind:'character',rules_version:'2014',class:'Fighter',class_source:'PHB',level:7,
  subclass:'Battle Master',subclass_source:'PHB',
  classes:[{name:'Fighter',source:'PHB',level:7,subclass:'Battle Master',subclass_source:'PHB'}],
  abilities:{str:16,dex:14,con:14,int:10,wis:10,cha:10}};
 const projection=calculateSheet(fighter,catalogs);
 const superiority=projection.trackers.find(t=>t.name==='Superiority Die');
 assert(superiority,'Battle Master should retain the Combat Superiority resource');
 const power=abilitiesForCreature(fighter,[],projection).find(p=>p.name==='Combat Superiority');
 assert(!power,'A shared superiority-dice pool must not become a fixed cost-1 action');
 const link=resourceLinkedSubclassTrait(superiority,projection.features,[]);
 assert.equal(link?.name,'Combat Superiority');
 assert.equal(link.origin_id,superiority.origin_id);
 const champion={...fighter,subclass:'Champion',classes:[{...fighter.classes[0],subclass:'Champion'}]};
 const result=calculateSheet(champion,catalogs);
 assert(!result.trackers.some(t=>t.name==='Superiority Die'));
 assert(!abilitiesForCreature(champion,[],result).some(p=>p.name==='Combat Superiority'));
});
