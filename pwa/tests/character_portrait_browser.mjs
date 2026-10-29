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
 // Use actual shipped artwork, deliberately choosing a different current form.
 await page.evaluate(async id=>{
  const {loadCreature,saveCreature}=await import('/creatures.js');
  const saved=await loadCreature(id);
  await saveCreature({...saved.data,default_miniature_id:'ore',current_miniature_id:'harmakis'},'default',saved.revision);
 },id);
 await page.reload();await page.locator('[data-act="open"]').click();
 await portrait.click();
 const useMiniature=page.locator('#sheet-context-dialog [data-act="info-portrait-miniature"]');
 assert.equal(await useMiniature.textContent(),'Usa la miniatura come immagine');
 for(const width of [360,390,768,1440]){
  await page.setViewportSize({width,height:950});
  const layout=await useMiniature.evaluate(button=>{
   const a=button.getBoundingClientRect(),b=button.previousElementSibling.getBoundingClientRect();
   return {below:a.top>=b.bottom,height:a.height,inside:a.right<=innerWidth};
  });
  assert(layout.below&&layout.height>=48&&layout.inside,JSON.stringify({width,...layout}));
 }
 await page.setViewportSize({width:390,height:950});
 await useMiniature.click();
 await portrait.locator('.play-portrait-frame img').waitFor();
 await page.waitForFunction(()=>document.querySelector('.play-portrait-frame img')?.naturalHeight>0);
 const miniSaved=await read();assert.match(miniSaved,/^data:image\/jpeg;base64,/);
 const dimensions=await portrait.locator('img').evaluate(img=>({width:img.naturalWidth,height:img.naturalHeight}));
 assert.deepEqual(dimensions,{width:630,height:940},'Current Harmakis artwork is saved whole, without square cropping');
 await page.locator('#sheet-context-dialog [data-act="sheet-context-close"]').first().click();
 await page.locator('#sheet-context-dialog').waitFor({state:'detached'});
 await page.screenshot({path:new URL('../.test-artifacts/miniature-portrait-harmakis.png',import.meta.url).pathname.replace(/^\/(\w:)/,'$1')});
 // The embedded result remains usable without fetching artwork again.
 await page.reload();await page.locator('[data-act="open"]').click();
 assert.equal(await portrait.locator('img').getAttribute('src'),miniSaved);
 assert.equal(await read(),miniSaved);
 const miniExport=await page.evaluate(async id=>{
  const {exportCreature}=await import('/creatures.js');
  return JSON.parse(await (await exportCreature(id)).text()).creature.sheet_portrait_data;
 },id);
 assert.equal(miniExport,miniSaved);
 // The installed image cache also supports choosing a miniature while offline.
 await page.waitForFunction(async()=>{
  for(const name of await caches.keys()){
   const cache=await caches.open(name);
   if(await cache.match('/miniature-images/ore.webp'))return true;
  }
  return false;
 });
 await page.evaluate(async id=>{
  const {loadCreature,saveCreature}=await import('/creatures.js');
  const saved=await loadCreature(id);
  await saveCreature({...saved.data,current_miniature_id:''},'default',saved.revision);
 },id);
 await fixture.context.setOffline(true);
 await page.reload();await page.locator('[data-act="open"]').click();
 await portrait.click();
 await useMiniature.click();
 await page.waitForFunction(previous=>document.querySelector('.play-portrait-frame img')?.src!==previous,miniSaved);
 assert.deepEqual(await portrait.locator('img').evaluate(img=>({width:img.naturalWidth,height:img.naturalHeight})),
  {width:800,height:940},'Base Ore artwork can be chosen from the offline cache');
 await fixture.context.setOffline(false);
 assert.deepEqual(errors,[],'No browser JS exceptions');
}finally{await close();}
