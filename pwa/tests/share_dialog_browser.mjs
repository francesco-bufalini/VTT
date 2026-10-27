import assert from 'node:assert/strict';
import {browserFixture} from './browser_fixture.mjs';
const f=await browserFixture(),{page,origin,errors}=f;
let release;
try{
 await page.route('**/api/share/peers',route=>route.fulfill({contentType:'application/json',body:JSON.stringify({inbox:[
  {id:'browser-offer',kind:'homebrew',title:'Contenuto di prova',sender_name:'Dispositivo di prova',size:2,parts:1}
 ]})}));
 await page.route('**/api/share/pull',async route=>{
  await new Promise(resolve=>release=resolve);
  await route.fulfill({contentType:'application/json',body:JSON.stringify({data:'e30='})});
 });
 await page.goto(origin);await page.locator('[data-act="library-add"]').waitFor();
 await page.evaluate(async()=>{await (await import('/share_transfer.js')).pollIncomingShares(true);});
 const dialog=page.locator('#share-receive-dialog');await dialog.waitFor({state:'visible'});
 await dialog.locator('[data-share-accept]').click();
 const deadline=Date.now()+10000;
 while(!release&&Date.now()<deadline)await page.waitForTimeout(20);
 assert.ok(release,'Import request started');
 assert.equal(await dialog.locator('[data-act="share-later"]').isDisabled(),true);
 await page.keyboard.press('Escape');assert.equal(await dialog.isVisible(),true);
 release();
 await dialog.locator('[data-share-status]').filter({hasText:'Importazione non riuscita'}).waitFor();
 assert.equal(await dialog.locator('[data-act="share-later"]').isEnabled(),true);
 await page.keyboard.press('Escape');await dialog.waitFor({state:'detached'});
 await page.evaluate(async()=>{
  const original=Date.now;Date.now=()=>original()+5000;
  try{await (await import('/share_transfer.js')).pollIncomingShares(true);}finally{Date.now=original;}
 });
 assert.equal(await dialog.count(),0,'Escape postpones the offer instead of reopening it on the next poll');
 assert.deepEqual(errors,[]);
 console.log('PASS: received-share modal blocks Escape while importing, unlocks after error and postpones on idle Escape.');
}finally{release?.();await f.close();}
