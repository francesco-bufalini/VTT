import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {pendingCharacterChoices} from '../pending_choices.js';
import {collectTraitRows,withGrantedSpellPreviews} from '../trait_projection.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const mechanics=read('../catalog/class_mechanics.json');
const details=read('../../vtt/data/compendium_features_5etools.json');
const catalogs={classMechanics:mechanics,originDetails:details,spells:mechanics.legacy_spells};
const record={kind:'character',rules_version:'2014',class:'Wizard',class_source:'PHB',level:4,
 classes:[{name:'Wizard',source:'PHB',level:4}],
 feats_catalog:[{id:'5etools:feats:bmt:cartomancer',name:'Cartomancer',source:'BMT'}],
 abilities:{str:10,dex:10,con:10,int:16,wis:10,cha:10}};

test('Cartomancer grants Prestidigitation from Card Tricks without slots, trackers or a casting-stat choice',async()=>{
 const sheet=calculateSheet(record,catalogs);
 const trait=sheet.features.find(row=>row.name==='Card Tricks');
 assert(trait);
 const spell=sheet.origin_spells.find(row=>row.spell_id==='phb2014_prestidigitation');
 assert(spell);assert.equal(spell.origin_id,trait.origin_id);assert.equal(spell.granting_trait,'Card Tricks');
 assert.equal(spell.id,'5etools:feat|bmt|cartomancer|phb2014_prestidigitation|known|_');
 assert.equal(spell.mode,'known');assert.equal(spell.payment_mode,'free');assert.equal(spell.tracker_id,'');
 assert.equal(spell.casting_ability_not_required,true);
 assert(!pendingCharacterChoices(record,sheet,catalogs).some(row=>row.kind==='casting_ability'&&row.origin_id===trait.origin_id));
 const providers={entries:async category=>category==='feats'?[{name:'Cartomancer',source:'BMT',
  ...details.feats['cartomancer|bmt']}]:[],detail:async(_category,row)=>row};
 const cards=withGrantedSpellPreviews(await collectTraitRows(record,sheet,providers),sheet.origin_spells,catalogs.spells);
 assert(cards.find(row=>row.name==='Card Tricks').granted_spells.some(row=>row.id===spell.spell_id));
 assert(!cards.find(row=>row.name==='Hidden Ace').granted_spells.length);
});

test('Card Tricks stops granting the cantrip when the trait or Cartomancer feat is disabled',()=>{
 const sheet=calculateSheet(record,catalogs),trait=sheet.features.find(row=>row.name==='Card Tricks');
 for(const changed of [
  {...record,origin_enabled:{[trait.origin_id]:false}},
  {...record,trait_enabled:{[trait.key]:false}},
  {...record,feats_catalog:[{...record.feats_catalog[0],disabled:true}]},
  {...record,feats_catalog:[{...record.feats_catalog[0],source:'XPHB'}]},
 ])assert(!calculateSheet(changed,catalogs).origin_spells.some(row=>row.spell_id==='phb2014_prestidigitation'));
});
