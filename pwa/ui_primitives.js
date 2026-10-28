// Shared, deliberately small PWA presentation primitives.
// Keep feature state in its owning view; these helpers only manage DOM/UI.
const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

export function openDialog(dialog,{removeOnClose=false}={}){
  if(!dialog)return null;
  if(removeOnClose&&!dialog.dataset.vttRemoveOnClose){
    dialog.dataset.vttRemoveOnClose='true';
    dialog.addEventListener('close',()=>dialog.remove(),{once:true});
  }
  if(!dialog.open){
    // Each view owns its initial values, including intentionally empty requests.
    if(typeof dialog.showModal==='function')dialog.showModal();
    else dialog.setAttribute('open','');
  }
  return dialog;
}

export function closeDialog(dialog,{remove=false}={}){
  if(!dialog)return;
  if(dialog.open&&typeof dialog.close==='function')dialog.close();
  else dialog.removeAttribute('open');
  if(remove)dialog.remove();
}

export function dialogCloseButton(action,label='Chiudi',className=''){
  return '<button type="button" class="'+esc(className)+' vtt-popup-close" data-act="'+esc(action)+
    '" aria-label="'+esc(label)+'" title="'+esc(label)+'">×</button>';
}

export function matchesSearch(query,...parts){
  const normalize=value=>String(value??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('it').trim();
  const needle=normalize(query);
  return !needle||normalize(parts.join(' ')).includes(needle);
}

export function pageResults(rows,limit=60){
  const all=Array.isArray(rows)?rows:[];
  const count=Math.min(all.length,Math.max(1,Math.floor(Number(limit)||60)));
  return {items:all.slice(0,count),shown:count,total:all.length,hasMore:count<all.length};
}

export function resultsFooter(action,shown,total,step=60){
  if(total<=shown)return '';
  return '<div class="vtt-results-footer"><span aria-live="polite">'+shown+' di '+total+'</span>'+
    '<button type="button" class="btn" data-act="'+esc(action)+'">Mostra altri '+
    Math.min(step,total-shown)+'</button></div>';
}
