import test from 'node:test';
import assert from 'node:assert/strict';
import {variantDescription} from '../creature_variants_view.js';
test('variant summaries combine preset and unique bestiary sources, with customized sections as fallback',()=>{
 assert.equal(variantDescription({preset:'alias',sections:['name']}),'Alias');
 assert.equal(variantDescription({preset:'wild_shape',sections:['hp'],sources:{hp:{name:'Wolf',source:'MM'},appearance:{name:'Wolf',source:'MM'},str:{name:'Bear',source:'MM'}}}),'Forma selvatica · Wolf (MM) · Bear (MM)');
 assert.equal(variantDescription({preset:'custom',sections:['hp','str']}),'Punti ferita · Caratteristica STR');
 assert.equal(variantDescription({preset:'custom',sections:['*']}),'Intera scheda');
});
