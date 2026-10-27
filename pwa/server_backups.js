import {observeArchiveChanges,setting} from './storage.js';
import {backupCredential} from './client.js';
const INTERVAL=60000;
let state={mode:'pending',savedAt:''},worker,timer,lastAttempt=0,dirty=true,busy=false,started=false,retry=INTERVAL;
const escape=value=>String(value||'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function serverBackupMarkup(){
 if(typeof globalThis.vttDesktopSaveFile==='function')return '';
 const labels={pending:'Modifiche in attesa della copia sul PC.',saving:'Salvataggio della copia sul PC…',
  saved:'Copia sul PC aggiornata.',empty:'Archivio vuoto: le copie precedenti sul PC sono conservate.',
  unpaired:'Collega il desktop per salvare una copia sul PC.',
  error:'Copia sul PC da completare. I dati restano salvati sul telefono.',
  unsupported:'Questo browser richiede Esporta backup per creare una copia esterna.'};
 return '<div id="server-backup-panel" data-backup-mode="'+state.mode+'"><p><strong>Copia automatica sul PC</strong></p>'+
  '<p role="status" aria-live="polite">'+labels[state.mode]+(state.savedAt?'<br>Ultima copia: '+escape(new Date(state.savedAt).toLocaleString()):'')+
  (state.error?'<br>'+escape(state.error):'')+'</p><p>Le modifiche vengono copiate in background mentre l’app è aperta e il PC è raggiungibile. Sul PC: Ctrl+Maiusc+P → Apri copie PWA. Per recuperare una copia, trasferisci il file backup-…json sul telefono e scegli Ripristina backup.</p>'+
  '<button type="button" class="btn" data-act="server-backup-now">Salva ora sul PC</button></div>';
}
export function syncServerBackupStatus(){
 const panel=document.querySelector('#server-backup-panel');if(panel)panel.outerHTML=serverBackupMarkup();
}
function report(update){state={...state,error:'',...update};syncServerBackupStatus();}
function schedule(immediate=false){
 dirty=true;if(!started||busy||state.mode==='unsupported')return;
 if(immediate){clearTimeout(timer);timer=null;}
 if(timer)return;
 timer=setTimeout(()=>{timer=null;void send();},immediate?0:Math.max(5000,INTERVAL-(Date.now()-lastAttempt)));
}
function retryLater(){
 dirty=true;retry=Math.min(retry*2,15*INTERVAL);clearTimeout(timer);
 timer=setTimeout(()=>{timer=null;void send();},retry);
}
async function send(){
 if(busy||!dirty)return;
 busy=true;dirty=false;lastAttempt=Date.now();
 try{
  const token=await backupCredential();
  if(!/^[a-f0-9]{64}$/i.test(token||'')){report({mode:'unpaired'});busy=false;return;}
  worker??=new Worker(new URL('./server_backup_worker.js',import.meta.url),{type:'module'});
  worker.onmessage=event=>{
   busy=false;report(event.data);
   if(event.data.mode==='error'||event.data.mode==='pending'){
    retryLater();
   }else{retry=INTERVAL;if(dirty){report({mode:'pending'});schedule();}}
  };
  worker.onerror=()=>{
   worker.terminate();worker=null;busy=false;dirty=true;
   report({mode:'error',error:'Il processo di backup non è disponibile. Il tentativo sarà ripetuto.'});retryLater();
  };
  report({mode:'saving'});worker.postMessage({token});
 }catch(error){busy=false;report({mode:'error',error:error.message});retryLater();}
}
export const serverBackups={schedule,async start(){
 if(started||typeof globalThis.vttDesktopSaveFile==='function')return;
 started=true;
 if(typeof Worker!=='function'){report({mode:'unsupported'});return;}
 try{const previous=await setting('server-backup-status');if(previous?.savedAt)report({savedAt:previous.savedAt});}catch{}
 observeArchiveChanges(()=>{report({mode:'pending'});schedule();});
 schedule();
}};
