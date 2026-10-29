import 'fake-indexeddb/auto';
import test from 'node:test';
import assert from 'node:assert/strict';
import {subscribeMap} from '../client.js';

const turn=()=>new Promise(resolve=>setImmediate(resolve));
async function started(predicate){
 for(let i=0;i<50;i++){if(predicate())return;await turn();}
 throw Error('Map request did not start');
}
for(const fails of [false,true]){
 test(`stopped map subscription ignores an in-flight ${fails?'failure':'response'}`,async t=>{
  let settle,requested=false;const received=[],errors=[];
  t.mock.method(globalThis,'fetch',()=>{
   requested=true;return new Promise((resolve,reject)=>{settle=fails?reject:resolve;});
  });
  const stop=subscribeMap(data=>received.push(data),error=>errors.push(error));
  t.after(stop);await started(()=>requested);stop();
  settle(fails?Error('Late disconnect'):new Response(JSON.stringify({tokens:[{id:'old-board'}]})));
  await turn();await turn();
  assert.deepEqual(received,[],'Leaving a session must prevent stale map updates');
  assert.deepEqual(errors,[],'Leaving a session must prevent late error callbacks');
 });
}
test('active map subscription still delivers responses and errors',async t=>{
 let fail=false;const received=[],errors=[];
 t.mock.method(globalThis,'fetch',async()=>{
  if(fail)throw Error('Disconnected');
  return new Response(JSON.stringify({tokens:[]}));
 });
 let stop=subscribeMap(data=>received.push(data),error=>errors.push(error));
 t.after(()=>stop());await started(()=>received.length===1);stop();
 assert.deepEqual(received,[{tokens:[]}]);
 fail=true;stop=subscribeMap(data=>received.push(data),error=>errors.push(error));
 await started(()=>errors.length===1);stop();assert.match(errors[0].message,/Disconnected/);
});
