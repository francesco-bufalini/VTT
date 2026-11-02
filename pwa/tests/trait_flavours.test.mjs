import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {traitFlavourChoices,flavourBenefitChoices,saveTraitFlavourChoice,
  saveFlavourFeatChoice,projectTraitFlavourBenefits} from '../trait_flavours.js';
import {savePendingChoice} from '../pending_choices.js';

const read=name=>JSON.parse(readFileSync(new URL('../../vtt/enrichment/benefits/'+name+'.json',import.meta.url),'utf8'));
const catalogs={flavours:read('flavours'),flavourBonuses:read('bonus'),
  flavourFeatGrants:read('feat_grant'),flavourDefenses:read('defense'),
  originDetails:{feats:{'Alert|PHB':{}}}};
const asi=level=>({name:'Ability Score Improvement',origin_id:'feature:class|phb|fighter|'+level+'|ability score improvement',
  origin_key:'class|phb|fighter',class_name:'Fighter',class_source:'PHB',level});
const base=()=>({kind:'character',rules_version:'2014',classes:[{name:'Fighter',source:'PHB',level:8}],
  feats_catalog:[],formula_bonuses:[],advancement_choices:[]});
const save=(record,choice,values)=>({...record,...savePendingChoice(record,choice,values)});
test('ASI has exactly two flavours, and its two independently owned +1 bonuses can target the same score',()=>{
 const features=[asi(4),asi(8)];let record=base();
 const choices=traitFlavourChoices(record,features,catalogs.flavours);
 assert.equal(choices.length,2);assert(choices.every(c=>c.options.length===2));
 record=save(record,choices[0],[choices[0].options[0]]);
 let picks=flavourBenefitChoices(record,features,catalogs);
 assert.equal(picks.length,2);
 assert.notEqual(picks[0].id,picks[1].id);
 record=save(record,picks[0],['str']);
 record=save(record,picks[1],['str']);
 const projection=projectTraitFlavourBenefits(record,features,catalogs);
 assert.deepEqual(projection.formula_bonuses.map(x=>x.target),['ability:str','ability:str']);
 assert.deepEqual(projection.formula_bonuses.map(x=>x.expression),['1','1']);
 assert.equal(new Set(projection.formula_bonuses.map(x=>x.id)).size,2);
 assert.equal(projection.flavour_traits.length,1);
 assert.equal(projection.flavour_traits[0].parent_origin,asi(4).origin_id);
 assert.equal(traitFlavourChoices(record,features,catalogs.flavours)[1].remaining,1);
});
test('ASI feat-grant is owned by its selected flavour and switching removes only its bonuses/feat',()=>{
 const owner=asi(4),features=[owner],initial=traitFlavourChoices(base(),features,catalogs.flavours)[0];
 let record=save(base(),initial,[initial.options[0]]);
 record=save(record,flavourBenefitChoices(record,features,catalogs)[0],['con']);
 const next=traitFlavourChoices(record,features,catalogs.flavours)[0];
 record=save(record,next,[next.options[1]]);
 assert.equal(record.formula_bonuses.length,0);
 let grant=flavourBenefitChoices(record,features,catalogs)[0];
 assert.equal(grant.kind,'flavour_feat');
 record=save(record,grant,['phb|alert']);
 assert.equal(record.feats_catalog.length,1);
 assert.equal(record.feats_catalog[0].flavour_parent_id,owner.origin_id);
 assert(record.feats_catalog[0].granted_by.startsWith('flavour:'));
 assert.equal(projectTraitFlavourBenefits(record,features,catalogs).flavour_traits[0].name,'Talento');
 record=save(record,traitFlavourChoices(record,features,catalogs.flavours)[0],[initial.options[0]]);
 assert.equal(record.feats_catalog.length,0);
});
test('FTD ancestry variants own their own resistance, while old colour choices stay compatible',()=>{
 const feature={name:'Draconic Ancestry',
  origin_id:'feature:species|dragonborn (chromatic)|ftd|1|draconic ancestry',
  origin_key:'species|dragonborn (chromatic)|ftd'};
 let record={rules_version:'2014',species:'Dragonborn (Chromatic)',species_source:'FTD',
   subrace:'Red',subrace_source:'FTD'};
 const choice=traitFlavourChoices(record,[feature],catalogs.flavours)[0];
 assert.equal(choice.selected[0],'flavour:dragonborn:ftd:chromatic:red');
 assert.equal(projectTraitFlavourBenefits(record,[feature],catalogs).damage_defense_entries.length,0,
  'Legacy colour stays owned by the old engine until an explicit flavour save');
 record=save(record,choice,['flavour:dragonborn:ftd:chromatic:blue']);
 const projected=projectTraitFlavourBenefits(record,[feature],catalogs);
 assert.equal(projected.damage_defense_entries.length,1);
 assert.equal(projected.damage_defense_entries[0].key,'lightning');
 assert.equal(projected.damage_defense_entries[0].origin_id,projected.flavour_traits[0].origin_id);
 assert.equal(record.subrace,'Blue');
});
test('feat with chosen ability migrates without double-counting old score allocations',()=>{
 const feat={name:'Athlete',source:'PHB',ability_choice:'str'};
 let record={rules_version:'2014',feats_catalog:[feat]};
 const choice=traitFlavourChoices(record,[],catalogs.flavours)[0];
 assert.equal(choice.selected[0],'flavour:athlete:phb:str');
 assert.equal(projectTraitFlavourBenefits(record,[],catalogs).formula_bonuses?.length||0,0);
 record=save(record,choice,['flavour:athlete:phb:dex']);
 assert.equal(record.feats_catalog[0].ability_choice,'');
 const projected=projectTraitFlavourBenefits(record,[],catalogs);
 assert.equal(projected.formula_bonuses[0].target,'ability:dex');
 assert.equal(projected.formula_bonuses[0].expression,'1');
});
test('all flavour grants reference an existing flavour, not the original trait',()=>{
 const ids=new Set(catalogs.flavours.entries.flatMap(e=>e.flavours.map(f=>f.id)));
 for(const catalog of [catalogs.flavourBonuses,catalogs.flavourDefenses,catalogs.flavourFeatGrants])
  for(const entry of catalog.entries){
   assert.equal(entry.granted_by.kind,'flavour');
   assert(ids.has(entry.granted_by.ref.id),entry.id);
  }
});
