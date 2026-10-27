import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {structuredSpellGrants,originChoiceMatches,applyOriginSpellChoice,originSpellId,sessionSpellEntries} from '../spell_selection.js';
import {calculateSheet} from '../sheet_rules.js';
import {spellCastPlan} from '../native_sheet.js';
import {collectTraitRows,withGrantedSpellPreviews} from '../trait_projection.js';
import {traitBenefitGroups} from '../trait_benefits.js';
const mechanics=JSON.parse(readFileSync(new URL('../catalog/class_mechanics.json',import.meta.url),'utf8'));
const spells=[
 {id:'phb2014_thaumaturgy',name:'Thaumaturgy',source:'PHB',level:0,classes:['Cleric']},
 {id:'phb2014_hellish_rebuke',name:'Hellish Rebuke',source:'PHB',level:1,classes:['Warlock']},
 {id:'phb2014_darkness',name:'Darkness',source:'PHB',level:2,classes:['Sorcerer','Warlock','Wizard']},
 {id:'darkness',name:'Darkness',source:'XPHB',level:2,classes:['Warlock','Wizard']},
 {id:'phb2014_misty_step',name:'Misty Step',source:'PHB',level:2,school:'Conjuration'},
 {id:'misty_step',name:'Misty Step',source:'XPHB',level:2,school:'Conjuration'},
 {id:'phb2014_charm_person',name:'Charm Person',source:'PHB',level:1,school:'Enchantment',classes:['Bard','Wizard']},
 {id:'phb2014_light',name:'Light',source:'PHB',level:0,school:'Evocation',classes:['Bard','Cleric','Wizard']},
 {id:'phb2014_mage_hand',name:'Mage Hand',source:'PHB',level:0,school:'Conjuration',classes:['Wizard']},
 {id:'phb2014_shield',name:'Shield',source:'PHB',level:1,school:'Abjuration',classes:['Wizard']}
];
const record=extra=>({kind:'character',rules_version:'2014',level:5,abilities:{int:16,wis:12,cha:14},...extra});
const project=c=>structuredSpellGrants(c,mechanics.additional_spells,spells);
test('native 2014 spell IDs, character level gates and stable daily counters are retained',()=>{
 const base=record({species:'Tiefling',species_source:'PHB'});
 const level1=project({...base,level:1}),level3=project({...base,level:3}),level5=project(base);
 assert.deepEqual(level1.grants.map(g=>g.spell_id),['phb2014_thaumaturgy']);
 assert.equal(level3.grants.length,2);assert.equal(level5.grants.length,3);
 assert.ok(level5.trackers.some(t=>t.id==='5espell:race|phb|tiefling|0|3|daily|1'&&t.max===1&&t.recharge==='long_rest'));
 assert.equal(originSpellId('darkness|xphb','2014',spells),'darkness');
 assert.equal(originSpellId('darkness','2014',spells),'phb2014_darkness');
 assert.equal(project({...base,origin_enabled:{'race|phb|tiefling':false}}).grants.length,0);
});
test('multi-block feats merge alternative choices and counters instead of granting every list',()=>{
 const out=project(record({feats_catalog:[{name:'Magic Initiate',source:'PHB'}]}));
 assert.equal(out.grants.length,0);
 assert.equal(out.trackers.length,1);
 assert.equal(out.choices.length,2);
 const cantrips=out.choices.find(c=>c.count===2),leveled=out.choices.find(c=>c.count===1);
 assert.equal(cantrips.filters.length,6);
 assert.equal(leveled.tracker_id,'5espell:feat|phb|magic initiate|0|_|daily|1');
 assert.equal(cantrips.spellcasting_ability,'');
 assert.equal(originChoiceMatches(cantrips,spells.find(s=>s.id==='phb2014_light')).matches,true);
 assert.equal(originChoiceMatches(cantrips,spells.find(s=>s.id==='phb2014_shield')).matches,false);
});
test('choice writes are explicit, bounded and preserve resource consumption and unknown fields',()=>{
 const c=record({feats_catalog:[{name:'Magic Initiate',source:'PHB'}],resource_tracker_spent:{keep:2},custom:{retain:true}});
 const choice=project(c).choices.find(c=>c.count===2),light=spells.find(s=>s.id==='phb2014_light'),hand=spells.find(s=>s.id==='phb2014_mage_hand');
 assert.throws(()=>applyOriginSpellChoice(c,choice,light),/caratteristica/);
 const first=applyOriginSpellChoice(c,choice,light,{ability:'int'});
 assert.throws(()=>applyOriginSpellChoice({...c,...first},choice,light,{ability:'int'}),/già scelto/);
 const second=applyOriginSpellChoice({...c,...first},choice,hand,{ability:'int'});
 assert.throws(()=>applyOriginSpellChoice({...c,...second},choice,light,{ability:'int'}),/completa/);
 assert.equal(c.origin_spell_grants,undefined);assert.deepEqual(c.resource_tracker_spent,{keep:2});
 const computed=calculateSheet({...c,...second},{classMechanics:mechanics,spells});
 assert.equal(computed.origin_choices.find(ch=>ch.id===choice.id).remaining,0);
 assert.equal(computed.origin_spells.length,2);
});
test('limited Fey Touched choices use different each-spell trackers and do not broaden unsupported filters',()=>{
 const out=project(record({feats_catalog:[{name:'Fey Touched',source:'TCE'}]}));
 assert.equal(out.grants.length,1);assert.equal(out.grants[0].spell_id,'phb2014_misty_step');
 assert.equal(out.trackers.length,2);assert.notEqual(out.trackers[0].id,out.trackers[1].id);
 assert.equal(originChoiceMatches(out.choices[0],spells.find(s=>s.name==='Charm Person')).matches,true);
 assert.equal(originChoiceMatches(out.choices[0],spells.find(s=>s.name==='Shield')).matches,false);
 assert.deepEqual(originChoiceMatches({filter:'unsupported=value'},spells[0]),{matches:false,supported:false});
});
test('prepared and expanded spell lists never create free entitlements; no lineage is guessed',()=>{
 const sample=[{kind:'race',name:'Test',source:'TST',blocks:[{prepared:{_ :['shield']},expanded:{_ :['shield']},known:{_ :['shield']}}]}];
 assert.equal(structuredSpellGrants(record({species:'Test',species_source:'TST'}),sample,[{id:'shield',name:'Shield',level:1}]).grants.length,0);
 const elf=project(record({rules_version:'2024',species:'Elf',species_source:'XPHB'}));
 assert.equal(elf.grants.length,0);assert.ok(elf.warnings.some(w=>w.includes('discendenza')));
});
test('casting readouts include native spell_attack equipment bonuses and legacy aliases',()=>{
 const c=record({class:'Wizard',level:5,inventory:[{id:'staff',name:'Staff',type:'M',damage:'1d6',quantity:1,equipped_slots:['main'],bonus_spell_attack:'+2'}],formula_bonuses:[{target:'spell_hit',expression:'1'}]});
 assert.equal(calculateSheet(c,{classMechanics:mechanics}).values['casting_hit:int'],9);
 const legacy=calculateSheet(record({inventory:[{id:'armor',type:'HA',ac:16,equipped_slots:['body']}]}));
 assert.equal(legacy.stats.armor_class,16,'old native items default to one owned copy');
});


test('spellcasting ability selection follows the source shown in PWA powers',()=>{
 const creature={
  prepared_spells:[{id:'wizard_spell',name:'Wizard spell',level:1,casting_classes:['wizard']}],
  spellcasting_ability:'int',
  spellcasting_section_abilities:{wizard:'cha','origin:feat':'wis'}
 };
 const calculated={
  casting_classes:[{id:'wizard',name:'Wizard',ability:'int',max_level:3}],
  origin_spells:[{id:'feat_grant',origin_id:'feat',origin_name:'Feat',spell_id:'feat_spell',spellcasting_ability:'cha'}]
 };
 const rows=sessionSpellEntries(creature,calculated,[
  {id:'wizard_spell',name:'Wizard spell',level:1,classes:['Wizard']},
  {id:'feat_spell',name:'Feat spell',level:1}
 ]);
 assert.equal(rows.find(s=>s.id==='wizard_spell').caster_ability,'cha');
 assert.equal(rows.find(s=>s.id==='feat_spell').caster_ability,'wis');
});

test('always-prepared origin spells use ordinary slots unless a cost is explicitly configured',()=>{
 const base=record({origin_spell_grants:[
  {id:'feature:known',origin_id:'feature:cleric',origin_name:'Domain Spells',
   spell_id:'phb2014_shield',mode:'prepared',spellcasting_ability:'wis'},
  {id:'feature:innate',origin_id:'feature:elf',origin_name:'Innate',
   spell_id:'phb2014_mage_hand',mode:'innate',spellcasting_ability:'int'}
 ]});
 const computed=calculateSheet(base,{classMechanics:mechanics,spells});
 assert.equal(computed.origin_spells.find(spell=>spell.id==='feature:known').payment_mode,'slot');
 assert.equal(computed.origin_spells.find(spell=>spell.id==='feature:innate').payment_mode,'free');
 const cantrip={...base,origin_spell_grants:[
   {...base.origin_spell_grants[0],spell_id:'phb2014_light'},
   base.origin_spell_grants[1]
 ]};
 assert.equal(calculateSheet(cantrip,{classMechanics:mechanics,spells})
   .origin_spells.find(spell=>spell.id==='feature:known').payment_mode,'free');
 const overridden=calculateSheet({...base,origin_spell_configs:{'feature:known':{payment_mode:'free'}}},
   {classMechanics:mechanics,spells});
 assert.equal(overridden.origin_spells.find(spell=>spell.id==='feature:known').payment_mode,'free');
});

test('Aarakocra Wind Caller unlocks at level three and owns its daily Gust of Wind counter',async()=>{
 const description=JSON.parse(readFileSync(new URL('../../vtt/data/compendium_features_5etools.json',import.meta.url),'utf8'))
   .races['aarakocra|mpmm'];
 const trait=description.entries.find(entry=>entry.name==='Wind Caller');
 assert.equal(trait.level,3);
 assert.equal(trait.requirements.min_level,3);
 const speciesId='5etools:races:mpmm:aarakocra';
 const creature=record({species:'Aarakocra',species_source:'MPMM',species_id:speciesId});
 const originKey='species|'+speciesId+'|mpmm';
 const ownerId='feature:'+originKey+'|'+originKey+'|3|wind caller';
 const features=[{name:'Wind Caller',origin_key:originKey,origin_id:ownerId,level:3}];
 const spell=[{id:'phb2014_gust_of_wind',name:'Gust of Wind',level:2,source:'PHB'}];
 const project=level=>structuredSpellGrants({...creature,level},
  mechanics.additional_spells,spell,features);
 assert.equal(project(1).grants.length,0);
 assert.equal(project(2).trackers.length,0);
 const result=project(3);
 assert.equal(result.grants.length,1);
 assert.equal(result.grants[0].spell_id,'phb2014_gust_of_wind');
 assert.equal(result.grants[0].origin_id,ownerId);
 assert.equal(result.grants[0].granting_trait,'Wind Caller');
 const tracker=result.trackers[0];
 assert.equal(tracker.id,'5espell:race|mpmm|aarakocra|0|3|daily|1');
 assert.equal(tracker.max,1);
 assert.equal(tracker.recharge,'long_rest');
 assert.equal(tracker.origin_id,ownerId);
 assert.equal(project(3).trackers[0].id,tracker.id,'usage must keep a stable persisted ID');
 const provider={entries:async category=>category==='races'?
   [{id:speciesId,name:'Aarakocra',source:'MPMM',entries:description.entries}]:[],
  detail:async(_category,row)=>row};
 const first=await collectTraitRows({...creature,level:1},{},provider);
 assert(!first.some(row=>row.name==='Wind Caller'));
 const listed=await collectTraitRows({...creature,level:3},{features},provider);
 const preview=withGrantedSpellPreviews(listed,result.grants,spell);
 const wind=preview.find(row=>row.name==='Wind Caller');
 assert.deepEqual(wind.granted_spells.map(item=>item.name),['Gust of Wind']);
 assert(traitBenefitGroups(wind,creature,{trackers:result.trackers}).some(group=>
   group.type==='resources'&&group.items.some(item=>item.label.includes('Wind Caller'))));
 const overview=preview.find(row=>row.name==='Descrizione · Aarakocra');
 assert(!overview.granted_spells.length);
 assert(!traitBenefitGroups(overview,creature,{trackers:result.trackers}).some(group=>group.type==='resources'));
});

test('a separate racial casting benefit binds to its own named trait',()=>{
 const creature=record({species:'Aasimar',species_source:'DMG'});
 const trait={name:'Celestial Legacy',origin_key:'species|aasimar|dmg',origin_id:'feature:celestial'};
 const out=structuredSpellGrants(creature,mechanics.additional_spells,spells,[trait]);
 const cantrip=out.grants.find(g=>g.spell_id==='phb2014_light');
 assert.equal(cantrip?.origin_id,'feature:celestial');
 assert.equal(cantrip?.granting_trait,'Celestial Legacy');
});

test('Wind Caller can spend its daily tracker OR an ordinary/Pact slot without duplicated spells',()=>{
 const rules=JSON.parse(readFileSync(new URL('../catalog/spell_grant_rules.json',import.meta.url),'utf8')).rules;
 const speciesId='5etools:races:mpmm:aarakocra';
 const owner='feature:wind_caller';
 const c=record({species:'Aarakocra',species_source:'MPMM',species_id:speciesId,level:3,
   resource_tracker_spent:{},spell_slots_spent:Array(10).fill(0),pact_slots_spent:0});
 const features=[{name:'Wind Caller',origin_id:owner,origin_key:'species|'+speciesId+'|mpmm',level:3}];
 const spell=[{id:'phb2014_gust_of_wind',name:'Gust of Wind',level:2,source:'PHB'}];
 const result=structuredSpellGrants(c,mechanics.additional_spells,spell,features,rules);
 assert.equal(result.grants.length,1);
 const grant={...result.grants[0],payment_mode:'tracker'};
 assert.equal(grant.slot_alternative,true);
 assert.deepEqual(grant.spellcasting_ability_options,['int','wis','cha']);
 assert.equal(grant.origin_id,owner);
 const counters=result.trackers.map(t=>({...t,spent:0}));
 const calc={origin_spells:[grant],trackers:counters,features:[],casting_classes:[],
   spell_slots:Array.from({length:9},(_,index)=>({level:index+1,total:index===1?2:0,spent:0})),
   pact_slots:{level:2,total:1,spent:0},
   values:{'casting_dc:wis':13,'casting_hit:wis':5}};
 const selection={id:grant.spell_id,grant_id:grant.id,level:2,caster_ability:'wis'};
 const tracker=spellCastPlan(c,selection,0,calc,'auto');
 assert.equal(tracker.patch.resource_tracker_spent[counters[0].id],1);
 assert.equal(tracker.patch.spell_slots_spent,undefined);
 const slot=spellCastPlan(c,selection,2,calc,'slot');
 assert.equal(slot.patch.spell_slots_spent[2],1);
 assert.equal(slot.patch.resource_tracker_spent,undefined);
 const pact=spellCastPlan(c,selection,2,calc,'pact');
 assert.equal(pact.patch.pact_slots_spent,1);
 const exhausted={...c,resource_tracker_spent:{[counters[0].id]:1}};
 assert.throws(()=>spellCastPlan(exhausted,selection,0,calc,'auto'),/Risorsa insufficiente/);
 assert.equal(spellCastPlan(exhausted,selection,2,calc,'slot').patch.spell_slots_spent[2],1);
 const noAlternate={...calc,origin_spells:[{...grant,slot_alternative:false}]};
 assert.throws(()=>spellCastPlan(c,selection,2,noAlternate,'slot'),/non permette/);
 const legacy=structuredSpellGrants(record({species:'Tiefling',species_source:'PHB',level:5}),
   mechanics.additional_spells,spells,[],rules);
 assert(legacy.grants.every(g=>!g.slot_alternative));
});

test('MPMM Aasimar Light Bearer is a Charisma cantrip and never spends spell slots',()=>{
 const rules=JSON.parse(readFileSync(new URL('../catalog/spell_grant_rules.json',import.meta.url),'utf8')).rules;
 const creature=record({species:'Aasimar',species_source:'MPMM',
   species_id:'5etools:races:mpmm:aasimar',
   spellcasting_section_abilities:{}});
 const derived=calculateSheet(creature,{classMechanics:mechanics,spells,spellGrantRules:rules});
 const light=derived.origin_spells.find(grant=>grant.spell_id==='phb2014_light');
 assert(light,'Light Bearer grant exists');
 assert.equal(light.cantrip,true);
 assert.equal(light.payment_mode,'free');
 assert.equal(light.spellcasting_ability,'cha');
 assert.equal(light.tracker_id,'');
 const choice=sessionSpellEntries(creature,derived,spells).find(row=>row.grant_id===light.id);
 assert.equal(choice.caster_ability,'cha');
 const plan=spellCastPlan(creature,choice,0,derived,'auto');
 assert.deepEqual(plan.patch,{});
 const older={...derived,origin_spells:[{...light,payment_mode:'slot',cantrip:false}]};
 assert.deepEqual(spellCastPlan(creature,choice,0,older,'auto').patch,{},
   'legacy erroneously slot-marked racial cantrips still cast for free');
 assert.throws(()=>spellCastPlan(creature,choice,1,derived,'slot'),/trucchetto/i);
});
