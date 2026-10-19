import { test } from "node:test";
import assert from "node:assert/strict";
import {JSDOM} from "jsdom";
import { validateSnapshot, imageCoordinates, hitMarker,
  isAimStatus, formatElevation, TacticalViewer } from "../tactical_view.js";
function snapshot() {
  return {ok:true,format:"webp",image:"d2VicA==",width:1536,height:1536,
    token_id:"hero",snapshot_id:"snapshot123",field_feet:120,contours:[],
    markers:[{id:"enemy",name:"Nemico",x:750,y:600,radius:15}]};
}
test("elevations use signed desktop-style tactical squares",()=>{
  assert.equal(formatElevation(2),"+2 □");
  assert.equal(formatElevation(-3),"-3 □");
  assert.equal(formatElevation(0),"");
  assert.equal(validateSnapshot({...snapshot(),token_overlays:true}).token_overlays,true);
});
test("snapshot uses Android's WebP/marker schema and stable zoom mapping",()=>{
  assert.equal(validateSnapshot(snapshot()).width,1536);
  assert.throws(()=>validateSnapshot({...snapshot(),format:"png"}),/Snapshot/);
  assert.throws(()=>validateSnapshot({...snapshot(),markers:[{id:"bad",x:NaN,y:0,radius:2}]}),/Coordinate/);
  const transform={originX:40,originY:20,scale:0.25,width:1536,height:1536};
  const image=imageCoordinates(40+750*.25,20+600*.25,transform);
  assert.deepEqual(image,[750,600]);
  assert.equal(hitMarker(image,snapshot().markers).id,"enemy");
  assert.equal(hitMarker([0,0],snapshot().markers),null);
  assert.equal(imageCoordinates(-30,20,transform),null);
  assert.equal(isAimStatus({active:true,phase:"wall_arc_end"}),true);
  assert.equal(isAimStatus({active:true,phase:"target_token"}),false);
});
test("native Godot receives exact spell/attack/area targeting payloads",async()=>{
  const calls=[],charges=[];
  const viewer=new TacticalViewer({
    send:async(action,payload)=>{
      calls.push({action,payload});
      if(action==="begin_spell")return {ok:true,targeting:{active:true,phase:"point"}};
      if(action==="preview_spell")return {ok:true,preview:{valid:true,points:[[1,1],[2,2],[3,3]],affected_ids:["enemy"]}};
      if(action==="target_spell")return {ok:true,targeting:{active:false,outcome:"completed"}};
      if(action==="target_attack")return {ok:true,distance_feet:30,long_range:false};
      return {ok:true};
    },
    ownerId:async()=> "1234567890123456",
    notify:()=>{},
    onCastAccepted:async(level,spell)=>charges.push({level,spell})
  });
  viewer.root={querySelector:()=>null,querySelectorAll:()=>[]};
  viewer.tokenId="hero";
  viewer.refresh=async()=>{};
  await viewer.beginSpell({spell:{id:"fireball",name:"Fireball",source:"PHB"},slotLevel:3});
  assert.deepEqual(calls[0],{action:"begin_spell",payload:{
    token_id:"hero",owner_id:"1234567890123456",spell_id:"fireball",
    name:"Fireball",source:"PHB",slot_level:3,context:{}}});
  assert.equal(charges.length,1);
  viewer.snapshot=snapshot();
  viewer.targeting={active:true,phase:"point"};
  viewer.draw=()=>{};
  await viewer.tap([300,400]);
  assert.equal(calls[1].action,"preview_spell");
  assert.deepEqual(calls[1].payload.pixel,[300,400]);
  assert.equal(calls[1].payload.snapshot_id,"snapshot123");
  assert.ok(viewer.preview.valid);
  await viewer.control("confirm-point");
  assert.equal(calls[2].action,"target_spell");
  assert.deepEqual(calls[2].payload.pixel,[300,400]);
  viewer.targeting={active:false};
  viewer.attack={range_feet:30,melee:false};
  await viewer.tap([750,600]);
  assert.equal(calls[3].action,"target_attack");
  assert.equal(calls[3].payload.target_id,"enemy");
});
test('desktop rejection or transport failure never consumes a local casting resource',async()=>{
 for(const send of [async()=>({ok:false,error:'Rejected'}),async()=>{throw Error('Disconnected');}]){
  let charged=0;
  const viewer=new TacticalViewer({send,ownerId:async()=> 'owner',notify:()=>{},onCastAccepted:async()=>{charged++;}});
  viewer.root={querySelector:()=>null,querySelectorAll:()=>[]};viewer.tokenId='token';viewer.refresh=async()=>{};
  await assert.rejects(viewer.beginSpell({spell:{id:'test'},slotLevel:1}));
  assert.equal(charged,0);
 }
});

test("a targeted spell selects the exact token ID and confirms/cancels via native protocol",async()=>{
 const actions=[];
 const viewer=new TacticalViewer({
  send:async(name,payload)=>{
   actions.push({name,payload});
   if(name==="target_spell")return {ok:true,targeting:{active:true,phase:"multi_target_tokens",selected_ids:["enemy"]}};
   return {ok:true,targeting:{active:false,outcome:name==="finish_spell"?"completed":"cancelled"}};
  },ownerId:async()=> "local-owner",notify:()=>{}
 });
 viewer.root={querySelector:()=>null,querySelectorAll:()=>[]};
 viewer.tokenId="hero";
 viewer.snapshot=snapshot();
 viewer.targeting={active:true,phase:"multi_target_tokens",selected_ids:[]};
 viewer.refresh=async()=>{};
 viewer.draw=()=>{};
 await viewer.tap([750,600]);
 assert.deepEqual(actions[0],{name:"target_spell",payload:{token_id:"hero",
   owner_id:"local-owner",target_id:"enemy",snapshot_id:"snapshot123",pixel:[750,600]}});
 await viewer.control("finish");
 assert.equal(actions[1].name,"finish_spell");
 assert.deepEqual(actions[1].payload,{token_id:"hero",owner_id:"local-owner"});
 viewer.targeting={active:true,phase:"target_token"};
 await viewer.control("cancel");
 assert.equal(actions[2].name,"cancel_spell");
});

test("point aiming over a token previews first and confirms the same elevated target",async()=>{
 const calls=[];
 const viewer=new TacticalViewer({ownerId:async()=>"owner",notify:()=>{},send:async(name,payload)=>{
  calls.push({name,payload});return {ok:true,preview:{valid:true,points:[[0,0],[1,0],[1,1]],affected_ids:["enemy"]}};
 }});
 viewer.tokenId="hero";viewer.snapshot=snapshot();viewer.targeting={active:true,phase:"point"};
 viewer.draw=()=>{};viewer.refresh=async()=>{};
 await viewer.tap([750,600]);
 assert.equal(calls[0].name,"preview_spell");assert.equal(calls[0].payload.target_id,"enemy");
 await viewer.control("confirm-point");
 assert.equal(calls[1].name,"target_spell");assert.equal(calls[1].payload.target_id,"enemy");
 assert.deepEqual(calls[1].payload.pixel,[750,600]);
});

test("area snapshots validate finite server-projected polygons while older desktops remain supported",()=>{
 const area={points:[[0,0],[1,0],[1,1]],color:"ff9900ff",affected_ids:["enemy"]};
 assert.equal(validateSnapshot({...snapshot(),areas:[area]}).areas[0],area);
 for(const bad of [{...area,points:[[NaN,0],[1,0],[1,1]]},{...area,color:"url(bad)"},
  {...area,affected_ids:[{}]},{...area,points:[[1,2]]}])
  assert.throws(()=>validateSnapshot({...snapshot(),areas:[bad]}),/Aree/);
 assert.doesNotThrow(()=>validateSnapshot(snapshot()));
});

test("desktop-only phases suppress confirmation and refresh on server completion without recapturing unchanged maps",async()=>{
 const dom=new JSDOM('<button data-tactical="finish"></button><button data-tactical="confirm-point"></button><button data-tactical="cancel"></button>',{pretendToBeVisual:true});
 const previous=globalThis.document;globalThis.document=dom.window.document;
 try{
  let captures=0;
  const viewer=new TacticalViewer({ownerId:async()=>"owner",notify:()=>{},send:async()=>({ok:true,
   targeting:{active:true,phase:"saving_throw",waiting_desktop:true,can_finish:false},view_revision:1})});
  viewer.root=dom.window.document.body;viewer.tokenId="hero";viewer.snapshot={...snapshot(),view_revision:1};
  viewer.targeting={active:true,phase:"saving_throw",waiting_desktop:true,can_finish:false};
  viewer.updateButtons();
  assert.equal(viewer.root.querySelector('[data-tactical="finish"]').hidden,true);
  assert.equal(viewer.root.querySelector('[data-tactical="confirm-point"]').hidden,true);
  viewer.refresh=async()=>{captures++;};await viewer.poll();assert.equal(captures,0);
  viewer.send=async()=>({ok:true,targeting:{active:false,outcome:"completed"},view_revision:2});
  await viewer.poll();assert.equal(captures,1);
  // Concurrent board changes must not destroy a still-unconfirmed aim.
  viewer.targeting={active:true,phase:"point"};viewer.aimPixel=[10,10];
  viewer.send=async()=>({ok:true,targeting:viewer.targeting,view_revision:3});
  await viewer.poll();assert.equal(captures,1);
 }finally{globalThis.document=previous;dom.window.close();}
});

test("closing active targeting cancels on desktop, while disconnection preserves a retryable map",async()=>{
 let closed=false;
 const viewer=new TacticalViewer({ownerId:async()=>"owner",notify:()=>{},send:async(name)=>{
  assert.equal(name,"cancel_spell");return {ok:true,targeting:{active:false,outcome:"cancelled"}};
 }});
 viewer.targeting={active:true};viewer.close=()=>{closed=true;};
 await viewer.control("close");assert.equal(closed,true);
 closed=false;viewer.targeting={active:true};viewer.send=async()=>{throw Error("Disconnected");};
 await assert.rejects(viewer.control("close"),/Disconnected/);assert.equal(closed,false);
});
