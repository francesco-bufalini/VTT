import {test} from 'node:test';
import assert from 'node:assert/strict';
import {calculateSheet} from '../sheet_rules.js';
import {effectiveBackgrounds,fixedProficiencies} from '../structured_effects.js';
import {battleActionPanels} from '../action_economy.js';
import {initialCreature} from '../character_core.js';
import {makeCreatureExport,parseCreatureExport,makeOwnedCopy} from '../creature_format.js';
import {completeRest} from '../native_sheet.js';

const player=()=>initialCreature('character','Esploratore','character-id','owner-id');
const base=()=>({...player(),abilities:{str:10,dex:14,con:12,int:10,wis:12,cha:10},max_hp_base:20});

test('ability-check and save category bonuses affect every roll exactly once, including initiative',()=>{
 const without=calculateSheet(base());
 const c={...base(),formula_bonuses:[
  {id:'check',target:'ability_check',expression:'1'},
  {id:'save',target:'saving_throw',expression:'2'},
  {id:'passive',target:'passive_perception',expression:'3'}
 ]};
 const result=calculateSheet(c);
 assert.equal(result.stats.initiative,without.stats.initiative+1);
 assert.equal(result.values['ability_check:dex'],without.values['ability_mod:dex']+1);
 assert.equal(result.values['ability_mod:dex'],without.values['ability_mod:dex']);
 assert.equal(result.skills.perception,without.skills.perception+1);
 assert.equal(result.skills.athletics,without.skills.athletics+1);
 assert.equal(result.saves.wis,without.saves.wis+2);
 assert.equal(result.saves.dex,without.saves.dex+2);
 assert.equal(result.stats.passive_perception,without.stats.passive_perception+4);
});

test('monster fixed saving throws also include general saving throw bonuses',()=>{
 const monster=initialCreature('monster','Guardiano','monster-id','owner-id');
 monster.stat_block={save:{str:'+5'}};
 monster.formula_bonuses=[{id:'ward',target:'saving_throw',expression:'2'}];
 assert.equal(calculateSheet(monster).saves.str,7);
});

test('Stone of Good Luck bonuses are category grants, and require an active equipped item',()=>{
 const stone={id:'stone-of-good-luck',name:'Stone of Good Luck',custom_item_type:'magic',
  quantity:1,req_attune:true,attuned:true,equipped:true,
  bonus_ability_check:1,bonus_saving_throw:1};
 const before=calculateSheet(base());
 const active=calculateSheet({...base(),inventory:[stone]});
 assert.equal(active.stats.initiative,before.stats.initiative+1);
 assert.equal(active.skills.perception,before.skills.perception+1);
 assert.equal(active.stats.passive_perception,before.stats.passive_perception+1);
 assert.equal(active.saves.str,before.saves.str+1);
 assert.equal(active.automatic_bonuses.filter(row=>row.target==='ability_check').length,1);
 assert.equal(active.automatic_bonuses.filter(row=>row.target==='saving_throw').length,1);
 const inactive=calculateSheet({...base(),inventory:[{...stone,attuned:false}]});
 assert.equal(inactive.stats.initiative,before.stats.initiative);
});

test('primary and additional backgrounds grant their own proficiencies with stable deduplication',()=>{
 const c={...base(),background:'Sage',background_source:'PHB',
  backgrounds_catalog:[{name:'Soldier',source:'PHB'},{name:'Sage',source:'PHB'}]};
 assert.deepEqual(effectiveBackgrounds(c).map(row=>row.name),['Sage','Soldier']);
 const index={background:[
  {name:'Sage',source:'PHB',skillProficiencies:['arcana']},
  {name:'Soldier',source:'PHB',skillProficiencies:['athletics']}
 ]};
 const trained=fixedProficiencies(c,index);
 assert(trained.has('skill:arcana'));
 assert(trained.has('skill:athletics'));
});

test('portable character transfers retain per-player variant rules and multiple backgrounds',()=>{
 const c={...base(),action_variants_2014:['flanking_dmg','overrun_dmg'],
  backgrounds_catalog:[{name:'Soldier',source:'PHB'}]};
 const packed=makeCreatureExport(c);
 const parsed=parseCreatureExport(JSON.stringify(packed));
 assert.deepEqual(parsed.creature.action_variants_2014,c.action_variants_2014);
 assert.deepEqual(parsed.creature.backgrounds_catalog,c.backgrounds_catalog);
 const copy=makeOwnedCopy(parsed.creature,'owner-123456789012','import_character');
 assert.deepEqual(copy.action_variants_2014,c.action_variants_2014);
 assert.deepEqual(copy.backgrounds_catalog,c.backgrounds_catalog);
});

test('class-only action panels hide D&D generic options but preserve equipped attacks',()=>{
 const c={...base(),rules_version:'2014'};
 const general=[{id:'dash',edition:'2014',name:'Scattare',timings:['movement'],
  description:'Raddoppia il movimento',source:'PHB'}];
 const projected={attacks:[{id:'item:sword',name:'Spada',slot:'main',hit:4,damage:'1d8',melee:true,range_feet:5}],skills:{}};
 const all=battleActionPanels(c,projected,[],[],general,[],[],false);
 const personal=battleActionPanels(c,projected,[],[],general,[],[],true);
 assert.match(all.movement,/Scattare/);
 assert.equal(personal.movement,'');
 assert.match(personal.attacks,/Spada/);
 assert.equal(personal.checks,'');
});

test('rest calculations can preview and accept exact manual Hit Dice results without mutating character',()=>{
 const c={...base(),hit_dice:'2d8',current_hp:9};
 const calc={...calculateSheet(c),stats:{...calculateSheet(c).stats,hit_dice:'2d8'}};
 const untouched=structuredClone(c);
 const preview=completeRest(c,'short_rest',calc,{d8:2},()=>1);
 let i=0;
 const outcome=completeRest(c,'short_rest',calc,{d8:2},()=>[5,7][i++]);
 assert.equal(outcome.rolls.length,2);
 assert.equal(outcome.rolls[0].roll,5);
 assert.equal(outcome.rolls[1].roll,7);
 assert(outcome.healed>=preview.healed);
 assert.deepEqual(c,untouched);
});
