import {test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {calculateSheet,parseArithmetic,spellProgression,requirementsAllow,localClasses}
  from "../sheet_rules.js";
import {localSheetView} from "../sheet_rules_view.js";

const load=file=>JSON.parse(readFileSync(fileURLToPath(new URL("../catalog/"+file+".json",import.meta.url)),"utf8"));
const catalogs={abilityGrants:load("ability_grants"),classMechanics:load("class_mechanics")};
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
