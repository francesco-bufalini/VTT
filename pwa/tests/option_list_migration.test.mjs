import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {powerSelectionModels} from '../power_selection.js';
import {inheritCanonicalBenefitNames} from '../benefit_source_text.js';
const read=file=>JSON.parse(readFileSync(new URL(file,import.meta.url),'utf8'));
const grants=read('../../vtt/enrichment/benefits/option_grant.json');
const rawLists=read('../../vtt/enrichment/benefits/option_list.json');
const lists=inheritCanonicalBenefitNames(rawLists);
const official=lists.entries.filter(entry=>entry.granted_by?.ref?.category==='optional_feature');
const subclass=lists.entries.filter(entry=>entry.id.startsWith('option_list:barbarian:2014:'));
const local=lists.entries.filter(entry=>entry.granted_by?.kind==='homebrew');
const options=lists.entries.flatMap(entry=>entry.benefit?.option_list?.options||[]);
test('272 optional features, 13 source-bound subclass options and three local capabilities are unique',()=>{
 assert.equal(official.length,272);assert.equal(local.length,3);
 assert.equal(subclass.length,3);
 assert.equal(subclass.flatMap(entry=>entry.benefit.option_list.options).length,13);
 assert.equal(new Set(options.map(row=>row.id)).size,288);
 for(const entry of official){
  const option=entry.benefit.option_list.options[0],ref=entry.granted_by.ref;
  assert.equal(ref.category,'optional_feature');assert.equal(ref.name,option.name);
  assert.equal(ref.source,option.source);assert.equal(entry.benefit.option_list.id,option.id);
 }
 assert(local.every(entry=>entry.benefit.option_list.options[0].local===true));
 assert(rawLists.entries.filter(entry=>entry.granted_by?.kind==='5etools')
  .every(entry=>!entry.benefit.option_list.name&&
    !entry.benefit.option_list.options[0].name&&
    !entry.benefit.option_list.options[0].description),
  'Canonical option names and descriptions belong to 5eTools, not the benefits JSON');
 for(const id of ['optional:tce:druidic-warrior','optional:tce:blessed-warrior','optional:phb:pact-of-the-tome']){
  const option=options.find(row=>row.id===id);
  assert(option.effects.some(effect=>effect.type==='option_grant'));
 }
});
test('all 17 optional progressions reference the canonical shared option lists',()=>{
 const typed=grants.entries.filter(entry=>entry.benefit?.option_grant?.source?.type==='list_refs'&&
  entry.benefit.option_grant.source.feature_types?.length);
 assert.equal(typed.length,17);
 const supported=new Set(options.flatMap(option=>option.types||[]));
 for(const entry of typed){
  const grant=entry.benefit.option_grant;
  assert(grant.source.feature_types.every(type=>supported.has(type)),grant.id);
 }
});
test('Fighting Styles remain selectable without a legacy optional-feature catalog',()=>{
 const rule=grants.entries.find(e=>e.benefit?.option_grant?.id==='optional:class:phb:ranger:fs-r').benefit.option_grant;
 const record={kind:'character',rules_version:'2014',classes:[{name:'Ranger',source:'PHB',level:2}]};
 const context={features:[{name:'Fighting Style',class_name:'Ranger',class_source:'PHB',
  origin_id:'test:ranger',origin_key:'class|phb|ranger'}]};
 const model=powerSelectionModels(record,context,{optionGrants:grants,optionLists:lists}).find(row=>row.id===rule.id);
 assert(model);assert(model.options.some(row=>row.id==='optional:phb:archery'));
 assert(model.options.some(row=>row.id==='optional:tce:blind-fighting'));
 assert.equal(new Set(model.options.map(row=>row.id)).size,model.options.length);
});
