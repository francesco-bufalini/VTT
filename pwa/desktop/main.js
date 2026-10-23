import {mount, desktopSheetSession, stopRealtime} from '/ui.js';
import {request} from './bridge.js';
const controls=document.createElement('div');
controls.className='desktop-controls';
controls.innerHTML='<span>Archivio VTT · salvataggio sul computer</span><button type="button" id="desktop-native" class="btn">Strumenti nativi</button>';
document.querySelector('.topbar').after(controls);
let closing=false;
async function close(native=false){
  if(closing)return; closing=true;
  try { await desktopSheetSession.flush(); await request(native?'native':'close'); }
  catch(error){ document.querySelector('#toast').textContent=error.message;document.querySelector('#toast').hidden=false; }
  finally{closing=false;}
}
document.querySelector('#desktop-native').onclick=()=>close(true);
globalThis.vttDesktopClose=close;
// External references must never replace the privileged embedded document.
document.addEventListener('click',event=>{
  if(event.target.closest('[data-nav="session"]')){
    event.preventDefault();event.stopImmediatePropagation();void close();return;
  }
  const link=event.target.closest('a[href]');
  if(link&&new URL(link.href,location.href).origin!==location.origin){
    event.preventDefault(); event.stopImmediatePropagation();
  }
},true);
document.addEventListener('keydown',event=>{
  if(event.key==='Escape'&&!document.querySelector('dialog[open]')){event.preventDefault();void close();}
});
try{
  await mount(); stopRealtime();
  const id=await request('selected');
  if(id)await desktopSheetSession.open(id);
  await request('ready');
}catch(error){
  document.querySelector('#app').textContent='Impossibile aprire la scheda: '+error.message;
}
