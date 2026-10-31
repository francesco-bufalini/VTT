import {test} from "node:test";
import assert from "node:assert/strict";
import {tokenGroups,tokenOwnershipGlyphKey,snapshotRevision,snapshotBlob,casterToken,SessionMapViewer} from "../session_map.js";

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
test("environment round stays in native order and is never a selectable token",()=>{
  const data={tokens,combat:{active:true,round:2,active_index:1,entries:[
    {token_id:"c",name:"Zanna"},
    {token_id:"",name:"Turno ambientale",initiative:20,environment:true},
    {token_id:"a",name:"Alba"}
  ]}};
  let groups=tokenGroups(data);
  assert.deepEqual(groups.participants.map(x=>x.name),["Zanna","Turno ambientale","Alba"]);
  assert.equal(groups.activeEnvironment,true);
  assert.equal(groups.turnId,"");
  assert.deepEqual(groups.participants[1],{id:"",name:"Turno ambientale",initiative:20,environment:true});
  assert.deepEqual(groups.outside.map(x=>x.id),["b","d"]);
  data.combat.active_index=0;
  groups=tokenGroups(data);
  assert.equal(groups.activeEnvironment,false);
  assert.equal(groups.turnId,"c");
  data.combat.entries=[data.combat.entries[1],data.combat.entries[0]];
  data.combat.active_index=0;
  groups=tokenGroups(data);
  assert.deepEqual(groups.participants.map(x=>x.name),["Turno ambientale","Zanna"]);
  assert.equal(groups.activeEnvironment,true);
  assert.equal(tokenGroups({tokens:[],combat:{active:true,active_index:0,entries:data.combat.entries}}).participants[0].environment,true);
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

test("party, size and miniature changes invalidate passive map snapshots",()=>{
 const token={id:"a",name:"Orco",conditions:[],party_id:"Nord",size_name:"Medium",
   footprint_cells:1,current_miniature_id:"mini-a"};
 const data={tokens:[token]};
 let key=snapshotRevision(data);
 token.party_id="Sud";assert.notEqual(snapshotRevision(data),key);
 key=snapshotRevision(data);
 token.size_name="Large";token.footprint_cells=2;
 assert.notEqual(snapshotRevision(data),key);
 key=snapshotRevision(data);
 token.current_miniature_id="mini-b";
 assert.notEqual(snapshotRevision(data),key);
});

test("session map zoom stays attached to its own viewport",()=>{
 const viewer=new SessionMapViewer();
 viewer.canvas={clientWidth:320,clientHeight:320,isConnected:false};
 viewer.zoomAt(2,160,160);
 assert.equal(viewer.zoom,2);
 assert.equal(viewer.panX,0);
 assert.equal(viewer.panY,0);
 viewer.zoomAt(2,80,80);
 assert.equal(viewer.zoom,4);
 assert.equal(viewer.panX,80);
 assert.equal(viewer.panY,80);
 viewer.zoomAt(100,160,160);
 assert.equal(viewer.zoom,4,"pinch zoom clamps at its source-resolution budget");
 viewer.reset();
 assert.equal(viewer.zoom,1);
 assert.equal(viewer.panX,0);
 assert.equal(viewer.panY,0);
});

test("roster icons distinguish only tokens explicitly linked to a local sheet",()=>{
 const local=[{id:"character-1",name:"Maga",linked_token_sync_id:"own"}];
 assert.equal(tokenOwnershipGlyphKey({id:"own",name:"Maga"},local),"map");
 assert.equal(tokenOwnershipGlyphKey({id:"other",name:"Maga"},local),"poison",
   "matching names cannot make a foreign token controllable");
 assert.equal(tokenOwnershipGlyphKey({id:"free",free:true},local),"poison");
 assert.equal(tokenOwnershipGlyphKey({id:""},local),"poison");
 assert.equal(tokenOwnershipGlyphKey(null,local),"poison");
});
