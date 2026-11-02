import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {featureItemGrantsFromBenefits,loadFeatureItemGrantBenefits,
 featureItemGrants} from '../feature_item_grants.js';
const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const typed=read('../../vtt/enrichment/benefits/item_grant.json');
const old=read('../catalog/feature_item_grants.json').grants;
const fetcher=routes=>async path=>({ok:Object.hasOwn(routes,path),json:async()=>routes[path]});

test('all five item grants project without dropping ownership, choices or powers',()=>{
 assert.equal(typed.entries.length,5);
 assert.deepEqual(featureItemGrantsFromBenefits(typed),old);
 assert.equal(new Set(typed.entries.map(e=>e.id)).size,old.length);
 for(const row of typed.entries){
  assert.equal(row.benefit.type,'item_grant');
  assert(row.granted_by.ref.name&&row.granted_by.ref.source);
 }
 const bard=typed.entries.find(x=>x.benefit.id==='bard-performance-of-creation');
 assert.equal(bard.granted_by.ref.subclass_source,'TCE');
 const rock=typed.entries.find(x=>x.benefit.id==='gnome-rock-tinker');
 assert.equal(rock.granted_by.ref.category,'species_trait');
 assert.equal(rock.granted_by.ref.subrace,'Rock');
});

test('source-qualified item grants load from v2 or old host, never malformed v2',async()=>{
 assert.deepEqual(await loadFeatureItemGrantBenefits(fetcher({
  '/benefits/item_grant.json':typed,'/catalog/feature_item_grants.json':{version:1,grants:[]}})),old);
 assert.deepEqual(await loadFeatureItemGrantBenefits(fetcher({
  '/catalog/feature_item_grants.json':{version:1,grants:old}})),old);
 assert.deepEqual(await loadFeatureItemGrantBenefits(fetcher({})),[]);
 await assert.rejects(()=>loadFeatureItemGrantBenefits(fetcher({
  '/benefits/item_grant.json':{...typed,entries:[{id:'broken'}]},
  '/catalog/feature_item_grants.json':{version:1,grants:old}})),/non valida/);
});

test('the migrated Eldritch Cannon retains its action and inventory options',()=>{
 const cannon=featureItemGrantsFromBenefits(typed).find(row=>row.id==='artificer-eldritch-cannon');
 assert.equal(cannon.activation_action_id,'eldritch_cannon');
 assert.equal(cannon.items.length,3);
 assert.equal(cannon.powers.length>0,true);
 assert.equal(cannon.max_owned_by_level.length>0,true);
});
test('item grant catalog has host and offline cache routes',()=>{
 const host=readFileSync(new URL('../../network/pwa_host.gd',import.meta.url),'utf8');
 const sw=readFileSync(new URL('../sw.js',import.meta.url),'utf8');
 assert(host.includes('"/benefits/item_grant.json": ["res://vtt/enrichment/benefits/item_grant.json"'));
 assert(sw.includes('"/benefits/item_grant.json"'));
});
