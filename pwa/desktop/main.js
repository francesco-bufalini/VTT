import {mount, desktopSheetSession, stopRealtime} from '/ui.js';
import {request} from './bridge.js';
const controls=document.createElement('div');
controls.className='desktop-controls';
controls.innerHTML='<span>Archivio VTT · salvataggio sul computer</span><button type="button" id="desktop-native" class="btn">Strumenti nativi</button>';
document.querySelector('.topbar').after(controls);
let closing=false;
let fileBusy=false;
async function close(mode='close',extra={}){
  if(closing||fileBusy)return; closing=true;
  try { await desktopSheetSession.flush(); await request(mode,{creatureId:desktopSheetSession.currentId(),...extra}); }
  catch(error){ document.querySelector('#toast').textContent=error.message;document.querySelector('#toast').hidden=false; }
  finally{closing=false;}
}
document.querySelector('#desktop-native').onclick=()=>close('native');
desktopSheetSession.configure({cast:({casterId,selection})=>close('cast',{creatureId:casterId,selection})});
globalThis.vttDesktopClose=close;
async function fileOperation(mode,options={}){
  if(fileBusy||closing)return;
  fileBusy=true;
  try{
    await desktopSheetSession.flush();
    let result;
    if(mode==='import')result=await request('import',{}, {timeoutMs:0});
    else{
      const blob=mode==='backup'?await desktopSheetSession.exportArchive():await fetch(options.url).then(r=>r.blob());
      result=await request('download',{text:await blob.text(),filename:options.filename||'archivio_creature.json'},{timeoutMs:0});
    }
    if(result?.canceled)return;
    if(mode==='import'){
      if(result.imported>0)await desktopSheetSession.showLibrary();
      const failures=result.failures||[];
      desktopSheetSession.notify('Creature importate come copie locali: '+result.imported+'.'+
        (failures.length?' Non importati: '+failures.join('; '):''),failures.length>0);
    }else if(result?.saved)desktopSheetSession.notify('Esportazione completata: '+result.filename);
  }catch(error){showError(error);}
  finally{fileBusy=false;}
}
// External references must never replace the privileged embedded document.
document.addEventListener('click',event=>{
  if(event.target.closest('[data-nav="session"]')){
    event.preventDefault();event.stopImmediatePropagation();void close();return;
  }
  const nativeAction=event.target.closest('[data-act]')?.dataset.act;
  if(['import','backup','restore-backup'].includes(nativeAction)){
    event.preventDefault();event.stopImmediatePropagation();
    void fileOperation(nativeAction==='backup'?'backup':'import');return;
  }
  const link=event.target.closest('a[href]');
  if(link?.download&&link.href.startsWith('blob:')){
    event.preventDefault();event.stopImmediatePropagation();
    void fileOperation('download',{url:link.href,filename:link.download});return;
  }
  if(link&&new URL(link.href,location.href).origin!==location.origin){
    event.preventDefault(); event.stopImmediatePropagation();
  }
},true);
function showError(error){document.querySelector('#toast').textContent=error.message;document.querySelector('#toast').hidden=false;}
// Desktop archives use the native portable format, not a phone browser backup.
function archiveLabels(){
  for(const [action,label] of [['backup','Esporta archivio'],['restore-backup','Importa archivio']]){
    const button=document.querySelector('[data-act="'+action+'"]');
    if(button&&button.textContent!==label)button.textContent=label;
  }
}
new MutationObserver(archiveLabels).observe(document.querySelector('#app'),{childList:true,subtree:true});
document.addEventListener('keydown',event=>{
  if(event.key==='Escape'&&!document.querySelector('dialog[open]')){event.preventDefault();void close();}
});
try{
  await mount(); stopRealtime();
  const id=await request('selected');
  if(id)await desktopSheetSession.open(id);
  await request('ready');
}catch(error){
  await request('ready').catch(()=>{});
  document.querySelector('#app').textContent='Impossibile aprire la scheda: '+error.message;
}
