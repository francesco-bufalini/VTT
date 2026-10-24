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
