import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {withBackgroundGrantedFeats} from '../structured_effects.js';

const all=JSON.parse(readFileSync(
 new URL('../../vtt/data/compendium_backgrounds_5etools.json',import.meta.url),'utf8')).backgrounds;
const spellRules=[{kind:'feat',name:'Magic Initiate',source:'XPHB',
 blocks:[{name:'Cleric Spells'},{name:'Druid Spells'},{name:'Wizard Spells'}]}];
const featDetails={
 'magic initiate|xphb':{name:'Magic Initiate',source:'XPHB'},
 'crafter|xphb':{name:'Crafter',source:'XPHB'}
};

test('source-qualified background feats are transient and resolve 2024 spell variants',()=>{
 const record={background:'Acolyte',background_source:'XPHB',feats_catalog:[]};
 const projection=withBackgroundGrantedFeats(record,all,featDetails,spellRules);
 assert.equal(projection.feats_catalog.length,1);
 assert.equal(projection.feats_catalog[0].name,'Magic Initiate');
 assert.equal(projection.feats_catalog[0].source,'XPHB');
 assert.equal(projection.feats_catalog[0].spell_variant,'Cleric Spells');
 assert.equal(projection.feats_catalog[0].granted_by,'background|xphb|acolyte');
 assert.deepEqual(record.feats_catalog,[],'saved creature must be unchanged');
 assert.deepEqual(withBackgroundGrantedFeats({...record,background_source:'PHB'},all,featDetails,spellRules).feats_catalog,[]);
});

test('background switch removes source-owned virtual feats and keeps manual ones',()=>{
 const manual={name:'Lucky',source:'PHB',id:'feat:manual'};
 const source={background:'Artisan',background_source:'XPHB',feats_catalog:[manual]};
 const projected=withBackgroundGrantedFeats(source,all,featDetails,spellRules);
 assert.deepEqual(projected.feats_catalog.map(x=>x.name),['Lucky','Crafter']);
 assert.deepEqual(withBackgroundGrantedFeats({...source,background:'Acolyte',background_source:'PHB'},
  all,featDetails,spellRules).feats_catalog,[manual]);
 assert.deepEqual(withBackgroundGrantedFeats({...source,origin_enabled:{'background|xphb|artisan':false}},
  all,featDetails,spellRules).feats_catalog,[manual]);
});

test('already-owned feat is not applied twice and unresolved choices are not guessed',()=>{
 const owned={name:'Crafter',source:'XPHB',id:'owned'};
 const rec={background:'Artisan',background_source:'XPHB',feats_catalog:[owned]};
 assert.equal(withBackgroundGrantedFeats(rec,all,featDetails,spellRules),rec);
 const custom={'haunted one|rhw':{name:'Haunted One',source:'RHW',
  feats:[{anyFromCategory:{category:['DG']}}]}};
 const result=withBackgroundGrantedFeats(
  {background:'Haunted One',background_source:'RHW',feats_catalog:[]},custom,{},[]);
 assert.equal(result.feats_catalog.length,0);
});

test('canonical background mirror holds upstream feat fields, not inferred prose',()=>{
 const acolyte=all['acolyte|xphb'],old=all['acolyte|phb'];
 assert.deepEqual(acolyte.feats,[{'magic initiate; cleric|xphb':true}]);
 assert.equal(old.feats,undefined);
 assert.deepEqual(all['artisan|xphb'].feats,[{'crafter|xphb':true}]);
});
