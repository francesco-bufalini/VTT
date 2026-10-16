import { test } from "node:test";
import assert from "node:assert/strict";
import { validateSnapshot, imageCoordinates, hitMarker,
  isAimStatus, TacticalViewer } from "../tactical_view.js";
function snapshot() {
  return {ok:true,format:"webp",image:"d2VicA==",width:1536,height:1536,
    token_id:"hero",snapshot_id:"snapshot123",field_feet:120,contours:[],
    markers:[{id:"enemy",name:"Nemico",x:750,y:600,radius:15}]};
}
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
