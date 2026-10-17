import {test} from 'node:test';
import assert from 'node:assert/strict';
import {calculateSheet} from '../sheet_rules.js';
import {hitPointPatch,rowsFor,collectionPatch,nativeRowPatch} from '../native_sheet.js';
import {referencePatch,rowReferencePatch} from '../native_sheet.js';
import {castingClasses,resourceTrackers} from '../sheet_rules.js';
import {slotUsePatch,recoveryPatch} from '../native_sheet.js';
import {addSelectedSpell,removeSelectedSpell} from '../spell_selection.js';
import {readFileSync,existsSync} from 'node:fs';
const mechanics=JSON.parse(readFileSync(new URL('../catalog/class_mechanics.json',import.meta.url),'utf8'));
const catalogs={classMechanics:mechanics};

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
test('native casting tables preserve editions, class ownership, cantrip limits and wizard spellbook',()=>{
 const c={rules_version:'2014',classes:[{name:'Wizard',source:'PHB',level:5},{name:'Warlock',source:'PHB',level:3}],abilities:{int:16,cha:14}};
 const members=castingClasses(c,mechanics,{int:3,cha:2});
 const [wizard,warlock]=members;
 assert.deepEqual([wizard.limit,wizard.cantrips,wizard.max_level,wizard.book],[8,4,3,true]);
 assert.deepEqual([warlock.limit,warlock.max_level],[4,2]);
 const modern=castingClasses({...c,rules_version:'2024',classes:[{name:'Wizard',source:'XPHB',level:5}]},mechanics,{int:5});
 assert.equal(modern[0].limit,9,'2024 uses its table rather than ability + level');
 const spell={id:'spell:shield|phb',name:'Shield',source:'PHB',level:1,classes:['Wizard','Warlock']};
 const options={member:wizard,classes:members,catalog:[spell]};
 assert.throws(()=>addSelectedSpell(c,spell,'prepared_spells',options),/libro/);
 const book=addSelectedSpell(c,spell,'spellbook_spells',options);
 const prepared=addSelectedSpell({...c,...book},spell,'prepared_spells',options);
 assert.deepEqual(prepared.prepared_spells[0].casting_classes,[wizard.id]);
 const shared=addSelectedSpell({...c,...prepared},spell,'prepared_spells',{...options,member:warlock});
 assert.deepEqual(shared.prepared_spells[0].casting_classes,[wizard.id,warlock.id]);
 const removed=removeSelectedSpell({...c,...shared},'prepared_spells',0,{classId:warlock.id,classes:members,catalog:[spell]});
 assert.deepEqual(removed.prepared_spells[0].casting_classes,[wizard.id]);
 assert.equal(shared.prepared_spells[0].casting_classes.length,2,'input never mutated');
});
test('slot counters distinguish class/pact, keep manual totals and recover without changing spell selections',()=>{
 const c={class:'Wizard',level:5,classes:[{name:'Wizard',level:5},{name:'Warlock',level:3}],spell_slots_spent:[0,1],pact_slots_spent:1,prepared_spells:[{id:'keep'}]};
 const out=calculateSheet(c,catalogs);
 assert.equal(out.spell_slots[0].total,4);
 assert.equal(out.pact_slots.total,2);
 assert.equal(slotUsePatch(c,1,1,out).spell_slots_spent[1],2);
 assert.deepEqual(slotUsePatch(c,0,-1,out),{pact_slots_spent:0});
 assert.throws(()=>slotUsePatch({...c,pact_slots_spent:2},0,1,out),/Nessuno/);
 assert.deepEqual(c.prepared_spells,[{id:'keep'}]);
 const manual=calculateSheet({...c,spell_slots_manual:true,spell_slots_total:[0,7],pact_slots_total:4,formula_bonuses:[{target:'slot:1',expression:'2'}]},catalogs);
 assert.equal(manual.spell_slots[0].base,7);
 assert.equal(manual.spell_slots[0].total,9);
 assert.equal(manual.pact_slots.total,4);
});
test('resources use native IDs, formulas, subclass gating and explicit rest recovery',()=>{
 const c={class:'Bard',class_source:'PHB',level:5,abilities:{cha:16},resource_trackers:[{id:'custom',name:'Personal',max:1,max_formula:'proficiency + 1',recharge:'manual'}],resource_tracker_spent:{'class:bard:phb:bardic_inspiration':2,custom:1,unknown:4}};
 const out=calculateSheet(c,catalogs);
 const inspiration=out.trackers.find(t=>t.id==='class:bard:phb:bardic_inspiration');
 assert.ok(inspiration);
 assert.equal(inspiration.max,3);
 assert.equal(inspiration.recharge,'short_rest');
 assert.equal(out.trackers.find(t=>t.id==='custom').max,4);
 assert.deepEqual(recoveryPatch(c,'short_rest',out.trackers).resource_tracker_spent,{custom:1,unknown:4});
 const monk=resourceTrackers({class:'Monk',class_source:'PHB',level:6,subclass:'Way of Shadow'},mechanics);
 assert.equal(monk.some(t=>t.name==='Wholeness of Body'),false);
 const monster=resourceTrackers({kind:'monster',stat_block:{legendaryActions:3,action:[{name:'Breath {@recharge 5}'}]}},mechanics);
 assert.deepEqual(monster.map(t=>[t.id,t.max,t.recharge]),[['legendary_actions',3,'turn'],['recharge:action:0',1,'d6']]);
});
test('species speeds resolve from native identity, replacing stale snapshots and keeping explicit special overrides',()=>{
 const out=calculateSheet({kind:'character',species:'Aarakocra',species_source:'EEPC',speed_base:99,species_speed:{walk:99},movement_speeds:{swim:15}},catalogs);
 assert.equal(out.stats.speeds.walk,25);
 assert.equal(out.stats.speeds.fly,50);
 assert.equal(out.stats.speeds.swim,15);
});
test('equipped attacks calculate proficiency, finesse, offhand damage, thrown range and native enhancement IDs',()=>{
 const weapon={id:'shortsword',name:'Shortsword',type:'M',weapon_category:'martial',damage:'1d6',properties:['F','L'],quantity:2,equipped_slots:['main','off']};
 const c={kind:'character',level:5,class:'Fighter',abilities:{str:12,dex:18},attack_ability:'dex',inventory:[weapon],proficiency_choices:[{kind:'weapon',key:'martial'}],formula_bonuses:[{target:'attack_hit:item:shortsword',expression:'1'}]};
 const out=calculateSheet(c,catalogs);
 assert.deepEqual(out.attacks.map(a=>[a.id,a.hit,a.damage]),[['item:shortsword',8,'1d6 + 4'],['item:off:shortsword',7,'1d6']]);
 assert.equal(out.attacks[1].offhand_bonus,true);
 const style=calculateSheet({...c,two_weapon_fighting:true},catalogs);
 assert.equal(style.attacks[1].damage,'1d6 + 4');
 const thrown=calculateSheet({...c,inventory:[{...weapon,id:'dagger',properties:['F','L','T'],range:'20/60',equipped_slots:['main']}]},catalogs);
 assert.deepEqual(thrown.attacks.map(a=>[a.id,a.range_feet,a.long_range_feet]),[['item:dagger',5,0],['item:throw:main:dagger',20,60]]);
 const monster=calculateSheet({kind:'monster',abilities:{str:20},stat_block:{action:[{name:'Bite',entries:['{@atk mw} {@hit 7} reach 10 ft. {@damage 2d6 + 5} damage.']}]}},catalogs);
 assert.equal(monster.attacks[0].hit,7);
 assert.equal(monster.attacks[0].damage,'2d6 + 5');
});
test('class and subclass catalog edits keep legacy fields and multi-class IDs coherent',()=>{
 const c={class:'Wizard',class_id:'old',class_source:'PHB',subclass:'Evoker',subclass_source:'PHB',subclass_id:'oldsub',level:5,
  classes:[{id:'old',name:'Wizard',source:'PHB',level:5,subclass:'Evoker',subclass_source:'PHB',subclass_id:'oldsub'}]};
 const patch=referencePatch(c,'class',{id:'new',name:'Wizard',source:'XPHB'});
 assert.deepEqual([patch.class_id,patch.class_source,patch.classes[0].id,patch.classes[0].source],['new','XPHB','new','XPHB']);
 assert.equal(patch.subclass,'');assert.equal(patch.classes[0].subclass_id,'');
 const row=rowReferencePatch(c,'classes',0,'subclass',{name:'Abjurer',source:'XPHB',id:'abjurer'});
 assert.equal(row.subclass_id,'abjurer');assert.equal(row.classes[0].subclass_source,'XPHB');
 assert.equal(c.subclass_id,'oldsub');
});
test('manual origin powers follow origin toggles and automatic bonus switches keep native IDs',()=>{
 const id='custom_origin';
 const c={kind:'character',level:3,proficiency_origins:[{id,name:'Chosen',disabled:false}],origin_spell_grants:[{id:'grant',origin_id:id,spell_id:'shield',payment_mode:'free'},{id:'duplicate',origin_id:id,spell_id:'shield'}]};
 assert.equal(calculateSheet(c,catalogs).origin_spells.length,1,'duplicate origin/spell pairs are projected once');
 assert.equal(calculateSheet({...c,origin_enabled:{[id]:false}},catalogs).origin_spells.length,0);
 assert.equal(c.origin_spell_grants.length,2,'projection never rewrites imported rows');
});
test('bundled PWA native tables and resource definitions are generated without divergence',t=>{
 const nativePath=new URL('../../vtt/data/class_mechanics_5etools.json',import.meta.url);
 const overridesPath=new URL('../../vtt/data/class_resource_overrides.json',import.meta.url);
 if(!existsSync(nativePath)||!existsSync(overridesPath))
   return t.skip('Source comparison requires full checkout; browser-assets checks out only pwa/.');
 const native=JSON.parse(readFileSync(nativePath,'utf8'));
 const overrides=JSON.parse(readFileSync(overridesPath,'utf8'));
 assert.deepEqual(mechanics.classes,native.classes);
 assert.deepEqual(mechanics.resource_overrides,overrides.classes);
});
