import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {classFeatureRollSources,resolveClassRollMode} from '../feature_mechanics.js';
import {traitBenefitGroups} from '../trait_benefits.js';
import {effectExtensionsFor} from '../effect_extensions.js';
const read=name=>JSON.parse(readFileSync(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const catalogs={classMechanics:read('class_mechanics'),classFeatures:read('classes'),
 abilityGrants:read('ability_grants'),proficiencyGrants:read('proficiency_grants'),
 traitStates:read('trait_states').states,effectExtensions:read('effect_extensions').extensions};
const armor=(type='HA',strength='15',stealth=true)=>({
 id:'plate',name:'Plate Armor',type,ac:18,strength,stealth,quantity:1,equipped_slots:['body']
});
const base=(overrides={})=>({kind:'character',rules_version:'2014',level:5,
 classes:[{name:'Fighter',level:5,source:'PHB'}],
 abilities:{str:10,dex:14,con:12,int:10,wis:10,cha:10},inventory:[armor()],
 armor_natural_formula:'10 + dex_mod',...overrides});
test('worn armor applies its strength and stealth penalties to actual derived values',()=>{
 const r=base(),c=calculateSheet(r,catalogs);
 assert.equal(c.values.speed,20);
 assert.equal(c.armor_effects.speed_penalty,10);
 assert.equal(c.armor_effects.strength_required,15);
 assert.equal(resolveClassRollMode(classFeatureRollSources(r,c,'skill:stealth')).mode,'disadvantage');
 assert.equal(calculateSheet(base({abilities:{str:15,dex:14,con:12,int:10,wis:10,cha:10}}),catalogs).values.speed,30);
 assert.equal(calculateSheet(base({inventory:[]}),catalogs).values.speed,30);
});
test('the checkbox bypasses only the movement rule, not stealth',()=>{
 const r=base({armor_speed_limit_enabled:false}),c=calculateSheet(r,catalogs);
 assert.equal(c.values.speed,30);
 assert.equal(resolveClassRollMode(classFeatureRollSources(r,c,'skill:stealth')).mode,'disadvantage');
});
test('stealth disadvantage works for medium armor, but only when its item flag says so',()=>{
 const medium=base({inventory:[armor('MA',null,true)]});
 const c=calculateSheet(medium,catalogs);
 assert.equal(c.values.speed,30);
 assert.equal(resolveClassRollMode(classFeatureRollSources(medium,c,'skill:stealth')).mode,'disadvantage');
 const normal=base({inventory:[armor('HA',15,false)]});
 assert.equal(resolveClassRollMode(classFeatureRollSources(normal,calculateSheet(normal,catalogs),'skill:stealth')).mode,'normal');
});
test('a pre-2024 dwarf gains the racial armor-strength waiver as a benefit',()=>{
 const r=base({species:'Dwarf',species_source:'PHB'}),c=calculateSheet(r,catalogs);
 assert.equal(c.values.speed,25);
 assert.equal(c.armor_effects.strength_waived,true);
 assert.equal(resolveClassRollMode(classFeatureRollSources(r,c,'skill:stealth')).mode,'disadvantage');
 const groups=traitBenefitGroups({rank:0,category:'razza',origin_key:'species|dwarf|phb'},r,c);
 assert.ok(groups.some(g=>g.items.some(x=>x.id==='armor_waiver:dwarf-heavy-armor-speed-2014')));
 const modern=base({rules_version:'2024',species:'Dwarf',species_source:'XPHB'});
 assert.equal(calculateSheet(modern,catalogs).armor_effects.speed_penalty,10);
});
test('Arcane Armor grants a per-item extension when the Armorer model is active',()=>{
 const r=base({classes:[{name:'Artificer',source:'TCE',level:8,subclass:'Armorer',subclass_source:'TCE'}],
 level:8,trait_state_selection:{armor_model:'armor_model:infiltrator'}});
 const c=calculateSheet(r,catalogs);
 assert.equal(c.armor_effects.speed_penalty,0);
 assert.equal(c.armor_effects.strength_waived,true);
 assert.equal(c.values.speed,35);
 const ext=c.effect_extensions.find(x=>x.operation==='ignore_armor_strength');
 assert.ok(ext?.origin_id?.startsWith('feature:'),JSON.stringify(c.effect_extensions));
 assert.equal(effectExtensionsFor([ext],{kind:'item',id:'plate',name:'Plate Armor',inventory_index:0}).length,1);
 assert.equal(effectExtensionsFor([ext],{kind:'item',id:'other',name:'Other',inventory_index:1}).length,0);
});
test('mithral armor has neither penalty',()=>{
 const r=base({inventory:[{...armor(),name:'Mithral Plate Armor'}]}),c=calculateSheet(r,catalogs);
 assert.equal(c.values.ac,18);
 assert.equal(c.values.speed,30);
 assert.equal(c.armor_effects.stealth_disadvantage,false);
});
