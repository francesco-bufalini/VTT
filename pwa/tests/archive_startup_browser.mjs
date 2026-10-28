import assert from 'node:assert/strict';
import {browserFixture} from './browser_fixture.mjs';

async function archiveRecoversFromOneBadSheet(){
 const f=await browserFixture();
 try{
  await f.page.goto(f.origin);
  await f.page.locator('[data-act="library-add"]').waitFor();
  const ids=await f.page.evaluate(async()=>{
   const {createCreature}=await import('/creatures.js');
   const {putRecord}=await import('/storage.js');
   const good=await createCreature('character','Scheda leggibile');
   const bad=await createCreature('character','Vecchia variante');
   await putRecord('default','creature',bad.id,{...bad.data,variants:[null]},bad.revision);
   const unnamed=await createCreature('character','Nome vecchio');
   await putRecord('default','creature',unnamed.id,{...unnamed.data,name:null},unnamed.revision);
   await putRecord('default','creature','legacy_missing_body',null,0);
   return {good:good.id,bad:bad.id,unnamed:unnamed.id};
  });
  await f.page.reload();
  await f.page.locator('[data-act="library-add"]').waitFor();
  assert.equal(await f.page.locator('[data-act="open"]').count(),4);
  assert.equal(await f.page.locator('#startup-error').count(),0);
  await f.page.getByText('Scheda non leggibile',{exact:true}).waitFor();
  await f.page.locator('[data-act="open"][data-id="legacy_missing_body"]').click();
  await f.page.getByText('Operazione non riuscita',{exact:true}).waitFor();
  await f.page.locator('#app [data-act="back"]').click();
  await f.page.locator('[data-act="library-add"]').waitFor();
  await f.page.locator('[data-act="open"][data-id="'+ids.bad+'"]').click();
  await f.page.getByText('Operazione non riuscita',{exact:true}).waitFor();
  assert.equal(await f.page.locator('#app').getAttribute('data-rendered-sheet'),'');
  await f.page.locator('#app [data-act="back"]').click();
  await f.page.locator('[data-act="library-add"]').waitFor();
  await f.page.locator('[data-act="open"][data-id="'+ids.good+'"]').click();
  await f.page.waitForFunction(()=>document.querySelector('#app').dataset.renderedSheet==='info');
  assert.equal(await f.page.locator('#creature-name').textContent(),'Scheda leggibile');
  const raw=await f.page.evaluate(async id=>{
   const {getRecord}=await import('/storage.js');return (await getRecord('default','creature',id)).data;
  },ids.bad);
  assert.deepEqual(raw.variants,[null],'Opening the index never rewrites the unreadable sheet');
  assert.equal(await f.page.evaluate(async()=>{
   const {getRecord}=await import('/storage.js');return (await getRecord('default','creature','legacy_missing_body')).data;
  }),null);
  assert.deepEqual(f.errors,[]);
  console.log('PASS: one unreadable legacy sheet cannot block the archive, backups or other creatures');
 }finally{await f.close();}
}

async function aasimarSheetsOpen(){
 const f=await browserFixture();
 try{
  await f.page.goto(f.origin);
  await f.page.locator('[data-act="library-add"]').waitFor();
  const ids=await f.page.evaluate(async()=>{
   const {createCreature,saveCreature}=await import('/creatures.js');const ids=[];
   for(const subrace of ['Radiant Soul','Necrotic Shroud','Radiant Consumption']){
    const saved=await createCreature('character',subrace);
    await saveCreature({...saved.data,level:3,species:'Aasimar',species_source:'MPMM',
     species_id:'5etools:races:mpmm:aasimar',subrace,subrace_source:'MPMM'},'default',saved.revision);
    ids.push(saved.id);
   }
   return ids;
  });
  await f.page.reload();await f.page.locator('[data-act="library-add"]').waitFor();
  for(const id of ids){
   await f.page.locator('[data-act="open"][data-id="'+id+'"]').click();
   await f.page.waitForFunction(()=>document.querySelector('#app').dataset.renderedSheet==='info');
   assert.equal(await f.page.getByText('Operazione non riuscita',{exact:true}).count(),0);
   await f.page.locator('#creature-back').click();
   await f.page.locator('[data-act="library-add"]').waitFor();
  }
  assert.deepEqual(f.errors,[]);
  console.log('PASS: all three MPMM Aasimar forms open and return to the archive');
 }finally{await f.close();}
}

async function updatePreservesEdits(failSave=false){
 const f=await browserFixture();
 try{
  await f.page.addInitScript(()=>{
   const worker={postMessage(){}};
   Object.defineProperty(navigator,'serviceWorker',{configurable:true,value:{
    controller:worker,
    addEventListener(type,listener){if(type==='controllerchange')window.__controllerChange=listener;},
    async register(){return {async update(){}};},
    ready:Promise.resolve({active:worker})
   }});
  });
  await f.page.goto(f.origin);await f.page.locator('[data-act="library-add"]').waitFor();
  await f.page.waitForFunction(()=>typeof window.__controllerChange==='function');
  const id=await f.page.evaluate(async()=>{
   const {createCreature}=await import('/creatures.js');const saved=await createCreature('character','Prima');
   const {desktopSheetSession}=await import('/ui.js');await desktopSheetSession.open(saved.id);return saved.id;
  });
  await f.popup('identity');
  let navigations=0;f.page.on('request',request=>{if(request.isNavigationRequest()&&request.frame()===f.page.mainFrame())++navigations;});
  if(failSave){
   await f.page.evaluate(()=>{
    const transaction=IDBDatabase.prototype.transaction;
    IDBDatabase.prototype.transaction=function(stores,mode,...rest){
     if(mode==='readwrite'&&[stores].flat().includes('records'))throw new DOMException('Disco pieno di prova','QuotaExceededError');
     return transaction.call(this,stores,mode,...rest);
    };
   });
  }
  const trigger=()=>f.page.evaluate(()=>{
   const field=document.querySelector('#sheet-context-dialog [data-field="name"]');
   field.value='Ultima modifica';field.dispatchEvent(new Event('input',{bubbles:true}));
   window.__controllerChange();
  });
  if(failSave){
   await trigger();
   await f.page.waitForFunction(()=>document.querySelector('#toast')?.textContent.includes('Aggiornamento rimandato'));
   assert.equal(navigations,0,'A rejected write must keep the current document open');
   assert.equal(await f.page.locator('#sheet-context-dialog [data-field="name"]').inputValue(),'Ultima modifica');
   assert.equal(await f.page.locator('#app').evaluate(app=>app.inert),false);
  }else{
   await Promise.all([f.page.waitForEvent('load'),trigger()]);
   await f.page.locator('[data-act="library-add"]').waitFor();
   assert.equal(navigations,1);
  }
  const name=await f.page.evaluate(async id=>{
   const {loadCreature}=await import('/creatures.js');return (await loadCreature(id)).data.name;
  },id);
  assert.equal(name,failSave?'Prima':'Ultima modifica');
  assert.deepEqual(f.errors,[]);
  console.log(failSave?'PASS: failed save postpones automatic update and preserves the entered text':
   'PASS: automatic update commits the last debounced edit before reloading');
 }finally{await f.close();}
}

await archiveRecoversFromOneBadSheet();
await aasimarSheetsOpen();
await updatePreservesEdits();
await updatePreservesEdits(true);
