import "fake-indexeddb/auto";
import {test} from "node:test";
import assert from "node:assert/strict";
import {webcrypto} from "node:crypto";
import {createCreature,loadCreature,openCreatureEditor,linkedTokenStatusPatch,syncLinkedTokenStatuses}
  from "../creatures.js";
if(!globalThis.crypto)Object.defineProperty(globalThis,"crypto",{value:webcrypto});

const token=(effects=["spell:bless|phb"])=>({
  id:"token-hero",conditions:["poisoned","concentrating"],
  concentrating_spell_id:"spell:bless|phb",active_spell_ids:effects,
  current_miniature_id:"mini:hero",default_miniature_id:"mini:default"
});
test("public effects are applied only to the linked owned creature, not all map tokens",()=>{
 const own={id:"own",linked_token_sync_id:"token-hero",conditions:[],
   proficiency_origins:[],active_spell_context:{}};
 const hit=linkedTokenStatusPatch(own,token(),[{id:"spell:bless|phb",name:"Bless"}]);
 assert.deepEqual(hit.conditions,["poisoned","concentrating"]);
 assert.equal(hit.concentrating_spell_id,"spell:bless|phb");
 assert.deepEqual(hit.proficiency_origins,[{
   id:"spell:spell:bless|phb",group:"spell",name:"Incantesimo · Bless",
   disabled:false,automatic:false,applied:true
 }]);
 assert.deepEqual(linkedTokenStatusPatch({...own,linked_token_sync_id:"another"},token()),{});
 assert.deepEqual(linkedTokenStatusPatch(own,{id:"token-hero",name:"Missing status"}),{});
});

test("Android-compatible dispel removes only applied spell origins and their context",()=>{
 const original={linked_token_sync_id:"token-hero",
   proficiency_origins:[
     {id:"spell:spell:old",group:"spell",applied:true,disabled:false},
     {id:"spell:spell:feature",group:"spell",applied:false},
     {id:"feat|phb|durable",group:"feat",applied:true}
   ],active_spell_context:{"spell:old":{bonus_dice:"1d4"}},conditions:["blinded"]};
 const result=linkedTokenStatusPatch(original,{
   id:"token-hero",active_spell_ids:[],conditions:["poisoned"],concentrating_spell_id:""
 });
 assert.equal(result.proficiency_origins.length,2);
 assert.ok(result.proficiency_origins.some(row=>row.id==="spell:spell:feature"));
 assert.ok(result.proficiency_origins.some(row=>row.id==="feat|phb|durable"));
 assert.deepEqual(result.active_spell_context,{});
 assert.deepEqual(result.conditions,["poisoned"]);
 assert.deepEqual(original.active_spell_context,{"spell:old":{bonus_dice:"1d4"}});
});

test("map changes persist through the live editor without invalidating IndexedDB CAS",async()=>{
 const scope="targeting-test-"+crypto.randomUUID();
 const creature=await createCreature("character","CasualTarget",scope);
 const editor=await openCreatureEditor(creature.id,scope);
 await editor.update({linked_token_sync_id:"token-hero",
   proficiency_origins:[{id:"spell:spell:old",group:"spell",applied:true}],
   active_spell_context:{"spell:old":{bonus_dice:"1d4"}}});
 const map={tokens:[token(["spell:bless|phb"]),{
   id:"token-elsewhere",active_spell_ids:["spell:hex|phb"],conditions:["stunned"]
 }]};
 const options={scope,liveEditor:{id:creature.id,editor},spells:[{id:"spell:bless|phb",name:"Bless"}]};
 assert.deepEqual(await syncLinkedTokenStatuses(map,options),[creature.id]);
 assert.deepEqual(await syncLinkedTokenStatuses(map,options),[]);
 await editor.update({notes:"Una modifica locale non deve fallire dopo la ricezione degli effetti."});
 let updated=(await loadCreature(creature.id,scope)).data;
 assert.equal(updated.notes.startsWith("Una modifica"),true);
 assert.equal(updated.proficiency_origins.length,1);
 assert.equal(updated.proficiency_origins[0].id,"spell:spell:bless|phb");
 assert.deepEqual(updated.active_spell_context,{});
 assert.equal(updated.concentrating_spell_id,"spell:bless|phb");
 assert.equal(updated.current_miniature_id,"mini:hero");
 map.tokens[0]=token([]);
 assert.deepEqual(await syncLinkedTokenStatuses(map,options),[creature.id]);
 updated=(await loadCreature(creature.id,scope)).data;
 assert.equal(updated.proficiency_origins.length,0);
 assert.equal(updated.notes.startsWith("Una modifica"),true);
 assert.deepEqual(await syncLinkedTokenStatuses({tokens:[]},options),[]);
});

test("desktop faction, size, miniature and conditions update the linked sheet",()=>{
 const own={id:"own",linked_token_sync_id:"token-hero",party_id:"Vecchi alleati",
   size_name:"Medium",footprint:1,current_miniature_id:"mini:old",
   conditions:[],proficiency_origins:[]};
 const sceneToken={id:"token-hero",party_id:"Culto del Drago",size_name:"Large",
   footprint_cells:2,current_miniature_id:"mini:new",conditions:["grappled"],
   active_spell_ids:[],concentrating_spell_id:""};
 const patch=linkedTokenStatusPatch(own,sceneToken);
 assert.equal(patch.party_id,"Culto del Drago");
 assert.equal(patch.size_name,"Large");
 assert.equal(patch.footprint,2);
 assert.equal(patch.current_miniature_id,"mini:new");
 assert.deepEqual(patch.conditions,["grappled"]);
 const current={...own,...patch};
 assert.deepEqual(linkedTokenStatusPatch(current,sceneToken),{});
 sceneToken.party_id="";
 assert.equal(linkedTokenStatusPatch(current,sceneToken).party_id,"",
   "clearing a faction must also synchronize");
});
