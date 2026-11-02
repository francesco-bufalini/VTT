import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {powerSelectionModels} from '../power_selection.js';

const read=file=>JSON.parse(readFileSync(new URL(file,import.meta.url),'utf8'));
const legacy=read('../catalog/optional_feature_progressions.json');
const grants=read('../../vtt/enrichment/benefits/option_grant.json');
const lists=read('../../vtt/enrichment/benefits/option_list.json');
const options=lists.entries.flatMap(entry=>entry.benefit?.option_list?.options||[]);

test('272 optional features retain their exact source identity and mechanical payload',()=>{
 assert.equal(options.length,272);
 assert.equal(new Set(options.map(row=>row.id)).size,272);
 assert.deepEqual(options,legacy.options);
 for(const entry of lists.entries){
  const ref=entry.granted_by?.ref,option=entry.benefit?.option_list?.options?.[0];
  assert.equal(entry.granted_by?.kind,'5etools');
  assert.equal(ref?.category,'optional_feature');
  assert.equal(ref?.name,option?.name);
  assert.equal(ref?.source,option?.source);
  assert.equal(entry.benefit?.option_list?.id,option?.id);
 }
});

test('all 17 typed grants resolve exactly the same selections and effects without legacy options',()=>{
 const typed=grants.entries.filter(entry=>entry.benefit?.option_grant?.source?.type==='list_refs'&&
  entry.benefit?.option_grant?.source?.feature_types?.length);
 assert.equal(typed.length,17);
 const former=structuredClone(grants);
 for(const entry of former.entries)
  if(entry.benefit?.option_grant?.source?.type==='list_refs'&&entry.benefit.option_grant.source.feature_types?.length)
   entry.benefit.option_grant.source.type='optional_features';
 for(const entry of typed){
  const rule=entry.benefit.option_grant,owner=rule.owner;
  const record={kind:'character',rules_version:owner.class_source==='XPHB'?'2024':'2014',
   classes:[{name:owner.class_name,source:owner.class_source,level:20,
    ...(owner.subclass?{subclass:owner.subclass,subclass_source:owner.subclass_source||owner.class_source}:{})}]};
  const feature={name:owner.trait,class_name:owner.class_name,class_source:owner.class_source,
   origin_key:'class|'+owner.class_source.toLowerCase()+'|'+owner.class_name.toLowerCase(),
   origin_id:'test:'+rule.id,
   level:rule.instances?.mode==='per_feature'?Number(rule.layers?.learned?.limit?.by_class_level?.[0]?.[0]||1):2};
  const calculated={features:[feature]};
  const modern=powerSelectionModels(record,calculated,{optionGrants:grants,optionLists:lists})
   .find(row=>row.id===rule.id);
  const before=powerSelectionModels(record,calculated,{
   optionGrants:former,optionalFeatureProgressions:legacy})
   .find(row=>row.id===rule.id);
  assert(modern&&before,'Missing selection models: '+rule.id);
  assert.deepEqual(modern.options,before.options,'Migrated options differ for '+rule.id);
  assert(modern.options.length,'No official options for '+rule.id);
 }
});

test('typed list_refs grants do not depend on the old optional-feature catalog',()=>{
 const rule=grants.entries.find(entry=>entry.benefit?.option_grant?.id==='optional:class:phb:ranger:fs-r')
  .benefit.option_grant;
 const record={kind:'character',rules_version:'2014',
  classes:[{name:'Ranger',source:'PHB',level:2}]};
 const calculated={features:[{name:'Fighting Style',class_name:'Ranger',class_source:'PHB',
  origin_id:'test:ranger',origin_key:'class|phb|ranger'}]};
 const model=powerSelectionModels(record,calculated,{
  optionGrants:grants,optionLists:lists,optionalFeatureProgressions:{options:[]}})
  .find(row=>row.id===rule.id);
 assert(model);
 assert(model.options.some(row=>row.id==='optional:phb:archery'));
 assert(model.options.some(row=>row.id==='optional:tce:blind-fighting'));
});

test('partial typed lists recover missing legacy choices in canonical order without duplicating IDs',()=>{
 const rule=grants.entries.find(entry=>entry.benefit?.option_grant?.id==='optional:class:phb:warlock:ei')
  .benefit.option_grant;
 const record={kind:'character',rules_version:'2014',classes:[{name:'Warlock',source:'PHB',level:5}]};
 const context={features:[{name:'Eldritch Invocations',class_name:'Warlock',class_source:'PHB',
  origin_id:'feature:warlock',origin_key:'class|phb|warlock'}]};
 const original=powerSelectionModels(record,context,{
   optionGrants:grants,optionLists:lists,
   optionalFeatureProgressions:legacy}).find(row=>row.id===rule.id);
 const firstEldritch=lists.entries.findIndex(entry=>
   entry.benefit?.option_list?.options?.[0]?.types?.includes('EI'));
 assert(firstEldritch>=0);
 const partial={...lists,entries:lists.entries.filter((_,i)=>i!==firstEldritch)};
 const migrated=powerSelectionModels(record,context,{
   optionGrants:grants,optionLists:partial,
   optionalFeatureProgressions:legacy}).find(row=>row.id===rule.id);
 assert(original&&migrated);
 assert.deepEqual(migrated.options,original.options);
 assert.equal(new Set(migrated.options.map(row=>row.id)).size,migrated.options.length);
});
