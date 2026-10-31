import assert from 'node:assert/strict';
import {browserFixture} from './browser_fixture.mjs';
const f=await browserFixture(),{page,origin,sheet}=f;
const snapshot=()=>page.evaluate(async()=>{
 const {listCreatures}=await import('/creatures.js');
 return (await listCreatures())[0]?.creature;
});
try{
 await page.goto(origin);await page.locator('[data-act="library-add"]').waitFor();
 await page.evaluate(async()=>{
  const {createCreature,saveCreature}=await import('/creatures.js');
  const saved=await createCreature('character','Generic variant test');
  await saveCreature({...saved.data,rules_version:'2014',
   class:'Fighter',class_source:'PHB',classes:[{name:'Fighter',source:'PHB',level:2}],
   inventory:[{id:'local_blade',instance_id:'test-blade',name:'Longsword',
    custom_item_type:'weapon',type:'M',weapon_category:'martial',damage:'1d8',
    source:'PHB',quantity:1,active:true,equipped_slots:['main']}]},
   'default',saved.revision);
 });
 await page.reload();await page.locator('[data-act="open"]').click();await sheet('inventory');
 await page.locator('.inventory-play-item[data-act="sheet-context"]').first().click();
 const popup=page.locator('#sheet-context-dialog');
 await popup.locator('[data-act="item-variant-open"]').click();
 const variants=page.locator('#item-variant-dialog');
 await variants.waitFor({state:'visible'});
 for(const name of ['+1 Weapon','+2 Weapon']){
  await variants.locator('[data-item-variant-search]').fill(name);
  await variants.locator('.magic-catalog-row').filter({hasText:name+' · DMG'})
   .locator('[data-act="item-variant-add"]').click();
  await page.waitForFunction(expected=>document.querySelectorAll(
   '#sheet-context-dialog [data-act="item-variant-remove"]').length===expected,
   ['+1 Weapon','+2 Weapon'].indexOf(name)+1);
 }
 const record=await snapshot();
 assert.deepEqual(record.inventory[0].option_extensions.map(row=>row.name),['+1 Weapon','+2 Weapon']);
 assert.match(await page.locator('#sheet-context-title').innerText(),/\+1 Weapon.*\+2 Weapon/);
 await page.locator('#item-variant-dialog [data-act="item-variant-close"]').click();
 await popup.locator('[data-act="item-variant-remove"]').first().click();
 assert.deepEqual((await snapshot()).inventory[0].option_extensions.map(row=>row.name),['+2 Weapon']);
 assert.deepEqual(f.errors,[]);assert.deepEqual(f.missing,[]);
 console.log('PASS: multiple 5eTools variants can be added and removed from one inventory popup');
}finally{await f.close();}
