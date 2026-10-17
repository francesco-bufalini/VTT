import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {structuredSpellGrants,originChoiceMatches,applyOriginSpellChoice,originSpellId} from '../spell_selection.js';
import {calculateSheet} from '../sheet_rules.js';
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
