import test from 'node:test';
import assert from 'node:assert/strict';
import {calculateSheet} from '../sheet_rules.js';
import {sheetScoreOriginSegments} from '../sheet_roll_origin.js';
import {armorClassBaseFormula} from '../armor_class_formula.js';

const character=inventory=>({kind:'character',rules_version:'2014',level:3,
 abilities:{str:10,dex:14,con:12,int:10,wis:10,cha:10},
 armor_class_base:10,armor_natural_formula:'10 + dex_mod',inventory});
const armor=(type,ac)=>({id:'armor',name:'Armatura',type,ac,quantity:1,equipped_slots:['body']});
const shield={id:'shield',name:'Scudo',type:'S',ac:2,quantity:1,equipped_slots:['off']};

test('CA score and equipment use one base formula for each armor type',()=>{
 for(const record of [character([]),character([armor('MA',14),shield]),
   character([armor('HA',18)]),character([armor('LA',11),shield])]){
  const calculated=calculateSheet(record,{});
  const presentation=armorClassBaseFormula(record,calculated);
  const segments=sheetScoreOriginSegments(record,calculated,'ac');
  assert.equal(segments[0].formula,presentation.formula);
  assert.equal(segments[0].originName,presentation.sourceLabel);
  assert.equal(segments.reduce((sum,row)=>sum+Number(row.value),0),calculated.values.ac);
  assert.doesNotMatch(segments[0].formula,/Armatura, scudo e regole/);
 }
});
test('AC details retain Dexterity cap and equipped shield terms',()=>{
 const medium=character([armor('MA',14),shield]);
 assert.equal(armorClassBaseFormula(medium,calculateSheet(medium,{})).formula,
  '14 + (2 DES, max +2) + 2 scudo');
 const heavy=character([armor('HA',18)]);
 assert.equal(armorClassBaseFormula(heavy,calculateSheet(heavy,{})).formula,'18 (senza DES)');
});
