import {speciesPowerTestIndex} from './species_power_test_fixture.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {racialPowerProjection,racialPowerSpellDefinitions} from '../species_powers.js';
import {proficiencyGrantModels,proficiencyGrantOptions,proficiencyGrantPatch} from '../proficiency_grant.js';
import {pendingCharacterChoices,savePendingChoice} from '../pending_choices.js';
import {powerRestSelections,powerRestChoicePatch} from '../trait_state_rules.js';
import {fixedProficiencies} from '../structured_effects.js';
import {calculateSheet} from '../sheet_rules.js';
const index=speciesPowerTestIndex();
const grants=JSON.parse(readFileSync(new URL('../catalog/proficiency_grants.json',import.meta.url),'utf8'));
const proficiencyBenefits=JSON.parse(readFileSync(new URL('../../vtt/enrichment/benefits/proficiency_grant.json',import.meta.url),'utf8'));
const native=JSON.parse(readFileSync(new URL('../../vtt/data/creature_references_5etools.json',import.meta.url),'utf8'));
const rule=(name,source)=>index.races.find(r=>r.name===name&&r.source===source);
const record=(name,source='MPMM')=>({id:'test-'+name,kind:'character',rules_version:'2014',
 name:'Hero',species:name,species_source:source,
 species_id:'5etools:races:'+source.toLowerCase()+':'+name.toLowerCase().replace(/\s+/g,'-'),
 abilities:{str:10,dex:10,con:12,int:12,wis:14,cha:10},
 level:5,current_hp:10,max_hp_base:20,
 proficiency_choices:[],origin_enabled:{},trait_state_selection:{},rest_selection_available:{}});
const featuresFor=(r)=>['Fey Step','Trance','Starlight Step','Astral Trance','Astral Knowledge']
 .map(name=>({name,origin_key:'species|'+r.species_id+'|'+r.species_source.toLowerCase(),
   key:'species|'+r.species_id+'|'+r.species_source.toLowerCase()+'|1|'+name.toLowerCase(),
   origin_id:'feature:species|'+r.species_id+'|'+r.species_source.toLowerCase()+'|1|'+name.toLowerCase()}));
const projection=(r)=>racialPowerProjection(r,index,featuresFor(r));
test('Eladrin Fey Step reuses the Starlight Step teleport engine, PB uses and bonus action',()=>{
 const r=record('Eladrin'),v=projection(r);
 assert.equal(v.origin_spells.length,1);
 assert.equal(v.origin_spells[0].spell_id,'vtt_eladrin_fey_step');
 assert.equal(v.origin_spells[0].payment_mode,'tracker');
 assert.equal(v.trackers[0].max,3);
 assert.equal(v.trackers[0].recharge,'long_rest');
 const definition=racialPowerSpellDefinitions(index,r).find(x=>x.id==='vtt_eladrin_fey_step');
 assert.equal(definition.target_mode,'teleport_self');
 assert.equal(definition.targeting_template_spell_id,'phb2014_misty_step');
 assert.equal(definition.teleport_range_feet,30);
 assert.equal(definition.time[0].unit,'bonus');
 assert.equal(definition.condition_inflict,undefined);
 assert.equal(projection({...r,rules_version:'2024'}).origin_spells.length,0);
});
test('season is a real racial picker, source qualified with descriptive rest guidance',()=>{
 const r=record('Eladrin'),catalogs={speciesPowers:index,proficiencyGrants:grants};
 const first=pendingCharacterChoices(r,{},catalogs).find(x=>x.kind==='racial_option');
 assert.equal(first.label,'Stagione');
 assert.deepEqual(first.options,['autumn','winter','spring','summer']);
 assert.equal(first.remaining,1);
 const selected={...r,...savePendingChoice(r,first,['winter'])};
 const after=pendingCharacterChoices(selected,{},catalogs).find(x=>x.kind==='racial_option');
 assert.deepEqual(after.selected,['winter']);
 assert.equal(after.remaining,0);
 assert.equal(savePendingChoice(selected,after,['summer']).trait_state_selection.eladrin_season,'summer');
 const calculated={features:featuresFor(selected),racial_rest_choices:projection(selected).rest_choices};
 const choices=powerRestSelections(selected,calculated);
 assert(choices.some(x=>x.id==='eladrin_season'));
 const rested={...selected,...powerRestChoicePatch(selected,'long_rest',calculated)};
 const summer={...rested,...savePendingChoice(rested,after,['summer'])};
 assert.equal(summer.trait_state_selection.eladrin_season,'summer');
 assert.equal(summer.rest_selection_available.eladrin_season,true);
 assert.throws(()=>savePendingChoice({...r,species:'Shadar-Kai'},first,['winter']),/Stagione/);
});
test('Fey Step displays the original selected seasonal effect only after level three',()=>{
 const nativeRace=native.races.find(x=>x.name==='Eladrin'&&x.source==='MPMM');
 const details={races:{'eladrin|mpmm':nativeRace}};
 const options=nativeRace.entries.find(x=>x.name==='Fey Step').entries
  .find(x=>x.type==='list').items;
 for(const season of ['autumn','winter','spring','summer']){
  const selected={...record('Eladrin'),trait_state_selection:{eladrin_season:season}};
  const show=racialPowerSpellDefinitions(index,selected,details).find(x=>x.id==='vtt_eladrin_fey_step');
  assert.match(show.description,/As a bonus action, you can magically teleport/);
  const chosen=options.find(x=>x.name.toLowerCase()===season);
  assert(show.description.includes(chosen.entry.slice(0,45)));
  for(const other of options.filter(x=>x!==chosen))
   assert(!show.description.includes(other.entry.slice(0,45)));
  const young=racialPowerSpellDefinitions(index,{...selected,level:2},details)
   .find(x=>x.id==='vtt_eladrin_fey_step');
  assert(!young.description.includes(chosen.entry.slice(0,45)));
 }
});
test('five species trait grants have exact typed slot filters and source-qualified owners',()=>{
 const expected=[
  ['Astral Elf','AAG',['skill','weapon/tool']],
  ['Eladrin','MPMM',['weapon/tool','weapon/tool']],
  ['Sea Elf','MPMM',['weapon/tool','weapon/tool']],
  ['Shadar-Kai','MPMM',['weapon/tool','weapon/tool']],
  ['Githyanki','MPMM',['skill','weapon/tool']]
 ];
 assert.equal(proficiencyBenefits.benefit_type,'proficiency_grant');
 assert.equal(proficiencyBenefits.entries.filter(row=>row.granted_by?.ref?.category==='species_trait').length,5);
 for(const [name,source,filters] of expected){
  const r=record(name,source),models=proficiencyGrantModels(r,{features:featuresFor(r)},proficiencyBenefits);
  assert.equal(models.length,1,name);
  assert.deepEqual(models[0].slots.map(slot=>slot.filter.kinds.join('/')),filters,name);
  assert.equal(models[0].trigger,'long_rest');
  assert.equal(models[0].limit,2);
  assert.equal(projection(r).rest_choices.some(row=>row.kind==='training'),false,
    'no legacy duplicate training projection');
 }
 const legacy=JSON.parse(readFileSync(new URL('../catalog/species_powers.json',import.meta.url),'utf8'));
 assert(legacy.races.every(race=>!race.rest_training));
});

test('Fey Step uses the original source text for the chosen season when available',()=>{
 const r={...record('Eladrin'),trait_state_selection:{eladrin_season:'summer'}};
 const nativeRace=native.races.find(x=>x.name==='Eladrin'&&x.source==='MPMM');
 const definition=racialPowerSpellDefinitions(index,r,{races:{'eladrin|mpmm':nativeRace}})
   .find(x=>x.id==='vtt_eladrin_fey_step');
 assert.match(definition.description,/Immediately after you use your Fey Step/);
 assert.match(definition.description,/fire damage equal to your proficiency bonus/);
 assert.doesNotMatch(definition.description,/\\{@damage/);
});
test('selected proficiencies persist across a rest and can be replaced at any time',()=>{
 const r=record('Sea Elf'),model=proficiencyGrantModels(r,{features:featuresFor(r)},proficiencyBenefits)[0];
 const allowed={index:grants,unavailable:[]};
 const first={...r,...proficiencyGrantPatch(r,model,['weapon:longsword',"tool:smith's tools"],allowed)};
 assert.deepEqual(first.proficiency_choices.map(row=>row.kind),['weapon','tool']);
 assert(first.proficiency_choices.every(row=>
   row.rest_training_group===model.id&&row.proficiency_grant_id===model.id&&
   row.granting_feature_origin_id===model.origin_id));
 const afterRest={...first,...powerRestChoicePatch(first,'long_rest',
  {features:featuresFor(first),proficiency_grants:[model]})};
 assert.equal(afterRest.rest_selection_available[model.id],true);
 assert.equal(afterRest.proficiency_choices.length,2);
 const updatedModel=proficiencyGrantModels(afterRest,{features:featuresFor(afterRest)},proficiencyBenefits)[0];
 const updated={...afterRest,...proficiencyGrantPatch(afterRest,updatedModel,
  ['weapon:shortsword',"tool:weaver's tools"],allowed)};
 assert.deepEqual(updated.proficiency_choices.map(row=>row.key),['shortsword',"weaver's tools"]);
 assert.equal(updated.proficiency_choices.length,2);
 assert.throws(()=>proficiencyGrantPatch(afterRest,model,
  ['weapon:longsword','weapon:longsword'],allowed),/due volte/);
});

test('filters, unavailable proficiencies and exact trait ownership are enforced',()=>{
 const r=record('Astral Elf','AAG'),model=proficiencyGrantModels(r,{features:featuresFor(r)},proficiencyBenefits)[0];
 const index=grants;
 assert(proficiencyGrantOptions(model.slots[0],r,index).some(row=>row.id==='skill:arcana'));
 assert(!proficiencyGrantOptions(model.slots[0],r,index).some(row=>row.id==='weapon:longsword'));
 assert.throws(()=>proficiencyGrantPatch(r,model,
  ['weapon:longsword',"tool:smith's tools"],{index,unavailable:[]}),/non valida/);
 assert.throws(()=>proficiencyGrantPatch(r,model,
  ['skill:arcana',"tool:smith's tools"],{index,unavailable:['skill:arcana']}),/non possiedi/);
 const chosen={...r,...proficiencyGrantPatch(r,model,
  ['skill:arcana','weapon:longsword'],{index,unavailable:[]})};
 const active=fixedProficiencies(chosen,grants,featuresFor(chosen));
 assert(active.has('skill:arcana')&&active.has('weapon:longsword'));
 const disabled={...chosen,origin_enabled:{[model.origin_id]:false}};
 assert(!fixedProficiencies(disabled,grants,featuresFor(disabled)).has('weapon:longsword'));
 const other=record('Eladrin');
 assert.equal(proficiencyGrantModels(other,{features:featuresFor(other)},
  { ...proficiencyBenefits,entries:[proficiencyBenefits.entries[0]]}).length,0);
});

test('legacy saved training slots remain effective without automatic expiration',()=>{
 const r=record('Githyanki'),features=featuresFor(r),model=proficiencyGrantModels(r,{features},proficiencyBenefits)[0];
 const ordinary=pendingCharacterChoices(r,{features},{proficiencyGrants:grants,speciesPowers:index});
 assert(!ordinary.some(x=>x.kind==='proficiency'&&['skill','tool'].includes(x.proficiency_kind)));
 assert(ordinary.some(x=>x.kind==='proficiency'&&x.proficiency_kind==='language'));
 const before=fixedProficiencies(r,grants,features);
 assert(!before.has('skill:arcana'));
 const stored={...r,proficiency_choices:[
  {kind:'skill',key:'arcana',origin_id:model.root_id,rest_training_group:model.id,
   granting_feature_origin_id:model.origin_id},
  {kind:'weapon',key:'longsword',origin_id:model.root_id,rest_training_group:model.id,
   granting_feature_origin_id:model.origin_id}
 ]};
 const current=proficiencyGrantModels(stored,{features},proficiencyBenefits)[0];
 assert.equal(current.selected.length,2);
 const active=fixedProficiencies(stored,grants,features);
 assert(active.has('skill:arcana')&&active.has('weapon:longsword'));
 const rested={...stored,...powerRestChoicePatch(stored,'long_rest',
   {features,proficiency_grants:[current]})};
 assert(fixedProficiencies(rested,grants,features).has('skill:arcana'));
 const changed={...rested,...proficiencyGrantPatch(rested,current,
   ['skill:perception',"tool:smith's tools"],{index:grants,unavailable:[]})};
 assert(!fixedProficiencies(changed,grants,features).has('skill:arcana'));
 assert(fixedProficiencies(changed,grants,features).has('skill:perception'));
});
