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

test('numeric sheet rules never request the full spell compendium',async()=>{
  const {loadRuleCatalogs,clearLocalRuleCatalogCache}=await import('../sheet_rules.js');
  const originalFetch=globalThis.fetch;
  const calls=[];
  clearLocalRuleCatalogCache();
  globalThis.fetch=async path=>{
    calls.push(path);
    assert.notEqual(path,'/catalog/spells.json',
      'Opening a creature must not fetch the complete spell catalog through sheet rules');
    const data=path==='/catalog/class_mechanics.json'?{legacy_spells:[]}:
      path==='/catalog/classes.json'?{version:1,class_features:[],subclass_features:[]}:
      path==='/catalog/feature_timing_recovery_rules.json'?{version:1,actions:[],recoveries:[]}:
      path==='/catalog/trait_states.json'?{version:1,states:[]}:
      path==='/catalog/benefits/action.json'?{schema_version:2,benefit_type:'action',scope:'catalog',entries:[]}:
          (path.startsWith('/benefits/')&&
           ['roll_mode.json','roll_bonus.json','attack.json','movement.json','resource.json','scaling_die.json','item_grant.json']
            .includes(path.split('/').at(-1)))?
        {schema_version:2,benefit_type:path.split('/').at(-1).slice(0,-5),scope:'catalog',entries:[]}:{};
    return new Response(JSON.stringify(data),{status:200});
  };
  try{
    const result=await loadRuleCatalogs();
    assert.ok(result.classMechanics&&result.abilityGrants);
    assert.ok(calls.includes('/catalog/class_mechanics.json'));
    assert.ok(!calls.includes('/catalog/spells.json'));
  }finally{
    clearLocalRuleCatalogCache();
    globalThis.fetch=originalFetch;
  }
});

test('typed option lists avoid fetching the duplicate legacy catalog, with an old-host fallback',async()=>{
  const {readFileSync}=await import('node:fs');
  const {loadRuleCatalogs,clearLocalRuleCatalogCache}=await import('../sheet_rules.js');
  const read=rel=>JSON.parse(readFileSync(new URL(rel,import.meta.url),'utf8'));
  const optionGrants=read('../../vtt/enrichment/benefits/option_grant.json');
  const optionLists=read('../../vtt/enrichment/benefits/option_list.json');
  const legacyOptions=read('../catalog/optional_feature_progressions.json');
  const originalFetch=globalThis.fetch;
  try{
    for(const modern of [true,false]){
      const calls=[];
      clearLocalRuleCatalogCache();
      globalThis.fetch=async path=>{
        calls.push(path);
        const catalogs={
          '/benefits/option_grant.json':modern?optionGrants:{},
          '/benefits/option_list.json':modern?optionLists:{},
          '/catalog/optional_feature_progressions.json':legacyOptions
        };
        const data=Object.hasOwn(catalogs,path)?catalogs[path]:
          path==='/catalog/class_mechanics.json'?{legacy_spells:[]}:
          path==='/catalog/classes.json'?{version:1,class_features:[],subclass_features:[]}:
          path==='/catalog/feature_timing_recovery_rules.json'?{version:1,actions:[],recoveries:[]}:
          path==='/catalog/trait_states.json'?{version:1,states:[]}:
          path==='/catalog/benefits/action.json'?{schema_version:2,benefit_type:'action',scope:'catalog',entries:[]}:
          (path.startsWith('/benefits/')&&
           ['roll_mode.json','roll_bonus.json','attack.json','movement.json','resource.json','scaling_die.json','item_grant.json']
            .includes(path.split('/').at(-1)))?
            {schema_version:2,benefit_type:path.split('/').at(-1).slice(0,-5),scope:'catalog',entries:[]}:{};
        return new Response(JSON.stringify(data),{status:200});
      };
      const result=await loadRuleCatalogs();
      assert.equal(result.optionLists.entries.length,modern?272:0);
      assert.equal(result.optionalFeatureProgressions.options.length,modern?0:272);
      assert.equal(calls.includes('/catalog/optional_feature_progressions.json'),!modern,
        'Skip the old 272-option download only when the typed catalog is available');
      assert.equal(calls.filter(path=>path==='/benefits/option_list.json').length,1);
      assert.equal(calls.filter(path=>path==='/benefits/option_grant.json').length,1);
    }
  }finally{
    clearLocalRuleCatalogCache();
    globalThis.fetch=originalFetch;
  }
});
