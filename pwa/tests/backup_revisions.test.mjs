import {IDBFactory} from 'fake-indexeddb';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
import {createCreature,openCreatureEditor,loadCreature,saveHomebrewDefinition,editHomebrewDefinition} from '../creatures.js';
import {exportBackup,importBackup,getRecord,openStorage} from '../storage.js';
Object.defineProperty(globalThis,'crypto',{value:webcrypto,configurable:true});
const fresh=()=>{globalThis.indexedDB=new IDBFactory();};

test('overwriting a backup must invalidate already open creature editors',async()=>{
 fresh();const saved=await createCreature('character','Originale');
 const stale=await openCreatureEditor(saved.id),archive=await exportBackup();
 const active=await openCreatureEditor(saved.id);await active.update({name:'Modifica successiva'});
 const before=await loadCreature(saved.id);
 await importBackup(archive,{overwrite:true});
 const restored=await loadCreature(saved.id);
 assert.equal(restored.data.name,'Originale');
 assert.ok(restored.revision>before.revision,'Restoration must advance the live revision');
 await assert.rejects(stale.update({name:'Scrittura obsoleta'}));
 assert.equal((await loadCreature(saved.id)).data.name,'Originale');
 const next=await openCreatureEditor(saved.id);await next.update({name:'Modifica autorizzata'});
 assert.equal((await loadCreature(saved.id)).data.name,'Modifica autorizzata');
});

test('homebrew restore rejects stale edits and advances on repeated restoration',async()=>{
 fresh();const definition={id:'homebrew:personal:feats:restore_revision',name:'Originale',data:{description:'Prima'}};
 await saveHomebrewDefinition(definition);
 const old=await getRecord('global','homebrew',definition.id),archive=await exportBackup();
 await editHomebrewDefinition({...definition,name:'Modificata'},old.revision);
 for(let i=0;i<2;i++){
  const before=await getRecord('global','homebrew',definition.id);
  await importBackup(archive,{overwrite:true});
  const restored=await getRecord('global','homebrew',definition.id);
  assert.ok(restored.revision>before.revision);
 }
 await assert.rejects(editHomebrewDefinition({...definition,name:'Obsoleta'},old.revision));
 assert.equal((await getRecord('global','homebrew',definition.id)).data.name,'Originale');
});

for(const revision of [0,-1,1.5,'1',null,undefined,Number.MAX_SAFE_INTEGER,Number.MAX_SAFE_INTEGER+1]){
 test('invalid backup revision is rejected atomically: '+String(revision),async()=>{
  fresh();const saved=await createCreature('character','Esistente'),archive=JSON.parse(await (await exportBackup()).text());
  archive.records[0].data.name='Non deve essere scritta';
  archive.records.push({scope:'global',type:'homebrew',id:'homebrew:personal:feats:invalid_revision',revision,
   data:{id:'homebrew:personal:feats:invalid_revision',name:'Non valido',data:{}}});
  await assert.rejects(importBackup(new Blob([JSON.stringify(archive)]),{overwrite:true}),/revision/i);
  assert.equal((await loadCreature(saved.id)).data.name,'Esistente');
  assert.equal(await getRecord('global','homebrew','homebrew:personal:feats:invalid_revision'),null);
 });
}


test('revision exhaustion aborts the whole overwrite transaction',async()=>{
 fresh();const saved=await createCreature('character','Da preservare');
 const archive=JSON.parse(await (await exportBackup()).text());
 archive.records.unshift({scope:'new',type:'note',id:'not-written',revision:1,data:{text:'Nuovo'}});
 const original=await loadCreature(saved.id);
 const db=await openStorage();
 try{
  const tx=db.transaction('records','readwrite');
  tx.objectStore('records').put({...original,revision:Number.MAX_SAFE_INTEGER});
  await new Promise((resolve,reject)=>{tx.oncomplete=resolve;tx.onabort=()=>reject(tx.error);tx.onerror=()=>reject(tx.error);});
 }finally{db.close();}
 await assert.rejects(importBackup(new Blob([JSON.stringify(archive)]),{overwrite:true}),/revision exhausted/);
 assert.equal(await getRecord('new','note','not-written'),null);
 const kept=await loadCreature(saved.id);
 assert.equal(kept.revision,Number.MAX_SAFE_INTEGER);
 assert.equal(kept.data.name,'Da preservare');
});
