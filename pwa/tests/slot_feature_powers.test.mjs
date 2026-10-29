import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {supplementalFeatureSpellGrants,sessionSpellEntries} from '../spell_selection.js';

const catalog=JSON.parse(readFileSync(new URL('../catalog/feature_slot_spells.json',import.meta.url),'utf8'));
const rangerFeature={name:'Primeval Awareness',origin_id:'feature:ranger-primal',
 origin_key:'class|phb|ranger|feature|primeval awareness'};
const moonFeature={name:'Combat Wild Shape',origin_id:'feature:moon-wild',
 origin_key:'class|phb|druid|subclass|circle of the moon|phb|feature|combat wild shape'};
function grants(record,features){
 return supplementalFeatureSpellGrants(record,features,catalog.spells,catalog.grants,
  [{name:record.classes[0].name,ability:'wis'}],[]);
}
test('Primeval Awareness is a native first-level slot-paid grant owned by its feature',()=>{
 const record={rules_version:'2014',classes:[{name:'Ranger',source:'PHB',level:3}]};
 const found=grants(record,[rangerFeature]);
 assert.equal(found.length,1);
 assert.equal(found[0].spell_id,'feature_slot_primeval_awareness_phb');
 assert.equal(found[0].origin_id,rangerFeature.origin_id);
 assert.equal(found[0].payment_mode,'slot');
 assert.equal(catalog.spells.find(spell=>spell.id===found[0].spell_id).level,1);
 assert.equal(grants({...record,classes:[{...record.classes[0],level:2}]},[rangerFeature]).length,0);
 assert.equal(grants(record,[{...rangerFeature,inactive:true}]).length,0);
 assert.equal(grants({...record,classes:[{name:'Ranger',source:'XPHB',level:3}]},[rangerFeature]).length,0);
});
test('Moon Druid grant uses the same spell path and requires explicit Wild Shape context',()=>{
 const record={rules_version:'2014',classes:[{name:'Druid',source:'PHB',subclass:'Circle of the Moon',subclass_source:'PHB',level:2}]};
 const found=grants(record,[moonFeature]);
 assert.equal(found.length,1);
 assert.equal(found[0].spell_id,'feature_slot_combat_wild_shape_heal_phb');
 assert.equal(found[0].cast_action_type,'bonus');
 assert.equal(found[0].requires_context,'Confermo di essere in Forma selvatica');
 assert.equal(found[0].payment_mode,'slot');
 const spells=sessionSpellEntries(record,{casting_classes:[],origin_spells:found},catalog.spells);
 assert.equal(spells.length,1);
 assert.equal(spells[0].level,1);
 assert.equal(spells[0].grant_id,found[0].id);
 assert.deepEqual(spells[0].time,[{number:1,unit:'bonus'}]);
 assert.equal(grants({...record,classes:[{...record.classes[0],subclass:'Circle of the Land'}]},[moonFeature]).length,0);
});
test('Both powers remain spell definitions, not separately tracked slot powers',()=>{
 assert.equal(catalog.spells.length,2);
 assert.equal(catalog.grants.length,2);
 assert.ok(catalog.spells.every(spell=>spell.level===1&&spell.internal_grant));
 assert.ok(catalog.grants.every(grant=>grant.payment_mode==='slot'));
});
