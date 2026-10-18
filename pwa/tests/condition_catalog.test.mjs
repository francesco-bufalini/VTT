import {test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {CORE_CONDITIONS, conditionOptions, conditionLabel} from "../condition_catalog.js";

const nativeFile=path=>readFileSync(fileURLToPath(new URL(path,import.meta.url)),"utf8");

test("mobile canonical condition IDs match both native condition declarations",()=>{
  const content=nativeFile("../../vtt/content_catalog.gd");
  const legacy=content.match(/const LEGACY_CONDITIONS := \[([\s\S]*?)\n\]/)?.[1]||"";
  const nativeIds=[...legacy.matchAll(/"id": "([^"]+)"/g)].map(hit=>hit[1]);
  const board=nativeFile("../../network/board_sync.gd");
  const tokenList=board.match(/const TOKEN_CONDITIONS := \[([\s\S]*?)\n\]/)?.[1]||"";
  const tokenIds=[...tokenList.matchAll(/"([^"]+)"/g)].map(hit=>hit[1]);
  assert.equal(nativeIds.length,20);
  assert.deepEqual(CORE_CONDITIONS,nativeIds);
  assert.deepEqual(CORE_CONDITIONS,tokenIds);
});

test("Italian labels are sorted but persisted IDs never change",()=>{
  const entries=conditionOptions(null,"2014");
  const collator=new Intl.Collator("it",{sensitivity:"base"});
  assert.equal(entries.length,20);
  assert.ok(entries.every((row,index)=>!index||collator.compare(entries[index-1].label,row.label)<=0));
  assert.equal(entries.find(row=>row.id==="grappled")?.label,"Afferrato");
  assert.equal(entries.find(row=>row.id==="restrained")?.label,"Trattenuto");
  assert.notEqual(conditionLabel("grappled"),conditionLabel("restrained"));
});

test("live catalog mirrors native edition-specific and custom IDs without translating storage",()=>{
  const homebrew="homebrew:campaign:conditions:icy_grip";
  const catalog={editions:{
    "2014":[{id:"restrained",name:"Restrained",category:"conditions"},{id:"grappled",name:"Grappled",category:"conditions"},{id:homebrew,name:"Morsa gelida",category:"conditions"}],
    "2024":[{id:"5etools:effects:xphb:bloodied",name:"Bloodied",category:"effects"},{id:"grappled",name:"Grappled",category:"conditions"}]
  }};
  const rows=conditionOptions(catalog,"2014");
  assert.deepEqual(rows.map(row=>row.id),["grappled",homebrew,"restrained"]);
  assert.deepEqual(rows.map(row=>row.label),["Afferrato","Morsa gelida","Trattenuto"]);
  assert.equal(conditionOptions(catalog,"2024").find(row=>row.id==="5etools:effects:xphb:bloodied")?.label,"Sanguinante");
  assert.ok(conditionOptions(null,"2014",[homebrew]).some(row=>row.id===homebrew));
});
