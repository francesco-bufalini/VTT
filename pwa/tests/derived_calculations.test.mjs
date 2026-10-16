import {test} from "node:test";
import assert from "node:assert/strict";
import {offlineBasics,derivedContent} from "../derived_calculations.js";

test("offline shows only deterministic base modifiers and class proficiency",()=>{
  const record={kind:"character",level:5,abilities:{str:18,dex:9,wis:15,con:10}};
  const result=offlineBasics(record);
  assert.equal(result.source,"offline");
  assert.equal(result.abilities.str.modifier,4);
  assert.equal(result.abilities.dex.modifier,-1);
  assert.equal(result.abilities.wis.modifier,2);
  assert.equal(result.stats.proficiency,3);
  assert.equal(result.stats.armor_class,undefined,"never invent effective armor class");
  assert.equal(result.stats.initiative,undefined,"never invent bonus-dependent initiative");
  const panel=derivedContent("battle",result);
  assert.match(panel,/Godot/);
  assert.doesNotMatch(panel,/Classe armatura/);
});
test("native results are labeled and presented without interpreting user input as HTML",()=>{
  const fake={source:"godot",schema:1,abilities:{dex:{modifier:2,score:14}},
    saves:{dex:4},skills:{perception:3},stats:{proficiency:2,initiative:3,
      armor_class:15,max_hp:27,passive_perception:13,speeds:{walk:30}},
    spell_slots:[{level:1,total:3,spent:1}],pact_slots:{total:0},
    attacks:[{name:"<img src=x>",hit:5,damage:"1d8",hit_formula:"<script>evil</script>"}]};
  assert.match(derivedContent("battle",fake),/Classe armatura/);
  assert.match(derivedContent("battle",fake),/15/);
  assert.doesNotMatch(derivedContent("battle",fake),/<img src=x>/);
  assert.doesNotMatch(derivedContent("battle",fake),/<script>/);
  assert.match(derivedContent("magic",fake),/2 \/ 3/);
  assert.match(derivedContent("stats",fake),/Tiri salvezza/);
});
