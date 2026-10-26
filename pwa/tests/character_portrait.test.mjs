import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {isPortraitDataUrl,preparePortraitImage,
 PORTRAIT_MAX_INPUT_BYTES,PORTRAIT_MAX_DATA_LENGTH} from '../character_portrait.js';
import {createVariant,applyVariantEdit,resolveVariant} from '../creature_variants.js';
import {initialCreature} from '../character_core.js';

test('portrait source accepts only bounded embedded raster images',()=>{
 const bytes=Buffer.from([0xff,0xd8,0xff]).toString('base64');
 assert.equal(isPortraitDataUrl('data:image/jpeg;base64,'+bytes),true);
 assert.equal(isPortraitDataUrl('data:image/png;base64,'+bytes),true);
 assert.equal(isPortraitDataUrl('data:image/webp;base64,'+bytes),true);
 for(const url of ['https://example.com/portrait.jpg','data:image/svg+xml;base64,'+bytes,
  'javascript:alert(1)','data:image/jpeg;base64,','data:image/jpeg;base64,%%%']){
  assert.equal(isPortraitDataUrl(url),false,url);
 }
 assert.equal(isPortraitDataUrl('data:image/jpeg;base64,'+'A'.repeat(PORTRAIT_MAX_DATA_LENGTH)),false);
});

test('unsupported, empty and oversized local images are rejected before decoding',async()=>{
 await assert.rejects(preparePortraitImage(null),/massimo 12 MB/);
 await assert.rejects(preparePortraitImage({type:'image/png',size:0}),/massimo 12 MB/);
 await assert.rejects(preparePortraitImage({type:'image/jpeg',size:PORTRAIT_MAX_INPUT_BYTES+1}),/massimo 12 MB/);
 await assert.rejects(preparePortraitImage({type:'image/svg+xml',size:1024}),/Formato non supportato/);
 await assert.rejects(preparePortraitImage({type:'text/html',size:1024}),/Formato non supportato/);
});

test('sheet portrait stays on the base creature while a polymorph form is active',()=>{
 const base={...initialCreature('character','Hero','hero','owner'),sheet_portrait_data:''};
 const form=createVariant(base,{id:'poly',name:'Forma mostruosa',preset:'polymorph'});
 const active={...base,variants:[form],current_form_id:'poly'};
 const changed=applyVariantEdit(active,{sheet_portrait_data:'photo'});
 assert.equal(changed.sheet_portrait_data,'photo');
 assert.equal(changed.variants[0].values.sheet_portrait_data,undefined);
 assert.equal(resolveVariant(changed).sheet_portrait_data,'photo');
});

test('Godot host permits embedded local character pictures without loosening script CSP',()=>{
 const host=readFileSync(new URL('../../network/pwa_host.gd',import.meta.url),'utf8');
 assert.match(host,/img-src 'self' blob: data:;/);
 assert.match(host,/script-src 'self';/);
});
