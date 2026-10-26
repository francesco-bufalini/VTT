import {test} from "node:test";
import assert from "node:assert/strict";
import {calculateSheet} from "../sheet_rules.js";
import {collectStructuredFeatures,structuredFeatureGrants} from "../structured_effects.js";
import {actionEntries} from "../action_economy.js";

const classFeatures={
 version:1,
 class_features:[
  {id:"5etools:class_features:phb:guard:fighter:2",name:"Guard",class_name:"Fighter",
   class_source:"PHB",level:2,bonuses:[{target:"ac",expression:2}]},
  {id:"5etools:class_features:xphb:guard:fighter:2",name:"Guard 2024",class_name:"Fighter",
   class_source:"XPHB",level:2,bonuses:[{target:"ac",expression:9}]},
  {id:"5etools:class_features:phb:surge:fighter:2",name:"Surge",class_name:"Fighter",
   class_source:"PHB",level:2,action_type:"bonus",tracker_id:"surge"},
  {id:"5etools:class_features:phb:late:fighter:9",name:"Late",class_name:"Fighter",
   class_source:"PHB",level:9,bonuses:[{target:"initiative",expression:99}]}
 ],
 subclass_features:[
  {id:"5etools:subclass_features:phb:warden",name:"Warden Shield",
   class_name:"Fighter",class_source:"PHB",subclass_name:"Warden",subclass_source:"PHB",
   level:3,bonuses:[{target:"initiative",expression:1}]},
  {id:"5etools:subclass_features:phb:other",name:"Other Shield",
   class_name:"Fighter",class_source:"PHB",subclass_name:"Other",subclass_source:"PHB",
   level:3,bonuses:[{target:"initiative",expression:100}]}
 ]
};
const catalog={classFeatures,originDetails:{races:{},backgrounds:{},feats:{}}};
const fighter=(level=3)=>({kind:"character",class:"Fighter",class_source:"PHB",level,
 classes:[{name:"Fighter",source:"PHB",level,subclass:"Warden",subclass_source:"PHB"}],
 abilities:{str:10,dex:14,con:10,int:10,wis:10,cha:10},armor_class_base:10,
 max_hp_base:20,inventory:[],rules_version:"2014"});

test("native catalog features respect individual class and subclass level gates",()=>{
 const levelOne=calculateSheet(fighter(1),catalog);
 assert.equal(levelOne.stats.armor_class,12);
 assert.equal(levelOne.stats.initiative,2);
 assert.equal(levelOne.features.length,0);
 const levelTwo=calculateSheet(fighter(2),catalog);
 assert.equal(levelTwo.stats.armor_class,14);
 assert.equal(levelTwo.stats.initiative,2);
 assert(!levelTwo.features.some(f=>f.name==="Warden Shield"));
 const levelThree=calculateSheet(fighter(3),catalog);
 assert.equal(levelThree.stats.armor_class,14);
 assert.equal(levelThree.stats.initiative,3);
 assert(!levelThree.features.some(f=>f.name==="Other Shield"||f.name==="Late"||f.name==="Guard 2024"));
 assert(levelThree.features.some(f=>f.name==="Warden Shield"));
 assert.equal(levelThree.stats.proficiency,2);
});

test("feature IDs match CreatureFeatures and saved disabled automatic grants",()=>{
 const c=fighter(3),features=collectStructuredFeatures(c,catalog);
 const guard=features.find(f=>f.name==="Guard");
 assert.equal(guard.key,"class|phb|fighter|5etools:class_features:phb:guard:fighter:2");
 const grants=structuredFeatureGrants(c,catalog,features);
 const bonus=grants.find(r=>r.target==="ac");
 assert.equal(bonus.id,"auto|feature:"+guard.key+"|bonuses|ac|ac");
 assert.equal(bonus.parent_origin,"class|phb|fighter");
 assert.equal(calculateSheet({...c,origin_enabled:{[guard.origin_id]:false}},catalog).stats.armor_class,12);
 assert.equal(calculateSheet({...c,formula_bonuses:[{id:bonus.id,automatic:true,disabled:true}]},catalog).stats.armor_class,12);
 assert.equal(calculateSheet({...c,origin_enabled:{"class|phb|fighter":false}},catalog).stats.armor_class,12);
 assert.equal(calculateSheet({...c,classes:[],class:"Wizard",class_source:"PHB"},catalog).stats.armor_class,12);
});

test("catalog feature actions appear only when granted and remain separate from passive traits",()=>{
 const c=fighter(2),calculated=calculateSheet(c,catalog),actions=actionEntries(c,calculated,[]);
 assert(actions.some(row=>row.name==="Surge"&&row.time==="bonus"));
 assert(!actions.some(row=>row.name==="Guard"));
 const surge=calculated.features.find(f=>f.name==="Surge");
 assert(!actionEntries({...c,origin_enabled:{[surge.origin_id]:false}},
   calculateSheet({...c,origin_enabled:{[surge.origin_id]:false}},catalog),[])
   .some(row=>row.name==="Surge"));
});

test("typed background, species, feat sections have native origin identities and never parse prose",()=>{
 const originDetails={
  races:{"elf|phb":{entries:[{name:"Natural Gift",bonuses:[{target:"speed",expression:5}],entries:["gift"]}]}},
  backgrounds:{"sage|phb":{source:"PHB",entries:[{name:"Researcher",bonuses:[{target:"skill:arcana",expression:2}],entries:["research"]}]}},
  feats:{"keen|phb":{feature_sections:[{name:"Sharper",min_level:4,bonuses:[{target:"initiative",expression:1}],entries:["sharp"]}]}}
 };
 const base={...fighter(3),species:"Elf",species_source:"PHB",background:"Sage",background_source:"PHB",
   feats_catalog:[{name:"Keen",source:"PHB"}]};
 const out=calculateSheet(base,{classFeatures,originDetails});
 assert.equal(out.values.speed,35);
 assert.equal(out.values["skill:arcana"],2);
 assert.equal(out.stats.initiative,3);
 assert(!out.features.some(f=>f.name==="Sharper"));
 const upgraded={...base,level:4,classes:[{...base.classes[0],level:4}]};
 const advanced=calculateSheet(upgraded,{classFeatures,originDetails});
 assert.equal(advanced.stats.initiative,4);
 const sharp=advanced.features.find(f=>f.name==="Sharper");
 assert.equal(sharp.origin_key,"feat|keen|phb");
 assert.equal(sharp.key,"feat|keen|phb|feat|keen|phb|4|sharper");
 assert.equal(calculateSheet({...upgraded,feats_catalog:[]},{classFeatures,originDetails}).stats.initiative,3);
 assert.equal(calculateSheet({...upgraded,feats_catalog:[{name:"Keen",source:"PHB",disabled:true}]},
   {classFeatures,originDetails}).stats.initiative,3);
});

test("native fallback feature keys honor nested feat requirement level and activation",()=>{
 const c=fighter(5);
 c.feats_catalog=[{name:"Attentive",source:"HB",feature_sections:[
  {name:"Level Gate",requirements:{min_level:5},
    bonuses:[{target:"initiative",expression:2}]}
 ]}];
 const featureCatalog={...classFeatures,class_features:[
  ...classFeatures.class_features,
  {id:"typed-reaction",name:"Counterguard",class_name:"Fighter",
   class_source:"PHB",level:4,activation:{type:"reaction"},entries:["reaction"]}
 ]};
 const catalogs={classFeatures:featureCatalog,originDetails:{}};
 const result=calculateSheet(c,catalogs);
 const gated=result.features.find(f=>f.name==="Level Gate");
 assert.equal(gated.key,"feat|attentive|hb|feat|attentive|hb|5|level gate");
 assert.equal(result.stats.initiative,3+2);
 assert(actionEntries(c,result,[]).some(x=>x.name==="Counterguard"&&x.time==="reaction"));
 const below=calculateSheet({...c,level:4,classes:[{...c.classes[0],level:4}]},catalogs);
 assert(!below.features.some(f=>f.name==="Level Gate"));
});

test("PHB 2014 supplemental feat grants are generated from native data",async()=>{
 const {readFileSync}=await import("node:fs");
 const native=JSON.parse(readFileSync(new URL("../../vtt/data/feat_numeric_bonuses_2014.json",import.meta.url)));
 const packaged=JSON.parse(readFileSync(new URL("../catalog/ability_grants.json",import.meta.url)));
 assert.deepEqual(packaged.feat_numeric_bonuses,native.feats);
 const base={...fighter(8),abilities:{str:10,dex:14,con:10,int:12,wis:14,cha:10}};
 const catalogs={...catalog,abilityGrants:packaged};
 const withFeat=feat=>calculateSheet({...base,feats_catalog:[{name:feat,source:"PHB"}]},catalogs);
 const observant=withFeat("Observant");
 assert.equal(observant.stats.passive_perception,17);
 assert.equal(observant.stats.passive_investigation,16);
 assert.equal(observant.skills.perception,2,"active Perception must not receive the feat bonus");
 assert.equal(observant.skills.investigation,1,"active Investigation must not receive the feat bonus");
 assert(observant.automatic_bonuses.some(b=>b.target==="passive_skill:investigation"&&b.origin_id==="feat|phb|observant"));
 assert.equal(withFeat("Alert").stats.initiative,8);
 assert.equal(withFeat("Mobile").stats.speeds.walk,40);
 assert.equal(withFeat("Tough").stats.max_hp,36);
 const levelTen={...base,level:10,classes:[{...base.classes[0],level:10}]};
 assert.equal(calculateSheet({...levelTen,feats_catalog:[{name:"Tough",source:"PHB"}]},catalogs).stats.max_hp,40);
 const noFeat=calculateSheet(base,catalogs);
 assert.equal(noFeat.stats.passive_perception,12);
 assert.equal(noFeat.stats.passive_investigation,11);
 assert.equal(calculateSheet({...base,feats_catalog:[{name:"Observant",source:"PHB",disabled:true}]},catalogs).stats.passive_perception,12);
 assert.equal(calculateSheet({...base,feats_catalog:[{name:"Observant",source:"PHB"}],origin_enabled:{"feat|phb|observant":false}},catalogs).stats.passive_investigation,11);
 assert.equal(calculateSheet({...base,feats_catalog:[{name:"Observant",source:"XPHB"}]},catalogs).stats.passive_perception,12,"2024 Observant has different mechanics");
 const suppressed=observant.automatic_bonuses.find(b=>b.target==="passive_perception");
 assert.equal(calculateSheet({...base,feats_catalog:[{name:"Observant",source:"PHB"}],formula_bonuses:[{id:suppressed.id,automatic:true,disabled:true}]},catalogs).stats.passive_perception,12);
 assert.equal(calculateSheet({...base,feats_catalog:[{name:"Observant",source:"PHB"}],trait_benefit_removed:{test:["bonus:"+suppressed.id]}},catalogs).stats.passive_perception,12);
});
