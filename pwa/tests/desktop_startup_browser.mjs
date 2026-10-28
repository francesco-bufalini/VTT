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
  // Static Godot host and embedded WebView must expose every transitive
  // module and catalog used by desktop/main.js -> ui.js -> sheet_rules.js.
  for(const path of ['/desktop/main.js','/ui.js','/sense_rules.js','/species_powers.js',
    '/catalog/sense_grants.json','/catalog/species_powers.json','/catalog/spell_grant_rules.json']){
    const response=await fetch(origin+path);
    assert.equal(response.status,200,'Desktop host must serve '+path);
    const type=response.headers.get('content-type')||'';
    assert.match(type,/javascript|json/,'Desktop host content type '+path);
    if(path.endsWith('.json')){
      const json=await response.text();
      assert.doesNotThrow(()=>JSON.parse(json),'Valid catalog '+path);
    }
  }
  await page.goto(origin);
  await page.waitForFunction(()=>document.querySelector('#app')?.dataset.renderedSheet==='info');
  await page.waitForFunction(()=>document.querySelector('#creature-name')?.textContent==='Lyria desktop');
  assert.equal(await page.locator('#desktop-close').count(),0,'Partita is the sole board destination');
  assert.equal(await page.evaluate(async()=>(await indexedDB.databases()).length),0,'No second browser archive');
  for(const width of [1440,1024,800,640,390]){
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
  const broken=await browser.newPage();
  await broken.route('**/desktop/main.js',route=>route.fulfill({status:200,contentType:'text/javascript',body:'import { missing } from "/desktop/storage.js";'}));
  await broken.goto(origin);
  await broken.getByText('Le creature salvate sul computer non sono state cancellate.').waitFor();
  assert(await broken.getByRole('button',{name:'Riprova',exact:true}).isVisible());
  await broken.close();
  // Missing transitive dependency must be reported without touching native data.
  const missingDependency=await browser.newPage();
  await missingDependency.route('**/sense_rules.js',route=>route.fulfill({status:404,contentType:'text/plain',body:'Not Found'}));
  await missingDependency.goto(origin);
  await missingDependency.getByText('Le creature salvate sul computer non sono state cancellate.').waitFor();
  assert(await missingDependency.getByRole('button',{name:'Riprova',exact:true}).isVisible());
  await missingDependency.close();
  // Runtime IPC failures need the same recoverable startup UI as failed imports.
  const failedArchive=await browser.newPage();
  await failedArchive.addInitScript(()=>{
    globalThis.ipc={postMessage(raw){
      const request=JSON.parse(raw);
      if(request.method==='owner'&&!sessionStorage.getItem('desktop-test-owner-failed')){
        sessionStorage.setItem('desktop-test-owner-failed','1');
        queueMicrotask(()=>globalThis.vttDesktopReceive({id:request.id,error:'Archivio temporaneamente non disponibile'}));
      }else fetch('/__test/rpc',{method:'POST',body:raw}).then(r=>r.json()).then(reply=>globalThis.vttDesktopReceive(reply));
    }};
  });
  await failedArchive.goto(origin);
  await failedArchive.getByRole('button',{name:'Riprova',exact:true}).waitFor();
  await failedArchive.getByRole('button',{name:'Riprova',exact:true}).click();
  await failedArchive.waitForFunction(()=>document.querySelector('#app')?.dataset.renderedSheet==='info');
  await failedArchive.close();
  console.log('PASS: desktop startup, native read/write, layout, missing modules and retry after archive failure');
}finally{
  await browser?.close();
  await fetch(origin+'/__test/stop').catch(()=>{});
  await new Promise(resolve=>{if(child.exitCode!==null)resolve();else{child.once('exit',resolve);setTimeout(()=>{child.kill();resolve();},3000).unref();}});
}
assert(!/SCRIPT ERROR:|^ERROR:/m.test(output),output);
