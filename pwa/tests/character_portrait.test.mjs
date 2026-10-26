import {test} from 'node:test';
import assert from 'node:assert/strict';
import {isPortraitDataUrl,preparePortraitImage,
 PORTRAIT_MAX_INPUT_BYTES,PORTRAIT_MAX_DATA_LENGTH} from '../character_portrait.js';

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
