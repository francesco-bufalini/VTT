import {test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {
 artificerLevel,infusionLimits,learnedInfusions,infusionEligible,infusionNumericBonuses,
 learnInfusionPatch,prepareInfusionPatch,preparedInfusions,activeInfusions,infusionGrantingTrait,
 applyInfusionPatch,clearInfusionPatch,forgetInfusionPatch
} from "../item_controls.js";
import {calculateSheet} from "../sheet_rules.js";
const index=JSON.parse(readFileSync(new URL("../catalog/ability_grants.json",import.meta.url),"utf8"));
const definitions=index.artificer_infusions;
const byName=name=>definitions.find(entry=>entry.name===name);
const mechanics={classes:[{name:"Artificer",source:"TCE",columns:[
 {name:"Infused Items",levels:[0,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,6,6,6]}
]}]};
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
 assert.deepEqual(infusionLimits(make(10),mechanics),{level:10,active:4,known:8});
 assert.deepEqual(infusionLimits(make(1),mechanics),{level:1,active:0,known:0});
 assert.equal(artificerLevel({class:"Artificer",class_source:"TCE",level:5}),5);
});

test("learn, infuse one stacked sword, and compute upgraded +2 attack/damage entirely offline",()=>{
 let record=make(10),entry=byName("Enhanced Weapon");
 record.inventory=[sword()];
 record={...record,...learnInfusionPatch(record,entry,definitions,mechanics)};
 const known=learnedInfusions(record,definitions);
 assert.equal(known.length,1);
 assert.equal(preparedInfusions(record,definitions).length,0,"New infusions require preparation");
 record={...record,...prepareInfusionPatch(record,known[0],true,definitions)};
 record={...record,...applyInfusionPatch(record,known[0],definitions,mechanics,0)};
 assert.equal(record.inventory.length,2);
 assert.equal(record.inventory[0].quantity,1);
 assert.equal(record.inventory[1].quantity,2);
 assert.equal(record.inventory[1].infusion,undefined);
 assert.equal(record.inventory[0].infusion.creator_id,record.id);
 assert.equal(infusionNumericBonuses(record,record.inventory[0],definitions).bonus_weapon,2);
 const output=calculateSheet(record,{abilityGrants:index});
 assert.equal(output.attacks[0].hit,3+4+2);
 assert.equal(output.attacks[0].damage,"1d8 + 5");
 assert.throws(()=>applyInfusionPatch(record,known[0],definitions,mechanics,1),/già applicata/);
 record={...record,...clearInfusionPatch(record,0)};
 assert.equal(calculateSheet(record,{abilityGrants:index}).attacks[0].hit,3+4);
});

test("infusion attunement, low-level restrictions and forgetting",()=>{
 const wand={id:"local_wand",name:"Arcane Wand",quantity:1,custom_item_type:"other",
   active:true,equipped:true,attuned:false,rarity:"none"};
 let record=make(10);record.inventory=[wand];
 const focus=byName("Enhanced Arcane Focus");
 assert.equal(infusionEligible(focus,wand),true);
 record={...record,...learnInfusionPatch(record,focus,definitions,mechanics)};
 record={...record,...prepareInfusionPatch(record,learnedInfusions(record,definitions)[0],true,definitions)};
 record={...record,...applyInfusionPatch(record,learnedInfusions(record,definitions)[0],definitions,mechanics,0)};
 assert.equal(record.inventory[0].infusion.requires_attunement,true);
 const output=calculateSheet(record,{abilityGrants:index});
 assert.equal(output.values.spell_attack,0,"Senza sintonia nessun bonus ai tiri di incantesimo");
 record.inventory[0].attuned=true;
 const buffed=calculateSheet(record,{abilityGrants:index});
 assert.equal(buffed.values.spell_attack,2);
 record={...record,...forgetInfusionPatch(record,learnedInfusions(record,definitions)[0])};
 assert.equal(record.optional_features_catalog.length,0);
 assert.equal(record.inventory[0].infusion,undefined);
 assert.equal(record.inventory[0].attuned,false);
 assert.throws(()=>learnInfusionPatch(make(1),focus,definitions,mechanics),/limite|non disponibile/i);
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
 assert.equal(infusionNumericBonuses(record,onItem,definitions).bonus_weapon,1);
 assert.deepEqual(infusionNumericBonuses(record,{...melee,infusion:onItem.infusion},definitions),{});
});

test("infusions require their granting trait, not mere class ownership",()=>{
 const trait={name:"Infuse Item",origin_key:"class|tce|artificer",
   origin_id:"feature:class|tce|artificer|2|infuse item",level:2};
 const known=byName("Enhanced Defense");
 let record=make(10);
 assert.equal(infusionGrantingTrait(record,[]),null);
 assert.throws(()=>learnInfusionPatch(record,known,definitions,mechanics,-1,[]),/Infuse Item/);
 record={...record,...learnInfusionPatch(record,known,definitions,mechanics,-1,[trait])};
 assert.equal(record.optional_features_catalog[0].source_trait_id,trait.origin_id);
 assert.equal(preparedInfusions(record,definitions).length,0);
 assert.throws(()=>applyInfusionPatch(record,learnedInfusions(record,definitions)[0],definitions,mechanics,0,[trait]),/non preparata/);
 record={...record,...prepareInfusionPatch(record,learnedInfusions(record,definitions)[0],true,definitions,[trait])};
 record.inventory=[{name:"Armor",id:"armor:test",type:"HA",rarity:"none",quantity:1,equipped_slots:["body"]}];
 record={...record,...applyInfusionPatch(record,preparedInfusions(record,definitions)[0],definitions,mechanics,0,[trait])};
 assert.equal(activeInfusions(record).length,1);
 const disabled={...record,origin_enabled:{[trait.origin_id]:false}};
 assert.equal(activeInfusions(disabled).length,0);
 assert.deepEqual(infusionNumericBonuses(disabled,disabled.inventory[0],definitions),{});
 record={...record,...prepareInfusionPatch(record,preparedInfusions(record,definitions)[0],false,definitions,[trait])};
 assert.equal(record.inventory[0].infusion,undefined);
 assert.equal(preparedInfusions(record,definitions).length,0);
 const legacy={...record};delete legacy.prepared_optional_features;
 assert.equal(preparedInfusions(legacy,definitions).length,1,"Legacy learned infusions remain ready");
});
