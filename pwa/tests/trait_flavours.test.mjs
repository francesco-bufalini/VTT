import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSenses} from '../sense_rules.js';
import {traitFlavourChoices,flavourBenefitChoices,saveTraitFlavourChoice,
  saveFlavourFeatChoice,projectTraitFlavourBenefits} from '../trait_flavours.js';
import {savePendingChoice} from '../pending_choices.js';
import {calculateSheet} from '../sheet_rules.js';

const read=name=>JSON.parse(readFileSync(new URL('../../vtt/enrichment/benefits/'+name+'.json',import.meta.url),'utf8'));
const catalogs={flavours:read('flavours'),flavourBonuses:read('bonus'),
  flavourFeatGrants:read('feat_grant'),flavourDamageModifiers:read('damage_modifier'),
  proficiencyGrantBenefits:read('proficiency_grant'),
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
 assert.throws(()=>save(base(),choices[0],[]),/Flavour non disponibile/);
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
 for(const catalog of [catalogs.flavourFeatGrants,
 ...[catalogs.flavourBonuses,catalogs.flavourDamageModifiers,catalogs.proficiencyGrantBenefits].map(c=>({
  entries:c.entries.filter(e=>e.granted_by?.kind==='flavour')
 }))])
  for(const entry of catalog.entries.filter(e=>e.granted_by?.kind==='flavour')){
   assert.equal(entry.granted_by.kind,'flavour');
   assert(ids.has(entry.granted_by.ref.id),entry.id);
  }
});

const abilityIndex=JSON.parse(readFileSync(new URL('../catalog/ability_grants.json',import.meta.url),'utf8'));
const fullCatalogs={...catalogs,abilityGrants:abilityIndex};
const sheetRecord=()=>({...base(),abilities:{str:10,dex:10,con:10,int:10,wis:10,cha:10}});

test('source-qualified 5eTools single-score feats are migrated to distinct flavour grants',()=>{
 const supported=abilityIndex.feat.filter(feat=>(feat.ability_choices||[]).length===1&&
   feat.ability_choices[0]?.choose?.from?.length>=2&&
   Number(feat.ability_choices[0]?.choose?.count??1)===1&&
   Number(feat.ability_choices[0]?.choose?.amount??1)===1&&
   !feat.ability_choices[0]?.choose?.entry);
 assert.equal(supported.length,152,'Source index changed: audit feat flavour migration');
 const migrated=supported.filter(f=>!(f.name==='Athlete'&&f.source==='PHB'));
 assert.equal(migrated.length,151);
 for(const feat of supported){
  const owner={name:feat.name,source:feat.source};
  const record={...sheetRecord(),feats_catalog:[owner]};
  const choice=traitFlavourChoices(record,[],catalogs.flavours);
  assert.equal(choice.length,1,feat.name+' ('+feat.source+')');
  const expected=feat.ability_choices[0].choose.from;
  assert.equal(choice[0].options.length,expected.length,feat.name);
  for(const stat of expected){
   const option=choice[0].options.find(id=>id.endsWith(':'+stat));
   assert(option,feat.name+':'+stat);
   const selected=save(record,choice[0],[option]);
   const projected=projectTraitFlavourBenefits(selected,[],catalogs);
   const matching=projected.formula_bonuses.filter(b=>b.target==='ability:'+stat);
   assert.equal(matching.length,1,feat.name+':'+stat);
   assert.equal(matching[0].origin_id,projected.flavour_traits[0].origin_id);
  }
 }
});

test('changing a migrated feat flavour withdraws legacy scores and applies exactly one new +1',()=>{
 const baseRecord={...sheetRecord(),feats_catalog:[{name:'Chef',source:'TCE',ability_choice:'wis'}]};
 assert.equal(calculateSheet(baseRecord,fullCatalogs).abilities.wis.score,11);
 const choice=traitFlavourChoices(baseRecord,[],catalogs.flavours)[0];
 assert.deepEqual(choice.selected,[choice.options.find(option=>option.endsWith(':wis'))]);
 const changed=save(baseRecord,choice,[choice.options.find(option=>option.endsWith(':con'))]);
 assert.equal(changed.feats_catalog[0].ability_choice,'');
 const projected=projectTraitFlavourBenefits(changed,[],catalogs);
 const sheet=calculateSheet(projected,fullCatalogs);
 assert.equal(sheet.abilities.con.score,11);
 assert.equal(sheet.abilities.wis.score,10);
 assert.equal(sheet.bonuses.filter(row=>row.target==='ability:con').length,1);
 const disabled={...changed,origin_enabled:{'feat|tce|chef':false}};
 const noFeat=calculateSheet(projectTraitFlavourBenefits(disabled,[],catalogs),fullCatalogs);
 assert.equal(noFeat.abilities.con.score,10);
});

test('feat flavour ownership remains stable even when feat section traits have distinct feature IDs',()=>{
 const record={...sheetRecord(),feats_catalog:[{name:'Chef',source:'TCE'}]};
 const sections=[{name:'Chef',origin_key:'feat|chef|tce',origin_id:'feature:feat|chef|tce|cooking'},
  {name:'Chef',origin_key:'feat|chef|tce',origin_id:'feature:feat|chef|tce|rest'}];
 const options=traitFlavourChoices(record,sections,catalogs.flavours);
 assert.equal(options.length,1);
 assert.equal(options[0].origin_id,'feat|tce|chef');
});

test('Resilient 2014 flavour grants one selected save proficiency and a +1 without old duplicates',()=>{
 const owner={name:'Resilient',source:'PHB',ability_choice:'wis'};
 let record={...sheetRecord(),feats_catalog:[owner],
   proficiency_choices:[{kind:'save',key:'wis',origin_id:'feat|phb|resilient'}]};
 const choice=traitFlavourChoices(record,[],catalogs.flavours)[0];
 assert.equal(choice.selected.length,1);
 assert.equal(choice.options.length,6);
 record=save(record,choice,[choice.options.find(id=>id.endsWith(':con'))]);
 assert.equal(record.feats_catalog[0].ability_choice,'');
 assert.equal(record.proficiency_choices.length,0,'old Resilient grant is withdrawn');
 const projected=projectTraitFlavourBenefits(record,[],catalogs);
 assert.deepEqual(projected.proficiency_choices.map(row=>row.kind+':'+row.key),['save:con']);
 assert.equal(projected.proficiency_choices[0].origin_id,projected.flavour_traits[0].origin_id);
 const sheet=calculateSheet(projected,fullCatalogs);
 assert(sheet.proficiencies.includes('save:con'));
 assert(!sheet.proficiencies.includes('save:wis'));
 assert.equal(sheet.abilities.con.score,11);
 assert.equal(sheet.abilities.wis.score,10);
 const disabled=projectTraitFlavourBenefits({...record,origin_enabled:{'feat|phb|resilient':false}},[],catalogs);
 assert.equal(disabled.proficiency_choices.length,0);
});
test('Resilient 2024 forbids an already proficient save except the owned current selection',()=>{
 const record={...sheetRecord(),rules_version:'2024',
   feats_catalog:[{name:'Resilient',source:'XPHB'}]};
 const choice=traitFlavourChoices(record,[],catalogs.flavours,['save:str','save:dex'])[0];
 assert.equal(choice.options.length,4);
 assert(choice.options.every(option=>!option.endsWith(':str')&&!option.endsWith(':dex')));
 const selected=save(record,choice,[choice.options.find(option=>option.endsWith(':wis'))]);
 const withProficiency=traitFlavourChoices(selected,[],catalogs.flavours,['save:str','save:dex','save:wis'])[0];
 assert(withProficiency.options.some(option=>option.endsWith(':wis')));
 assert.equal(withProficiency.selected.length,1);
});

test('selected flavour can grant a sense without preserving it on alternate variants',()=>{
 const feature={name:'Draconic Ancestry',
  origin_id:'feature:species|dragonborn (chromatic)|ftd|1|draconic ancestry',
  origin_key:'species|dragonborn (chromatic)|ftd'};
 const initial={rules_version:'2014',species:'Dragonborn (Chromatic)',species_source:'FTD',
  subrace:'Red',subrace_source:'FTD'};
 const choice=traitFlavourChoices(initial,[feature],catalogs.flavours)[0];
 const red='flavour:dragonborn:ftd:chromatic:red',blue='flavour:dragonborn:ftd:chromatic:blue';
 const senseCatalog={entries:[{id:'test:flavour:sense',
  granted_by:{kind:'flavour',ref:{category:'flavour',id:red}},
  benefit:{type:'sense',id:'test:flavour:sense',sense:{type:'truesight',range_feet:30}}}]};
 const selected=save(initial,choice,[red]);
 const projected=projectTraitFlavourBenefits(selected,[feature],{...catalogs,senseGrants:senseCatalog});
 assert.equal(projected.sense_grants.length,1);
 assert.equal(projected.sense_grants[0].origin_id,projected.flavour_traits[0].origin_id);
 assert.equal(calculateSenses(projected,[],{}).distances.truesight,30);
 const switched=save(selected,traitFlavourChoices(selected,[feature],catalogs.flavours)[0],[blue]);
 assert.equal(projectTraitFlavourBenefits(switched,[feature],{...catalogs,senseGrants:senseCatalog}).sense_grants.length,0);
});
