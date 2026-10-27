import 'fake-indexeddb/auto';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
import {syncServerBackup,hashText,BACKUP_CHUNK_BYTES} from '../server_backup_core.js';
import {observeArchiveChanges,putRecord,getRecord,setting,insertRecords} from '../storage.js';
Object.defineProperty(globalThis,'crypto',{value:webcrypto,configurable:true});
const token='a'.repeat(64),owner='b'.repeat(32),key=async()=>'c'.repeat(64);
const row=(id,name='Lyria')=>({scope:'default',type:'creature',id,revision:1,updatedAt:1,data:{id,kind:'character',name,owner_id:owner}});
function transport(manifest={generation:'',records:[],blobs:[],outbox_hash:''}){
 const calls=[],chunks=[];let active=0,maxActive=0;
 return {calls,chunks,get maxActive(){return maxActive;},request:async(route,body)=>{
  active++;maxActive=Math.max(maxActive,active);
  try{
   await new Promise(resolve=>setTimeout(resolve,1));calls.push({route,body});
   if(route==='manifest')return manifest;
   if(route==='chunk'){chunks[body.index]=Buffer.from(body.data,'base64');return {accepted:body.index};}
   return {saved_at:'2026-10-27T12:00:00Z'};
  }finally{active--;}
 }};
}
test('empty or unpaired installations never send or replace a server archive',async()=>{
 const network=transport();
 for(const auth of ['',token]){
  const result=await syncServerBackup({token:auth,key,request:network.request,read:async()=>({owner,records:[],blobs:[],outbox:[]})});
  assert.equal(result.mode,auth?'empty':'unpaired');
 }
 assert.equal(network.calls.length,0);
});
test('unchanged archive performs only a metadata request, without attachment reads',async()=>{
 const record=row('same'),digest='d'.repeat(64);
 const network=transport({generation:'e'.repeat(64),records:[{key:['default','creature','same'],hash:await hashText(JSON.stringify(record))}],
  blobs:[digest],outbox_hash:await hashText('[]'),saved_at:'earlier'});
 const result=await syncServerBackup({token,key,request:network.request,
  read:async()=>({owner,records:[record],blobs:[{digest,blob:{arrayBuffer(){throw Error('must not read attachment');}}}],outbox:[]})});
 assert.equal(result.unchanged,true);assert.deepEqual(network.calls.map(c=>c.route),['manifest']);
});
test('editing one record sends only that record and keeps known attachments off the wire',async()=>{
 const original=row('one'),unchanged=row('two'),digest='d'.repeat(64);
 const network=transport({generation:'e'.repeat(64),records:[original,unchanged].map(r=>({key:[r.scope,r.type,r.id],hash:''})),blobs:[digest],outbox_hash:await hashText('[]')});
 network.calls.length=0;
 const remote=await Promise.all([original,unchanged].map(async r=>({key:[r.scope,r.type,r.id],hash:await hashText(JSON.stringify(r))})));
 const other=transport({generation:'e'.repeat(64),records:remote,blobs:[digest],outbox_hash:await hashText('[]')});
 await syncServerBackup({token,key,request:other.request,chunkDelay:0,read:async()=>({owner,
  records:[{...original,revision:2,data:{...original.data,name:'Updated'}},unchanged],
  blobs:[{digest,blob:{arrayBuffer(){throw Error('must not read');}}}],outbox:[]})});
 const delta=JSON.parse(Buffer.concat(other.chunks));
 assert.equal(delta.upserts.length,1);assert.equal(delta.upserts[0].record.id,'one');assert.deepEqual(delta.blobs,[]);
 assert.equal(other.maxActive,1);
});
test('large updates are sequential bounded blocks with pauses and a final verified commit',async()=>{
 const network=transport(),pauses=[];
 const records=[{...row('big'),data:{...row('big').data,notes:'à'.repeat(100000)}}];
 const result=await syncServerBackup({token,key,request:network.request,pause:async ms=>pauses.push(ms),
  read:async()=>({owner,records,blobs:[],outbox:[]})});
 assert.ok(result.parts>1);assert.equal(pauses.length,result.parts-1);assert.ok(pauses.every(ms=>ms===250));
 assert.ok(network.chunks.every(chunk=>chunk.length<=BACKUP_CHUNK_BYTES));
 const text=Buffer.concat(network.chunks).toString('utf8');
 assert.equal(await hashText(text),network.calls.at(-1).body.sha256);
 assert.deepEqual(JSON.parse(text).upserts[0].record,records[0]);assert.equal(network.maxActive,1);
 assert.equal(network.calls.at(-1).route,'commit');
 assert.ok(!text.includes(token)&&!text.includes('server-backup-key'));
});
test('interrupted upload never commits or reports success',async()=>{
 const network=transport();let chunks=0;
 await assert.rejects(syncServerBackup({token,key,pause:async()=>{},read:async()=>({owner,
  records:[{...row('big'),data:{notes:'x'.repeat(180000)}}],blobs:[],outbox:[]}),request:async(route,body)=>{
   if(route==='chunk'&&++chunks===2)throw Error('offline');return network.request(route,body);
 }}),/offline/);
 assert.ok(!network.calls.some(c=>c.route==='commit'));
});
test('archive observers ignore reads, settings and aborted writes',async()=>{
 let changes=0;const stop=observeArchiveChanges(()=>changes++);
 await setting('test-backup-state',1);await getRecord('observer','creature','one');assert.equal(changes,0);
 await putRecord('observer','creature','one',{name:'saved'},0);assert.equal(changes,1);
 await assert.rejects(insertRecords([{scope:'observer',type:'creature',id:'two',data:{}},
  {scope:'observer',type:'creature',id:'one',data:{}}]));
 assert.equal(changes,1);assert.equal(await getRecord('observer','creature','two'),null);stop();
});
