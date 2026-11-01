import {speciesPowerTestIndex} from './species_power_test_fixture.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {racialPowerProjection} from '../species_powers.js';
import {abilityAttackRoll} from '../action_economy.js';
import {racialItemGrantFeatures,featureItemGrants,claimFeatureItemPatch} from '../feature_item_grants.js';
import {expandedOriginSpellFeatures,expandedOriginClassSpellIds,spellEligible,
 castingSources,structuredSpellGrants} from '../spell_selection.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const powers=speciesPowerTestIndex();
const original={races:read('../../vtt/data/compendium_features_5etools.json').races};
const items=read('../catalog/feature_item_grants.json').grants;
const additional=read('../../vtt/data/additional_spells_5etools.json').entries;
const base={kind:'character',rules_version:'2014',level:5,
 abilities:{str:12,dex:12,con:12,int:14,wis:10,cha:10},inventory:[]};

test('DMG Gnoll Rampage is an unconditional selectable bonus-action Bite roll',()=>{
 const record={...base,species:'Gnoll',species_source:'DMG',
  species_id:'5etools:races:dmg:gnoll'};
 const trait={name:'Rampage',origin_key:'species|'+record.species_id+'|dmg',
  origin_id:'feature:species|'+record.species_id+'|dmg|1|rampage',key:'rampage'};
 const projected=racialPowerProjection(record,powers,[trait],original);
 const action=projected.abilities.find(row=>row.name==='Rampage');
 assert(action);
 assert.equal(action.action_type,'bonus');
 assert.equal(action.resource_cost,0);
 assert.deepEqual(action.roll_attack,{kind:'attack',trait:'Bite',slot:'natural'});
 assert.match(action.description,/0 hit points/);
 const target='attack_hit:natural:gnoll:bite';
 const roll=abilityAttackRoll(action,{attacks:[{id:'natural:gnoll:bite',
  name:'Bite',slot:'natural'}],values:{[target]:5}});
 assert.equal(roll.target,target);
 assert(!racialPowerProjection({...record,species:'Gnome',species_source:'PHB'},
  powers,[trait]).abilities.some(row=>row.name==='Rampage'));
});

test('Rock Gnome Tinker grants three actual inventory devices, including duplicates',()=>{
 const record={...base,species:'Gnome',species_source:'PHB',
  species_id:'5etools:races:phb:gnome',subrace:'Rock',subrace_source:'PHB'};
 const feature=racialItemGrantFeatures(record,[],items);
 assert.equal(feature.length,1);
 assert.equal(feature[0].name,'Tinker');
 assert.equal(feature[0].origin_key,'subrace|phb|rock');
 const grant=featureItemGrants(record,feature,items).find(row=>row.id==='gnome-rock-tinker');
 assert(grant);
 assert.equal(grant.max_owned,3);
 assert.equal(grant.items.length,3);
 let current=record;
 for(const choice of ['clockwork-toy','clockwork-toy','fire-starter']){
  const live=featureItemGrants(current,feature,items);
  current={...current,...claimFeatureItemPatch(current,{feature_item_grants:live},grant.id,choice)};
 }
 assert.equal(current.inventory.length,3);
 assert.equal(new Set(current.inventory.map(row=>row.id)).size,3);
 assert(current.inventory.every(row=>row.granted_by===feature[0].origin_id));
 assert.throws(()=>claimFeatureItemPatch(current,
  {feature_item_grants:featureItemGrants(current,feature,items)},
  grant.id,'music-box'),/Rimuovi prima/);
 const removed={...current,inventory:current.inventory.slice(1)};
 const replaced={...removed,...claimFeatureItemPatch(removed,
  {feature_item_grants:featureItemGrants(removed,feature,items)},
  grant.id,'clockwork-toy')};
 assert.equal(new Set(replaced.inventory.map(row=>row.id)).size,3,
  'removing and recreating a duplicate must not overwrite an existing item');
 assert.equal(featureItemGrants({...record,subrace:'Forest'},feature,items).length,0);
 assert.equal(featureItemGrants({...record,rules_version:'2024'},feature,items).length,0);
 assert.equal(featureItemGrants({...record,trait_enabled:{[feature[0].key]:false}},
  feature,items).length,0);
});

test('ERLW Spells of the Mark extends class spell lists, never free or prepared grants',()=>{
 const record={...base,species:'Gnome',species_source:'PHB',
  species_id:'5etools:races:phb:gnome',subrace:'Mark of Scribing',subrace_source:'ERLW',
  classes:[{name:'Wizard',source:'PHB',level:5}]};
 const owner=expandedOriginSpellFeatures(record,additional,[]);
 assert.equal(owner.length,1);
 assert.equal(owner[0].origin_key,'subrace|erlw|mark of scribing');
 const expanded=expandedOriginClassSpellIds(record,additional,owner);
 assert.deepEqual([...expanded].sort(),[
  'phb2014_comprehend_languages','phb2014_illusory_script','phb2014_animal_messenger',
  'phb2014_silence','phb2014_sending','phb2014_tongues','phb2014_arcane_eye',
  'phb2014_confusion','phb2014_dream'].sort());
 assert(expanded.includes('phb2014_animal_messenger'));
 assert(expanded.includes('phb2014_dream'));
 const wizard={id:'wizard:phb',name:'Wizard',max_level:3,expanded_spell_ids:expanded};
 const animalMessenger={id:'phb2014_animal_messenger',name:'Animal Messenger',
  source:'PHB',level:2,classes:['Bard','Druid']};
 assert.equal(spellEligible(animalMessenger,wizard),true);
 assert.equal(spellEligible(animalMessenger,{...wizard,expanded_spell_ids:[]}),false);
 assert.deepEqual(castingSources(animalMessenger,[wizard],[animalMessenger]),['wizard:phb']);
 assert.equal(spellEligible({...animalMessenger,level:4},wizard),false);
 assert.equal(expandedOriginClassSpellIds({...record,subrace:'Rock'},additional,owner).length,0);
 assert.equal(expandedOriginClassSpellIds({...record,rules_version:'2024'},additional,owner).length,0);
 assert.equal(expandedOriginClassSpellIds({...record,
  origin_enabled:{[owner[0].origin_id]:false}},additional,owner).length,0);
 const granted=structuredSpellGrants(record,additional,[],owner);
 assert(!granted.grants.some(row=>row.spell_id==='phb2014_animal_messenger'),
  'expanded list spells are never granted as automatic/free casts');
 assert(granted.grants.some(row=>row.spell_id==='phb2014_message'));
});
