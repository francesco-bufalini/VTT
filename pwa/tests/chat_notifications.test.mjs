import test from 'node:test';
import assert from 'node:assert/strict';

for(const change of ['disabled','chat-visible','none']){
 test(`pending chat notification respects current state: ${change}`,async t=>{
  let release,visible=false;const notices=[];
  const ready=new Promise(resolve=>release=resolve);
  const originals=new Map();
  for(const [key,value] of Object.entries({
   self:{isSecureContext:true},window:{Notification:{}},
   Notification:{permission:'granted'},
   navigator:{serviceWorker:{ready}},
   localStorage:{getItem:()=>null,setItem:()=>{}},
   document:{get visibilityState(){return visible?'visible':'hidden';},hasFocus:()=>visible,
    querySelector:()=>visible?{closest:()=>null}:null}
  })){
   originals.set(key,Object.getOwnPropertyDescriptor(globalThis,key));
   Object.defineProperty(globalThis,key,{value,configurable:true});
  }
  t.after(()=>{for(const [key,descriptor] of originals){if(descriptor)Object.defineProperty(globalThis,key,descriptor);else delete globalThis[key];}});
  const notifications=await import('../chat_notifications.js?case='+change);
  const pending=notifications.notifyIncomingChat({kind:'chat',id:'example',text:'Hello',author:'Player'});
  if(change==='disabled')await notifications.toggleChatNotifications();
  if(change==='chat-visible')visible=true;
  release({showNotification:async(...args)=>notices.push(args)});await pending;
  assert.equal(notices.length,change==='none'?1:0);
 });
}
