import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet,formulaValue,applicableDiceBonuses,validBonusDice} from '../sheet_rules.js';
import {recoveryPatch,requirementPatch,nativeRows,nativeRowPatch} from '../native_sheet.js';
const load=name=>JSON.parse(readFileSync(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const catalogs={classMechanics:load('class_mechanics'),abilityGrants:load('ability_grants'),proficiencyGrants:load('proficiency_grants')};
const base={kind:'character',level:8,class:'Wizard',class_source:'PHB',abilities:{str:10,dex:14,con:12,int:16,wis:10,cha:16}};

test('tracker formulas, additive bonuses and requirement toggles preserve stable saved consumption',()=>{
 const record={...base,resource_trackers:[{id:'focus',name:'Focus',max:9,max_formula:'1 + cha_mod',recharge:'short_rest',requirements:{scope:'class',class_name:'Wizard',class_source:'PHB',min_level:8}}],resource_tracker_spent:{focus:6,unrelated:3},formula_bonuses:[{id:'bonus',target:'tracker:focus',expression:'proficiency / 2'}]};
 const out=calculateSheet(record,catalogs),focus=out.trackers.find(t=>t.id==='focus');assert.equal(focus.max,6);assert.equal(focus.spent,6);
 assert.equal(formulaValue('level + cha_mod',out),11);
 assert.equal(calculateSheet({...record,level:7},catalogs).trackers.some(t=>t.id==='focus'),false);
 assert.deepEqual(record.resource_tracker_spent,{focus:6,unrelated:3});
 assert.deepEqual(recoveryPatch(record,'short_rest',out.trackers).resource_tracker_spent,{unrelated:3});
});
test('invalid tracker formulas use the native base fallback and report the reason',()=>{
 const out=calculateSheet({...base,resource_trackers:[{id:'bad',name:'Draft',max:7,max_formula:'unknown + 1'}]},catalogs);
 assert.equal(out.trackers.find(t=>t.id==='bad').max,7);assert.match(out.warnings.join(' '),/Formula tracker Draft.*sconosciuta/);
 assert.throws(()=>formulaValue('round(cha_mod)',out));
});
test('all cyclic grants are rejected consistently while independent additive bonuses survive',()=>{
 const out=calculateSheet({...base,formula_bonuses:[{target:'ability:dex',expression:'initiative'},{target:'initiative',expression:'dex_mod'},{target:'initiative',expression:'2'}]},catalogs);
 assert.equal(out.abilities.dex.score,14);assert.equal(out.stats.initiative,4);
 assert.ok(out.warnings.filter(w=>/circolare/.test(w)).length>=2);
});
test('requirements editors preserve unknown metadata and dormant bonus rows',()=>{
 const row={requirements:{scope:'class',class_name:'Wizard',min_level:5,max_level:12,custom:'keep'}};
 assert.deepEqual(requirementPatch(row,'max_level',''),{scope:'class',class_name:'Wizard',min_level:5,custom:'keep'});
 assert.throws(()=>requirementPatch(row,'max_level','4'),/inferiore/);
 const record={formula_bonuses:[{id:'retained',target:'tracker:hidden',expression:'cha_mod',origin_id:'old',disabled:true,...row,extension:'keep'}]};
 assert.match(nativeRows(record,'formula_bonuses',{origins:[],trackers:[]}),/tracker:hidden/);
 assert.equal(nativeRowPatch(record,'formula_bonuses',0,'expression','1 + cha_mod').formula_bonuses[0].extension,'keep');
});
test('dice grants stay independent of numeric bonuses and match native roll scopes',()=>{
 const record={...base,dice_bonuses:[{id:'bless',target:'saving_throw',dice:'1d4'},{id:'all',target:'any_d20',dice:'1d6'},{id:'damage',target:'damage_roll',dice:'2d6'},{id:'disabled',target:'saving_throw',dice:'1d4',disabled:true},{id:'bad',target:'saving_throw',dice:'200d6'}]};
 assert.deepEqual(applicableDiceBonuses(record,'save:dex').map(r=>r.id),['bless','all']);
 assert.deepEqual(applicableDiceBonuses(record,'attack_damage:item:x').map(r=>r.id),['damage']);
 assert.deepEqual(applicableDiceBonuses(record,'casting_hit:int').map(r=>r.id),['all']);
 assert.equal(validBonusDice('100d100-2'),true);assert.equal(validBonusDice('1d3'),false);
 assert.equal(calculateSheet(record,catalogs).saves.dex,2);
});
test('formal recharge wins over monster supplements and ambiguous names get no guessed counters',()=>{
 const catalog={monster_resources:[{name:'Synthetic',source:'MM',resources:[{section:'action',name:'Breath',max:3,recharge:'long_rest'}]}]};
 const monster={...base,kind:'monster',class:'',stat_block:{name:'Synthetic',source:'MM',action:[{name:'Breath {@recharge 5}'}]}};
 assert.deepEqual(calculateSheet(monster,{...catalogs,classMechanics:catalog}).trackers.map(t=>[t.id,t.max,t.recharge]),[['recharge:action:0',1,'d6']]);
 monster.stat_block.action=[{name:'Breath'},{name:'Breath'}];assert.equal(calculateSheet(monster,{...catalogs,classMechanics:catalog}).trackers.length,0);
});
