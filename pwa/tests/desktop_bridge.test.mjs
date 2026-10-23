import {test} from 'node:test';
import assert from 'node:assert/strict';
import {request,receive} from '../desktop/bridge.js';

test('native file chooser waits for its result, cancellation and write errors',async()=>{
  let sent;
  globalThis.ipc={postMessage(raw){sent=JSON.parse(raw);}};
  const file=request('import',{}, {timeoutMs:0});
  await new Promise(resolve=>setTimeout(resolve,30));
  receive({id:sent.id,value:{canceled:true}});
  assert.deepEqual(await file,{canceled:true});
  const failed=request('download',{}, {timeoutMs:100});
  receive({id:sent.id,error:'Disco non disponibile'});
  await assert.rejects(failed,/Disco non disponibile/);
  await assert.rejects(request('get',{}, {timeoutMs:5}),/non risponde/);
  globalThis.ipc={postMessage(){throw Error('Finestra chiusa');}};
  await assert.rejects(request('import',{}, {timeoutMs:0}),/Finestra chiusa/);
  delete globalThis.ipc;
});
