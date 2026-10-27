import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {classFeatureRollSources} from '../feature_mechanics.js';
import {collectEffectExtensions,effectExtensionsFor,applyEffectExtensions} from '../effect_extensions.js';
import {addBenefitPatch,removeBenefitPatch} from '../trait_benefit_editor.js';
import {applyInfusionPatch,clearInfusionPatch,learnInfusionPatch,prepareInfusionPatch,learnedInfusions,infusionNumericBonuses} from '../item_controls.js';
import {traitBenefitGroups} from '../trait_benefits.js';

const abilityGrants=JSON.parse(readFileSync(new URL('../catalog/ability_grants.json',import.meta.url),'utf8'));
const extensions=JSON.parse(readFileSync(new URL('../catalog/effect_extensions.json',import.meta.url),'utf8')).extensions;
const definitions=abilityGrants.artificer_infusions;
const infusionTrait={id:'infuse_item',name:'Infuse Item',class_name:'Artificer',
 class_source:'TCE',level:2,origin_key:'class|tce|artificer',
 origin_id:'feature:class|tce|artificer|infuse_item'};
const classFeatures={class_features:[infusionTrait],subclass_features:[]};
const classMechanics={classes:[{name:'Artificer',source:'TCE',columns:[{
 name:'Infused Items',levels:[0,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,6,6,6]}]}]};
const catalogs={abilityGrants,classFeatures,classMechanics,effectExtensions:extensions};
const base=()=>({id:'artificer_test',kind:'character',name:'Infusions',
 rules_version:'2014',classes:[{name:'Artificer',source:'TCE',level:10}],
 abilities:{str:12,dex:12,con:12,int:18,wis:12,cha:10},
 optional_features_catalog:[],inventory:[],formula_bonuses:[]});
const byName=name=>definitions.find(row=>row.name===name);
const weapon=(instance_id,opts={})=>({id:'weapon:javelin',instance_id,
 name:'Javelin',type:'M',quantity:1,damage:'1d6',
 properties:['T'],active:true,rarity:'none',equipped_slots:[],...opts});
const grant=(name,item,record=base())=>{
 const rule=byName(name);
 return {...item,infusion:{id:rule.id,name,creator_id:record.id,level:10,
  requires_attunement:rule.requires_attunement,origin_id:infusionTrait.origin_id}};
};

test('infusion extensions are scoped to the actually infused inventory instance',()=>{
 const record=base();
 const original=grant('Returning Weapon',weapon('copy_one',{equipped_slots:['main']}),record);
 record.inventory=[original,weapon('copy_two')];
 record.optional_features_catalog=[{id:byName('Returning Weapon').id,name:'Returning Weapon',source:'TCE'}];
 const sheet=calculateSheet(record,catalogs);
 const owned=effectExtensionsFor(sheet.effect_extensions,
  {kind:'item',id:original.id,name:original.name,instance_id:'copy_one',inventory_index:0});
 assert.equal(owned.length,1);
 assert.equal(owned[0].operation,'grant_property');
 assert.match(owned[0].description,/ritorna/i);
 assert.equal(effectExtensionsFor(sheet.effect_extensions,
  {kind:'item',id:original.id,name:original.name,instance_id:'copy_two',inventory_index:1}).length,0);
 assert.equal(effectExtensionsFor(sheet.effect_extensions,{kind:'spell',name:'Javelin'}).length,0);
 const result=applyEffectExtensions(original,sheet.effect_extensions,
  {kind:'item',id:original.id,name:original.name,instance_id:'copy_one',inventory_index:0});
 assert.equal(result.extended_effects.length,1);
 const optional={key:'optional|tce|returning weapon|0|returning weapon',feature_origin:'optional|tce|returning weapon',
  origin_key:'optional|tce|returning weapon',name:'Returning Weapon',category:'altro',rank:2};
 assert.equal(traitBenefitGroups(optional,record,sheet).find(row=>row.type==='effect_extensions')?.items.length,1);
 const itemTrait={key:'item:weapon:javelin|javelin|0',origin_key:'item:weapon:javelin',
  name:'Javelin',category:'oggetti',rank:0};
 assert.equal(traitBenefitGroups(itemTrait,record,sheet).find(row=>row.type==='effect_extensions')?.items.length,1);
 assert.equal(traitBenefitGroups(itemTrait,record,sheet).find(row=>row.type==='effect_extensions')?.items[0].id,'',
  'target-side trait preview should be read-only');
});

test('passive item effects disappear on unequip, infusion removal or disabled Infuse Item',()=>{
 const record=base();
 record.optional_features_catalog=[{id:byName('Returning Weapon').id,name:'Returning Weapon',source:'TCE'}];
 record.inventory=[grant('Returning Weapon',weapon('copy_a',{equipped_slots:['main']}),record)];
 assert.equal(calculateSheet(record,catalogs).effect_extensions.length,1);
 record.inventory[0].equipped_slots=[];
 assert.equal(calculateSheet(record,catalogs).effect_extensions.length,0);
 record.inventory[0].equipped_slots=['main'];
 const disabled={...record,origin_enabled:{[infusionTrait.origin_id]:false}};
 assert.equal(calculateSheet(disabled,catalogs).effect_extensions.length,0);
 const cleared={...record,...clearInfusionPatch(record,0)};
 assert.equal(calculateSheet(cleared,catalogs).effect_extensions.length,0);
});

test('Resistant Armor asks for an explicit allowed damage choice and obeys attunement',()=>{
 const entry=byName('Resistant Armor');
 assert.ok(entry.effect_choice?.options.includes('fire'));
 let record=base();
 record.inventory=[{id:'armor:chainmail',instance_id:'armor_1',name:'Chainmail',
  type:'MA',custom_item_type:'armor',quantity:1,rarity:'none',active:true,
  equipped_slots:['body'],attuned:false}];
 record={...record,...learnInfusionPatch(record,entry,definitions,classMechanics,-1,[infusionTrait])};
 let known=learnedInfusions(record,definitions)[0];
 record={...record,...prepareInfusionPatch(record,known,definitions,[infusionTrait],true)};
 assert.throws(()=>applyInfusionPatch(record,known,definitions,classMechanics,0,[infusionTrait]),
  /Seleziona/);
 assert.throws(()=>applyInfusionPatch(record,known,definitions,classMechanics,0,[infusionTrait],{damage_type:'unknown'}),
  /Seleziona/);
 record={...record,...applyInfusionPatch(record,known,definitions,classMechanics,0,[infusionTrait],{damage_type:'fire'})};
 assert.equal(record.inventory[0].infusion.effect_choice.damage_type,'fire');
 assert.equal(calculateSheet(record,catalogs).effect_extensions.length,0);
 record.inventory[0].attuned=true;
 const effect=calculateSheet(record,catalogs).effect_extensions.find(row=>row.operation==='resistance');
 assert.equal(effect?.value,'fire');
 assert.equal(effect?.target_instance_id,'armor_1');
 record.inventory[0].attuned=false;
 assert.equal(calculateSheet(record,catalogs).effect_extensions.length,0);
});

test('ordinary enhanced weapon numeric bonus remains unchanged with effect-extension rules enabled',()=>{
 const record=base(),entry=byName('Enhanced Weapon');
 record.inventory=[grant('Enhanced Weapon',weapon('enhanced',{equipped_slots:['main']}),record)];
 assert.equal(infusionNumericBonuses(record,record.inventory[0],definitions,[infusionTrait]).bonus_weapon,2);
 const without=calculateSheet(record,{...catalogs,effectExtensions:[]});
 const withEffects=calculateSheet(record,catalogs);
 assert.equal(withEffects.values['attack_hit:item:weapon:javelin'],
  without.values['attack_hit:item:weapon:javelin']);
 assert.equal(withEffects.effect_extensions.length,0,'numeric bonuses are not duplicated as descriptive extensions');
});

test('manual item extension can be bound to one owned copy and removed without changing the item',()=>{
 const record=base(),trait={key:'special|infuse|0',name:'Extra Item Enchantment',rank:2,origin_key:'other'};
 record.inventory=[weapon('first'),weapon('second')];
 const patch=addBenefitPatch(record,trait,'effect_extensions',{
  target_kind:'item',target_name:'Javelin',target_id:'weapon:javelin',
  target_instance_id:'first',operation:'grant_property',trigger:'passive',
  description:'Magic returning property',frequency:'each'},'trait:copywise1');
 assert.equal(patch.effect_extensions.length,1);
 const updated={...record,...patch};
 const effects=collectEffectExtensions(updated,[],[]);
 assert.equal(effectExtensionsFor(effects,{kind:'item',id:'weapon:javelin',
  instance_id:'first'}).length,1);
 assert.equal(effectExtensionsFor(effects,{kind:'item',id:'weapon:javelin',
  instance_id:'second'}).length,0);
 const removed=removeBenefitPatch(updated,trait,{type:'effect_extensions',id:'effect_extension:trait:copywise1'});
 assert.deepEqual(removed.effect_extensions,[]);
 assert.equal(updated.inventory[0].instance_id,'first');
});


test('Helm of Awareness contributes a real initiative advantage roll source only while attuned',()=>{
 const record=base();
 record.inventory=[grant('Helm of Awareness',{
   id:'local_helm',instance_id:'helm_1',name:'Helm of Awareness target',custom_item_type:'other',
   quantity:1,active:true,attuned:true,rarity:'none'},record)];
 record.optional_features_catalog=[{id:byName('Helm of Awareness').id,name:'Helm of Awareness',source:'TCE'}];
 const calculated=calculateSheet(record,catalogs);
 assert.equal(calculated.effect_extensions.find(x=>x.operation==='roll_mode')?.value,'advantage');
 const initiative=classFeatureRollSources(record,calculated,'initiative');
 assert.ok(initiative.some(row=>row.mode==='advantage'&&row.kind==='item'));
 assert.equal(classFeatureRollSources(record,calculated,'save:dex').some(row=>row.kind==='item'),false);
 record.inventory[0].attuned=false;
 const unequipped=calculateSheet(record,catalogs);
 assert.equal(classFeatureRollSources(record,unequipped,'initiative').some(row=>row.kind==='item'),false);
});

test('Resistant Armor damage type is exposed as an active defense, not a generic permanent bonus',()=>{
 const record=base();
 record.inventory=[grant('Resistant Armor',{
   id:'armor:chainmail',instance_id:'arm-1',name:'Chainmail',
   custom_item_type:'armor',quantity:1,active:true,rarity:'none',
   equipped_slots:['body'],attuned:true,infusion:{}
 },record)];
 record.inventory[0].infusion.effect_choice={damage_type:'fire'};
 const sheet=calculateSheet(record,catalogs);
 assert.deepEqual(sheet.item_damage_resistances.map(x=>x.damage_type),['fire']);
 assert.equal(sheet.item_damage_resistances[0].target_instance_id,'arm-1');
 record.inventory[0].equipped_slots=[];
 assert.equal(calculateSheet(record,catalogs).item_damage_resistances.length,0);
});
