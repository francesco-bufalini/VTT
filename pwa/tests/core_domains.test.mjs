import "fake-indexeddb/auto";
import {test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {initialCreature,changeTrackerUses,spendTrackerUses} from "../character_core.js";
import {recoveryPatch as nativeRecoveryPatch} from "../native_sheet.js";
import {sessionSpellEntries} from "../spell_selection.js";
const recoveryPatch=(record,event)=>nativeRecoveryPatch(record,event,record.resource_trackers||[]);
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
test("multiclass spell choices keep distinct source-qualified casting classes",()=>{
 const wizard='class|phb|wizard',bard='class|phb|bard';
 const spell={id:'spell:light|phb',name:'Light',source:'PHB',level:0,classes:['Wizard','Bard'],
  time:[{number:1,unit:'action'}],casting_classes:[wizard,bard]};
 const record={kind:'character',rules_version:'2014',abilities:{int:16,cha:14},
  classes:[{name:'Wizard',source:'PHB',level:5},{name:'Bard',source:'PHB',level:3}],
  prepared_spells:[spell],spells:[spell]};
 const calc={casting_classes:[{id:wizard,name:'Wizard',ability:'int'},
  {id:bard,name:'Bard',ability:'cha'}],origin_spells:[],trackers:[]};
 const choices=sessionSpellEntries(record,calc,[spell]).filter(row=>row.id===spell.id);
 assert.deepEqual(choices.map(row=>row.casting_class),[wizard,bard]);
 assert(choices.every(row=>row.level===0));
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
