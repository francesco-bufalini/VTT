import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {powerSelectionModels,powerSelectionPatch,powerApplicationPatch,projectSelectionBenefits} from '../power_selection.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const grants=read('../../vtt/enrichment/benefits/option_grant.json');
const lists=read('../../vtt/enrichment/benefits/option_list.json');
const catalog={optionGrants:grants,optionLists:lists,powerSelections:{selections:[],templates:[]}};
const armored=()=>({
 kind:'character',id:'armor',rules_version:'2014',
 classes:[{name:'Artificer',source:'TCE',level:8,subclass:'Armorer',subclass_source:'TCE'}],
 inventory:[
  {id:'plate',instance_id:'plate-one',name:'Plate',type:'HA',quantity:1,ac:18,equipped_slots:['body']},
  {id:'chain',instance_id:'chain-two',name:'Chain',type:'MA',quantity:1,ac:16,equipped_slots:['body']}
 ]
});
const armorerFeature={name:'Arcane Armor',class_name:'Artificer',class_source:'TCE',
 origin_key:'class|tce|artificer|subclass|armorer|tce',origin_id:'feature:arcane-armor',level:8};
const armorer={features:[armorerFeature]};
const model=(record,ctx,id,values=catalog)=>powerSelectionModels(record,ctx,values)
 .find(row=>row.id===id);

test('Arcane Armor is one local capability that can independently extend multiple objects',()=>{
 let record=armored();
 const root=model(record,armorer,'arcane_armor');
 assert.deepEqual(root.options.map(row=>row.id),['arcane_armor']);
 assert.equal(root.layers.applied.limit,null);
 assert.equal(root.layers.applied.trigger,null);
 for(const index of [0,1]){
  record={...record,...powerApplicationPatch(record,armorer,catalog,'arcane_armor','arcane_armor',true,{itemIndex:index})};
 }
 assert.equal(record.power_applications.arcane_armor.length,2);
 assert(record.inventory.every(item=>item.option_extensions?.some(row=>row.id==='arcane_armor')),
  JSON.stringify({applications:record.power_applications.arcane_armor,extensions:record.inventory.map(i=>i.option_extensions)}));
 assert.throws(()=>powerApplicationPatch(record,armorer,catalog,'arcane_armor','arcane_armor',true,{itemIndex:0}),/già applicato/);
 const children=powerSelectionModels(record,armorer,catalog).filter(row=>row.id.startsWith('armor_model:from:'));
 assert.equal(children.length,2);
 assert(children.every(row=>row.options.length===2&&row.layers.applied.limit===1&&row.layers.applied.trigger==='short_rest'));
 record={...record,...powerApplicationPatch(record,armorer,catalog,'arcane_armor','arcane_armor',false,{itemIndex:0})};
 assert.equal(record.power_applications.arcane_armor.length,1);
 assert.equal(powerSelectionModels(record,armorer,catalog).filter(row=>row.id.startsWith('armor_model:from:')).length,1);
 assert.deepEqual(record.inventory[0].option_extensions||[],[]);
 assert.equal(record.inventory[1].option_extensions.length,1);
});

test('selected model creates a State trait that owns its attacks and numeric benefits',()=>{
 let record=armored();
 record={...record,...powerApplicationPatch(record,armorer,catalog,'arcane_armor','arcane_armor',true,{itemIndex:0})};
 const child=powerSelectionModels(record,armorer,catalog).find(row=>row.id.startsWith('armor_model:from:'));
 assert(child);
 assert.deepEqual(child.options.map(row=>row.name),['Guardian','Infiltrator']);
 record={...record,...powerApplicationPatch(record,armorer,catalog,child.id,'armor_model:infiltrator',true)};
 let projection=projectSelectionBenefits(record,catalog,armorer.features);
 assert.equal(projection.selection_traits.length,1);
 assert.equal(projection.selection_traits[0].name,'Infiltrator');
 assert(projection.selection_traits[0].benefits.some(e=>e.type==='attack'));
 assert.equal(projection.attack_grants[0]?.id,'class_feature:lightning_launcher');
 assert.equal(projection.attack_grants[0]?.selection_trait_id,projection.selection_traits[0].id);
 assert.equal(projection.formula_bonuses.some(row=>row.target==='speed'),true);
 record={...record,...powerApplicationPatch(record,armorer,catalog,child.id,'armor_model:guardian',true)};
 projection=projectSelectionBenefits(record,catalog,armorer.features);
 assert.equal(projection.selection_traits[0]?.name,'Guardian');
 assert.equal(projection.attack_grants[0]?.id,'class_feature:thunder_gauntlets');
 assert(!projection.attack_grants.some(row=>row.id==='class_feature:lightning_launcher'));
 assert.equal(projection.formula_bonuses.some(row=>row.target==='speed'),false);
 record={...record,inventory:record.inventory.map(item=>({...item,equipped_slots:[]}))};
 projection=projectSelectionBenefits(record,catalog,armorer.features);
 assert.deepEqual(projection.selection_traits,[]);
 assert.deepEqual(projection.attack_grants||[],[]);
});

test('applied Druidic Warrior, Blessed Warrior and Pact of the Tome grant independent learned cantrips',()=>{
 const scenarios=[
  {owner:'Ranger',rule:'optional:class:phb:ranger:fs-r',feature:'Fighting Style',
   option:'optional:tce:druidic-warrior',grant:'spell_choice:druidic_warrior',spellClass:'Druid',ability:'wis',count:2},
  {owner:'Paladin',rule:'optional:class:phb:paladin:fs-p',feature:'Fighting Style',
   option:'optional:tce:blessed-warrior',grant:'spell_choice:blessed_warrior',spellClass:'Cleric',ability:'cha',count:2},
  {owner:'Warlock',rule:'optional:class:phb:warlock:pb',feature:'Pact Boon',
   option:'optional:phb:pact-of-the-tome',grant:'spell_choice:pact_of_the_tome',spellClass:'Wizard',ability:'cha',count:3}
 ];
 for(const scenario of scenarios){
  const spell={id:'test:'+scenario.spellClass.toLowerCase(),name:'Test Cantrip',source:'PHB',level:0,classes:[scenario.spellClass]};
  const wrong={id:'test:other',name:'Other Cantrip',source:'PHB',level:0,
   classes:[scenario.spellClass==='Wizard'?'Cleric':'Wizard']};
  const indexed={...catalog,spells:[spell,wrong]};
  const ctx={features:[{name:scenario.feature,class_name:scenario.owner,class_source:'PHB',
   origin_id:'feature:'+scenario.owner,origin_key:'class|phb|'+scenario.owner.toLowerCase(),level:3}]};
  let record={kind:'character',rules_version:'2014',classes:[{name:scenario.owner,source:'PHB',level:3}],inventory:[]};
  record={...record,...powerSelectionPatch(record,ctx,indexed,scenario.rule,'learned',scenario.option)};
  if(!model(record,ctx,scenario.rule,indexed).layers.applied?.automatic)
   record={...record,...powerApplicationPatch(record,ctx,indexed,scenario.rule,scenario.option,true)};
  const child=powerSelectionModels(record,ctx,indexed).find(row=>row.id.startsWith(scenario.grant+':from:'));
  assert(child,'Nested spell chooser missing: '+scenario.option);
  assert.equal(child.layers.learned.limit,scenario.count);
  assert.equal(child.ability,scenario.ability);
  assert(child.options.some(row=>row.id===spell.id));
  if(scenario.owner!=='Warlock')assert(!child.options.some(row=>row.id===wrong.id));
  record={...record,...powerSelectionPatch(record,ctx,indexed,child.id,'learned',spell.id)};
  const projection=projectSelectionBenefits(record,indexed,ctx.features);
  const grant=projection.origin_spell_grants.find(row=>row.spell_id===spell.id);
  assert(grant,'Cantrip granted by selected style: '+scenario.option);
  assert.equal(grant.cantrip,true);
  assert.equal(grant.payment_mode,'slot'); // Canonical cantrip flag makes it free at the casting layer.
  assert.equal(grant.spellcasting_ability,scenario.ability);
  record={...record,...(model(record,ctx,scenario.rule,indexed).layers.applied?.automatic?
    powerSelectionPatch(record,ctx,indexed,scenario.rule,'learned',scenario.option):
    powerApplicationPatch(record,ctx,indexed,scenario.rule,scenario.option,false))};
  assert(!projectSelectionBenefits(record,indexed,ctx.features).origin_spell_grants.some(row=>row.spell_id===spell.id));
 }
});
