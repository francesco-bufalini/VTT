import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {racialPowerProjection,racialPowerSpellDefinitions,restTrainingPatch} from '../species_powers.js';
import {pendingCharacterChoices,savePendingChoice} from '../pending_choices.js';
import {powerRestSelections,powerRestChoicePatch} from '../trait_state_rules.js';
import {fixedProficiencies} from '../structured_effects.js';
import {calculateSheet} from '../sheet_rules.js';
const index=JSON.parse(readFileSync(new URL('../catalog/species_powers.json',import.meta.url),'utf8'));
const grants=JSON.parse(readFileSync(new URL('../catalog/proficiency_grants.json',import.meta.url),'utf8'));
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
 assert(choices.some(x=>x.id==='eladrin_training'));
 const rested={...selected,...powerRestChoicePatch(selected,'long_rest',calculated)};
 const summer={...rested,...savePendingChoice(rested,after,['summer'])};
 assert.equal(summer.trait_state_selection.eladrin_season,'summer');
 assert.equal(summer.rest_selection_available.eladrin_season,true);
 assert.equal(summer.rest_selection_available.eladrin_training,true,'changing season does not consume training');
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
test('all five latest pre-2024 racial rest proficiencies use their exact distinct slot types',()=>{
 const expected=[
  ['Astral Elf','AAG',['skill','weapon/tool']],
  ['Eladrin','MPMM',['weapon/tool','weapon/tool']],
  ['Sea Elf','MPMM',['weapon/tool','weapon/tool']],
  ['Shadar-Kai','MPMM',['weapon/tool','weapon/tool']],
  ['Githyanki','MPMM',['skill','weapon/tool']]
 ];
 for(const [name,source,kinds] of expected){
  const r=record(name,source),p=projection(r),choices=p.rest_choices.filter(x=>x.kind==='training');
  assert.equal(choices.length,1,name);
  const choice=choices[0];
  assert.deepEqual(choice.picks.map(row=>row.kinds.join('/')),kinds,name);
  const two=kinds[0]==='skill'?['skill:arcana','tool:smiths tools']:
    ['weapon:longsword','tool:smiths tools'];
  const allowed={skill:['arcana','perception'],weapon:['longsword','shortsword'],
    tool:['smiths tools','weavers tools'],unavailable:[]};
  const chosen={...r,...restTrainingPatch(r,choice,two,allowed)};
  assert.deepEqual(chosen.proficiency_choices.map(row=>row.kind),two.map(x=>x.split(':')[0]));
  assert(chosen.proficiency_choices.every(x=>x.rest_training_group===choice.group&&x.origin_id===choice.root_id));
  assert.equal(restTrainingPatch(chosen,choice,two,allowed).proficiency_choices.length,2);
  const calculated={features:featuresFor(chosen),racial_rest_choices:p.rest_choices};
  const rested={...chosen,...powerRestChoicePatch(chosen,'long_rest',calculated)};
  assert.deepEqual(rested.proficiency_choices,[],'old trance proficiencies expire at next long rest');
  const replacement=kinds[0]==='skill'?['skill:perception','tool:weavers tools']:
    ['weapon:shortsword','tool:weavers tools'];
  const updated={...rested,...restTrainingPatch(rested,choice,replacement,allowed)};
  assert.equal(updated.proficiency_choices.length,2,'reselection replaces, never accumulates');
  assert.deepEqual(updated.proficiency_choices.map(row=>row.key),replacement.map(x=>x.split(':')[1]));
  assert.throws(()=>restTrainingPatch(rested,choice,['tool:smiths tools','tool:smiths tools'],allowed),name==='Astral Elf'||name==='Githyanki'?/non valida/:/due volte/);
 }
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
test('rest expiration preserves permanent and unrelated proficiency choices',()=>{
 const r=record('Sea Elf'),choice=projection(r).rest_choices.find(x=>x.kind==='training');
 const withGrant={...r,proficiency_choices:[
   {kind:'skill',key:'arcana',origin_id:'background|phb|sage'},
   {kind:'weapon',key:'longsword',origin_id:choice.root_id,rest_training_group:choice.group}
 ]};
 const calc={features:featuresFor(withGrant),racial_rest_choices:projection(withGrant).rest_choices};
 const patch=powerRestChoicePatch(withGrant,'long_rest',calc);
 assert.deepEqual(patch.proficiency_choices.map(x=>x.key),['arcana']);
 assert.equal(patch.rest_selection_available[choice.group],true);
 assert.equal(powerRestChoicePatch(withGrant,'short_rest',calc).proficiency_choices,undefined);
});
test('temporary choices reject previously owned proficiencies and wrong source',()=>{
 const r=record('Eladrin'),choice=projection(r).rest_choices.find(x=>x.kind==='training');
 const allowed={skill:[],weapon:['longsword','shortsword'],tool:['smiths tools'],unavailable:['weapon:longsword']};
 assert.throws(()=>restTrainingPatch(r,choice,['weapon:longsword','tool:smiths tools'],allowed),/non possiedi/);
 assert.throws(()=>restTrainingPatch(r,choice,['skill:arcana','tool:smiths tools'],allowed),/non valida/);
});
test('existing racial training choices are projected on the character and old permanent grants survive',()=>{
 const r=record('Eladrin'),nativeRace=native.races.find(x=>x.name==='Eladrin'&&x.source==='MPMM');
 const c=calculateSheet(r,{speciesPowers:index,proficiencyGrants:grants,
   classMechanics:{races:[nativeRace],additional_spells:[]},
   originDetails:{races:{'eladrin|mpmm':nativeRace}}});
 assert(c.racial_rest_choices.some(x=>x.group==='eladrin_training'));
 assert(c.racial_rest_choices.some(x=>x.group==='eladrin_season'));
 assert(c.origin_spells.some(x=>x.spell_id==='vtt_eladrin_fey_step'));
 assert(c.trackers.some(x=>x.id==='race:mpmm:eladrin:fey_step:uses'));
 const choice=c.racial_rest_choices.find(x=>x.kind==='training');
 const chosen={...r,...restTrainingPatch(r,choice,['weapon:longsword','tool:smiths tools'],
   {weapon:['longsword'],tool:['smiths tools'],skill:[],unavailable:[]})};
 const prof=fixedProficiencies(chosen,grants,c.features);
 assert(prof.has('weapon:longsword'));
 assert(prof.has('tool:smiths tools'));
 const resolved=calculateSheet(chosen,{speciesPowers:index,proficiencyGrants:grants,
   classMechanics:{races:[nativeRace],additional_spells:[]},
   originDetails:{races:{'eladrin|mpmm':nativeRace}}});
 assert(resolved.proficiency_sources['weapon:longsword'].some(row=>
   row.id===choice.origin_id),'temporary proficiency belongs to Trance trait');
 const disabled={...chosen,origin_enabled:{[choice.origin_id]:false}};
 const muted=calculateSheet(disabled,{speciesPowers:index,proficiencyGrants:grants,
   classMechanics:{races:[nativeRace],additional_spells:[]},
   originDetails:{races:{'eladrin|mpmm':nativeRace}}});
 assert(!muted.proficiencies.includes('weapon:longsword'),
   'disabling the granting racial trait removes temporary proficiencies');
});

test('Githyanki Astral Knowledge grants exactly two temporary proficiencies, not duplicate permanent ones',()=>{
 const r=record('Githyanki'),features=featuresFor(r),powers=projection(r);
 const ordinary=pendingCharacterChoices(r,{features},{proficiencyGrants:grants,speciesPowers:index});
 assert(!ordinary.some(x=>x.kind==='proficiency'&&['skill','tool'].includes(x.proficiency_kind)),
   'Astral Knowledge must not create ordinary permanent racial skill/tool choices');
 assert(ordinary.some(x=>x.kind==='proficiency'&&x.proficiency_kind==='language'),
   'the unrelated MPMM language choice must remain');
 const before=fixedProficiencies(r,grants,features);
 assert(![...before.keys()].some(key=>key.startsWith('skill:')||key.startsWith('tool:')),
   'no automatic permanent Astral Knowledge proficiency');
 const choice=powers.rest_choices.find(x=>x.group==='githyanki_training');
 assert(choice&&choice.picks.length===2);
 const chosen={...r,...restTrainingPatch(r,choice,['skill:arcana','weapon:longsword'],
   {skill:['arcana'],weapon:['longsword'],tool:[],unavailable:[]})};
 const selected=fixedProficiencies(chosen,grants,features);
 assert(selected.has('skill:arcana')&&selected.has('weapon:longsword'));
 assert.equal([...selected.keys()].filter(k=>k.startsWith('skill:')||k.startsWith('weapon:')||k.startsWith('tool:')).length,2);
 const restored={...chosen,...powerRestChoicePatch(chosen,'long_rest',
   {features,racial_rest_choices:powers.rest_choices})};
 const expired=fixedProficiencies(restored,grants,features);
 assert(!expired.has('skill:arcana')&&!expired.has('weapon:longsword'));
 assert.equal(restored.rest_selection_available.githyanki_training,true);
});
