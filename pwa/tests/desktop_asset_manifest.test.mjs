import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root=fileURLToPath(new URL('../../',import.meta.url));
const host=readFileSync(path.join(root,'network/pwa_host.gd'),'utf8');
const served=new Map([...host.matchAll(/"([^"]+\.(?:js|json|css))"\s*:\s*\["(res:\/\/[^"]+)",/g)]
 .map(([,url,file])=>[url,file.slice(6)]));
const desktop=new Set(['/desktop/startup.js','/desktop/main.js','/desktop/bridge.js',
 '/desktop/storage.js','/desktop/desktop.css']);
const all=new Map([...served, ...[...desktop].map(uri=>[uri,'pwa'+uri])]);
function imports(content){
 const staticModules=[...content.matchAll(/\bfrom\s*['"]([^'"]+\.js(?:#[^'"]+)?)['"]/g)].map(x=>x[1]);
 const dynamic=[...content.matchAll(/\bimport\s*\(\s*['"]([^'"]+\.js(?:#[^'"]+)?)['"]\s*\)/g)].map(x=>x[1]);
 return [...new Set([...staticModules,...dynamic])];
}
function resolveModule(parent,dep){
 const target=dep.split('#')[0];
 if(target.startsWith('/'))return path.posix.normalize(target);
 if(target.startsWith('.'))return path.posix.normalize(path.posix.join(path.posix.dirname(parent),target));
 return null;
}
test('every dependency of the Godot-served JavaScript module graph has an HTTP route',()=>{
 const missing=[];
 for(const [uri,source] of all){
  if(!uri.endsWith('.js'))continue;
  const filename=path.join(root,source);
  assert(existsSync(filename),'Missing source for '+uri+' => '+source);
  for(const dep of imports(readFileSync(filename,'utf8'))){
   const resolved=resolveModule(uri,dep);
   if(resolved&&!all.has(resolved))missing.push(uri+' -> '+resolved);
  }
 }
 assert.deepEqual(missing,[],'Every transitive module must have a Godot route');
});
test('all offline-critical racial and sense catalogs are exposed by the desktop host',()=>{
 for(const uri of ['/sense_rules.js','/species_powers.js',
  '/catalog/sense_grants.json','/catalog/species_powers.json','/catalog/spell_grant_rules.json']){
  assert(served.has(uri),'Missing Godot host mapping: '+uri);
  assert(existsSync(path.join(root,served.get(uri))),'Mapped source is missing: '+uri);
 }
});

// A valid HTTP route is insufficient when a cached module imports an uncached
// dependency while the desktop is unavailable. Check the two manifests together.
test('all Godot-served PWA modules belong to the atomic offline shell',()=>{
 const worker=readFileSync(path.join(root,'pwa/sw.js'),'utf8');
 const shell=worker.match(/const SHELL = \[([\s\S]*?)\];/);
 assert(shell,'Offline shell declaration must exist');
 const cached=new Set([...shell[1].matchAll(/['"]([^'"]+)['"]/g)].map(match=>match[1]));
 const missing=[...served.keys()].filter(uri=>uri.endsWith('.js')&&uri!=='/sw.js'&&!cached.has(uri));
 assert.deepEqual(missing,[],'Every served PWA module must remain available offline');
});
