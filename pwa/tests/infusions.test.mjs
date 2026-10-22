import {test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {
 artificerLevel,infusionLimits,learnedInfusions,infusionEligible,infusionNumericBonuses,
 infusionGrantingTrait,isInfusionPrepared,prepareInfusionPatch,activeInfusions,
 targetableInventoryItems,compatibleInfusionTargets,
 learnInfusionPatch,applyInfusionPatch,clearInfusionPatch,forgetInfusionPatch
} from "../item_controls.js";
import {calculateSheet} from "../sheet_rules.js";
const index=JSON.parse(readFileSync(new URL("../catalog/ability_grants.json",import.meta.url),"utf8"));
const definitions=index.artificer_infusions;
const byName=name=>definitions.find(entry=>entry.name===name);
const mechanics={classes:[{name:"Artificer",source:"TCE",columns:[
 {name:"Infused Items",levels:[0,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,6,6,6]}
]}]};
const infusionTrait={id:"infuse_item",name:"Infuse Item",class_name:"Artificer",
 class_source:"TCE",level:2,origin_key:"class|tce|artificer",
 origin_id:"feature:class|tce|artificer|infuse_item"};
const classFeatures={class_features:[infusionTrait],subclass_features:[]};
const sheetCatalogs={abilityGrants:index,classFeatures,classMechanics:mechanics};
const make=(level=10)=>({
 id:"artificer_test",kind:"character",name:"Artefice",classes:[{name:"Artificer",source:"TCE",level}],
 abilities:{str:16,dex:10,con:12,int:18,wis:10,cha:10},
 proficiency_choices:[{kind:"weapon",key:"longsword"}],
 optional_features_catalog:[],inventory:[],formula_bonuses:[]
});
const sword=()=>({id:"weapon:longsword",name:"Longsword",type:"M",quantity:3,
 damage:"1d8",rarity:"none",active:true,properties:["V"],equipped_slots:["main"]});

test("all 16 source-qualified TCE infusions are available in served offline catalog",()=>{
 assert.equal(definitions.length,16);
 assert.ok(definitions.every(entry=>entry.id?.startsWith("infusion|tce|")&&entry.item_selector));
 assert.equal(byName("Enhanced Weapon").numeric_item_bonuses.bonus_weapon,1);
 assert.deepEqual(infusionLimits(make(10),mechanics,[infusionTrait]),{level:10,active:4,known:8});
 assert.deepEqual(infusionLimits(make(1),mechanics,[infusionTrait]),{level:1,active:0,known:0});
 assert.equal(artificerLevel({class:"Artificer",class_source:"TCE",level:5}),5);
});

test("learn, infuse one stacked sword, and compute upgraded +2 attack/damage entirely offline",()=>{
 let record=make(10),entry=byName("Enhanced Weapon");
 record.inventory=[sword()];
 record={...record,...learnInfusionPatch(record,entry,definitions,mechanics,-1,[infusionTrait])};
 record={...record,...prepareInfusionPatch(record,learnedInfusions(record,definitions)[0],definitions,[infusionTrait],true)};
 const known=learnedInfusions(record,definitions);
 assert.equal(known.length,1);
 record={...record,...applyInfusionPatch(record,known[0],definitions,mechanics,0,[infusionTrait])};
 assert.equal(record.inventory.length,2);
 assert.equal(record.inventory[0].quantity,1);
 assert.equal(record.inventory[1].quantity,2);
 assert.equal(record.inventory[1].infusion,undefined);
 assert.equal(record.inventory[0].infusion.creator_id,record.id);
 assert.equal(infusionNumericBonuses(record,record.inventory[0],definitions,[infusionTrait]).bonus_weapon,2);
 const output=calculateSheet(record,sheetCatalogs);
 assert.equal(output.attacks[0].hit,3+4+2);
 assert.equal(output.attacks[0].damage,"1d8 + 5");
 assert.throws(()=>applyInfusionPatch(record,known[0],definitions,mechanics,1,[infusionTrait]),/già applicata/);
 record={...record,...clearInfusionPatch(record,0)};
 assert.equal(calculateSheet(record,sheetCatalogs).attacks[0].hit,3+4);
});

test("infusion attunement, low-level restrictions and forgetting",()=>{
 const wand={id:"local_wand",name:"Arcane Wand",quantity:1,custom_item_type:"other",
   active:true,equipped:true,attuned:false,rarity:"none"};
 let record=make(10);record.inventory=[wand];
 const focus=byName("Enhanced Arcane Focus");
 assert.equal(infusionEligible(focus,wand),true);
 record={...record,...learnInfusionPatch(record,focus,definitions,mechanics,-1,[infusionTrait])};
 record={...record,...prepareInfusionPatch(record,learnedInfusions(record,definitions)[0],definitions,[infusionTrait],true)};
 record={...record,...applyInfusionPatch(record,learnedInfusions(record,definitions)[0],definitions,mechanics,0,[infusionTrait])};
 assert.equal(record.inventory[0].infusion.requires_attunement,true);
 const output=calculateSheet(record,sheetCatalogs);
 assert.equal(output.values.spell_attack,0,"Senza sintonia nessun bonus ai tiri di incantesimo");
 record.inventory[0].attuned=true;
 const buffed=calculateSheet(record,sheetCatalogs);
 assert.equal(buffed.values.spell_attack,2);
 record={...record,...forgetInfusionPatch(record,learnedInfusions(record,definitions)[0])};
 assert.equal(record.optional_features_catalog.length,0);
 assert.equal(record.inventory[0].infusion,undefined);
 assert.equal(record.inventory[0].attuned,false);
 assert.throws(()=>learnInfusionPatch(make(1),focus,definitions,mechanics,-1,[infusionTrait]),/limite|non disponibile/i);
});

test("typed selectors reject mismatched or magical items; Repeating Shot applies only on ranged weapons",()=>{
 const repeating=byName("Repeating Shot");
 const arrow={id:"weapon:crossbow",type:"R",name:"Crossbow",quantity:1,
   properties:["A"],rarity:"none",equipped_slots:["main"],active:true};
 const melee={...arrow,type:"M",id:"weapon:melee"};
 const magical={...arrow,id:"magic_item:crossbow",rarity:"rare"};
 assert.equal(infusionEligible(repeating,arrow),true);
 assert.equal(infusionEligible(repeating,melee),true,"Selector eligibility checks ammunition; numeric effect checks ranged type");
 assert.equal(infusionEligible(repeating,magical),false);
 const record=make(10);
 const onItem={...arrow,infusion:{id:repeating.id,creator_id:record.id,level:10}};
 assert.equal(infusionNumericBonuses(record,onItem,definitions,[infusionTrait]).bonus_weapon,1);
 assert.deepEqual(infusionNumericBonuses(record,{...melee,infusion:onItem.infusion},definitions,[infusionTrait]),{});
});


test("Infuse Item is the only granting feature; known and prepared are independent",()=>{
 const record=make(10),source=[infusionTrait],entry=byName("Enhanced Weapon");
 assert.equal(infusionGrantingTrait(record,source)?.origin_id,infusionTrait.origin_id);
 assert.equal(infusionLimits(record,mechanics,[]).active,0,
   "Class membership without the owned, enabled feature must grant no infusion capacity");
 assert.throws(()=>learnInfusionPatch(record,entry,definitions,mechanics,-1,[]),/limite|non disponibile/i);
 const learned={...record,...learnInfusionPatch(record,entry,definitions,mechanics,-1,source)};
 assert.equal(isInfusionPrepared(learned,learnedInfusions(learned,definitions)[0],definitions),false);
 assert.throws(()=>applyInfusionPatch({...learned,inventory:[sword()]},learnedInfusions(learned,definitions)[0],definitions,mechanics,0,source),
   /Prepara/);
 const prepared={...learned,...prepareInfusionPatch(learned,learnedInfusions(learned,definitions)[0],definitions,source,true)};
 assert.equal(isInfusionPrepared(prepared,learnedInfusions(prepared,definitions)[0],definitions),true);
 assert.deepEqual(compatibleInfusionTargets({...prepared,inventory:[sword()]},
   learnedInfusions(prepared,definitions)[0],definitions,source).map(x=>x.index),[0]);
 assert.deepEqual(targetableInventoryItems({...record,inventory:[sword()]},{kinds:["armor"]}),[]);
});

test("equipped and attuned infusion projects one magical trait; disabled source suppresses it",()=>{
 const entry=byName("Enhanced Arcane Focus"),source=[infusionTrait];
 const wand={id:"local_arcane_wand",name:"Arcane Wand",quantity:1,custom_item_type:"other",
   active:true,equipped:true,attuned:false,rarity:"none"};
 let record={...make(10),inventory:[wand]};
 record={...record,...learnInfusionPatch(record,entry,definitions,mechanics,-1,source)};
 let known=learnedInfusions(record,definitions)[0];
 record={...record,...prepareInfusionPatch(record,known,definitions,source,true)};
 record={...record,...applyInfusionPatch(record,known,definitions,mechanics,0,source)};
 assert.equal(activeInfusions(record,definitions,source).length,0,"Attunement is required");
 record.inventory[0].attuned=true;
 const applied=activeInfusions(record,definitions,source);
 assert.equal(applied.length,1);
 assert.ok(applied[0].id.startsWith("infusion:"));
 record.inventory[0].equipped=false;record.inventory[0].attuned=false;
 assert.equal(activeInfusions(record,definitions,source).length,0);
 record.inventory[0].equipped=true;record.inventory[0].attuned=true;
 record.origin_enabled={[infusionTrait.origin_id]:false};
 assert.equal(activeInfusions(record,definitions,source).length,0);
 assert.deepEqual(infusionNumericBonuses(record,record.inventory[0],definitions,source),{});
});

test("legacy learned infusions remain prepared until preparation is explicitly saved",()=>{
 const entry=byName("Enhanced Weapon");
 const record={...make(10),optional_features_catalog:[{id:entry.id,name:entry.name,source:"TCE"}]};
 assert.equal(isInfusionPrepared(record,learnedInfusions(record,definitions)[0],definitions),true);
 const changed={...record,...prepareInfusionPatch(record,learnedInfusions(record,definitions)[0],
   definitions,[infusionTrait],false)};
 assert.equal(isInfusionPrepared(changed,learnedInfusions(changed,definitions)[0],definitions),false);
});
