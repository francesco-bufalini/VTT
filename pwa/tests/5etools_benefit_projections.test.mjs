import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {abilityIndexFromBenefits,backgroundStartingFeatsFromBenefits} from '../5etools_benefit_projections.js';
import {withBackgroundGrantedFeats} from '../structured_effects.js';
const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const ability=read('../catalog/ability_grants.json');
const copied=abilityIndexFromBenefits(read('../../vtt/enrichment/benefits/bonus.json'));
test('typed 5eTools ability grants preserve every fixed and weighted choice',()=>{
 for(const kind of ['race','subrace','feat','background']){
  assert.deepEqual(copied[kind],ability[kind],kind);
 }
 const acolyte=copied.background.find(row=>row.name==='Acolyte'&&row.source==='XPHB');
 assert.deepEqual(acolyte.ability_choices[0].choose.weighted.weights,[2,1]);
 assert.deepEqual(acolyte.ability_choices[1].choose.weighted.weights,[1,1,1]);
});
test('typed background starting feats retain all upstream variants and category choices',()=>{
 const source=read('../../vtt/data/compendium_backgrounds_5etools.json').backgrounds;
 const copy=backgroundStartingFeatsFromBenefits(read('../../vtt/enrichment/benefits/feat_grant.json'));
 const expected=Object.fromEntries(Object.entries(source).filter(([,r])=>Array.isArray(r.feats)&&r.feats.length)
  .map(([key,r])=>[key,{name:r.name,source:r.source,feats:r.feats}]));
 assert.deepEqual(copy,expected);
 const output=withBackgroundGrantedFeats({background:'Artisan',background_source:'XPHB',feats_catalog:[]},
  copy,{'crafter|xphb':{name:'Crafter',source:'XPHB'}},[]);
 assert.equal(output.feats_catalog[0]?.name,'Crafter');
});
test('no authored flavour or feat bonuses were changed by the new source snapshot',()=>{
 const bonuses=read('../../vtt/enrichment/benefits/bonus.json').entries;
 const feats=read('../../vtt/enrichment/benefits/feat_grant.json').entries;
 assert.equal(bonuses.filter(e=>e.projection!=='5etools_structured').length,571);
 assert.equal(feats.filter(e=>e.projection!=='5etools_structured').length,2);
});
