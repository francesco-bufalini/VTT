import {test} from 'node:test';
import assert from 'node:assert/strict';
import {characterHomebrewEntries,appendSharedHomebrew} from '../character_homebrew.js';

const h='homebrew:personal:';
test('homebrew from one character appears in pickers for another, without owned state',()=>{
 const owner={inventory:[{id:h+'items:blade',name:'Lama del vento',source:'Personalizzato',
   damage:'1d8',quantity:3,instance_id:'copy-1',equipped:true,attuned:true,
   instance_overrides:{damage:'9d9'},container_id:'vault'}],
   feats_catalog:[{id:h+'feats:adept',name:'Adepto',source:'Personalizzato'}],
   prepared_spells:[{id:h+'spells:glow',name:'Luce antica',source:'Personalizzato',level:1,
     classes:['Wizard'],casting_classes:['specific-owner'],origin_id:'first-character'}],
   background:'Viandante',background_id:h+'backgrounds:wayfarer',background_source:'Personalizzato',
   classes:[{name:'Mago di vetro',id:h+'classes:glass',source:'Personalizzato',level:7}]};
 const copy=structuredClone(owner);
 const items=characterHomebrewEntries('items',[owner,copy]);
 assert.equal(items.length,1);
 assert.equal(items[0].damage,'1d8');
 for(const key of ['quantity','equipped','attuned','instance_id','instance_overrides','container_id'])
   assert.equal(Object.hasOwn(items[0],key),false,key);
 assert.equal(characterHomebrewEntries('weapons',[owner]).length,0);
 assert.equal(characterHomebrewEntries('feats',[owner])[0].name,'Adepto');
 assert.equal(characterHomebrewEntries('backgrounds',[owner])[0].name,'Viandante');
 assert.equal(characterHomebrewEntries('classes',[owner])[0].name,'Mago di vetro');
 const spell=characterHomebrewEntries('spells',[owner])[0];
 assert.deepEqual(spell.classes,['Wizard']);
 assert.equal(spell.casting_classes,undefined);
 assert.equal(spell.origin_id,undefined);
 assert.deepEqual(owner,copy,'building options must never change the owner');
});
test('packaged/global definitions win and only homebrew is shared',()=>{
 const id=h+'feats:adept';
 const global={id,name:'Adepto',source:'Personalizzato',_category:'feats',_homebrew:true,description:'Full definition'};
 const copied={id,name:'Adepto',source:'Personalizzato',_category:'feats',_homebrew:true};
 assert.deepEqual(appendSharedHomebrew([global],[copied]),[global]);
 assert.equal(characterHomebrewEntries('feats',[{feats_catalog:[
   {id:'phb2014_alert',name:'Alert',source:'PHB'},
   {id,name:'Adepto',source:'Personalizzato'}]}]).length,1);
});
test('standalone custom spells are selectable, invalid spell references are not',()=>{
 const rows=characterHomebrewEntries('spells',[{spells:[
   {name:'Nebbia rossa',source:'Personalizzato',level:2,description:'Nebbia magica'},
   {id:h+'spells:missing',source:'Personalizzato',level:3},
   {id:'phb2014_fireball',name:'Fireball',source:'PHB',level:3}]}]);
 assert.equal(rows.length,1);
 assert.match(rows[0].id,/^local_shared_spells_/);
});
