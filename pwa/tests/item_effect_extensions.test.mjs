import test from 'node:test';
import assert from 'node:assert/strict';
import {collectEffectExtensions,effectExtensionsFor,applyEffectExtensions} from '../effect_extensions.js';

const option={id:'arcane-armor',name:'Arcane Armor',selection_id:'arcane_armor',
 effect_choice:{element:'fire'},
 definition:{id:'arcane-armor',name:'Arcane Armor',effect_extensions:[
  {id:'arcane-grant',target_kind:'item',operation:'grant_property',value:'',
   trigger:'passive',description:'Armor becomes impossible to remove by force'},
  {id:'arcane-resistance',target_kind:'item',operation:'resistance',value:'fire',
   trigger:'passive',description:'Resistance to fire'}
 ]}};
const armor=(id='body-1')=>({id:'armor:chain_mail',instance_id:id,name:'Chain Mail',
 type:'HA',quantity:1,equipped_slots:['body'],option_extensions:[option]});
test('an applied option projects typed effect extensions to exactly one item instance',()=>{
 const record={inventory:[armor(),armor('body-2')]};
 const rows=collectEffectExtensions(record);
 assert.equal(rows.length,4);
 assert.equal(effectExtensionsFor(rows,{kind:'item',id:'armor:chain_mail',instance_id:'body-1',inventory_index:0}).length,2);
 assert.equal(effectExtensionsFor(rows,{kind:'item',id:'armor:chain_mail',instance_id:'body-2',inventory_index:1}).length,2);
 assert(rows.every(row=>row.origin_name==='Oggetto · Arcane Armor'));
});
test('removing an option removes the effects without a legacy infusion cleanup',()=>{
 const equipped=armor();
 const before=collectEffectExtensions({inventory:[equipped]});
 assert.equal(before.length,2);
 const after=collectEffectExtensions({inventory:[{...equipped,option_extensions:[]}]});
 assert.deepEqual(after,[]);
});
test('effects do not activate from unequipped or disabled armor',()=>{
 const equipped=armor();
 assert.deepEqual(collectEffectExtensions({inventory:[{...equipped,equipped_slots:[]}]}),[]);
 assert.deepEqual(collectEffectExtensions({inventory:[{...equipped,disabled:true}]}),[]);
});

test('Resistant Armor stores an independent damage type on each infused copy',()=>{
 const effect={id:'resistant-armor',owner:{kind:'infusion',id:'infusion|tce|resistant armor'},
  target_kind:'item',operation:'resistance',trigger:'passive',value_from_item_choice:'damage_type'};
 const withChoice=(instance,damage)=>({...armor(instance),option_extensions:[{
  id:'optional:tce:resistant-armor',name:'Resistant Armor',selection_id:'artificer_infusions',
  effect_choice:{damage_type:damage},definition:{id:'infusion|tce|resistant armor',effect_extensions:[effect]}
 }]});
 const fire=withChoice('copy-fire','fire'),cold=withChoice('copy-cold','cold');
 const grants=collectEffectExtensions({inventory:[fire,cold]});
 assert.deepEqual(grants.map(x=>x.value),['fire','cold']);
 assert.equal(effectExtensionsFor(grants,{kind:'item',id:fire.id,instance_id:'copy-fire',inventory_index:0})[0].value,'fire');
 assert.equal(effectExtensionsFor(grants,{kind:'item',id:cold.id,instance_id:'copy-cold',inventory_index:1})[0].value,'cold');
 assert.equal(collectEffectExtensions({inventory:[{...fire,option_extensions:[]},cold]}).length,1);
});
