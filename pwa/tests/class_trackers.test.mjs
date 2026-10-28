import {test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {classResourceTrackers} from "../class_trackers.js";
import {changeTrackerUses} from "../character_core.js";
import {recoveryPatch} from "../native_sheet.js";

const index=JSON.parse(readFileSync(fileURLToPath(
  new URL("../catalog/class_mechanics.json",import.meta.url)),"utf8"));
const overrides={classes:[
 {class:"Bard",source:"PHB",resources:[{name:"Bardic Inspiration",minimum:1,
  steps:[{level:1,value:"cha_mod",reset:"long_rest"},
    {level:5,value:"cha_mod",reset:"short_rest"}]}]},
 {class:"Druid",source:"PHB",resources:[{name:"Wild Shape",
  steps:[{level:2,value:"2",reset:"short_rest"}]}]},
 {class:"Fighter",source:"PHB",resources:[{name:"Superiority Die",subclass:"Battle Master",
  steps:[{level:3,value:"4",reset:"short_rest"}]}]},
 {class:"Barbarian",source:"PHB",resources:[{name:"Rage",column:"Rages",
  steps:[{level:1,value:"2",reset:"long_rest"},
    {level:20,value:"6",reset:"long_rest"}]}]}
]};

test("class trackers follow source-qualified numeric steps and recharge without special UI code",()=>{
 const bard={kind:"character",level:5,abilities:{cha:16},
  classes:[{name:"Bard",source:"PHB",level:5}]};
 const rows=classResourceTrackers(bard,index,overrides,{cha:3});
 const inspiration=rows.find(x=>x.name==="Bardic Inspiration");
 assert.ok(inspiration);
 assert.equal(inspiration.id,"class:bard:phb:bardic_inspiration");
 assert.equal(inspiration.max,3);
 assert.equal(inspiration.recharge,"short_rest");
 assert.equal(inspiration.automatic,true);
 const lower=classResourceTrackers({...bard,level:3,classes:[{name:"Bard",source:"PHB",level:3}]},
  index,overrides,{cha:2}).find(x=>x.name==="Bardic Inspiration");
 assert.equal(lower.max,2);
 assert.equal(lower.recharge,"long_rest");
 let state={...bard,resource_tracker_spent:{[inspiration.id]:2}};
 state={...state,...changeTrackerUses(state,inspiration.id,1,rows)};
 assert.equal(state.resource_tracker_spent[inspiration.id],3);
 state={...state,...recoveryPatch(state,"short_rest",rows)};
 assert.equal(state.resource_tracker_spent[inspiration.id],undefined);
});
test("Wild Shape and subclass maneuvers appear only when unlocked",()=>{
 const druid={kind:"character",level:2,classes:[{name:"Druid",source:"PHB",level:2}]};
 const rows=classResourceTrackers(druid,index,overrides);
 assert.equal(rows.find(x=>x.name==="Wild Shape")?.recharge,"short_rest");
 assert.equal(rows.find(x=>x.name==="Wild Shape")?.max,2);
 assert.equal(classResourceTrackers({...druid,level:1,classes:[{name:"Druid",source:"PHB",level:1}]},index,overrides)
   .some(x=>x.name==="Wild Shape"),false);
 const fighter={kind:"character",level:3,
  classes:[{name:"Fighter",source:"PHB",level:3,subclass:"Battle Master"}]};
 assert.equal(classResourceTrackers(fighter,index,overrides)
   .find(x=>x.name==="Superiority Die")?.max,4);
 fighter.classes[0].subclass="Champion";
 assert.equal(classResourceTrackers(fighter,index,overrides)
   .some(x=>x.name==="Superiority Die"),false);
});
test("native unlimited table entries cannot be overwritten by finite supplements",()=>{
 const low={kind:"character",level:1,classes:[{name:"Barbarian",source:"PHB",level:1}]};
 const early=classResourceTrackers(low,index,overrides);
 assert.ok(early.some(x=>x.id==="class:barbarian:phb:rages"&&x.max===2));
 const high={...low,level:20,classes:[{name:"Barbarian",source:"PHB",level:20}]};
 assert.equal(classResourceTrackers(high,index,overrides)
  .some(x=>x.id==="class:barbarian:phb:rages"),false);
});
test("2024 Fighter uses the source-qualified Action Surge and Indomitable steps",()=>{
 for(const [level,surgeMax,indomitableMax] of [[2,1,0],[9,1,1],[13,1,2],[17,2,3]]){
  const record={kind:"character",level,classes:[{name:"Fighter",source:"XPHB",level}]};
  const rows=classResourceTrackers(record,index,{classes:index.resource_overrides});
  const surge=rows.find(row=>row.name==="Action Surge");
  const indomitable=rows.find(row=>row.name==="Indomitable");
  assert.equal(surge?.id,"class:fighter:xphb:action_surge");
  assert.equal(surge?.max,surgeMax);
  assert.equal(surge?.recharge,"short_rest");
  assert.equal(indomitable?.max,indomitableMax||undefined);
  if(indomitableMax){
   assert.equal(indomitable.id,"class:fighter:xphb:indomitable");
   assert.equal(indomitable.recharge,"long_rest");
  }
 }
});
test("2024 Paladin, Sorcerer and Wizard counters use shared source-qualified data",()=>{
 const mixed={kind:"character",level:10,classes:[
  {name:"Paladin",source:"XPHB",level:3},
  {name:"Wizard",source:"XPHB",level:7}]};
 const rows=classResourceTrackers(mixed,index,{classes:index.resource_overrides});
 const lay=rows.find(row=>row.name==="Lay on Hands");
 assert.equal(lay?.id,"class:paladin:xphb:lay_on_hands");
 assert.equal(lay?.max,15);
 assert.equal(lay?.origin,"Lay on Hands");
 assert.equal(lay?.recharge,"long_rest");
 const arcane=rows.find(row=>row.name==="Arcane Recovery");
 assert.equal(arcane?.id,"class:wizard:xphb:arcane_recovery");
 assert.equal(arcane?.max,1);
 assert.equal(arcane?.recharge,"long_rest");
 const sorcerer={kind:"character",level:1,classes:[{name:"Sorcerer",source:"XPHB",level:1}]};
 const innate=classResourceTrackers(sorcerer,index,{classes:index.resource_overrides})
  .find(row=>row.name==="Innate Sorcery");
 assert.equal(innate?.id,"class:sorcerer:xphb:innate_sorcery");
 assert.equal(innate?.max,2);
 assert.equal(innate?.recharge,"long_rest");
});
test("Artificer TCE counters retain subclass gates, limits and feature origins",()=>{
 const expected={
  Armorer:{"Defensive Field":5,"Perfected Armor":5},
  Alchemist:{"Experimental Elixir":3,"Restorative Reagents":4,
   "Chemical Mastery (Heal)":1,"Chemical Mastery (Greater Restoration)":1},
  Artillerist:{"Eldritch Cannon":1},
  "Battle Smith":{"Arcane Jolt":4}
 };
 for(const [subclass,own] of Object.entries(expected)){
  const record={kind:"character",level:15,abilities:{int:18},
   classes:[{name:"Artificer",source:"TCE",level:15,subclass}]};
  const rows=classResourceTrackers(record,index,{classes:index.resource_overrides});
  const actual=Object.fromEntries(rows.map(row=>[row.name,row.max]));
  assert.deepEqual(actual,{"Flash of Genius":4,...own});
  assert(rows.every(row=>row.recharge==="long_rest"&&row.id.startsWith("class:artificer:tce:")));
  if(subclass==="Armorer")assert.equal(rows.find(row=>row.name==="Perfected Armor")?.origin,"Guardian");
  if(subclass==="Alchemist")assert.equal(rows.find(row=>row.name==="Chemical Mastery (Heal)")?.origin,"Chemical Mastery");
 }
 for(const [level,max] of [[3,1],[6,2],[15,3]]){
  const record={kind:"character",level,abilities:{int:8},
   classes:[{name:"Artificer",source:"TCE",level,subclass:"Alchemist"}]};
  const rows=classResourceTrackers(record,index,{classes:index.resource_overrides});
  assert.equal(rows.find(row=>row.name==="Experimental Elixir")?.max,max);
  if(level>=7)assert.equal(rows.find(row=>row.name==="Flash of Genius")?.max,1);
 }
});
test("Fight Club counter aliases resolve to exact PHB subclass traits without changing saved IDs",()=>{
 for(const [owner,subclass,level,name,id] of [
  ["Warlock","The Fiend",6,"Dark One's Own Luck","class:warlock:phb:dark_one's_luck"],
  ["Wizard","School of Illusion",10,"Illusory Self","class:wizard:phb:illusory_step"],
  ["Wizard","School of Divination",10,"The Third Eye","class:wizard:phb:third_eye"]
 ]){
  const record={kind:"character",level,classes:[{name:owner,source:"PHB",level,subclass}]};
  const row=classResourceTrackers(record,index,{classes:index.resource_overrides})
   .find(resource=>resource.name===name);
  assert.equal(row?.id,id);
  assert.equal(row?.origin,name);
  assert.equal(row?.recharge,"short_rest");
 }
});
test("2024 Rogue Stroke of Luck is unlocked only at level 20 with its own edition ID",()=>{
 const rowsAt=level=>classResourceTrackers({kind:"character",level,
  classes:[{name:"Rogue",source:"XPHB",level}]},index,{classes:index.resource_overrides});
 assert.equal(rowsAt(19).some(row=>row.name==="Stroke of Luck"),false);
 const stroke=rowsAt(20).find(row=>row.name==="Stroke of Luck");
 assert.equal(stroke?.id,"class:rogue:xphb:stroke_of_luck");
 assert.equal(stroke?.max,1);
 assert.equal(stroke?.recharge,"short_rest");
});
test("2024 Ranger tracks only the limited Tireless action and Nature's Veil uses",()=>{
 const rowsAt=(level,wis)=>classResourceTrackers({kind:"character",level,abilities:{wis},
  classes:[{name:"Ranger",source:"XPHB",level}]},index,{classes:index.resource_overrides});
 assert.equal(rowsAt(9,18).some(row=>row.name.startsWith("Tireless")),false);
 const tireless=rowsAt(10,18).find(row=>row.name==="Tireless (Temporary Hit Points)");
 assert.equal(tireless?.max,4);
 assert.equal(tireless?.origin,"Tireless");
 assert.equal(tireless?.recharge,"long_rest");
 assert.equal(rowsAt(13,18).some(row=>row.name==="Nature's Veil"),false);
 const veil=rowsAt(14,8).find(row=>row.name==="Nature's Veil");
 assert.equal(veil?.id,"class:ranger:xphb:nature's_veil");
 assert.equal(veil?.max,1);
 assert.equal(veil?.recharge,"long_rest");
});
test("2024 recovery features keep separate trait counters and edition identities",()=>{
 const rowsAt=(name,source,level)=>classResourceTrackers({kind:"character",level,
  classes:[{name,source,level}]},index,{classes:index.resource_overrides});
 for(const [name,level,feature,id] of [
  ["Barbarian",15,"Persistent Rage","class:barbarian:xphb:persistent_rage"],
  ["Monk",2,"Uncanny Metabolism","class:monk:xphb:uncanny_metabolism"],
  ["Warlock",2,"Magical Cunning","class:warlock:xphb:magical_cunning"]
 ]){
  assert.equal(rowsAt(name,"XPHB",level-1).some(row=>row.name===feature),false);
  const row=rowsAt(name,"XPHB",level).find(row=>row.name===feature);
  assert.equal(row?.id,id);
  assert.equal(row?.origin,feature);
  assert.equal(row?.max,1);
  assert.equal(row?.recharge,"long_rest");
  assert.equal(rowsAt(name,"PHB",level).some(row=>row.name===feature),false);
 }
 assert.equal(rowsAt("Monk","XPHB",2).find(row=>row.name==="Focus Points")?.max,2);
 assert.equal(rowsAt("Barbarian","XPHB",15).find(row=>row.name==="Rages")?.max,5);
});
test("saved custom trackers coexist with typed class resources and preserve other counters",()=>{
 const record={kind:"character",level:2,
  classes:[{name:"Druid",source:"PHB",level:2}],
  resource_trackers:[{id:"custom",name:"Risorsa extra",max:4,recharge:"manual"}],
  resource_tracker_spent:{custom:2,"class:druid:phb:wild_shape":1}};
 const trackers=classResourceTrackers(record,index,overrides);
 assert.equal(trackers.length,2);
 assert.equal(trackers.find(x=>x.id==="custom")?.max,4);
 const patch=recoveryPatch(record,"short_rest",trackers);
 assert.equal(patch.resource_tracker_spent.custom,2);
 assert.equal(patch.resource_tracker_spent["class:druid:phb:wild_shape"],undefined);
});
