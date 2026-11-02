import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {spellExtensionTraits} from '../spell_extension_benefits.js';
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
