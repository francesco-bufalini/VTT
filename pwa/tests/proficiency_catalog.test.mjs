import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,existsSync} from 'node:fs';
import {proficiencyIndexFromBenefits,proficiencySourceEntry,PROFICIENCY_SOURCE_SECTIONS}
 from '../proficiency_catalog.js';
import {proficiencyTestIndex} from './proficiency_test_fixture.mjs';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const typed=read('../../vtt/enrichment/benefits/proficiency_grant.json');
const languages=read('../../vtt/data/languages_5etools.json');

test('all proficiency source mechanics are authored only in proficiency_grant v2',()=>{
 assert.equal(typed.schema_version,2);
 assert.equal(typed.benefit_type,'proficiency_grant');
 assert.equal(existsSync(new URL('../catalog/proficiency_grants.json',import.meta.url)),false);
 for(const section of PROFICIENCY_SOURCE_SECTIONS)assert.equal(languages[section],undefined);
 const sources=typed.entries.filter(e=>e.benefit?.proficiency_grant?.source_rules);
 const fixed=typed.entries.filter(e=>e.benefit?.proficiency_grant?.grants);
 const selectable=typed.entries.filter(e=>e.benefit?.proficiency_grant?.groups);
 assert.equal(sources.length,411);
 assert.equal(fixed.length,12);
 assert.equal(selectable.length,7);
 assert.equal(new Set(typed.entries.map(e=>e.id)).size,430);
 assert.deepEqual(fixed.map(e=>e.benefit.proficiency_grant.grants[0].kind),Array(12).fill('save'));
 assert(fixed.every(e=>e.granted_by.kind==='flavour'));
 assert.equal(languages.languages.length,111);
});

test('every migrated section is reconstructed from the typed catalog without dropping source metadata',()=>{
 const index=proficiencyTestIndex();
 const expected={class:26,race:124,subrace:37,background:150,feat:26,
  classFeature:7,subclassFeature:41};
 for(const [section,count] of Object.entries(expected))assert.equal(index[section]?.length,count,section);
 const wizard=index.class.find(e=>e.name==='Wizard'&&e.source==='PHB');
 assert.deepEqual(wizard.savingThrows,['int','wis']);
 assert.equal(wizard.multiclassProficiencies,undefined);
 assert(wizard.startingProficiencies.skills[0].choose.from.includes('arcana'));
 const artificer=index.class.find(e=>e.name==='Artificer'&&e.source==='TCE');
 assert(artificer.multiclassProficiencies.toolProficiencies);
 const feat=index.feat.find(e=>e.name==='Skilled'&&e.source==='PHB');
 assert(feat&&!feat.proficiencyChoices,'Skilled choices are in the typed permanent grant');
 assert.equal(index.subrace.filter(e=>e.name==='Variant; Mark of Finding').length,2);
 assert.equal(proficiencyIndexFromBenefits(languages,typed).race.length,124);
});

test('typed source profiles round-trip, including subclass level, replacements and ownership',()=>{
 for(const entry of typed.entries){
  const rule=entry.benefit?.proficiency_grant?.source_rules;
  if(!rule)continue;
  const ref=entry.granted_by.ref;
  const old=proficiencyIndexFromBenefits({},{
   schema_version:2,benefit_type:'proficiency_grant',entries:[entry]
  })[rule.section][0];
  const rewritten=proficiencySourceEntry(rule.section,old,entry.id);
  assert.deepEqual(rewritten.granted_by,entry.granted_by,entry.id);
  assert.deepEqual(rewritten.benefit.proficiency_grant.source_rules,rule,entry.id);
  assert.equal(ref.source,old.source);
 }
});
