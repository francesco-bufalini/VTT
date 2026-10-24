import {VARIANT_SECTIONS,VARIANT_PRESETS,activeVariant,createVariant,configureVariant,importVariantSections,bestiarySheet,creatureMatchesFilter,resolveVariant} from './creature_variants.js';
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function variantBar(record){
 const v=activeVariant(record);
 return '<div class="variant-bar"><div><span>Forma attuale</span><strong>'+esc(v?.name||'Base')+'</strong></div><button type="button" class="btn" data-act="creature-variants">Forme e varianti</button></div>';
}
export function openVariantsDialog({read,save,switchForm,sources,notify}){
 document.querySelector('#creature-variants-dialog')?.remove();
 const dialog=document.createElement('dialog');dialog.id='creature-variants-dialog';dialog.className='sheet-roll-dialog variants-dialog';
 let draft=null,entries=[],selectedSource=null;
 const guard=fn=>async event=>{const button=event?.currentTarget;try{if(button?.tagName==='BUTTON')button.disabled=true;await fn(event);}catch(e){notify(e.message,true);}finally{if(button?.isConnected)button.disabled=false;}};
 const close=()=>dialog.close?dialog.close():dialog.remove();
 const draw=()=>{
  const c=read(),v=activeVariant(c);
  dialog.innerHTML='<header><h2>Forme e varianti</h2><button type="button" class="btn" data-variant-close>Chiudi</button></header><p>Una sola scheda base, una forma attuale. Ogni variante conserva le sezioni personalizzate; le altre sono condivise con la base.</p><div class="variant-list">'+
   [{id:'',name:'Base · '+c.name},...(c.variants||[])].map(row=>'<article><strong>'+esc(row.name)+'</strong><div class="actions"><button type="button" class="btn" data-variant-switch="'+esc(row.id)+'"'+((c.current_form_id||'')===row.id?' disabled':'')+'>'+((c.current_form_id||'')===row.id?'Attuale':'Usa forma')+'</button>'+(row.id?'<button type="button" class="btn" data-variant-edit="'+esc(row.id)+'">Modifica</button>':'')+'</div></article>').join('')+'</div><button type="button" class="btn primary" data-variant-new>Crea variante</button><section data-variant-editor></section>';
  dialog.querySelector('[data-variant-close]').onclick=close;
  dialog.querySelector('[data-variant-new]').onclick=()=>{draft=createVariant(c,{preset:'alias',name:'Nuova variante'});edit();};
  dialog.querySelectorAll('[data-variant-switch]').forEach(b=>b.onclick=guard(async()=>{await switchForm(b.dataset.variantSwitch);draw();}));
  dialog.querySelectorAll('[data-variant-edit]').forEach(b=>b.onclick=()=>{draft=structuredClone(c.variants.find(v=>v.id===b.dataset.variantEdit));edit();});
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
  root.innerHTML='<h3>'+esc(draft.name)+'</h3><label>Nome della variante<input data-variant-name maxlength="160" value="'+esc(draft.name)+'"></label><label>Preset<select data-variant-preset>'+VARIANT_PRESETS.map(p=>'<option value="'+p.id+'"'+(draft.preset===p.id?' selected':'')+'>'+esc(p.label)+'</option>').join('')+'</select></label><p>Il preset propone le sezioni. Puoi modificarle; i limiti della capacità dipendono dalle regole della tua scheda.</p><label class="check"><input type="checkbox" data-variant-all'+(all?' checked':'')+'>Intera scheda</label><div class="variant-sections">'+VARIANT_SECTIONS.map(s=>'<label class="check"><input type="checkbox" data-variant-section="'+s.id+'"'+(all||draft.sections.includes(s.id)?' checked':'')+'>'+esc(s.label)+'</label>').join('')+'</div><p>Sezione selezionata: dati propri della variante. Sezione non selezionata: dati condivisi.</p><details><summary>Creature consentite dal preset</summary><p>Filtro JSON: ids, type, sources, max_cr, no_fly, no_swim. Un oggetto vuoto consente tutte le creature.</p><textarea data-variant-filter rows="4">'+esc(JSON.stringify(draft.creature_filter||{},null,2))+'</textarea></details><h3>Importa personalizzazioni dal bestiario</h3><p>Prima seleziona le sezioni. Puoi importarle tutte da una creatura e poi sostituire singole sezioni da altre.</p><button type="button" class="btn" data-variant-load>Apri bestiario</button><div data-variant-import-controls hidden><label>Cerca creatura<input type="search" data-variant-search></label><label>Creatura di origine<select data-variant-source></select></label><label>Sezioni da importare<select data-variant-import-section></select></label><button type="button" class="btn" data-variant-import>Importa nella variante</button></div><p data-variant-sources>'+esc(Object.entries(draft.sources||{}).map(([id,ref])=>(VARIANT_SECTIONS.find(s=>s.id===id)?.label||'Tutte')+': '+(ref.name||ref.id||'Creatura')).join(' · '))+'</p><div class="actions"><button type="button" class="btn primary" data-variant-save>Salva variante</button><button type="button" class="btn" data-variant-cancel>Annulla modifiche</button>'+(read().variants?.some(v=>v.id===draft.id)?'<button type="button" class="btn" data-variant-delete>Elimina variante</button>':'')+'</div><p>Dopo il salvataggio usa la forma e modifica i dati dai normali controlli della scheda.</p>';
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
   capture();entries=await sources();root.querySelector('[data-variant-import-controls]').hidden=false;paintSources();
  });
  const paintSources=()=>{
   const q=root.querySelector('[data-variant-search]').value.toLocaleLowerCase(),filtered=entries.filter(e=>(e.name+' '+(e.source||'')).toLocaleLowerCase().includes(q));
   const select=root.querySelector('[data-variant-source]');
   select.innerHTML='<option value="">Scegli una creatura</option>'+filtered.slice(0,100).map(e=>'<option value="'+esc(e.key)+'">'+esc(e.name+' · '+(e.source||'Locale'))+'</option>').join('');
   const ids=draft.sections.includes('*')?VARIANT_SECTIONS.map(s=>s.id):draft.sections;
   root.querySelector('[data-variant-import-section]').innerHTML='<option value="*">Tutte le sezioni personalizzate</option>'+ids.map(id=>'<option value="'+id+'">'+esc(VARIANT_SECTIONS.find(s=>s.id===id)?.label)+'</option>').join('');
  };
  root.querySelector('[data-variant-search]').oninput=paintSources;
  root.querySelector('[data-variant-import]').onclick=guard(async()=>{
   capture();selectedSource=entries.find(e=>e.key===root.querySelector('[data-variant-source]').value);
   if(!selectedSource)throw Error('Scegli una creatura dal bestiario.');
   const loaded=await selectedSource.load(),stat=loaded.stat_block||loaded;
   if(!creatureMatchesFilter({...stat,id:selectedSource.id},draft.creature_filter))throw Error('La creatura non rispetta il filtro del preset.');
   const source=loaded.kind?resolveVariant(loaded):bestiarySheet(loaded,selectedSource.miniature);
   const section=root.querySelector('[data-variant-import-section]').value;
   draft=importVariantSections(read(),draft,source,section==='*'?draft.sections:[section],{id:selectedSource.id||selectedSource.key,name:selectedSource.name,source:selectedSource.source||''});
   edit();notify('Personalizzazioni importate. Salva la variante per conservarle.');
  });
 };
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});document.body.append(dialog);draw();
 if(dialog.showModal)dialog.showModal();else dialog.setAttribute('open','');
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
