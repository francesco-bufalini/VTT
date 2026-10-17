import {test} from 'node:test';
import assert from 'node:assert/strict';
import {calculateSheet} from '../sheet_rules.js';
import {hitPointPatch,rowsFor,collectionPatch,nativeRowPatch} from '../native_sheet.js';

test('damage consumes temporary, transformed and normal HP in native order; healing respects effective maximum',()=>{
 const c={temporary_hp:4,second_form_hp:8,current_hp:20,max_hp_base:25,formula_bonuses:[{target:'hp',expression:'5'}]};
 const out=calculateSheet(c);
 assert.deepEqual(hitPointPatch(c,-15,out),{temporary_hp:0,second_form_hp:0,current_hp:17});
 assert.deepEqual(hitPointPatch(c,50,out),{current_hp:30});
 assert.deepEqual(hitPointPatch(c,-100,out),{temporary_hp:0,second_form_hp:0,current_hp:0});
 assert.equal(c.current_hp,20);
 assert.throws(()=>hitPointPatch(c,NaN,out));
});
test('legacy class becomes editable without losing primary class or subclass references',()=>{
 const c={class:'Wizard',class_source:'PHB',class_id:'wizard',subclass:'Evocation',subclass_id:'evocation',level:5};
 const rows=rowsFor(c,'classes');
 assert.equal(rows[0].subclass_id,'evocation');
 rows.push({name:'Fighter',source:'PHB',level:2});
 const patch=collectionPatch(c,'classes',rows);
 assert.equal(patch.level,7);
 assert.equal(patch.class_id,'wizard');
 assert.equal(nativeRowPatch({...c,...patch},'classes',1,'level',3).level,8);
 assert.throws(()=>nativeRowPatch({...c,...patch},'classes',1,'level',19),/20/);
});
test('all sheet readouts expose effective values and native bonus targets, including legacy HP alias',()=>{
 const out=calculateSheet({abilities:{dex:14},max_hp_base:10,formula_bonuses:[
  {target:'ability:dex',expression:'2',origin_name:'Scelta'},
  {target:'skill:stealth',expression:'1'}, {target:'max_hp',expression:'3'}]});
 assert.equal(out.values['ability:dex'],16);
 assert.equal(out.values['ability_mod:dex'],3);
 assert.equal(out.values['skill:stealth'],4);
 assert.equal(out.values.ac,13);
 assert.equal(out.values.initiative,3);
 assert.equal(out.values.hp,13);
 assert.match(out.explanations['ability:dex'],/Scelta.*2/);
});
