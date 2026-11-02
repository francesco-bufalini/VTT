import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {scalingDiceFromBenefits,loadScalingDieBenefits,scalingDiceFor} from '../scaling_dice.js';
const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const typed=read('../../vtt/enrichment/benefits/scaling_die.json');
const projected=scalingDiceFromBenefits(typed);
const fetcher=routes=>async url=>({ok:Object.hasOwn(routes,url),json:async()=>routes[url]});

test('all three source-qualified class dice project losslessly to v1',()=>{
 assert.equal(typed.entries.length,3);
 assert.equal(projected.dice.length,3);
 assert.equal(new Set(typed.entries.map(e=>e.id)).size,3);
 for(const row of typed.entries){
  assert(row.granted_by.ref.name&&row.granted_by.ref.source&&row.granted_by.ref.class_source);
  assert.equal(row.benefit.type,'scaling_die');
  assert(!('description' in row.benefit));
 }
});
test('typed scaling die loader requires a valid canonical catalog',async()=>{
 assert.deepEqual(await loadScalingDieBenefits(fetcher({'/benefits/scaling_die.json':typed})),projected);
 await assert.rejects(()=>loadScalingDieBenefits(fetcher({})),/non disponibili/);
 await assert.rejects(()=>loadScalingDieBenefits(fetcher({
  '/benefits/scaling_die.json':{...typed,entries:[{id:'broken'}]}})),/non valida/);
});
test('Bard and Battle Master effective dice are unchanged for both editions',()=>{
 const dice=projected.dice;
 for(const source of ['PHB','XPHB']){
  const character={classes:[{name:'Bard',source,level:10}]};
  const features=[{name:'Bardic Inspiration',origin_key:'class|'+source.toLowerCase()+'|bard',origin_id:'feature:bardic:'+source}];
  assert.equal(scalingDiceFor(character,dice,features)[0].sides,10);
 }
 const fighter={classes:[{name:'Fighter',source:'PHB',subclass:'Battle Master',level:18}]};
 const features=[{name:'Combat Superiority',origin_key:'class|phb|fighter|subclass|battle master',origin_id:'feature:superiority'}];
 assert.equal(scalingDiceFor(fighter,dice,features)[0].sides,12);
});
test('typed dice are exposed on PWA host and cached offline',()=>{
 const host=readFileSync(new URL('../../network/pwa_host.gd',import.meta.url),'utf8');
 const sw=readFileSync(new URL('../sw.js',import.meta.url),'utf8');
 assert(host.includes('"/benefits/scaling_die.json": ["res://vtt/enrichment/benefits/scaling_die.json"'));
 assert(sw.includes('"/benefits/scaling_die.json"'));
});
