import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {racialPowerProjection,racialAbilityEffectFormula,racialAbilityTemporaryHpPatch} from '../species_powers.js';
import {abilitiesForCreature} from '../activated_abilities.js';
import {battleAbilityEntries} from '../action_economy.js';
import {applicableDiceBonuses} from '../sheet_rules.js';
import {featureRollTarget,featureRollFlatBonuses,featureRollExtensionBonuses} from '../feature_rolls.js';
import {normalizeEffectExtension,effectExtensionsFor} from '../effect_extensions.js';
const index=JSON.parse(readFileSync(new URL('../catalog/species_powers.json',import.meta.url),'utf8'));
const record=(name,source)=>({
 kind:'character',rules_version:'2014',level:8,
 species:name,species_source:source,
 species_id:'5etools:races:'+source.toLowerCase()+':'+name.toLowerCase(),
 inventory:[],abilities:{str:12,dex:14,con:16,int:10,wis:12,cha:10}
});
const trait=(record,name)=>{
 const key='species|'+record.species_id+'|'+record.species_source.toLowerCase();
 return {name,key:key+'|1|'+name.toLowerCase(),
  origin_key:key,origin_id:'feature:'+key+'|1|'+name.toLowerCase()};
};
const projected=(rec,traitName)=>{
 const feature=trait(rec,traitName);
 const power=racialPowerProjection(rec,index,[feature]);
 return {feature,power,abilities:abilitiesForCreature(rec,[],{features:[feature],racial_abilities:power.abilities,trackers:power.trackers})};
};

test('2014 Goblin Nimble Escape exposes two separate bonus actions on all eligible sources',()=>{
 for(const source of ['DMG','VGM','MPMM']){
  const rec=record('Goblin',source);
  const {power,abilities}=projected(rec,'Nimble Escape');
  assert.equal(power.abilities.length,2,source);
  assert.deepEqual(new Set(power.abilities.map(x=>x.action_ref)),new Set(['hide','disengage']));
  assert(power.abilities.every(x=>x.action_type==='bonus'&&x.resource_cost===0));
  const entries=battleAbilityEntries(rec,{trackers:[]},[],abilities);
  assert.equal(entries.length,2,source);
  assert(entries.every(x=>x.time==='bonus'&&x.type==='Capacità'));
  assert.deepEqual(new Set(entries.map(x=>x.action_ref)),new Set(['hide','disengage']));
  assert.equal(racialPowerProjection({...rec,rules_version:'2024'},index,[trait(rec,'Nimble Escape')]).abilities.length,0);
 }
 const r=record('Goblin','PSZ');
 assert.equal(racialPowerProjection(r,index,[trait(r,'Nimble Escape')]).abilities.length,0);
 const r2=record('Goblin','MPMM'),f=trait(r2,'Nimble Escape');
 assert.equal(racialPowerProjection({...r2,origin_enabled:{[f.origin_id]:false}},index,[f]).abilities.length,0);
});

test('Orc MPMM Adrenaline Rush uses Dash as bonus action with a PB resource and temporary HP',()=>{
 const rec=record('Orc','MPMM'),{power}=projected(rec,'Adrenaline Rush');
 const action=power.abilities.find(a=>a.name==='Adrenaline Rush');
 assert(action);
 assert.equal(action.action_ref,'dash');
 assert.equal(action.action_type,'bonus');
 assert.equal(action.mode,'tracked_action');
 assert.equal(action.resource_cost,1);
 assert.equal(power.trackers[0].max,3);
 assert.equal(power.trackers[0].recharge,'long_rest');
 assert.deepEqual(racialAbilityTemporaryHpPatch({...rec,temporary_hp:8},action,
  {values:{proficiency:3}}),{temporary_hp:8},'temporary HP do not stack');
 assert.deepEqual(racialAbilityTemporaryHpPatch(rec,action,
  {values:{proficiency:3}}),{temporary_hp:3});
});

test('Stone Endurance and Hadozee Dodge have separate stable targets and reaction counters',()=>{
 const g=record('Goliath','MPMM'),h=record('Hadozee','AAG');
 const gp=projected(g,"Stone's Endurance").power,hp=projected(h,'Hadozee Dodge').power;
 const ga=gp.abilities[0],ha=hp.abilities[0];
 assert.equal(ga.action_type,'reaction');
 assert.equal(ha.action_type,'reaction');
 assert.equal(ga.mode,'tracked_action');
 assert.equal(gp.trackers[0].max,3);
 assert.equal(hp.trackers[0].max,3);
 assert.equal(racialAbilityEffectFormula(ga,{abilities:{con:{modifier:3}},stats:{proficiency:3}}),'1d12+3');
 assert.equal(racialAbilityEffectFormula(ha,{abilities:{con:{modifier:3}},stats:{proficiency:3}}),'1d6+3');
 assert.equal(featureRollTarget(ga),'feature_roll:race:mpmm:goliath:stones_endurance');
 assert.equal(featureRollTarget(ha),'feature_roll:race:aag:hadozee:hadozee_dodge');
 assert.notEqual(featureRollTarget(ga),featureRollTarget(ha));
 assert.equal(featureRollTarget({id:'activated:'+ga.id,ability_id:ga.id,roll_effect:ga.roll_effect}),
  featureRollTarget(ga));
 const empty={values:{proficiency:3},attunements:{counts:[]},racial_roll_bonuses:[]};
 const bonus={id:'second-trait',origin_id:'feat|example',dice:'1d4',target:featureRollTarget(ga)};
 const stored={...g,dice_bonuses:[bonus,{...bonus,id:'d20',target:'any_d20'}]};
 const available=target=>applicableDiceBonuses(stored,target,[],empty);
 assert.deepEqual(available(featureRollTarget(ga)).map(x=>x.id),['second-trait']);
 assert.equal(available(featureRollTarget(ha)).length,0);
});

test('extensions and numeric benefits may target exactly one named feature roll',()=>{
 const ability=projected(record('Goliath','MPMM'),"Stone's Endurance").power.abilities[0];
 const extension=normalizeEffectExtension({
  id:'other-class-feature',origin_id:'feature:class|phb|fighter|1|defense',
  origin_name:'Tratto · Protezione',target_kind:'ability',
  target_name:"Stone's Endurance",target_id:ability.id,
  operation:'bonus_roll',trigger:'on_use',frequency:'each',value:'1d4'});
 assert(extension);
 const fromAbility=effectExtensionsFor([extension],{kind:'ability',id:ability.id,name:ability.name});
 assert.equal(fromAbility.length,1);
 const calc={effect_extensions:[extension],values:{proficiency:4},stats:{proficiency:4}};
 assert.deepEqual(featureRollExtensionBonuses(calc,ability).map(x=>x.dice),['1d4']);
 assert.equal(featureRollExtensionBonuses(calc,
  projected(record('Hadozee','AAG'),'Hadozee Dodge').power.abilities[0]).length,0);
 const numeric=normalizeEffectExtension({...extension,id:'another-feature',value:'proficiency'});
 assert.equal(featureRollExtensionBonuses({...calc,effect_extensions:[numeric]},ability)[0].flat_bonus,4);
 const negative=normalizeEffectExtension({...extension,id:'clumsy-feature',value:'-2'});
 assert.equal(featureRollExtensionBonuses({...calc,effect_extensions:[negative]},ability)[0].flat_bonus,-2);
 const stored={formula_bonuses:[{id:'flat',target:featureRollTarget(ability),
  expression:'proficiency+1',origin_id:'feat|example',origin_name:'Other feature'}]};
 assert.equal(featureRollFlatBonuses(stored,calc,ability)[0].flat_bonus,5);
 assert.equal(featureRollFlatBonuses(stored,calc,
  projected(record('Hadozee','AAG'),'Hadozee Dodge').power.abilities[0]).length,0);
 assert.equal(featureRollFlatBonuses({...stored,origin_enabled:{'feat|example':false}},calc,ability).length,0);
});
