import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {companionOwnerValues} from '../companion_owner_stats.js';
import {calculateSheet} from '../sheet_rules.js';
import {battleActionPanels} from '../action_economy.js';
import {sheetScoreOriginSegments} from '../sheet_roll_origin.js';
import {characterDefenseSummary} from '../defense_summary.js';
import {bestiarySheet} from '../creature_variants.js';

import {featureCompanionRule,eligibleCompanionFeatureRules,matchesCompanionFeature,
 spellCompanionRule,companionTemplateStat,companionStatBlockView,companionSources,companionGrantActive,infusionCompanionRule,companionSpellEffectPatch} from '../companion_rules.js';

const rules=JSON.parse(readFileSync(new URL('../catalog/companion_spells.json',import.meta.url),'utf8'));
const owner=(className,subclass,level)=>({
 kind:'character',rules_version:'2014',
 class:className,subclass,level,classes:[{name:className,level,subclass}],
 abilities:{str:10,dex:10,con:12,int:18,wis:16,cha:18},proficiency_bonus:3
});
const features=(className,name,id='1')=>({features:[{
 origin_id:id,name,origin_key:'class|phb|'+className.toLowerCase()+'|subclass|'+name.toLowerCase().replaceAll(' ','_')
}]});
test('Animating Performance is only eligible for a College of Creation bard at level six',()=>{
 const rule=rules.features.find(row=>row.id==='animating_performance_2014');
 const bard=owner('Bard','College of Creation',6),calculated=features('Bard','Animating Performance','feature:creation');
 assert.equal(featureCompanionRule(bard,calculated,rules,'feature:creation')?.id,rule.id);
 assert(!featureCompanionRule({...bard,subclass:'College of Lore',classes:[{name:'Bard',level:6,subclass:'College of Lore'}]},calculated,rules,'feature:creation'));
 assert(!featureCompanionRule(owner('Bard','College of Creation',5),calculated,rules,'feature:creation'));
 assert(!featureCompanionRule({...bard,rules_version:'2024'},calculated,rules,'feature:creation'));
 assert(!featureCompanionRule({...bard,origin_enabled:{'feature:creation':false}},calculated,rules,'feature:creation'));
 assert.equal(rule.alternative_slot_min,3);
});
test('Dancing Item, steel defender and wildfire spirit are derived from their actual owner',()=>{
 const item=companionTemplateStat(rules.templates.dancing_item,owner('Bard','College of Creation',9),{name:'Tappeto volante',size:'Small'});
 assert.equal(item.name,'Tappeto volante');
 assert.equal(item.size,'S');
 assert.equal(item.hp.average,55);
 assert.equal(item.ac[0],16);
 assert.equal(item.str,18);
 const steel=companionTemplateStat(rules.templates.steel_defender,owner('Artificer','Battle Smith',5));
 assert.equal(steel.hp.average,31);
 assert.equal(steel.speed.walk,40);
 const wildfire=companionTemplateStat(rules.templates.wildfire_spirit,owner('Druid','Circle of Wildfire',7));
 assert.equal(wildfire.hp.average,40);
 const drake=companionTemplateStat(rules.templates.drake_companion,owner('Ranger','Drakewarden',7));
 assert.equal(drake.ac[0],17);
 const servant=companionTemplateStat(rules.templates.homunculus_servant,owner('Artificer','Alchemist',8));
 assert.equal(servant.hp.average,13);
 assert.equal(servant.hit_dice,'8d4');
 const leveled=companionTemplateStat(rules.templates.homunculus_servant,
  owner('Artificer','Alchemist',12));
 assert.equal(leveled.skill.perception,8,'A stale saved PB must not leak into new companions');
 assert.deepEqual(servant.skill,{perception:6,stealth:5});
 assert.deepEqual(servant.save,{dex:5});
 const saved=bestiarySheet(servant);
 assert.deepEqual(saved.stat_block.skill,servant.skill);
 assert.deepEqual(saved.stat_block.save,servant.save);
 assert.deepEqual(saved.stat_block.immune,['poison']);
 assert.deepEqual(saved.stat_block.conditionImmune,['exhaustion','poisoned']);
});
test('trait choices must match the source and allowed beast CR/size',async()=>{
 const ranger=owner('Ranger','Beast Master',5);
 const rule=rules.features.find(x=>x.id==='rangers_companion_2014');
 const list=[{key:'a',name:'Wolf',source:'MM',type:'beast',cr:'1/4',size:['M'],load:async()=>({name:'Wolf'})},
   {key:'b',name:'Brown Bear',source:'MM',type:'beast',cr:'1',size:['L'],load:async()=>({name:'Brown Bear'})},
   {key:'c',name:'Rat',source:'MM',type:'beast',cr:'0',size:['T'],load:async()=>({name:'Rat'})}];
 const choices=companionSources(rule,rules,list,ranger);
 assert.deepEqual(choices.map(x=>x.name),['Wolf','Rat']);
 const regular=rules.features.find(x=>x.id==='steel_defender_2014');
 const d=companionSources(regular,rules,[],owner('Artificer','Battle Smith',3));
 assert.equal(d.length,1);
 assert.equal((await d[0].load()).hp.average,21);
});
test('Animate Dead can add multiple creatures; the legacy familiars retain one exclusive sheet',()=>{
 const wizard=owner('Wizard','Evocation',7);
 assert.equal(spellCompanionRule(rules,{name:'Animate Dead'},wizard).limit_per_owner_spell,0);
 assert.equal(spellCompanionRule(rules,{name:'Find Familiar'},wizard).limit_per_owner_spell,1);
 assert.equal(spellCompanionRule(rules,{name:'Animate Dead'},{...wizard,rules_version:'2024'}),null);
});
test('unrelated passive traits do not produce free summons',()=>{
 const bard=owner('Bard','College of Creation',6);
 const p=features('Bard','Performance of Creation','different');
 assert.deepEqual(eligibleCompanionFeatureRules(bard,p,rules),[]);
 assert.equal(featureCompanionRule(bard,p,rules,'different'),null);
});

test('infused-object and spell-effect grants toggle availability, not saved sheets',()=>{
 const artificer=owner('Artificer','Alchemist',7);
 const infusion={id:'infusion|tce|homunculus servant',companion:{rule_id:'homunculus_servant_2014'}};
 assert.equal(infusionCompanionRule(rules,[infusion],infusion.id,artificer)?.activation,'item');
 assert.equal(infusionCompanionRule(rules,[],infusion.id,artificer),null);
 const child={companion_grant:{kind:'inventory_infusion',id:infusion.id},companion_selected:true};
 assert.equal(companionGrantActive({...artificer,inventory:[]},child),false);
 assert.equal(companionGrantActive({...artificer,inventory:[{quantity:1,infusion:{id:infusion.id}}]},child),true);
 assert.equal(companionGrantActive({...artificer,inventory:[{quantity:1,infusion:{id:infusion.id}}]},{...child,companion_selected:false}),false);
 const effect=companionSpellEffectPatch(artificer,{grant_kind:'spell_effect',names:['Find Familiar']},'find-familiar');
 const familiar={companion_grant:{kind:'spell_effect',id:'spell:find-familiar'}};
 assert.equal(companionGrantActive(artificer,familiar),false);
 assert.equal(companionGrantActive({...artificer,...effect},familiar),true);
 assert.equal(companionGrantActive({...artificer,...effect,proficiency_origins:[]},familiar),false);
 assert.deepEqual(companionSpellEffectPatch(artificer,{},'find-familiar'),{});
});

test('homunculus servant uses live owner proficiency, spell attack and HP',()=>{
 const parent={...owner('Artificer','Alchemist',8),id:'owner',owner_id:'install',name:'Ari',
  class_source:'TCE',classes:[{name:'Artificer',source:'TCE',level:8}]};
 const template=rules.templates.homunculus_servant;
 const child={kind:'monster',id:'homunculus',parent_creature_id:parent.id,owner_id:'install',
  companion_rule_id:'homunculus_servant_2014',companion_template_id:'homunculus_servant',
  // Existing saved companions can predate the new structured training fields.
  stat_block:{action:structuredClone(template.action),hp:{average:13},ac:[13],
   immune:structuredClone(template.immune),conditionImmune:structuredClone(template.conditionImmune)},
  abilities:template.abilities,current_hp:4,max_hp:13,max_hp_base:13,
  armor_class_base:13,armor_natural_formula:'13',inventory:[]};
 const initial=companionOwnerValues(child,parent,calculateSheet(parent,{}),rules);
 assert.equal(initial.proficiency,3);
 assert.equal(initial.hp,13);
 assert.equal(initial.hit_dice,'8d4');
 assert.equal(initial.attacks[0].hit,7);
 assert.equal(initial.attacks[0].damage,'1d4 + 3');
 const calculated=calculateSheet({...child,companion_owner_values:initial},{});
 assert.equal(calculated.values.proficiency,3);
 assert.equal(calculated.stats.max_hp,13);
 assert.equal(calculated.stats.hit_dice,'8d4');
 assert.equal(calculated.attacks.find(x=>x.name==='Force Strike').hit,7);
 assert.equal(calculated.attacks.find(x=>x.name==='Force Strike').damage,'1d4 + 3');
 const displayed=battleActionPanels({...child,companion_owner_values:initial},calculated).attacks;
 const force=displayed.indexOf('data-attack-id="monster:action:0"');
 const unarmed=displayed.indexOf('data-attack-id="unarmed"');
 assert(force>=0&&unarmed>=0&&force<unarmed,
  'The homunculus stat-block Force Strike appears before the generic unarmed strike');
 assert.deepEqual([calculated.values['skill:perception'],calculated.values['skill:stealth'],
  calculated.values['save:dex'],calculated.values.passive_perception],[6,5,5,16]);
 assert(calculated.proficiencies.includes('expertise:perception'));
 assert(calculated.proficiencies.includes('skill:stealth'));
 assert(calculated.proficiencies.includes('save:dex'));
 assert.equal(calculated.proficiency_sources['expertise:perception'][0].id,
  'companion:homunculus_servant_2014');
 const defenses=characterDefenseSummary(child,calculated);
 assert.deepEqual(defenses.groups[1].items.map(x=>x.key),['poison']);
 assert.deepEqual(defenses.groups[2].items.map(x=>x.key).sort(),['exhaustion','poisoned']);
 assert.equal(sheetScoreOriginSegments(child,calculated,'proficiency')[0].originName,'Proprietario · Ari');
 const grown={...parent,level:12,classes:[{name:'Artificer',source:'TCE',level:12}],
  abilities:{...parent.abilities,int:20}};
 const next=companionOwnerValues(child,grown,calculateSheet(grown,{}),rules);
 assert.equal(next.proficiency,4);
 assert.equal(next.hp,18);
 assert.equal(next.hit_dice,'12d4');
 assert.equal(next.attacks[0].hit,9);
 const changed=calculateSheet({...child,companion_owner_values:next},{});
 assert.deepEqual([changed.values['skill:perception'],changed.values['skill:stealth'],
  changed.values['save:dex'],changed.values.passive_perception],[8,6,6,18]);
 assert.equal(child.current_hp,4);
 assert.equal(child.max_hp_base,13,'linked values do not overwrite a saved companion');
 assert.equal(companionOwnerValues({...child,parent_creature_id:'different'},parent,calculateSheet(parent,{}),rules),null);
});
test('owner-stat bindings are opt-in, including drake AC but not Find Familiar',()=>{
 const parent={...owner('Ranger','Drakewarden',7),id:'owner',owner_id:'install',
  class_source:'FTD',classes:[{name:'Ranger',source:'FTD',level:7}]};
 const child={kind:'monster',id:'drake',parent_creature_id:'owner',owner_id:'install',
  companion_rule_id:'drake_companion_2014',companion_template_id:'drake_companion',
  stat_block:{action:structuredClone(rules.templates.drake_companion.action)}};
 const calculated=calculateSheet(parent,{}),linked=companionOwnerValues(child,parent,calculated,rules);
 assert.equal(linked.proficiency,3);
 assert.equal(linked.ac,17);
 assert.equal(calculateSheet({...child,companion_owner_values:linked},{}).values.ac,17);
 assert.equal(companionOwnerValues({...child,companion_rule_id:'find_familiar_2014'},parent,calculated,rules),null);
});

test('ordinary bestiary monsters preserve fixed skill totals and project unconditional defenses',()=>{
 const monster=bestiarySheet({name:'Test Beast',type:'beast',cr:3,str:10,dex:12,con:10,int:10,wis:12,cha:10,
  hp:{average:12},ac:[12],skill:{perception:7},
  resist:['cold'],immune:['fire'],vulnerable:['radiant'],conditionImmune:['poisoned'],
  // Conditional defenses must not become blanket resistances.
  trait:[],action:[]});
 monster.stat_block.resist.push({resist:['slashing'],note:'only against nonmagical attacks'});
 const result=calculateSheet(monster,{});
 assert.equal(result.values['skill:perception'],7);
 const defenses=characterDefenseSummary(monster,result);
 assert.deepEqual(defenses.groups.map(group=>group.items.map(row=>row.key)),
  [['cold'],['fire'],['poisoned'],['radiant']]);
});

test('5eTools-based companion profiles preserve languages, reactions and all PB-dependent skills/saves',()=>{
 const artificer={...owner('Artificer','Battle Smith',8),id:'artificer',owner_id:'local'};
 const steel=companionTemplateStat(rules.templates.steel_defender,artificer);
 assert.deepEqual(steel.skill,{athletics:5,perception:6});
 assert.deepEqual(steel.save,{dex:4,con:5});
 assert.equal(steel.passive,16);
 assert.equal(steel.hit_dice,'8d8');
 assert.deepEqual(steel.reaction.map(x=>x.name),['Deflect Attack']);
 assert.equal(steel.languages[0],'understands the languages you speak');
 assert.deepEqual(companionTemplateStat(rules.templates.dancing_item,owner('Bard','College of Creation',6))
   .trait.map(x=>x.name),['Immutable Form','Irrepressible Dance']);
 const drake=companionTemplateStat(rules.templates.drake_companion,owner('Ranger','Drakewarden',7));
 assert.deepEqual(drake.save,{dex:4,wis:5});
 assert.equal(drake.hit_dice,'7d10');
 assert.deepEqual(drake.reaction.map(x=>x.name),['Infused Strikes']);
 assert.deepEqual(drake.languages,['Draconic']);
 const homunculus=companionTemplateStat(rules.templates.homunculus_servant,artificer);
 assert.deepEqual(homunculus.reaction.map(x=>x.name),['Channel Magic']);
 assert.equal(homunculus.passive,16);
 assert.equal(bestiarySheet(companionTemplateStat(rules.templates.dancing_item,
  owner('Bard','College of Creation',6))).alignment,'Senza allineamento');
});

test('saved companion sheets gain omitted template entries in view only and retain user edits',()=>{
 const saved={kind:'monster',parent_creature_id:'owner',companion_rule_id:'steel_defender_2014',
  companion_template_id:'steel_defender',stat_block:{name:'Steel Defender',
   action:[{name:'Force-Empowered Rend',entries:['Custom attack text']}],
   trait:[{name:'Vigilant',entries:['Custom description']}],
   immune:['custom'],languages:['Goblin']},
  current_hp:7,inventory:[{id:'my-item'}]};
 const before=structuredClone(saved);
 const viewed=companionStatBlockView(saved,rules);
 assert.deepEqual(saved,before,'Render must never persist or mutate source');
 assert.equal(viewed.stat_block.trait[0].entries[0],'Custom description');
 assert.deepEqual(viewed.stat_block.reaction.map(x=>x.name),['Deflect Attack']);
 assert.deepEqual(viewed.stat_block.immune,['custom']);
 assert.deepEqual(viewed.stat_block.languages,['Goblin']);
 assert.deepEqual(viewed.inventory,saved.inventory);
 assert.equal(viewed.current_hp,7);
 const drake=companionStatBlockView({...saved,
  companion_rule_id:'drake_companion_2014',companion_template_id:'drake_companion',
  stat_block:{action:[{name:'Bite'}]}},rules);
 assert.deepEqual(drake.stat_block.reaction.map(x=>x.name),['Infused Strikes']);
 assert.equal(companionStatBlockView({...saved,companion_template_id:'invalid'},rules).stat_block,saved.stat_block);
});

test('steel defender and drake owner proficiency changes update their full live training',()=>{
 const original={...owner('Artificer','Battle Smith',8),id:'owner',owner_id:'local'};
 const child={kind:'monster',id:'steel',owner_id:'local',parent_creature_id:'owner',
  companion_rule_id:'steel_defender_2014',companion_template_id:'steel_defender',
  stat_block:{action:rules.templates.steel_defender.action},
  abilities:rules.templates.steel_defender.abilities};
 const linked=companionOwnerValues(child,original,calculateSheet(original,{}),rules);
 const first=calculateSheet({...child,companion_owner_values:linked},{});
 assert.deepEqual([first.values['save:dex'],first.values['save:con'],
  first.values['skill:athletics'],first.values['skill:perception'],first.values.passive_perception],
  [4,5,5,6,16]);
 assert.equal(first.proficiencies.includes('expertise:perception'),true);
 const grown={...original,level:12,classes:[{name:'Artificer',level:12}]};
 const next=companionOwnerValues(child,grown,calculateSheet(grown,{}),rules);
 const second=calculateSheet({...child,companion_owner_values:next},{});
 assert.deepEqual([second.values['save:dex'],second.values['save:con'],
  second.values['skill:athletics'],second.values['skill:perception'],second.values.passive_perception],
  [5,6,6,8,18]);
});

test('ordinary bestiary saving throws and training icons retain source numeric totals',()=>{
 const beast=bestiarySheet({name:'Guardian',cr:3,str:10,dex:12,con:12,int:10,wis:14,cha:10,
  hp:{average:18},ac:[13],skill:{perception:6,stealth:3,arcana:9},
  save:{dex:3,con:3},passive:16});
 const calc=calculateSheet(beast,{});
 assert.equal(beast.alignment,'—');
 assert.equal(bestiarySheet({name:'Wolf',hp:{average:11,formula:'2d8 + 2'},ac:[13]}).hit_dice,'2d8');
 assert.equal(calc.values['skill:perception'],6);
 assert.equal(calc.values['skill:stealth'],3);
 assert.equal(calc.values['skill:arcana'],9);
 assert.equal(calc.proficiencies.includes('expertise:perception'),true);
 assert.equal(calc.proficiencies.includes('skill:stealth'),true);
 assert.equal(calc.proficiencies.includes('save:con'),true);
 assert.equal(calc.values['save:con'],3);
 assert.equal(calc.values.passive_perception,16);
});
