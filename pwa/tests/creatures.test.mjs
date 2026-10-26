import "fake-indexeddb/auto";
import { test } from "node:test";
import assert from "node:assert/strict";
import { parseCreatureExport, makeOwnedCopy, referencedDefinitions, makeCreatureExport } from "../creature_format.js";
import { importCreatureExport, importCreatureFile, loadCreature, listCreatures,
  ownerId, openCreatureEditor, exportCreature, exportCreatureBatch, removeCreature, createCreature,
  createSubcreature, summonSubcreature, listSubcreatures } from "../creatures.js";
import { exportBackup, importBackup, putAttachment, getAttachment, listRecords } from "../storage.js";

const feat = { id: "homebrew:personal:feats:brave", name: "Coraggioso",
  source: "Personalizzato", data: { description: "Concede un oggetto",
    item: "homebrew:personal:items:charm" } };
const item = { id: "homebrew:personal:items:charm", name: "Amuleto",
  data: { type: "OTH", rarity: "rare", value: 250 } };
const creature = { id: "character_old", kind: "character", name: "Paladino",
  owner_id: "desktop_old_owner_id", transfer_revision: 7,
  linked_token_sync_id: "token_old", linked_token_name: "Originale",
  current_hp: 29, max_hp: 50,
  spell_slots_spent: [0,1,2], inventory: [{ id: item.id, quantity: 2 }],
  feats_catalog: [{ id: feat.id }], spells: ["magic_missile"],
  arbitrary_future_field: { nested: [1,2,3] } };
const exported = { format: "vtt_creature_export_v1", version: 1,
  creature, homebrew_content: [feat, item] };

test('batch export preserves portable dependencies and does not mutate source creatures',async()=>{
  const scope='batch_export_'+Date.now();
  const copy=await importCreatureExport(exported,scope);
  const before=await loadCreature(copy.creature.id,scope);
  const blob=await exportCreatureBatch([copy.creature.id],scope);
  const payload=JSON.parse(await blob.text());
  assert.equal(payload.format,'vtt_creature_batch_export_v1');
  assert.deepEqual(payload.entries[0],JSON.parse(await (await exportCreature(copy.creature.id,scope)).text()));
  assert.deepEqual(await loadCreature(copy.creature.id,scope),before);
  await assert.rejects(exportCreatureBatch([],scope),/1 a 200/);
  await assert.rejects(exportCreatureBatch(Array(201).fill(copy.creature.id),scope),/1 a 200/);
  await assert.rejects(exportCreatureBatch([copy.creature.id,'missing'],scope),/not found/);
});

test("portable VTT format retains unknown fields and nested homebrew", () => {
  const parsed = parseCreatureExport(JSON.stringify(exported));
  assert.deepEqual(parsed.creature, creature);
  const local = makeOwnedCopy(parsed.creature, "1234567890123456", "import_abc");
  assert.equal(local.id, "import_abc");
  assert.equal(local.owner_id, "1234567890123456");
  assert.equal(local.linked_token_sync_id, "");
  assert.equal(local.transfer_revision, 0);
  assert.deepEqual(local.arbitrary_future_field, creature.arbitrary_future_field);
  const wanted = referencedDefinitions(creature, new Map([[feat.id, feat], [item.id, item]]));
  assert.deepEqual(wanted.map(x => x.id), [feat.id, item.id]);
  assert.equal(makeCreatureExport(creature, wanted).format, "vtt_creature_export_v1");
  assert.throws(() => referencedDefinitions(creature, new Map([[feat.id, feat]])),
    /Missing portable homebrew dependency/);
  assert.throws(() => parseCreatureExport({ ...exported,
    homebrew_content: [{ id: "bad", data: {}, name: "X" }] }), /homebrew/);
});

test("offline import, durable edits, export and owner isolation", async () => {
  const scope = "test_offline_" + Date.now();
  const copy = await importCreatureExport(exported, scope);
  const owner = await ownerId();
  assert.equal(copy.creature.owner_id, owner);
  assert.notEqual(copy.creature.id, creature.id);
  assert.equal(copy.creature.linked_token_sync_id, "");
  assert.equal(copy.creature.linked_token_name, "");
  assert.equal(copy.creature.transfer_revision, 0);
  assert.deepEqual(copy.creature.arbitrary_future_field, creature.arbitrary_future_field);

  let fromDisk = await loadCreature(copy.creature.id, scope);
  assert.equal(fromDisk.revision, 1);
  assert.equal(fromDisk.data.current_hp, 29);
  const first = await openCreatureEditor(copy.creature.id, scope);
  const second = await openCreatureEditor(copy.creature.id, scope);
  await first.update({ current_hp: 13, inventory: [{ id: item.id, quantity: 1 }] });
  await first.update({ spell_slots_spent: [0,2,2] });
  await first.flush();
  fromDisk = await loadCreature(copy.creature.id, scope);
  assert.equal(fromDisk.revision, 3);
  assert.equal(fromDisk.data.current_hp, 13);
  assert.deepEqual(fromDisk.data.spell_slots_spent, [0,2,2]);
  assert.deepEqual(fromDisk.data.arbitrary_future_field, creature.arbitrary_future_field);
  await assert.rejects(second.update({ current_hp: 100 }), /abort|revision|AbortError/i);
  assert.equal((await loadCreature(copy.creature.id, scope)).data.current_hp, 13);

  const portable = JSON.parse(await (await exportCreature(copy.creature.id, scope)).text());
  assert.equal(portable.format, "vtt_creature_export_v1");
  assert.equal(portable.creature.current_hp, 13);
  assert.deepEqual(portable.homebrew_content.map(x => x.id),
    [feat.id, item.id]);

  const secondImport = await importCreatureFile(new Blob([JSON.stringify(exported)]), scope);
  assert.notEqual(secondImport.creature.id, copy.creature.id);
  assert.equal((await listCreatures(scope)).length, 2);
  assert.equal((await listRecords("global", "homebrew")).filter(x => x.id === feat.id).length, 1);
  assert.equal(await removeCreature(copy.creature.id, scope, fromDisk.revision), true);
  assert.equal(await loadCreature(copy.creature.id, scope), null);
  assert.equal((await listCreatures(scope)).length, 1);
});

test("multi-creature export package imports local copies with homebrew", async () => {
  const scope="test_batch_"+Date.now();
  const second={...exported,creature:{...creature,id:"character_second",name:"Paladino secondo"}};
  const packageFile={format:"vtt_creature_batch_export_v1",version:1,entries:[exported,second]};
  const imported=await importCreatureFile(new Blob([JSON.stringify(packageFile)]),scope);
  assert.equal(imported.length,2);
  const rows=await listCreatures(scope);
  assert.equal(rows.length,2);
  assert.deepEqual(rows.map(x=>x.creature.name).sort(),["Paladino","Paladino secondo"]);
  assert.ok(rows.every(x=>x.creature.owner_id===imported[0].creature.owner_id));
  assert.ok(rows.every(x=>x.creature.linked_token_sync_id===""));
  const invalid={...packageFile,entries:[exported,{...second,version:2}]};
  await assert.rejects(importCreatureFile(new Blob([JSON.stringify(invalid)]),scope));
  assert.equal((await listCreatures(scope)).length,2,"An invalid batch must fail validation before importing");
});

test("batch import rejects conflicting homebrew without writing any creature", async () => {
  const scope="test_batch_conflict_"+Date.now();
  const altered={...feat,data:{description:"Contradictory feat definition"}};
  const second={...exported,creature:{...creature,id:"different_character"},
    homebrew_content:[altered,item]};
  const file={format:"vtt_creature_batch_export_v1",version:1,entries:[exported,second]};
  await assert.rejects(importCreatureFile(new Blob([JSON.stringify(file)]),scope),
    /homebrew in conflitto/);
  assert.equal((await listCreatures(scope)).length,0,
    "A conflict in any entry must leave the entire archive untouched");
});

test("import is atomic on invalid homebrew, backup keeps local edits", async () => {
  const scope = "test_import_" + Date.now();
  const before = (await listRecords("global", "homebrew")).length;
  await assert.rejects(importCreatureExport({
    ...exported, homebrew_content: [feat, {id:"wrong", name:"Broken", data:{}}]
  }, scope), /homebrew/);
  assert.equal((await listCreatures(scope)).length, 0);
  assert.equal((await listRecords("global", "homebrew")).length, before);

  const row = await createCreature("character", "Created offline", scope);
  assert.equal(row.data.kind, "character");
  assert.equal(row.revision, 1);
  const archive = await exportBackup();
  assert.equal(archive.type, "application/json");
  const editor = await openCreatureEditor(row.id, scope);
  await editor.update({ name: "Edited since backup" });
  const existing = await loadCreature(row.id, scope);
  assert.equal(existing.revision, 2);
  await importBackup(archive);
  assert.equal((await loadCreature(row.id, scope)).data.name, "Edited since backup");
  await importBackup(archive, { overwrite: true });
  assert.equal((await loadCreature(row.id, scope)).data.name, "Created offline");

  await putAttachment("attachments", "document", "file_1", { name: "note" },
    new Blob(["content-persisted"], { type: "text/plain" }));
  const item = (await listRecords("attachments", "document"))[0];
  assert.equal(await (await getAttachment(item.digest)).text(), "content-persisted");
  const backupWithAttachment = await exportBackup();
  await importBackup(backupWithAttachment);
  const damaged = JSON.parse(await backupWithAttachment.text());
  damaged.blobs[0].base64 = "YQ==";
  await assert.rejects(importBackup(new Blob([JSON.stringify(damaged)])), /checksum/);
  assert.equal(await (await getAttachment(item.digest)).text(), "content-persisted");
});


test('functional edits compose against latest state and retain identity checks',async()=>{
 const row=await createCreature('character','Aggiornamenti atomici');
 const editor=await openCreatureEditor(row.id);
 const first=editor.update(current=>({future_count:(current.future_count||0)+1}));
 const second=editor.update(current=>({future_count:(current.future_count||0)+1}));
 await Promise.all([first,second]);
 assert.equal((await loadCreature(row.id)).data.future_count,2);
 await assert.rejects(editor.update(current=>{current.name='Mutation on a copy';return null;}),/object/);
 assert.equal(editor.read().name,'Aggiornamenti atomici');
 await assert.rejects(editor.update(()=>({id:'another-id'})),/identity/);
 await editor.update(current=>({name:current.name+' salvati'}));
 assert.equal((await loadCreature(row.id)).data.name,'Aggiornamenti atomici salvati');
});

test("subcreatures have independent sheets, remain hidden from the main roster and travel with their owner", async () => {
  const scope="linked_familiars_"+Date.now();
  const parent=await createCreature("character","Mago",scope);
  const cat=await createSubcreature(parent.id,{
    name:"Cat",source:"MM",hp:{average:2},ac:[12],speed:{walk:40},str:3,dex:15,con:10,int:3,wis:12,cha:7
  },{name:"Cat",source:"MM",spell_id:"find-familiar"},scope);
  assert.equal(cat.data.kind,"monster");
  assert.equal(cat.data.parent_creature_id,parent.id);
  assert.equal(cat.data.companion_origin_spell_id,"find-familiar");
  assert.equal(cat.data.max_hp,2);
  assert.equal((await listCreatures(scope)).length,1);
  assert.equal((await listCreatures(scope,{includeSubcreatures:true})).length,2);
  const editor=await openCreatureEditor(cat.id,scope);
  await editor.update({current_hp:1,notes:"Gatto del mago"});
  await editor.flush();
  await assert.rejects(editor.update({parent_creature_id:"different_owner"}),/parent|identity/i);
  const packaged=JSON.parse(await (await exportCreature(parent.id,scope)).text());
  assert.equal(packaged.subcreatures.length,1);
  assert.equal(packaged.subcreatures[0].current_hp,1);
  assert.equal(packaged.subcreatures[0].notes,"Gatto del mago");
  await assert.rejects(exportCreature(cat.id,scope),/proprietario/);
  const imported=await importCreatureExport(packaged,scope);
  const descendants=await listSubcreatures(imported.creature.id,scope);
  assert.equal(descendants.length,1);
  assert.notEqual(descendants[0].creature.id,cat.id);
  assert.equal(descendants[0].creature.parent_creature_id,imported.creature.id);
  assert.equal(descendants[0].creature.owner_id,await ownerId());
  assert.equal(descendants[0].creature.notes,"Gatto del mago");
  const beforeParent=await loadCreature(parent.id,scope);
  await removeCreature(parent.id,scope,beforeParent.revision);
  assert.equal(await loadCreature(parent.id,scope),null);
  assert.equal(await loadCreature(cat.id,scope),null);
  assert.equal((await listSubcreatures(imported.creature.id,scope)).length,1);
});

test("invalid subcreature packages and wrong owners cannot create orphan sheets",async()=>{
  const scope="familiar_validation_"+Date.now();
  const parent=await createCreature("character","Druido",scope);
  await assert.rejects(createSubcreature("missing",{name:"Owl"}, {},scope),/proprietaria/);
  const child=await createSubcreature(parent.id,{name:"Owl",hp:{average:1},ac:[11]},{name:"Owl"},scope);
  const original=JSON.parse(await (await exportCreature(parent.id,scope)).text());
  const damaged={...original,subcreatures:[{...original.subcreatures[0],parent_creature_id:"wrong"}]};
  await assert.rejects(importCreatureExport(damaged,scope),/subcreature/i);
  assert.equal((await listSubcreatures(parent.id,scope)).length,1);
  const stale=await loadCreature(parent.id,scope);
  const editor=await openCreatureEditor(parent.id,scope);
  await editor.update({notes:"Il proprietario è stato modificato"});
  await editor.flush();
  await assert.rejects(removeCreature(parent.id,scope,stale.revision),/changed/);
  assert.ok(await loadCreature(parent.id,scope));
  assert.ok(await loadCreature(child.id,scope));
});

test("exclusive companions are re-summoned in one stable sheet while nonexclusive spells add sheets",async()=>{
 const scope="test_companion_replacement_"+Date.now();
 const owner=await createCreature('character','Bardo',scope);
 const reference={name:'Dancing Item',source:'TCE',rule_id:'animating_performance_2014',
   feature_id:'feature:creation',template_id:'dancing_item',limit_per_owner_rule:1};
 const item=(hp,size)=>({name:'Dancing Item',source:'TCE',type:'construct',size,
   hp:{average:hp},ac:[16],str:18,dex:14,con:16,int:4,wis:10,cha:6,speed:{walk:30}});
 const first=await summonSubcreature(owner.id,item(40,'M'),reference,scope);
 const editor=await openCreatureEditor(first.id,scope);
 await editor.update({current_hp:2,notes:'Un oggetto precedente'});await editor.flush();
 const again=await summonSubcreature(owner.id,item(55,'L'),reference,scope);
 assert.equal(first.id,again.id,'A new animated item must replace the previous exclusive creature');
 assert.equal(again.data.max_hp,55);
 assert.equal(again.data.current_hp,55);
 assert.equal(again.data.size_name,'Large');
 assert.equal(again.data.notes,'','A replaced creature uses its new, fresh stat block');
 assert.equal((await listSubcreatures(owner.id,scope)).length,1);
 const undead={name:'Skeleton',source:'MM',hp:{average:13},ac:[13],size:'M',type:'undead'};
 await summonSubcreature(owner.id,undead,{spell_id:'animate_dead',rule_id:'animate_dead_2014',
   limit_per_owner_rule:0},scope);
 await summonSubcreature(owner.id,undead,{spell_id:'animate_dead',rule_id:'animate_dead_2014',
   limit_per_owner_rule:0},scope);
 assert.equal((await listSubcreatures(owner.id,scope)).length,3);
 const exported=JSON.parse(await (await exportCreature(owner.id,scope)).text());
 assert.equal(exported.subcreatures.length,3);
});
