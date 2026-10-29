import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {isPortraitDataUrl,preparePortraitImage,miniaturePortraitPath,
 PORTRAIT_MAX_INPUT_BYTES,PORTRAIT_MAX_DATA_LENGTH} from '../character_portrait.js';
import {createVariant,applyVariantEdit,resolveVariant} from '../creature_variants.js';
import {initialCreature} from '../character_core.js';
import {createHash} from 'node:crypto';

test('miniature portraits use the current identity and only bundled raster paths',()=>{
 const profiles=[{id:'ore',token_image_path:'res://pwa/miniature-images/ore.webp'},
  {id:'harmakis',token_image_path:'res://pwa/miniature-images/harmakis.webp'}];
 assert.equal(miniaturePortraitPath({default_miniature_id:'ore',current_miniature_id:'harmakis'},profiles),'/miniature-images/harmakis.webp');
 assert.equal(miniaturePortraitPath({default_miniature_id:'ore'},profiles),'/miniature-images/ore.webp');
 assert.throws(()=>miniaturePortraitPath({current_miniature_id:'unknown',default_miniature_id:'ore'},profiles),/non disponibile/);
 for(const path of ['https://example.org/a.webp','res://pwa/miniature-images/../ore.webp','res://pwa/miniature-images/ore.svg'])
  assert.throws(()=>miniaturePortraitPath({default_miniature_id:'ore'},[{id:'ore',token_image_path:path}]),/non disponibile/);
});

test('all twelve character 2D tokens have verified bytes and offline host routes',()=>{
 const catalog=JSON.parse(readFileSync(new URL('../../vtt/data/token_catalog_offline.json',import.meta.url)));
 const host=readFileSync(new URL('../../network/pwa_host.gd',import.meta.url),'utf8');
 const worker=readFileSync(new URL('../sw.js',import.meta.url),'utf8');
 const profiles=catalog.tokens.filter(row=>row.release_tag==='characters');
 assert.equal(profiles.length,12);
 for(const profile of profiles){
  const path=miniaturePortraitPath({default_miniature_id:profile.id},profiles);
  const bytes=readFileSync(new URL('..'+path,import.meta.url));
  assert.equal(bytes.length,profile.token_image_bytes);
  assert.equal(createHash('sha256').update(bytes).digest('hex'),profile.token_image_sha256);
  assert(host.includes('"'+path+'": ["'+profile.token_image_path+'", "image/webp"]'));
  assert(worker.includes('"'+path+'"'));
  assert(profile.token_image_url.includes('/characters/'+profile.id+'.webp?v='));
 }
});

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
