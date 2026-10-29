import {readFileSync, existsSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root=fileURLToPath(new URL('../',import.meta.url));

// Check the actual index, not working files that may be omitted from a commit.
export function stagedSnapshot(directory, revision=''){
 const git=(args,input)=>{
  const result=spawnSync('git',args,{cwd:directory,input,maxBuffer:32*1024*1024});
  if(result.status!==0)throw new Error(result.stderr?.toString()||'Cannot read Git index');
  return result.stdout;
 };
 const files=new Set(git(revision?['ls-tree','-r','--name-only','-z',revision]:['ls-files','-z']).toString().split('\0').filter(Boolean));
 const wanted=[...files].filter(p=>p==='network/pwa_host.gd'||
  (p.startsWith('pwa/')&&p.endsWith('.js')&&!p.startsWith('pwa/tests/')&&!p.startsWith('pwa/tools/')));
 const data=git(['cat-file','--batch'],wanted.map(p=>revision+':'+p+'\n').join(''));
 const contents=new Map();let offset=0;
 for(const name of wanted){
  const end=data.indexOf(10,offset),header=data.subarray(offset,end).toString();
  const size=Number(header.split(' ')[2]);
  if(!Number.isFinite(size))throw new Error('Cannot read staged asset: '+name);
  contents.set(name,data.subarray(end+1,end+1+size).toString());offset=end+size+2;
 }
 return {read:name=>{if(!contents.has(name))throw new Error('Missing staged source: '+name);return contents.get(name);},exists:name=>files.has(name)};
}

export function checkPwaAssets({read,exists}){
 const host=read('network/pwa_host.gd'),sw=read('pwa/sw.js');
 const routes=new Map([...host.matchAll(/"([^"\n]+)":\s*\["res:\/\/([^"\n]+)",\s*"([^"\n]+)"\]/g)]
  .map(m=>[m[1],{file:m[2],mime:m[3]}]));
 const assets=new Set();const errors=new Set();
 for(const name of ['SHELL','CATALOGS','REQUIRED_CATALOGS']){
  const block=sw.match(new RegExp('const '+name+'\\s*=\\s*\\[([\\s\\S]*?)\\]'));
  if(!block)throw new Error('Missing worker asset list: '+name);
  for(const match of block[1].matchAll(/['"](\/[^'"\n]+)['"]/g))assets.add(match[1]);
 }
 const queue=[...assets];const checked=new Set();
 while(queue.length){
  const url=queue.shift();if(checked.has(url))continue;checked.add(url);
  // Only this catalog is generated dynamically by the host.
  if(url==='/catalog/spells.json'){
   if(!host.includes('path == "/catalog/spells.json"'))errors.add('Missing dynamic spell catalog handler');
   continue;
  }
  const route=routes.get(url);
  if(!route){errors.add('Unserved PWA asset: '+url);continue;}
  if(!exists(route.file)){errors.add('Missing asset file: '+route.file);continue;}
  if(url.endsWith('.json')&&!/json/i.test(route.mime))errors.add('Invalid JSON MIME: '+url);
  if(!url.endsWith('.js'))continue;
  if(!/javascript|ecmascript/i.test(route.mime))errors.add('Invalid module MIME: '+url);
  const source=read(route.file);
  // Static imports, re-exports and literal dynamic imports share this graph.
  for(const match of source.matchAll(/(?:\bfrom\s*|\bimport\s*(?:\(\s*)?)["']([^"']+)["']/g)){
   const specifier=match[1].split(/[?#]/)[0];
   if(!specifier.startsWith('.')&&!specifier.startsWith('/'))continue;
   const target=path.posix.resolve(path.posix.dirname(url),specifier);
   if(!assets.has(target))errors.add('Module missing from offline shell: '+target+' (imported by '+url+')');
   queue.push(target);
  }
 }
 return {errors:[...errors],assets:checked.size};
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{
  const refIndex=process.argv.indexOf('--ref');
  if(refIndex>=0&&!process.argv[refIndex+1])throw new Error('--ref requires a Git revision');
  const snapshot=process.argv.includes('--staged')||refIndex>=0?stagedSnapshot(root,refIndex>=0?process.argv[refIndex+1]:''):{
   read:name=>readFileSync(path.join(root,name),'utf8'),exists:name=>existsSync(path.join(root,name))};
  const result=checkPwaAssets(snapshot);
  if(result.errors.length)throw new Error(result.errors.join('\n'));
  console.log('PASS: PWA host routes, files, MIME and offline module graph ('+result.assets+' assets)');
 }catch(error){console.error('PWA update check failed:\n'+error.message);process.exitCode=1;}
}
