import {test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {
 artificerLevel,infusionLimits,learnedInfusions,infusionEligible,infusionNumericBonuses,
 infusionGrantingTrait,activeInfusions,
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


test("known infusions are immediately usable while disabled source still blocks them",()=>{
 const record=make(10),source=[infusionTrait],entry=byName("Enhanced Weapon");
 assert.equal(infusionGrantingTrait(record,source)?.origin_id,infusionTrait.origin_id);
 assert.equal(infusionLimits(record,mechanics,[]).active,0);
 assert.throws(()=>learnInfusionPatch(record,entry,definitions,mechanics,-1,[]),/limite|non disponibile/i);
 const learned={...record,...learnInfusionPatch(record,entry,definitions,mechanics,-1,source)};
 const option=learnedInfusions(learned,definitions)[0];
 assert.deepEqual(compatibleInfusionTargets({...learned,inventory:[sword()]},
   option,definitions,source).map(row=>row.index),[0]);
 const applied=applyInfusionPatch({...learned,inventory:[sword()]},option,definitions,mechanics,0,source);
 assert.equal(applied.inventory[0].infusion.id,entry.id);
 assert.deepEqual(targetableInventoryItems({...record,inventory:[sword()]},{kinds:["armor"]}),[]);
});
test("equipped and attuned infusion projects one magical trait; disabled source suppresses it",()=>{
 const entry=byName("Enhanced Arcane Focus"),source=[infusionTrait];
 const wand={id:"local_arcane_wand",name:"Arcane Wand",quantity:1,custom_item_type:"other",
   active:true,equipped:true,attuned:false,rarity:"none"};
 let record={...make(10),inventory:[wand]};
 record={...record,...learnInfusionPatch(record,entry,definitions,mechanics,-1,source)};
 let known=learnedInfusions(record,definitions)[0];

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

test("legacy preparation records cannot block learned infusions",()=>{
 const entry=byName("Enhanced Weapon");
 const record={...make(10),optional_features_catalog:[{id:entry.id,name:entry.name,source:"TCE"}],
   prepared_features:[] ,inventory:[sword()]};
 const known=learnedInfusions(record,definitions)[0];
 assert.deepEqual(compatibleInfusionTargets(record,known,definitions,[infusionTrait]).map(row=>row.index),[0]);
 assert.equal(applyInfusionPatch(record,known,definitions,mechanics,0,[infusionTrait]).inventory[0].infusion.id,entry.id);
});
test("only a worn/attuned infused item adds its source-bound descriptive trait",async()=>{
 const entry=byName("Enhanced Arcane Focus");
 const item={id:"local_arcane_wand",name:"Arcane Wand",quantity:1,
   custom_item_type:"other",active:true,equipped:true,attuned:true,rarity:"none"};
 let record={...make(10),inventory:[item]};
 record={...record,...learnInfusionPatch(record,entry,definitions,mechanics,-1,[infusionTrait])};
 const known=learnedInfusions(record,definitions)[0];

 record={...record,...applyInfusionPatch(record,known,definitions,mechanics,0,[infusionTrait])};
 const providers={
   entries:async category=>category==="class_features"?[infusionTrait]:
     category==="optional_features"?[{name:entry.name,source:"TCE"}]:[],
   detail:async(_category,row)=>({...row,entries:["Magical focus effect"]}),
   isDocument:()=>false
 };
 const calc={features:[infusionTrait],infusion_catalog:definitions};
 const traits=await collectTraitRows(record,calc,providers);
 const itemTraits=traits.filter(row=>row.category==="oggetti");
 assert.equal(itemTraits.length,1);
 assert.equal(itemTraits[0].name,"Arcane Wand - Enhanced Arcane Focus");
 assert.equal(itemTraits[0].infusion_origin_id,
  activeInfusions(record,definitions,[infusionTrait])[0].id);
 assert.ok(itemTraits[0].entries.includes("Magical focus effect"));
 assert.equal(traits.some(row=>row.origin.startsWith("Privilegio opzionale")),false);
 assert.equal(traits.some(row=>row.name==="Infusione · Enhanced Arcane Focus"),false);
 assert.equal(traits.some(row=>row.category==="stati"&&row.infusion_id),false);
 const unequipped={...record,inventory:[{...record.inventory[0],equipped:false,attuned:false}]};
 const hidden=await collectTraitRows(unequipped,calc,providers);
 assert.equal(hidden.find(row=>row.name==="Arcane Wand - Enhanced Arcane Focus")?.inactive,true);
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

test("non-equipment example names can be bypassed while armor/weapon/shield remain strict",()=>{
 const plain={id:"other:stone",name:"Smooth Pebble",custom_item_type:"other",quantity:1,rarity:"none",active:true};
 for(const name of ["Enhanced Arcane Focus","Boots of the Winding Path",
   "Helm of Awareness","Homunculus Servant","Spell-Refueling Ring"]){
   assert.equal(infusionEligible(byName(name),plain),true,name+" should allow generic objects");
 }
 for(const name of ["Enhanced Weapon","Enhanced Defense","Repulsion Shield",
   "Radiant Weapon","Armor of Magical Strength","Repeating Shot"]){
   assert.equal(infusionEligible(byName(name),plain),false,name+" should enforce equipment category");
 }
 const magic={...plain,id:"magic_item:stone",rarity:"rare"};
 assert.equal(infusionEligible(byName("Enhanced Arcane Focus"),magic),false,"nonmagical restriction survives");
 const robe={...plain,name:"Comfortable Robe"};
 assert.equal(infusionEligible(byName("Mind Sharpener"),robe),true,"robes are a valid alternative");
});
test("infusion descriptions are sourced from the packaged 5etools optional feature index",()=>{
 const compendium=JSON.parse(readFileSync(new URL("../../vtt/data/compendium_features_5etools.json",import.meta.url),"utf8"));
 for(const row of definitions.filter(row=>row.application_kind!=="replicate")){
   assert.equal(typeof row.description,"undefined","no manually authored infusion prose: "+row.name);
   const source=compendium.optional_features[row.name.toLowerCase()+"|"+row.source.toLowerCase()];
   assert(source?.entries?.length>0,"missing 5etools entries for "+row.name);
 }
 const variants=expandedInfusionDefinitions(definitions).filter(row=>row.application_kind==="replicate_variant");
 assert(variants.every(row=>row.description_source_name==="Replicate Magic Item"));
});
