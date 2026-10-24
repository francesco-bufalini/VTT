import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';
const child=spawn(process.env.GODOT||'C:/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe',['--headless','--path',fileURLToPath(new URL('../../',import.meta.url)),'--script','res://tests/fixtures/desktop_sheet_server.gd'],{windowsHide:true});
let output='',browser;
try{
 const origin=await new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>reject(Error('Native host startup timeout: '+output)),30000);
  child.stdout.on('data',data=>{output+=data;const m=output.match(/DESKTOP_TEST_ORIGIN=(http:\/\/[^\r\n]+)/);if(m){clearTimeout(timer);resolve(m[1]);}});
  child.stderr.on('data',data=>{output+=data;});child.on('exit',code=>{clearTimeout(timer);reject(Error('Native host exited '+code+': '+output));});
 });
 browser=await chromium.launch({headless:true,executablePath:process.platform==='win32'?'C:/Program Files/Google/Chrome/Application/chrome.exe':undefined});
 const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];page.setDefaultTimeout(15000);page.on('pageerror',e=>errors.push(e.message));
 await page.addInitScript(()=>{globalThis.ipc={postMessage(raw){fetch('/__test/rpc',{method:'POST',body:raw}).then(r=>r.json()).then(reply=>globalThis.vttDesktopReceive(reply));}};});
 await page.goto(origin);await page.waitForFunction(()=>document.querySelector('#app')?.dataset.renderedSheet==='info');
 await page.locator('[data-act="creature-variants"]').click();await page.locator('[data-variant-new]').click();
 await page.locator('[data-variant-name]').fill('Alias desktop');await page.locator('[data-variant-save]').click();
 await page.locator('.variant-list article').filter({hasText:'Alias desktop'}).getByRole('button',{name:'Usa forma'}).click();await page.locator('[data-variant-close]').click();
 await page.locator('[data-sheet-context="identity"]').click();await page.locator('#sheet-context-dialog [data-field="name"]').fill('Ombra desktop');await page.locator('[data-act="sheet-context-close"]').click();
 await page.evaluate(async()=>{const {desktopSheetSession}=await import('/ui.js');await desktopSheetSession.flush();});
 const native=await page.evaluate(async()=>{const {request}=await import('/desktop/bridge.js');return request('get',{scope:'default',type:'creature',id:'desktop_browser_fixture'});});
 assert.equal(native.data.name,'Lyria desktop');assert.equal(native.data.variants[0].values.name,'Ombra desktop');assert.equal(native.data.current_form_id,native.data.variants[0].id);
 assert.equal(await page.evaluate(async()=>(await indexedDB.databases()).length),0);
 await page.reload();await page.waitForFunction(()=>document.querySelector('#creature-name')?.textContent==='Ombra desktop');
 // Exercise the actual native bestiary client and its existing cache / copy resolver.
 const bestiary=await fetch(origin+'/catalog/bestiary.json',{signal:AbortSignal.timeout(60000)});assert.equal(bestiary.status,200);
 const catalog=await bestiary.json();assert(catalog.monsters.some(c=>c.name==='Wolf'&&c.source==='MM'));
 const response=await fetch(origin+'/catalog/bestiary/Wolf/MM.json',{signal:AbortSignal.timeout(60000)});assert.equal(response.status,200);
 const wolf=await response.json();assert.equal(wolf.name,'Wolf');assert.equal(wolf.source,'MM');assert(wolf.hp.average>0);
 assert.deepEqual(errors,[]);console.log('PASS: Chrome desktop variants persist through the native archive/reload with no browser copy; actual Godot bestiary index and Wolf stat block delivered.');
 await fetch(origin+'/__test/stop').catch(()=>{});
}finally{
 await browser?.close();
 if(child.exitCode===null)child.kill();
 await new Promise(resolve=>{if(child.exitCode!==null)resolve();else child.once('exit',resolve);});
}
assert(!/SCRIPT ERROR:|^ERROR:/m.test(output),output);
