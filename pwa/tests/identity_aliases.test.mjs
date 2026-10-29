import assert from 'node:assert/strict';
import test from 'node:test';
import {identityEntries,identityEntriesPatch} from '../identity_aliases.js';

test('legacy name and party stay valid with one active identity',()=>{
 const old={name:'Lyria',party_id:'Arcani'};
 assert.deepEqual(identityEntries(old,'names'),[{value:'Lyria',active:true}]);
 assert.deepEqual(identityEntries(old,'factions'),[{value:'Arcani',active:true}]);
 const names=identityEntriesPatch(old,'names',[
  {value:'Lyria',active:false},{value:'Guardiana della Luna',active:true}
 ]);
 assert.equal(names.name,'Guardiana della Luna');
 assert.deepEqual(identityEntries({...old,...names},'names'),[
  {value:'Lyria',active:false},{value:'Guardiana della Luna',active:true}
 ]);
});

test('names are exclusive; empty identity rows are discarded',()=>{
 const old={name:'Uno'};
 const patch=identityEntriesPatch(old,'names',[
  {value:'Uno',active:true},{value:'Due',active:true},{value:' ',active:false}
 ]);
 assert.equal(patch.identity_names.length,2);
 assert.deepEqual(patch.identity_names.map(row=>row.active),[true,false]);
 assert.throws(()=>identityEntriesPatch(old,'names',[{value:' ',active:false}]),/nome/);
});

test('several active factions are stored, but the legacy party remains scalar',()=>{
 const old={name:'Lyria',party_id:'A'};
 const patch=identityEntriesPatch(old,'factions',[
  {value:'A',active:true},{value:'B',active:true},{value:'',active:true},
  {value:'C',active:false}
 ]);
 assert.equal(patch.party_id,'A');
 assert.deepEqual(identityEntries({...old,...patch},'factions'),[
  {value:'A',active:true},{value:'B',active:true},{value:'C',active:false}
 ]);
 const none=identityEntriesPatch(old,'factions',[
  {value:'A',active:false},{value:'B',active:false}
 ]);
 assert.equal(none.party_id,'');
 assert.deepEqual(identityEntries({...old,...none},'factions'),none.identity_factions);
});
