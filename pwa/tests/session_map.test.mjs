import {test} from "node:test";
import assert from "node:assert/strict";
import {tokenGroups,snapshotRevision,snapshotBlob,casterToken} from "../session_map.js";

test("connected casting recovers only the exact owned creature token, never a display name",()=>{
 const creature={id:"creature-a",name:"Maga"};
 const data={tokens:[{id:"foreign",creature_id:"creature-a",owner_id:"other",name:"Maga"},
  {id:"own",creature_id:"creature-a",owner_id:"owner",name:"Maga"}]};
 assert.equal(casterToken(creature,data,"owner").id,"own");
 assert.equal(casterToken(creature,{tokens:[data.tokens[0]]},"owner"),null);
 assert.equal(casterToken({...creature,linked_token_sync_id:"own"},data,"owner").id,"own");
 assert.throws(()=>casterToken(creature,{tokens:[data.tokens[1],{...data.tokens[1],id:"duplicate"}]},"owner"),/Più token/);
});

const tokens=[
  {id:"c",name:"Zanna",conditions:[]},
  {id:"a",name:"Alba",conditions:[]},
  {id:"b",name:"Bardo",conditions:[]},
  {id:"d",name:"Escluso",conditions:[]}
];
test("out of combat, all tokens are alphabetic and no combat heading",()=>{
  const groups=tokenGroups({tokens,combat:{active:false}});
  assert.deepEqual(groups.participants.map(x=>x.id),["a","b","d","c"]);
  assert.deepEqual(groups.outside,[]);
  assert.equal(groups.turnId,"");
});
test("in combat native initiative ordering wins; nonparticipants are listed separately",()=>{
  const data={tokens,combat:{active:true,round:3,active_index:2,entries:[
    {token_id:"c",name:"Zanna",initiative:20},
    {token_id:"environment",name:"Ambiente",initiative:15},
    {token_id:"a",name:"Alba",initiative:12},
    {token_id:"c",name:"Duplicate",initiative:5},
    {token_id:"b",name:"Bardo",initiative:2}
  ]}};
  const groups=tokenGroups(data);
  assert.equal(groups.active,true);
  assert.equal(groups.round,3);
  assert.deepEqual(groups.participants.map(x=>x.id),["c","a","b"]);
  assert.equal(groups.turnId,"a");
  assert.deepEqual(groups.outside.map(x=>x.id),["d"]);
});
test("empty board and deleted active token do not manufacture an initiative turn",()=>{
  const groups=tokenGroups({tokens:[],combat:{active:true,round:1,active_index:0,entries:[
    {token_id:"missing",initiative:20,name:"Missing"}]}});
  assert.equal(groups.turnId,"");
  assert.deepEqual(groups.participants,[]);
});
test("snapshot refresh key tracks desktop revision, conditions and token appearance",()=>{
  const state={revision:9,combat:{active:false,entries:[]},tokens:[{...tokens[0]}]};
  const original=snapshotRevision(state);
  assert.equal(snapshotRevision(structuredClone(state)),original);
  state.revision++;
  assert.notEqual(snapshotRevision(state),original);
  const second=snapshotRevision(state);
  state.tokens[0].conditions=["poisoned"];
  assert.notEqual(snapshotRevision(state),second);
});
test("base64 WebP becomes a typed Blob, not a CSP-blocked data URI",async()=>{
  const blob=snapshotBlob({ok:true,format:"webp",image:"d2VicA=="});
  assert.ok(blob instanceof Blob);
  assert.equal(blob.type,"image/webp");
  assert.deepEqual([...new Uint8Array(await blob.arrayBuffer())],[119,101,98,112]);
  assert.equal(snapshotBlob({ok:true,format:"png",image:"d2VicA=="}),null);
  assert.equal(snapshotBlob({ok:true,format:"webp",image:'" onload="alert(1)'}),null);
  assert.equal(snapshotBlob({ok:true,format:"webp",image:"A".repeat(1800001)}),null);
  assert.equal(snapshotBlob({ok:true,format:"webp",image:"not-base64!"}),null);
});

test("area changes and token elevations refresh the passive map without a network revision",()=>{
 const data={tokens:[{...tokens[0],position:[1,0,2]}],area_revision:10};
 let key=snapshotRevision(data);
 data.area_revision++;
 assert.notEqual(snapshotRevision(data),key);
 key=snapshotRevision(data);data.tokens[0].position[1]=5;
 assert.notEqual(snapshotRevision(data),key);
});
