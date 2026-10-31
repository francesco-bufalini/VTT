import test from 'node:test';
import assert from 'node:assert/strict';
import {activeItemOptionEffects,itemOptionChargeTrackers,itemOptionChargeTrackerId,
 itemOptionNumericBonuses,requiresAttunement,ownedItemDisplayName,expandedInfusionDefinitions,
 consolidateOwnedItems} from '../item_controls.js';
import {projectItemOptionBenefits} from '../power_selection.js';

const sword=(id='copy-one')=>({id:'weapon:longsword',instance_id:id,name:'Longsword',type:'M',
 quantity:1,active:true,equipped_slots:['main'],attuned:true,attuned_count:1});
const enchantment=(overrides={})=>({id:'enhanced',name:'Enhanced Weapon',selection_id:'artificer_infusions',
 requires_attunement:true,level:10,
 definition:{id:'enhanced',name:'Enhanced Weapon',
  numeric_item_bonuses:{bonus_weapon:1,upgrade_level:10},
  charge_tracker:{max:3,recovery:'dawn'},
  effects:[{type:'bonus',target:'saving_throw',expression:'+1'}]},...overrides});
const equipped=(option=enchantment())=>({...sword(),option_extensions:[option]});
test('the same applied option grants numeric bonuses without a separate infusion field',()=>{
 const item=equipped();
 const record={id:'art',inventory:[item]};
 assert.equal(Object.hasOwn(item,'infusion'),false);
 const active=activeItemOptionEffects(record);
 assert.equal(active.length,1);
 assert.equal(active[0].option.selection_id,'artificer_infusions');
 assert.equal(active[0].id,'item-option:copy-one:enhanced');
 assert.equal(itemOptionNumericBonuses(record,item).bonus_weapon,2);
 assert.equal(projectItemOptionBenefits(record).formula_bonuses[0].expression,'+1');
});
test('unequipped or unattuned copies grant no active effects',()=>{
 const item=equipped();
 assert.equal(activeItemOptionEffects({inventory:[{...item,attuned:false,attuned_count:0}]}).length,0);
 assert.equal(activeItemOptionEffects({inventory:[{...item,equipped_slots:[]}]}).length,0);
 assert.equal(activeItemOptionEffects({inventory:[{...item,active:false}]}).length,0);
});
test('item option charges have one stable ID and remain visible while unequipped',()=>{
 const item=equipped(),id=itemOptionChargeTrackerId(item,item.option_extensions[0]);
 const track=itemOptionChargeTrackers({inventory:[{...item,equipped_slots:[]}]});
 assert.equal(id,'item-option-charges:copy-one:enhanced');
 assert.equal(track.length,1);
 assert.equal(track[0].id,id);
 assert.equal(track[0].max,3);
});
test('option extensions own attunement and display name, not a separate infusion record',()=>{
 const item=equipped();
 assert.equal(requiresAttunement(item),true);
 assert.equal(ownedItemDisplayName(item),'Longsword - Enhanced Weapon');
 assert.equal(requiresAttunement({...item,option_extensions:[],attuned:false}),false);
});
test('differently extended copies never merge into one stack',()=>{
 const rows=consolidateOwnedItems([equipped(),{...sword('copy-two'),option_extensions:[]}]);
 assert.equal(rows.length,2);
});
test('Replicate Magic Item expands only to concrete selections, not the old generic option',()=>{
 const source=[{id:'infusion|tce|replicate magic item',name:'Replicate Magic Item',source:'TCE',
  application_kind:'replicate',replicable_items:[{name:'Bag of Holding',level:2},{name:'Alchemy Jug',level:2}]}];
 const rows=expandedInfusionDefinitions(source);
 assert.equal(rows.length,2);
 assert(rows.every(row=>row.application_kind==='replicate_variant'&&!row.legacy_replicate));
 assert(rows.some(row=>row.name==='Replicate Magic Item · Bag of Holding'));
});
test('an option can add a native action without storing legacy metadata',()=>{
 const record={inventory:[equipped({...enchantment(),definition:{id:'enhanced',
  effects:[{type:'actions',name:'Activate',action_type:'bonus',description:'A bonus action'}]}})]};
 const out=projectItemOptionBenefits(record);
 assert.deepEqual(out.action_grants.map(row=>[row.name,row.action_type]),[['Activate','bonus']]);
});
