import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {collectStructuredFeatures} from '../structured_effects.js';
import {powerSelectionModels} from '../power_selection.js';
import {calculateSheet} from '../sheet_rules.js';

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

test('audit: optional spell-choice privileges create source-scoped spell pickers',()=>{
 const catalogs={
  classFeatures:index,classMechanics:read('../catalog/class_mechanics.json'),
  abilityGrants:read('../catalog/ability_grants.json'),
  spellcastingBenefits:spellcasting,optionGrants:grants,
  powerSelections:powerCatalog,optionalFeatureProgressions:optionCatalog
 };
 const checks=[
  {className:'Ranger',level:2,rule:'optional:class:phb:ranger:fs-r',
   option:'optional:tce:druidic-warrior',mode:'manual'},
  {className:'Paladin',level:2,rule:'optional:class:phb:paladin:fs-p',
   option:'optional:tce:blessed-warrior',mode:'manual'},
  {className:'Warlock',level:3,rule:'optional:class:phb:warlock:pb',
   option:'optional:phb:pact-of-the-tome',mode:'automatic'}
 ];
 const findings=[];
 for(const check of checks){
  const record={kind:'character',rules_version:'2014',level:check.level,
   class:check.className,class_source:'PHB',
   classes:[{name:check.className,source:'PHB',level:check.level}],
   abilities:{str:10,dex:10,con:12,int:12,wis:16,cha:16},
   power_selections:{[check.rule]:{learned:[check.option]}},
   ...(check.mode==='manual'?{power_applications:{[check.rule]:[{id:check.option}]}}:{})};
  const calculated=calculateSheet(record,catalogs);
  const candidates=(calculated.origin_choices||[]).filter(row=>
   /Druidic Warrior|Blessed Warrior|Pact of the Tome/i.test(row.origin_name||''));
  findings.push({className:check.className,option:check.option,
   choices:candidates.map(row=>({origin:row.origin_name,count:row.count,
    filter:row.filter||'',spell_options:row.spell_options?.length||0}))});
 }
 console.log('OPTION_GRANT_SPELL_CHOICE_AUDIT '+JSON.stringify(findings));
 assert.equal(findings.length,3);
});
