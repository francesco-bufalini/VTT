import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {practicallySpellsFromBenefits} from '../practically_spells.js';
import {supplementalFeatureSpellGrants,spellEligible} from '../spell_selection.js';
const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const catalog=read('../../vtt/enrichment/benefits/practically_spells.json');
const projection=practicallySpellsFromBenefits(catalog);

test('practically spells come exclusively from typed benefits and appear on no spell list',()=>{
 assert.equal(catalog.benefit_type,'practically_spells');
 assert.equal(projection.spells.length,2);
 assert.equal(projection.grants.length,2);
 assert.deepEqual(new Set(projection.spells.map(row=>row.id)),new Set([
  'feature_slot_primeval_awareness_phb',
  'feature_slot_combat_wild_shape_heal_phb']));
 assert(projection.spells.every(spell=>spell.internal_grant===true&&
  Array.isArray(spell.lists)&&spell.lists.length===0&&
  !spell.classes?.length&&!spell.entries?.length));
 assert(projection.spells.every(spell=>!spellEligible(spell,{
  name:'Druid',spell_list_class_name:'Druid',max_level:9})));
 assert(projection.grants.every(grant=>grant.payment_mode==='slot'&&
  grant.mechanic_source==='typed.practically_spells'));
});
test('the Ranger capability consumes slots at the original source-qualified feature',()=>{
 const record={kind:'character',rules_version:'2014',class:'Ranger',class_source:'PHB',
   classes:[{name:'Ranger',source:'PHB',level:3}]};
 const feature={name:'Primeval Awareness',origin_id:'feature:primeval',
   origin_key:'class|phb|ranger',source:'PHB'};
 const grants=supplementalFeatureSpellGrants(record,[feature],projection.spells,
   projection.grants,[{name:'Ranger',ability:'wis'}],[]);
 assert.equal(grants.length,1);
 assert.equal(grants[0].origin_id,feature.origin_id);
 assert.equal(grants[0].spell_id,'feature_slot_primeval_awareness_phb');
 assert.equal(grants[0].payment_mode,'slot');
 assert.equal(grants[0].casting_ability_not_required,true);
});
test('Moon Druid healing uses a bonus action and requires Wild Shape',()=>{
 const record={kind:'character',rules_version:'2014',class:'Druid',class_source:'PHB',
   subclass:'Circle of the Moon',subclass_source:'PHB',
   classes:[{name:'Druid',source:'PHB',level:2,subclass:'Circle of the Moon',subclass_source:'PHB'}]};
 const feature={name:'Combat Wild Shape',origin_id:'feature:combat-wild-shape',
  origin_key:'class|phb|druid|subclass|circle of the moon|phb',source:'PHB'};
 const grants=supplementalFeatureSpellGrants(record,[feature],projection.spells,
  projection.grants,[{name:'Druid',ability:'wis'}],[]);
 assert.equal(grants.length,1);
 assert.equal(grants[0].spell_id,'feature_slot_combat_wild_shape_heal_phb');
 assert.equal(grants[0].payment_mode,'slot');
 assert.equal(grants[0].cast_action_type,'bonus');
 assert.match(grants[0].requires_context,/Forma selvatica/);
});
test('malformed lists, duplicate IDs or detached origins are rejected',()=>{
 const invalid=structuredClone(catalog);
 invalid.entries[0].benefit.parameters.spell.lists=['Ranger'];
 assert.throws(()=>practicallySpellsFromBenefits(invalid),/non valido/);
 const duplicate=structuredClone(catalog);
 duplicate.entries.push(structuredClone(duplicate.entries[0]));
 assert.throws(()=>practicallySpellsFromBenefits(duplicate),/duplicato/);
});
