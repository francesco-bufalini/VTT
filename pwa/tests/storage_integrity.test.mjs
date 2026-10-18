import "fake-indexeddb/auto";
import { test } from "node:test";
import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { importCreatureExport, listCreatures } from "../creatures.js";
import { insertRecords, getRecord, importBackup, pendingActions } from "../storage.js";
Object.defineProperty(globalThis,"crypto",{value:webcrypto,configurable:true});

test("existing conflicting homebrew rejects a creature import atomically",async()=>{
  const id="homebrew:personal:items:conflict";
  const definition={id,name:"Amuleto",data:{value:10}};
  await insertRecords([{scope:"global",type:"homebrew",id,data:definition}]);
  const payload={format:"vtt_creature_export_v1",version:1,
    creature:{id:"source",kind:"character",name:"Importato",inventory:[{id}]},
    homebrew_content:[{...definition,data:{value:999}}]};
  await assert.rejects(importCreatureExport(payload,"conflict-test"),/homebrew.*conflitto/i);
  assert.equal((await listCreatures("conflict-test")).length,0);
  assert.deepEqual((await getRecord("global","homebrew",id)).data,definition);
});

test("identical homebrew reuses the local entry regardless of object key order",async()=>{
  const id="homebrew:personal:items:equivalent";
  const definition={id,name:"Amuleto",data:{value:10,properties:["a","b"]}};
  await insertRecords([{scope:"global",type:"homebrew",id,data:definition}]);
  await insertRecords([{scope:"global",type:"homebrew",id,ifAbsent:true,
    data:{data:{properties:["a","b"],value:10},name:"Amuleto",id}}]);
  assert.equal((await getRecord("global","homebrew",id)).revision,1);
});

for(const overwrite of [false,true])test(`backup rejects duplicate record IDs before writing (overwrite=${overwrite})`,async()=>{
  const scope="duplicate-"+overwrite;
  const record={scope,type:"creature",id:"same",revision:1,updatedAt:1,data:{name:"Prima"}};
  const content={format:"vtt-pwa-backup",version:1,records:[record,{...record,data:{name:"Seconda"}}],blobs:[],outbox:[]};
  await assert.rejects(importBackup(new Blob([JSON.stringify(content)]),{overwrite}),/duplicate/i);
  assert.equal(await getRecord(scope,"creature","same"),null);
});


test("conflicting dependency rolls back earlier writes in the same batch",async()=>{
  await insertRecords([{scope:"global",type:"homebrew",id:"occupied",data:{name:"Locale"}}]);
  await assert.rejects(insertRecords([
    {scope:"rollback",type:"creature",id:"new",data:{name:"Nuova"}},
    {scope:"global",type:"homebrew",id:"new-dependency",data:{name:"Nuova"}},
    {scope:"global",type:"homebrew",id:"occupied",data:{name:"Diversa"},ifAbsent:true}
  ]),/conflitto/);
  assert.equal(await getRecord("rollback","creature","new"),null);
  assert.equal(await getRecord("global","homebrew","new-dependency"),null);
});

test("backup rejects duplicate pending actions without importing records",async()=>{
  const scope="duplicate-actions";
  const action={id:"repeated",scope,action:"chat_send",payload:{message:"A"}};
  const content={format:"vtt-pwa-backup",version:1,blobs:[],
    records:[{scope,type:"creature",id:"new",revision:1,data:{name:"Nuova"}}],
    outbox:[action,{...action,payload:{message:"B"}}]};
  await assert.rejects(importBackup(new Blob([JSON.stringify(content)])),/Duplicate action/);
  assert.equal(await getRecord(scope,"creature","new"),null);
  assert.deepEqual(await pendingActions(scope),[]);
});


test('backup merge rejects conflicting homebrew and rolls back new creatures',async()=>{
  const id='homebrew:personal:items:backup-conflict';
  const local={scope:'global',type:'homebrew',id,data:{id,name:'Amuleto locale',data:{value:10}}};
  await insertRecords([local]);
  const archive={format:'vtt-pwa-backup',version:1,blobs:[],outbox:[],records:[
    {scope:'backup-conflict',type:'creature',id:'new',revision:1,data:{name:'Importato'}},
    {...local,revision:1,data:{...local.data,name:'Amuleto differente'}}
  ]};
  const file=new Blob([JSON.stringify(archive)]);
  await assert.rejects(importBackup(file),/homebrew.*conflitto/i);
  assert.equal(await getRecord('backup-conflict','creature','new'),null);
  assert.deepEqual((await getRecord('global','homebrew',id)).data,local.data);
  await importBackup(file,{overwrite:true});
  assert.equal((await getRecord('global','homebrew',id)).data.name,'Amuleto differente');
});
