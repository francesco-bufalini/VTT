import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {classActionOverridesFromBenefits,classRollBonusRulesFromBenefits,
 loadClassActionBenefits,loadClassRollBonusBenefits} from '../class_benefit_catalogs.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const typedAction=read('../../vtt/enrichment/benefits/action.json');
const typedRoll=read('../../vtt/enrichment/benefits/roll_bonus.json');

test('all 52 class actions survive the typed migration with exact operation, costs and source',()=>{
 assert.equal(typedAction.entries.filter(row=>row.projection!=='timing_action'&&row.projection!=='timing_contextual_action'&&['class_feature','subclass_feature'].includes(row.granted_by.ref.category)).length,52);
 assert.equal(typedAction.entries.filter(row=>row.projection==='timing_action').length,65);
 const rules=classActionOverridesFromBenefits(typedAction);
 assert.equal(rules.length,52);
 assert.equal(rules.find(row=>row.feature_name==='Rage'&&row.book==='PHB')?.activation,'bonus');
 assert(typedAction.entries.some(row=>row.granted_by.ref.source==='XPHB'));
 assert(typedAction.entries.some(row=>row.granted_by.ref.source==='TCE'));
 for(const entry of typedAction.entries.filter(row=>['class_feature','subclass_feature'].includes(row.granted_by.ref.category))){
  assert(['class_feature','subclass_feature'].includes(entry.granted_by.ref.category));
  assert(!('description' in entry.benefit));
 }
});

test('all 15 class and subclass roll bonuses retain their numeric and conditional mechanics',()=>{
 assert.equal(typedRoll.entries.filter(entry=>['class_feature','subclass_feature'].includes(entry.granted_by.ref.category)).length,15);
 assert.equal(classRollBonusRulesFromBenefits(typedRoll).length,15);
 const subclass=typedRoll.entries.find(row=>row.granted_by.ref.subclass==='Champion');
 assert.equal(subclass.granted_by.ref.name,'Remarkable Athlete');
 const passive=typedRoll.entries.find(row=>row.benefit.id==='artificer_tool_expertise');
 assert.equal(passive.benefit.passive,true);
 const conditional=typedRoll.entries.find(row=>row.benefit.id==='ranger_favored_enemy_tracking');
 assert.equal(conditional.benefit.bonus.roll_mode,'advantage');
});

const fakeFetch=(routes)=>async url=>({ok:Object.hasOwn(routes,url),status:Object.hasOwn(routes,url)?200:404,json:async()=>routes[url]});

test('PWA loads only typed class benefits and rejects absent or malformed catalogs',async()=>{
 const a='/catalog/benefits/action.json',r='/catalog/benefits/roll_bonus.json';
 assert.deepEqual(await loadClassActionBenefits(fakeFetch({[a]:typedAction})),classActionOverridesFromBenefits(typedAction));
 assert.deepEqual(await loadClassRollBonusBenefits(fakeFetch({[r]:typedRoll})),classRollBonusRulesFromBenefits(typedRoll));
 await assert.rejects(()=>loadClassActionBenefits(fakeFetch({})),/non disponibile/);
 await assert.rejects(()=>loadClassRollBonusBenefits(fakeFetch({})),/non disponibile/);
 await assert.rejects(()=>loadClassActionBenefits(fakeFetch({[a]:{...typedAction,entries:[{id:'broken'}]}})),/non valida/);
 await assert.rejects(()=>loadClassRollBonusBenefits(fakeFetch({[r]:{...typedRoll,entries:[{id:'broken'}]}})),/non valida/);
});

test('typed class catalogs are hosted and cached offline',()=>{
 const host=readFileSync(new URL('../../network/pwa_host.gd',import.meta.url),'utf8');
 const sw=readFileSync(new URL('../sw.js',import.meta.url),'utf8');
 for(const [web,path] of [
  ['/class_benefit_catalogs.js','pwa/class_benefit_catalogs.js'],
  ['/catalog/benefits/action.json','vtt/enrichment/benefits/action.json'],
  ['/catalog/benefits/roll_bonus.json','vtt/enrichment/benefits/roll_bonus.json']
 ]){
  assert(host.includes('"'+web+'": ["res://'+path+'"'),web+' missing host route');
  assert(sw.includes('"'+web+'"'),web+' missing offline cache');
 }
});
