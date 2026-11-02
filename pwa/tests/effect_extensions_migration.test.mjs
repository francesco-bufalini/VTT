import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {effectExtensionsFromBenefits,loadEffectExtensionBenefits,collectEffectExtensions} from '../effect_extensions.js';
const read=p=>JSON.parse(readFileSync(new URL(p,import.meta.url),'utf8'));
const typed=read('../../vtt/enrichment/benefits/effect_extension.json');
const projected=effectExtensionsFromBenefits(typed);
const fake=routes=>async url=>({ok:Object.hasOwn(routes,url),json:async()=>routes[url]});
test('26 source-bound effect extensions preserve all old mechanics',()=>{
 assert.equal(typed.entries.length,26);
 assert.equal(projected.length,26);
 assert.equal(new Set(typed.entries.map(e=>e.id)).size,26);
 assert.equal(typed.entries.find(e=>e.benefit.id==='infusion-repulsion-shield-grant_action-14').granted_by.ref.name,'Repulsion Shield');
});
test('typed extension loader requires a canonical catalog and rejects corrupt data',async()=>{
 assert.deepEqual(await loadEffectExtensionBenefits(fake({'/benefits/effect_extension.json':typed})),projected);
 await assert.rejects(()=>loadEffectExtensionBenefits(fake({})),/non disponibili/);
 await assert.rejects(()=>loadEffectExtensionBenefits(fake({'/benefits/effect_extension.json':{...typed,entries:[{id:'broken'}]}})),/non valida/);
});
test('Warlock invocation remains bound to the selected feature',()=>{
 const record={rules_version:'2014',optional_features_catalog:[{name:'Agonizing Blast',source:'PHB'}]};
 assert(collectEffectExtensions(record,projected).some(row=>row.id?.includes('agonizing-blast')));
});
test('effect catalog is available through host and offline cache',()=>{
 const host=readFileSync(new URL('../../network/pwa_host.gd',import.meta.url),'utf8');
 const sw=readFileSync(new URL('../sw.js',import.meta.url),'utf8');
 assert(host.includes('"/benefits/effect_extension.json": ["res://vtt/enrichment/benefits/effect_extension.json"'));
 assert(sw.includes('"/benefits/effect_extension.json"'));
});
