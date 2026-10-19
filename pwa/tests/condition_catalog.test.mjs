import {test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {CORE_CONDITIONS, conditionOptions, conditionLabel, conditionCatalogFrom5etools, mergeConditionCatalog, conditionDescriptionHtml} from "../condition_catalog.js";

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

test("bundled 5etools catalog exposes edition-specific diseases and original rules",()=>{
  const json=JSON.parse(nativeFile("../../vtt/data/effects_5etools.json"));
  const catalog=conditionCatalogFrom5etools(json);
  const choices2014=conditionOptions(catalog,"2014");
  const choices2024=conditionOptions(catalog,"2024");
  const arcane=choices2014.find(row=>row.name==="Arcane Blight");
  assert.equal(arcane?.category,"diseases");
  assert.equal(arcane?.source,"IDRotF");
  assert.ok(choices2014.some(row=>row.id==="grappled"&&row.label==="Afferrato"));
  assert.ok(choices2014.some(row=>row.id==="restrained"&&row.label==="Trattenuto"));
  assert.ok(choices2024.some(row=>row.id==="5etools:effects:xphb:bloodied"&&row.label==="Sanguinante"));
  assert.ok(choices2024.some(row=>row.category==="diseases"&&row.name==="Cackle Fever"));
  const grappled=choices2014.find(row=>row.id==="grappled");
  const restrained=choices2014.find(row=>row.id==="restrained");
  assert.match(conditionDescriptionHtml(grappled),/speed becomes 0/);
  assert.match(conditionDescriptionHtml(restrained),/Attack rolls against the creature have advantage/);
  assert.doesNotMatch(conditionDescriptionHtml(grappled),/\{@condition/);
  assert.match(conditionDescriptionHtml(arcane),/IDRotF/);
});

test("online homebrew descriptions merge with bundled disease catalog",()=>{
  const local=conditionCatalogFrom5etools(JSON.parse(nativeFile("../../vtt/data/effects_5etools.json")));
  const id="homebrew:campaign:diseases:moonfever";
  const desktop={editions:{"2014":[{id,name:"Febbre lunare",category:"diseases",source:"Campagna",
    entries:["Il bersaglio soffre una febbre magica."]}],"2024":[]}};
  const merged=mergeConditionCatalog(local,desktop);
  assert.equal(conditionOptions(merged,"2014").find(row=>row.id===id)?.label,"Febbre lunare");
  assert.match(conditionDescriptionHtml(conditionOptions(merged,"2014").find(row=>row.id===id)),/febbre magica/);
  assert.ok(conditionOptions(merged,"2014").some(row=>row.name==="Arcane Blight"));
  assert.ok(conditionOptions(local,"2014").every(row=>row.id!==id));
});

test("5etools status popup safely escapes homebrew content and renders exhaustion table",()=>{
  const html=conditionDescriptionHtml({id:"homebrew:campaign:conditions:unsafe",name:"Unsafe",
    category:"conditions",source:"User",entries:["<script>alert(1)</script> {@condition incapacitated} & friends"]});
  assert.doesNotMatch(html,/<script>/);
  assert.match(html,/&lt;script&gt;/);
  assert.match(html,/incapacitated &amp; friends/);
  const bundled=conditionCatalogFrom5etools(JSON.parse(nativeFile("../../vtt/data/effects_5etools.json")));
  const exhaustion=conditionOptions(bundled,"2014").find(row=>row.id==="exhaustion");
  assert.match(conditionDescriptionHtml(exhaustion),/<table>/);
  assert.match(conditionDescriptionHtml(exhaustion),/Speed halved/);
});
