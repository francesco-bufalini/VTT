import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {powerSelectionModels,powerSelectionPatch,powerSelectionLimit,
  powerApplicationPatch,powerSelectionTargets} from '../power_selection.js';
const data={...JSON.parse(readFileSync(new URL('../catalog/power_selections.json',import.meta.url),'utf8')),optionalFeatureProgressions:JSON.parse(readFileSync(new URL('../catalog/optional_feature_progressions.json',import.meta.url),'utf8'))};
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

test('PHB Ranger Favored Enemy uses alternative option packages at levels 1, 6 and 14',()=>{
 for(const [level,max] of [[1,1],[5,1],[6,2],[13,2],[14,3],[20,3]]){
  const model=pick(ranger(level),context());
  assert.equal(model.layers.learned.limit,max);
  assert.equal(model.layers.prepared,undefined);
  assert.equal(model.layers.learned.trigger,null);
  assert.equal(model.ui,'generic');
  assert.deepEqual([...new Set(model.options.filter(row=>row.min_level<=level).map(row=>row.choice_slot))].sort(),Array.from({length:max},(_,i)=>i+1));
 }
 assert.equal(pick(ranger(1),{features:[]}),undefined);
 assert.equal(pick({classes:[{name:'Ranger',source:'XPHB',level:20}]},context()),undefined);
});

test('alternative packages choose one monster type or two humanoid races within each slot',()=>{
 const ctx=context(),id='ranger_favored_enemy_phb';let record=ranger(1);
 assert.throws(()=>powerSelectionPatch(record,ctx,data,id,'learned','humanoid_races:1',['orc']),/sotto-opzioni/);
 assert.throws(()=>powerSelectionPatch(record,ctx,data,id,'learned','humanoid_races:1',['orc','orc']),/sotto-opzioni/);
 assert.throws(()=>powerSelectionPatch(record,ctx,data,id,'learned','humanoid_races:1',['orc','not-in-list']),/sotto-opzioni/);
 record={...record,...powerSelectionPatch(record,ctx,data,id,'learned','monster_types:1',['dragons'])};
 assert.deepEqual(pick(record,ctx).layers.learned.selected,[{id:'monster_types:1',subchoices:['dragons']}]);
 record={...record,...powerSelectionPatch(record,ctx,data,id,'learned','humanoid_races:1',['orc','goblin'])};
 assert.deepEqual(pick(record,ctx).layers.learned.selected,[{id:'humanoid_races:1',subchoices:['orc','goblin']}]);
 assert.throws(()=>powerSelectionPatch(record,ctx,data,id,'learned','monster_types:2',['fey']),/Livello insufficiente/);
 record.classes[0].level=6;
 record={...record,...powerSelectionPatch(record,ctx,data,id,'learned','monster_types:2',['fey'])};
 assert.equal(pick(record,ctx).layers.learned.used,2);
 assert.deepEqual(pick(record,ctx).layers.learned.selected.map(row=>row.id),['humanoid_races:1','monster_types:2']);
 record.classes[0].level=14;
 record={...record,...powerSelectionPatch(record,ctx,data,id,'learned','humanoid_races:3',['elf','human'])};
 assert.equal(pick(record,ctx).layers.learned.used,3);
});

test('spell selection benefits project the same stage and source contract as optional powers',()=>{
 const calculated={casting_classes:[
  {id:'wizard',name:'Wizard',level:7,book:true,mode:'Preparati',limit:10,cantrips:4,
   level_class_name:'Wizard',spell_list_class_name:'Wizard',
   selection_layers:{learned:{limit:18,storage:'spellbook_spells'},
     prepared:{limit:10,storage:'prepared_spells',trigger:'long_rest'}}},
  {id:'druid',name:'Druid',level:7,book:false,mode:'Preparati',limit:10,
   selection_layers:{learned:{mode:'class_list',storage:'known_spell_overrides'},
     prepared:{limit:10,storage:'prepared_spells',trigger:'long_rest'}}},
  {id:'sorcerer',name:'Sorcerer',level:7,book:false,mode:'Conosciuti',limit:8,
   selection_layers:{learned:{limit:8,storage:'prepared_spells',trigger:'level_up'},
     applied:{mode:'automatic',from:'learned'}}}
 ]};
 const [wizard,druid,sorcerer]=powerSelectionModels({},calculated,data);
 assert.equal(wizard.benefit_type,'spell_selection');
 assert.equal(wizard.source.type,'spell_catalog');
 assert.deepEqual(Object.keys(wizard.layers),['learned','prepared']);
 assert.equal(wizard.layers.learned.limit,18);
 assert.equal(wizard.layers.learned.storage,'spellbook_spells');
 assert.equal(wizard.layers.learned.trigger,null);
 assert.equal(wizard.layers.prepared.trigger,'long_rest');
 assert.deepEqual(Object.keys(druid.layers),['learned','prepared']);
 assert.equal(druid.layers.learned.automatic,true,'the full class list is learned automatically');
 assert.deepEqual(Object.keys(sorcerer.layers),['learned','applied']);
 assert.equal(sorcerer.layers.applied.automatic,true);
 assert.equal(sorcerer.layers.learned.trigger,'level_up');
});

test('Artificer infusions use the canonical learned and applied selection stages',()=>{
 const artificer={id:'a',classes:[{name:'Artificer',source:'TCE',subclass:'Armorer',level:8}],inventory:[]};
 const features=[owner('Artificer','TCE','Infuse Item')];
 const models=powerSelectionModels(artificer,{features},data);
 const infusion=models.find(row=>row.id==='artificer_infusions');
 assert.ok(infusion);
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

test('arbitrary traits can use the same alternative package selector',()=>{
 const schema={selections:[{id:'choices',owner:{class_name:'Ranger',class_source:'PHB',trait:'Favored Enemy'},
  source:{packages:[{id:'small',name:'Two choices',count:2,options:[{id:'a',name:'A'},{id:'b',name:'B'}]},
   {id:'large',name:'One choice',count:1,options:[{id:'x',name:'X'}]}]},
  layers:{learned:{limit:1}}}]};
 let record=ranger(1);
 record={...record,...powerSelectionPatch(record,context(),schema,'choices','learned','small:1',['a','b'])};
 record={...record,...powerSelectionPatch(record,context(),schema,'choices','learned','large:1',['x'])};
 assert.deepEqual(powerSelectionModels(record,context(),schema)[0].layers.learned.selected,
  [{id:'large:1',subchoices:['x']}]);
});

test('option benefit targets are defined by data, including equipped armor and optional object extensions',()=>{
 const inventory=[
  {id:'armor-a',name:'Armor A',type:'MA',rarity:'none',quantity:1,equipped_slots:['body']},
  {id:'armor-b',name:'Armor B',type:'MA',rarity:'none',quantity:1,equipped_slots:[]},
  {id:'weapon-a',name:'Sword',type:'M',rarity:'none',quantity:1,equipped_slots:['main']}
 ];
 const record={id:'owner',inventory},option={id:'any-option',item_selector:{kinds:['armor'],nonmagical:true}};
 const target={kind:'equipped_item',slot:'body',kinds:['armor']};
 assert.deepEqual(powerSelectionTargets(record,{layers:{applied:{target}}},option).map(row=>row.index),[0]);
 assert.deepEqual(powerSelectionTargets(record,{layers:{applied:{}}},option),[]);
 const extension={kind:'item',selector:'option.item_selector'};
 const model={layers:{applied:{target:extension}}};
 assert.deepEqual(powerSelectionTargets(record,model,option).map(row=>row.index),[0,1]);
 assert.deepEqual(powerSelectionTargets(record,model,option).map(row=>row.index),[0,1]);
 assert.deepEqual(powerSelectionTargets({...record,inventory:inventory.map(item=>({...item,disabled:true}))},model,option),[]);
});



test('targeted options are not applied before object choice and extend only the selected copy',()=>{
 const context={features:[owner('Artificer','TCE','Arcane Armor'),owner('Artificer','TCE','Armor Model')]};
 let record={id:'owner',classes:[{name:'Artificer',source:'TCE',subclass:'Armorer',level:8}],inventory:[{id:'free',name:'Any object',quantity:3}]};
 const model=powerSelectionModels(record,context,data).find(m=>m.id==='arcane_armor');
 assert.equal(model.layers.learned,undefined);assert.equal(model.layers.applied.limit,1);
 assert.throws(()=>powerApplicationPatch(record,context,data,'arcane_armor','arcane_armor',true),/oggetto/);
 assert.equal(record.power_applications,undefined);
 record={...record,...powerApplicationPatch(record,context,data,'arcane_armor','arcane_armor',true,{itemIndex:0})};
 assert.deepEqual(record.inventory.map(i=>i.quantity),[1,2]);
 const application=record.power_applications.arcane_armor[0];assert.equal(application.trait,undefined);
 assert.equal(application.target_item_id,record.inventory[0].instance_id);
 assert.equal(record.inventory[0].option_extensions[0].name,'Armatura Arcana');
 assert(powerSelectionModels(record,context,data).some(m=>m.id==='armor_model'));
 record={...record,...powerApplicationPatch(record,context,data,'arcane_armor','arcane_armor',false)};
 assert(!powerSelectionModels(record,context,data).some(m=>m.id==='armor_model'));
 assert.deepEqual(record.inventory[0].option_extensions,[]);
});
