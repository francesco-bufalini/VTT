import {resolveVariant,applyVariantEdit,variantDamage} from '../creature_variants.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {classFeatureEntries,classFeatureActivationPatch,classFeatureRollAdvantage,
 classFeatureActive,wildShapePatch,endWildShapePatch,metamagicPlan} from '../feature_mechanics.js';
import {spellCastPlan,recoveryPatch,hitPointPatch} from '../native_sheet.js';
import {rollSheetDice,sheetRollFormula} from '../sheet_rules_view.js';
import {actionEntries} from '../action_economy.js';
const read=name=>JSON.parse(readFileSync(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const catalogs={classMechanics:read('class_mechanics'),classFeatures:read('classes'),
 spellcastingBenefits:read('spellcasting_benefits'),
 abilityGrants:read('ability_grants'),proficiencyGrants:read('proficiency_grants'),
 featureRules:JSON.parse(readFileSync(new URL('../../vtt/data/feature_timing_recovery_rules.json',import.meta.url),'utf8'))};
const sheet=(name,level=5,edition='2014')=>({kind:'character',rules_version:edition,class:name,
 class_source:edition==='2024'?'XPHB':'PHB',level,classes:[{name,level,source:edition==='2024'?'XPHB':'PHB'}],
 abilities:{str:18,dex:16,con:14,int:16,wis:16,cha:18},inventory:[],max_hp_base:50,current_hp:10,
 spell_slots_automatic:true,spell_slots_spent:Array(10).fill(0),resource_tracker_spent:{}});
const apply=(record,key,options={})=>({...record,...classFeatureActivationPatch(record,calculateSheet(record,catalogs),key,options)});
test('Rage applies damage, advantage and defenses, cancels concentration and blocks spellcasting',()=>{
 for(const edition of ['2014','2024']){
  const c={...sheet('Barbarian',9,edition),conditions:['concentrating','poisoned'],concentrating_spell_id:'light',
   inventory:[{id:'axe',name:'Axe',type:'M',custom_item_type:'weapon',damage:'1d6',properties:['T'],range:'20/60',quantity:1,equipped_slots:['main']}]};
  const before=structuredClone(c),base=calculateSheet(c,catalogs),active=apply(c,'rage'),out=calculateSheet(active,catalogs);
  assert.deepEqual(c,before,'activation is a plan, never mutates the record');
  assert.equal(active.conditions.includes('concentrating'),false);assert.equal(active.concentrating_spell_id,'');
  assert(active.conditions.includes('poisoned'));
  assert.equal(out.attacks.find(a=>a.id==='item:axe').damage,'1d6 + 7');
  assert.equal(out.attacks.find(a=>a.id==='item:throw:main:axe').feature_damage,edition==='2024'?3:0);
  assert.deepEqual(out.feature_damage_resistances,['bludgeoning','piercing','slashing']);
  assert(classFeatureRollAdvantage(active,out,'save:str'));
  assert(!classFeatureRollAdvantage(active,out,'skill:athletics'),
   'Poisoned cancels the advantage granted by Rage on Strength checks');
  assert(!classFeatureRollAdvantage(active,out,'save:dex'));
  assert.throws(()=>spellCastPlan(active,{id:'light',level:0},0,out),/Ira/);
  const trait=out.features.find(f=>f.name==='Rage');
  assert.equal(out.active_feature_effects[0].origin_id,trait.origin_id);
  const off=apply(active,'rage'),reverted=calculateSheet(off,catalogs);
  assert.equal(reverted.attacks[0].damage,base.attacks[0].damage);
  assert.equal(Object.values(off.resource_tracker_spent)[0],1,'deactivation cannot refund or charge');
  const disabled={...active,origin_enabled:{[trait.origin_id]:false}};
  assert.equal(calculateSheet(disabled,catalogs).attacks[0].feature_damage,0);
  assert(!classFeatureActive(disabled,calculateSheet(disabled,catalogs),'rage'));
 }
});
test('Rage suppressed by equipment or incapacitation; stale/missing resources never charge',()=>{
 const c=sheet('Barbarian',3),active=apply(c,'rage');
 const armor={id:'plate',type:'HA',custom_item_type:'armor',quantity:1,equipped_slots:['body']};
 assert.throws(()=>apply({...c,inventory:[armor]},'rage'),/armatura/);
 assert(!classFeatureActive({...active,inventory:[armor]},calculateSheet(active,catalogs),'rage'));
 assert.throws(()=>apply({...c,conditions:['unconscious']},'rage'),/incapacità/);
 assert.throws(()=>classFeatureActivationPatch(c,{features:[],trackers:[]},'rage'),/disponibile/);
 const out=calculateSheet(c,catalogs),tracker=out.trackers.find(t=>t.name==='Rages');
 assert.throws(()=>apply({...c,resource_tracker_spent:{[tracker.id]:tracker.max}},'rage'),/insufficiente/);
});
test('Second Wind, Lay on Hands and enhanced monk powers apply effects with exact payments',()=>{
 const fighter=sheet('Fighter',5),healed=apply(fighter,'second_wind',{roll:7});
 assert.equal(healed.current_hp,22);assert.equal(Object.values(healed.resource_tracker_spent)[0],1);
 const paladin=sheet('Paladin',5),pool=apply(paladin,'lay_on_hands',{amount:9});
 assert.equal(pool.current_hp,19);assert.equal(Object.values(pool.resource_tracker_spent)[0],9);
 const other=apply(paladin,'lay_on_hands',{amount:9,apply_to_self:false});assert.equal(other.current_hp,10);
 assert.throws(()=>apply(paladin,'lay_on_hands',{amount:-1}),/non valida/);
 for(const key of ['patient_defense','step_of_the_wind']){
  const monk=sheet('Monk',5,'2024'),free=apply(monk,key),paid=apply(monk,key,{enhanced:true});
  assert.deepEqual(free.resource_tracker_spent,{});assert.equal(Object.values(paid.resource_tracker_spent)[0],1);
  if(key==='patient_defense'){
   assert(!classFeatureRollAdvantage(free,calculateSheet(free,catalogs),'save:dex'));
   assert(classFeatureRollAdvantage(paid,calculateSheet(paid,catalogs),'save:dex'));
  }
 }
});
test('Font of Magic creates usable temporary slots or converts one into spent points; Arcane Recovery respects budget',()=>{
 let sorc=sheet('Sorcerer',5),out=calculateSheet(sorc,catalogs);
 const initial=out.spell_slots.find(s=>s.level===2).total;
 sorc=apply(sorc,'font_of_magic',{level:2,create_slot:true});out=calculateSheet(sorc,catalogs);
 assert.equal(out.spell_slots.find(s=>s.level===2).total,initial+1);
 assert.equal(Object.values(sorc.resource_tracker_spent)[0],3);
 sorc=apply(sorc,'font_of_magic',{level:2,create_slot:false});
 assert.equal(sorc.spell_slots_spent[2],1);assert.equal(Object.values(sorc.resource_tracker_spent)[0],1);
 assert(recoveryPatch(sorc,'long_rest',out.trackers).created_spell_slots.every(n=>n===0));
 const wizard={...sheet('Wizard',5),spell_slots_spent:[0,2,1,1]};
 const recovered=apply(wizard,'arcane_recovery',{levels:[1,1,0,0,0]});
 assert.equal(recovered.spell_slots_spent[1],1);assert.equal(recovered.spell_slots_spent[2],0);
 assert.throws(()=>apply(wizard,'arcane_recovery',{levels:[0,1,1,0,0]}),/Troppi/);
 assert.throws(()=>apply(recovered,'arcane_recovery',{levels:[1,0,0,0,0]}),/insufficiente/);
});
test('Wild Shape changes appearance, uses one charge, preserves base HP and restores the original form',()=>{
 const druid={...sheet('Druid',5),default_miniature_id:'elf',current_miniature_id:'elf',temporary_hp:3};
 const original=structuredClone(druid),out=calculateSheet(druid,catalogs);
 const changes=wildShapePatch(druid,out,{id:'wolf'},11),transformed={...druid,...changes};
 assert.deepEqual(druid,original);assert.equal(transformed.current_hp,druid.current_hp);
 assert.equal(resolveVariant(transformed).current_miniature_id,'wolf');assert.equal(resolveVariant(transformed).current_hp,11);
 assert.equal(changes.second_form_hp,undefined);
 assert.equal(Object.values(changes.resource_tracker_spent)[0],1);
 assert.throws(()=>wildShapePatch(transformed,calculateSheet(transformed,catalogs),{id:'bear'},12),/già attiva/);
 const hit=variantDamage(transformed,16),damaged=applyVariantEdit(transformed,hit.patch);
 assert.equal(resolveVariant(damaged).current_hp,0);assert.equal(damaged.current_hp,10);assert.equal(hit.overflow,5);
 const ended=endWildShapePatch(damaged);assert.equal(resolveVariant({...damaged,...ended}).current_miniature_id,'elf');assert.equal(ended.current_form_id,'');
 assert.equal(ended.resource_tracker_spent,undefined,'ending a transformation must not change uses');
 assert.throws(()=>wildShapePatch({...druid,default_miniature_id:'',current_miniature_id:''},out,{id:'wolf'},11),/miniatura di base/);
 assert(classFeatureEntries(druid,out).every(a=>a.origin_id?.startsWith('feature:')));
});
test('advantage rolls two actual dice, keeps the right die and leaves other bonuses independent',()=>{
 let dice=[2,18,3];const rolled=rollSheetDice(4,[{dice:'1d4',origin_name:'Bless'}],()=>dice.shift(),'advantage');
 assert.equal(rolled.total,25);assert.deepEqual(rolled.rolls,[2,18]);assert.match(rolled.notation,/^ADV · 1d20/);
 assert.doesNotMatch(rolled.notation,/2d20kh1/);
 dice=[2,18];assert.equal(rollSheetDice(4,[],()=>dice.shift(),'disadvantage').total,6);
 assert.equal(sheetRollFormula(4,[],'advantage'),'ADV · 1d20 + 4');
 assert.equal(sheetRollFormula(4,[],'disadvantage'),'DIS · 1d20 + 4');
});
test('Metamagic validates acquired options and charges together with spell payment only in a confirmed plan',()=>{
 const spell={id:'test',name:'Spell',level:1,range_feet:60,range:'60 feet',time:[{unit:'action'}],components:{v:true,s:true},duration:[{type:'timed',duration:{type:'minute',amount:1}}]};
 const sorc={...sheet('Sorcerer',5),prepared_spells:['test'],optional_features_catalog:[
  {name:'Distant Spell',source:'PHB'},{name:'Quickened Spell',source:'PHB'},
  {name:'Extended Spell',source:'PHB'},{name:'Empowered Spell',source:'PHB'}]};
 const out=calculateSheet(sorc,catalogs),before=structuredClone(sorc);
 const distant={...spell,metamagic:{names:['Distant Spell']}};
 const plan=spellCastPlan(sorc,distant,1,out);
 assert.deepEqual(sorc,before);assert.equal(plan.spell.range_feet,120);
 assert.equal(plan.context.metamagic.names[0],'Distant Spell');
 assert.equal(plan.patch.spell_slots_spent[1],1);assert.equal(Object.values(plan.patch.resource_tracker_spent)[0],1);
 assert.equal(metamagicPlan(sorc,{...spell,metamagic:{names:['Quickened Spell']}},1,out).spell.time,'bonus');
 assert.equal(metamagicPlan(sorc,{...spell,metamagic:{names:['Extended Spell']}},1,out).spell.duration,'120 seconds');
 assert.throws(()=>metamagicPlan(sorc,{...spell,metamagic:{names:['Heightened Spell']}},1,out),/non disponibile/);
 assert.throws(()=>metamagicPlan(sorc,{...spell,metamagic:{names:['Distant Spell','Quickened Spell']}},1,out),/combinare/);
 assert.throws(()=>metamagicPlan(sorc,{...spell,metamagic:{names:['Empowered Spell']}},1,out),/dopo il tiro/);
 const reroll=apply(sorc,'metamagic:Empowered Spell',{count:3,sides:6});
 assert.equal(Object.values(reroll.resource_tracker_spent)[0],1);assert.equal(reroll.active_class_features,undefined);
 assert.throws(()=>apply(sorc,'metamagic:Empowered Spell',{count:5,sides:6}),/Carisma/);
});
test('Innate Sorcery is paid, grants Sorcerer DC/attack benefits and does not boost another class',()=>{
 const c={...sheet('Sorcerer',5,'2024'),prepared_spells:['test']};
 const active=apply(c,'innate_sorcery'),out=calculateSheet(active,catalogs);
 const spell={id:'test',level:1,source_class:'Sorcerer',caster_ability:'cha'};
 const plan=spellCastPlan(active,spell,1,out);
 assert.equal(plan.context.spell_save_dc,out.values['casting_dc:cha']+1);
 assert.equal(plan.context.spell_attack_advantage,true);
 assert(classFeatureRollAdvantage(active,out,'casting_hit:cha'));
 assert.equal(spellCastPlan(active,{...spell,source_class:'Bard'},1,out).context.spell_attack_advantage,undefined);
 assert.equal(Object.values(active.resource_tracker_spent)[0],1);
});
test('descriptive class overrides cannot duplicate the executable privilege of the same trait',()=>{
 const c=sheet('Sorcerer',5),out=calculateSheet(c,catalogs);
 const overrides=JSON.parse(readFileSync(new URL('../../vtt/data/action_feature_overrides.json',import.meta.url),'utf8')).entries;
 const actions=actionEntries(c,out,[],overrides);
 assert.equal(actions.filter(a=>a.class_feature_id==='font_of_magic').length,1);
 assert(!actions.some(a=>a.name==='Conversione slot e punti stregoneria'));
});
