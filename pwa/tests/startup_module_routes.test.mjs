import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const read=path=>readFileSync(new URL(path,import.meta.url),'utf8');

test('startup module lists contain only routes served by the native PWA host',()=>{
 const main=read('../main.js'),host=read('../../network/pwa_host.gd'),sw=read('../sw.js');
 const routes=new Set([...host.matchAll(/"([^"\n]+\.js)":\s*\["res:\/\//g)].map(x=>x[1]));
 const assets=new Set([...sw.matchAll(/"(\/[^"\n]+\.js)"/g)].map(x=>x[1]));
 for(const key of ['STARTUP_MODULE_PATHS','SERIAL_STARTUP_ORDER']){
  const start=main.indexOf('const '+key+' = ['),end=main.indexOf('];',start);
  assert(start>=0&&end>start,key+' must be present');
  const paths=[...main.slice(start,end).matchAll(/"(\/[^"\n]+\.js)"/g)].map(x=>x[1]);
  assert(paths.length>15,key+' should exercise the complete startup graph');
  for(const path of paths){assert(routes.has(path),key+' imports an unserved module: '+path);
    assert(assets.has(path),key+' imports a module missing from offline shell: '+path);}
 }
});
