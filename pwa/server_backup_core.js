// Runs in a dedicated worker. No game commands, chat or map channel is used.
import {readBackupState, getOrCreateSetting, setting, MAX_IMPORT_BYTES} from './storage.js';
export const BACKUP_CHUNK_BYTES = 64 * 1024;
export const backupKey = () => getOrCreateSetting('server-backup-key', () =>
  Array.from(crypto.getRandomValues(new Uint8Array(32)), b => b.toString(16).padStart(2,'0')).join(''));
export async function hashText(text) {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(text))),
    b=>b.toString(16).padStart(2,'0')).join('');
}
function base64(bytes) {
  let s=''; for(let i=0;i<bytes.length;i+=32768)s+=String.fromCharCode(...bytes.subarray(i,i+32768));
  return btoa(s);
}
export async function backupRequest(route,payload,token) {
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),60000);
  try {
    const response=await fetch('/api/backup/'+route,{method:'POST',cache:'no-store',credentials:'omit',
      headers:{'Content-Type':'application/json',Authorization:'Bearer '+token},
      body:JSON.stringify(payload),signal:controller.signal});
    // Preserve the HTTP status even when a proxy sends HTML or no error body.
    // Successful responses still require valid JSON.
    const data = await response.json().catch(error => {
      if (response.ok) throw error;
      return null;
    });
    if(!response.ok){const error=Error(data?.error||'Backup server non disponibile');error.status=response.status;throw error;}
    return data;
  } finally {clearTimeout(timer);}
}
export async function syncServerBackup({token,read=readBackupState,key=backupKey,
  request=backupRequest,pause=ms=>new Promise(resolve=>setTimeout(resolve,ms)),chunkDelay=250}={}) {
  if(!/^[a-f0-9]{64}$/i.test(token||''))return {mode:'unpaired'};
  const local=await read();
  // Clearing Chrome creates a new identity. An empty installation must never
  // delete a useful server copy, even if the previous identity is later reused.
  if(!local.records.length)return {mode:'empty'};
  const auth={owner:local.owner,key:await key()};
  const manifest=await request('manifest',auth,token);
  const remote=new Map(manifest.records.map(row=>[JSON.stringify(row.key),row.hash]));
  const localKeys=new Set(),upserts=[];
  for(const record of local.records){
    const id=JSON.stringify([record.scope,record.type,record.id]);localKeys.add(id);
    const hash=await hashText(JSON.stringify(record));
    if(remote.get(id)!==hash)upserts.push({record,hash});
  }
  const deletes=[...remote.keys()].filter(id=>!localKeys.has(id)).map(id=>JSON.parse(id));
  const knownBlobs=new Set(manifest.blobs),blobs=[];
  for(const entry of local.blobs)if(!knownBlobs.has(entry.digest))
    blobs.push({digest:entry.digest,mime:entry.mime||'',base64:base64(new Uint8Array(await entry.blob.arrayBuffer()))});
  const outboxHash=await hashText(JSON.stringify(local.outbox));
  const blobDigests=local.blobs.map(entry=>entry.digest).sort();
  if(!upserts.length&&!deletes.length&&!blobs.length&&manifest.outbox_hash===outboxHash&&
     JSON.stringify([...knownBlobs].sort())===JSON.stringify(blobDigests))
    return {mode:'saved',savedAt:manifest.saved_at,unchanged:true};
  const delta={version:1,upserts,deletes,blobs,blob_digests:blobDigests,outbox:local.outbox,outbox_hash:outboxHash};
  const text=JSON.stringify(delta),bytes=new TextEncoder().encode(text);
  if(bytes.length>MAX_IMPORT_BYTES)throw Error('Backup oltre il limite di 128 MiB. Le schede restano sul telefono.');
  const upload=crypto.randomUUID().replaceAll('-','');
  const envelope={...auth,upload,base:manifest.generation,size:bytes.length,
    parts:Math.ceil(bytes.length/BACKUP_CHUNK_BYTES),sha256:await hashText(text)};
  for(let index=0;index<envelope.parts;index++){
    await request('chunk',{...envelope,index,data:base64(bytes.subarray(index*BACKUP_CHUNK_BYTES,(index+1)*BACKUP_CHUNK_BYTES))},token);
    // One in-flight request, ~256 KiB/s maximum before base64/network overhead.
    if(index+1<envelope.parts)await pause(chunkDelay);
  }
  const result=await request('commit',envelope,token);
  return {mode:'saved',savedAt:result.saved_at,bytes:bytes.length,parts:envelope.parts};
}
export async function runBackupWorker(token) {
  const run=()=>syncServerBackup({token});
  const result=globalThis.navigator?.locks?
    await navigator.locks.request('vtt-server-backup',{ifAvailable:true},lock=>lock?run():{mode:'pending'}):await run();
  if(result.mode==='saved')await setting('server-backup-status',result);
  return result;
}
