import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {collectStructuredFeatures} from '../structured_effects.js';
import {powerSelectionModels} from '../power_selection.js';
import {calculateSheet} from '../sheet_rules.js';
import {applyOriginSpellChoice} from '../spell_selection.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const index=read('../catalog/classes.json');
const grants=read('../../vtt/enrichment/benefits/option_grant.json');
const lists=read('../../vtt/enrichment/benefits/option_list.json');
const resources=read('../../vtt/enrichment/benefits/resource.json');

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
 for(const entry of grants.entries.filter(entry=>!entry.benefit.option_grant.nested)){
  const ref=sourceFor(entry),record=makeRecord(ref);
  const features=collectStructuredFeatures(record,{classFeatures:index,
   optionGrants:grants,optionLists:lists,slotBenefits:resources});
  const matching=features.filter(feature=>feature.benefits?.some(benefit=>
   benefit.type==='option_grant'&&benefit.id===entry.benefit.id));
  if(!matching.length)missing.push(entry.benefit.id);
  else present.push(entry.benefit.id);
  if(matching.length>1&&!entry.benefit.option_grant.instances)
   ambiguous.push([entry.benefit.id,matching.map(f=>f.origin_id)]);
  if(matching.length&&entry.benefit.option_grant.option_kind!=='spell'){
   const catalog={optionGrants:grants,optionLists:lists};
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
 const originals=grants.entries.filter(entry=>!entry.benefit.option_grant.compatibility?.supplement_only);
 assert.equal(originals.length,47);
 const children=originals.filter(entry=>entry.benefit.option_grant.nested);
 assert.equal(children.length,4);
 for(const child of children){
  const refs=lists.entries.flatMap(entry=>entry.benefit.option_list?.options||[])
    .flatMap(option=>[...(option.effects||[]),...(option.item_effects?.effects||[])])
    .filter(effect=>effect.type==='option_grant'&&effect.grant_id===child.benefit.id);
  assert(refs.length,'Nested grant has no canonical parent application: '+child.benefit.id);
 }
 assert.deepEqual(missing,[], 'Each typed grant must have a real 5eTools feature');
 assert.deepEqual(ambiguous,[], 'Repeated features must explicitly declare per-feature instancing');
 assert.deepEqual(modelMissing,[], 'Every nondependent grant must produce a visible model');
});

test('audit: source-qualified 2024 Fighting Style features reveal non-option-grant paths',()=>{
 const rows=index.class_features.filter(row=>row.class_source==='XPHB'&&
  ['Fighter','Paladin','Ranger'].includes(row.class_name)&&
  /fighting style/i.test(row.name||''));
 const findings=rows.map(feature=>{
  const record=makeRecord({class_name:feature.class_name,class_source:'XPHB'});
  const installed=collectStructuredFeatures(record,{
   classFeatures:index,optionGrants:grants,slotBenefits:resources});
  const source=installed.find(row=>row.name===feature.name&&row.level===feature.level&&
   row.requirements?.class_name===feature.class_name);
  return {name:feature.class_name+' · '+feature.name,level:feature.level,
   linked:source?.benefits?.some(row=>row.type==='option_grant')||false};
 });
 console.log('OPTION_GRANT_2024_FIGHTING_STYLE_AUDIT '+JSON.stringify(findings));
 assert(findings.every(row=>row.level>=1));
});

test('audit: optional feature cantrip choices are nested option_grants',()=>{
 const choices=[
  {option:'optional:tce:druidic-warrior',type:'spell_choice:druidic_warrior',count:2,filter:'level=0|class=druid'},
  {option:'optional:tce:blessed-warrior',type:'spell_choice:blessed_warrior',count:2,filter:'level=0|class=cleric'},
  {option:'optional:phb:pact-of-the-tome',type:'spell_choice:pact_of_the_tome',count:3,filter:'level=0'}
 ];
 for(const choice of choices){
  const parent=lists.entries.find(row=>row.benefit.option_list?.id===choice.option);
  assert(parent,'Parent option must be defined by its 5eTools source: '+choice.option);
  assert(parent.benefit.option_list.options[0].effects.some(effect=>
   effect.type==='option_grant'&&effect.grant_id===choice.type));
  const declaration=grants.entries.find(row=>row.benefit?.id===choice.type);
  assert(declaration?.benefit?.option_grant?.nested);
  assert.equal(declaration.benefit.option_grant.layers.learned.limit,choice.count);
  assert.equal(declaration.benefit.option_grant.source.filter,choice.filter);
 }
});
