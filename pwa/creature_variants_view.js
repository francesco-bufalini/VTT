import {VARIANT_SECTIONS,VARIANT_PRESETS,createVariant,configureVariant,importVariantSections,bestiarySheet,creatureMatchesFilter,resolveVariant} from './creature_variants.js';
import {openDialog,closeDialog,dialogCloseButton,matchesSearch,pageResults,resultsFooter} from './ui_primitives.js';
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function variantDescription(variant){
 const preset=VARIANT_PRESETS.find(p=>p.id===variant.preset);
 const label=preset&&preset.id!=='custom'?preset.label.replace(' · personalizzabile',''):'';
 const creatures=[...new Set(Object.values(variant.sources||{}).map(ref=>ref.name?ref.name+(ref.source?' ('+ref.source+')':''):'').filter(Boolean))];
 if(label||creatures.length)return [label,...creatures].filter(Boolean).join(' · ');
 return variant.sections.includes('*')?'Intera scheda':variant.sections.map(id=>VARIANT_SECTIONS.find(s=>s.id===id)?.label).filter(Boolean).join(' · ')||'Nessuna parte personalizzata';
}
const formName=v=>(v.sections?.includes('*')||v.sections?.includes('name'))&&v.values?.name?v.values.name:v.name;
export function openVariantsDialog({read,save,switchForm,sources,notify,icon=()=>'',
 subcreatures=[],addSubcreature=null,openSubcreature=null,
 manualCompanions=[],onCompanionFeature=null}){
 document.querySelector('#creature-variants-dialog')?.remove();
 const dialog=document.createElement('dialog');dialog.id='creature-variants-dialog';dialog.className='sheet-context-dialog variants-dialog';dialog.setAttribute('aria-labelledby','variants-title');
 let draft=null,entries=[],selectedSource=null,selectedSourceKey='',sourceLimit=60;
 let familiarEntries=[],familiarChoice='',familiarLimit=60;
 const guard=fn=>async event=>{const button=event?.currentTarget;try{if(button?.tagName==='BUTTON')button.disabled=true;await fn(event);}catch(e){notify(e.message,true);}finally{if(button?.isConnected)button.disabled=false;}};
 const close=()=>closeDialog(dialog,{remove:true});
 const draw=()=>{
  const c=read();
  dialog.innerHTML='<header class="variants-head"><div><small>FORME</small><h2 id="variants-title">Forme e varianti</h2></div>'+dialogCloseButton("variant-close","Chiudi","variants-icon-button")+'</header><div class="variants-content"><div class="variant-list vtt-selection-list">'+
   [{id:'',name:c.name},...(c.variants||[])].map(row=>{
    const current=(c.current_form_id||'')===row.id,name=row.id?formName(row):row.name;
    return '<article class="variant-card vtt-selectable'+(current?' is-current is-selected':'')+'"'+(current?' aria-current="true"':'')+'><span class="variant-emblem" aria-hidden="true">'+icon(row.id?'wild_shape':'proficiency')+'</span><div class="variant-copy"><strong>'+esc(name)+'</strong><small>'+esc(row.id?variantDescription(row):'Base')+'</small></div><div class="variant-actions"><button type="button" class="variants-icon-button variant-use" data-variant-switch="'+esc(row.id)+'" aria-label="'+(current?'Forma attuale · '+esc(name):'Usa forma '+esc(name))+'" title="'+(current?'Forma attuale':'Usa forma')+'"'+(current?' disabled':'')+'>'+(current?'<span aria-hidden="true">✓</span>':icon('wild_shape'))+'</button>'+(row.id?'<button type="button" class="variants-icon-button" data-variant-edit="'+esc(row.id)+'" aria-label="Modifica '+esc(name)+'" title="Modifica">'+icon('settings')+'</button>':'')+'</div></article>';
   }).join('')+'</div><button type="button" class="btn variant-create" data-variant-new>'+icon('increase')+'<span>Crea variante</span></button>'+
   (addSubcreature?'<section class="variant-familiars"><h3>Famigli e sottocreature</h3>'+
    '<div class="variant-list vtt-selection-list">'+(subcreatures.length?subcreatures.map(child=>
      '<button type="button" class="vtt-variant-source-option vtt-selectable" data-subcreature-open="'+esc(child.id)+'"><strong>'+esc(child.name)+'</strong><small>'+esc(child.bestiary_ref?.source||'Mostro')+'</small></button>').join(''):'<p class="hint">Nessuna sottocreatura collegata.</p>')+'</div>'+
    '<button type="button" class="btn variant-create" data-subcreature-new>'+icon('increase')+'<span>Aggiungi famiglio dal bestiario</span></button>'+
    '<div data-subcreature-picker hidden><label class="vtt-list-search">Cerca nel bestiario<input type="search" data-subcreature-search placeholder="Nome del mostro"></label><div class="vtt-variant-source-list vtt-selection-list" data-subcreature-choices></div><button type="button" class="btn primary" data-subcreature-create disabled>Crea scheda mostro</button></div></section>':'')+
   (manualCompanions.length?'<section class="variant-familiars"><h3>Creature da privilegi</h3>'+
      manualCompanions.map(entry=>'<button type="button" class="vtt-variant-source-option vtt-selectable" data-companion-feature="'+esc(entry.id)+'"><strong>'+esc(entry.name)+'</strong><small>'+esc(entry.source||'Sottocreatura da capacità')+'</small></button>').join('')+'</section>':'')+
   '<section data-variant-editor></section></div>';
  dialog.querySelector('[data-act="variant-close"]').onclick=event=>{event.stopPropagation();close();};
  dialog.querySelector('[data-variant-new]').onclick=()=>{draft=createVariant(c,{preset:'alias',name:'Nuova variante'});edit();};
  dialog.querySelectorAll('[data-variant-switch]').forEach(b=>b.onclick=guard(async()=>{await switchForm(b.dataset.variantSwitch);draw();}));
  dialog.querySelectorAll('[data-variant-edit]').forEach(b=>b.onclick=()=>{draft=structuredClone(c.variants.find(v=>v.id===b.dataset.variantEdit));draft.name=formName(draft);edit();});
  dialog.querySelectorAll('[data-companion-feature]').forEach(b=>b.onclick=guard(async()=>{
    if(!onCompanionFeature)throw Error('Creazione da privilegio non disponibile.');
    await onCompanionFeature(b.dataset.companionFeature);close();
  }));
  dialog.querySelectorAll('[data-subcreature-open]').forEach(b=>b.onclick=guard(async()=>{
    close();await openSubcreature(b.dataset.subcreatureOpen);
  }));
  const picker=dialog.querySelector('[data-subcreature-picker]');
  const paintFamiliars=()=>{
    if(!picker)return;
    const query=picker.querySelector('[data-subcreature-search]').value;
    const filtered=familiarEntries.filter(entry=>matchesSearch(query,entry.name,entry.source));
    const {items,shown,total}=pageResults(filtered,familiarLimit);
    picker.querySelector('[data-subcreature-choices]').innerHTML=items.map(entry=>
      '<button type="button" class="vtt-variant-source-option vtt-selectable'+(entry.key===familiarChoice?' is-selected':'')+
      '" aria-pressed="'+(entry.key===familiarChoice)+'" data-subcreature-option="'+esc(entry.key)+'"><strong>'+
      esc(entry.name)+'</strong><small>'+esc(entry.source||'Bestiario')+'</small></button>').join('')+
      resultsFooter('subcreature-more',shown,total,60);
    picker.querySelector('[data-subcreature-create]').disabled=!familiarChoice;
  };
  dialog.querySelector('[data-subcreature-new]')?.addEventListener('click',guard(async()=>{
    familiarEntries=await sources();familiarChoice='';familiarLimit=60;
    picker.hidden=false;paintFamiliars();picker.querySelector('input').focus();
  }));
  picker?.querySelector('[data-subcreature-search]').addEventListener('input',()=>{familiarLimit=60;paintFamiliars();});
  picker?.querySelector('[data-subcreature-choices]').addEventListener('click',event=>{
    const more=event.target.closest('[data-act="subcreature-more"]');
    if(more){familiarLimit+=60;paintFamiliars();return;}
    const option=event.target.closest('[data-subcreature-option]');
    if(!option)return;
    familiarChoice=option.dataset.subcreatureOption;paintFamiliars();
  });
  picker?.querySelector('[data-subcreature-create]').addEventListener('click',guard(async()=>{
    const entry=familiarEntries.find(source=>source.key===familiarChoice);
    if(!entry)throw Error('Scegli una creatura dal bestiario.');
    close();await addSubcreature(entry);
  }));
 };
 const capture=()=>{
  const root=dialog.querySelector('[data-variant-editor]');
  const sections=root.querySelector('[data-variant-all]').checked?['*']:[...root.querySelectorAll('[data-variant-section]:checked')].map(n=>n.dataset.variantSection);
  const filter=JSON.parse(root.querySelector('[data-variant-filter]').value||'{}');
  if(!filter||typeof filter!=='object'||Array.isArray(filter))throw Error('Il filtro deve essere un oggetto JSON.');
  draft=configureVariant(read(),draft,{name:root.querySelector('[data-variant-name]').value.trim(),sections,creature_filter:filter});
 };
 const edit=()=>{
  const root=dialog.querySelector('[data-variant-editor]'),all=draft.sections.includes('*');
  dialog.querySelector('.variant-list').hidden=true;dialog.querySelector('[data-variant-new]').hidden=true;
  root.innerHTML='<div class="variant-editor-heading"><button type="button" class="variants-icon-button" data-variant-back aria-label="Torna alle forme">‹</button><h3>'+esc(draft.name)+'</h3></div><div class="variant-editor-fields"><label>Nome della variante<input data-variant-name maxlength="160" value="'+esc(draft.name)+'"></label><label>Preset<select data-variant-preset>'+VARIANT_PRESETS.map(p=>'<option value="'+p.id+'"'+(draft.preset===p.id?' selected':'')+'>'+esc(p.label.replace(' · personalizzabile',''))+'</option>').join('')+'</select></label></div><fieldset class="variant-parts"><legend>Parti personalizzate</legend><label class="check variant-all"><input type="checkbox" data-variant-all'+(all?' checked':'')+'>Intera scheda</label><div class="variant-sections">'+VARIANT_SECTIONS.map(s=>'<label class="check"><input type="checkbox" data-variant-section="'+s.id+'"'+(all||draft.sections.includes(s.id)?' checked':'')+'>'+esc(s.label)+'</label>').join('')+'</div></fieldset><fieldset class="variant-import"><legend>Bestiario</legend><button type="button" class="btn" data-variant-load>'+icon('book')+'<span>Importa</span></button><div data-variant-import-controls hidden><label class="vtt-list-search">Cerca creatura<input type="search" data-variant-search></label><div class="vtt-variant-source-picker" role="group" aria-label="Scegli una creatura"><div class="vtt-variant-source-list vtt-selection-list" data-variant-source-list></div></div><label>Sezione<select data-variant-import-section></select></label><button type="button" class="btn" data-variant-import>Importa dati</button></div><div class="variant-source-tags" data-variant-sources>'+Object.entries(draft.sources||{}).map(([id,ref])=>'<span>'+esc((VARIANT_SECTIONS.find(s=>s.id===id)?.label||'Tutte')+' · '+(ref.name||ref.id||'Creatura'))+'</span>').join('')+'</div></fieldset><details class="variant-filter"><summary>Filtro creature</summary><textarea data-variant-filter aria-label="Filtro creature JSON" rows="4">'+esc(JSON.stringify(draft.creature_filter||{},null,2))+'</textarea></details><footer class="variant-editor-actions"><button type="button" class="btn primary" data-variant-save>Salva variante</button><button type="button" class="btn" data-variant-cancel>Annulla</button>'+(read().variants?.some(v=>v.id===draft.id)?'<button type="button" class="btn danger" data-variant-delete>Elimina</button>':'')+'</footer>';
  root.querySelector('[data-variant-back]').onclick=()=>{draft=null;draw();};
  root.querySelector('[data-variant-all]').onchange=e=>root.querySelectorAll('[data-variant-section]').forEach(b=>b.checked=e.target.checked);
  root.querySelector('[data-variant-preset]').onchange=guard(async e=>{
   capture();const preset=VARIANT_PRESETS.find(p=>p.id===e.target.value);
   draft=configureVariant(read(),draft,{sections:preset.sections,preset:preset.id,creature_filter:preset.creature_filter});edit();
  });
  root.querySelector('[data-variant-cancel]').onclick=()=>{draft=null;draw();};
  root.querySelector('[data-variant-save]').onclick=guard(async()=>{capture();const c=read(),variants=[...(c.variants||[])],i=variants.findIndex(v=>v.id===draft.id);if(i<0)variants.push(draft);else variants[i]=draft;await save({variants,variant_schema_version:1});draft=null;draw();});
  root.querySelector('[data-variant-delete]')?.addEventListener('click',guard(async()=>{
   const c=read();if(c.current_form_id===draft.id)await switchForm('');
   await save({variants:read().variants.filter(v=>v.id!==draft.id)});draft=null;draw();
  }));
  root.querySelector('[data-variant-load]').onclick=guard(async()=>{
   capture();entries=await sources();selectedSourceKey='';sourceLimit=60;root.querySelector('[data-variant-import-controls]').hidden=false;paintSources();
  });
  const paintSources=()=>{
   const q=root.querySelector('[data-variant-search]').value;
   const filtered=entries.filter(e=>matchesSearch(q,e.name,e.source));
   const {items,shown,total}=pageResults(filtered,sourceLimit);
   const list=root.querySelector('[data-variant-source-list]');
   list.innerHTML=(items.length?items.map(e=>
    '<button type="button" class="vtt-variant-source-option vtt-selectable'+(e.key===selectedSourceKey?' is-selected':'')+
    '" aria-pressed="'+(e.key===selectedSourceKey)+'" data-variant-source-key="'+esc(e.key)+'">'+
    '<strong>'+esc(e.name)+'</strong><small>'+esc(e.source||'Locale')+'</small></button>').join(''):
    '<p class="hint">Nessuna creatura corrispondente.</p>')+resultsFooter('variant-source-more',shown,total,60);
   const ids=draft.sections.includes('*')?VARIANT_SECTIONS.map(s=>s.id):draft.sections;
   root.querySelector('[data-variant-import-section]').innerHTML='<option value="*">Tutte le sezioni personalizzate</option>'+ids.map(id=>'<option value="'+id+'">'+esc(VARIANT_SECTIONS.find(s=>s.id===id)?.label)+'</option>').join('');
  };
  root.querySelector('[data-variant-search]').oninput=()=>{sourceLimit=60;paintSources();};
  root.querySelector('[data-variant-source-list]').onclick=event=>{
   const more=event.target.closest('[data-act="variant-source-more"]');
   if(more){event.stopPropagation();sourceLimit+=60;paintSources();return;}
   const button=event.target.closest('[data-variant-source-key]');
   if(!button)return;
   selectedSourceKey=selectedSourceKey===button.dataset.variantSourceKey?'':button.dataset.variantSourceKey;
   root.querySelectorAll('[data-variant-source-key]').forEach(row=>{
    const active=row.dataset.variantSourceKey===selectedSourceKey;
    row.setAttribute('aria-pressed',String(active));row.classList.toggle('is-selected',active);
   });
  };
  root.querySelector('[data-variant-import]').onclick=guard(async()=>{
   capture();selectedSource=entries.find(e=>e.key===selectedSourceKey);
   if(!selectedSource)throw Error('Scegli una creatura dal bestiario.');
   const loaded=await selectedSource.load(),stat=loaded.stat_block||loaded;
   if(!creatureMatchesFilter({...stat,id:selectedSource.id},draft.creature_filter))throw Error('La creatura non rispetta il filtro del preset.');
   const source=loaded.kind?resolveVariant(loaded):bestiarySheet(loaded,selectedSource.miniature);
   const section=root.querySelector('[data-variant-import-section]').value;
   draft=importVariantSections(read(),draft,source,section==='*'?draft.sections:[section],{id:selectedSource.id||selectedSource.key,name:selectedSource.name,source:selectedSource.source||''});
   edit();notify('Dati importati.');
  });
 };
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});document.body.append(dialog);draw();
 openDialog(dialog);
 return dialog;
}
export async function variantSources(localCreatures,homebrew=[]){
 const local=localCreatures.filter(c=>c.kind==='monster').map(c=>({key:'local:'+c.id,id:c.id,name:c.name,source:c.source||'Archivio locale',load:async()=>c}));
 const custom=homebrew.filter(r=>r.id?.split(':')[2]==='monsters').map(r=>({key:r.id,id:r.id,name:r.data.name,source:r.data.source||'Homebrew',load:async()=>r.data.data}));
 let remote=[];
 try{
  const response=await fetch('/catalog/bestiary.json');if(!response.ok)throw Error('Bestiario non disponibile.');
  const data=await response.json();
  let miniatures=[];try{const r=await fetch('/catalog/miniatures.json');miniatures=(await r.json()).tokens||[];}catch{}
  remote=(data.monsters||[]).map(c=>({...c,key:'bestiary:'+c.name+'|'+c.source,id:c.id||'bestiary:'+c.name+'|'+c.source,
   miniature:miniatures.find(m=>m.name?.toLowerCase()===c.name?.toLowerCase()),load:async()=>{
    const r=await fetch('/catalog/bestiary/'+encodeURIComponent(c.name)+'/'+encodeURIComponent(c.source)+'.json');
    if(!r.ok)throw Error('Dati della creatura non disponibili. Collegati al desktop per scaricarli.');return r.json();
   }}));
 }catch(error){if(!local.length&&!custom.length)throw error;}
 return [...local,...custom,...remote];
}
