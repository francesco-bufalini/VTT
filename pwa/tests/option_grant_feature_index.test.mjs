import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {collectStructuredFeatures} from '../structured_effects.js';
import {powerSelectionModels} from '../power_selection.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const index=read('../catalog/classes.json');
const grants=read('../../vtt/enrichment/benefits/option_grant.json');
const resources=read('../../vtt/enrichment/benefits/resource.json');
const spellcasting=read('../catalog/spellcasting_benefits.json');
const optionCatalog=read('../catalog/optional_feature_progressions.json');
const powerCatalog=read('../catalog/power_selections.json');
const spellSlots=resources.entries.filter(row=>row.benefit.kind==='spell_slots');
const sourceFor=entry=>entry.granted_by.ref;
const makeRecord=ref=>({
 kind:'character',id:'test-ownership',level:20,
 rules_version:ref.class_source==='XPHB'?'2024':'2014',
 classes:[{name:ref.class_name,source:ref.class_source,level:20,
  ...(ref.subclass?{subclass:ref.subclass,subclass_source:ref.subclass_source||ref.source}:{})}]
});

test('migration grant identity is source-qualified and each slot resource has an owner',()=>{
 assert.equal(new Set(grants.entries.map(row=>row.id)).size,grants.entries.length);
 assert.equal(new Set(spellSlots.map(row=>row.id)).size,spellSlots.length);
 for(const resource of spellSlots){
  assert(grants.entries.some(g=>g.granted_by.ref.class_name===resource.granted_by.ref.class_name&&
    g.granted_by.ref.class_source===resource.granted_by.ref.class_source&&
    g.granted_by.ref.name===resource.granted_by.ref.name&&
    (g.granted_by.ref.subclass||'')===(resource.granted_by.ref.subclass||'')),
    'Orphan slot entitlement: '+resource.id);
 }
});

test('audit: every migrated option-grant has a resolvable real feature source',()=>{
 const missing=[],present=[],ambiguous=[],modelMissing=[];
 for(const entry of grants.entries){
  const ref=sourceFor(entry),record=makeRecord(ref);
  const features=collectStructuredFeatures(record,{classFeatures:index,
   spellcastingBenefits:spellcasting,optionGrants:grants,slotBenefits:resources});
  const matching=features.filter(feature=>feature.benefits?.some(benefit=>
   benefit.type==='option_grant'&&benefit.id===entry.benefit.id));
  if(!matching.length)missing.push(entry.benefit.id);
  else present.push(entry.benefit.id);
  if(matching.length>1&&!entry.benefit.option_grant.instances)
   ambiguous.push([entry.benefit.id,matching.map(f=>f.origin_id)]);
  if(matching.length&&entry.benefit.option_grant.option_kind!=='spell'){
   const catalog={...powerCatalog,optionGrants:grants,optionalFeatureProgressions:optionCatalog};
   const selection=powerSelectionModels(record,{features},catalog);
   if(!selection.some(m=>m.id===entry.benefit.id)&&
     !entry.benefit.option_grant.requires_application)modelMissing.push(entry.benefit.id);
  }
 }
 console.log('OPTION_GRANT_FEATURE_SOURCE_AUDIT '+JSON.stringify({
  total:grants.entries.length,present:present.length,missing,ambiguous,modelMissing
 }));
 // The catalog source report is intentionally preserved even if upstream
 // 5eTools does not currently contain a source, so that omissions are visible.
 assert.equal(grants.entries.length,41);
 assert.deepEqual(missing,[], 'Each typed grant must have a real 5eTools feature');
 assert.deepEqual(ambiguous,[], 'Repeated features must explicitly declare per-feature instancing');
 assert.deepEqual(modelMissing,[], 'Every nondependent grant must produce a visible model');
});
