import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {projectSpeciesAttacks} from '../tools/species_mechanics.mjs';
import {calculateSheet} from '../sheet_rules.js';
import {pendingCharacterChoices,savePendingChoice} from '../pending_choices.js';
import {traitBenefitGroups} from '../trait_benefits.js';

const json=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const source=json('../../vtt/data/creature_references_5etools.json');
const catalog=json('../catalog/species_attacks.json');
const abilities={str:16,dex:12,con:14,int:10,wis:10,cha:10};
const record=(book)=>({
 kind:'character',species:'Aarakocra',species_source:book,
 species_id:'5etools:races:'+book.toLowerCase()+':aarakocra',
 abilities,level:1,inventory:[],rules_version:'2014'
});
const calculated=(book,changes={})=>calculateSheet({...record(book),...changes},{speciesAttacks:catalog});
const natural=sheet=>sheet.attacks.find(a=>a.id.startsWith('natural:'));

test('published source data generates deterministic typed natural strikes (never prose at runtime)',()=>{
 assert.deepEqual(projectSpeciesAttacks(source.races),catalog);
 assert.ok(catalog.races.length>=20);
 assert.equal(catalog.races.filter(r=>r.name==='Aarakocra').length,3);
 assert.ok(!catalog.races.some(r=>r.name==='Shifter (Longtooth)'&&r.source==='ERLW'),
   'conditional shifting attacks must not become permanent');
 assert.ok(!catalog.races.some(r=>r.name==='Naga'&&r.source==='PSA'),
   'complex multi-damage attacks need explicit modeling, not guesswork');
});

test('Aarakocra source variants grant correctly typed strikes, without using a hand',()=>{
 for(const [source,base,damage] of [
  ['DMG','1d4','1d4'],['EEPC','1d4','1d4 + 3'],['MPMM','1d6','1d6 + 3']]){
  const result=calculated(source);
  const attack=natural(result);
  assert.ok(attack,source+' natural attack missing');
  assert.equal(attack.damage_base_formula,base);
  assert.equal(attack.damage,damage);
  assert.equal(attack.damage_type,'taglienti');
  assert.equal(attack.ability,'str');
  assert.equal(attack.hit,5);
  assert.equal(attack.slot,'natural');
  assert.equal(attack.origin_name,'Tratto · Talons');
  assert.ok(result.attacks.some(a=>a.id==='unarmed'),'ordinary unarmed strike stays available');
 }
});

test('a source, or its precise Talons trait, can disable natural attacks without editing the catalog',()=>{
 const source='EEPC',origin='species|5etools:races:eepc:aarakocra|eepc';
 const feature='feature:'+origin+'|1|talons';
 assert.equal(natural(calculated(source,{origin_enabled:{[origin]:false}})),undefined);
 assert.equal(natural(calculated(source,{origin_enabled:{[feature]:false}})),undefined);
 assert.ok(natural(calculated(source)));
 const attack=natural(calculated(source));
 const groups=traitBenefitGroups({feature_origin:attack.origin_id,category:'razza',rank:2},
   record(source),{attacks:[attack]});
 assert.ok(groups.some(group=>group.type==='attacks'));
});

test('selected natural weapon belongs to its source, including non-Strength Dhampir bite',()=>{
 const dhampir=calculateSheet({...record('VRGR'),species:'Dhampir',
   species_id:'5etools:races:vrgr:dhampir'},
   {speciesAttacks:catalog});
 const bite=natural(dhampir);
 assert.ok(bite);
 assert.equal(bite.ability,'con');
 assert.equal(bite.hit,4);
 assert.equal(bite.damage,'1d4 + 2');
 assert.equal(bite.damage_type,'perforanti');
 assert.equal(natural(calculated('EEPC')).name,'Talons');
});

test('one-stat origin choice uses existing picker, provenance and disabling gates',()=>{
 const index={race:[{name:'Birdfolk',source:'BOOK',
   ability_choices:[{choose:{from:['dex','wis'],count:1,amount:2}}]}]};
 const character={...record('EEPC'),species:'Birdfolk',species_source:'BOOK',species_id:'',
   abilities:{...abilities,dex:10}};
 const catalogs={abilityGrants:index};
 const pending=pendingCharacterChoices(character,{},catalogs);
 const picker=pending.find(r=>r.id==='ability:race|book|birdfolk');
 assert.ok(picker);
 assert.deepEqual(picker.options,['dex','wis']);
 assert.equal(picker.remaining,1);
 const patch=savePendingChoice(character,picker,['dex']);
 assert.deepEqual(patch.origin_ability_choices,[{origin_id:picker.origin_id,ability:'dex'}]);
 const chosen=calculateSheet({...character,...patch},catalogs);
 assert.equal(chosen.abilities.dex.score,12);
 assert.equal(calculateSheet(character,catalogs).abilities.dex.score,10);
 assert.equal(calculateSheet({...character,...patch,species:'Other'},catalogs).abilities.dex.score,10);
 assert.equal(calculateSheet({...character,...patch,origin_enabled:{[picker.origin_id]:false}},catalogs).abilities.dex.score,10);
});
