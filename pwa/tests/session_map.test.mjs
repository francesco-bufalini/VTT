import {test} from "node:test";
import assert from "node:assert/strict";
import {tokenGroups,snapshotRevision,snapshotSource} from "../session_map.js";

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
test("only a bounded valid WebP payload can be embedded in the UI",()=>{
  assert.equal(snapshotSource({ok:true,format:"webp",image:"d2VicA=="}),"data:image/webp;base64,d2VicA==");
  assert.equal(snapshotSource({ok:true,format:"png",image:"d2VicA=="}),"");
  assert.equal(snapshotSource({ok:true,format:"webp",image:'" onload="alert(1)'}),"");
  assert.equal(snapshotSource({ok:true,format:"webp",image:"A".repeat(1800001)}),"");
});
