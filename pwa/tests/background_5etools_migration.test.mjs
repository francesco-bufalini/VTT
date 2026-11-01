import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {allocationVariants,originVariants,effectiveAllocations,allocationComplete} from '../ability_choice_rules.js';

const index=JSON.parse(readFileSync(new URL('../catalog/ability_grants.json',import.meta.url),'utf8'));
const prof=JSON.parse(readFileSync(new URL('../catalog/proficiency_grants.json',import.meta.url),'utf8'));
const key=row=>row.name.toLowerCase()+'|'+row.source.toLowerCase();

test('5eTools structured 2024 background grants are projected without per-background supplements',()=>{
 assert.equal(index.background.length,74);
 assert.equal(prof.background.length,150);
 assert.equal(new Set(index.background.map(key)).size,index.background.length);
 assert.equal(new Set(prof.background.map(key)).size,prof.background.length);
 const acolyte=prof.background.find(row=>row.name==='Acolyte'&&row.source==='XPHB');
 assert.deepEqual(acolyte.skillProficiencies,[{insight:true,religion:true}]);
 assert.deepEqual(acolyte.toolProficiencies,[{"calligrapher's supplies":true}]);
 assert.ok(prof.background.some(row=>row.name==='Aberrant Heir'&&row.source==='EFA'));
 // Same name and different source must never be conflated.
 assert.ok(prof.background.some(row=>row.name==='Acolyte'&&row.source==='PHB'));
});

test('2024 weighted +2/+1 and +1/+1/+1 ability allocations work for any background',()=>{
 const row=index.background.find(row=>row.name==='Acolyte'&&row.source==='XPHB');
 assert.ok(row);
 const variants=originVariants(index,'background',row,row.source);
 assert.equal(variants.length,2);
 assert.deepEqual(variants.map(v=>v.parts.map(p=>p.amount)),[[2,1],[1,1,1]]);
 const id='background|xphb|acolyte';
 let record={origin_ability_choices:[{origin_id:id,variant:0,
  allocations:[{part:0,ability:'int'},{part:1,ability:'wis'}]}]};
 assert.deepEqual(effectiveAllocations(record,id,variants),[
  {ability:'int',amount:2},{ability:'wis',amount:1}]);
 record={origin_ability_choices:[{origin_id:id,variant:1,
  allocations:[{part:0,ability:'int'},{part:1,ability:'wis'},{part:2,ability:'cha'}]}]};
 assert.deepEqual(effectiveAllocations(record,id,variants),[
  {ability:'int',amount:1},{ability:'wis',amount:1},{ability:'cha',amount:1}]);
 record={origin_ability_choices:[{origin_id:id,variant:0,
  allocations:[{part:0,ability:'int'},{part:1,ability:'int'}]}]};
 assert.deepEqual(effectiveAllocations(record,id,variants),[]);
 assert.equal(allocationComplete({allocations:[{part:0,ability:'int'},{part:1,ability:'int'}]},variants[0]),false);
});

test('legacy and malformed allocation definitions are handled without inventing bonuses',()=>{
 assert.deepEqual(allocationVariants([{choose:{from:['str','dex'],count:1,amount:1}}])[0].parts,
  [{options:['str','dex'],count:1,amount:1}]);
 assert.deepEqual(allocationVariants([{choose:{weighted:{from:['str'],weights:[2,1]}}}]),[]);
 assert.deepEqual(allocationVariants([{choose:{weighted:{from:['str','dex'],weights:[2,-3]}}}]),[]);
});
