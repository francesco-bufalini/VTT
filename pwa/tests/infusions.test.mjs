import {test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {
 artificerLevel,infusionLimits,learnedInfusions,infusionEligible,infusionNumericBonuses,
 infusionGrantingTrait,isInfusionPrepared,prepareInfusionPatch,activeInfusions,
 targetableInventoryItems,compatibleInfusionTargets,
 learnInfusionPatch,applyInfusionPatch,clearInfusionPatch,forgetInfusionPatch,expandedInfusionDefinitions
} from "../item_controls.js";
import {calculateSheet} from "../sheet_rules.js";
import {collectTraitRows} from "../trait_projection.js";
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

test("only a worn/attuned infused item adds its source-bound descriptive trait",async()=>{
 const entry=byName("Enhanced Arcane Focus");
 const item={id:"local_arcane_wand",name:"Arcane Wand",quantity:1,
   custom_item_type:"other",active:true,equipped:true,attuned:true,rarity:"none"};
 let record={...make(10),inventory:[item]};
 record={...record,...learnInfusionPatch(record,entry,definitions,mechanics,-1,[infusionTrait])};
 const known=learnedInfusions(record,definitions)[0];
 record={...record,...prepareInfusionPatch(record,known,definitions,[infusionTrait],true)};
 record={...record,...applyInfusionPatch(record,known,definitions,mechanics,0,[infusionTrait])};
 const providers={
   entries:async category=>category==="class_features"?[infusionTrait]:
     category==="optional_features"?[{name:entry.name,source:"TCE"}]:[],
   detail:async(_category,row)=>({...row,entries:["Magical focus effect"]}),
   isDocument:()=>false
 };
 const calc={features:[infusionTrait],infusion_catalog:definitions};
 const traits=await collectTraitRows(record,calc,providers);
 const active=traits.filter(row=>row.name==="Infusione · Enhanced Arcane Focus");
 assert.equal(active.length,1);
 assert.equal(active[0].category,"oggetti");
 assert.equal(active[0].feature_origin,activeInfusions(record,definitions,[infusionTrait])[0].id);
 assert.deepEqual(active[0].entries,["Magical focus effect"]);
 const unequipped={...record,inventory:[{...record.inventory[0],equipped:false,attuned:false}]};
 const hidden=await collectTraitRows(unequipped,calc,providers);
 assert.equal(hidden.some(row=>row.name==="Infusione · Enhanced Arcane Focus"),false);
});


test("infusion bonus provenance remains valid and withdraws with the granting trait",()=>{
 const entry=byName("Enhanced Arcane Focus");
 const item={id:"local_wand",instance_id:"wand_1",name:"Arcane Wand",quantity:1,
   custom_item_type:"other",active:true,equipped:true,attuned:true,rarity:"none",
   infusion:{id:entry.id,name:entry.name,creator_id:"artificer_test",level:10,requires_attunement:true}};
 const record={...make(10),inventory:[item]};
 const result=calculateSheet(record,sheetCatalogs);
 const grant=result.bonuses.find(g=>g.target==='spell_attack'&&String(g.source_id||g.origin_id||'').startsWith('infusion:'));
 assert.ok(grant,'The active infusion must have its own verifiable source');
 assert.equal(result.values.spell_attack,2);
 const disabled={...record,origin_enabled:{[result.features.find(f=>f.name==='Infuse Item').origin_id]:false}};
 assert.equal(calculateSheet(disabled,sheetCatalogs).values.spell_attack,0);
});

test("Replicate Magic Item expands to distinct options, each usable on any owned item",()=>{
 const expanded=expandedInfusionDefinitions(definitions);
 const base=definitions.find(row=>row.application_kind==="replicate");
 const variants=expanded.filter(row=>row.application_kind==="replicate_variant");
 assert.equal(variants.length,base.replicable_items.length);
 assert(variants.every(row=>row.item_selector&&Object.keys(row.item_selector).length===0));
 const bag=variants.find(row=>row.name.includes("Bag of holding"));
 assert(bag&&bag.min_level===2);
 const advanced=variants.find(row=>row.name.includes("Winged boots"));
 assert(advanced&&advanced.min_level===10);
 let c=make(10);c.inventory=[sword()];
 c={...c,...learnInfusionPatch(c,bag,expanded,mechanics,-1,[infusionTrait])};
 const known=learnedInfusions(c,expanded)[0];
 assert.equal(known.plan_item_id,"");
 c={...c,...prepareInfusionPatch(c,known,expanded,[infusionTrait],true)};
 assert.deepEqual(compatibleInfusionTargets(c,known,expanded,[infusionTrait]).map(x=>x.index),[0]);
 c={...c,...applyInfusionPatch(c,known,expanded,mechanics,0,[infusionTrait])};
 assert.equal(c.inventory[0].infusion.id,bag.id);
});
test("Old generic Replicate Magic Item records still resolve",()=>{
 const original=definitions.find(row=>row.application_kind==="replicate");
 const expanded=expandedInfusionDefinitions(definitions);
 const c=make(10);c.optional_features_catalog=[{id:original.id,name:original.name,
   plan_item_id:"magic_item:bag_of_holding",plan_item_name:"Bag of holding"}];
 assert.equal(learnedInfusions(c,expanded).length,1);
 assert.equal(learnedInfusions(c,expanded)[0].legacy_replicate,true);
});
