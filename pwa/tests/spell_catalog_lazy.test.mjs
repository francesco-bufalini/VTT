import assert from 'node:assert/strict';
import {test} from 'node:test';
import 'fake-indexeddb/auto';
import {selectedSpellEntries} from '../catalog_data.js';

test('character references are loaded by ID/class without requesting the full catalog',async()=>{
  const originalFetch=globalThis.fetch;
  const calls=[];
  globalThis.fetch=async(path,options={})=>{
    calls.push({path,options});
    assert.equal(path,'/catalog/spells/selected');
    assert.equal(options.method,'POST');
    const selection=JSON.parse(options.body);
    assert.deepEqual(selection.ids,['spell:a']);
    assert.deepEqual(selection.classes,[{name:'Cleric',max_level:2}]);
    return new Response(JSON.stringify({version:1,spells:[
      {id:'spell:a',name:'Prepared',level:1,classes:['Cleric']},
      {id:'spell:b',name:'Known class spell',level:2,classes:['Cleric']}
    ]}),{headers:{'content-type':'application/json'}});
  };
  try{
    const [first,second]=await Promise.all([
      selectedSpellEntries(['spell:a'],[{name:'Cleric',max_level:2}]),
      selectedSpellEntries(['spell:a'],[{name:'Cleric',max_level:2}])
    ]);
    assert.deepEqual(first.map(row=>row.id),['spell:a','spell:b']);
    assert.deepEqual(second.map(row=>row.id),['spell:a','spell:b']);
    assert.equal(calls.length,1,'Concurrent sheet renders should share the same request');
    assert.ok(!calls.some(call=>call.path==='/catalog/spells.json'));
  }finally{
    globalThis.fetch=originalFetch;
  }
});
