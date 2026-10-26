import test from 'node:test';
import assert from 'node:assert/strict';
import {contentForRules,isContentAvailableForRules,sourceCode} from '../source_edition.js';
import {spellsForEdition,addSelectedSpell,applyOriginSpellChoice} from '../spell_selection.js';

test('2014 characters only see sources released before 2024 in all catalog types',()=>{
  const entries=[
    {name:'Legacy class',source:'PHB'},
    {name:'Legacy race',source:'EEPC'},
    {name:'Legacy feat',source:'TCE'},
    {name:'Legacy item',source:'BMT'},
    {name:'New class',source:'XPHB'},
    {name:'New item',source:'XDMG'},
    {name:'New feat',source:'EFA'},
    {name:'New spell',source:'FRHoF'},
    {name:'New adventure reference',source:'QftIS'},
    {name:'2026 source',source:'RHW'}
  ];
  assert.deepEqual(contentForRules(entries,'2014').map(x=>x.name),
    ['Legacy class','Legacy race','Legacy feat','Legacy item']);
  assert.deepEqual(contentForRules(entries,'2024'),entries);
  assert.equal(entries.length,10,'the catalog itself stays unchanged');
});
test('publication dates and metadata override unknown source codes',()=>{
  assert.equal(isContentAvailableForRules({source:'SOMEBOOK',published:'2024-01-01'},'2014'),false);
  assert.equal(isContentAvailableForRules({source:'SOMEBOOK',publicationYear:2025},'2014'),false);
  assert.equal(isContentAvailableForRules({source:'SOMEBOOK',sourceMetadata:{date:'2026-03-01'}},'2014'),false);
  assert.equal(isContentAvailableForRules({source:'SOMEBOOK',releaseDate:'2023-12-31'},'2014'),true);
  assert.equal(isContentAvailableForRules({source:'UA2025Spells'},'2014'),false);
  assert.equal(isContentAvailableForRules({edition:'2024',source:'OLD'},'2014'),false);
  assert.equal(sourceCode({source:{abbreviation:'xPHB'}}),'XPHB');
  assert.equal(isContentAvailableForRules({id:'homebrew:quick_local:items:test',source:'Personalizzato'},'2014'),true);
  assert.equal(isContentAvailableForRules({name:'Manuale senza fonte'},'2014'),true);
});
test('2023 Sigil and the Outlands is still offered under 2014 rules',()=>{
  assert.equal(isContentAvailableForRules({source:'SatO'},'2014'),true);
});
test('2014 spell chooser filters 2024 and later sources and keeps PHB legacy identity',()=>{
  const entries=[
    {id:'phb2014_shield',name:'Shield',source:'PHB',level:1},
    {id:'shield',name:'Shield',source:'PHB',level:1},
    {id:'new',name:'Shield',source:'XPHB',level:1},
    {id:'arts',name:'Spell',source:'EFA',level:1},
    {id:'new-adventure',name:'Spell',source:'VEoR',level:1},
    {id:'old',name:'Spell',source:'TCE',level:1}
  ];
  assert.deepEqual(spellsForEdition(entries,'2014').map(s=>s.id),['phb2014_shield','old']);
  assert.deepEqual(spellsForEdition(entries,'2024').map(s=>s.id),
    ['shield','new','arts','new-adventure','old']);
});
test('add/choose actions reject recent sources for 2014 but accept older ones',()=>{
  const future={id:'new',name:'New Spell',source:'XPHB',level:1};
  const old={id:'old',name:'Old Spell',source:'PHB',level:1};
  assert.throws(()=>addSelectedSpell({rules_version:'2014'},future),/2014/);
  const added=addSelectedSpell({rules_version:'2014'},old);
  assert.equal(added.prepared_spells[0].id,'old');
  assert.equal(addSelectedSpell({rules_version:'2024'},future).prepared_spells[0].id,'new');
  const choice={id:'origin-choice',origin_id:'feature',origin_name:'Feat',
    count:1,filter:'',stage:'1',spellcasting_ability:'int'};
  assert.throws(()=>applyOriginSpellChoice({rules_version:'2014'},choice,future),/2014/);
});
