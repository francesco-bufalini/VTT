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

test("PWA derives class abilities from the actual structured features, not level placeholders",()=>{
  const record={classes:[{name:"Bard",source:"PHB",level:3},{name:"Druid",source:"PHB",level:2}]};
  const feature=(name,owner)=>({name,origin_key:"class|phb|"+owner,
    origin_id:"feature:class|phb|"+owner+"|"+name,entries:[name+" description"]});
  const bard=feature("Bardic Inspiration","bard");
  const druid=feature("Wild Shape","druid");
  assert.deepEqual(abilitiesForCreature(record,definitions).map(x=>x.id),[],
    "a class level must not fabricate a privilege when no features are loaded");
  const projected={features:[bard,druid],trackers:[
    {id:"class:bard:phb:bardic_inspiration",name:"Bardic Inspiration",
      origin_class:"Bard",max:3,spent:1},
    {id:"class:druid:phb:wild_shape",name:"Wild Shape",
      origin_class:"Druid",max:2,spent:0}
  ]};
  const powers=abilitiesForCreature(record,definitions,projected);
  assert.deepEqual(powers.map(x=>x.id),["vtt_bardic_inspiration","vtt_wild_shape"]);
  assert.equal(powers[0].tracker_remaining,2);
  assert.equal(powers[1].tracker_id,"class:druid:phb:wild_shape");
  assert.equal(powers[0].feature_id,bard.origin_id);
  assert.equal(powers[0].origin_name,'Tratto · Bardic Inspiration');
  assert.equal(powers[1].origin_name,'Tratto · Wild Shape');
  assert.equal(powers[1].feature_name,'Wild Shape');
  for(const power of powers){
    assert.equal(power.action_kind,"ability");
    assert.equal(Object.hasOwn(power,"level"),false);
    assert.equal(Object.hasOwn(power,"school"),false);
    assert.equal(Object.hasOwn(power,"components"),false);
  }
  const disabled={...projected,features:[{...bard,disabled:true},druid]};
  assert.deepEqual(abilitiesForCreature(record,definitions,disabled).map(x=>x.id),["vtt_wild_shape"]);
  assert.deepEqual(abilitiesForCreature({...record,origin_enabled:{[druid.origin_id]:false}},
    definitions,projected).map(x=>x.id),["vtt_bardic_inspiration"]);
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

test("typed active features and optional grants preserve their origins and costs",()=>{
 const feature={id:"feature:typed",key:"class|phb|fighter|typed",name:"Parry",
   origin_key:"class|phb|fighter",origin_id:"feature:class|phb|fighter|typed",
   action_type:{type:"reaction"},entries:["Protect yourself"]};
 const projection={features:[feature],trackers:[{id:"superiority",name:"Superiority Die",max:4,spent:2}]};
 const record={class:"Fighter",class_source:"PHB",level:3,
   optional_features_catalog:[{name:"Ambush",source:"TCE",origin_id:"optional:ambush"}]};
 const abilities=abilitiesForCreature(record,definitions,projection);
 assert(abilities.some(x=>x.feature_id===feature.origin_id));
 assert(abilities.some(x=>x.id==="ability:maneuver:tce:ambush"));
 assert.equal(abilities.find(x=>x.name==="Ambush").tracker_remaining,2);
 const disabled=abilitiesForCreature({...record,origin_enabled:{"optional:ambush":false}},
   definitions,projection);
 assert(!disabled.some(x=>x.name==="Ambush"));
});


test('read-only previews include disabled class, optional and granted powers while runtime stays gated',()=>{
 const record={class:'Fighter',class_source:'PHB',level:3,
  origin_enabled:{'feature:class|phb|fighter|typed':false},
  optional_features_catalog:[{name:'Ambush',source:'TCE',disabled:true}],
  origin_spell_grants:[{ability_id:'ability:maneuver:phb:parry',origin_id:'feat|phb|martial',
    disabled:true,action_kind:'ability'}]};
 const features=[{name:'Parry',key:'class|phb|fighter|typed',
  origin_id:'feature:class|phb|fighter|typed',
  origin_key:'class|phb|fighter',action_type:'reaction',disabled:true}];
 const projection={features};
 assert.deepEqual(abilitiesForCreature(record,definitions,projection),[]);
 const previews=abilitiesForCreature(record,definitions,projection,{includeUnavailable:true});
 assert.deepEqual(previews.map(x=>x.name),['Ambush','Parry','Parry']);
 assert.equal(previews.length,3);
 assert.ok(previews.every(x=>x.unavailable===true));
 assert.ok(previews.some(x=>x.name==='Ambush'&&x.origin_id==='optional|tce|ambush'));
 assert.ok(previews.some(x=>x.origin_id==='feat|phb|martial'));
 assert.ok(previews.some(x=>x.origin_id===features[0].origin_id));
});
