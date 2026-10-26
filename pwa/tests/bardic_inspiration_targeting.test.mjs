import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import {calculateSheet} from '../sheet_rules.js';
import {abilitiesForCreature} from '../activated_abilities.js';
import {battleActionPanels} from '../action_economy.js';
import {battleResourcePowers,mountPlaySheet} from '../sheet_rules_view.js';
import {TacticalViewer} from '../tactical_view.js';

const json=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const catalogs={
 classMechanics:json('../catalog/class_mechanics.json'),
 classFeatures:json('../catalog/classes.json'),
 abilityGrants:json('../catalog/ability_grants.json'),
 proficiencyGrants:json('../catalog/proficiency_grants.json'),
 featureRules:json('../../vtt/data/feature_timing_recovery_rules.json')
};
const bard=edition=>({
 id:'bard-'+edition,name:'Bardo',kind:'character',rules_version:edition==='PHB'?'2014':'2024',
 class:'Bard',class_source:edition,level:6,
 classes:[{name:'Bard',source:edition,level:6}],
 abilities:{str:10,dex:14,con:12,int:10,wis:10,cha:18},
 current_hp:28,max_hp_base:28,resource_tracker_spent:{}
});

for(const edition of ['PHB','XPHB']){
 test('Bardic Inspiration '+edition+' is a targeted bonus action',()=>{
  const creature=bard(edition),calculated=calculateSheet(creature,catalogs);
  const bardic=abilitiesForCreature(creature,[],calculated).find(row=>row.id==='vtt_bardic_inspiration');
  assert(bardic,'Native Bardic Inspiration must be available');
  assert.equal(bardic.action_type,'bonus');
  assert.equal(bardic.activation_mode,'bonus');
  assert.equal(bardic.target_mode,'single_token');
  assert.equal(bardic.target_range_feet,60);
  assert.equal(bardic.exclude_self,true);
  assert.equal(bardic.resource_cost,1);
  assert(bardic.tracker_id);
  const panels=battleActionPanels(creature,calculated,[],[],[],[],[bardic]);
  assert(panels.abilityEntries.some(row=>row.name==='Bardic Inspiration'&&row.time==='bonus'));
  const resource=battleResourcePowers(calculated,panels.abilityEntries,[bardic])
   .find(row=>row.name==='Bardic Inspiration');
  assert(resource);
  assert.equal(resource.timing,'bonus');
  assert.equal(resource.cost,1);
  const dom=new JSDOM('<main id="app"><div data-local-sheet-calculations></div></main>');
  const previous=globalThis.document;
  try{
   globalThis.document=dom.window.document;
   const app=dom.window.document.querySelector('#app');
   mountPlaySheet(app,{creature,calculated,sheet:'battle',
    view:{battleActions:panels,battleAbilities:[bardic]},icon:()=>''});
   const row=[...app.querySelectorAll('.play-resource-power-row')].find(node=>
    node.textContent.includes('Bardic Inspiration'));
   assert(row);
   assert.match(row.textContent,/Azione bonus/);
   assert(row.querySelector('[data-act="battle-use-ability"]'));
  }finally{globalThis.document=previous;dom.window.close();}
 });
}

test('Token selection rejects caster and blanks without making API calls or spending resources',async()=>{
 const picked=[];
 const viewer=new TacticalViewer({send:async()=>{throw Error('Must not invoke spell commands');},
  ownerId:async()=>'owner',notify:()=>{}});
 viewer.root={querySelectorAll:()=>[],querySelector:()=>null};
 viewer.setStatus=()=>{};viewer.updateButtons=()=>{};viewer.draw=()=>{};
 viewer.tokenId='caster';
 viewer.targeting={};
 viewer.snapshot={markers:[
  {id:'caster',name:'Bardo',x:10,y:10,radius:5},
  {id:'ally',name:'Alleata',x:50,y:40,radius:5}
 ]};
 viewer.setAbilityTarget({name:'Bardic Inspiration',range_feet:60,exclude_self:true,
  onSelected:async token=>picked.push(token)});
 await viewer.tap([10,10]);
 assert.equal(picked.length,0);
 await viewer.tap([200,200]);
 assert.equal(picked.length,0);
 viewer.close=()=>{viewer.root=null;viewer.abilityTarget=null;};
 await viewer.tap([50,40]);
 assert.deepEqual(picked,[{id:'ally',name:'Alleata'}]);
 assert.equal(viewer.abilityTarget,null);
});
