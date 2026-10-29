import assert from 'node:assert/strict';
import {browserFixture,seedPlayCreature} from './browser_fixture.mjs';

const fixture=await browserFixture({imagePolicy:true});
const {page,origin,close,errors}=fixture;
try{
 await seedPlayCreature(page,origin);
 const portrait=page.locator('#sheet-play-view .play-character-portrait');
 await portrait.waitFor();
 const order=await page.locator('#sheet-play-view').evaluate(root=>
  [...root.children].map(node=>node.className||''));
 assert(order.includes('play-character-portrait'));
 assert.equal(await portrait.locator(':scope > .play-identity').count(),1,
  'Character identity and portrait share the same responsive card');
 if(order.includes('pending-choices-notice')){
  assert(order.indexOf('pending-choices-notice')>order.indexOf('play-character-portrait'),
   'Unresolved character choices must be below the portrait button');
 }
 assert.equal(await portrait.locator('img').count(),0);
 assert.equal(await portrait.locator('[data-act="info-portrait-pick"]').count(),0,'Portrait controls were moved to the identity settings dialog');
 await portrait.click();
 assert.equal(await page.locator('#sheet-context-dialog [data-act="info-portrait-pick"]').count(),1);
 const id=await page.evaluate(async()=>{
  const {listCreatures}=await import('/creatures.js');
  return (await listCreatures())[0].creature.id;
 });
 const image=await page.evaluate(()=>{
  const canvas=document.createElement('canvas');
  canvas.width=90;canvas.height=125;
  const ctx=canvas.getContext('2d');
  ctx.fillStyle='#a77a45';ctx.fillRect(0,0,90,125);
  ctx.fillStyle='#35201c';ctx.fillRect(10,10,65,100);
  return canvas.toDataURL('image/png');
 });
 // The visible button must open the native chooser synchronously (also on iOS).
 const chooserPromise=page.waitForEvent('filechooser');
 await page.locator('#sheet-context-dialog [data-act="info-portrait-pick"]').click();
 const chooser=await chooserPromise;
 await chooser.setFiles({name:'ritratto.png',mimeType:'image/png',
  buffer:Buffer.from(image.split(',')[1],'base64')});
 await portrait.locator('.play-portrait-frame img').waitFor();
 await page.waitForFunction(()=>{
  const img=document.querySelector('.play-portrait-frame img');
  return img?.complete;
 });
 const visible=await portrait.locator('.play-portrait-frame img').evaluate(img=>({
  width:img.naturalWidth,height:img.naturalHeight,
  frameWidth:img.getBoundingClientRect().width
 }));
 assert(visible.width>0&&visible.height>0&&visible.frameWidth>0,
  'Uploaded portrait must really decode and render under the Godot host image CSP: '+JSON.stringify(visible));
 const read=()=>page.evaluate(async creatureId=>{
  const {loadCreature}=await import('/creatures.js');
  return (await loadCreature(creatureId)).data.sheet_portrait_data;
 },id);
 const saved=await read();
 assert.match(saved,/^data:image\/jpeg;base64,/);
 assert(saved.length<2*1024*1024);
 const exported=await page.evaluate(async creatureId=>{
  const {exportCreature}=await import('/creatures.js');
  return JSON.parse(await (await exportCreature(creatureId)).text()).creature.sheet_portrait_data;
 },id);
 assert.equal(exported,saved,'portrait travels in the portable character export');
 await page.reload();
 await page.locator('[data-act="open"]').click();
 await page.locator('#sheet-play-view .play-portrait-frame img').waitFor();
 await page.waitForFunction(()=>document.querySelector('.play-portrait-frame img')?.complete);
 assert(await page.locator('#sheet-play-view .play-portrait-frame img').evaluate(img=>img.naturalWidth>0&&img.naturalHeight>0),
  'The reloaded portrait must still decode under CSP');
 assert.equal(await page.locator('#sheet-play-view .play-portrait-frame img').getAttribute('src'),saved,
  'The photo survives a reload from local IndexedDB');
 await portrait.click();
 await page.locator('#sheet-context-dialog [data-act="info-portrait-remove"]').click();
 await page.waitForFunction(()=>!document.querySelector('#sheet-play-view .play-portrait-frame'));
 assert.equal(await read(),'');
 assert.equal(await page.locator('#sheet-context-dialog [data-act="info-portrait-pick"]').textContent().then(s=>s.trim()),'▧Aggiungi foto');
 assert.deepEqual(errors,[],'No browser JS exceptions');
}finally{await close();}
