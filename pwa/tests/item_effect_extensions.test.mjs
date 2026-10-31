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
