import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {applyOriginSpellChoice,originChoiceMatches,sessionSpellEntries} from '../spell_selection.js';
import {savePendingChoice} from '../pending_choices.js';
import {spellCastPlan,recoveryPatch} from '../native_sheet.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const mechanics=read('../catalog/class_mechanics.json');
const audit=read('../../scripts/data/feat_spell_grants_2014.json').entries;
const catalogs={classMechanics:mechanics,originDetails:read('../../vtt/data/compendium_features_5etools.json'),
 classFeatures:read('../catalog/classes.json'),spells:mechanics.legacy_spells};
const root=(name,source)=>'feat|'+source.toLowerCase()+'|'+name.toLowerCase();
const feat=(name,source,extra={})=>({name,source,id:'test:'+source+':'+name,ability_choice:'wis',...extra});
const character=(name,source,level=9)=>({kind:'character',rules_version:'2014',class:'Wizard',class_source:'PHB',level,
 classes:[{name:'Wizard',source:'PHB',level}],feats_catalog:[feat(name,source)],
 abilities:{str:10,dex:12,con:14,int:16,wis:16,cha:14},
 spellcasting_section_abilities:{['origin:'+root(name,source)]:'wis'}});
const sheet=record=>calculateSheet(record,catalogs);
const byName=name=>catalogs.spells.find(row=>row.name.toLowerCase()===name.toLowerCase());
const pick=(record,choice,spell)=>({...record,...applyOriginSpellChoice(record,choice,spell,{ability:'wis'})});
const variant=(record,value)=>({...record,...savePendingChoice(record,sheet(record).origin_spell_variant_choices[0],[value])});
const selection=(record,grant)=>sessionSpellEntries(record,sheet(record),catalogs.spells).find(row=>row.grant_id===grant.id);

test('all 27 audited 2014 feat identities are packaged, source-qualified and disable cleanly',()=>{
 assert.equal(audit.length,27);
 for(const row of audit){
  assert(mechanics.additional_spells.some(value=>value.kind==='feat'&&value.name===row.name&&value.source===row.source&&value.audited_2014),row.name);
  let record=character(row.name,row.source);
  const first=sheet(record);
  if(first.origin_spell_variant_choices.length)record=variant(record,first.origin_spell_variant_choices[0].options[0]);
  const active=sheet(record);
  assert(active.origin_spells.length||active.origin_choices.length,row.name);
  const disabled=sheet({...record,origin_enabled:{[root(row.name,row.source)]:false}});
  assert.equal(disabled.origin_spells.length,0,row.name);assert.equal(disabled.origin_choices.length,0,row.name);
 }
});

test('High Sorcery binds both level-one picks to one moon and gives each its own daily use',()=>{
 let record=variant(character('Initiate of High Sorcery','DSotDQ'),'nuitari');
 let choice=sheet(record).origin_choices.find(row=>row.spell_options?.length===4);
 assert.equal(choice.count,2);assert(!originChoiceMatches(choice,byName('Shield')).matches);
 record=pick(record,choice,byName('Hex'));
 choice=sheet(record).origin_choices.find(row=>row.spell_options?.length===4);
 record=pick(record,choice,byName('Dissonant Whispers'));
 const calculated=sheet(record),grants=calculated.origin_spells.filter(row=>row.source_choice_id===choice.id);
 assert.equal(grants.length,2);assert.equal(new Set(grants.map(row=>row.tracker_id)).size,2);
 assert(grants.every(row=>row.slot_alternative&&row.spellcasting_ability==='wis'));
 assert(grants.every(row=>calculated.trackers.find(tracker=>tracker.id===row.tracker_id)?.max===1));
});

test('Strixhaven college choices never mix cantrips and first-level spell lists',()=>{
 let record=variant(character('Strixhaven Initiate','SCC'),'lorehold 1');
 let calculated=sheet(record);
 assert.deepEqual(calculated.origin_spells.map(row=>row.spell_id).sort(),[byName('Light').id,byName('Sacred Flame').id].sort());
 const choice=calculated.origin_choices[0];
 assert(originChoiceMatches(choice,byName('Shield')).matches);
 assert(!originChoiceMatches(choice,byName('Hex')).matches);
 record=pick(record,choice,byName('Sanctuary'));
 record=variant(record,'prismari 1');calculated=sheet(record);
 assert(!calculated.origin_spells.some(row=>row.spell_id===byName('Sanctuary').id));
 assert(calculated.origin_spells.some(row=>row.spell_id===byName('Fire Bolt').id));
 assert.equal(record.origin_spell_grants.length,1,'old explicit decisions remain stored without leaking into another variant');
});

test('Rune Shaper grants Comprehend Languages plus only explicitly selected runes',()=>{
 for(const [level,count] of [[1,1],[9,2],[17,3]]){
  const calculated=sheet(character('Rune Shaper','BGG',level));
  assert.deepEqual(calculated.origin_spells.map(row=>row.spell_id),[byName('Comprehend Languages').id]);
  assert.equal(calculated.origin_choices[0].count,count);
  assert.equal(calculated.origin_choices[0].spell_options.length,13);
 }
 let record=character('Rune Shaper','BGG');
 record=pick(record,sheet(record).origin_choices[0],byName('Burning Hands'));
 record=pick(record,sheet(record).origin_choices[0],byName('Fog Cloud'));
 const calculated=sheet(record),runes=calculated.origin_spells.filter(row=>row.requires_context);
 assert.equal(runes.length,2);assert.notEqual(runes[0].tracker_id,runes[1].tracker_id);
 assert.throws(()=>spellCastPlan(record,selection(record,runes[0]),0,calculated),/condizioni/);
 const cast=spellCastPlan(record,{...selection(record,runes[0]),context_confirmed:true},0,calculated);
 assert.equal(cast.patch.resource_tracker_spent[runes[0].tracker_id],1);
 assert.equal(cast.patch.resource_tracker_spent[runes[1].tracker_id],undefined);
 const old='5espell:'+root('Rune Shaper','BGG')+'|0|_|daily|1e|burning hands';
 const alreadyUsed=sheet({...record,resource_tracker_spent:{[old]:1}});
 assert.equal(alreadyUsed.trackers.find(row=>row.id===runes[0].tracker_id).spent,1);
});

test('Fey Teleportation recovers on a short rest and preserves the old daily tracker usage',()=>{
 const record=character('Fey Teleportation','XGE');
 const old='5espell:'+root('Fey Teleportation','XGE')+'|0|_|daily|1';
 const spent={...record,resource_tracker_spent:{[old]:1}},calculated=sheet(spent),grant=calculated.origin_spells[0];
 const tracker=calculated.trackers.find(row=>row.id===grant.tracker_id);
 assert.equal(tracker.recharge,'short_rest');assert.equal(tracker.spent,1);
 assert.throws(()=>spellCastPlan(spent,selection(spent,grant),0,calculated),/Risorsa/);
 const recovered={...spent,...recoveryPatch(spent,'short_rest',calculated.trackers,calculated)};
 assert.equal(sheet(recovered).trackers[0].spent,0);
});

test('Ritual Caster and ritual familiars have no daily tracker or instant/slot casting path',()=>{
 let record=variant(character('Ritual Caster','PHB'),'wizard spells');
 record=pick(record,sheet(record).origin_choices[0],byName('Find Familiar'));
 const calculated=sheet(record),grant=calculated.origin_spells[0],entry=selection(record,grant);
 assert(grant.ritual_only);assert(!calculated.trackers.some(row=>String(row.origin_id).includes('ritual caster')));
 assert.deepEqual(entry.time,[{number:70,unit:'minute'}]);
 assert.throws(()=>spellCastPlan(record,entry,0,calculated),/condizioni/);
 assert.throws(()=>spellCastPlan(record,{...entry,context_confirmed:true},0,calculated),/rituale/);
 const completed={...entry,context_confirmed:true,ritual_completed:true};
 assert.throws(()=>spellCastPlan(record,completed,1,calculated,'slot'),/rituale/);
 assert.deepEqual(spellCastPlan(record,completed,0,calculated).patch,{});
 for(const [name,source] of [['Strixhaven Mascot','SCC'],['Servo Crafting','PSK']]){
  const familiar=sheet(character(name,source));assert(familiar.origin_spells[0].ritual_only,name);
  assert(!familiar.trackers.some(row=>String(row.origin_id).includes(name.toLowerCase())));
 }
});

test('Spell Sniper accepts attack-roll cantrips and rejects save-only or utility spells',()=>{
 const record=variant(character('Spell Sniper','PHB'),'wizard spells'),choice=sheet(record).origin_choices[0];
 assert(originChoiceMatches(choice,byName('Fire Bolt')).matches);
 assert(!originChoiceMatches(choice,byName('Acid Splash')).matches);
 assert(!originChoiceMatches(choice,byName('Prestidigitation')).matches);
});

test('casting abilities inherit the chosen feat increase or prerequisite feat instead of an arbitrary score',()=>{
 for(const name of ['Fey Touched','Shadow Touched','Telekinetic','Telepathic']){
  const record=character(name,'TCE'),calculated=sheet(record);
  assert(calculated.origin_spells.every(row=>row.spellcasting_ability==='wis'),name);
  const old={...record,spellcasting_section_abilities:{['origin:'+root(name,'TCE')]:'int'}};
  assert(sessionSpellEntries(old,sheet(old),catalogs.spells).every(row=>row.caster_ability==='wis'),name);
  const pending=sheet({...record,feats_catalog:[{...record.feats_catalog[0],ability_choice:''}]});
  assert(pending.origin_spells.every(row=>row.casting_ability_unresolved),name);
 }
 const record=character('Adept of the Red Robes','DSotDQ');
 assert(sheet(record).origin_choices[0].casting_ability_unresolved);
 record.feats_catalog.push(feat('Initiate of High Sorcery','DSotDQ',{spell_variant:'Lunitari'}));
 record.spellcasting_section_abilities['origin:'+root('Initiate of High Sorcery','DSotDQ')]='cha';
 const choices=sheet(record).origin_choices.filter(row=>row.origin_parent_id===root('Adept of the Red Robes','DSotDQ'));
 assert.equal(choices[0].spellcasting_ability,'cha');
});

test('Divinely Favored uses the character alignment and does not mix alignment lists',()=>{
 const evil=sheet({...character('Divinely Favored','DSotDQ'),alignment:'Caotico malvagio'});
 const choice=evil.origin_choices.find(row=>row.filter.includes('level=1'));
 assert.equal(choice.filter,'level=1|class=warlock');
 assert.equal(evil.origin_spell_variant_choices.length,0);
 assert(!originChoiceMatches(choice,byName('Cure Wounds')).matches);
 assert(evil.origin_spells.find(row=>row.spell_id===byName('Augury').id).slot_alternative);
});

test('legacy merged choices migrate only after a class is selected and retain saved grant IDs',()=>{
 const record=character('Magic Initiate','PHB');
 record.origin_spell_grants=[{id:'old-choice-id',origin_id:root('Magic Initiate','PHB'),
  source_choice_id:'alternatives:'+root('Magic Initiate','PHB')+':known:_:0:at_will',
  spell_id:byName('Mage Hand').id,spellcasting_ability:'int',payment_mode:'free'}];
 assert.equal(sheet(record).origin_spells.length,0);
 const selected=variant(record,'wizard spells'),calculated=sheet(selected);
 assert.equal(calculated.origin_spells[0].id,'old-choice-id');
 assert.equal(calculated.origin_choices.find(row=>row.count===2).remaining,1);
});
