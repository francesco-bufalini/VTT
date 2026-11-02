import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {inheritCanonicalBenefitNames} from '../benefit_source_text.js';

const read=type=>JSON.parse(readFileSync(
 new URL('../../vtt/enrichment/benefits/'+type+'.json',import.meta.url),'utf8'));
function hasHandwrittenDescription(value){
 if(Array.isArray(value))return value.some(hasHandwrittenDescription);
 if(!value||typeof value!=='object')return false;
 return Object.entries(value).some(([key,item])=>
  key==='description'||hasHandwrittenDescription(item));
}

test('typed benefits contain no authored descriptions; source references remain',()=>{
 for(const type of ['action','attack','creature_grant','effect_extension',
   'item_grant','option_grant','option_list']){
  const catalog=read(type);
  for(const entry of catalog.entries)
   assert(!hasHandwrittenDescription(entry.benefit),
    type+' must obtain the description from the granting trait: '+entry.id);
 }
 const flavours=read('flavours');
 assert(flavours.entries.every(entry=>entry.flavours.every(flavour=>
  !Object.hasOwn(flavour,'detail')&&!Object.hasOwn(flavour,'description'))));
});

test('only redundant names are reconstructed from the canonical 5eTools reference',()=>{
 const actions=read('action');
 const racial=actions.entries.find(e=>e.id==='race:mpmm:firbolg:hidden_step');
 assert.equal(racial.benefit.name,undefined);
 assert.equal(inheritCanonicalBenefitNames(actions).entries.find(e=>e.id===racial.id)
  .benefit.name,racial.granted_by.ref.name);
 const grants=read('option_grant');
 const arcane=grants.entries.find(e=>e.id==='option_grant:arcane_armor');
 assert.equal(arcane.benefit.option_grant.title,undefined);
 assert.equal(inheritCanonicalBenefitNames(grants).entries.find(e=>e.id===arcane.id)
  .benefit.option_grant.title,'Arcane Armor');
 const lists=read('option_list');
 const named=inheritCanonicalBenefitNames(lists);
 for(const entry of named.entries.filter(e=>e.granted_by?.kind==='5etools')){
  const option=entry.benefit.option_list.options[0];
  assert.equal(option.name,entry.granted_by.ref.name);
  assert.equal(entry.benefit.option_list.name,entry.granted_by.ref.name);
  const original=lists.entries.find(row=>row.id===entry.id)
   .benefit.option_list.options[0];
  if(option.details)assert.equal(option.details.name,
   original.details?.name||entry.granted_by.ref.name,
   'Distinct sub-option names must not be replaced by the granting trait');
 }
});

test('mechanical conditions and distinct action / flavour names are preserved',()=>{
 assert(read('roll_mode').entries.some(e=>
  e.benefit.roll_modes?.some(m=>m.condition_label)));
 assert(read('roll_bonus').entries.some(e=>e.benefit.bonus?.condition_label));
 const actions=read('action');
 assert(actions.entries.some(e=>e.benefit.name&&
  e.benefit.name!==e.granted_by?.ref?.name));
 const flavours=read('flavours');
 assert(flavours.entries.some(e=>e.flavours.length>1&&
  new Set(e.flavours.map(f=>f.name)).size===e.flavours.length));
});
