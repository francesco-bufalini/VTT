import test from 'node:test';
import assert from 'node:assert/strict';
import {classFeatureEntries,classFeatureActivationPatch} from '../feature_mechanics.js';
import {abilitiesForCreature} from '../activated_abilities.js';
import {battleAbilityEntries} from '../action_economy.js';
import {readFileSync} from 'node:fs';
const featureActionOverrides=JSON.parse(readFileSync(new URL('../../vtt/data/action_feature_overrides.json',import.meta.url),'utf8')).entries;

const create=(name,owner='Artificer',source='TCE')=>{
 const key='class|'+source.toLowerCase()+'|'+owner.toLowerCase();
 return {name,origin_key:key,origin_id:'feature:'+key+'|'+name.toLowerCase(),
  key:key+'|'+name.toLowerCase(),requirements:{class_name:owner,class_source:source}};
};
test('purely descriptive class powers are visible, never spend a no-op use',()=>{
 const creature={rules_version:'2014',classes:[{name:'Artificer',source:'TCE',level:3}],
  resource_tracker_spent:{}};
 const features=[create('Magical Tinkering'),create('Eldritch Cannon'),create('Steel Defender')];
 const projection={features,trackers:[],feature_rules:{},feature_action_overrides:featureActionOverrides};
 const entries=classFeatureEntries(creature,projection);
 for(const id of ['magical_tinkering','command_cannon','command_defender']){
  const row=entries.find(item=>item.class_feature_id===id);
  assert(row?.descriptive_only,id+' should be retained as descriptive');
  assert.throws(()=>classFeatureActivationPatch(creature,projection,row.id),/descrittiva/);
 }
 const powers=abilitiesForCreature(creature,[],projection);
 assert(powers.find(power=>power.name==='Magical Tinkering')?.descriptive_only);
 const battle=battleAbilityEntries(creature,projection,entries,powers);
 assert(battle.some(row=>row.descriptive_only));
});
