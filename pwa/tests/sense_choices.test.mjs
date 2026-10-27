import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {selectedSources,grantedFields,fixedProficiencies} from '../structured_effects.js';
import {calculateSenses} from '../sense_rules.js';
const prof=JSON.parse(readFileSync(new URL('../catalog/proficiency_grants.json',import.meta.url),'utf8'));
const senses=JSON.parse(readFileSync(new URL('../catalog/sense_grants.json',import.meta.url),'utf8'));
test('Custom Lineage chooses darkvision or skill, not both, and preserves dormant skill',()=>{
 const key='race|tce|custom lineage';
 const saved={species:'Custom Lineage',species_source:'TCE',
  proficiency_choices:[{origin_id:key,kind:'skill',key:'perception'}]};
 const chosen=(value)=>({...saved,origin_sense_choices:{[key]:value}});
 assert.equal(fixedProficiencies(chosen('skill'),prof,[]).has('skill:perception'),true);
 assert.equal(calculateSenses(chosen('skill'),[],senses).distances.darkvision,undefined);
 assert.equal(fixedProficiencies(chosen('darkvision'),prof,[]).has('skill:perception'),false);
 assert.equal(calculateSenses(chosen('darkvision'),[],senses).distances.darkvision,60);
 const source=selectedSources(chosen('darkvision'),prof,[]).find(x=>x.id===key);
 assert.deepEqual(grantedFields(source,'skill'),[]);
 assert.equal(fixedProficiencies(chosen('skill'),prof,[]).has('skill:perception'),true,
  'Switching back must restore the previously selected skill');
});
