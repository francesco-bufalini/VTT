import {IDBFactory} from 'fake-indexeddb';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
import {createCreature,ownerId,openCreatureEditor,loadCreature} from '../creatures.js';
import {exportBackup,importBackup,insertRecords,getRecord} from '../storage.js';
Object.defineProperty(globalThis,'crypto',{value:webcrypto,configurable:true});
const fresh=()=>{globalThis.indexedDB=new IDBFactory();};
async function backup(){
 fresh();const row=await createCreature('character','Viaggiatore');
 const editor=await openCreatureEditor(row.id);
 await editor.update({linked_token_sync_id:'desktop-token',linked_token_name:'Token originale',future_data:{kept:[1,2]}});
 return {row,blob:await exportBackup(),sourceOwner:await ownerId()};
}
for(const existing of [false,true])test(`restored creatures remain editable on another installation (existing=${existing})`,async()=>{
 const saved=await backup();fresh();
 const local=existing?await createCreature('character','Scheda locale'):null;
 await importBackup(saved.blob);
 const targetOwner=await ownerId();
 assert.notEqual(targetOwner,saved.sourceOwner);
 const restored=await loadCreature(saved.row.id);
 assert.equal(restored.data.owner_id,targetOwner);
 assert.equal(restored.data.linked_token_sync_id,'');
 assert.equal(restored.data.linked_token_name,'');
 assert.deepEqual(restored.data.future_data,{kept:[1,2]});
 const editor=await openCreatureEditor(saved.row.id);
 await editor.update({name:'Ripristinato e modificato'});
 assert.equal((await loadCreature(saved.row.id)).data.name,'Ripristinato e modificato');
 if(local)assert.equal((await loadCreature(local.id)).data.name,'Scheda locale');
});

test('same-installation backup keeps token links and existing edits',async()=>{
 const saved=await backup();
 const editor=await openCreatureEditor(saved.row.id);await editor.update({name:'Modifica successiva'});
 await importBackup(saved.blob);
 const kept=await loadCreature(saved.row.id);
 assert.equal(kept.data.name,'Modifica successiva');
 assert.equal(kept.data.linked_token_sync_id,'desktop-token');
 assert.equal(kept.data.owner_id,saved.sourceOwner);
 await importBackup(saved.blob,{overwrite:true});
 assert.equal((await loadCreature(saved.row.id)).data.name,'Viaggiatore');
});

test('legacy backup without owner metadata can be recovered on another browser',async()=>{
 const saved=await backup(),payload=JSON.parse(await saved.blob.text());
 delete payload.owner_id;fresh();
 await importBackup(new Blob([JSON.stringify(payload)]));
 const editor=await openCreatureEditor(saved.row.id);
 await editor.update({name:'Backup precedente recuperato'});
 assert.equal((await loadCreature(saved.row.id)).data.owner_id,await ownerId());
});


test('repeating recovery repairs old foreign-owned copies without losing their contents',async()=>{
 const saved=await backup(),payload=JSON.parse(await saved.blob.text());fresh();
 const localOwner=await ownerId();
 const original=payload.records.find(row=>row.id===saved.row.id);
 await insertRecords([{...original,data:{...original.data,name:'Copia già ripristinata'}}]);
 await importBackup(saved.blob);
 const repaired=await loadCreature(saved.row.id);
 assert.equal(repaired.data.owner_id,localOwner);
 assert.equal(repaired.data.name,'Copia già ripristinata');
 assert.equal(repaired.revision,2,'repair invalidates stale edit sessions');
 const editor=await openCreatureEditor(saved.row.id);await editor.update({current_hp:7});
 assert.equal((await loadCreature(saved.row.id)).data.current_hp,7);
});

test('backup identifies its owner but never exports pairing credentials or claims other owners',async()=>{
 const saved=await backup();
 const {setting}=await import('../storage.js');await setting('pairing-secret','private-token');
 await insertRecords([{scope:'foreign',type:'creature',id:'foreign-creature',data:{name:'Altrui',owner_id:'other-owner'}}]);
 const blob=await exportBackup(),payload=JSON.parse(await blob.text());
 assert.equal(payload.owner_id,saved.sourceOwner);
 assert.ok(!(await blob.text()).includes('private-token'));
 fresh();await importBackup(blob);
 assert.equal((await getRecord('foreign','creature','foreign-creature')).data.owner_id,'other-owner');
 assert.equal((await loadCreature(saved.row.id)).data.owner_id,await ownerId());
});

test('ambiguous legacy ownership fails before importing anything',async()=>{
 const saved=await backup(),payload=JSON.parse(await saved.blob.text());
 delete payload.owner_id;
 payload.records.push({scope:'foreign',type:'creature',id:'foreign-creature',revision:1,data:{name:'Altrui',owner_id:'other-owner'}});
 fresh();await assert.rejects(importBackup(new Blob([JSON.stringify(payload)])),/ambigui/);
 assert.equal(await loadCreature(saved.row.id),null);
});
