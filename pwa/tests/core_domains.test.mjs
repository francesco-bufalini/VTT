import "fake-indexeddb/auto";
import {test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {initialCreature,changeTrackerUses,spendTrackerUses,recoveryPatch} from "../character_core.js";
import {classSpellSections,eligibleForClass,assignClassSpell,revokeClassSpell,classSpellId} from "../class_spells.js";
import {quickDefinition,createQuickHomebrew,quickGrantPatch,deleteQuickHomebrew} from "../quick_homebrew.js";
import {createCreature,openCreatureEditor,exportCreature,loadCreature} from "../creatures.js";
import {fixedProficiencies} from "../structured_effects.js";

test("new browser character uses native Android core defaults without shared references",async()=>{
 const row=await createCreature("character","Esploratore");
 const c=row.data;
 assert.equal(c.rules_version,"2014");
 assert.equal(c.abilities.str,10);
 assert.equal(c.max_hp_base,1);
 assert.equal(c.pact_slot_level,1);
 assert.equal(c.spell_slots_total.length,10);
 assert.deepEqual(c.classes,[]);
 assert.deepEqual(c.resource_trackers,[]);
 assert.deepEqual(c.proficiency_choices,[]);
 assert.deepEqual(c.attack_overrides,{});
 assert.equal(c.linked_token_sync_id,"");
 assert.deepEqual(c.resource_recovery_ready,{});
 assert.deepEqual(c.resource_recovery_used,{});
 assert.deepEqual(c,initialCreature("character",c.name,c.id,c.owner_id),
   "Archive and domain factory must keep the same native-compatible defaults");
 const other=initialCreature("character","Altro","local_second","owner_second");
 other.spell_slots_spent[2]=1;
 other.abilities.str=18;
 assert.equal(c.spell_slots_spent[2],0,"Default arrays must not share references");
 assert.equal(c.abilities.str,10,"Default objects must not share references");
 const monster=initialCreature("monster","Sentinella","local_monster","owner_monster");
 assert.deepEqual(monster.stat_block,{});
 assert.deepEqual(monster.resource_recovery_ready,{});
 assert.deepEqual(monster.resource_recovery_used,{});
});
test("resource operations recover only the correct rest types and keep stable IDs",()=>{
 const c=initialCreature("character","Mago","id","owner");
 c.resource_trackers=[
  {id:"turn",name:"Turn",max:2,recharge:"turn"},
  {id:"short",name:"Short",max:3,recharge:"short_rest"},
  {id:"long",name:"Long",max:1,recharge:"long_rest"},
  {id:"manual",name:"Manual",max:4,recharge:"manual"}];
 c.resource_tracker_spent={turn:1,short:2,long:1,manual:3,missing:2};
 c.spell_slots_spent=[0,2,1,0,0,0,0,0,0,0];
 c.pact_slots_spent=2;
 assert.deepEqual(changeTrackerUses(c,"short",-1).resource_tracker_spent.short,1);
 assert.equal(changeTrackerUses(c,"long",-1).resource_tracker_spent.long,undefined);
 assert.equal(changeTrackerUses(c,"short",1).resource_tracker_spent.short,3);
 assert.throws(()=>changeTrackerUses(c,"invalid",1),/non disponibile/);
 const turn=recoveryPatch(c,"turn");
 assert.equal(turn.resource_tracker_spent.turn,undefined);
 assert.equal(turn.resource_tracker_spent.short,2);
 assert.equal(turn.pact_slots_spent,undefined);
 const short=recoveryPatch(c,"short_rest");
 assert.equal(short.resource_tracker_spent.short,undefined);
 assert.equal(short.resource_tracker_spent.long,1);
 assert.equal(short.resource_tracker_spent.manual,3);
 assert.equal(short.resource_tracker_spent.missing,2);
 assert.equal(short.pact_slots_spent,0);
 assert.equal(short.spell_slots_spent,undefined);
 const long=recoveryPatch(c,"long_rest");
 assert.equal(long.resource_tracker_spent.short,undefined);
 assert.equal(long.resource_tracker_spent.long,undefined);
 assert.equal(long.resource_tracker_spent.manual,3);
 assert.deepEqual(long.spell_slots_spent,Array(10).fill(0));
 assert.deepEqual(c.resource_tracker_spent,{turn:1,short:2,long:1,manual:3,missing:2},"Rest must be pure");
});
test("class spell selection applies per-class progressions, level limits and identities",()=>{
 const file=readFileSync(fileURLToPath(new URL("../catalog/class_mechanics.json",import.meta.url)),"utf8");
 const catalog=JSON.parse(file);
 const c={rules_version:"2014",abilities:{int:16,cha:14},
  classes:[{name:"Wizard",source:"PHB",level:5},{name:"Bard",source:"PHB",level:3}]};
 const sections=classSpellSections(c,catalog);
 const wizard=sections.find(s=>s.name==="Wizard"),bard=sections.find(s=>s.name==="Bard");
 assert.equal(wizard.id,classSpellId("Wizard","PHB"));
 assert.equal(wizard.mode,"Preparati");
 assert.equal(wizard.limit,8);
 assert.equal(wizard.max_level,3);
 assert.equal(wizard.book,true);
 assert.equal(bard.mode,"Conosciuti");
 assert.equal(bard.limit,6);
 assert.equal(bard.max_level,2,"Overall multiclass slots must not grant third-level Bard spells");
 const spell={id:"spell:light|phb",name:"Light",source:"PHB",level:0,classes:["Wizard","Bard"]};
 assert.equal(eligibleForClass(spell,wizard),true);
 let patch=assignClassSpell(c,spell,wizard.id,"prepared_spells",sections);
 assert.deepEqual(patch.spells,patch.prepared_spells);
 assert.deepEqual(patch.spells[0].casting_classes,[wizard.id]);
 patch=assignClassSpell({...c,...patch},spell,bard.id,"prepared_spells",sections);
 assert.deepEqual(patch.spells[0].casting_classes,[wizard.id,bard.id]);
 assert.throws(()=>assignClassSpell({...c,...patch},spell,wizard.id,"prepared_spells",sections),/già presente/);
 const removed=revokeClassSpell({...c,...patch},"prepared_spells",0,wizard.id);
 assert.deepEqual(removed.spells[0].casting_classes,[bard.id]);
 assert.deepEqual(revokeClassSpell({...c,...removed},"prepared_spells",0,bard.id).spells,[]);
 assert.throws(()=>assignClassSpell(c,{id:"x",name:"Fireball",level:3,classes:["Wizard"]},bard.id,"prepared_spells",sections),/non disponibile/);
});
test("quick homebrew keeps native portable definitions, structured grants and safe deletion",async()=>{
 const def=quickDefinition("backgrounds","Cronista","Descrizione",
   [{kind:"skill",key:"history"},{kind:"language",key:"elvish"}],{},"local_test");
 assert.equal(def.id,"homebrew:quick_local:backgrounds:local_test");
 assert.deepEqual(def.data.skillProficiencies,[{history:true}]);
 assert.deepEqual(def.data.languageProficiencies,[{elvish:true}]);
 assert.throws(()=>quickDefinition("items","Wrong","",[],{value:-1}),/Valore/);
 const feat=await createQuickHomebrew("feats","Avventuriero di prova","Talento",
   [{kind:"skill",key:"perception"}]);
 const item=await createQuickHomebrew("items","Moneta speciale","Un oggetto",[],
   {custom_item_type:"other",rarity:"rare",value:25});
 const c=await createCreature("character","Creatura del contenuto");
 const editor=await openCreatureEditor(c.id);
 const patch=quickGrantPatch(editor.read(),feat);
 await editor.update({...patch,feats_catalog:[{id:feat.id,name:feat.name,source:feat.source}],
   inventory:[{id:item.id,name:item.name,quantity:1}]});
 const stored=(await loadCreature(c.id)).data;
 assert.equal(fixedProficiencies(stored).get("skill:perception"),true);
 const exported=JSON.parse(await (await exportCreature(c.id)).text());
 assert.deepEqual(exported.homebrew_content.map(x=>x.id).sort(),[feat.id,item.id].sort());
 await assert.rejects(deleteQuickHomebrew(feat.id),/ancora in uso/);
 await editor.update({feats_catalog:[],inventory:[]});
 assert.equal(fixedProficiencies(editor.read()).get("skill:perception"),undefined,
   "Removed feat must not continue granting proficiency");
 assert.equal(await deleteQuickHomebrew(feat.id),true);
 assert.equal(await deleteQuickHomebrew(item.id),true);
 assert.equal(await deleteQuickHomebrew(item.id),false);
});


test('ability payments accept multiple uses and reject insufficient resources atomically',()=>{
 const record={resource_trackers:[{id:'focus',max:5}],resource_tracker_spent:{focus:1,other:2}};
 const change=spendTrackerUses(record,'focus',2);
 assert.deepEqual(change.resource_tracker_spent,{focus:3,other:2});
 assert.deepEqual(record.resource_tracker_spent,{focus:1,other:2});
 assert.deepEqual(spendTrackerUses({...record,...change},'focus',2).resource_tracker_spent,{focus:5,other:2});
 assert.throws(()=>spendTrackerUses({...record,...change},'focus',3),/insufficiente/);
 for(const invalid of [0,-1,1.5,Infinity,Number.MAX_SAFE_INTEGER+1])
  assert.throws(()=>spendTrackerUses(record,'focus',invalid),/non valido/);
 assert.throws(()=>spendTrackerUses(record,'missing',1),/non disponibile/);
 assert.throws(()=>spendTrackerUses(record,'focus',1,[{id:'focus',max:5,disabled:true}]),/non disponibile/);
});
