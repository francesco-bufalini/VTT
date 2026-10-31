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
  await f.page.locator('#creature-back').click();
  await f.page.locator('[data-act="library-add"]').waitFor();
  await f.page.locator('#nav [data-nav="session"]').click();
  await f.page.locator('#pair-form').waitFor();
  await f.page.locator('[data-session-creature-errors]').waitFor();
  assert.equal(await f.page.locator('#app').getAttribute('data-page'),'session');
  assert.match(await f.page.locator('[data-session-creature-errors]').textContent(),/Vecchia variante/);
  // Bring up an isolated simulated table after testing the offline pairing screen.
  await f.page.route('**/api/**',route=>{
   const path=new URL(route.request().url()).pathname;
   const body=path==='/api/pair'?{token:'a'.repeat(64)}:
    path==='/api/session'?{protocol:1,session:'archive-recovery-test',mobile_protocol:3}:
    path==='/api/conditions'?{editions:{'2014':[],'2024':[]}}:
    path==='/api/action'?{ok:true,token_id:'placed_readable',name:'Scheda leggibile'}:
    {protocol:1,desktop_online:true,tokens:[{id:'reference',name:'Riferimento',conditions:[]}],
     combat:{active:false},devices:[],inbox:[],messages:[],events:[]};
   return route.fulfill({contentType:'application/json',body:JSON.stringify(body)});
  });
  await f.page.locator('[data-act="check"]').click();
  await f.page.locator('#pair-form button[type="submit"]').waitFor({state:'visible'});
  await f.page.locator('#pair-secret').fill('0123456789ABCDEF');
  await f.page.locator('#pair-form button[type="submit"]').click();
  await f.page.waitForFunction(id=>!!document.querySelector('#place-creature option[value="'+id+'"]'),ids.good);
  assert.equal(await f.page.locator('#place-creature option[value="'+ids.bad+'"]').count(),0);
  assert.equal(await f.page.locator('#place-creature option[value="legacy_missing_body"]').count(),0);
  assert.equal(await f.page.locator('#place-creature option[value="'+ids.unnamed+'"]').count(),0);
  await f.page.locator('[data-session-creature-errors]').waitFor();
  await f.page.locator('.session-connection-state', {hasText:'Partita connessa'}).waitFor();
  assert(await f.page.locator('.session-map-panel').isVisible(),'Map is shown without selecting a pane');
  await f.page.locator('[data-act="open-place-token"]').click();
  await f.page.locator('#place-creature').selectOption(ids.good);
  await f.page.locator('[data-act="place-creature"]').click();
  await f.page.waitForFunction(()=>!document.querySelector('#session-place-dialog')?.open);
  // Polling can replace transient notifications; dialog closure and the durable
  // token link below prove placement completed despite the other unreadable sheet.
  assert.equal(await f.page.evaluate(async id=>{
   const {getRecord}=await import('/storage.js');return (await getRecord('default','creature',id)).data.linked_token_sync_id;
  },ids.good),'placed_readable');
  await f.page.locator('[data-nav="library"]').first().click();
  await f.page.locator('[data-act="library-add"]').waitFor();
  assert.equal(await f.page.locator('[data-act="open"]').count(),4);
  const unchanged=await f.page.evaluate(async id=>{
   const {getRecord}=await import('/storage.js');return (await getRecord('default','creature',id)).data;
  },ids.bad);
  assert.deepEqual(unchanged,raw);
  assert.deepEqual(f.errors,[]);
  console.log('PASS: unreadable sheets cannot block archive, pairing, placement, refresh or valid session creatures');
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
   const worker={postMessage(message,ports){
    if(message?.type==='VTT_SHELL_REVISION')
      ports?.[0]?.postMessage({commit:'a'.repeat(40)});
   }};
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
   const field=document.querySelector('#sheet-context-dialog [data-identity-value="names"]');
   field.value='Ultima modifica';field.dispatchEvent(new Event('input',{bubbles:true}));
   window.__controllerChange();
  });
  if(failSave){
   await trigger();
   await f.page.waitForFunction(()=>document.querySelector('#toast')?.textContent.includes('Aggiornamento rimandato'));
   assert.equal(navigations,0,'A rejected write must keep the current document open');
   assert.equal(await f.page.locator('#sheet-context-dialog [data-identity-value="names"]').inputValue(),'Ultima modifica');
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

async function desktopExportOver200(){
 const f=await browserFixture();
 try{
  await f.page.goto(f.origin);await f.page.locator('[data-act="library-add"]').waitFor();
  const result=await f.page.evaluate(async()=>{
   const {initialCreature}=await import('/character_core.js');const {ownerId}=await import('/creatures.js');
   const {insertRecords}=await import('/storage.js');const owner=await ownerId();
   await insertRecords(Array.from({length:201},(_,i)=>({scope:'default',type:'creature',id:'whole_'+i,
    data:initialCreature('character','Intero '+i,'whole_'+i,owner)})));
   const {desktopSheetSession}=await import('/ui.js');const blob=await desktopSheetSession.exportArchive();
   return {count:JSON.parse(await blob.text()).entries.length};
  });
  assert.equal(result.count,201);
  assert.deepEqual(f.errors,[]);
  console.log('PASS: desktop export entry point includes an entire archive with over 200 creatures');
 }finally{await f.close();}
}

await archiveRecoversFromOneBadSheet();
await desktopExportOver200();
await aasimarSheetsOpen();
await updatePreservesEdits();
await updatePreservesEdits(true);
