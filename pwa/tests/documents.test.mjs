import "fake-indexeddb/auto";
import {test} from "node:test";
import assert from "node:assert/strict";
import {webcrypto} from "node:crypto";
import {createCreature,openCreatureEditor,saveHomebrewDefinition,
  editHomebrewDefinition,exportCreature,importCreatureExport} from "../creatures.js";
import {getRecord} from "../storage.js";
import {parseCreatureExport} from "../creature_format.js";
import {isDocument,createDocumentDefinition,createOwnedDocument,
  documentInfo,editDocumentDefinition,documentStyle} from "../documents.js";

Object.defineProperty(globalThis,"crypto",{value:webcrypto,configurable:true});

test("native document homebrew is embedded in creature export and survives import",async()=>{
  const created=await createCreature("character","Archivista");
  const id="doc_"+crypto.randomUUID().replace(/-/g,"");
  const definition=createDocumentDefinition(id,"Lettera di prova","Testo di origine");
  assert.equal(definition.id,"homebrew:vttdoc:documents:"+id);
  await saveHomebrewDefinition(definition);
  const item=createOwnedDocument(definition,"owned_doc_"+id,1600000000);
  assert.ok(isDocument(item));
  assert.equal(item.display_style,"pergamena");
  assert.equal(item.added_at,1600000000);
  const editor=await openCreatureEditor(created.id);
  await editor.update({inventory:[item]});
  await editor.flush();
  const blob=await exportCreature(created.id);
  const payload=parseCreatureExport(await blob.text());
  assert.equal(payload.homebrew.length,1);
  assert.equal(payload.homebrew[0].id,definition.id);
  assert.equal(payload.homebrew[0].data.description,"Testo di origine");
  const imported=await importCreatureExport(JSON.parse(await blob.text()));
  assert.equal(imported.creature.inventory[0].id,item.id);
  assert.equal(imported.creature.inventory[0].added_at,1600000000);
  assert.notEqual(imported.creature.id,created.id);
});

test("document title and body are revisioned while instance style stays per copy",async()=>{
  const id="doc_"+crypto.randomUUID().replace(/-/g,"");
  const definition=createDocumentDefinition(id);
  await saveHomebrewDefinition(definition);
  const old=await getRecord("global","homebrew",definition.id);
  const edited=editDocumentDefinition(old.data," Nuovo titolo ","Riga 1\nRiga 2");
  await editHomebrewDefinition(edited,old.revision);
  const current=await getRecord("global","homebrew",definition.id);
  assert.equal(current.data.name,"Nuovo titolo");
  assert.equal(documentInfo({},current.data).body,"Riga 1\nRiga 2");
  assert.equal(documentStyle("lettera"),"lettera");
  assert.equal(documentStyle("malformed"),"pergamena");
  const a=createOwnedDocument(current.data,"owned_doc_a");
  const b={...createOwnedDocument(current.data,"owned_doc_b"),display_style:"lettera"};
  assert.equal(documentInfo(a,current.data).style,"pergamena");
  assert.equal(documentInfo(b,current.data).style,"lettera");
  assert.equal(a.id,b.id,"copies share the same definition");
  await assert.rejects(editHomebrewDefinition(edited,old.revision));
});
test("document limits and identifiers match native invariants",()=>{
  assert.throws(()=>createDocumentDefinition("invalid"),/Identificativo/);
  assert.throws(()=>editDocumentDefinition(createDocumentDefinition("doc_a"),"x".repeat(161),""),/160/);
  assert.throws(()=>editDocumentDefinition(createDocumentDefinition("doc_b"),"","x".repeat(3501)),/3500/);
  assert.equal(editDocumentDefinition(createDocumentDefinition("doc_c"),"   ","").name,"Senza titolo");
  assert.ok(isDocument({id:"homebrew:custom:documents:abc"}));
});
