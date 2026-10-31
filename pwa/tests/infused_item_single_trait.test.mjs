import test from 'node:test';
import assert from 'node:assert/strict';
import {collectTraitRows,stateTraitNavigationKey} from '../trait_projection.js';
import {activeItemOptionEffects} from '../item_controls.js';

const item=id=>({id:'weapon:dagger',instance_id:id,name:'Dagger',type:'M',
 quantity:1,equipped_slots:['main'],option_extensions:[{id:'enhanced',name:'Enhanced Weapon',
 selection_id:'artificer_infusions',description:'Weapon gains a magical bonus.',
 definition:{id:'enhanced',name:'Enhanced Weapon'}}]});
const providers={entries:async category=>category==='items'?
 [{id:'weapon:dagger',name:'Dagger',entries:['Ordinary dagger description']}]:[],
 detail:async(_,row)=>row};
test('an item extension appears in the owning item trait, not a second trait card',async()=>{
 const record={inventory:[item('copy-a')]};
 const traits=await collectTraitRows(record,{features:[]},providers);
 const owned=traits.filter(trait=>trait.category==='oggetti');
 assert.equal(owned.length,1);
 assert.match(String(owned[0].name),/Enhanced Weapon/);
 assert.match(JSON.stringify(owned[0].entries),/magical bonus/);
 assert.equal(owned[0].item_inventory_indices[0],0);
});
test('two physically different extended copies retain distinct trait origins',async()=>{
 const one=item('copy-a'),two=item('copy-b');
 const traits=await collectTraitRows({inventory:[one,two]}, {features:[]},providers);
 const owned=traits.filter(trait=>trait.category==='oggetti');
 assert.equal(owned.length,2);
 assert.notEqual(owned[0].key,owned[1].key);
});
test('option state navigation resolves to the precise extended item',async()=>{
 const sword=item('copy-a'),record={inventory:[sword]};
 const active=activeItemOptionEffects(record);
 const traits=await collectTraitRows(record,{features:[]},providers);
 const key='state|infusion:'+active[0].id;
 assert.equal(stateTraitNavigationKey(key,traits,active),traits.find(t=>t.category==='oggetti').key);
});
