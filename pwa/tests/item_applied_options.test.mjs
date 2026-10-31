import test from 'node:test';
import assert from 'node:assert/strict';
import {itemAppliedOptions} from '../item_applied_options.js';

const item={id:'weapon:longsword',instance_id:'one',name:'Longsword',
 option_extensions:[
  {id:'flame',name:'Flame Tongue',generic_variant:true,description:'Fire damage'},
  {id:'enhance',name:'Enhanced Weapon',selection_id:'artificer_infusions',description:'Enhanced attack'}
 ]};
const effects=[
 {id:'infused',origin_id:'item-option:one:enhance',origin_name:'Oggetto · Enhanced Weapon'},
 {id:'other-1',origin_id:'feature:armor',origin_name:'Magical Armor',description:'One technical effect'},
 {id:'other-2',origin_id:'feature:armor',origin_name:'Magical Armor',description:'Another technical effect'}
];
test('variants and granted extensions share one list with only variants removable',()=>{
 const applied=itemAppliedOptions(item,effects,{
  optionDescription:row=>row.description,
  originDescription:row=>row.origin_name==='Magical Armor'?'Original trait text':''
 });
 assert.deepEqual(applied.map(row=>row.name),['Flame Tongue','Enhanced Weapon','Magical Armor']);
 assert.deepEqual(applied.map(row=>row.removable),[true,false,false]);
 assert.equal(applied[0].variant_id,'flame');
 assert.equal(applied[1].variant_id,'');
 assert.equal(applied[2].description,'Original trait text');
 assert.equal(applied[2].effects.length,2);
 assert.equal(applied[1].effects.length,0,'Do not show an infusion effect twice');
});
test('multiple effects from one granting trait become one displayed entry',()=>{
 const list=itemAppliedOptions({option_extensions:[]},effects.slice(1),
  {originDescription:()=> 'Trait description'});
 assert.equal(list.length,1);
 assert.equal(list[0].effects.length,2);
});
test('effects from a different item instance do not duplicate the current option',()=>{
 const applied=itemAppliedOptions({...item,instance_id:'two'},effects,
  {optionDescription:row=>row.description,originDescription:()=> 'Source text'});
 assert.equal(applied.length,4);
 assert.equal(applied.find(row=>row.name==='Oggetto · Enhanced Weapon').removable,false);
});
