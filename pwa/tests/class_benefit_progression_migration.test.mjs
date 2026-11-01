import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {projectFeatureTimingRules,projectClassResourceOverrides,
 loadClassFeatureTimingBenefits,loadClassResourceBenefits} from '../class_benefit_progression.js';
import {classActionOverridesFromBenefits} from '../class_benefit_catalogs.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const sourceTiming=read('../../vtt/data/feature_timing_recovery_rules.json');
const sourceResources=read('../../vtt/data/class_resource_overrides.json');
const oldActions=read('../../vtt/data/action_feature_overrides.json').entries;
const benefitTypes=['action','activation','resource_recovery','attack_count','action_sequence','resource'];
const catalogs=Object.fromEntries(benefitTypes.map(type=>
 [type,read('../../vtt/enrichment/benefits/'+type+'.json')]));
const count={action:65,activation:31,resource_recovery:17,attack_count:26,action_sequence:12,resource:90};
const classEntries=(catalog,type)=>catalog.entries.filter(entry=>
 entry.granted_by?.kind==='5etools'&&
 ['class_feature','subclass_feature'].includes(entry.granted_by.ref.category)&&
 (type!=='action'||entry.projection==='timing_action'));

test('all 151 timing/recovery/attack-count and sequence entries retain original runtime projection',()=>{
 const projected=projectFeatureTimingRules(catalogs);
 for(const name of ['contextual_actions','actions','recoveries','attack_count_grants','attack_actions']){
  assert.deepEqual(projected[name],sourceTiming[name],name+' changed when projected');
 }
 assert.equal(projected.version,1);
 for(const type of benefitTypes.filter(x=>x!=='resource')){
  assert.equal(classEntries(catalogs[type],type).length,count[type],type);
 }
 // The Druid has two distinct Wild Shape grants with the same runtime rule ID,
 // one base action and one higher-priority subclass bonus action.
 const wildShape=classEntries(catalogs.action,'action').filter(x=>x.benefit.id==='druid_phb_wild_shape');
 assert.equal(wildShape.length,2);
 assert.equal(new Set(wildShape.map(x=>x.id)).size,2);
 assert.deepEqual(wildShape.map(x=>x.benefit.priority),[0,10]);
 assert.deepEqual(classActionOverridesFromBenefits(catalogs.action),oldActions);
});

test('all 90 subclass/class resource overrides project losslessly without changing tracker identifiers',()=>{
 assert.equal(classEntries(catalogs.resource,'resource').length,count.resource);
 assert.deepEqual(projectClassResourceOverrides(catalogs.resource),sourceResources.classes);
 for(const item of classEntries(catalogs.resource,'resource')){
  const ref=item.granted_by.ref;
  assert(ref.name&&ref.source&&ref.class_source);
  assert(!('description' in item.benefit));
 }
});

test('class/subclass source references use the actual rulebook, not the parent class book',()=>{
 const cases=[
  ['Battlerager','SCAG'],['Zealot','XGE'],['Cavalier','XGE'],
  ['Way of the Sun Soul','XGE'],['The Hexblade','XGE'],['Armorer','TCE']
 ];
 const all=benefitTypes.flatMap(type=>classEntries(catalogs[type],type));
 for(const [subclass,source] of cases){
  const matches=all.filter(item=>item.granted_by.ref.subclass===subclass);
  assert(matches.length,subclass+' missing');
  assert(matches.some(item=>item.granted_by.ref.subclass_source===source),subclass+' wrong source');
 }
 const unusual=all.find(item=>item.granted_by.ref.subclass==='Berserker');
 assert.equal(unusual.granted_by.ref.class_source,'PHB');
 assert.equal(unusual.granted_by.ref.source,'PHB');
});

const fetcher=(items)=>async path=>({ok:Object.hasOwn(items,path),
 status:Object.hasOwn(items,path)?200:404,json:async()=>items[path]});

test('typed class timing catalog loads as one atomic set, with legacy fallback for partial hosts',async()=>{
 const routes=Object.fromEntries(benefitTypes.map(type=>
 ['/catalog/benefits/'+type+'.json',catalogs[type]]));
 const typed=await loadClassFeatureTimingBenefits(fetcher(routes));
 for(const section of ['contextual_actions','actions','recoveries','attack_count_grants','attack_actions'])
  assert.deepEqual(typed[section],sourceTiming[section]);
 const legacy='/catalog/feature_timing_recovery_rules.json';
 assert.deepEqual(await loadClassFeatureTimingBenefits(fetcher({
  '/catalog/benefits/action.json':catalogs.action,[legacy]:sourceTiming
 })),sourceTiming);
 await assert.rejects(()=>loadClassFeatureTimingBenefits(fetcher({
  ...routes,'/catalog/benefits/resource_recovery.json':
   {...catalogs.resource_recovery,benefit_type:'action'}
 })),/resource_recovery/);
});

test('class resource catalog uses typed grants and falls back to old class tables',async()=>{
 const typed='/catalog/benefits/resource.json';
 const legacy='/catalog/class_resource_overrides.json';
 assert.deepEqual(await loadClassResourceBenefits(fetcher({[typed]:catalogs.resource})),
  sourceResources.classes);
 assert.deepEqual(await loadClassResourceBenefits(fetcher({[legacy]:sourceResources})),
  sourceResources.classes);
 assert.equal(await loadClassResourceBenefits(fetcher({})),null);
});

test('host and offline cache make all new type catalogs available',()=>{
 const host=readFileSync(new URL('../../network/pwa_host.gd',import.meta.url),'utf8');
 const sw=readFileSync(new URL('../sw.js',import.meta.url),'utf8');
 for(const type of benefitTypes){
  const path='/catalog/benefits/'+type+'.json';
  assert(host.includes('"'+path+'": ["res://vtt/enrichment/benefits/'+type+'.json"'),path+' missing host route');
  assert(sw.includes('"'+path+'"'),path+' not precached');
 }
 assert(host.includes('"/class_benefit_progression.js"'));
 assert(sw.includes('"/class_benefit_progression.js"'));
});
