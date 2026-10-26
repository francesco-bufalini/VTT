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
  try {
    await desktopSheetSession.flush();
    const requestedId=extra.creatureId??desktopSheetSession.currentId();
    const creatureId=typeof requestedId==='string'?requestedId:'';
    await request(mode,{...extra,creatureId});
  }
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
      const blob=mode==='backup'?await desktopSheetSession.exportArchive():options.blob;
      if(!(blob instanceof Blob))throw Error('Il file da esportare non è disponibile.');
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
// Called by the shared PWA export helper: no blob URL, temporary fetch or download interception.
globalThis.vttDesktopSaveFile=(blob,filename)=>fileOperation('download',{blob,filename});
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
  if(link&&new URL(link.href,location.href).origin!==location.origin){
    event.preventDefault(); event.stopImmediatePropagation();
  }
},true);
function showError(error){document.querySelector('#toast').textContent=error.message;document.querySelector('#toast').hidden=false;}
// Desktop archives use the native portable format, not a phone browser backup.
function archiveLabels(){
  const brand=document.querySelector('#creature-name');
  if(brand?.textContent==='VTT Mobile')brand.textContent='VTT Desktop';
  for(const [selector,label] of [['.library-backup-copy strong','Importazione ed esportazione'],['.library-backup-content > p','Esporta una copia portatile delle creature e dei contenuti collegati, oppure importa schede VTT come nuove copie locali.']]){
    const node=document.querySelector(selector);
    if(node&&node.textContent!==label)node.textContent=label;
  }
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
  if(typeof id==='string'&&id)await desktopSheetSession.open(id);
  await request('ready');
}catch(error){
  await request('ready').catch(()=>{});
  document.querySelector('#app').textContent='Impossibile aprire la scheda: '+error.message;
}
