import {test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {calculateSheet,parseArithmetic,spellProgression,requirementsAllow,localClasses}
  from "../sheet_rules.js";
import {rollBattleDamage,sheetRollChatFields} from "../sheet_rules_view.js";
import {fixedProficiencies,structuredFeatureGrants,automaticId} from "../structured_effects.js";

const load=file=>JSON.parse(readFileSync(fileURLToPath(new URL("../catalog/"+file+".json",import.meta.url)),"utf8"));
const catalogs={abilityGrants:load("ability_grants"),classMechanics:load("class_mechanics"),proficiencyGrants:load("proficiency_grants")};
const castingCatalogs={...catalogs,classFeatures:load("classes"),spellcastingBenefits:load("spellcasting_benefits")};
const castingProfile=(name,source='PHB')=>castingCatalogs.spellcastingBenefits.grants.find(row=>
  row.feature_id.startsWith('5etools:class_features:'+source.toLowerCase()+':')&&
  row.benefit.level_class===name)?.benefit.slot_progression;
const character=(overrides={})=>({kind:"character",level:1,abilities:{str:10,dex:14,con:12,int:10,wis:10,cha:10},
  armor_class_base:10,max_hp_base:12,speed_base:30,inventory:[],...overrides});

test("arithmetic grants use safe grammar, rounding and reject code",()=>{
  assert.equal(parseArithmetic("4 + dex_mod * (3 - 1)",k=>k==="dex_mod"?2:0),8);
  assert.equal(parseArithmetic("(1+2)/2",()=>0),2);
  assert.equal(parseArithmetic("-1.5",()=>0),-2);
  assert.equal(parseArithmetic(".5",()=>0),1);
  assert.throws(()=>parseArithmetic("Math.random()"),/non valida/);
  assert.throws(()=>parseArithmetic("1/0"),/zero/);
  assert.throws(()=>parseArithmetic("2d6",()=>0),/non valida/);
  assert.throws(()=>parseArithmetic("1 + undefined_var",()=>{throw Error("Sconosciuta")}),/Sconosciuta/);
});
test("unarmored 5e character derives native-style AC, initiative, skills and saves",()=>{
  const c=character({class:"Fighter",level:5,
    proficiency_choices:[{kind:"save",key:"str"},{kind:"save",key:"con"},
      {kind:"skill",key:"perception"},{kind:"skill",key:"athletics"}]});
  const out=calculateSheet(c,catalogs);
  assert.equal(out.abilities.dex.modifier,2);
  assert.equal(out.stats.proficiency,3);
  assert.equal(out.stats.armor_class,12);
  assert.equal(out.stats.initiative,2);
  assert.equal(out.saves.str,3);
  assert.equal(out.saves.con,4);
  assert.equal(out.skills.athletics,3);
  assert.equal(out.skills.perception,3);
  assert.equal(out.stats.passive_perception,13);
  assert.equal(out.stats.speeds.walk,30);
});
test("armor and shield use actual occupied slots and dexterity caps",()=>{
  const armor={id:"local_armor",custom_item_type:"armor",type:"MA",ac:14,quantity:1,equipped_slots:["body"]};
  const shield={id:"local_shield",custom_item_type:"shield",type:"S",ac:2,quantity:1,equipped_slots:["off"]};
  assert.equal(calculateSheet(character({inventory:[armor,shield]}),catalogs).stats.armor_class,18);
  assert.equal(calculateSheet(character({inventory:[{...armor,type:"HA",ac:16},shield]}),catalogs).stats.armor_class,18);
  assert.equal(calculateSheet(character({inventory:[{...armor,type:"LA",ac:12},shield]}),catalogs).stats.armor_class,16);
  assert.equal(calculateSheet(character({inventory:[{...armor,equipped_slots:[]},shield]}),catalogs).stats.armor_class,14);
  assert.equal(calculateSheet(character({inventory:[shield,{...shield,id:"local_shield2",equipped_slots:["main"]}]}),catalogs).stats.armor_class,14);
});
test("attack ability scope and versatile two-handed damage honor the shared equipment settings",()=>{
 const versatile={id:"vers",name:"Stocco versatile",custom_item_type:"weapon",type:"M",
   quantity:1,damage:"1d6",versatile_damage:"1d8",properties:["F","V"],equipped_slots:["main"]};
 const plain={id:"plain",name:"Mazza",custom_item_type:"weapon",type:"M",
   quantity:1,damage:"1d8",properties:[],equipped_slots:["main"]};
 const base=character({abilities:{str:16,dex:12,con:12,int:10,wis:10,cha:10},
   attack_ability:"dex",attack_ability_finesse_only:true});
 const roll=(item,extra={})=>calculateSheet({...base,...extra,inventory:[item]},catalogs).attacks
   .find(attack=>attack.id==="item:"+item.id);
 assert.equal(roll(versatile).ability,"dex");
 assert.equal(roll(plain).ability,"str");
 assert.equal(roll(plain,{attack_ability_finesse_only:false}).ability,"dex");
 assert.equal(roll(versatile,{hand_grip_two_handed:true}).damage,"1d8 + 1");
 const withOff=calculateSheet({...base,hand_grip_two_handed:true,inventory:[
   versatile,{...plain,equipped_slots:["off"]}]},catalogs).attacks.find(a=>a.id==="item:vers");
 assert.equal(withOff.damage,"1d6 + 1","Two-handed versatile damage requires the off-hand to be free");
});

test("worn shield grants improvised attack and removal withdraws it",()=>{
 const shield={id:"sh",name:"Scudo",custom_item_type:"shield",type:"S",ac:2,quantity:1,equipped_slots:["off"]};
 const withShield=calculateSheet(character({inventory:[shield],abilities:{str:16,dex:14,con:12,int:10,wis:10,cha:10}}),catalogs);
 const hit=withShield.attacks.find(a=>a.id==="shield:improvised:off:sh");
 assert(hit);assert.equal(hit.damage,"1d4 + 3");assert.equal(hit.hit,3);
 assert.equal(hit.range_feet,5);assert.equal(hit.damage_type,"contundente");
 assert.equal(withShield.values?.["attack_hit:shield:improvised:off:sh"],3);
 const without=calculateSheet(character({inventory:[{...shield,equipped_slots:[]}]}),catalogs);
 assert(!without.attacks.some(a=>a.id.startsWith("shield:improvised:")));
});

test("automatic unarmed strikes and shield respect offhand availability",()=>{
 const base=character({abilities:{str:16,dex:14,con:12,int:10,wis:10,cha:10}});
 const attacks=extra=>calculateSheet({...base,...extra},catalogs).attacks;
 const bare=attacks({});
 assert(bare.some(a=>a.id==="unarmed"&&!a.offhand_bonus));
 assert(bare.some(a=>a.id==="unarmed:off"&&a.slot==="off"&&a.offhand_bonus));
 assert.equal(bare.find(a=>a.id==="unarmed:off").damage,"4");
 assert.equal(bare.filter(a=>a.id.startsWith("unarmed")).length,2);
 const shield={id:"shield",name:"Scudo",type:"S",custom_item_type:"shield",ac:2,quantity:1,equipped_slots:["off"]};
 const protectedHands=attacks({inventory:[shield]});
 assert(!protectedHands.some(a=>a.id==="unarmed:off"),"No unarmed offhand while shield occupies it");
 assert(protectedHands.some(a=>a.id==="shield:improvised:off:shield"&&a.offhand_bonus));
 const greatsword={id:"great",name:"Spadone",type:"M",custom_item_type:"weapon",
  damage:"2d6",properties:["2H"],quantity:1,equipped_slots:["main"]};
 assert(!attacks({inventory:[greatsword]}).some(a=>a.id==="unarmed:off"));
 assert(attacks({inventory:[greatsword],hand_off_with_two_handed:true}).some(a=>a.id==="unarmed:off"));
 assert(attacks({inventory:[greatsword,shield],hand_off_with_two_handed:true})
  .some(a=>a.id==="shield:improvised:off:shield"&&a.offhand_bonus));
 const special=attacks({hand_main_special:"unarmed",hand_off_special:"unarmed"});
 assert.deepEqual(special.filter(a=>a.id.startsWith("unarmed")).map(a=>a.id),["unarmed","unarmed:off"],
  "Legacy manual unarmed selections must not cause duplicates");
});

test("2014/2024 full, half, pact and multiclass slot progressions match Godot tables",()=>{
  const wizard=spellProgression(character(),[{slot_progression:castingProfile("Wizard"),level:5}]);
  assert.deepEqual(wizard.slots.slice(0,4),[0,4,3,2]);
  const multi=spellProgression({rules_version:"2014"},[{slot_progression:castingProfile("Wizard"),level:3},{slot_progression:castingProfile("Paladin"),level:3}]);
  assert.equal(multi.caster_level,4);
  const modern=spellProgression({rules_version:"2024"},[{slot_progression:castingProfile("Wizard","XPHB"),level:3},{slot_progression:castingProfile("Paladin","XPHB"),level:3}]);
  assert.equal(modern.caster_level,5);
  const warlock=spellProgression(character(),[{slot_progression:castingProfile("Warlock"),level:11}]);
  assert.equal(warlock.pact_total,3);
  assert.equal(warlock.pact_level,5);
  assert.equal(warlock.caster_level,0);
  const c=character({class:"Wizard",level:5,spell_slots_automatic:true,spell_slots_total:[0,4,3,2]});
  const withoutTraits=calculateSheet(c,catalogs);
  assert.deepEqual(withoutTraits.spell_slots.slice(0,3).map(x=>x.total),[0,0,0],
    "Missing class-feature catalog cannot grant class slots from levels");
  assert.equal(withoutTraits.casting_classes.length,0);
  const withTraits=calculateSheet(c,castingCatalogs);
  assert.deepEqual(withTraits.spell_slots.slice(0,3).map(x=>x.total),[4,3,2]);
  assert.equal(withTraits.casting_classes[0].granting_trait_name,"Spellcasting");
  const muted={...c,origin_enabled:{[withTraits.casting_classes[0].granting_trait_id]:false}};
  assert.equal(calculateSheet(muted,castingCatalogs).spell_slots[0].total,0);
});
test("5etools structured racial and feat ability increases apply without Godot",()=>{
  const c=character({species:"Aarakocra",species_source:"EEPC",feats_catalog:[{name:"Actor",source:"PHB"}]});
  const out=calculateSheet(c,catalogs);
  assert.equal(out.abilities.dex.score,16);
  assert.equal(out.abilities.dex.modifier,3);
  assert.equal(out.abilities.wis.score,11);
  assert.equal(out.abilities.cha.score,11);
  assert.equal(out.stats.armor_class,13);
});
test("saved arithmetic bonuses, thresholds and cycling formulas cannot corrupt sheet",()=>{
  const c=character({class:"Wizard",level:5,formula_bonuses:[
    {id:"a",target:"ability:dex",expression:"2"},
    {id:"b",target:"initiative",expression:"wis_mod + 1",requirements:{min_level:5}},
    {id:"c",target:"ac",expression:"1",requirements:{min_level:6}},
    {id:"d",target:"speed",expression:"10"},
    {id:"e",target:"proficiency",expression:"ac",disabled:true}
  ]});
  const out=calculateSheet(c,catalogs);
  assert.equal(out.abilities.dex.score,16);
  assert.equal(out.stats.armor_class,13);
  assert.equal(out.stats.initiative,4);
  assert.equal(out.stats.speeds.walk,40);
  assert.equal(out.stats.proficiency,3);
  assert.equal(requirementsAllow(c,{requirements:{scope:"class",class_name:"Wizard",min_level:5}}),true);
  assert.equal(requirementsAllow(c,{requirements:{scope:"class",class_name:"Cleric",min_level:1}}),false);
  const cyclic=calculateSheet(character({formula_bonuses:[
    {target:"ability:dex",expression:"initiative"},
    {target:"initiative",expression:"dex_mod"}
  ]}),catalogs);
  assert.ok(cyclic.warnings.some(w=>/circolare/.test(w)));
});
test("automatic HP uses native hit die table with constitution and first-level maximum",()=>{
  const c=character({class:"Wizard",level:5,abilities:{...character().abilities,con:14}});
  const out=calculateSheet(c,catalogs);
  assert.equal(out.stats.automatic_hp.available,true);
  assert.equal(out.stats.automatic_hp.value,32);
});
test("local derived values remain available offline without the obsolete summary renderer",()=>{
 const c=character({name:"<script>bad</script>",class:"Wizard",level:5});
 const out=calculateSheet(c,catalogs);
 assert.equal(out.source,"local");
 assert.equal(out.complete,false);
 assert.equal(typeof out.stats.armor_class,"number");
 assert.equal(typeof out.stats.proficiency,"number");
 assert.ok(Array.isArray(out.spell_slots));
 const withTraits=calculateSheet(c,castingCatalogs);
 assert.ok(withTraits.spell_slots.some(slot=>slot.total>0));
});

test("disabling a saved origin withdraws its ability and skill bonuses offline",()=>{
  const origin="race|eepc|aarakocra";
  const c=character({species:"Aarakocra",species_source:"EEPC",
    proficiency_origins:[{id:origin,disabled:true}],
    proficiency_choices:[{kind:"skill",key:"perception",origin_id:origin,disabled:false}]});
  const out=calculateSheet(c,catalogs);
  assert.equal(out.abilities.dex.score,14);
  assert.equal(out.skills.perception,0);
  const enabled=calculateSheet({...c,proficiency_origins:[{id:origin,disabled:false}]},catalogs);
  assert.equal(enabled.abilities.dex.score,16);
  assert.equal(enabled.skills.perception,2);
});

test("automatic fixed proficiencies match native 5etools and do not auto-pick choices",()=>{
  const c=character({class:"Fighter",class_source:"PHB",
    species:"Aarakocra",species_source:"DMG",background:"Acolyte",background_source:"PHB"});
  const computed=fixedProficiencies(c,catalogs.proficiencyGrants);
  assert.equal(computed.has("save:str"),true);
  assert.equal(computed.has("save:con"),true);
  assert.equal(computed.has("skill:insight"),true);
  assert.equal(computed.has("skill:religion"),true);
  assert.equal(computed.has("skill:acrobatics"),false,
    "Selectable class skills must not be granted without a choice");
  const derived=calculateSheet(c,catalogs);
  assert.equal(derived.saves.con,3);
  assert.equal(derived.skills.insight,3,"WIS +1 and fixed proficiency +2");
  assert.equal(derived.skills.religion,2,"INT +0 and fixed proficiency +2");
  const suppressed=calculateSheet({...c,
    proficiency_origins:[{id:"background|phb|acolyte",disabled:true}]},catalogs);
  assert.equal(suppressed.skills.insight,1,"Muting an origin removes proficiency, not racial Wisdom");
  assert.equal(fixedProficiencies({...c,
    proficiency_origins:[{id:"background|phb|acolyte",disabled:true}]},
    catalogs.proficiencyGrants).has("skill:insight"),false);
});
test("stable native bonus IDs allow disabling only one derived racial bonus",()=>{
  const c=character({species:"Aarakocra",species_source:"EEPC"});
  const before=calculateSheet(c,catalogs);
  assert.equal(before.abilities.dex.score,16);
  assert.equal(before.abilities.wis.score,11);
  const target=automaticId("race|eepc|aarakocra","ability","ability:dex");
  assert.equal(target,"auto|race|eepc|aarakocra|ability|ability:dex");
  const after=calculateSheet({...c,formula_bonuses:[
    {id:target,target:"ability:dex",expression:"2",automatic:true,disabled:true}
  ]},catalogs);
  assert.equal(after.abilities.dex.score,14);
  assert.equal(after.abilities.wis.score,11);
  assert.equal(before.abilities.dex.score,16,"Source data must not mutate");
});
test("generic typed monster traits grant numeric effects without parsing entries",()=>{
  const m=character({kind:"monster",stat_block:{cr:"2",trait:[
    {id:"shell",name:"Natural Shell",
      entries:["Flavor only"],bonuses:[{target:"ac",expression:"2"}]},
    {id:"bad",name:"Description only",
      entries:["You gain +100 AC from a sentence."]}
  ]}});
  const grants=structuredFeatureGrants(m);
  assert.equal(grants.length,1);
  assert.equal(grants[0].id,"auto|feature:monster|trait|shell|bonuses|ac|ac");
  assert.equal(calculateSheet(m,catalogs).stats.armor_class,12);
  const disabled=calculateSheet({...m,formula_bonuses:[
    {id:grants[0].id,automatic:true,disabled:true,target:"ac",expression:"2"}
  ]},catalogs);
  assert.equal(disabled.stats.armor_class,10);
});
test("typed feat sections and class feature thresholds use generic native eligibility",()=>{
  const feat={id:"localFeat",name:"Homebrew feat",source:"HB",
    feature_sections:[{id:"feat_armor",name:"Guarded",min_level:4,
      bonuses:[{target:"ac",expression:"1"}]}]};
  const klass={name:"Wizard",source:"PHB",level:5,features:[
    {id:"class_defense",name:"Warding",level:5,
      bonuses:[{target:"ac",expression:"2"}]}
  ]};
  const low=calculateSheet(character({level:3,classes:[{...klass,level:3}],
    feats_catalog:[feat]}),catalogs);
  const high=calculateSheet(character({level:5,classes:[klass],
    feats_catalog:[feat]}),catalogs);
  assert.equal(low.stats.armor_class,12);
  assert.equal(high.stats.armor_class,15);
  const muted=calculateSheet(character({level:5,classes:[klass],
    feats_catalog:[{...feat,disabled:true}]}),catalogs);
  assert.equal(muted.stats.armor_class,14);
  const mutedOrigin=calculateSheet(character({level:5,classes:[klass],
    feats_catalog:[feat],proficiency_origins:[{id:"class|phb|wizard",disabled:true}]}),catalogs);
  assert.equal(mutedOrigin.stats.armor_class,13);
});
test("native item bonuses use stable per-item IDs, including attack and spell adjustments",()=>{
  const item={id:"local_wand",name:"Test wand",quantity:1,
    custom_item_type:"other",equipped:true,bonusSpellAttack:2,bonusSpellSaveDc:1,
    bonusSavingThrowConcentration:3};
  const rows=calculateSheet(character({inventory:[item]}),catalogs);
  assert.equal(rows.stats.armor_class,12);
  const weapon={id:"local_blade",name:"Blade",custom_item_type:"weapon",type:"M",
    damage:"1d6",equipped_slots:["main"],quantity:1,bonusWeaponAttack:3};
  const withWeapon=calculateSheet(character({inventory:[weapon]}),catalogs);
  assert.equal(withWeapon.stats.armor_class,12);
});

test("switching origins withdraws saved proficiencies from a replaced background",()=>{
  const characterWithLegacyOrigin=character({
    background:"Noble",background_source:"PHB",
    proficiency_choices:[{kind:"skill",key:"religion",origin_id:"background|phb|acolyte",
      origin_name:"Acolyte",disabled:false}],
    proficiency_origins:[{id:"background|phb|acolyte",disabled:false}]
  });
  const result=fixedProficiencies(characterWithLegacyOrigin,catalogs.proficiencyGrants);
  assert.equal(result.has("skill:religion"),false,
    "Former backgrounds cannot keep granting proficiencies after replacement");
  const derived=calculateSheet(characterWithLegacyOrigin,catalogs);
  assert.equal(derived.skills.religion,0);
  const active=calculateSheet({...characterWithLegacyOrigin,
    background:"Acolyte",background_source:"PHB"},catalogs);
  assert.equal(active.skills.religion,2);
});

test("battle damage rolls use bounded dice notation and desktop-compatible chat events",()=>{
 const die=sides=>sides===8?5:sides===4?3:2;
 const result=rollBattleDamage("2d8 + 1d4 + 3",die);
 assert.equal(result.total,16);
 assert.equal(result.modifier,3);
 assert.equal(result.notation,"2d8+1d4+3");
 assert.deepEqual(result.parts.map(row=>row.rolls),[[5,5],[3]]);
 const event=sheetRollChatFields(result);
 assert.equal(event.die,"formula");
 assert.equal(event.terms.length,2);
 assert.equal(event.modifier,3);
 assert.equal(rollBattleDamage("1d6 - 2",()=>4).total,2);
 for(const invalid of ["", "alert(1)", "1d6-1d4", "101d6", "1d0", "10000","2d6+1d4+foo"])
  assert.throws(()=>rollBattleDamage(invalid,()=>1),/danni|dadi/i);
});
