import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';

const root=fileURLToPath(new URL('../../',import.meta.url));
const artifacts=new URL('../.test-artifacts/',import.meta.url);
await mkdir(artifacts,{recursive:true});
const godot=process.env.GODOT||'C:/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe';
const child=spawn(godot,['--headless','--path',root,'--script','res://tests/fixtures/desktop_sheet_server.gd'],{windowsHide:true});
let output='';
const origin=await new Promise((resolve,reject)=>{
  const timeout=setTimeout(()=>reject(Error('Desktop fixture startup timeout: '+output)),30000);
  child.stdout.on('data',data=>{output+=data;const match=output.match(/DESKTOP_TEST_ORIGIN=(http:\/\/[^\r\n]+)/);if(match){clearTimeout(timeout);resolve(match[1]);}});
  child.stderr.on('data',data=>{output+=data;});
  child.on('exit',code=>{clearTimeout(timeout);reject(Error('Fixture exited '+code+': '+output));});
});
let browser;
try{
  browser=await chromium.launch({headless:true,executablePath:process.platform==='win32'?'C:/Program Files/Google/Chrome/Application/chrome.exe':undefined});
  const page=await browser.newPage({viewport:{width:1440,height:1000}});
  page.setDefaultTimeout(20000);
  const errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  await page.addInitScript(()=>{
    globalThis.ipc={postMessage(raw){
      fetch('/__test/rpc',{method:'POST',body:raw}).then(r=>r.json()).then(reply=>globalThis.vttDesktopReceive(reply));
    }};
  });
  await page.goto(origin);
  await page.waitForFunction(()=>document.querySelector('#app')?.dataset.renderedSheet==='info');
  await page.waitForFunction(()=>document.querySelector('#creature-name')?.textContent==='Lyria desktop');
  assert.equal(await page.locator('#desktop-close').count(),0,'Partita is the sole board destination');
  assert.equal(await page.evaluate(async()=>(await indexedDB.databases()).length),0,'No second browser archive');
  for(const width of [1440,1024,800]){
    await page.setViewportSize({width,height:1000});
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Desktop horizontal fit at '+width);
  }
  await page.setViewportSize({width:1440,height:1000});
  await page.locator('[data-sheet-context="identity"]').click();
  await page.locator('#sheet-context-dialog [data-field="name"]').fill('Lyria modificata nel desktop');
  await page.locator('[data-act="sheet-context-close"]').click();
  await page.evaluate(async()=>{const {desktopSheetSession}=await import('/ui.js');await desktopSheetSession.flush();});
  const native=await page.evaluate(async()=>{
    const {request}=await import('/desktop/bridge.js');return request('get',{scope:'default',type:'creature',id:'desktop_browser_fixture'});
  });
  assert.equal(native.data.name,'Lyria modificata nel desktop');
  assert.equal(native.data.additional_traits,'Nota campagna da conservare');
  for(const sheet of ['battle','magic','inventory','info']){
    await page.locator('#sheet-navigation [data-sheet="'+sheet+'"]').click();
    await page.waitForFunction(key=>document.querySelector('#app').dataset.renderedSheet===key,sheet);
    await page.screenshot({path:fileURLToPath(new URL('desktop-'+sheet+'.png',artifacts))});
  }
  // A web edit of another creature must not change the previous native selection.
  const second=await page.evaluate(async()=>{
    const {createCreature}=await import('/creatures.js');const row=await createCreature('monster','Seconda creatura');
    const {desktopSheetSession}=await import('/ui.js');await desktopSheetSession.open(row.id);return row.id;
  });
  await page.locator('[data-sheet-context="identity"]').click();
  await page.locator('#sheet-context-dialog [data-field="name"]').fill('Mostro modificato');
  await page.locator('[data-act="sheet-context-close"]').click();
  await page.locator('#dock-session').click();
  await page.waitForFunction(async()=>{const {calls}=await fetch('/__test/calls').then(r=>r.json());return calls.some(c=>c.method==='close');});
  const calls=await page.evaluate(async()=>fetch('/__test/calls').then(r=>r.json()));
  assert.equal(calls.calls.filter(c=>c.method==='close').at(-1).args.creatureId,second);
  assert(!calls.calls.some(c=>['map','pair','session'].includes(c.method)));
  // A native concurrent edit must block stale web writes, preserving native data.
  const conflict=await page.evaluate(async()=>{
    const {request}=await import('/desktop/bridge.js');const {desktopSheetSession}=await import('/ui.js');
    await desktopSheetSession.open('desktop_browser_fixture');
    const args={scope:'default',type:'creature',id:'desktop_browser_fixture'};
    const row=await request('get',args);
    await request('put',{...args,data:{...row.data,name:'Aggiornamento nativo'},expectedRevision:row.revision});
    const {openCreatureEditor}=await import('/creatures.js');const fresh=await openCreatureEditor(args.id);
    const latest=await request('get',args);
    await request('put',{...args,data:{...latest.data,name:'Nativo più recente'},expectedRevision:latest.revision});
    try{await fresh.update({name:'Obsoleto'});return false;}catch{return (await request('get',args)).data.name==='Nativo più recente';}
  });
  assert(conflict);
  assert.deepEqual(errors,[]);
  console.log('PASS: embedded desktop UI, 800/1024/1440px, all sections, native persistence, separate creatures, Partita flush and concurrent edit protection');
}finally{
  await browser?.close();
  await fetch(origin+'/__test/stop').catch(()=>{});
  await new Promise(resolve=>{if(child.exitCode!==null)resolve();else{child.once('exit',resolve);setTimeout(()=>{child.kill();resolve();},3000).unref();}});
}
assert(!/SCRIPT ERROR:|^ERROR:/m.test(output),output);
