import 'fake-indexeddb/auto';
import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {webcrypto} from 'node:crypto';
import {pollIncomingShares,encodeShareChunk} from '../share_transfer.js';
import {getRecord} from '../storage.js';
const dom=new JSDOM('<!doctype html><body></body>',{url:'https://vtt.test/'});
globalThis.document=dom.window.document;
Object.defineProperty(globalThis,'navigator',{value:dom.window.navigator,configurable:true});
Object.defineProperty(globalThis,'crypto',{value:webcrypto,configurable:true});
let now=1000000000000;
async function until(predicate){
 for(let i=0;i<200;i++){if(predicate())return;await new Promise(resolve=>setTimeout(resolve,5));}
 throw Error('Dialog operation did not finish');
}
function setup(t,id,operation){
 document.body.innerHTML='';now+=1000000;
 t.mock.method(Date,'now',()=>now);
 const offer={id,kind:'homebrew',title:'Test',sender_name:'Sender',size:2,parts:1};
 t.mock.method(globalThis,'fetch',async url=>{
  const body=url.endsWith('/peers')?{inbox:[offer]}:await operation(url);
  return new Response(JSON.stringify(body),{status:200});
 });
}
test('incoming import keeps close and Escape blocked until a failed import is recoverable',async t=>{
 let release,pulling=false;
 const pending=new Promise(resolve=>release=resolve);
 t.after(()=>release({data:'e30='}));
 setup(t,'busy-import',async url=>{assert.ok(url.endsWith('/pull'));pulling=true;return pending;});
 await pollIncomingShares(true);
 const dialog=document.querySelector('#share-receive-dialog');
 dialog.querySelector('[data-share-accept]').click();await until(()=>pulling);
 const close=dialog.querySelector('[data-act="share-later"]');
 close.click();assert.ok(dialog.isConnected,'Close must not hide an import in progress');
 assert.equal(close.disabled,true);
 const cancel=new dom.window.Event('cancel',{cancelable:true});dialog.dispatchEvent(cancel);
 assert.equal(cancel.defaultPrevented,true);assert.ok(dialog.isConnected);
 release({data:'e30='}); // Invalid package: the user must be able to retry or postpone.
 await until(()=>!dialog.querySelector('[data-share-accept]').disabled);
 assert.match(dialog.querySelector('[data-share-status]').textContent,/Importazione non riuscita/);
 assert.equal(close.disabled,false);close.click();assert.equal(dialog.isConnected,false);
 now+=5000;await pollIncomingShares(true);assert.equal(document.querySelector('dialog'),null);
});
test('Escape postpones an idle incoming offer for the same interval as Later',async t=>{
 setup(t,'escape-offer',async()=>{throw Error('No transfer should start');});
 await pollIncomingShares(true);
 const dialog=document.querySelector('dialog');
 const cancel=new dom.window.Event('cancel',{cancelable:true});dialog.dispatchEvent(cancel);
 assert.equal(cancel.defaultPrevented,true);assert.equal(dialog.isConnected,false);
 now+=5000;await pollIncomingShares(true);assert.equal(document.querySelector('dialog'),null);
 now+=60000;await pollIncomingShares(true);assert.ok(document.querySelector('dialog[open]'));
});
test('incoming rejection also locks the close control until acknowledgement completes',async t=>{
 let release,acking=false;
 const pending=new Promise(resolve=>release=resolve);t.after(()=>release({}));
 setup(t,'busy-reject',async url=>{assert.ok(url.endsWith('/ack'));acking=true;return pending;});
 await pollIncomingShares(true);const dialog=document.querySelector('dialog');
 dialog.querySelector('[data-share-reject]').click();await until(()=>acking);
 const close=dialog.querySelector('[data-act="share-later"]');close.click();
 assert.ok(dialog.isConnected);assert.equal(close.disabled,true);
 release({});await until(()=>!dialog.isConnected);
 now+=5000;await pollIncomingShares(true);assert.equal(document.querySelector('dialog'),null);
});

test('successful import reports a failed screen refresh without offering a duplicate import',async t=>{
 const id='homebrew:sharing_test:items:refresh_failure';
 const definition={id,name:'Refresh regression',data:{description:'Saved before refresh'}};
 const bytes=new TextEncoder().encode(JSON.stringify({
  format:'vtt_homebrew_share_v1',version:1,definitions:[definition]
 }));
 document.body.innerHTML='';now+=1000000;t.mock.method(Date,'now',()=>now);
 const offer={id:'refresh-failure',kind:'homebrew',title:'Test',sender_name:'Sender',size:bytes.length,parts:1};
 let acknowledgements=0,refreshes=0;const notices=[];
 t.mock.method(globalThis,'fetch',async url=>{
  let body;
  if(url.endsWith('/peers'))body={inbox:[offer]};
  else if(url.endsWith('/pull'))body={data:encodeShareChunk(bytes)};
  else {assert.ok(url.endsWith('/ack'));acknowledgements++;body={};}
  return new Response(JSON.stringify(body),{status:200});
 });
 await pollIncomingShares(true,async()=>{refreshes++;throw Error('Refresh unavailable');},message=>notices.push(message));
 const dialog=document.querySelector('dialog');dialog.querySelector('[data-share-accept]').click();
 await until(()=>refreshes===1);await new Promise(resolve=>setTimeout(resolve,0));
 assert.deepEqual((await getRecord('global','homebrew',id)).data,definition);
 assert.equal(acknowledgements,1);assert.equal(dialog.isConnected,false);
 assert.equal(notices.length,1,'A refresh failure must remain visible after the import dialog closes');
 assert.match(notices[0],/Importato.*aggiornamento.*Refresh unavailable/);
 now+=5000;await pollIncomingShares(true);assert.equal(document.querySelector('dialog'),null);
});
