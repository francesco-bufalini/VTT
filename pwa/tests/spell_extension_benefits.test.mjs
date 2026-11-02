import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {spellExtensionTraits} from '../spell_extension_benefits.js';
import {spellCastPlan} from '../native_sheet.js';
const catalog=JSON.parse(readFileSync(new URL('../../vtt/enrichment/benefits/spell_extension.json',import.meta.url),'utf8'));
const feature={key:'merge-with-stone',origin_key:'species|genasi|mpmm',origin_id:'feature:merge-with-stone',name:'Merge with Stone',entries:['Original 5eTools trait description']};
const record={species:'Genasi',species_source:'MPMM',subrace:'Earth',subrace_source:'MPMM'};
test('spell extension displays its owned trait for the exact Earth Genasi spell',()=>{
 const result=spellExtensionTraits(record,{features:[feature]},{name:'Blade Ward',source:'PHB'},catalog);
 assert.equal(result.length,1);
 assert.equal(result[0].feature,feature);
 assert.equal(result[0].trait,'Merge with Stone');
});
test('spell extensions do not leak between subraces, origins or spells',()=>{
 for(const other of [{...record,subrace:'Fire'},{...record,species_source:'EEPC'},{...record,trait_enabled:{'merge-with-stone':false}}])
  assert.equal(spellExtensionTraits(other,{features:[feature]},{name:'Blade Ward',source:'PHB'},catalog).length,0);
 assert.equal(spellExtensionTraits(record,{features:[feature]},{name:'Light',source:'PHB'},catalog).length,0);
 assert.equal(spellExtensionTraits(record,{features:[feature]},{name:'Blade Ward',source:'XPHB'},catalog).length,0);
});

test('sequence casting pays its own tracker once and leaves normal Blade Ward free',()=>{
 const trackerId='race:mpmm:genasi:earth:blade_ward_bonus:uses';
 const actionId='attack_action:feature:merge-with-stone';
 const base={id:'phb2014_blade_ward',name:'Blade Ward',source:'PHB',level:0};
 const sheet={prepared_spells:[base],resource_tracker_spent:{},spellcasting_ability:'int'};
 const calculated={origin_spells:[],features:[],attack_actions:[{id:actionId,cost:1,tracker_id:trackerId,
   steps:[{selector:{kind:'spell',name:'Blade Ward',source:'PHB'}}]}],
   trackers:[{id:trackerId,max:3,spent:0}],
   values:{'casting_hit:int':3,'casting_dc:int':13}};
 const bonus=spellCastPlan(sheet,{...base,sequence_action_id:actionId},0,calculated,'auto');
 assert.equal(bonus.patch.resource_tracker_spent[trackerId],1);
 const normal=spellCastPlan(sheet,base,0,calculated,'auto');
 assert.equal(normal.patch.resource_tracker_spent,undefined);
 assert.throws(()=>spellCastPlan(sheet,{...base,name:'Other',sequence_action_id:actionId},0,calculated,'auto'),
   /non previsto dalla sequenza/);
});
