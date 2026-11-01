import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {traitStateSource,traitStateActions,traitStateEffects} from '../trait_state_rules.js';
import {powerSelectionModels} from '../power_selection.js';

const catalog=JSON.parse(readFileSync(new URL('../catalog/trait_states.json',import.meta.url),'utf8'));
const selections=JSON.parse(readFileSync(new URL('../catalog/power_selections.json',import.meta.url),'utf8'));
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
 const model=selections.selections.find(row=>row.id==='armor_model');
 assert(model);
 assert.equal(Object.hasOwn(model,'title'),false);
 for(const option of model.source.options){
  assert(!('name' in option)&&!('summary' in option)&&!('description' in option),option.id);
 }
});

test('owned 5etools options supply the names and descriptions of state models',()=>{
 const guardian=catalog.states.find(row=>row.id==='armor_model:guardian');
 const source=traitStateSource(guardian,feature,[feature]);
 assert.equal(source.name,'Armor Model · Guardian');
 assert.equal(source.option_name,'Guardian');
 assert.equal(source.description,'Original Guardian text from 5etools.');
 const actions=traitStateActions(owner,[feature],[guardian]);
 assert.equal(actions[0]?.name,'Armor Model · Guardian');
 assert.equal(actions[0]?.description,'Original Guardian text from 5etools.');
 const effects=traitStateEffects(owner,[feature],[guardian]);
 assert.equal(effects[0]?.summary,'Original Guardian text from 5etools.');
 const arcane={...feature,name:'Arcane Armor',origin_id:'feature:arcane-armor'};
 const models=powerSelectionModels(owner,{features:[feature,arcane]},selections);
 const choices=models.find(row=>row.id==='armor_model');
 assert(choices);
 assert.equal(choices.title,'Armor Model');
 assert.deepEqual(choices.options.map(row=>row.name),
  ['Armor Model · Guardian','Armor Model · Infiltrator']);
 assert.deepEqual(choices.options.map(row=>row.description),
  ['Original Guardian text from 5etools.','Original Infiltrator text from 5etools.']);
});

test('nested choice text is also resolved for generic barbarian form IDs',()=>{
 const beast={name:'Form of the Beast',origin_key:'class|tce|barbarian|subclass|beast|tce',
  entries:[{type:'list',items:[{name:'Bite',entry:'Original bite rules.'},
   {name:'Claws',entry:'Original claw rules.'}]}]};
 const result=traitStateSource({id:'barbarian_beast_form:bite',trait:'Form of the Beast'},beast,[beast]);
 assert.equal(result.name,'Form of the Beast · Bite');
 assert.equal(result.description,'Original bite rules.');
});
