import "fake-indexeddb/auto";
import { test } from "node:test";
import assert from "node:assert/strict";
import { parseCreatureExport, makeOwnedCopy, referencedDefinitions, makeCreatureExport } from "../creature_format.js";
import { importCreatureExport, importCreatureFile, loadCreature, listCreatures,
  ownerId, openCreatureEditor, exportCreature, removeCreature, createCreature } from "../creatures.js";
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
