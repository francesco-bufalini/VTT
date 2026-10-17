import {test} from "node:test";
import assert from "node:assert/strict";
import {abilitiesForCreature, loadActivatedAbilities} from "../activated_abilities.js";

const definitions=[
  {id:"ability:maneuver:tce:ambush",name:"Ambush",source:"TCE",kind:"ability",
    activation_mode:"contextual",resource_name:"Superiority Die",school:"none",components:"none",level:0},
  {id:"ability:maneuver:phb:parry",name:"Parry",source:"PHB",kind:"ability",
    activation_mode:"contextual"},
  {id:"ability:maneuver:xphb:parry",name:"Parry",source:"XPHB",kind:"ability",
    activation_mode:"contextual"}
];

test("PWA projects Bardic Inspiration and Wild Shape as nonspell capabilities",()=>{
  const record={classes:[{name:"Bard",level:3},{name:"Druid",level:2}]};
  const powers=abilitiesForCreature(record,definitions);
  assert.deepEqual(powers.map(x=>x.id),["vtt_bardic_inspiration","vtt_wild_shape"]);
  for(const power of powers){
    assert.equal(power.action_kind,"ability");
    assert.equal(Object.hasOwn(power,"level"),false);
    assert.equal(Object.hasOwn(power,"school"),false);
    assert.equal(Object.hasOwn(power,"components"),false);
  }
});

test("PWA selects only acquired maneuvers and preserves legacy omitted source",()=>{
  const fighter={class:"Fighter",level:3,rules_version:"2024",
    optional_features_catalog:[{name:"Ambush",source:"TCE"},
      {name:"Parry"},{name:"Bait and Switch",source:"TCE",disabled:true}]};
  const powers=abilitiesForCreature(fighter,definitions);
  assert.deepEqual(powers.map(x=>x.name),["Ambush","Parry"]);
  assert.equal(powers.find(x=>x.name==="Parry").source,"XPHB");
  assert.equal(powers.find(x=>x.name==="Ambush").school,undefined);
  assert.equal(powers.find(x=>x.name==="Ambush").components,undefined);
  assert.equal(powers.find(x=>x.name==="Ambush").level,undefined);
  assert.equal(powers.find(x=>x.name==="Ambush").activation_mode,"contextual");
});

test("PWA custom ability grants stay distinct from ordinary feat spell grants",()=>{
  const sheet={origin_spell_grants:[
    {spell_id:"cure_wounds",origin_name:"Talento"},
    {ability_id:"custom:mark",action_kind:"ability",origin_name:"Tratto",
      name:"Mark Target",description:"Marks the selected creature."},
    {spell_id:"ability:maneuver:tce:ambush",origin_name:"Talento"}
  ]};
  const powers=abilitiesForCreature(sheet,definitions);
  assert.equal(powers.length,2);
  assert.ok(powers.some(x=>x.name==="Mark Target"));
  assert.ok(powers.some(x=>x.name==="Ambush"));
  assert.equal(sheet.origin_spell_grants[0].spell_id,"cure_wounds");
  assert.equal(sheet.origin_spell_grants[1].action_kind,"ability");
});

test("PWA manifest loader requests shared structured native data",async()=>{
  const previous=globalThis.fetch;
  globalThis.fetch=async (url,options)=>{
    assert.equal(url,"/catalog/activated_abilities.json");
    assert.equal(options?.cache,"no-store");
    return {ok:true,json:async()=>({abilities:definitions})};
  };
  try{
    const loaded=await loadActivatedAbilities();
    assert.deepEqual(loaded,definitions);
  }finally{
    globalThis.fetch=previous;
  }
});
