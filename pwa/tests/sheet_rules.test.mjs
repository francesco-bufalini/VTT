import {test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {calculateSheet,parseArithmetic,spellProgression,requirementsAllow,localClasses}
  from "../sheet_rules.js";
import {localSheetView} from "../sheet_rules_view.js";
import {fixedProficiencies,structuredFeatureGrants,automaticId} from "../structured_effects.js";

const load=file=>JSON.parse(readFileSync(fileURLToPath(new URL("../catalog/"+file+".json",import.meta.url)),"utf8"));
const catalogs={abilityGrants:load("ability_grants"),classMechanics:load("class_mechanics"),proficiencyGrants:load("proficiency_grants")};
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
    saving_throw_proficiencies:["str","con"],skill_proficiencies:["perception","athletics"]});
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
test("2014/2024 full, half, pact and multiclass slot progressions match Godot tables",()=>{
  const wizard=spellProgression(character(),[{name:"Wizard",level:5}]);
  assert.deepEqual(wizard.slots.slice(0,4),[0,4,3,2]);
  const multi=spellProgression({rules_version:"2014"},[{name:"Wizard",level:3},{name:"Paladin",level:3}]);
  assert.equal(multi.caster_level,4);
  const modern=spellProgression({rules_version:"2024"},[{name:"Wizard",level:3},{name:"Paladin",level:3}]);
  assert.equal(modern.caster_level,5);
  const warlock=spellProgression(character(),[{name:"Warlock",level:11}]);
  assert.equal(warlock.pact_total,3);
  assert.equal(warlock.pact_level,5);
  assert.equal(warlock.caster_level,0);
  const c=character({class:"Wizard",level:5,spell_slots_automatic:true,spell_slots_total:[0,4,3,2]});
  const value=calculateSheet(c,catalogs);
  assert.deepEqual(value.spell_slots.slice(0,3).map(x=>x.total),[4,3,2]);
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
test("all derived output stays on device and UI marks unsupported features",()=>{
  const c=character({name:"<script>bad</script>",class:"Wizard",level:5});
  const out=calculateSheet(c,catalogs);
  assert.equal(out.source,"local");
  assert.equal(out.complete,false);
  const stat=localSheetView("stats",out);
  assert.match(stat,/data-local-sheet-calculations/);
  assert.match(stat,/localmente sul dispositivo/);
  assert.match(stat,/Tiri salvezza/);
  assert.doesNotMatch(stat,/<script>/);
  assert.match(localSheetView("battle",out),/Classe armatura/);
  assert.match(localSheetView("magic",out),/Slot livello/);
  assert.equal(localSheetView("inventory",out),"");
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
