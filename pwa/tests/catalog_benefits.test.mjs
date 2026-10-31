import {test} from 'node:test';
import assert from 'node:assert/strict';
import {catalogBenefitRows,flattenDescription} from '../catalog_data.js';

test('catalog detail shows only structured grants instead of inferring them from lore',()=>{
 const record={name:'Artiglio',description:'Concede immunità ai fulmini secondo la storia.',source:'TST'};
 assert.deepEqual(catalogBenefitRows(record),[]);
 assert.equal(flattenDescription(record),'Concede immunità ai fulmini secondo la storia.');
});

test('catalog benefits include typed proficiencies and resistances',()=>{
 const rows=catalogBenefitRows({
  skillProficiencies:[{athletics:true,perception:true}],
  resist:['cold','fire'],conditionImmune:['poisoned'],
  ability:[{str:2,cha:1}]
 });
 assert.deepEqual(rows,[
  {label:'Competenze',text:'athletics, perception'},
  {label:'Resistenze',text:'cold, fire'},
  {label:'Immunità',text:'poisoned'},
  {label:'Caratteristiche',text:'str +2, cha +1'}
 ]);
});

test('catalog benefits respect freeform structured benefit records',()=>{
 const rows=catalogBenefitRows({benefits:[{name:'Bonus al tiro',description:'+2 ai tiri salvezza'},'Iniziativa migliorata']});
 assert.deepEqual(rows,[
  {label:'Bonus al tiro',text:'+2 ai tiri salvezza'},
  {label:'Beneficio',text:'Iniziativa migliorata'}
 ]);
});
