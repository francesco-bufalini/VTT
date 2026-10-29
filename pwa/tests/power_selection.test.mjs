import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {powerSelectionModels,powerSelectionPatch,powerSelectionLimit,
  powerApplicationPatch} from '../power_selection.js';
const data=JSON.parse(readFileSync(new URL('../catalog/power_selections.json',import.meta.url),'utf8'));
const owner=(className,source,name)=>({name,origin_id:'feature:'+name,
 origin_key:'class|'+source.toLowerCase()+'|'+className.toLowerCase(),
 requirements:{class_name:className,class_source:source}});
const ranger=level=>({
 classes:[{name:'Ranger',source:'PHB',level}],
 abilities:{str:12,dex:14,con:12,int:10,wis:16,cha:8}
});
const context=()=>({features:[owner('Ranger','PHB','Favored Enemy')]});
const pick=(record,calculated,id='ranger_favored_enemy_phb')=>
 powerSelectionModels(record,calculated,data).find(row=>row.id===id);

test('PHB Ranger Favored Enemy uses prepared-only power choices without a trigger',()=>{
 for(const [level,max] of [[1,1],[5,1],[6,2],[13,2],[14,3],[20,3]]){
  const row=pick(ranger(level),context());
  assert.equal(row.layers.prepared.limit,max);
  assert.equal(row.layers.learned,undefined);
  assert.equal(row.layers.applied,undefined);
  assert.equal(row.layers.prepared.trigger,null);
  assert.equal(row.ui,'generic');
 }
 assert.equal(pick(ranger(1),{features:[]}),undefined,'no feature: no free benefit');
 assert.equal(pick({classes:[{name:'Ranger',source:'XPHB',level:20}]},context()),undefined);
});

test('Favored Enemy tracks chosen creature types and two humanoid races',()=>{
 const ctx=context(),id='ranger_favored_enemy_phb';
 let record=ranger(1);
 record={...record,...powerSelectionPatch(record,ctx,data,id,'prepared','dragons')};
 assert.deepEqual(pick(record,ctx).layers.prepared.selected,['dragons']);
 assert.throws(()=>powerSelectionPatch(record,ctx,data,id,'prepared','beasts'),/massimo/);
 record={...record,...powerSelectionPatch(record,ctx,data,id,'prepared','dragons')};
 assert.deepEqual(pick(record,ctx).layers.prepared.selected,[]);
 assert.throws(()=>powerSelectionPatch(record,ctx,data,id,'prepared','humanoids',['elf']),/sotto-opzioni/);
 record={...record,...powerSelectionPatch(record,ctx,data,id,'prepared','humanoids',['Elf','Orc'])};
 assert.deepEqual(pick(record,ctx).layers.prepared.selected,[{id:'humanoids',subchoices:['Elf','Orc']}]);
 assert.throws(()=>powerSelectionPatch(record,ctx,data,id,'prepared','humanoids',['Elf','elf']),/sotto-opzioni/);
 // Reselection of an existing option updates its sublist without spending a new pick.
 record={...record,...powerSelectionPatch(record,ctx,data,id,'prepared','humanoids',['Elf','Goblin'])};
 assert.equal(pick(record,ctx).layers.prepared.used,1);
 record.classes[0].level=6;
 record={...record,...powerSelectionPatch(record,ctx,data,id,'prepared','dragons')};
 assert.equal(pick(record,ctx).layers.prepared.used,2);
 // Recoveries and advancement triggers do not gate edits.
 assert.equal(record.rest_selection_available,undefined);
});

test('class spellcasting projects optional learned and prepared layers',()=>{
 const calculated={casting_classes:[
  {id:'wizard',name:'Wizard',level:7,book:true,mode:'Preparati',limit:10,cantrips:4},
  {id:'druid',name:'Druid',level:7,book:false,mode:'Preparati',limit:10},
  {id:'sorcerer',name:'Sorcerer',level:7,book:false,mode:'Conosciuti',limit:8}
 ]};
 const [wizard,druid,sorcerer]=powerSelectionModels({},calculated,data);
 assert.deepEqual(Object.keys(wizard.layers),['learned','prepared']);
 assert.equal(wizard.layers.learned.limit,null,'spellbook is not artificially capped');
 assert.equal(wizard.layers.learned.trigger,null);
 assert.equal(wizard.layers.prepared.trigger,'long_rest');
 assert.deepEqual(Object.keys(druid.layers),['prepared']);
 assert.deepEqual(Object.keys(sorcerer.layers),['learned']);
 assert.equal(sorcerer.layers.learned.trigger,'level_up');
});

test('Armor Model and infusion JSON share the same stage contract',()=>{
 const artificer={id:'a',classes:[{name:'Artificer',source:'TCE',subclass:'Armorer',level:8}],
  trait_state_selection:{armor_model:'armor_model:guardian'},inventory:[]};
 const features=[owner('Artificer','TCE','Armor Model'),
   owner('Artificer','TCE','Infuse Item')];
 const calculated={features,trait_state_catalog:[{group:'armor_model',id:'armor_model:guardian',
  name:'Guardian'}, {group:'armor_model',id:'armor_model:infiltrator',name:'Infiltrator'}],
  infusion_catalog:[],infusion_mechanics:{}};
 const models=powerSelectionModels(artificer,calculated,data);
 const armor=models.find(row=>row.id==='armor_model');
 const infusion=models.find(row=>row.id==='artificer_infusions');
 assert.deepEqual(Object.keys(armor.layers),['applied']);
 assert.equal(armor.layers.applied.used,1);
 assert.equal(armor.layers.applied.limit,1);
 assert.equal(armor.layers.applied.trigger,'short_rest');
 assert.deepEqual(Object.keys(infusion.layers),['learned','applied']);
 assert.equal(infusion.layers.applied.trigger,'long_rest');
 assert.equal(infusion.layers.learned.trigger,'level_up');
 assert.equal(powerSelectionLimit({by_class_level:[[1,1],[3,2],[8,3]]},7),2);
});

test('generic applied powers spend and refund exactly one owned tracker use',()=>{
 const custom={selections:[{id:'item_grant',owner:{class_name:'Ranger',
  class_source:'PHB',trait:'Favored Enemy'},source:{type:'inline',
   options:[{id:'one',name:'One'}]},application_tracker_id:'resource',
  layers:{learned:{limit:1},applied:{limit:1,target:{kind:'equipped_item',slot:'body'},
    refund_on_remove:true}}}]};
 const calculated={...context(),trackers:[{id:'resource',max:2}]};
 let record={...ranger(8),inventory:[{id:'armor',instance_id:'a',type:'MA',
  quantity:1,equipped_slots:['body']}],resource_tracker_spent:{}};
 assert.throws(()=>powerApplicationPatch(record,calculated,custom,'item_grant','one',
  true,{itemIndex:0}),/prima imparare/);
 record={...record,...powerSelectionPatch(record,calculated,custom,'item_grant','learned','one')};
 assert.throws(()=>powerApplicationPatch(record,calculated,custom,'item_grant','one',
  true,{itemIndex:4}),/oggetto/);
 record={...record,...powerApplicationPatch(record,calculated,custom,'item_grant','one',
  true,{itemIndex:0})};
 assert.equal(record.resource_tracker_spent.resource,1);
 assert.equal(powerSelectionModels(record,calculated,custom)[0].layers.applied.used,1);
 assert.throws(()=>powerApplicationPatch(record,calculated,custom,'item_grant','one',
  true,{itemIndex:0}),/già applicato/);
 record={...record,...powerApplicationPatch(record,calculated,custom,'item_grant','one',false)};
 assert.equal(record.resource_tracker_spent.resource,0);
 assert.equal(powerSelectionModels(record,calculated,custom)[0].layers.applied.used,0);
});

test('learned options form the prepared sublist and cannot be lost while active',()=>{
 const schema={selections:[{id:'three_layers',
  owner:{class_name:'Ranger',class_source:'PHB',trait:'Favored Enemy'},
  source:{type:'inline',options:[{id:'a',name:'A'},{id:'b',name:'B'}]},
  layers:{learned:{limit:2},prepared:{limit:1},applied:{limit:1}}}]};
 let rec=ranger(8),calc=context();
 assert.throws(()=>powerSelectionPatch(rec,calc,schema,'three_layers','prepared','a'),/prima imparare/);
 rec={...rec,...powerSelectionPatch(rec,calc,schema,'three_layers','learned','a')};
 rec={...rec,...powerSelectionPatch(rec,calc,schema,'three_layers','learned','b')};
 rec={...rec,...powerSelectionPatch(rec,calc,schema,'three_layers','prepared','a')};
 assert.throws(()=>powerSelectionPatch(rec,calc,schema,'three_layers','learned','a'),/prima/);
 assert.throws(()=>powerSelectionPatch(rec,calc,schema,'three_layers','prepared','b'),/massimo/);
 rec={...rec,...powerApplicationPatch(rec,calc,schema,'three_layers','a',true)};
 assert.throws(()=>powerSelectionPatch(rec,calc,schema,'three_layers','prepared','a'),/Disapplica/);
 rec={...rec,...powerApplicationPatch(rec,calc,schema,'three_layers','a',false)};
 rec={...rec,...powerSelectionPatch(rec,calc,schema,'three_layers','prepared','a')};
 rec={...rec,...powerSelectionPatch(rec,calc,schema,'three_layers','learned','a')};
 assert.deepEqual(powerSelectionModels(rec,calc,schema)[0].layers.learned.selected,['b']);
});
