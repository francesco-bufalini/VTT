import {test} from 'node:test';
import assert from 'node:assert/strict';
import {detailedEntry,flattenDescription} from '../catalog_data.js';

test('5etools tattoo descriptions resolve across catalog categories',async()=>{
 const original=globalThis.fetch;
 let calls=0;
 globalThis.fetch=async path=>{
  assert.equal(path,'/catalog/items.json');calls++;
  return {ok:true,json:async()=>({magic_items:{
   'absorbing tattoo|tce':{inherits:{entries:['The tattoo grants {@item resistance|phb}.'],additionalEntries:['Absorbs energy.']}},
   'barrier tattoo|tce':{entries:['The tattoo grants protection.']}
  }})};
 };
 try{
  const tattoo=await detailedEntry('items',{id:'magic_item:absorbing-tattoo',name:'Absorbing Tattoo',source:'TCE'});
  assert.match(flattenDescription(tattoo),/resistance/);
  assert.match(flattenDescription(tattoo),/Absorbs energy/);
  const legacy=await detailedEntry('items',{id:'legacy',_category:'items',name:'Barrier Tattoo',source:'TCE'});
  assert.match(flattenDescription(legacy),/tattoo grants protection/);
  assert.equal(calls,1);
 }finally{globalThis.fetch=original;}
});
test('description text merges inherited fields and removes exact duplicates',()=>{
 const result=flattenDescription({entries:['Main'],additionalEntries:['Extra'],inherits:{entries:['Main'],entriesTemplate:['Template']}});
 assert.equal(result,'Main\n\nExtra\n\nTemplate');
});
