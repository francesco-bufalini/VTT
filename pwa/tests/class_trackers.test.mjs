import {test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {classResourceTrackers} from "../class_trackers.js";
import {changeTrackerUses,recoveryPatch} from "../character_core.js";

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
