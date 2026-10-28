// Session-scoped, opt-in transfers between PWAs paired to the same board.
// No browser has to expose a listening socket, and the desktop only keeps
// bounded temporary chunks until the receiver accepts or rejects the offer.
import {shareRequest} from './client.js';
import {ownerId,importCreatureFile,importHomebrewPackage} from './creatures.js';
import {getOrCreateSetting} from './storage.js';
import {openDialog,closeDialog,dialogCloseButton} from './ui_primitives.js';

const CHUNK=128*1024, MAX_BYTES=16*1024*1024;
const ignored=new Set();
const postponed=new Map();
let polling=false, lastPoll=0;
const esc=value=>String(value??'').replace(/[&<>"']/g,
  c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const errorText=error=>String(error?.message||error||'Errore di trasferimento');
async function localDevice(){
 const id=await ownerId(),userAgent=navigator.userAgent||'';
 const token=await getOrCreateSetting('pwa-device-share-secret',()=>
   [...crypto.getRandomValues(new Uint8Array(32))].map(b=>b.toString(16).padStart(2,'0')).join(''));
 const type=/iPhone|iPad/i.test(userAgent)?'iPhone / iPad':
   /Android/i.test(userAgent)?'Android':'Computer';
 return {id,token,name:type+' · '+id.slice(0,6)};
}
async function authenticatedShare(route,payload={}){
 const device=await localDevice();
 return shareRequest(route,{...payload,device_id:device.id,device_token:device.token});
}
async function directory(){
 const device=await localDevice();
 return authenticatedShare('peers',{device_name:device.name});
}
export function encodeShareChunk(bytes){
 let raw='';
 for(let i=0;i<bytes.length;i+=8192)
   raw+=String.fromCharCode(...bytes.subarray(i,i+8192));
 return btoa(raw);
}
export function decodeShareChunk(data){
 const raw=atob(data),bytes=new Uint8Array(raw.length);
 for(let i=0;i<raw.length;i++)bytes[i]=raw.charCodeAt(i);
 return bytes;
}
async function send(recipient,kind,title,payload,progress){
 const bytes=new TextEncoder().encode(JSON.stringify(payload));
 if(bytes.length<1||bytes.length>MAX_BYTES)throw Error('Pacchetto troppo grande (massimo 16 MiB).');
 const device_id=(await localDevice()).id;
 const transfer_id=crypto.randomUUID().replace(/-/g,'');
 const parts=Math.ceil(bytes.length/CHUNK);
 for(let index=0;index<parts;index++){
   await authenticatedShare('chunk',{
     device_id,recipient_id:recipient,transfer_id,kind,title,index,parts,
     size:bytes.length,data:encodeShareChunk(bytes.subarray(index*CHUNK,(index+1)*CHUNK))
   });
   progress(index+1,parts);
 }
}
export async function openSendDialog(kind,title,makePayload,notify=()=>{}){
 if(!['creature','homebrew'].includes(kind))throw Error('Tipo di condivisione non valido.');
 const roster=await directory(),peers=roster.devices||[];
 if(!peers.length)throw Error('Nessun altro dispositivo collegato alla partita.');
 const dialog=document.createElement('dialog');
 dialog.className='library-create-dialog';dialog.id='share-send-dialog';
 dialog.innerHTML='<div class="library-create-body">'+
  dialogCloseButton('share-close','Chiudi','library-create-close')+
  '<h2>Manda '+esc(title)+'</h2>'+
  '<p class="hint">Scegli un dispositivo della partita. Dovrà confermare prima di importare il contenuto.</p>'+
  '<label>Destinatario<select data-share-destination>'+
  peers.map(peer=>'<option value="'+esc(peer.id)+'">'+esc(peer.name)+'</option>').join('')+
  '</select></label><p role="status" data-share-status></p>'+
  '<div class="library-create-actions">'+
  '<button type="button" class="btn" data-share-cancel>Annulla</button>'+
  '<button type="button" class="btn primary" data-share-confirm>Manda</button></div></div>';
 let sending=false;
 const close=()=>{if(!sending)closeDialog(dialog,{remove:true});};
 dialog.querySelector('[data-share-cancel]').addEventListener('click',close);
 dialog.querySelector('[data-act="share-close"]').addEventListener('click',close);
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 dialog.addEventListener('cancel',event=>{if(sending)event.preventDefault();});
 dialog.querySelector('[data-share-confirm]').addEventListener('click',async()=>{
   if(sending)return;
   sending=true;
   const confirm=dialog.querySelector('[data-share-confirm]');
   const cancel=dialog.querySelector('[data-share-cancel]');
   const select=dialog.querySelector('[data-share-destination]');
   const status=dialog.querySelector('[data-share-status]');
   confirm.disabled=cancel.disabled=select.disabled=true;
   try{
     status.textContent='Preparazione del contenuto…';
     const payload=await makePayload();
     await send(select.value,kind,title,payload,(part,total)=>{
       status.textContent='Invio: '+part+' / '+total+' blocchi';
     });
     sending=false;
     close();
     notify('Trasferimento inviato. Il destinatario deve accettare l’importazione.');
   }catch(error){
     status.textContent=errorText(error);
     status.classList.add('warning');
     confirm.disabled=cancel.disabled=select.disabled=false;
   }finally{sending=false;}
 });
 document.body.append(dialog);
 openDialog(dialog);
}
function incomingDialog(offer,onImported,notify){
 if(document.querySelector('#share-receive-dialog')||document.querySelector('dialog[open]'))return;
 const dialog=document.createElement('dialog');
 dialog.id='share-receive-dialog';dialog.className='library-create-dialog';
 const kind=offer.kind==='creature'?'creatura':'contenuto homebrew';
 dialog.innerHTML='<div class="library-create-body">'+
   dialogCloseButton('share-later','Chiudi','library-create-close')+
   '<h2>Contenuto ricevuto</h2><p><strong>'+esc(offer.title)+'</strong></p>'+
   '<p class="hint">'+esc(offer.sender_name)+' vuole inviarti '+kind+
   '. L’importazione sarà una copia locale indipendente.</p>'+
   '<p role="status" data-share-status></p><div class="library-create-actions">'+
   '<button type="button" class="btn" data-share-later>Più tardi</button>'+
   '<button type="button" class="btn" data-share-reject>Rifiuta</button>'+
   '<button type="button" class="btn primary" data-share-accept>Importa</button></div></div>';
 let busy=false;
 const postpone=()=>{if(busy)return;postponed.set(offer.id,Date.now()+60000);closeDialog(dialog,{remove:true});};
 const dismiss=()=>{ignored.add(offer.id);closeDialog(dialog,{remove:true});};
 const buttons=[...dialog.querySelectorAll('[data-share-later],[data-act="share-later"],[data-share-reject],[data-share-accept]')];
 dialog.querySelector('[data-share-later]').addEventListener('click',postpone);
 dialog.querySelector('[data-act="share-later"]').addEventListener('click',postpone);
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 dialog.addEventListener('cancel',event=>{event.preventDefault();postpone();});
 dialog.querySelector('[data-share-reject]').addEventListener('click',async()=>{
   if(busy)return;
   busy=true;buttons.forEach(b=>b.disabled=true);
   try{
     await authenticatedShare('ack',{device_id:(await localDevice()).id,transfer_id:offer.id});
     dismiss();notify('Trasferimento rifiutato.');
   }catch(error){
     dialog.querySelector('[data-share-status]').textContent=errorText(error);
     buttons.forEach(b=>b.disabled=false);
   }finally{busy=false;}
 });
 dialog.querySelector('[data-share-accept]').addEventListener('click',async()=>{
   if(busy)return;
   busy=true;buttons.forEach(b=>b.disabled=true);
   const status=dialog.querySelector('[data-share-status]');
   let imported=false;
   try{
     if(!['creature','homebrew'].includes(offer.kind)||
       !Number.isInteger(offer.size)||offer.size<1||offer.size>MAX_BYTES||
       !Number.isInteger(offer.parts)||offer.parts!==Math.ceil(offer.size/CHUNK))
       throw Error('Metadati della condivisione non validi.');
     const device_id=(await localDevice()).id,bytes=new Uint8Array(offer.size);
     let offset=0;
     for(let index=0;index<offer.parts;index++){
       status.textContent='Ricezione: '+(index+1)+' / '+offer.parts+' blocchi';
       const part=await authenticatedShare('pull',{device_id,transfer_id:offer.id,index});
       const section=decodeShareChunk(part.data);
       if(section.length!==Math.min(CHUNK,offer.size-offset))
         throw Error('Blocco del trasferimento danneggiato.');
       bytes.set(section,offset);offset+=section.length;
     }
     status.textContent='Importazione nell’archivio…';
     const payload=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
     if(offer.kind==='creature')await importCreatureFile(payload);
     else await importHomebrewPackage(payload);
     imported=true;
     ignored.add(offer.id);
     try{await authenticatedShare('ack',{device_id,transfer_id:offer.id});}
     catch(error){console.warn('Importazione completata ma ricevuta non confermata',error);}
     closeDialog(dialog,{remove:true});
     await onImported(offer.kind);
     notify('Contenuto ricevuto e importato in locale.');
   }catch(error){
     if(imported){
       // The import is durable and its dialog is already closed. Report refresh
       // failures through the visible app notification, without offering a retry.
       notify('Importato, ma aggiornamento della schermata fallito: '+errorText(error));
     }else{
       status.textContent='Importazione non riuscita: '+errorText(error);
       status.classList.add('warning');
       buttons.forEach(b=>b.disabled=false);
     }
   }finally{busy=false;}
 });
 document.body.append(dialog);openDialog(dialog);
}
export async function pollIncomingShares(connected,onImported=async()=>{},notify=()=>{}){
 if(!connected||polling||Date.now()-lastPoll<4500)return;
 polling=true;lastPoll=Date.now();
 try{
   const listing=await directory();
   const next=(listing.inbox||[]).find(item=>item.id&&!ignored.has(item.id)&&
     Date.now()>=(postponed.get(item.id)||0));
   if(next)incomingDialog(next,onImported,notify);
 }catch(error){
   // Matches nonblocking map/chat polls: temporary disconnects are expected.
 }finally{polling=false;}
}
