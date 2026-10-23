import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet,formulaValue,applicableDiceBonuses,validBonusDice} from '../sheet_rules.js';
import {recoveryPatch,requirementPatch,nativeRows,nativeRowPatch,spellCastPlan} from '../native_sheet.js';
import {sessionSpellEntries} from '../spell_selection.js';
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
test('casting choices preserve class and origin identity; counters and effective casting math are validated before sending',()=>{
 const spell={id:'synthetic',name:'Synthetic spell',level:1,classes:['Wizard'],source:'PHB'};
 const record={...base,name:'Caster',prepared_spells:[spell],origin_spell_grants:[{id:'daily-grant',spell_id:spell.id,origin_id:'custom',origin_name:'Daily',payment_mode:'tracker',tracker_id:'daily',tracker_cost:2,spellcasting_ability:'cha'}],proficiency_origins:[{id:'custom',name:'Custom'}],resource_trackers:[{id:'daily',name:'Daily',max:3}],resource_tracker_spent:{daily:1},formula_bonuses:[{target:'spell_attack',expression:'2'},{target:'spell_dc',expression:'1'}]};
 const calculated=calculateSheet(record,catalogs),entries=sessionSpellEntries(record,calculated,[spell]);
 assert.equal(entries.length,2);assert.equal(entries[1].id,'synthetic');assert.equal(entries[1].grant_id,'daily-grant');
 const origin=spellCastPlan(record,entries[1],0,calculated);
 assert.deepEqual(origin.patch,{resource_tracker_spent:{daily:3}});assert.equal(origin.slotLevel,1);
 assert.equal(origin.context.spell_attack_bonus,8);assert.equal(origin.context.spell_save_dc,15);assert.equal(origin.context.caster_name,'Caster');
 assert.deepEqual(record.resource_tracker_spent,{daily:1},'preparing a cast must not consume resources');
 assert.throws(()=>spellCastPlan({...record,resource_tracker_spent:{daily:2}},entries[1],0,calculated),/insufficiente/);
 const targeted={...entries[0],item_target:{inventory_index:0,item_id:'wand',instance_id:'wand-1'}};
 const targetedPlan=spellCastPlan(record,targeted,0,calculated);
 assert.deepEqual(targetedPlan.context.item_target,targeted.item_target);
 assert.notEqual(targetedPlan.context.item_target,targeted.item_target);
 const regular=spellCastPlan(record,entries[0],0,calculated);assert.equal(regular.patch.spell_slots_spent[1],1);
 assert.throws(()=>spellCastPlan({...record,spell_slots_spent:[0,4]},entries[0],1,calculated),/Nessuno slot/);
});
test('pact casting charges the pact pool and cantrips charge no slots',()=>{
 const spell={id:'pact',name:'Pact spell',level:1,classes:['Warlock'],source:'PHB'},cantrip={id:'cantrip',name:'Cantrip',level:0,classes:['Warlock'],source:'PHB'};
 const record={...base,class:'Warlock',class_source:'PHB',level:5,prepared_spells:[spell,cantrip]};
 const calculated=calculateSheet(record,catalogs),entries=sessionSpellEntries(record,calculated,[spell,cantrip]);
 const plan=spellCastPlan(record,entries[0],0,calculated);assert.equal(plan.slotLevel,3);assert.deepEqual(plan.patch,{pact_slots_spent:1});
 assert.deepEqual(spellCastPlan(record,entries[1],0,calculated).patch,{});
});
