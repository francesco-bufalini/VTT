import 'fake-indexeddb/auto';
import test from 'node:test';
import assert from 'node:assert/strict';
import {createCreature,ownerId,listSubcreatures,loadCreature,exportCreatureArchive,
 exportCreatureBatch,importCreatureFile} from '../creatures.js';
import {insertRecords,putRecord,listRecords} from '../storage.js';
import {initialCreature} from '../character_core.js';
import {MAX_CREATURE_BYTES} from '../creature_format.js';

const definition={id:'homebrew:personal:feats:archive_test',name:'Archivio di prova',
 source:'Personalizzato',data:{description:'Dipendenza da conservare'}};

test('whole archives over 200 roots preserve families, dependencies and unknown fields and restore atomically',async()=>{
 const scope='archive_large',owner=await ownerId();
 const records=Array.from({length:201},(_,i)=>({...initialCreature('character','Scheda '+i,'archive_'+i,owner),
  future_data:{index:i},...(i===0?{feats_catalog:[{id:definition.id}]}:{})}));
 const child={...initialCreature('monster','Famiglio','archive_child',owner),parent_creature_id:records[0].id};
 await insertRecords([...records,child].map(data=>({scope,type:'creature',id:data.id,data})));
 await insertRecords([{scope:'global',type:'homebrew',id:definition.id,data:definition,ifAbsent:true}]);
 const before=await listRecords(scope,'creature');
 const blob=await exportCreatureArchive(scope),payload=JSON.parse(await blob.text());
 assert.equal(payload.format,'vtt_creature_batch_export_v1');
 assert.equal(payload.entries.length,201);
 const first=payload.entries.find(row=>row.creature.id==='archive_0');
 assert.deepEqual(first.homebrew_content,[definition]);
 assert.equal(first.subcreatures[0].parent_creature_id,'archive_0');
 assert.deepEqual(first.creature.future_data,{index:0});
 assert.deepEqual(await listRecords(scope,'creature'),before,'Export never writes to the source archive');
 await assert.rejects(exportCreatureBatch(records.map(row=>row.id),scope),/1 a 200/,
  'Manual selection keeps its existing bound');
 const imported=await importCreatureFile(blob,'archive_restored');
 assert.equal(imported.length,201);
 const restored=await listRecords('archive_restored','creature');
 assert.equal(restored.length,202);
 const root=imported.find(row=>row.creature.future_data.index===0).creature;
 assert(restored.some(row=>row.data.parent_creature_id===root.id));
 assert.notEqual(root.id,'archive_0');
 const invalid=structuredClone(payload);invalid.entries.at(-1).creature.name='';
 await assert.rejects(importCreatureFile(invalid,'archive_invalid'));
 assert.deepEqual(await listRecords('archive_invalid','creature'),[],'Malformed later entries never create a partial restore');
});

test('large archive imports retain the portable byte limit before any write',async()=>{
 const record=initialCreature('character','Grande','huge_source',await ownerId());
 record.notes='x'.repeat(MAX_CREATURE_BYTES);
 const payload={format:'vtt_creature_batch_export_v1',version:1,entries:[
  {format:'vtt_creature_export_v1',version:1,creature:record}]};
 await assert.rejects(importCreatureFile(payload,'archive_oversized'),/16 MiB/);
 assert.deepEqual(await listRecords('archive_oversized','creature'),[]);
});

test('a legacy companion without a string name cannot block listing siblings or change stored data',async()=>{
 const scope='archive_legacy_family',parent=await createCreature('character','Proprietario',scope),owner=await ownerId();
 for(const [id,name] of [['legacy_child_a','Famiglio'],['legacy_child_b',null],['legacy_child_c',42]])
  await putRecord(scope,'creature',id,{...initialCreature('monster','Nome',id,owner),name,parent_creature_id:parent.id},0);
 const before=await listRecords(scope,'creature');
 const children=await listSubcreatures(parent.id,scope);
 assert.deepEqual(new Set(children.map(row=>row.creature.id)),new Set(['legacy_child_a','legacy_child_b','legacy_child_c']));
 assert.deepEqual(await listRecords(scope,'creature'),before);
 assert.equal((await loadCreature('legacy_child_b',scope)).data.name,null);
});

test('whole exports reject orphaned children rather than silently losing them',async()=>{
 const scope='archive_orphan',owner=await ownerId();
 await createCreature('character','Valida',scope);
 await putRecord(scope,'creature','orphan',{...initialCreature('monster','Orfano','orphan',owner),parent_creature_id:'missing_parent'},0);
 await assert.rejects(exportCreatureArchive(scope),/Proprietario/);
 assert.equal((await listRecords(scope,'creature')).length,2);
});
