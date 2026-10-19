// Real browser -> native HTTP bridge -> native spell lifecycle and WebP capture.
// Uses synthetic tokens, a random loopback port and a private Godot data folder.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {readFile,mkdir,mkdtemp,writeFile,rm} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {join,resolve,sep,basename} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {chromium} from 'playwright';

const root=fileURLToPath(new URL('../../',import.meta.url));
const artifacts=resolve(root,'pwa/.test-artifacts');
await mkdir(artifacts,{recursive:true});
const runtime=await mkdtemp(join(artifacts,'spell-fixture-'));
await mkdir(join(runtime,'appdata'),{recursive:true});
const infoFile=join(runtime,'connection.json');
const executable=process.env.GODOT_PATH||'C:/Program Files/Godot/Godot_v4.7.2-stable_win64.exe';
const godot=spawn(executable,['--path',root,'--script','res://tests/fixtures/pwa_spell_server.gd',
 '--rendering-method','gl_compatibility','--audio-driver','Dummy','--resolution','800x600','--position','10000,10000'],{
 windowsHide:true,env:{...process.env,APPDATA:join(runtime,'appdata'),VTT_PWA_FIXTURE_INFO:infoFile},stdio:['ignore','pipe','pipe']});
let nativeLog='',browser;
godot.stdout.on('data',data=>{nativeLog+=data;});godot.stderr.on('data',data=>{nativeLog+=data;});
let spawnError;godot.on('error',error=>{spawnError=error;});
try{
 let info;
 for(let attempt=0;attempt<150;attempt++){
  if(spawnError)throw spawnError;
  if(godot.exitCode!==null)throw Error('Native fixture exited: '+nativeLog);
  try{info=JSON.parse(await readFile(infoFile,'utf8'));break;}catch{}
  await delay(200);
 }
 assert.ok(info,'Native fixture did not start: '+nativeLog);
 const origin='http://127.0.0.1:'+info.port;
 browser=await chromium.launch({headless:true,...(process.platform==='win32'?{
  executablePath:process.env.CHROME_PATH||'C:/Program Files/Google/Chrome/Application/chrome.exe'}:{})});
 const context=await browser.newContext({viewport:{width:390,height:844},hasTouch:true,isMobile:true});
 const page=await context.newPage();page.setDefaultTimeout(20000);
 const errors=[];page.on('pageerror',error=>errors.push(error.message));
 await page.goto(origin);
 await page.locator('#nav').waitFor();
 await page.evaluate(async info=>{
  const {setting}=await import('/storage.js');
  await setting('paired-desktop-secret',info.token);
 },info);
 await page.evaluate(async()=>{
  const {TacticalViewer}=await import('/tactical_view.js');
  const {action}=await import('/client.js');
  window.fixtureViewer=new TacticalViewer({send:action,ownerId:async()=> 'pwa-fixture-owner-123456',
   notify:()=>{},onCastAccepted:async()=>{window.fixtureCharges=(window.fixtureCharges||0)+1;}});
  await window.fixtureViewer.open('caster');
 });
 let snap=await page.evaluate(()=>window.fixtureViewer.snapshot);
 assert.equal(snap.markers.length,4);
 assert.equal(snap.token_overlays,true);
 assert.equal(snap.markers.find(m=>m.id==='high').elevation_cells,4);
 assert.equal(snap.markers.find(m=>m.id==='low').elevation_cells,-4);
 await writeFile(join(artifacts,'spell-native-elevations.webp'),Buffer.from(snap.image,'base64'));
 // Cast onto an actual token: preview must not commit until explicit confirm.
 await page.evaluate(async()=>{await window.fixtureViewer.beginSpell({spell:{id:'fireball',name:'Fireball'},slotLevel:3});});
 const victim=await page.evaluate(()=>window.fixtureViewer.snapshot.markers.find(m=>m.id==='victim'));
 const canvasPoint=await page.evaluate(v=>{
  const t=window.fixtureViewer.transform();const r=window.fixtureViewer.canvas.getBoundingClientRect();
  return {x:r.x+t.originX+v.x*t.scale,y:r.y+t.originY+v.y*t.scale};
 },victim);
 await page.mouse.click(canvasPoint.x,canvasPoint.y);
 await page.waitForFunction(()=>window.fixtureViewer.preview?.valid);
 assert.equal(await page.evaluate(()=>window.fixtureViewer.targeting.phase),'point');
 assert.ok((await page.evaluate(()=>window.fixtureViewer.preview.affected_ids)).includes('victim'));
 await page.screenshot({path:join(artifacts,'spell-pwa-aim.png')});
 await page.locator('[data-tactical="confirm-point"]').click();
 await page.waitForFunction(()=>!window.fixtureViewer.busy&&window.fixtureViewer.snapshot.areas.length>0);
 snap=await page.evaluate(()=>window.fixtureViewer.snapshot);
 assert.equal(snap.area_overlays,true);assert.ok(snap.areas.some(a=>a.shape==='sphere'));
 await writeFile(join(artifacts,'spell-native-fireball.webp'),Buffer.from(snap.image,'base64'));
 for(const width of [360,390,768,1440]){
  await page.setViewportSize({width,height:width<500?844:900});
  await page.screenshot({path:join(artifacts,'spell-pwa-'+width+'.png')});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
 }
 // Real GM saving-throw decision: apply persistent effects only on failure.
 await page.evaluate(async()=>{
  await window.fixtureViewer.beginSpell({spell:{id:'phb2014_hold_person',name:'Hold Person',source:'PHB'},slotLevel:2});
  const v=window.fixtureViewer.snapshot.markers.find(m=>m.id==='victim');
  await window.fixtureViewer.tap([v.x,v.y]);
 });
 assert.equal(await page.evaluate(()=>window.fixtureViewer.targeting.waiting_desktop),true);
 assert.equal(await page.locator('[data-tactical="finish"]').isVisible(),false);
 await page.waitForFunction(()=>window.fixtureViewer.targeting.outcome==='completed',{},{timeout:15000});
 const action=async(name,payload={})=>page.evaluate(async({name,payload})=>{
  const {action}=await import('/client.js');return action(name,payload);
 },{name,payload});
 const map=async()=>page.evaluate(async()=>{const {map}=await import('/client.js');return map();});
 let data=await map(),target=data.tokens.find(t=>t.id==='victim');
 assert.ok(target.conditions.includes('paralyzed'));assert.ok(target.active_spell_ids.length>0);
 assert.equal(data.tokens.find(t=>t.id==='caster').concentrating_spell_id,'phb2014_hold_person');
 // A second target succeeds and must receive neither condition nor spell effect.
 await page.evaluate(async()=>{
  await window.fixtureViewer.beginSpell({spell:{id:'phb2014_hold_person',name:'Hold Person',source:'PHB'},slotLevel:2});
  const v=window.fixtureViewer.snapshot.markers.find(m=>m.id==='high');
  await window.fixtureViewer.tap([v.x,v.y]);
 });
 await page.waitForFunction(()=>window.fixtureViewer.targeting.outcome==='completed',{},{timeout:15000});
 data=await map();target=data.tokens.find(t=>t.id==='high');
 assert.ok(!target.conditions.includes('paralyzed'));assert.equal(target.active_spell_ids.length,0);
 assert.ok(data.tokens.find(t=>t.id==='victim').conditions.includes('paralyzed'));
 const rejected=await action('begin_spell',{token_id:'caster',owner_id:'wrong-owner',spell_id:'fireball'});
 assert.equal(rejected.ok,false);
 // Escape must cancel the native preview as well as closing the browser viewer.
 await page.evaluate(async()=>{await window.fixtureViewer.beginSpell({spell:{id:'fireball'},slotLevel:3});});
 await page.keyboard.press('Escape');
 await page.locator('.tactical-overlay').waitFor({state:'detached'});
 const status=await action('spell_status',{token_id:'caster',owner_id:'pwa-fixture-owner-123456'});
 assert.equal(status.targeting.active,false);assert.equal(status.targeting.outcome,'cancelled');
 assert.equal(await page.evaluate(()=>window.fixtureCharges),4);
 // Exercise the actual sheet button and IndexedDB payment, not only the viewer.
 const creatureId=await page.evaluate(async()=>{
  const {setting}=await import('/storage.js');
  const {createCreature,saveCreature}=await import('/creatures.js');
  await setting('local-creature-owner-id','pwa-fixture-owner-123456');
  const created=await createCreature('character','Maga della prova connessa');
  await saveCreature({...created.data,class:'Wizard',class_source:'PHB',level:5,
   classes:[{name:'Wizard',source:'PHB',level:5}],abilities:{int:18},
   linked_token_sync_id:'caster',spell_slots_automatic:true,
   prepared_spells:[{id:'phb2014_fireball',name:'Fireball',source:'PHB',level:3,casting_classes:['class|phb|wizard']}]},
   'default',created.revision);
  return created.data.id;
 });
 await page.reload();await page.locator('[data-act="open"]').click();
 await page.locator('button[data-sheet="magic"]').first().click();
 await page.locator('#sheet-play-view [data-act="sheet-proxy"]').filter({hasText:'Fireball'}).first().click();
 const beginResponse=page.waitForResponse(r=>r.url().endsWith('/api/action')&&
  r.request().postDataJSON()?.action==='begin_spell');
 await page.locator('[data-act="action-cast-confirm"]').click();
 assert.equal((await (await beginResponse).json()).ok,true);
 await page.locator('.tactical-overlay').waitFor();
 await page.waitForFunction(async id=>{
  const {loadCreature}=await import('/creatures.js');
  return (await loadCreature(id))?.data.spell_slots_spent?.[3]===1;
 },creatureId);
 await page.locator('[data-tactical="cancel"]').click();
 await page.locator('[data-tactical="close"]').click();
 const spent=await page.evaluate(async id=>{
  const {loadCreature}=await import('/creatures.js');return (await loadCreature(id)).data.spell_slots_spent[3];
 },creatureId);
 assert.equal(spent,1,'Accepted casting pays exactly once, including after polling and cancellation');
 assert.deepEqual(errors,[]);
 assert.ok(!/(?:SCRIPT ERROR:|ERROR:)/.test(nativeLog),nativeLog);
 console.log('PASS: real Chrome/native HTTP spell targeting, held AoE WebPs, portraits at +/-4 levels, 360/390/768/1440px, GM saves/effects and Escape cleanup');
}finally{
 await browser?.close();
 godot.kill();
 await Promise.race([new Promise(done=>godot.once('exit',done)),delay(5000)]);
 await writeFile(join(artifacts,'spell-native.log'),nativeLog);
 // Only this invocation's verified fixture directory contains disposable data.
 assert.ok(resolve(runtime).startsWith(artifacts+sep)&&basename(runtime).startsWith('spell-fixture-'));
 await rm(runtime,{recursive:true,force:true});
}
