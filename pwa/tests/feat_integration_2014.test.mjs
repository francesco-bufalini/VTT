import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {concentrationDamageCheck,concentrationEndPatch} from '../concentration_rules.js';
import {expandedSpellFeatOptions,addFeatWithOrigin} from '../feat_picker.js';
import {featMechanicGrants,calculateSheet} from '../sheet_rules.js';
import {classFeatureRollSources,resolveClassRollMode,applicableFeatRollBonuses} from '../feature_mechanics.js';
import {structuredSpellGrants,originChoiceMatches} from '../spell_selection.js';
import {traitBenefitGroups} from '../trait_benefits.js';
import {nativeClassFeatureActions,actionEntries} from '../action_economy.js';
const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));

test('damage prompts a concentration save with half damage DC (min 10), including temp HP',()=>{
 const record={id:'actor',conditions:['concentrating','poisoned'],concentrating_spell_id:'bless',temporary_hp:40};
 assert.equal(concentrationDamageCheck(record,1)?.dc,10);
 assert.equal(concentrationDamageCheck(record,20)?.dc,10);
 assert.equal(concentrationDamageCheck(record,28)?.dc,14);
 assert.equal(concentrationDamageCheck(record,101)?.dc,50);
 assert.equal(concentrationDamageCheck(record,0),null);
 assert.equal(concentrationDamageCheck({...record,conditions:[],concentrating_spell_id:''},22),null);
 assert.equal(concentrationDamageCheck(record,28)?.target,'save:con');
 assert.deepEqual(concentrationEndPatch(record),{conditions:['poisoned'],concentrating_spell_id:''});
});

test('Lucky tracker and War Caster rules are native-typed and source-qualified',()=>{
 const native=read('../../vtt/data/feat_mechanics_2014.json').feats;
 const packaged=read('../catalog/ability_grants.json');
 assert.deepEqual(packaged.feat_mechanics,native);
 const warrior={kind:'character',rules_version:'2014',class:'Fighter',class_source:'PHB',level:5,
  classes:[{name:'Fighter',source:'PHB',level:5}],
  feats_catalog:[{name:'War Caster',source:'PHB'},{name:'Lucky',source:'PHB'}],
  abilities:{str:10,dex:10,con:14,int:10,wis:10,cha:10},armor_class_base:10,max_hp_base:20,inventory:[]};
 const typed=featMechanicGrants(warrior,packaged);
 assert.equal(typed.trackers.length,1);
 assert.equal(typed.trackers[0].max,3);
 assert.equal(typed.trackers[0].recharge,'long_rest');
 assert.equal(typed.actions.length,1);
 assert.equal(typed.actions[0].resource_cost,0);
 assert.equal(typed.actions[0].action_type,'reaction');
 assert.equal(typed.roll_modes[0].context,'concentration_damage');
 const actionRows=actionEntries(warrior,{feat_actions:typed.actions,features:[],trackers:[],attacks:[]});
 assert(actionRows.some(row=>row.name==='Attacco opportunità con incantesimo'&&row.time==='reaction'&&row.cost===0));

 const calculated=calculateSheet(warrior,{abilityGrants:packaged,classMechanics:{},proficiencyGrants:{}});
 assert.equal(calculated.trackers.filter(t=>t.id===typed.trackers[0].id).length,1);
 assert.equal(classFeatureRollSources(warrior,calculated,'save:con').some(x=>x.origin_id==='feat|phb|war caster'),false);
 assert.equal(resolveClassRollMode(classFeatureRollSources(warrior,calculated,'save:con','concentration_damage')).mode,'advantage');
 assert.equal(classFeatureRollSources(warrior,calculated,'save:dex','concentration_damage').length,0);
 const benefit=traitBenefitGroups({name:'War Caster',category:'talenti',rank:0,
   origin_key:'feat|war caster|phb'},warrior,calculated);
 assert(benefit.some(group=>group.type==='roll_modes'&&group.items.some(item=>
   item.label.includes('concentrazione')&&item.value==='Vantaggio')));
 assert(benefit.some(group=>group.type==='abilities'&&group.items.some(item=>
   item.label==='Attacco opportunità con incantesimo'&&item.cost==='Nessun costo')));
 assert(nativeClassFeatureActions(warrior,calculated).some(row=>row.name==='Attacco opportunità con incantesimo'));

 const without={...warrior,feats_catalog:[{name:'Lucky',source:'XPHB'},{name:'War Caster',source:'XPHB'}]};
 assert.equal(featMechanicGrants(without,packaged).trackers.length,0);
 assert.equal(featMechanicGrants({...warrior,feats_catalog:[{name:'Lucky',source:'PHB',disabled:true}]},packaged).trackers.length,0);
});

test('source-provided class-specific spell feat variants replace their generic picker row',()=>{
 const entries=read('../../vtt/data/additional_spells_5etools.json').entries;
 const original=[{name:'Magic Initiate',source:'PHB'},{name:'Ritual Caster',source:'PHB'},
  {name:'Spell Sniper',source:'PHB'},{name:'Lucky',source:'PHB'}];
 const options=expandedSpellFeatOptions(original,entries);
 assert.equal(options.filter(f=>f.name==='Magic Initiate').length,6);
 assert.equal(options.filter(f=>f.name==='Ritual Caster').length,6);
 assert.equal(options.filter(f=>f.name==='Spell Sniper').length,6);
 assert.equal(options.filter(f=>f.name==='Lucky').length,1);
 assert(options.some(f=>f.display_name==='Magic Initiate · Wizard'));
 assert(!options.some(f=>f.name==='Magic Initiate'&&!f.spell_variant));
 const selected=options.find(f=>f.name==='Magic Initiate'&&f.spell_variant==='Wizard Spells');
 const c={rules_version:'2014',feats_catalog:[]};
 const change=addFeatWithOrigin(c,selected,'manual',{},{}).feats_catalog[0];
 assert.equal(change.name,'Magic Initiate');
 assert.equal(change.spell_variant,'Wizard Spells');
 const row=entries.find(r=>r.kind==='feat'&&r.name==='Magic Initiate'&&r.source==='PHB');
 const effects=structuredSpellGrants({...c,level:4,feats_catalog:[change]},[row],[]);
 assert.equal(effects.choices.length,2);
 assert.equal(effects.trackers.length,1);
 assert(effects.choices.every(x=>x.spellcasting_ability==='int'));
 assert(effects.choices.some(x=>x.count===2&&x.filter.includes('class=Wizard')));
 assert(!effects.choices.some(x=>JSON.stringify(x).includes('class=Bard')));
});

test('conditional feat advantages require explicit use, retain source and do not affect unrelated rolls',()=>{
 const packaged=read('../catalog/ability_grants.json');
 const record={kind:'character',rules_version:'2014',level:4,abilities:{cha:16},
  feats_catalog:[{name:'Actor',source:'PHB'},{name:'Dungeon Delver',source:'PHB'}]};
 const calculated=calculateSheet(record,{abilityGrants:packaged});
 const deception=applicableFeatRollBonuses(record,calculated,'skill:deception');
 assert.equal(deception.length,1);
 assert.equal(deception[0].roll_mode,'advantage');
 assert.match(deception[0].condition_label,/impersonare/);
 assert.equal(deception[0].origin_id,'feat|phb|actor');
 assert.equal(applicableFeatRollBonuses(record,calculated,'skill:performance').length,1);
 assert.equal(applicableFeatRollBonuses(record,calculated,'skill:athletics').length,0);
 assert.equal(classFeatureRollSources(record,calculated,'skill:deception').some(row=>row.origin_id==='feat|phb|actor'),false);
 assert.equal(resolveClassRollMode(classFeatureRollSources(record,calculated,'skill:deception')).mode,'normal');
 assert.equal(resolveClassRollMode([{mode:deception[0].roll_mode,origin_id:deception[0].origin_id}]).mode,'advantage');
 const trap=applicableFeatRollBonuses(record,calculated,'save:wis');
 assert.equal(trap.length,1);assert.match(trap[0].condition_label,/trappole/);
 const card=traitBenefitGroups({name:'Actor',origin_key:'feat|actor|phb',
  category:'talenti',rank:0},record,calculated);
 assert(card.some(group=>group.type==='roll_modes'&&group.items.some(row=>
  row.label.includes('Inganno')&&row.value.includes('impersonare'))));
 const off={...record,feats_catalog:[{name:'Actor',source:'PHB',disabled:true}]};
 assert.equal(applicableFeatRollBonuses(off,calculateSheet(off,{abilityGrants:packaged}),'skill:deception').length,0);
 const ui=readFileSync(new URL('../ui.js',import.meta.url),'utf8');
 assert.match(ui,/applicableFeatRollBonuses\(creature,calculated,key\)/);
 assert.match(ui,/applicableFeatRollBonuses\(creature,calculated,'attack_damage:'\+attackId\)/);
});

test('other pre-2024 conditional feat roll modes and Charger damage are source- and attack-qualified',()=>{
 const packaged=read('../catalog/ability_grants.json');
 const record={rules_version:'2014',feats_catalog:[
  {name:'Grappler',source:'PHB'},{name:'Mage Slayer',source:'PHB'},
  {name:'Mounted Combatant',source:'PHB'},
  {name:'Infernal Constitution',source:'XGE'},
  {name:'Squat Nimbleness',source:'XGE'},
  {name:'Charger',source:'PHB'}]};
 const typed=featMechanicGrants(record,packaged);
 const calculated={feat_roll_modes:typed.roll_modes,feat_roll_bonuses:typed.roll_bonuses,
  attacks:[{id:'sword',melee:true},{id:'bow',melee:false}]};
 const melee=applicableFeatRollBonuses(record,calculated,'attack_hit:sword');
 assert(melee.some(x=>x.feat_name==='Mounted Combatant'));
 assert(melee.some(x=>x.feat_name==='Grappler'));
 const ranged=applicableFeatRollBonuses(record,calculated,'attack_hit:bow');
 assert(!ranged.some(x=>x.feat_name==='Mounted Combatant'));
 assert(ranged.some(x=>x.feat_name==='Grappler'));
 const sword=applicableFeatRollBonuses(record,calculated,'attack_damage:sword');
 assert(sword.some(x=>x.flat_bonus===5&&x.feat_name==='Charger'));
 const bow=applicableFeatRollBonuses(record,calculated,'attack_damage:bow');
 assert(!bow.some(x=>x.feat_name==='Charger'));
 const save=applicableFeatRollBonuses(record,calculated,'save:wis');
 assert(save.some(x=>x.feat_name==='Infernal Constitution'));
 assert(save.some(x=>x.feat_name==='Mage Slayer'));
 const skill=applicableFeatRollBonuses(record,calculated,'skill:athletics');
 assert(skill.some(x=>x.feat_name==='Squat Nimbleness'));
 assert.equal(applicableFeatRollBonuses(record,calculated,'skill:perception').length,0);
});

test('Shield Master scales with equipped shield AC; power attacks require appropriate proficient weapons',()=>{
 const packageRules=read('../catalog/ability_grants.json');
 const feats=[{name:'Shield Master',source:'PHB'},{name:'Great Weapon Master',source:'PHB'},
  {name:'Sharpshooter',source:'PHB'}];
 const typed=featMechanicGrants({feats_catalog:feats},packageRules);
 const attacks=[{id:'item:heavy',melee:true,proficient:true},
  {id:'item:bow',melee:false,proficient:true},
  {id:'item:sword',melee:true,proficient:true},
  {id:'item:untrained',melee:true,proficient:false}];
 const weapons=[
  {id:'heavy',name:'Greatsword',type:'M',damage:'2d6',properties:['H','2H'],equipped_slots:['main'],quantity:1},
  {id:'bow',name:'Longbow',type:'R',damage:'1d8',properties:['H','2H'],equipped_slots:['main'],quantity:1},
  {id:'sword',name:'Sword',type:'M',damage:'1d8',properties:[],equipped_slots:['off'],quantity:1},
  {id:'untrained',name:'Halberd',type:'M',damage:'1d10',properties:['H','2H'],equipped_slots:['main'],quantity:1},
  {id:'shield',name:'Shield +1',type:'S',ac:3,equipped_slots:['off'],quantity:1}
 ];
 const record={rules_version:'2014',feats_catalog:feats,inventory:weapons};
 const calculated={feat_roll_modes:typed.roll_modes,feat_roll_bonuses:typed.roll_bonuses,attacks};
 const shield=applicableFeatRollBonuses(record,calculated,'save:dex').find(x=>x.feat_name==='Shield Master');
 assert.equal(shield?.flat_bonus,3);
 assert.equal(applicableFeatRollBonuses({...record,inventory:weapons.filter(w=>w.id!=='shield')},calculated,'save:dex')
  .filter(x=>x.feat_name==='Shield Master').length,0);
 const heavy=applicableFeatRollBonuses(record,calculated,'attack_hit:item:heavy');
 assert(heavy.some(x=>x.feat_name==='Great Weapon Master'&&x.flat_bonus===-5&&x.require_before_roll));
 assert(!heavy.some(x=>x.feat_name==='Sharpshooter'));
 const bow=applicableFeatRollBonuses(record,calculated,'attack_hit:item:bow');
 assert(bow.some(x=>x.feat_name==='Sharpshooter'&&x.flat_bonus===-5&&x.require_before_roll));
 assert(!bow.some(x=>x.feat_name==='Great Weapon Master'));
 assert(!applicableFeatRollBonuses(record,calculated,'attack_hit:item:sword')
  .some(x=>x.feat_name==='Great Weapon Master'));
 assert(!applicableFeatRollBonuses(record,calculated,'attack_hit:item:untrained')
  .some(x=>x.feat_name==='Great Weapon Master'));
 assert(applicableFeatRollBonuses(record,calculated,'attack_damage:item:heavy')
  .some(x=>x.feat_name==='Great Weapon Master'&&x.flat_bonus===10));
 const ui=readFileSync(new URL('../ui.js',import.meta.url),'utf8');
 assert.match(ui,/row\.roll_mode\|\|row\.require_before_roll/);
 assert.match(ui,/featAvailable=applicableFeatRollBonuses/);
});
