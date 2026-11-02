import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {powerSelectionModels,projectSelectionBenefits,powerApplicationPatch} from '../power_selection.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const optionGrants=read('../../vtt/enrichment/benefits/option_grant.json');
const optionLists=read('../../vtt/enrichment/benefits/option_list.json');
const catalog={optionGrants,optionLists};
const rules=optionGrants.entries.filter(entry=>entry.id.startsWith('option_grant:barbarian_2014:'));
const lists=optionLists.entries.filter(entry=>entry.id.startsWith('option_list:barbarian:2014:'));
const beast={name:'Form of the Beast',origin_id:'feature:beast',origin_key:'class|phb|barbarian|subclass|beast|tce',
  class_name:'Barbarian',class_source:'PHB',level:3,
  entries:[{type:'list',items:[{name:'Bite',entry:'Original bite rules from 5eTools.'},
    {name:'Claws',entry:'Original claws rules from 5eTools.'},
    {name:'Tail',entry:'Original tail rules from 5eTools.'}]}]};
const record=()=>({kind:'character',rules_version:'2014',classes:[{name:'Barbarian',source:'PHB',
  level:5,subclass:'Path of the Beast'}],inventory:[]});

test('all 13 subclass options are source-bound and do not duplicate prose',()=>{
 assert.equal(rules.length,3);
 assert.equal(lists.length,3);
 const options=lists.flatMap(row=>row.benefit.option_list.options);
 assert.equal(options.length,13);
 assert.equal(new Set(options.map(x=>x.id)).size,13);
 assert(options.every(option=>!('description' in option)&&!('summary' in option)));
 assert(lists.every(row=>row.granted_by.kind==='5etools'&&row.granted_by.ref.category==='subclass_feature'));
 assert(rules.every(row=>row.benefit.option_grant.source.type==='list_refs'));
});

test('old Beast form survives in-memory migration into native applied options',()=>{
 const saved={...record(),trait_state_selection:{barbarian_beast_form:'barbarian_beast_form:bite'}};
 const model=powerSelectionModels(saved,{features:[beast]},catalog).find(row=>row.id==='barbarian_2014:beast-form');
 assert(model);
 assert.equal(model.options.length,3);
 assert.deepEqual(model.layers.applied.selected,['barbarian_beast_form:bite']);
 assert.equal(model.options[0].name,'Form of the Beast · Bite');
 assert.equal(model.options[0].description,'Original bite rules from 5eTools.');
 const applied=projectSelectionBenefits(saved,{powerSelections:catalog},[beast]);
 assert.equal(applied.selection_traits.length,1);
 assert.equal(applied.attack_grants.length,1);
 assert.equal(applied.attack_grants[0].id,'barbarian:beast:bite');
 assert.equal(applied.attack_grants[0].damage,'1d8');
 assert.equal(applied.attack_grants[0].grants_proficiency,true);
 assert.equal(applied.power_applications['barbarian_2014:beast-form'][0].id,'barbarian_beast_form:bite');
});
test('explicitly clearing a migrated form does not resurrect its legacy selection',()=>{
 const saved={...record(),trait_state_selection:{barbarian_beast_form:'barbarian_beast_form:bite'}};
 const patch=powerApplicationPatch(saved,{features:[beast]},catalog,'barbarian_2014:beast-form','barbarian_beast_form:bite',false,{viaAction:true});
 const changed={...saved,...patch};
 assert.deepEqual(changed.power_applications['barbarian_2014:beast-form'],[]);
 assert.equal(projectSelectionBenefits(changed,{powerSelections:catalog},[beast]).attack_grants.length,0);
});
test('Totem Warrior selections stay independent and require their feature',()=>{
 const aspect={name:'Aspect of the Beast',origin_id:'feature:aspect',origin_key:'class|phb|barbarian',
  class_name:'Barbarian',class_source:'PHB',level:6};
 const attuned={name:'Totemic Attunement',origin_id:'feature:attunement',origin_key:'class|phb|barbarian',
  class_name:'Barbarian',class_source:'PHB',level:14};
 const totem={kind:'character',rules_version:'2014',classes:[{name:'Barbarian',source:'PHB',level:14,subclass:'Totem Warrior'}],
  trait_state_selection:{barbarian_totem_aspect:'barbarian_totem_aspect:elk',
    barbarian_totem_attunement:'barbarian_totem_attunement:wolf'}};
 const models=powerSelectionModels(totem,{features:[aspect,attuned]},catalog);
 assert.equal(models.length,2);
 assert.deepEqual(models.map(model=>model.layers.applied.selected[0]),
   ['barbarian_totem_aspect:elk','barbarian_totem_attunement:wolf']);
 assert(models.every(model=>model.options.length===5));
 assert.equal(powerSelectionModels({...totem,classes:[{...totem.classes[0],subclass:'Berserker'}]},
   {features:[aspect,attuned]},catalog).length,0);
});
