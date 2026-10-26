import 'fake-indexeddb/auto';
import test from 'node:test';
import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
import {saveHomebrewDefinition,exportHomebrewPackage,importHomebrewPackage}
  from '../creatures.js';
import {getRecord} from '../storage.js';
import {encodeShareChunk,decodeShareChunk} from '../share_transfer.js';
Object.defineProperty(globalThis,'crypto',{value:webcrypto,configurable:true});

test('chunk encoding survives arbitrary binary content, including UTF-8 and chunk limits',()=>{
 const bytes=webcrypto.getRandomValues(new Uint8Array(128*1024));
 const original=new TextEncoder().encode(JSON.stringify({text:'⚔️ È un drago'}));
 assert.deepEqual(decodeShareChunk(encodeShareChunk(original)),original);
 assert.deepEqual(decodeShareChunk(encodeShareChunk(bytes)),bytes);
 assert.equal(decodeShareChunk(encodeShareChunk(new Uint8Array())).length,0);
});

test('homebrew sharing retains transitive dependencies without changing source data',async()=>{
 const suffix=webcrypto.randomUUID().replaceAll('-','').slice(0,14);
 const child={id:'homebrew:sharing_test:items:relic_'+suffix,
   name:'Reliquia',data:{rarity:'rare',value:50}};
 const parent={id:'homebrew:sharing_test:feats:feat_'+suffix,
   name:'Talento',data:{linked_item:child.id,description:'Bonus della reliquia'}};
 await saveHomebrewDefinition(child);
 await saveHomebrewDefinition(parent);
 const before=await getRecord('global','homebrew',parent.id);
 const exported=await exportHomebrewPackage(parent.id);
 assert.equal(exported.format,'vtt_homebrew_share_v1');
 assert.deepEqual(exported.definitions.map(x=>x.id),[parent.id,child.id]);
 assert.equal(await importHomebrewPackage(exported),2,
   'an identical definition may already be locally installed');
 assert.deepEqual(await getRecord('global','homebrew',parent.id),before);
 const changed={...exported,definitions:exported.definitions.map(row=>row.id===child.id?
   {...row,data:{...row.data,rarity:'legendary'}}:row)};
 await assert.rejects(importHomebrewPackage(changed),/conflitto/);
 assert.deepEqual((await getRecord('global','homebrew',child.id)).data,child);
});

test('homebrew imports reject malformed and duplicate definitions',async()=>{
 await assert.rejects(importHomebrewPackage({
   format:'vtt_homebrew_share_v1',version:1,definitions:[{id:'nope',name:'X',data:{}}]
 }),/non valido/);
 const id='homebrew:sharing_test:items:duplicate_'+webcrypto.randomUUID().slice(0,8);
 const entry={id,name:'Duplicato',data:{description:'X'}};
 await assert.rejects(importHomebrewPackage({
   format:'vtt_homebrew_share_v1',version:1,definitions:[entry,entry]
 }),/duplicato/);
});
