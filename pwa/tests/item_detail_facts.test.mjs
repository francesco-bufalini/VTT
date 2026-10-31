import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {structuredItemFacts} from '../item_detail_facts.js';

test('magic item detail facts retain every structured catalog attribute',()=>{
 const item={
  id:'magic_item:staff',instance_id:'a',name:'Bastone del crepuscolo',quantity:1,
  entries:['Long prose belongs below in the description.'],
  description:'Magic description',source:'DMG',rarity:'very rare',
  reqAttune:'by a spellcaster',charges:7,recharge:'dawn',
  rechargeAmount:'1d6 + 1',bonusSpellAttack:2,bonusSpellSaveDc:2,
  resist:['fire','cold'],attachedSpells:['{@spell Fireball|PHB}'],
  wondrous:true,curse:{type:'nightmares',dc:15},attuned:false,
  instance_overrides:{weight:1},container_id:'backpack'
 };
 const pairs=structuredItemFacts(item);
 const found=new Map(pairs);
 for(const label of ['Fonte','Rarità','Richiede sintonia','Cariche','Ricarica',
  'Cariche recuperate','Bonus attacco magico','Bonus CD incantesimi',
  'Resistenze','Incantesimi associati','Oggetto meraviglioso','Maledizione'])
  assert(found.has(label),'Missing '+label);
 assert.match(found.get('Incantesimi associati'),/Fireball/);
 assert.match(found.get('Maledizione'),/Tipo: nightmares/);
 assert(!pairs.some(([key,value])=>/Descrizione|entries|instance|container/i.test(key+' '+value)));
});

test('nested and unknown item metadata is preserved without inventing values',()=>{
 const entries=structuredItemFacts({
  type:'W',tier:'major',customArcaneEffect:{extraDice:'1d8',savingThrow:{ability:'wis',dc:17}},
  notes:null,empty:'',enabled:false,entries:['prose']
 });
 const facts=new Map(entries);
 assert.equal(facts.get('Fascia'),'major');
 assert.match(facts.get('Custom Arcane Effect'),/Extra Dice: 1d8/);
 assert.match(facts.get('Custom Arcane Effect'),/Dc: 17/);
 assert.equal(facts.get('Enabled'),'No');
 assert(!facts.has('Notes'));assert(!facts.has('Empty'));
});

test('internal item options stay out of structured facts',()=>{
 const facts=structuredItemFacts({
  id:'armor:chain',name:'Chain Mail',type:'HA',strength:13,stealth:true,
  option_extensions:[{id:'enhanced',name:'Enhanced Defense',definition:{effects:[{type:'bonus'}]}}],
  effect_extensions:[{id:'hidden'}]
 });
 const pairs=new Map(facts);
 assert.equal(pairs.get('Forza minima richiesta'),'13');
 assert.equal(pairs.get('Svantaggio alla furtività'),'Sì');
 assert(!facts.some(([label,value])=>/Option Extensions|Effect Extensions|Enhanced Defense|hidden/.test(label+' '+value)));
});
test('armor without a strength requirement shows a dash, including zero',()=>{
 for(const strength of [undefined,null,0]){
  const item={id:'armor:leather',type:'LA',stealth:false};
  if(strength!==undefined)item.strength=strength;
  const facts=new Map(structuredItemFacts(item));
  assert.equal(facts.get('Forza minima richiesta'),'—');
  assert.equal(facts.get('Svantaggio alla furtività'),'No');
 }
 assert(!new Map(structuredItemFacts({id:'weapon:dagger',type:'M'})).has('Forza minima richiesta'));
});
