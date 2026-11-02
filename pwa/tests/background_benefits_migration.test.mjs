import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {backgroundAbilityIndexFromBenefits,backgroundFeatIndexFromBenefits} from '../background_benefit_catalogs.js';
import {allocationVariants,effectiveAllocations} from '../ability_choice_rules.js';
import {withBackgroundGrantedFeats} from '../structured_effects.js';
import {savePendingChoice} from '../pending_choices.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const source=read('../../vtt/data/structured_ability_grants_5etools.json').background;
const bonusCatalog=read('../../vtt/enrichment/benefits/bonus.json');
const featCatalog=read('../../vtt/enrichment/benefits/feat_grant.json');
const backgrounds=read('../../vtt/data/compendium_backgrounds_5etools.json').backgrounds;
const scores=backgroundAbilityIndexFromBenefits(bonusCatalog);
const feats=backgroundFeatIndexFromBenefits(featCatalog,backgrounds);
const key=row=>row.name.toLowerCase()+'|'+row.source.toLowerCase();

test('all 74 source-qualified background score choices are copied into bonus benefits',()=>{
 assert.equal(scores.length,74);
 assert.deepEqual(new Set(scores.map(key)),new Set(source.map(key)));
 for(const row of source){
  const converted=scores.find(x=>key(x)===key(row));
  assert.deepEqual(converted?.ability_choices,row.ability_choices,key(row));
  assert.equal(allocationVariants(converted.ability_choices).length,2);
 }
 assert.equal(scores.filter(x=>x.source==='PHB').length,0,
  'PHB 2014 backgrounds do not create 2024 ability-score bonuses');
});

test('saved background ability allocations retain +2/+1 and three +1 variants',()=>{
 const acolyte=scores.find(row=>key(row)==='acolyte|xphb');
 const variants=allocationVariants(acolyte.ability_choices);
 const origin='background|xphb|acolyte';
 const first={origin_ability_choices:[{origin_id:origin,variant:0,allocations:[
  {part:0,ability:'int'},{part:1,ability:'wis'}]}]};
 assert.deepEqual(effectiveAllocations(first,origin,variants),[
  {ability:'int',amount:2},{ability:'wis',amount:1}]);
 const second={origin_ability_choices:[{origin_id:origin,variant:1,allocations:[
  {part:0,ability:'int'},{part:1,ability:'wis'},{part:2,ability:'cha'}]}]};
 assert.deepEqual(effectiveAllocations(second,origin,variants),[
  {ability:'int',amount:1},{ability:'wis',amount:1},{ability:'cha',amount:1}]);
 assert.deepEqual(effectiveAllocations({origin_ability_choices:[{
  origin_id:origin,variant:0,allocations:[{part:0,ability:'int'},{part:1,ability:'int'}]
 }]},origin,variants),[],'the 2/1 selection requires distinct abilities');
});

test('all background feat grants use typed entries; non-choice feats remain virtual',()=>{
 const all=featCatalog.entries.filter(e=>e.benefit?.parameters?.background_feat_grant);
 assert.equal(all.length,84);
 assert.equal(all.reduce((n,e)=>n+(e.benefit.grants?.length||0),0),86);
 assert.deepEqual(feats['acolyte|xphb'].feats,[{'magic initiate; cleric|xphb':true}]);
 assert.deepEqual(feats['acolyte|phb'].feats,[]);
 const record={background:'Artisan',background_source:'XPHB',feats_catalog:[]};
 const projected=withBackgroundGrantedFeats(record,feats,{
  'crafter|xphb':{name:'Crafter',source:'XPHB'}});
 assert.equal(projected.feats_catalog[0]?.name,'Crafter');
 assert.deepEqual(record.feats_catalog,[]);
});

test('multiple offered feats are an exclusive choice and do not leak when background changes',()=>{
 for(const name of ['rewarded|bmt','ruined|bmt','haunted one|rhw',
  'investigator|rhw','mist wanderer|rhw','spirit medium|rhw']){
  assert.equal(feats[name].background_feat_choice.count,1);
  assert.deepEqual(feats[name].feats,[]);
 }
 assert.deepEqual(feats['haunted one|rhw'].background_feat_choice.categories,['DG']);
 const origin='background|bmt|rewarded';
 const choice={kind:'background_feat',origin_id:origin,count:1,
  name:'Rewarded',options:['phb|lucky','phb|skilled'],
  option_rows:{'phb|lucky':{name:'Lucky',source:'PHB'},
   'phb|skilled':{name:'Skilled',source:'PHB'}}};
 const chosen=savePendingChoice({feats_catalog:[]},choice,['phb|lucky']);
 assert.equal(chosen.feats_catalog.length,1);
 assert.equal(chosen.feats_catalog[0].granted_by,origin);
 assert.equal(chosen.feats_catalog[0].name,'Lucky');
 const active={background:'Rewarded',background_source:'BMT',feats_catalog:chosen.feats_catalog};
 assert.equal(withBackgroundGrantedFeats(active,feats).feats_catalog.length,1);
 const changed=withBackgroundGrantedFeats({...active,background:'Acolyte',background_source:'PHB'},feats);
 assert.deepEqual(changed.feats_catalog,[]);
 assert.equal(active.feats_catalog.length,1,'previous saved selection stays recoverable');
});
