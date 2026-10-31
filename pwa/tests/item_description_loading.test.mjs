import {test} from 'node:test';
import assert from 'node:assert/strict';
import {detailedEntry,flattenDescription} from '../catalog_data.js';

test('5etools item-group placeholders are expanded for the absorbing tattoo variants',async()=>{
 const original=globalThis.fetch;
 let calls=0;
 globalThis.fetch=async path=>{
  assert.equal(path,'/catalog/items.json');calls++;
  return {ok:true,json:async()=>({magic_items:{
   'acid absorbing tattoo|tce':{entries:['{#itemEntry Absorbing Tattoo|TCE}']},
   'cold absorbing tattoo|tce':{entries:['{#itemEntry Absorbing Tattoo|TCE}']},
   'barrier tattoo|tce':{entries:['The tattoo grants protection.']},
   'parent item|dmg':{inherits:{entries:['A parent description.']}},
   'subtype item|dmg':{entries:['{#itemEntry Parent Item|DMG}']}
  }})};
 };
 try{
  for(const type of ['Acid','Cold']){
   const tattoo=await detailedEntry('items',{id:'magic_item:'+type.toLowerCase(),name:type+' Absorbing Tattoo',source:'TCE'});
   const prose=flattenDescription(tattoo);
   assert.match(prose,new RegExp('resistance to '+type.toLowerCase()+' damage'));
   assert.match(prose,/Damage Absorption/);
   assert.doesNotMatch(prose,/\{#itemEntry/);
  }
  const inherited=await detailedEntry('items',{id:'magic_item:subtype',name:'Subtype Item',source:'DMG'});
  assert.match(flattenDescription(inherited),/A parent description/);
  const legacy=await detailedEntry('items',{id:'legacy',_category:'items',name:'Barrier Tattoo',source:'TCE'});
  assert.match(flattenDescription(legacy),/tattoo grants protection/);
  assert.equal(calls,1,'offline detail index should be shared');
 }finally{globalThis.fetch=original;}
});

test('description text merges inherited fields and removes exact duplicates',()=>{
 const result=flattenDescription({entries:['Main'],additionalEntries:['Extra'],
  inherits:{entries:['Main'],entriesTemplate:['Template']}});
 assert.equal(result,'Main\n\nExtra\n\nTemplate');
});
