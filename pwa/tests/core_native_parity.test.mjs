import "fake-indexeddb/auto";
import {test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync,existsSync} from "node:fs";
import {createCreature,loadCreature,openCreatureEditor,exportCreature} from "../creatures.js";
import {recoveryPatch,actionEntries,nativeSection} from "../native_sheet.js";
import {quickDefinition,quickGrantPatch,createQuickHomebrew,deleteQuickHomebrew} from "../catalog_data.js";
import {validDefinition} from "../creature_format.js";
import {fixedProficiencies} from "../structured_effects.js";
import {calculateSheet} from "../sheet_rules.js";

test("new PWA characters preserve the complete native core and evaluate locally", async()=>{
 const scope="pwa_core_"+Date.now();
 const saved=await createCreature("character","Ranger PWA",scope);
 const record=(await loadCreature(saved.id,scope)).data;
 assert.equal(record.kind,"character");
 assert.equal(record.level,1);
 assert.equal(record.abilities.dex,10);
 for(const key of ["classes","prepared_spells","inventory","resource_trackers","formula_bonuses","proficiency_choices"])
   assert.ok(Array.isArray(record[key]),key+" must be initialized");
 for(const key of ["resource_tracker_spent","origin_spell_configs","damage_defense_overrides","active_spell_context"])
   assert.equal(typeof record[key],"object",key);
 assert.equal(record.spell_slots_spent.length,10);
 const editor=await openCreatureEditor(saved.id,scope);
 await editor.update({abilities:{...record.abilities,dex:18},speed_base:35});
 await editor.flush();
 const reopened=(await loadCreature(saved.id,scope)).data;
 const sheet=calculateSheet(reopened,{});
 assert.equal(sheet.values["ability_mod:dex"],4);
 assert.equal(reopened.speed_base,35);
 const exported=JSON.parse(await (await exportCreature(saved.id,scope)).text());
 assert.equal(exported.creature.abilities.dex,18);
 assert.equal(exported.creature.spell_slots_spent.length,10);
});

test("recovery is explicit: pact on short rest, class slots on long rest",()=>{
 const c={spell_slots_spent:[0,1,2,0,0,0,0,0,0,0],pact_slots_spent:2,
  resource_tracker_spent:{short:2,long:1,manual:4,disabled:1}};
 const trackers=[
  {id:"short",recharge:"short_rest"},
  {id:"long",recharge:"long_rest"},
  {id:"manual",recharge:"manual"},
  {id:"disabled",recharge:"short_rest",disabled:true}];
 const short=recoveryPatch(c,"short_rest",trackers);
 assert.equal(short.pact_slots_spent,0);
 assert.equal(short.spell_slots_spent,undefined);
 assert.deepEqual(short.resource_tracker_spent,{long:1,manual:4,disabled:1});
 const turn=recoveryPatch(c,"turn",trackers);
 assert.equal(turn.pact_slots_spent,undefined);
 const long=recoveryPatch(c,"long_rest",trackers);
 assert.equal(long.pact_slots_spent,0);
 assert.deepEqual(long.spell_slots_spent,Array(10).fill(0));
 assert.deepEqual(long.resource_tracker_spent,{manual:4,disabled:1});
});

test("quick homebrew grants competencies only while the source is active",()=>{
 const feat=quickDefinition("feats","Sguardo vigile","Ottieni Percezione",
   [{kind:"skill",key:"perception"},{kind:"save",key:"wis"}],{},"local_test_feat");
 assert.equal(validDefinition(feat),true);
 const original={kind:"character",name:"Eroe",feats_catalog:[]};
 const active={...original,feats_catalog:[{id:feat.id,name:feat.name,source:feat.source}],
  ...quickGrantPatch(original,feat)};
 assert.equal(fixedProficiencies(active,{}).has("skill:perception"),true);
 assert.equal(fixedProficiencies(active,{}).has("save:wis"),true);
 assert.equal(fixedProficiencies({...active,feats_catalog:[]},{}).has("skill:perception"),false);
 assert.throws(()=>quickDefinition("items","X","",[],{value:-2},"local_test_item"),/Valore/);
});

test("quick homebrew can be created and removed from IndexedDB",async()=>{
 const name="PWA homebrew test "+Date.now();
 const definition=await createQuickHomebrew("items",name,"Prova",[],{custom_item_type:"tool",rarity:"common",value:12});
 assert.equal(validDefinition(definition),true);
 assert.equal(definition.data.custom_item_type,"tool");
 assert.equal(await deleteQuickHomebrew(definition.id),true);
 assert.equal(await deleteQuickHomebrew(definition.id),false);
});

test("server-served JS paths contain every imported runtime module",()=>{
 const ui=readFileSync(new URL("../ui.js",import.meta.url),"utf8");
 const native=readFileSync(new URL("../native_sheet.js",import.meta.url),"utf8");
 const serverPath=new URL("../../network/pwa_host.gd",import.meta.url);
 const imports=[...ui.matchAll(/from\s+["']\.\/(.+?\.js)["']/g),...native.matchAll(/from\s+["']\.\/(.+?\.js)["']/g)];
 // browser-assets CI checks out only pwa/. Native-loopback verifies endpoint serving.
 if(existsSync(serverPath)){
   const server=readFileSync(serverPath,"utf8");
   for(const match of imports)
     assert.ok(server.includes('"/'+match[1]+'"'),"Godot must serve /"+match[1]);
 }
 assert.match(ui,/from\s+["']\.\/action_economy\.js/);
});

test("native-style Info keeps derived identity and health editors without optional narrative details",()=>{
 const c={kind:"character",name:"Arciere",species:"Elf",species_source:"PHB",
   class:"Wizard",class_source:"PHB",classes:[
     {name:"Wizard",source:"PHB",level:4},{name:"Fighter",source:"PHB",level:1}],
   abilities:{str:10,dex:10,con:10,int:10,wis:10,cha:10}};
 const field=(name,key,value,type="text")=>'<input data-field="'+key+'" value="'+(value??"")+'" type="'+type+'">';
 const area=(name,key)=>'<textarea data-field="'+key+'"></textarea>';
 const panel=(name,content)=>'<section>'+content+'</section>';
 const calculated={values:{},stats:{max_hp:5},automatic_bonuses:[],origins:[]};
 const options={field,area,panel,resources:"",equipment:"",armor:"",attacks:"",calculated,
   catalogs:{races:[{name:"Elf",source:"PHB"}]}};
 const info=nativeSection(c,"info",options);
 const battle=nativeSection(c,"battle",options);
 assert.match(info,/<dt>Tipo<\/dt><dd>Umanoide<\/dd>/);
 assert.match(info,/Classi secondarie/);
 assert.match(info,/data-native-list="classes" data-index="1"/);
 assert.doesNotMatch(info,/data-native-list="classes" data-index="0"/);
 assert.doesNotMatch(info,/data-field="(appearance|player_name|inspiration|notes)"/);
 assert.doesNotMatch(info,/Aspetto, identità e personalità/);
 assert.doesNotMatch(battle,/data-field="death_save_successes"/);
 assert.doesNotMatch(battle,/data-field="death_save_failures"/);
 assert.match(battle,/class="battle-hp-grid"/);
 assert.match(battle,/data-act="hp-restore-second"/);
 assert.ok(battle.indexOf('battle-hp-controls')<battle.indexOf('battle-defense-values'),
   'The armor class is displayed immediately after hit points');
 const spells=actionEntries({spells:[{id:"spell_1"}]},
  {attacks:[{id:"bow",name:"Arco",damage:"1d8"}]},
  [{id:"spell_1",name:"Incantesimo",level:1,time:[{unit:"action"}]}]);
 assert.ok(spells.some(s=>s.name==="Incantesimo"));
 assert.ok(spells.some(s=>s.name==="Arco"));
});
