import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {browserFixture,seedPlayCreature} from './browser_fixture.mjs';

const f=await browserFixture(),{page,origin,sheet,errors,close}=f;
const row=index=>page.locator('#sheet-play-view [data-inventory-item-index="'+index+'"]');
const buttons=()=>page.locator('#sheet-play-view [data-inventory-bulk]');
try{
  await seedPlayCreature(page,origin);
  await sheet('inventory');
  assert.equal(await buttons().isVisible(),false,'selection starts hidden');

  // Long-press one item; a release/click must not open its detail popup.
  const item=row(0).locator('.inventory-play-item');
  await item.dispatchEvent('pointerdown',{pointerId:51,button:0,clientX:50,clientY:200});
  await page.waitForTimeout(560);
  await item.dispatchEvent('pointerup',{pointerId:51,button:0,clientX:50,clientY:200});
  await item.dispatchEvent('click');
  assert.equal(await buttons().isVisible(),true,'long press reveals toolbar');
  assert.equal(await page.locator('#sheet-context-dialog[open]').count(),0);
  assert.equal(await row(0).locator('input[data-inventory-select]').isChecked(),true);

  // While selecting, a short tap toggles another item instead of opening it.
  await row(1).locator('.inventory-play-item').click();
  assert.equal(await row(1).locator('input[data-inventory-select]').isChecked(),true);
  assert.match(await buttons().locator('[data-inventory-selection-count]').textContent(),/2 selezionati/);

  const dlPromise=page.waitForEvent('download');
  await buttons().locator('[data-act="inventory-bulk-export"]').click();
  const downloaded=await dlPromise;
  assert.match(downloaded.suggestedFilename(),/inventario.*json/);
  const payload=JSON.parse(await readFile(await downloaded.path(),'utf8'));
  assert.equal(payload.format,'vtt_inventory_export_v1');
  assert.deepEqual(payload.items.map(item=>item.name),['Lama lunare','Pozione curativa']);
  assert.deepEqual(payload.items.map(item=>item.quantity),[1,2]);

  // Reuse the same share workflow as the creature library.
  await page.route('**/api/share/peers',route=>route.fulfill({
    contentType:'application/json',body:JSON.stringify({
      devices:[{id:'linked-device',name:'Secondo dispositivo'}],inbox:[]})
  }));
  await buttons().locator('[data-act="inventory-bulk-send"]').click();
  await page.locator('#share-send-dialog[open]').waitFor();
  assert.match(await page.locator('#share-send-dialog').innerText(),/2 oggetti/);
  await page.locator('#share-send-dialog [data-share-cancel]').click();
  await page.locator('#share-send-dialog').waitFor({state:'detached'});

  await buttons().locator('[data-act="inventory-bulk-delete"]').click();
  await page.locator('#inventory-delete-dialog[open]').waitFor();
  assert.match(await page.locator('#inventory-delete-dialog').innerText(),/Pozione curativa/);
  await page.locator('#inventory-delete-dialog [data-inventory-delete-cancel]').click();
  assert.equal(await row(0).count(),1,'cancel keeps items');
  await buttons().locator('[data-act="inventory-bulk-delete"]').click();
  await page.locator('#inventory-delete-dialog [data-inventory-delete-confirm]').click();
  await page.waitForFunction(async()=>{
    const {listCreatures}=await import('/creatures.js');
    return (await listCreatures())[0]?.creature?.inventory?.length===1;
  });
  const remaining=await page.evaluate(async()=>{
    const {listCreatures}=await import('/creatures.js');
    return (await listCreatures())[0].creature.inventory.map(item=>item.name);
  });
  assert.deepEqual(remaining,['Anello stellare']);
  assert.equal(await buttons().isVisible(),false,'bulk actions close after deleting');
  assert.deepEqual(errors,[]);
  console.log('PASS: long-press selection, JSON export, Send modal and confirmed bulk deletion');
}finally{await close();}
