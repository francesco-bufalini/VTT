import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,readFile,readdir,rm,mkdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve,sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';
const root=fileURLToPath(new URL('../../',import.meta.url));
const folder=await mkdtemp(join(tmpdir(),'vtt-pwa-backup-'));
const child=spawn(process.env.GODOT||(process.platform==='win32'?'C:/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe':'godot'),
 ['--headless','--path',root,'--script','res://tests/fixtures/pwa_backup_server.gd'],
 {windowsHide:true,env:{...process.env,VTT_BACKUP_TEST_DIR:folder}});
let output='',browser,origin;
try{
 origin=await new Promise((resolveOrigin,reject)=>{
  const timeout=setTimeout(()=>reject(Error('Backup server timeout: '+output)),30000);
  child.stdout.on('data',data=>{output+=data;const match=output.match(/BACKUP_TEST_ORIGIN=(http:\/\/[^\r\n]+)/);if(match){clearTimeout(timeout);resolveOrigin(match[1]);}});
  child.stderr.on('data',data=>{output+=data;});
  child.on('exit',code=>{clearTimeout(timeout);reject(Error('Fixture exited '+code+': '+output));});
 });
 const headers={'Content-Type':'application/json',Authorization:'Bearer '+'e'.repeat(64)};
 assert.equal((await fetch(origin+'/api/backup/manifest',{method:'POST',body:'{}'})).status,401);
 assert.equal((await fetch(origin+'/api/backup/manifest')).status,405);
 browser=await chromium.launch({headless:true,executablePath:process.platform==='win32'?'C:/Program Files/Google/Chrome/Application/chrome.exe':undefined});
 const context=await browser.newContext({viewport:{width:390,height:844}});
 const uploads=new Map(),errors=[];
 context.on('request',request=>{
  if(request.url().endsWith('/api/backup/chunk')){
   const chunk=JSON.parse(request.postData());const parts=uploads.get(chunk.upload)||[];
   parts[chunk.index]=Buffer.from(chunk.data,'base64');uploads.set(chunk.upload,parts);
   assert.ok(parts[chunk.index].length<=65536);
  }
 });
 const page=await context.newPage();page.on('pageerror',error=>errors.push(error.message));
 await page.goto(origin);
 await page.locator('[data-act="library-add"]').waitFor({timeout:30000});
 const seeded=await page.evaluate(async()=>{
  const storage=await import('/storage.js'),creatures=await import('/creatures.js');
  await storage.setting('paired-desktop-secret','e'.repeat(64));
  const row=await creatures.createCreature('character','Lyria à recuperare');
  await storage.putAttachment('default','document','document-one',{title:'Originale'},new Blob(['documento '.repeat(15000)],{type:'text/plain'}));
  const owner=await storage.localOwnerId();
  (await import('/server_backups.js')).serverBackups.schedule(true);
  return {id:row.id,owner};
 });
 await page.waitForFunction(()=>document.querySelector('#server-backup-panel')?.dataset.backupMode==='saved',{},{timeout:30000});
 const archiveDir=join(folder,seeded.owner);
 let index=JSON.parse(await readFile(join(archiveDir,'index.json'),'utf8'));
 let archive=JSON.parse(await readFile(join(archiveDir,index.file),'utf8'));
 assert.equal(archive.records.find(r=>r.type==='creature').data.name,'Lyria à recuperare');
 assert.equal(archive.blobs.length,1);assert.ok(!JSON.stringify(archive).includes('paired-desktop-secret'));
 await page.evaluate(async id=>{
  const storage=await import('/storage.js');const row=await storage.getRecord('default','creature',id);
  await storage.putRecord('default','creature',id,{...row.data,name:'Lyria aggiornata'},row.revision);
  (await import('/server_backups.js')).serverBackups.schedule(true);
 },seeded.id);
 await page.waitForFunction(()=>document.querySelector('#server-backup-panel')?.dataset.backupMode==='saved',{},{timeout:30000});
 index=JSON.parse(await readFile(join(archiveDir,'index.json'),'utf8'));
 archive=JSON.parse(await readFile(join(archiveDir,index.file),'utf8'));
 assert.equal(archive.records.find(r=>r.type==='creature').data.name,'Lyria aggiornata');
 const deltas=[...uploads.values()].map(parts=>JSON.parse(Buffer.concat(parts).toString('utf8')));
 assert.equal(deltas.length,2);assert.equal(deltas[0].blobs.length,1);assert.equal(deltas[1].blobs.length,0);
 assert.equal(deltas[1].upserts.length,1);assert.equal(archive.blobs.length,1);
 const wrong=await fetch(origin+'/api/backup/manifest',{method:'POST',headers,
  body:JSON.stringify({owner:seeded.owner,key:'0'.repeat(64)})});assert.equal(wrong.status,403);
 await page.locator('.library-backup > summary').click();
 assert.ok(await page.locator('#server-backup-panel').isVisible());
 await page.locator('[data-act="server-backup-now"]').click();
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
 await mkdir(new URL('../.test-artifacts/',import.meta.url),{recursive:true});
 await page.screenshot({path:fileURLToPath(new URL('../.test-artifacts/server-backups-mobile.png',import.meta.url)),fullPage:true});
 await context.close(); // A new context has no old IndexedDB, cookies or permissions.
 const fresh=await browser.newContext();const recovery=await fresh.newPage();
 await recovery.goto(origin);await recovery.locator('[data-act="library-add"]').waitFor({timeout:30000});
 await recovery.evaluate(async()=>{
  await (await import('/storage.js')).setting('paired-desktop-secret','e'.repeat(64));
  (await import('/server_backups.js')).serverBackups.schedule(true);
 });
 await recovery.waitForFunction(()=>document.querySelector('#server-backup-panel')?.dataset.backupMode==='empty');
 assert.deepEqual(JSON.parse(await readFile(join(archiveDir,'index.json'),'utf8')),index,'Cleared browser preserves the server copy');
 await recovery.evaluate(async saved=>{
  const storage=await import('/storage.js');await storage.importBackup(new Blob([JSON.stringify(saved)]));
 },archive);
 const restored=await recovery.evaluate(async()=>{
  const rows=await (await import('/creatures.js')).listCreatures();const storage=await import('/storage.js');
  return {rows,owner:await storage.localOwnerId(),attachment:await (await storage.getAttachment((await storage.getRecord('default','document','document-one')).digest)).text()};
 });
 assert.equal(restored.rows[0].creature.name,'Lyria aggiornata');assert.equal(restored.rows[0].creature.owner_id,restored.owner);
 assert.notEqual(restored.owner,seeded.owner);assert.equal(restored.attachment,'documento '.repeat(15000));
 assert.deepEqual(errors,[]);await fresh.close();
 console.log('PASS: real Godot HTTP + Chromium worker, incremental attachments, durable files, clear-browser recovery, ownership and mobile layout');
}catch(error){console.error(output.slice(-5000));throw error;}
finally{
 await browser?.close();if(child.exitCode===null&&child.signalCode===null){child.kill();await new Promise(resolve=>child.once('exit',resolve));}
 assert.ok(resolve(folder).startsWith(resolve(tmpdir())+sep+'vtt-pwa-backup-'));
 await rm(folder,{recursive:true,force:true});
}
