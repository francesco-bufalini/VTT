import 'fake-indexeddb/auto';
import test from 'node:test';
import assert from 'node:assert/strict';
import {map} from '../client.js';
import {backupRequest} from '../server_backup_core.js';

for(const [name,request] of [['map',()=>map()],['backup',()=>backupRequest('manifest',{},'a'.repeat(64))]]){
 for(const [status,body] of [[401,'<html>Unauthorized</html>'],[503,''],[429,'null']]){
  test(`${name} preserves HTTP ${status} for non-object error bodies`,async t=>{
   t.mock.method(globalThis,'fetch',async()=>new Response(body,{status}));
   await assert.rejects(request(),error=>error.status===status&&typeof error.message==='string');
  });
 }
 test(`${name} preserves a structured server error`,async t=>{
  t.mock.method(globalThis,'fetch',async()=>new Response(JSON.stringify({error:'specific failure'}),{status:409}));
  await assert.rejects(request(),error=>error.status===409&&error.message==='specific failure');
 });
 test(`${name} still rejects malformed successful responses`,async t=>{
  t.mock.method(globalThis,'fetch',async()=>new Response('<html>Bad gateway</html>',{status:200}));
  await assert.rejects(request(),SyntaxError);
 });
}
