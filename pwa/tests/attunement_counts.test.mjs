import {test} from 'node:test';
import assert from 'node:assert/strict';
import {calculateSheet,applicableDiceBonuses} from '../sheet_rules.js';
import {sheetScoreOriginSegments} from '../sheet_roll_origin.js';
import {initialCreature} from '../character_core.js';
import {itemAttunementCount,inventoryAttunementCounts,changeOwnedItem,changeItemOverride,consolidateOwnedItems} from '../item_controls.js';
import {collectTraitRows} from '../trait_projection.js';
import {traitBenefitGroups} from '../trait_benefits.js';
import {makeCreatureExport,parseCreatureExport} from '../creature_format.js';

const stone=(count=0,extra={})=>({id:'magic_item:stone-of-good-luck',name:'Stone of Good Luck',
 custom_item_type:'magic',quantity:4,req_attune:true,attuned:count>0,attuned_count:count,
 bonus_ability_check:1,bonus_saving_throw:1,...extra});
const creature=inventory=>({...initialCreature('character','Custode','test_attunement','owner_test'),
 abilities:{str:10,dex:14,con:12,int:10,wis:12,cha:10},inventory});

test('legacy attunement means one copy and explicit counts remain bounded by ownership',()=>{
 const legacy=stone(0);delete legacy.attuned_count;legacy.attuned=true;
 const before=structuredClone(legacy);
 assert.equal(itemAttunementCount(legacy),1);
 assert.equal(itemAttunementCount(stone(7)),4);
 assert.equal(itemAttunementCount(stone(3,{quantity:0})),0);
 assert.equal(itemAttunementCount(stone(3,{req_attune:false})),0);
 assert.deepEqual(legacy,before);
 assert.deepEqual(inventoryAttunementCounts([stone(2),stone(3)],3),[2,1]);
});

test('dedicating attunements enforces stack quantity and the shared capacity without mutating input',()=>{
 const inventory=[stone(0),stone(1,{id:'ring',quantity:1})],before=structuredClone(inventory);
 const changed=changeOwnedItem(inventory,0,'attuned_count',2);
 assert.equal(changed[0].attuned_count,2);assert.equal(changed[0].attuned,true);
 assert.throws(()=>changeOwnedItem(inventory,0,'attuned_count',3),/massimo/);
 for(const count of [-1,1.5,5,'',NaN])assert.throws(()=>changeOwnedItem(inventory,0,'attuned_count',count),/Sintonie/);
 assert.equal(changeOwnedItem(inventory,0,'attuned_count',4,{attunementMax:5})[0].attuned_count,4);
 assert.equal(changeOwnedItem(changed,0,'attuned',false)[0].attuned_count,0);
 assert.equal(changeOwnedItem(inventory,0,'attuned',true)[0].attuned_count,1);
 assert.deepEqual(inventory,before);
});

test('reducing quantity releases excess attunements, while increasing it never grants new ones',()=>{
 const smaller=changeOwnedItem([stone(3)],0,'quantity',2);
 assert.equal(smaller[0].attuned_count,2);
 assert.equal(changeOwnedItem(smaller,0,'quantity',4)[0].attuned_count,2);
});

test('four luckstones grant exactly one or three copies of their bonuses according to attunement',()=>{
 const baseline=calculateSheet(creature([]));
 for(const count of [0,1,2,3]){
  const calculated=calculateSheet(creature([stone(count)]));
  assert.equal(calculated.stats.initiative,baseline.stats.initiative+count);
  assert.equal(calculated.skills.perception,baseline.skills.perception+count);
  assert.equal(calculated.stats.passive_perception,baseline.stats.passive_perception+count);
  for(const ability of ['str','dex','con','int','wis','cha'])assert.equal(calculated.saves[ability],baseline.saves[ability]+count);
  assert.equal(calculated.attunements.used,count);
 }
});

test('maximum attunements track the editable base separately from feature bonuses',()=>{
 const record={...creature([stone(4)]),attunement_max_base:4,
  formula_bonuses:[{id:'attunement-extension',target:'attunement_max',expression:'2'}]};
 const calculated=calculateSheet(record);
 assert.equal(calculated.values.attunement_max,6);
 assert.equal(calculated.attunements.maximum,6);
 assert.equal(calculated.attunements.used,4);
 const segments=sheetScoreOriginSegments(record,calculated,'attunement_max');
 assert.equal(segments.find(row=>row.kind==='base')?.value,4);
 assert.equal(segments.reduce((sum,row)=>sum+row.value,0),6);
 assert.equal(calculateSheet({...record,attunement_max_base:0}).values.attunement_max,2);
});
test('external over-allocation cannot exceed capacity and does not rewrite saved inventory',()=>{
 const record=creature([stone(4),stone(1,{id:'ring'})]),before=structuredClone(record);
 const result=calculateSheet(record),baseline=calculateSheet(creature([]));
 assert.equal(result.stats.initiative,baseline.stats.initiative+3);
 assert.deepEqual(result.attunements,{counts:[3,0],used:3,maximum:3});
 assert.deepEqual(record,before);
 const larger=calculateSheet({...record,formula_bonuses:[{id:'extra-attunements',target:'attunement_max',expression:'2'}]});
 assert.equal(larger.attunements.maximum,5);assert.deepEqual(larger.attunements.counts,[4,1]);
});

test('same-ID stacks contribute their own allocated copies, including legacy single attunement',()=>{
 const legacy=stone(1,{instance_id:'second',quantity:2});delete legacy.attuned_count;
 const result=calculateSheet(creature([stone(2),legacy]));
 assert.equal(result.stats.initiative,calculateSheet(creature([])).stats.initiative+3);
 assert.equal(result.attunements.used,3);
});

test('manual item formulas and optional dice follow attuned copies using stable item origins',()=>{
 const record={...creature([stone(3)]),formula_bonuses:[
  {id:'custom-bonus',origin_id:'item:magic_item:stone-of-good-luck',target:'ac',expression:'2'},
  {id:'custom-trait-bonus',origin_id:'feature:trait:item:magic_item:stone-of-good-luck|0|stone of good luck',target:'hp',expression:'2'}],
  dice_bonuses:[{id:'luck-dice',origin_id:'item:magic_item:stone-of-good-luck',target:'ability_check',dice:'2d4+1'}]};
 const result=calculateSheet(record),baseline=calculateSheet(creature([]));
 assert.equal(result.stats.armor_class,baseline.stats.armor_class+6);
 assert.equal(result.stats.max_hp,baseline.stats.max_hp+6);
 assert.equal(applicableDiceBonuses(record,'initiative',[],result)[0].dice,'6d4+3');
 const inactive={...record,inventory:[stone(0)]};
 assert.equal(calculateSheet(inactive).stats.armor_class,baseline.stats.armor_class);
 assert.deepEqual(applicableDiceBonuses(inactive,'initiative'),[]);
});

test('item trait and benefit explanation distinguish owned quantity from active attuned copies',async()=>{
 for(const count of [0,1,3]){
  const record=creature([stone(count)]),calculated=calculateSheet(record);
  const trait=(await collectTraitRows(record,calculated)).find(row=>row.origin_key==='item:magic_item:stone-of-good-luck');
  assert.equal(trait.item_quantity,4);assert.equal(trait.item_active_quantity,count);
  assert.equal(trait.item_requires_attunement,true);assert.equal(trait.inactive,count===0);
  const benefits=traitBenefitGroups(trait,record,calculated);
  if(count===3)assert(benefits.some(group=>group.items.some(row=>row.value.includes('×3'))));
 }
});

test('non-attuning copies retain their quantity multiplier',()=>{
 const inventory=[stone(0,{req_attune:false})],calculated=calculateSheet(creature(inventory));
 assert.equal(calculated.stats.initiative,calculateSheet(creature([])).stats.initiative+4);
});

test('splitting a personalized copy preserves total attunements and prevents stack consolidation',()=>{
 const sword=stone(3,{type:'M',custom_item_type:'weapon',damage:'1d8',quantity:3});
 const split=changeItemOverride([sword],0,'damage','1d10');
 assert.deepEqual(split.map(row=>row.quantity),[2,1]);
 assert.deepEqual(split.map(itemAttunementCount),[2,1]);
 assert.equal(consolidateOwnedItems([stone(1),stone(0)]).length,2);
});

test('portable exports retain the allocated count and legacy boolean',()=>{
 const record=creature([stone(3)]);
 const parsed=parseCreatureExport(JSON.stringify(makeCreatureExport(record)));
 assert.equal(parsed.creature.inventory[0].attuned_count,3);
 assert.equal(parsed.creature.inventory[0].attuned,true);
});
