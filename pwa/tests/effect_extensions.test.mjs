import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {collectEffectExtensions,effectExtensionsFor,applyEffectExtensions,effectExtensionLabel} from '../effect_extensions.js';
import {addBenefitPatch,removeBenefitPatch,restoreBenefitPatch} from '../trait_benefit_editor.js';
import {traitBenefitGroups} from '../trait_benefits.js';

const catalog=JSON.parse(readFileSync(new URL('../catalog/effect_extensions.json',import.meta.url),'utf8')).extensions;
const warlock=(extra={})=>({rules_version:'2014',
 classes:[{name:'Warlock',source:'PHB',level:5}],
 optional_features_catalog:[
  {name:'Agonizing Blast',source:'PHB'},
  {name:'Eldritch Spear',source:'PHB'},
  {name:'Repelling Blast',source:'PHB'}],...extra});
const warlockRows=record=>collectEffectExtensions(record,catalog,[]);
const bardFeature={name:'Mote of Potential',
 origin_id:'feature:class|phb|bard|subclass|college of creation|tce|3|mote',
 origin_key:'class|phb|bard|subclass|college of creation|tce',
 requirements:{class_name:'Bard'},disabled:false};

test('2014 Eldritch Blast extensions combine range, per-beam damage and push',()=>{
 const effects=warlockRows(warlock());
 assert.equal(effects.length,3);
 const result=applyEffectExtensions(
  {name:'Eldritch Blast',range:{type:'point',distance:{type:'feet',amount:120}}},
  effects,{kind:'spell',name:'Eldritch Blast'}, {cha_mod:4});
 assert.equal(result.range.distance.amount,300);
 assert.equal(result.range_feet,300);
 assert.equal(result.effect_extensions.length,3);
 assert.equal(result.extended_effects.find(x=>x.operation==='bonus_damage')?.resolved_value,4);
 assert.equal(result.extended_effects.find(x=>x.operation==='push')?.resolved_value,10);
 assert.equal(result.extended_effects.find(x=>x.operation==='bonus_damage')?.frequency,'each');
 assert.equal(effectExtensionsFor(effects,{kind:'spell',name:'Fire Bolt'}).length,0);
 assert.match(effectExtensionLabel(effects[0],{cha_mod:4}),/4/);
});

test('optional class powers require ownership, minimum class level and active source',()=>{
 assert.equal(warlockRows(warlock({optional_features_catalog:[]})).length,0);
 assert.equal(warlockRows(warlock({classes:[{name:'Warlock',source:'PHB',level:1}]})).length,0);
 assert.equal(warlockRows(warlock({rules_version:'2024'})).length,0);
 assert.equal(warlockRows(warlock({optional_features_catalog:[{name:'Agonizing Blast',source:'PHB',disabled:true}]})).length,0);
 const disabled=warlock({origin_enabled:{'optional|phb|agonizing blast':false}});
 assert.equal(warlockRows(disabled).length,2);
 const suppressed=warlock({trait_benefit_removed:{'some-trait':['effect_extension:invocation-eldritch-spear-2014']}});
 assert.equal(warlockRows(suppressed).length,2);
});

test('mote of potential extends only bardic inspiration with three typed triggers',()=>{
 const record={rules_version:'2014',
  classes:[{name:'Bard',source:'PHB',level:3,subclass:'College of Creation',subclass_source:'TCE'}]};
 const effects=collectEffectExtensions(record,catalog,[bardFeature]);
 assert.equal(effects.length,3);
 const bardic=effectExtensionsFor(effects,{kind:'ability',id:'vtt_bardic_inspiration',name:'Bardic Inspiration'});
 assert.deepEqual(bardic.map(x=>x.trigger).sort(),['ability_check','attack_roll','saving_throw']);
 assert.ok(bardic.some(x=>x.operation==='temporary_hp'&&x.value==='bardic_inspiration_die+cha_mod'));
 assert.equal(effectExtensionsFor(effects,{kind:'ability',name:'Flash of Genius'}).length,0);
 const otherClass={...record,classes:[{name:'Bard',source:'PHB',level:3,subclass:'College of Lore'}]};
 assert.equal(collectEffectExtensions(otherClass,catalog,[bardFeature]).length,0);
 assert.equal(collectEffectExtensions({...record,classes:[{...record.classes[0],level:2}]},catalog,[bardFeature]).length,0);
 assert.equal(collectEffectExtensions({...record,origin_enabled:{[bardFeature.origin_id]:false}},catalog,[bardFeature]).length,0);
});

test('user-defined extensions persist as trait-owned editable benefits, removable and restorable',()=>{
 const trait={key:'class|phb|warlock|5|custom blast',name:'Custom Blast',origin_key:'class|phb|warlock',
  feature_origin:'feature:custom-blast',category:'classi',rank:2};
 const patch=addBenefitPatch({},trait,'effect_extensions',{
  target_kind:'spell',target_name:'Eldritch Blast',operation:'bonus_damage',
  value:'1d6',trigger:'on_hit',frequency:'once_per_turn',description:'On impact'},'trait:abc1234');
 assert.equal(patch.effect_extensions.length,1);
 const row=patch.effect_extensions[0];
 assert.equal(row.trait_key,trait.key);
 assert.equal(row.origin_id,'feature:trait:'+trait.key);
 assert.equal(row.parent_origin,trait.feature_origin);
 const record={...patch,classes:[{name:'Warlock',source:'PHB',level:5}]};
 const effects=collectEffectExtensions(record,[],[]);
 assert.equal(effects.length,1);
 assert.equal(traitBenefitGroups(trait,record,{effect_extensions:effects}).find(x=>x.type==='effect_extensions')?.items.length,1);
 const removed=removeBenefitPatch(record,trait,{type:'effect_extensions',id:'effect_extension:'+row.id});
 assert.equal(removed.effect_extensions.length,0);
 assert.equal(collectEffectExtensions({...record,...removed},[],[]).length,0);
 const masked=removeBenefitPatch({},trait,{type:'effect_extensions',id:'effect_extension:catalog-id'});
 assert.deepEqual(masked.trait_benefit_removed[trait.key],['effect_extension:catalog-id']);
 assert.deepEqual(restoreBenefitPatch({...record,...masked},trait).trait_benefit_removed,{});
 assert.throws(()=>addBenefitPatch({},trait,'effect_extensions',{
  target_kind:'spell',target_name:'Eldritch Blast',operation:'set_range',value:'-3',
  trigger:'passive',frequency:'each'},'trait:abc1234'),/Estensione non valida/);
});

test('disabled custom trait cannot affect other magical effects',()=>{
 const trait={key:'other|0|enchant',name:'Enchant',origin_key:'other|0',rank:2};
 const row=addBenefitPatch({},trait,'effect_extensions',{
  target_kind:'ability',target_name:'Custom Inspiration',operation:'add_effect',
  trigger:'saving_throw',frequency:'once_per_use',description:'Extra saving throw boon'},'trait:abc0001').effect_extensions[0];
 const record={effect_extensions:[row],trait_enabled:{[trait.key]:false}};
 assert.equal(collectEffectExtensions(record,[],[]).length,0);
 assert.equal(collectEffectExtensions({...record,trait_enabled:{[trait.key]:true}},[],[]).length,1);
});
