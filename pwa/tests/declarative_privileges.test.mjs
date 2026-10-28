import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {CLASS_DEFENSE_RULES as defenses} from '../catalog/class_defense_rules.js';
import {CLASS_FEATURE_RULES as operations} from '../catalog/class_feature_operations.js';
import {CLASS_NUMERIC_FEATURE_GRANTS as numeric} from '../catalog/class_numeric_feature_grants.js';
import {BARBARIAN_2014_GRANTS as barbarian} from '../catalog/barbarian_2014_rules.js';
import {supplementalClassSpells,supplementalItemBonuses} from '../catalog/supplemental_rules.js';
import {CLASS_DEFENSE_RULES as legacyDefenses} from '../class_defenses.js';
import {CLASS_FEATURE_RULES as legacyOperations} from '../feature_mechanics.js';
import {barbarian2014Supplements} from '../barbarian_2014.js';

const source=p=>readFileSync(new URL(p,import.meta.url),'utf8');

test('declarative source catalogs retain the existing feature identities',()=>{
 assert.equal(defenses,legacyDefenses);
 assert.equal(operations,legacyOperations);
 assert.equal(defenses.length,23);
 assert.equal(operations.length,31);
 assert.equal(new Set(operations.map(rule=>rule[0])).size,operations.length);
 assert.deepEqual(numeric.map(rule=>rule.feature),[
  'Magic Item Adept','Magic Item Savant','Magic Item Master','Soul of Artifice']);
 assert.equal(supplementalClassSpells[0].subclass,'Armorer');
 assert(supplementalItemBonuses.some(rule=>rule.names.includes('Stone of Good Luck')));
});

test('Barbarian supplements come from feature-keyed declarative grants',()=>{
 assert.deepEqual(barbarian.map(rule=>rule.kind),[
  'numeric','numeric','action','roll_mode','initiative',
  'proficiency','proficiency','spell_choice']);
 const record={class:'Barbarian',class_source:'PHB',level:7,classes:[{name:'Barbarian',source:'PHB',level:7}],rules_version:'2014',inventory:[]};
 const trait={name:'Fast Movement',origin_id:'feature:fast',origin_key:'class|phb|barbarian'};
 assert.equal(barbarian2014Supplements(record,[trait]).numeric_grants[0]?.expression,'10');
 assert.equal(barbarian2014Supplements({...record,origin_enabled:{'feature:fast':false}},[trait]).numeric_grants.length,0);
 assert.equal(barbarian2014Supplements({...record,rules_version:'2024'},[trait]).numeric_grants.length,0);
});

test('offline app-shell contains every declarative rule module',()=>{
 const sw=source('../sw.js'),host=source('../../network/pwa_host.gd');
 for(const file of ['class_defense_rules.js','class_feature_operations.js',
  'class_numeric_feature_grants.js','barbarian_2014_rules.js','supplemental_rules.js']){
   assert(sw.includes('"/catalog/'+file+'"'),file+' missing from offline shell');
   assert(host.includes('"/catalog/'+file+'": ["res://pwa/catalog/'+file+'"'),
     file+' missing from native host routes');
 }
});
