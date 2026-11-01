import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {projectSpeciesAttacks,projectSpeciesAttackBenefitCatalogs} from '../tools/species_mechanics.mjs';
import {speciesAttacksFromBenefits} from '../species_benefit_catalogs.js';
import {calculateSheet} from '../sheet_rules.js';
import {pendingCharacterChoices,savePendingChoice} from '../pending_choices.js';
import {traitBenefitGroups} from '../trait_benefits.js';

const json=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const source=json('../../vtt/data/creature_references_5etools.json');
const generated=projectSpeciesAttackBenefitCatalogs(source.races);
const attackBenefits=json('../../vtt/enrichment/benefits/attack.json');
const movementBenefits=json('../../vtt/enrichment/benefits/movement.json');
const catalog=speciesAttacksFromBenefits(attackBenefits,movementBenefits);
const abilities={str:16,dex:12,con:14,int:10,wis:10,cha:10};
const record=(book)=>({
 kind:'character',species:'Aarakocra',species_source:book,
 species_id:'5etools:races:'+book.toLowerCase()+':aarakocra',
 abilities,level:1,inventory:[],rules_version:'2014'
});
const calculated=(book,changes={})=>calculateSheet({...record(book),...changes},{speciesAttacks:catalog});
const natural=sheet=>sheet.attacks.find(a=>a.id.startsWith('natural:'));

test('published source data generates deterministic typed natural strikes (never prose at runtime)',()=>{
 assert.deepEqual(attackBenefits,generated.attack);
 assert.deepEqual(movementBenefits,generated.movement);
 const canonical=projectSpeciesAttacks(source.races);
 const sort=rows=>[...rows].sort((a,b)=>a.id.localeCompare(b.id));
 assert.deepEqual(sort(catalog.races),sort(canonical.races));
 assert.equal(attackBenefits.entries.length,20);
 assert.equal(movementBenefits.entries.length,10);
 assert.ok(catalog.races.length>=20);
 assert.equal(catalog.races.filter(r=>r.name==='Aarakocra').length,3);
 assert.ok(!catalog.races.some(r=>r.name==='Shifter (Longtooth)'&&r.source==='ERLW'),
   'conditional shifting attacks must not become permanent');
 assert.ok(!catalog.races.some(r=>r.name==='Naga'&&r.source==='PSA'),
   'complex multi-damage attacks need explicit modeling, not guesswork');
});

test('EEPC and DMG racial ability increments remain source-correct and conditional on origin',()=>{
 const abilityGrants=json('../catalog/ability_grants.json');
 const eepc=calculateSheet(record('EEPC'),{abilityGrants});
 const dmg=calculateSheet(record('DMG'),{abilityGrants});
 assert.equal(eepc.abilities.dex.score,14);
 assert.equal(eepc.abilities.wis.score,11);
 assert.equal(dmg.abilities.dex.score,14);
 assert.equal(dmg.abilities.wis.score,12);
 const disabled=calculateSheet({...record('EEPC'),
   origin_enabled:{'race|eepc|aarakocra':false}},{abilityGrants});
 assert.equal(disabled.abilities.dex.score,12);
 const mpmm=calculateSheet(record('MPMM'),{abilityGrants});
 assert.equal(mpmm.abilities.dex.score,12,
   'do not invent a fixed increase for a book with user-selected scores');
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

test('winged species with fly:true use walking speed; armor gating stays source-qualified',()=>{
 const races=['EEPC','MPMM'].map(book=>({
   id:'5etools:races:'+book.toLowerCase()+':aarakocra',
   name:'Aarakocra',source:book,speed:{walk:book==='EEPC'?25:30,fly:book==='MPMM'?true:50}
 }));
 const rules={speciesAttacks:catalog,classMechanics:{races}};
 const unarmored=calculateSheet(record('MPMM'),rules);
 assert.equal(unarmored.stats.speeds.walk,30);
 assert.equal(unarmored.stats.speeds.fly,30);
 assert.equal(calculateSheet(record('EEPC'),rules).stats.speeds.fly,50);
 const armor={id:'test-chain',name:'Chain Shirt',type:'MA',ac:13,
   quantity:1,equipped_slots:['body']};
 assert.equal(calculateSheet({...record('MPMM'),inventory:[armor]},rules).stats.speeds.fly,0);
 assert.equal(calculateSheet({...record('EEPC'),inventory:[armor]},rules).stats.speeds.fly,0);
 const dmgRules={speciesAttacks:catalog,classMechanics:{races:[
   {id:'5etools:races:dmg:aarakocra',name:'Aarakocra',source:'DMG',
    speed:{walk:20,fly:50}}
 ]}};
 assert.equal(calculateSheet({...record('DMG'),inventory:[armor]},dmgRules).stats.speeds.fly,50,
   'an edition without an armor restriction must not inherit it from another book');
});

test('Wood Elf receives 35 ft from its canonical subrace metadata',()=>{
 const parent={id:'elf',name:'Elf',source:'PHB',speed:30};
 const subtype={id:'wood',name:'Wood',source:'PHB',raceName:'Elf',raceSource:'PHB',speed:35};
 const character={kind:'character',species:'Elf',species_source:'PHB',species_id:'elf',
  subrace:'Wood',subrace_source:'PHB',subrace_id:'wood',level:1,
  rules_version:'2014',abilities,inventory:[]};
 const result=calculateSheet(character,{classMechanics:{races:[parent],subraces:[subtype]}});
 assert.equal(result.stats.speeds.walk,35);
 assert.equal(calculateSheet({...character,subrace:'',subrace_source:''},
  {classMechanics:{races:[parent],subraces:[subtype]}}).stats.speeds.walk,30);
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
