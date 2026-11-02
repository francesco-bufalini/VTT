import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {traitStateSource,traitStateActions,traitStateEffects} from '../trait_state_rules.js';
import {powerSelectionModels} from '../power_selection.js';

const catalog=JSON.parse(readFileSync(new URL('../catalog/trait_states.json',import.meta.url),'utf8'));
const selections=JSON.parse(readFileSync(new URL('../../vtt/enrichment/benefits/option_grant.json',import.meta.url),'utf8'));
const feature={name:'Armor Model',class_name:'Artificer',class_source:'TCE',
 origin_key:'class|tce|artificer|subclass|armorer|tce',origin_id:'feature:armor-model',
 entries:[{type:'list',items:[
  {name:'Guardian',entry:'Original Guardian text from 5etools.'},
  {name:'Infiltrator',entry:'Original Infiltrator text from 5etools.'}
 ]}]};
const owner={classes:[{name:'Artificer',source:'TCE',level:8,subclass:'Armorer'}],
 inventory:[{id:'armor',quantity:1,type:'HA',equipped_slots:['body']}],
 power_applications:{arcane_armor:[{id:'arcane_armor',target_item_id:'armor'}]},
 trait_state_selection:{armor_model:'armor_model:guardian'}};

test('structured model options do not own replacement titles or summaries',()=>{
 for(const state of catalog.states){
  assert.equal(Object.hasOwn(state,'name'),false,state.id);
  assert.equal(Object.hasOwn(state,'summary'),false,state.id);
 }
 const model=selections.entries.map(row=>row.benefit?.option_grant).find(row=>row?.id==='armor_model');
 assert(model);
 assert.equal(Object.hasOwn(model,'title'),false);
 assert.equal(model.source.type,'list_refs');
 assert.deepEqual(model.source.list_ids,['local:armor_model:guardian','local:armor_model:infiltrator']);
 assert(!Object.hasOwn(model.source,'options'),'Descriptions must come from the referenced capability rather than duplicated inline options');
});

test('locally declared Armor Model abilities use one canonical list without replacement summaries',()=>{
 const lists=JSON.parse(readFileSync(new URL('../../vtt/enrichment/benefits/option_list.json',import.meta.url),'utf8'));
 const models=lists.entries.filter(entry=>entry.id.startsWith('option_list:local:armor_model:'));
 assert.deepEqual(models.map(entry=>entry.benefit.option_list.name),['Guardian','Infiltrator']);
 for(const entry of models){
  const option=entry.benefit.option_list.options[0];
  assert.equal(option.local,true);
  assert(!Object.hasOwn(option,'summary'));
  assert(option.effects.some(effect=>effect.type==='attack'));
  assert(!option.effects.some(effect=>effect.type==='state_selection'));
 }
});
test('nested choice text is also resolved for generic barbarian form IDs',()=>{
 const beast={name:'Form of the Beast',origin_key:'class|tce|barbarian|subclass|beast|tce',
  entries:[{type:'list',items:[{name:'Bite',entry:'Original bite rules.'},
   {name:'Claws',entry:'Original claw rules.'}]}]};
 const result=traitStateSource({id:'barbarian_beast_form:bite',trait:'Form of the Beast'},beast,[beast]);
 assert.equal(result.name,'Form of the Beast · Bite');
 assert.equal(result.description,'Original bite rules.');
});
