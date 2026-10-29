import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {checkPwaAssets,stagedSnapshot} from '../../scripts/check_pwa_assets.mjs';

function fixture(){
 return new Map([
  ['network/pwa_host.gd','const FILES = {"/main.js": ["res://pwa/main.js", "text/javascript"], "/dep.js": ["res://pwa/dep.js", "text/javascript"]}'],
  ['pwa/sw.js','const SHELL = ["/main.js", "/dep.js"]; const CATALOGS = []; const REQUIRED_CATALOGS = [];'],
  ['pwa/main.js',"import './dep.js';"],['pwa/dep.js','export const value=1;']
 ]);
}
const snapshot=files=>({read:name=>{assert(files.has(name),'Missing '+name);return files.get(name);},exists:name=>files.has(name)});

test('asset gate accepts a complete offline module graph',()=>{
 assert.deepEqual(checkPwaAssets(snapshot(fixture())).errors,[]);
});
test('asset gate rejects a module with no host route',()=>{
 const files=fixture();files.set('network/pwa_host.gd','"/main.js": ["res://pwa/main.js", "text/javascript"]');
 assert(checkPwaAssets(snapshot(files)).errors.includes('Unserved PWA asset: /dep.js'));
});
test('asset gate follows transitive imports absent from the shell',()=>{
 const files=fixture();files.set('pwa/dep.js',"export {value} from './nested.js';");
 files.set('pwa/nested.js','export const value=1;');
 files.set('network/pwa_host.gd',files.get('network/pwa_host.gd')+'\n"/nested.js": ["res://pwa/nested.js", "text/javascript"]');
 assert(checkPwaAssets(snapshot(files)).errors.some(e=>e.includes('Module missing from offline shell: /nested.js')));
});
test('asset gate rejects missing files and wrong module MIME',()=>{
 const files=fixture();files.delete('pwa/dep.js');
 assert(checkPwaAssets(snapshot(files)).errors.includes('Missing asset file: pwa/dep.js'));
 files.set('pwa/dep.js','');files.set('network/pwa_host.gd',files.get('network/pwa_host.gd').replaceAll('text/javascript','text/html'));
 assert(checkPwaAssets(snapshot(files)).errors.includes('Invalid module MIME: /main.js'));
});
test('staged gate rejects a broken index even if the working tree is repaired',()=>{
 const directory=mkdtempSync(path.join(tmpdir(),'vtt-pwa-gate-'));
 try{
  const files=fixture();const correct=files.get('network/pwa_host.gd');
  files.set('network/pwa_host.gd','"/main.js": ["res://pwa/main.js", "text/javascript"]');
  for(const [name,text] of files){mkdirSync(path.dirname(path.join(directory,name)),{recursive:true});writeFileSync(path.join(directory,name),text);}
  execFileSync('git',['init','--quiet'],{cwd:directory});
  execFileSync('git',['add','.'],{cwd:directory,stdio:'pipe'});
  writeFileSync(path.join(directory,'network/pwa_host.gd'),correct);
  assert(checkPwaAssets(stagedSnapshot(directory)).errors.includes('Unserved PWA asset: /dep.js'));
  execFileSync('git',['add','.'],{cwd:directory,stdio:'pipe'});
  assert.deepEqual(checkPwaAssets(stagedSnapshot(directory)).errors,[]);
  execFileSync('git',['-c','user.name=Test','-c','user.email=test@example.invalid','commit','--quiet','-m','fixture'],{cwd:directory,stdio:'pipe'});
  assert.deepEqual(checkPwaAssets(stagedSnapshot(directory,'HEAD')).errors,[]);
 }finally{rmSync(directory,{recursive:true,force:true});}
});
