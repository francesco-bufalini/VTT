import { status, session, pair, unpair, map, action, subscribeMap, takeQrPairCode } from "./client.js";
import { listCreatures, loadCreature, createCreature, importCreatureFile, exportCreature,
  removeCreature, openCreatureEditor, ownerId } from "./creatures.js";
import { TacticalViewer } from "./tactical_view.js";
import { createDemoCreature } from "./demo.js";
import { CATALOG_CATEGORIES, catalogEntries, detailedEntry, flattenDescription } from "./catalog_data.js";
import { exportBackup, importBackup } from "./storage.js";

const app = document.querySelector("#app");
const nav = document.querySelector("#nav");
const connection = document.querySelector("#connection");
const creatureInput = document.querySelector("#import-creature");
const backupInput = document.querySelector("#import-backup");
const toastElement = document.querySelector("#toast");
const sections = new Set(["library", "catalog", "dice", "chat", "session"]);
const conditions = ["blinded","charmed","deafened","exhaustion","frightened",
  "grappled","incapacitated","invisible","paralyzed","petrified","poisoned",
  "prone","restrained","stunned","unconscious","concentrating","surprised","hidden","dead"];
const abilities = {str:"Forza",dex:"Destrezza",con:"Costituzione",int:"Intelligenza",wis:"Saggezza",cha:"Carisma"};
const state = { page:"library", creatureId:null, editor:null, sheet:"stats", map:null,
  tokenId:"", online:false, paired:false, session:null, errors:[], messages:[],
  after:"", rollHistory:[], roll:null, stopMap:null, pollChat:null, renderTicket:0,
  librarySelectedIds:new Set(),
  hostReachable:false, catalogCategory:"items", catalogQuery:"", catalogRows:[], catalogSelected:-1,
  castCreatureId:"", castSpellIndex:0, castLevel:1,
  attackRange:30, attackLongRange:0, attackMelee:false,
  saving:false, saveError:"", pendingActions:0, busy:false };
let tacticalViewer=null;
let toastTimer = null;
const pendingFieldTimers = new Map();
async function flushPendingFields() {
  const targets = [...pendingFieldTimers.keys()];
  for (const target of targets) {
    clearTimeout(pendingFieldTimers.get(target));
    pendingFieldTimers.delete(target);
    if (target.isConnected && state.editor) await handleField(target);
  }
  if (state.editor) await state.editor.flush();
}
function esc(value) { return String(value ?? "").replace(/[&<>"']/g, c =>
  ({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" })[c]); }
function text(value) { return String(value ?? "").trim(); }
function number(value, fallback=0) { const n = Number(value); return Number.isFinite(n) ? n : fallback; }
function btn(name, label, variant="") { return '<button type="button" class="btn '+variant+'" data-act="'+esc(name)+'">'+label+'</button>'; }
function header(eyebrow, title, subtitle) {
  return '<div class="page-head"><p class="eyebrow">'+esc(eyebrow)+'</p><h1>'+esc(title)+
    '</h1><p>'+esc(subtitle)+'</p></div>';
}
function panel(title, body, className="") {
  return '<section class="panel '+className+'"><h2>'+esc(title)+'</h2>'+body+'</section>';
}
function tag(label) { return '<span class="tag">'+esc(label)+'</span>'; }
function field(label, key, value, type="text", more="") {
  const val = value ?? "";
  return '<label>'+esc(label)+'<input data-field="'+esc(key)+'" type="'+esc(type)+
    '" value="'+esc(val)+'" '+more+'></label>';
}
function area(label, key, value, rows=3) {
  return '<label>'+esc(label)+'<textarea data-field="'+esc(key)+'" rows="'+rows+'">'+esc(value ?? "")+'</textarea></label>';
}
function message(textValue, error=false) {
  clearTimeout(toastTimer);
  toastElement.hidden = false;
  toastElement.textContent = textValue;
  toastElement.style.borderColor = error ? "#c77b82" : "";
  toastTimer = setTimeout(() => { toastElement.hidden = true; }, 4500);
}
function errorMessage(error) {
  const code = Number(error?.status);
  if (code === 503) return "Apri una partita sul desktop per completare il collegamento.";
  if (code === 401) return "Associazione necessaria: inserisci il codice del desktop.";
  return error instanceof Error ? error.message : String(error);
}
function syncNav() {
  for(const button of nav.querySelectorAll("[data-nav]")) {
    const current = button.dataset.nav === state.page;
    if(current) button.setAttribute("aria-current","page");
    else button.removeAttribute("aria-current");
  }
  connection.textContent = state.paired && state.online ? "● Partita collegata" :
    state.online ? "● Desktop in partita" : state.hostReachable ? "○ Nessuna partita aperta" : "○ Archivio offline";
  connection.classList.toggle("connected",state.paired && state.online);
}
function download(blob, filename) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url; link.download = filename; link.style.display = "none";
  document.body.append(link); link.click(); link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60000);
}
function filename(value) { return text(value).replace(/[^a-zA-Z0-9_-]/g,"_").slice(0,60) || "creatura"; }
function selectedName() { return state.editor?.read().name || "Giocatore"; }
function stopSubscriptions() {
  state.stopMap?.(); state.stopMap = null;
  if(state.pollChat) { clearInterval(state.pollChat); state.pollChat = null; }
}
async function navigate(page, id=null) {
  if (!sections.has(page)) return;
  if (state.editor) {
    try { await flushPendingFields(); }
    catch (error) { message("Salvataggio bloccato: "+errorMessage(error),true); return; }
  }
  stopSubscriptions();
  state.page=page; state.creatureId=id; state.editor=null;
  if (page==="chat" || page==="session" || page==="catalog") state.cachedCreatures=(await listCreatures()).map(row=>row.creature);
  await render();
}
async function render() {
  const ticket = ++state.renderTicket;
  syncNav();
  try {
    let html = "";
    if (state.page === "library") html = await libraryView();
    else if (state.page === "catalog") html = await catalogView();
    else if (state.page === "dice") html = diceView();
    else if (state.page === "chat") html = chatView();
    else if (state.page === "session") html = sessionView();
    if(ticket !== state.renderTicket) return;
    app.innerHTML = html;
    if(state.page === "session" && state.paired) startMap();
    if(state.page === "chat" && state.paired) startChat();
  } catch(error) {
    if(ticket !== state.renderTicket) return;
    app.innerHTML = header("Errore", "Operazione non riuscita", errorMessage(error))+
      btn("refresh","Riprova","primary");
  }
}
async function libraryView() {
  if(state.creatureId) return editorView();
  const rows = await listCreatures();
  const availableIds=new Set(rows.map(row=>row.creature.id));
  for(const id of state.librarySelectedIds)if(!availableIds.has(id))state.librarySelectedIds.delete(id);
  let list = rows.map(({creature:c}) =>
    '<article class="creature-card"><label class="library-batch-check" aria-label="Seleziona '+esc(c.name)+'">'+
      '<input type="checkbox" data-library-select="'+esc(c.id)+'" '+
      (state.librarySelectedIds.has(c.id)?'checked':'')+'></label>'+
      '<div class="creature-avatar" aria-hidden="true">'+
      (c.kind === "monster" ? "◆" : "♜")+'</div><div class="creature-info"><div class="creature-name">'+
      esc(c.name)+'</div><div class="creature-details">'+
      esc(c.kind === "monster" ? "Mostro" : "Personaggio")+' · '+
      esc(c.class || c.species || c.type || "Scheda locale")+
      (c.level ? " · Liv. "+esc(c.level) : "")+'</div></div>'+
      '<button type="button" class="btn small" data-act="open" data-id="'+esc(c.id)+
      '" aria-label="Apri '+esc(c.name)+'">Apri →</button></article>').join("");
  if(!list) list = '<div class="empty"><div class="symbol">♜</div>'+
    '<strong>Nessuna creatura salvata</strong><p>Crea una scheda, importa un JSON da VTT desktop o Android, oppure prova il personaggio dimostrativo.</p>'+btn("demo","Prova personaggio demo","primary")+'</div>';
  return header("Archivio indipendente", "Le tue creature", "Le schede rimangono sul dispositivo e si aprono anche senza il desktop.")+
    '<div class="actions">'+btn("create","＋ Nuovo personaggio","primary")+
    btn("import","Importa scheda")+btn("backup","Esporta backup")+btn("restore-backup","Importa backup")+'</div>'+
    (rows.length?'<div class="actions">'+btn("library-select-all","Seleziona tutte")+
      '<span id="library-selected-actions">'+(state.librarySelectedIds.size ?
        btn("library-select-none","Deseleziona")+
        btn("library-export","Esporta ('+state.librarySelectedIds.size+')")+
        btn("library-delete","Elimina ('+state.librarySelectedIds.size+')","danger") : '')+
      '</span></div>':'')+list+
    '<p class="hint">L’archivio usa IndexedDB. Esporta periodicamente un backup: iOS può eliminare i dati dei siti in alcune condizioni.</p>';
}
function renderCatalogRows() {
  const filter=state.catalogQuery.trim().toLocaleLowerCase();
  const matches=state.catalogRows.map((row,i)=>({row,i})).filter(({row})=>{
    const string=String(row.name||"")+" "+String(row.source||"");
    return !filter || string.toLocaleLowerCase().includes(filter);
  }).slice(0,90);
  return matches.length?matches.map(({row,i})=>
    '<button type="button" class="btn full catalog-entry" data-act="catalog-open" data-index="'+i+'">'+
    '<span>'+esc(row.name||"Senza nome")+'</span><span class="tag">'+esc(row.source||row._category||"")+'</span></button>').join("") :
    '<p class="hint">Nessun risultato. Prova un altro termine o una categoria.</p>';
}
async function catalogView() {
  state.catalogRows=await catalogEntries(state.catalogCategory);
  const chosen=state.catalogRows[state.catalogSelected];
  let detail="";
  if(chosen){
    const full=await detailedEntry(state.catalogCategory,chosen);
    const description=flattenDescription(full);
    const assignable=["spells","feats","backgrounds","races","weapons","armor","tools",
      "mundane_items","magic_items","items"].includes(chosen._category||state.catalogCategory);
    detail=panel("Dettagli · "+String(full.name||""),'<p class="hint">'+
      esc(full.source||"Fonte sconosciuta")+'</p><p class="notable catalog-description">'+
      esc(description||"Descrizione non disponibile nell'archivio locale.")+'</p>'+
      (full._description_warning?'<p class="warning">'+esc(full._description_warning)+'</p>':"")+
      (assignable && (state.cachedCreatures||[]).length?
      '<div class="separator"></div><label>Aggiungi alla scheda<select id="catalog-creature">'+
      state.cachedCreatures.map(c=>'<option value="'+esc(c.id)+'">'+esc(c.name)+'</option>').join("")+
      '</select></label><div class="actions">'+btn("catalog-assign","Aggiungi contenuto alla creatura","primary")+'</div>'+
      '<p class="hint">La PWA salva il riferimento; i bonus delle origini vengono calcolati solo nel motore Godot.</p>':""));
  }
  return header("Compendio", "Catalogo", "Fonti strutturate incluse in VTT. Il catalogo base è disponibile offline dopo l'installazione.")+
    panel("Esplora",'<div class="columns"><label>Sezione<select id="catalog-category">'+
      CATALOG_CATEGORIES.map(([id,label])=>
      '<option value="'+id+'" '+(state.catalogCategory===id?'selected':'')+'>'+label+'</option>').join("")+
      '</select></label><label>Ricerca<input id="catalog-search" type="search" value="'+esc(state.catalogQuery)+
      '" placeholder="Nome o fonte"></label></div><p class="hint">'+
      state.catalogRows.length+' voci nel catalogo · fino a 90 risultati per pagina</p>'+
      '<div id="catalog-results" class="catalog-results">'+renderCatalogRows()+'</div>')+
    detail;
}

async function editorView() {
  if(!state.editor) state.editor = await openCreatureEditor(state.creatureId);
  const c = state.editor.read();
  const tabs = [["stats","Statistiche"],["origins","Origini"],["inventory","Inventario"],
    ["magic","Incantesimi"],["resources","Risorse"],["notes","Note"],["json","JSON"]];
  const navigation = '<div class="editor-head">'+
    '<button type="button" class="btn small ghost" data-act="back">← Indietro</button>'+
    '<h1>'+esc(c.name)+'</h1></div>'+
    '<div class="row between editor-meta">'+tag(c.kind === "monster" ? "Mostro" : "Personaggio")+
    '<span id="save-state" class="save-status'+(state.saveError?" error":"")+'">'+
    (state.saveError ? esc(state.saveError) : "✓ Salvato in locale")+'</span></div>'+
    '<div class="section-tabs" role="tablist" aria-label="Scheda creatura">'+tabs.map(([key,title]) =>
      '<button role="tab" type="button" data-act="sheet" data-sheet="'+key+'" aria-pressed="'+
      (state.sheet===key)+'">'+title+'</button>').join("")+'</div>';
  let body = "";
  switch(state.sheet){
  case "stats":
    body = panel("Identità",'<div class="columns">'+field("Nome","name",c.name)+
      field("Giocatore","player_name",c.player_name)+field("Classe","class",c.class)+
      field("Livello","level",c.level??1,"number",'min="1" max="20"')+'</div>')+
      panel("Combattimento",'<div class="columns three">'+
      field("PF attuali","current_hp",c.current_hp??1,"number")+
      field("PF massimi","max_hp_base",c.max_hp_base??c.max_hp??1,"number",'min="0"')+
      field("PF temporanei","temporary_hp",c.temporary_hp??0,"number",'min="0"')+
      field("CA base","armor_class_base",c.armor_class_base??c.armor_class??10,"number",'min="0"')+
      field("Iniziativa","initiative",c.initiative??0,"number")+
      field("Velocità (ft)","speed_base",c.speed_base??c.speed??30,"number",'min="0"')+'</div>'+
      '<p class="hint">I valori derivati (CA, iniziativa e velocità effettive) vengono calcolati dalla versione nativa di VTT; la PWA modifica i valori base.</p>')+
      panel("Caratteristiche",'<div class="columns three">'+Object.entries(abilities).map(([k,label])=>
        '<div class="ability-box"><label>'+label+'<input data-ability="'+k+
        '" type="number" min="1" max="30" value="'+esc(c.abilities?.[k]??10)+'"></label></div>').join("")+'</div>');
    break;
  case "origins":
    body = '<p class="warning">Modifica i riferimenti alle origini qui; il calcolo di privilegi, competenze e bonus rimane affidato alle regole della versione nativa.</p>'+
      panel("Origini",'<div class="columns">'+field("Specie","species",c.species)+
      field("Fonte specie","species_source",c.species_source)+
      field("Background","background",c.background)+
      field("Sottoclasse","subclass",c.subclass)+
      field("Allineamento","alignment",c.alignment)+
      field("Edizione","rules_version",c.rules_version||"2014")+'</div>')+
      panel("Tratti e personalità",area("Tratti del personaggio","personality_traits",c.personality_traits)+
        area("Ideali","ideals",c.ideals)+area("Legami","bonds",c.bonds)+area("Difetti","flaws",c.flaws));
    break;
  case "inventory":
    body = panel("Oggetti nell’inventario",'<p class="hint">I dati aggiunti agli oggetti originali (ID, equipaggiamento, homebrew) vengono mantenuti.</p>'+
      (Array.isArray(c.inventory) ? c.inventory.map((item,index) => inventoryRow(item,index)).join("") : "")+
      '<div class="actions">'+btn("add-item","＋ Aggiungi oggetto","primary")+'</div>');
    break;
  case "magic":
    body = panel("Slot incantesimo",'<p class="hint">Modifica il consumo degli slot. I lanci effettuati dalla sezione Partita usano le regole Godot. I privilegi speciali richiedono ancora la versione nativa.</p>'+
      '<div class="columns three">'+Array.from({length:9},(_,i)=>{const level=i+1,tot=c.spell_slots_total?.[level]??0,spent=c.spell_slots_spent?.[level]??0;
      return '<div class="ability-box"><label>Liv. '+level+'<input type="number" min="0" data-slot="'+level+
        '" value="'+esc(spent)+'"></label><span class="hint">Usati / '+esc(tot)+'</span></div>';}).join("")+'</div>')+
      panel("Incantesimi conosciuti",spellList(c,"spells"))+
      panel("Incantesimi preparati",spellList(c,"prepared_spells"))+
      panel("Libro degli incantesimi",spellList(c,"spellbook_spells"));
    break;
  case "resources":{
    const trackers=Array.isArray(c.resource_trackers)?c.resource_trackers:[];
    const spent=c.resource_tracker_spent && typeof c.resource_tracker_spent==="object"?
      c.resource_tracker_spent:{};
    body=panel("Utilizzi e risorse",
      '<p class="hint">Contatori salvati nella scheda con la struttura nativa di VTT. I tracker derivati automaticamente da classe o privilegi vengono calcolati solo da Godot.</p>'+
      (trackers.length?trackers.map((t,i)=>{
        const max=Math.max(0,Number(t.max)||0);
        const used=Math.max(0,Number(spent[t.id])||0);
        return '<div class="list-item"><div class="row between"><strong>'+esc(t.name||"Risorsa")+
          '</strong><button type="button" class="btn small danger" data-act="tracker-delete" data-index="'+i+'">Elimina</button></div>'+
          '<div class="row between"><span class="hint">Disponibili: '+esc(Math.max(0,max-used))+
          ' / '+esc(max)+' · '+esc(t.recharge||"manual")+'</span><span class="row">'+
          '<button type="button" class="btn small" data-act="tracker-less" data-index="'+i+'" aria-label="Ripristina un utilizzo">−</button>'+
          '<button type="button" class="btn small" data-act="tracker-more" data-index="'+i+'" aria-label="Consuma un utilizzo">＋</button></span></div></div>';
      }).join(""):'<p class="hint">Nessun tracker manuale salvato.</p>')+
      '<div class="actions">'+btn("tracker-short","Riposo breve")+btn("tracker-long","Riposo lungo")+'</div>')+
      panel("Aggiungi tracker",'<div class="columns">'+
      '<label>Nome<input type="text" id="tracker-name" maxlength="120" placeholder="Es. Ispirazione bardica"></label>'+
      '<label>Utilizzi massimi<input type="number" id="tracker-max" min="1" max="99999" value="1"></label></div>'+
      '<label>Ricarica<select id="tracker-recharge"><option value="manual">Manuale</option>'+
      '<option value="turn">Inizio turno</option><option value="short_rest">Riposo breve</option>'+
      '<option value="long_rest">Riposo lungo</option></select></label>'+
      '<div class="actions">'+btn("tracker-add","Aggiungi risorsa","primary")+'</div>');
    break;
  }
  case "notes":
    body = panel("Profilo",area("Descrizione fisica","appearance",c.appearance,5)+
      area("Storia","background_personality",c.background_personality,5)+
      area("Tratti aggiuntivi","additional_traits",c.additional_traits,5)+
      area("Appunti","notes",c.notes,5))+
      panel("Condizioni personali",'<div class="pillbox">'+conditions.map(id=>
        '<label class="check pill"><input type="checkbox" data-condition="'+id+'" '+
        ((c.conditions||[]).includes(id)?"checked":"")+'>'+esc(id)+'</label>').join("")+'</div>');
    break;
  case "json":
    body = panel("Editor avanzato",'<p class="warning">Modifica JSON per campi non ancora presenti nella GUI. La scheda viene validata prima del salvataggio; ID e proprietario non possono cambiare.</p>'+
      '<label>Documento completo<textarea id="json-editor" rows="18" spellcheck="false" class="inline-code">'+
        esc(JSON.stringify(c,null,2))+'</textarea></label><div class="actions">'+
      btn("save-json","Salva modifiche JSON","primary")+'</div>');
    break;
  }
  return navigation+body+'<div class="actions">'+btn("export","Esporta JSON")+
    btn("delete","Elimina scheda","danger")+'</div>';
}
function inventoryRow(item,index) {
  const obj = item && typeof item === "object" ? item : {name:String(item??"")};
  return '<div class="list-item"><div class="row between"><strong>Oggetto '+(index+1)+'</strong>'+
    '<button type="button" class="btn danger small" data-act="remove-item" data-index="'+index+'">Rimuovi</button></div>'+
    '<div class="columns">'+listField("Nome",index,"name",obj.name||obj.title)+
    listField("Quantità",index,"quantity",obj.quantity??1,"number")+'</div>'+
    '<label>Descrizione<textarea data-item-index="'+index+'" data-item-key="description" rows="2">'+
    esc(obj.description||"")+'</textarea></label></div>';
}
function listField(label,index,key,value,type="text") {
  return '<label>'+label+'<input type="'+type+'" data-item-index="'+index+'" data-item-key="'+key+
    '" value="'+esc(value)+'" '+(type==="number"?'min="0"':"")+'></label>';
}
function spellList(c,key) {
  const rows=Array.isArray(c[key])?c[key]:[];
  return '<div class="stack">'+(rows.length?rows.map((spell,i)=>{
    const name=typeof spell==="string" ? spell :
      text(spell?.name || spell?.id || JSON.stringify(spell));
    return '<div class="row between"><div class="grow">'+tag(name || "Incantesimo senza nome")+
      '</div><button type="button" class="btn danger small" data-act="remove-spell" data-key="'+
      key+'" data-index="'+i+'">Rimuovi</button></div>';
  }).join(""):'<p class="hint">Nessun incantesimo.</p>')+
    '<div class="row"><input type="text" id="new-'+key+'" placeholder="Nome o ID incantesimo" aria-label="Nome o ID incantesimo">'+
    '<button type="button" class="btn small primary" data-act="add-spell" data-key="'+key+'">Aggiungi</button></div>'+
    '<p class="hint">L’inserimento manuale salva un ID testuale; selezione dal catalogo e cast non sono ancora disponibili nella PWA.</p></div>';
}
function diceView() {
  return header("Strumenti", "Lancia i dadi", "Tiri locali con generatore crittografico. Se collegato, puoi condividerli nella chat della partita.")+
    panel("Nuovo tiro",'<div class="columns">'+
      '<label>Numero dadi<input id="die-count" type="number" value="1" min="1" max="20"></label>'+
      '<label>Modificatore<input id="die-mod" type="number" value="0" min="-999" max="999"></label></div>'+
      '<div class="dice-options">'+[4,6,8,10,12,20,100].map(n=>
        '<button class="btn" type="button" data-act="roll" data-sides="'+n+'">d'+n+'</button>').join("")+'</div>'+
      (state.roll?'<div class="dice-result">'+esc(state.roll.total)+'</div><p class="hint" class="centered">'+
        esc(state.roll.detail)+'</p><div class="actions">'+btn("share-roll","Invia in chat",state.paired?"primary":"")+'</div>':""))+
    panel("Tiri recenti",state.rollHistory.length ? state.rollHistory.slice(0,12).map(r=>
      '<div class="combat-line"><span>'+esc(r.notation)+'</span><strong>'+esc(r.total)+'</strong></div>').join("") :
      '<p class="muted">Non hai ancora effettuato tiri.</p>');
}
function chatView() {
  return header("Comunicazione", "Chat della partita", "Messaggi e tiri condivisi col desktop. Non vengono memorizzati nell’archivio delle schede.")+
    (!state.paired?'<div class="empty"><p>Collega prima il desktop nella sezione Partita.</p>'+
      '<button type="button" class="btn primary" data-nav="session">Vai alla partita</button></div>':
    panel("Messaggi",'<div id="events" class="scroll-y" aria-live="polite">'+renderEvents()+'</div>'+
      '<form id="chat-form" class="stack" autocomplete="off">'+
      '<label>Scrivi come <select id="chat-author"><option value="">Giocatore</option>'+
      (state.cachedCreatures||[]).map(x=>'<option value="'+esc(x.name)+'">'+esc(x.name)+'</option>').join("")+
      '</select></label><label>Messaggio<textarea id="chat-message" rows="2" maxlength="1000" placeholder="Messaggio alla partita…" required></textarea></label>'+
      '<button type="submit" class="btn primary full">Invia messaggio</button></form>'));
}
function renderEvents() {
  return state.messages.length ? state.messages.slice(-80).map(e=>
    '<article class="event"><div class="meta"><strong>'+esc(e.author||"Giocatore")+'</strong><span>'+
    esc(e.kind==="roll"?"Dadi":e.kind==="action"?"Azione":"Chat")+'</span></div>'+
    '<div class="body">'+esc(e.kind==="roll" ? ((e.label||e.die||"Tiro")+": "+e.total) :
      (e.text||""))+'</div></article>').join("") :
    '<p class="hint">Nessun evento recente. La cronologia è disponibile mentre il desktop è collegato.</p>';
}
function sessionView() {
  const entries = Array.isArray(state.map?.tokens)?state.map.tokens:[];
  const combat=state.map?.combat||{};
  const isActive=state.paired && state.online;
  const statusMarkup = '<div class="row between"><span>'+tag(isActive?"Partita connessa":
    state.hostReachable?"Desktop attivo · nessuna partita":"Desktop non raggiungibile")+'</span>'+
    '<button type="button" class="btn small" data-act="check">Aggiorna</button></div>'+
    (state.session?'<p class="hint">Partita '+esc(state.session.session||"—")+'</p>':"");
  const pairing = '<form id="pair-form" class="stack"><label>Codice temporaneo del desktop'+
    '<input id="pair-secret" type="text" inputmode="text" autocapitalize="characters" spellcheck="false" minlength="16" maxlength="19" pattern="[a-fA-F0-9 -]{16,19}" autocomplete="off" placeholder="XXXX-XXXX-XXXX-XXXX" required></label>'+
    '<label class="check"><input id="pair-remember" type="checkbox" checked> Ricorda questo desktop sul dispositivo</label>'+
    '<button type="submit" class="btn primary full">Collega alla partita</button>'+
    '<p class="hint">Sul PC con VTT aperto premi <strong>Ctrl + Shift + P</strong>: inquadra il QR con la fotocamera del telefono oppure inserisci i 16 caratteri mostrati. Il codice vale 5 minuti e si usa una sola volta.</p></form>';
  let html = header("Connessione", "La tua partita", "Il PC con VTT nativo aperto ospita la partita e aggiorna automaticamente questa PWA.")+
    panel("Desktop",statusMarkup+(state.paired?'<div class="actions">'+
      btn("disconnect","Dissocia desktop","danger")+'</div>':pairing));
  if(!state.paired) return html;
  html += panel("Token sulla scena",entries.length ? '<div class="stack">'+
    entries.map(token => '<button type="button" class="btn full '+(state.tokenId===token.id?"primary":"")+
      '" data-act="select-token" data-id="'+esc(token.id)+'">'+
      esc(token.name)+(token.free?" · libero":"")+'</button>').join("")+'</div>' :
    '<p class="hint">Nessun token visibile. Aggiorna quando il desktop ha una scena attiva.</p>');
  const selected=entries.find(x=>x.id===state.tokenId);
  if(selected){
    html += panel("Controlli · "+selected.name,
      '<p class="hint">Muovi il token sulla griglia del desktop. Per alcune operazioni il desktop può richiedere il controllo della creatura.</p>'+
      '<div class="movement"><span></span><button class="btn" type="button" data-act="move" data-direction="north">↑</button><span></span>'+
      '<button class="btn" type="button" data-act="move" data-direction="west">←</button>'+
      '<span aria-hidden="true" class="pill movement-center">•</span>'+
      '<button class="btn" type="button" data-act="move" data-direction="east">→</button>'+
      '<span></span><button class="btn" type="button" data-act="move" data-direction="south">↓</button><span></span></div>'+
      '<div class="actions">'+btn("move-up","Quota +") + btn("move-down","Quota −")+'</div>'+
      '<h3>Condizioni</h3><div class="pillbox">'+conditions.map(id=>
      '<label class="check pill"><input type="checkbox" data-token-condition="'+id+'" '+
      ((selected.conditions||[]).includes(id)?"checked":"")+'>'+esc(id)+'</label>').join("")+'</div>');
    if((state.cachedCreatures||[]).length) html+=panel("Piazza una tua creatura",
      '<p class="hint">Seleziona una scheda locale. Il desktop riceverà solo l’identità e i dati tattici pubblici necessari a posizionare il token.</p>'+
      '<label>Creatura<select id="place-creature">'+state.cachedCreatures.map(c=>
        '<option value="'+esc(c.id)+'">'+esc(c.name)+'</option>').join("")+'</select></label>'+
      '<div class="actions">'+btn("place-creature","Piazza vicino al token","primary")+
      (selected.free?btn("claim-creature","Associa al token libero"):"")+'</div>');
  }
  if(selected) {
    const selectedCaster = (state.cachedCreatures||[]).find(c=>c.id===state.castCreatureId)
      || (state.cachedCreatures||[]).find(c=>c.linked_token_sync_id===selected.id)
      || (state.cachedCreatures||[])[0];
    const allSpells=[...(selectedCaster?.prepared_spells||[]),...(selectedCaster?.spells||[]),
      ...(selectedCaster?.origin_spell_grants||[])];
    const spells=[],seen=new Set();
    for(const raw of allSpells){
      const item=typeof raw==="string"?{id:raw,name:raw}:raw;
      if(!item||typeof item!=="object")continue;
      const id=String(item.id||item.spell_id||"");
      if(!id||seen.has(id))continue;
      seen.add(id);spells.push({id,name:item.name||id,source:item.source||""});
    }
    state.visibleSpells=spells;
    html+=panel("Mappa e bersagli",
      '<p class="hint">Richiedi la vista 2D esistente: zoom con due dita, trascinamento e selezione dei token. Per attacchi e incantesimi la risoluzione resta sul desktop.</p>'+
      '<div class="actions">'+btn("snapshot-map","Apri mappa 2D","primary")+'</div>'+
      '<div class="columns three">'+field("Gittata (ft)","attack_range_ui",state.attackRange,"number",'min="0" max="10000"')+
      field("Gittata lunga","attack_long_ui",state.attackLongRange,"number",'min="0" max="10000"')+
      '<label class="check"><input type="checkbox" data-field="attack_melee_ui" '+
      (state.attackMelee?'checked':'')+'>Mischia</label></div>'+
      '<div class="actions">'+btn("attack-map","Mira attacco")+'</div>')+
      panel("Lancia un incantesimo",
      '<label>Creatura<select id="cast-creature">'+(state.cachedCreatures||[]).map(c=>
        '<option value="'+esc(c.id)+'" '+(selectedCaster?.id===c.id?'selected':'')+'>'+
        esc(c.name)+'</option>').join("")+'</select></label>'+
      '<label>Incantesimo<select id="cast-spell">'+spells.map((sp,i)=>
        '<option value="'+i+'">'+esc(sp.name)+(sp.source?' · '+esc(sp.source):'')+'</option>').join("")+
      '</select></label><div class="columns">'+
      field("Livello slot / 0 trucchetto","cast_slot_ui",state.castLevel,"number",'min="0" max="9"')+
      '</div><p class="hint">Puoi lanciare soltanto incantesimi già presenti nella scheda. Il desktop ne verifica l’effetto e il targeting.</p>'+
      '<div class="actions">'+btn("begin-spell","Avvia incantesimo",spells.length?"primary":"")+'</div>');
  }
  if(combat.active) html += panel("Iniziativa · Round "+(combat.round||1),
    (combat.entries||[]).map((entry,i)=>
      '<div class="combat-line '+(i===combat.active_index?"active":"")+'"><span>'+
      (i===combat.active_index?"▶ ":"")+esc(entry.name)+'</span><span>'+esc(entry.initiative)+'</span></div>').join(""));
  else html += panel("Iniziativa",'<p class="hint">Nessun combattimento attivo nella scena.</p>');
  html += '<p class="hint">Lo snapshot mostra la vista ortografica acquisita dal desktop. Gittate ed effetti vengono calcolati da Godot, non nel browser.</p>';
  return html;
}
async function refreshConnection(quiet=false) {
  try {
    const result = await status();
    state.hostReachable=true;
    state.online=!!result.desktop_online;
    if(state.online){
      try {
        state.session=await session(); state.paired=true;
      } catch(error) {
        state.paired=false; state.session=null;
        if(error.status!==401 && error.status!==503 && !quiet) message(errorMessage(error),true);
      }
    } else { state.paired=false; state.session=null; }
  } catch(error){ state.hostReachable=false; state.online=false; state.paired=false; state.session=null; }
  syncNav();
}
function startMap() {
  state.stopMap?.();
  state.stopMap = subscribeMap(data=>{
    if(state.page!=="session") return;
    const recovered=!state.online;
    state.map = data;
    state.online=true;
    state.hostReachable=true;
    if(recovered){
      syncNav();
      // The native board can restart while the PWA is open. Refresh its
      // session label without interrupting the recovered tactical view.
      session().then(info=>{
        if(state.page==="session"&&state.paired)state.session=info;
      }).catch(()=>{});
    }
    const entries=data?.tokens||[];
    if(!entries.some(x=>x.id===state.tokenId)) state.tokenId="";
    if(!state.tokenId && entries.length) state.tokenId=entries[0].id;
    // Avoid replacing focused inputs while a player interacts.
    if(!app.contains(document.activeElement) || document.activeElement?.tagName==="BUTTON"){
      const scrollY=window.scrollY;
      app.innerHTML=sessionView();
      window.scrollTo(0,scrollY);
    }
  },error=>{
    if(state.page!=="session")return;
    const wasOnline=state.online;
    state.online=false;
    state.hostReachable=!!error?.status;
    // Never leave stale token controls on screen. A temporary 503 or
    // network loss is recoverable: subscribeMap continues retrying.
    state.map=null;
    state.tokenId="";
    if(error?.status===401){
      state.paired=false;state.session=null;
      state.stopMap?.();state.stopMap=null;
      render().catch(e=>message(errorMessage(e),true));
      return;
    }
    syncNav();
    app.innerHTML=sessionView();
    if(wasOnline)message("Connessione persa. Riconnessione automatica in corso.");
  },2500);
}
async function fetchChat() {
  if(!state.paired) return;
  try {
    const reply=await action("chat_poll",{after:state.after});
    if(!reply.ok) throw new Error(reply.error||"Chat non disponibile");
    if(Array.isArray(reply.events) && reply.events.length){
      const ids=new Set(state.messages.map(e=>e.id));
      for(const entry of reply.events){
        if(!entry || !entry.id) continue;
        if(!ids.has(entry.id)){ state.messages.push(entry); ids.add(entry.id); }
        state.after=entry.id;
      }
      state.messages=state.messages.slice(-100);
      const container=document.querySelector("#events");
      if(state.page==="chat"&&container){ container.innerHTML=renderEvents();container.scrollTop=container.scrollHeight; }
    }
  }catch(error){ if(state.page==="chat"&&error.status===401) message(errorMessage(error),true); }
}
function startChat() {
  clearInterval(state.pollChat);
  fetchChat();
  state.pollChat=setInterval(()=>{ if(state.page==="chat") fetchChat(); },2500);
}
function randomDie(sides) {
  const range=0x100000000;
  const ceiling=Math.floor(range/sides)*sides;
  const values=new Uint32Array(1);
  do { crypto.getRandomValues(values); } while(values[0]>=ceiling);
  return 1+(values[0]%sides);
}
async function roll(sides) {
  const count=number(document.querySelector("#die-count")?.value,1);
  const modifier=number(document.querySelector("#die-mod")?.value,0);
  if(!Number.isInteger(count)||count<1||count>20||!Number.isInteger(modifier)||
     modifier < -999 || modifier > 999) throw new Error("Controlla il numero di dadi e il modificatore.");
  const rolls=Array.from({length:count},()=>randomDie(sides));
  const total=rolls.reduce((a,b)=>a+b,modifier);
  const notation=count+"d"+sides+(modifier<0?String(modifier):modifier?"+"+modifier:"");
  state.roll={sides,count,modifier,rolls,total,notation,detail:rolls.join(" + ")+
    (modifier?(" "+(modifier>0?"+ ":"− ")+Math.abs(modifier)):"")};
  state.rollHistory.unshift(state.roll);
  await render();
}
async function shareRoll() {
  if(!state.roll) return;
  if(!state.paired) throw new Error("Collega prima una partita.");
  const r=state.roll;
  const event={id:"pwa_"+crypto.randomUUID(),kind:"roll",author:"Giocatore",
    timestamp:Math.floor(Date.now()/1000),label:r.notation,die:"d"+r.sides,
    count:r.count,modifier:r.modifier,rolls:r.rolls,total:r.total};
  const result=await action("chat_send",{event});
  if(!result.ok) throw new Error(result.error||"Tiro non inviato");
  message("Tiro condiviso nella chat.");
}
async function patch(patchValue) {
  if(!state.editor) return;
  const status=document.querySelector("#save-state");
  if(status){ status.textContent="Salvataggio…"; status.classList.remove("error"); }
  try {
    await state.editor.update(patchValue);
    state.saveError="";
    if(status){ status.textContent="✓ Salvato in locale"; status.classList.remove("error"); }
  }catch(error) {
    state.saveError=errorMessage(error);
    if(status){ status.textContent="Errore salvataggio";status.classList.add("error"); }
    message("Modifica non salvata: "+state.saveError,true);
  }
}
async function handleField(target) {
  // Tactical controls are independent from an open local creature editor.
  if(target.dataset.tokenCondition){
    const result=await action("set_condition",{token_id:state.tokenId,
      condition_id:target.dataset.tokenCondition,enabled:target.checked});
    if(!result.ok){target.checked=!target.checked;throw new Error(result.error||"Condizione non applicata");}
    await refreshMapOnce();
    return;
  }
  if(!state.editor) return;
  const creature=state.editor.read();
  if(target.dataset.field){
    const key=target.dataset.field;
    let value=target.type==="checkbox"?target.checked:target.value;
    if(target.type==="number") {
      value=Number(value);
      if(!Number.isFinite(value)) throw new Error("Inserisci un numero valido.");
    }
    await patch({[key]:value});
    if(key==="name"){
      const title=app.querySelector(".editor-head h1");
      if(title) title.textContent=value;
    }
  } else if(target.dataset.ability){
    const key=target.dataset.ability, value=Number(target.value);
    if(!Number.isInteger(value)||value<1||value>30) throw new Error("Caratteristica da 1 a 30.");
    await patch({abilities:{...creature.abilities,[key]:value}});
  } else if(target.dataset.slot){
    const level=Number(target.dataset.slot), value=Number(target.value);
    if(!Number.isInteger(value)||value<0||value>99) throw new Error("Numero slot non valido.");
    const array=Array.isArray(creature.spell_slots_spent)?[...creature.spell_slots_spent]:Array(10).fill(0);
    while(array.length<10) array.push(0);
    array[level]=value;
    await patch({spell_slots_spent:array});
  } else if(target.dataset.itemIndex !== undefined){
    const index=Number(target.dataset.itemIndex),key=target.dataset.itemKey;
    const items=structuredClone(creature.inventory||[]);
    if(!items[index]||typeof items[index]!=="object") throw new Error("Oggetto non valido.");
    items[index][key] = key==="quantity"?Number(target.value):target.value;
    if(key==="quantity"&&(!Number.isInteger(items[index][key])||items[index][key]<0))
      throw new Error("Quantità non valida.");
    await patch({inventory:items});
  } else if(target.dataset.condition){
    const entries=new Set(creature.conditions||[]);
    if(target.checked) entries.add(target.dataset.condition);
    else entries.delete(target.dataset.condition);
    await patch({conditions:[...entries]});
  }
}
async function refreshMapOnce() {
  state.map=await map();
  if(state.page==="session"){const scroll=window.scrollY;app.innerHTML=sessionView();window.scrollTo(0,scroll);}
}
async function consumeAcceptedSlot(level,spell) {
  if(level<1)return; // Cantrip or free use does not expend a class slot.
  const id=document.querySelector("#cast-creature")?.value;
  // The modal is rendered outside the main session page, but the session
  // selector remains mounted underneath.
  if(!id)return;
  const editor=await openCreatureEditor(id);
  const saved=editor.read();
  const slots=Array.isArray(saved.spell_slots_spent)?[...saved.spell_slots_spent]:[];
  while(slots.length<10)slots.push(0);
  slots[level]=Number(slots[level]||0)+1;
  await editor.update({spell_slots_spent:slots});
  state.cachedCreatures=(await listCreatures()).map(row=>row.creature);
}

async function handleAction(target){
  const act=target.dataset.act;
  if(act==="catalog-open"){
    state.catalogSelected=Number(target.dataset.index);
    await render();return;
  }
  if(act==="catalog-assign"){
    const cId=document.querySelector("#catalog-creature")?.value;
    const entry=state.catalogRows[state.catalogSelected];
    const stored=await loadCreature(cId);
    if(!stored||!entry)throw new Error("Seleziona contenuto e creatura.");
    const editor=await openCreatureEditor(cId),sheet=editor.read();
    const category=entry._category;
    if(category==="spells"){
      const spell={id:String(entry.id||""),name:entry.name,source:entry.source||"",
        level:Number(entry.level)||0};
      if(!spell.id)throw new Error("Incantesimo privo di identificativo VTT.");
      const known=Array.isArray(sheet.spells)?sheet.spells:[];
      if(known.some(row=>String(typeof row==="string"?row:row?.id)===spell.id))
        throw new Error("Incantesimo già presente in questa scheda.");
      await editor.update({spells:[...known,spell]});
    }else if(["weapons","armor","tools","mundane_items","magic_items","items"].includes(category)){
      const item=structuredClone(entry);
      delete item._category;delete item._homebrew;
      item.instance_id="pwa_"+crypto.randomUUID();
      item.quantity=1;
      await editor.update({inventory:[...(sheet.inventory||[]),item]});
    }else if(category==="feats"){
      const feat={id:entry.id||"",name:entry.name,source:entry.source||""};
      const current=Array.isArray(sheet.feats_catalog)?sheet.feats_catalog:[];
      if(current.some(row=>row.id===feat.id&&row.name===feat.name&&row.source===feat.source))
        throw new Error("Talento già presente in questa scheda.");
      await editor.update({feats_catalog:[...current,feat]});
    }else if(category==="backgrounds"){
      await editor.update({background:entry.name,background_source:entry.source||""});
    }else if(category==="races"){
      await editor.update({species:entry.name,species_source:entry.source||""});
    }else throw new Error("Categoria non assegnabile alla scheda.");
    state.cachedCreatures=(await listCreatures()).map(row=>row.creature);
    message("Contenuto aggiunto. Eventuali bonus vengono elaborati dalla versione Godot.");
    return;
  }
  if(act==="refresh"){await render();return;}
  if(act==="demo"){
    state.creatureId=await createDemoCreature();state.editor=null;state.sheet="stats";
    await render();message("Eroe dimostrativo creato solo su questo dispositivo.");return;
  }
  if(act==="library-select-all"){
    state.librarySelectedIds=new Set((await listCreatures()).map(row=>row.creature.id));
    await render();return;
  }
  if(act==="library-select-none"){
    state.librarySelectedIds.clear();await render();return;
  }
  if(act==="library-export"||act==="library-delete"){
    const rows=(await listCreatures()).filter(row=>state.librarySelectedIds.has(row.creature.id));
    if(!rows.length)throw new Error("Seleziona almeno una creatura.");
    if(act==="library-export"){
      if(rows.length>200)throw new Error("Puoi esportare fino a 200 creature in un file.");
      const entries=[];
      for(const row of rows){
        const blob=await exportCreature(row.creature.id);
        entries.push(JSON.parse(await blob.text()));
      }
      const data=JSON.stringify({format:"vtt_creature_batch_export_v1",version:1,entries},null,2);
      if(new TextEncoder().encode(data).length>16*1024*1024)
        throw new Error("Esportazione troppo grande per il formato portatile.");
      download(new Blob([data],{type:"application/json"}),"vtt-creature-selezionate.json");
      message("Esportate "+rows.length+" creature e i loro contenuti homebrew.");return;
    }
    if(!window.confirm("Eliminare definitivamente "+rows.length+
        " creature da questo dispositivo? L'operazione non può essere annullata."))return;
    let deleted=0;
    for(const row of rows){
      if(await removeCreature(row.creature.id,"default",row.revision)){
        state.librarySelectedIds.delete(row.creature.id);deleted++;
      }
    }
    await render();message("Eliminate "+deleted+" creature dall'archivio locale.");return;
  }
  if(act==="create"){
    const row=await createCreature("character","Nuovo personaggio");
    state.creatureId=row.id;state.editor=null;state.sheet="stats";await render();return;
  }
  if(act==="import"){creatureInput.click();return;}
  if(act==="restore-backup"){backupInput.click();return;}
  if(act==="backup"){
    const blob=await exportBackup();download(blob,"vtt-pwa-backup-"+new Date().toISOString().slice(0,10)+".json");
    message("Backup esportato. Conservalo fuori dal browser.");
    return;
  }
  if(act==="open"){state.creatureId=target.dataset.id;state.sheet="stats";state.editor=null;await render();return;}
  if(act==="back"){
    try{await state.editor?.flush();}catch(error){throw new Error("Salvataggio incompleto: "+errorMessage(error));}
    state.editor=null;state.creatureId=null;await render();return;
  }
  if(act==="sheet"){
    try{await state.editor?.flush();}catch(error){throw new Error("Salvataggio incompleto: "+errorMessage(error));}
    state.sheet=target.dataset.sheet;await render();return;
  }
  if(act==="export"){
    await state.editor?.flush();
    const c=state.editor.read();
    download(await exportCreature(c.id),filename(c.name)+".json");
    message("Scheda esportata in formato VTT.");return;
  }
  if(act==="delete"){
    const record=state.editor.read();
    if(!confirm('Eliminare "'+record.name+'"? Questa operazione non è reversibile.'))return;
    await state.editor.flush();
    await removeCreature(record.id,"default",state.editor.revision);
    state.creatureId=null;state.editor=null;await render();message("Scheda eliminata.");return;
  }
  if(act==="tracker-add"){
    const name=text(document.querySelector("#tracker-name")?.value);
    const maximum=Number(document.querySelector("#tracker-max")?.value);
    const recharge=document.querySelector("#tracker-recharge")?.value||"manual";
    if(!name||name.length>120||!Number.isInteger(maximum)||maximum<1||maximum>99999)
      throw new Error("Specifica nome e massimo valido della risorsa.");
    const record=state.editor.read();
    const trackers=structuredClone(record.resource_trackers||[]);
    trackers.push({id:"pwa_tracker_"+crypto.randomUUID(),name,max:maximum,
      max_formula:"",origin_name:"Personalizzato",recharge});
    await patch({resource_trackers:trackers});await render();return;
  }
  if(["tracker-more","tracker-less","tracker-delete"].includes(act)){
    const record=state.editor.read(),trackers=structuredClone(record.resource_trackers||[]);
    const index=Number(target.dataset.index),row=trackers[index];
    if(!row)throw new Error("Tracker non disponibile.");
    if(act==="tracker-delete"){
      trackers.splice(index,1);
      const spent={...(record.resource_tracker_spent||{})};delete spent[row.id];
      await patch({resource_trackers:trackers,resource_tracker_spent:spent});
    }else{
      const maximum=Math.max(0,Number(row.max)||0);
      const spent={...(record.resource_tracker_spent||{})};
      const delta=act==="tracker-more"?1:-1;
      spent[row.id]=Math.max(0,Math.min(maximum,(Number(spent[row.id])||0)+delta));
      await patch({resource_tracker_spent:spent});
    }
    await render();return;
  }
  if(act==="tracker-short"||act==="tracker-long"){
    const record=state.editor.read(),spent={...(record.resource_tracker_spent||{})};
    for(const row of record.resource_trackers||[]){
      if(row.recharge==="short_rest" ||
        (act==="tracker-long"&&row.recharge==="long_rest")) delete spent[row.id];
    }
    await patch({resource_tracker_spent:spent});await render();return;
  }
  if(act==="add-item"){
    const c=state.editor.read();
    const inventory=Array.isArray(c.inventory)?[...c.inventory]:[];
    inventory.push({id:"local_"+crypto.randomUUID(),name:"Nuovo oggetto",quantity:1,description:""});
    await patch({inventory});await render();return;
  }
  if(act==="remove-item"){
    const c=state.editor.read(),inventory=structuredClone(c.inventory||[]);
    inventory.splice(Number(target.dataset.index),1);
    await patch({inventory});await render();return;
  }
  if(act==="add-spell"){
    const key=target.dataset.key, input=document.getElementById("new-"+key),value=text(input?.value);
    if(!value)throw new Error("Inserisci un nome o ID.");
    const c=state.editor.read(),spells=[...(c[key]||[])];spells.push(value);
    await patch({[key]:spells});await render();return;
  }
  if(act==="remove-spell"){
    const key=target.dataset.key,c=state.editor.read(),spells=[...(c[key]||[])];
    spells.splice(Number(target.dataset.index),1);
    await patch({[key]:spells});await render();return;
  }
  if(act==="save-json"){
    const raw=document.getElementById("json-editor")?.value;
    const changed=JSON.parse(raw);
    if(!changed||Array.isArray(changed)||typeof changed!=="object")throw new Error("JSON deve essere un oggetto.");
    await patch(changed);await render();return;
  }
  if(act==="check"){await refreshConnection();if(state.paired){try{state.map=await map();}catch{state.map=null;}}await render();return;}
  if(act==="disconnect"){
    if(!confirm("Dissociare questo desktop? Le schede locali rimarranno sul dispositivo.")) return;
    await unpair();stopSubscriptions();state.paired=false;state.session=null;state.map=null;await render();return;
  }
  if(act==="place-creature"||act==="claim-creature"){
    const selectedId=document.querySelector("#place-creature")?.value;
    const selectedToken=state.map?.tokens?.find(t=>t.id===state.tokenId);
    if(!selectedToken||!selectedId)throw new Error("Scegli un token e una creatura locale.");
    if(act==="claim-creature"&&!selectedToken.free)throw new Error("Il token non è più libero.");
    const stored=await loadCreature(selectedId);
    if(!stored)throw new Error("Scheda non trovata in locale.");
    const sheet=stored.data;
    // Do NOT upload the private character sheet. This is the Android tactical
    // identity projection, with no inventory, HP, biography or known spells.
    const visible={id:sheet.id,owner_id:sheet.owner_id,name:sheet.name,
      current_miniature_id:sheet.current_miniature_id||"",
      default_miniature_id:sheet.default_miniature_id||"",
      size_name:sheet.size_name||"Medium",footprint:sheet.footprint??1,
      reach_feet:sheet.reach_feet??5,conditions:sheet.conditions||[],
      rules_version:sheet.rules_version||"2014",
      visual_front_quarter_turns:sheet.visual_front_quarter_turns??0};
    const result=await action(act==="claim-creature"?"claim_free_token":"place_token",
      {token_id:state.tokenId,creature:visible});
    if(!result.ok)throw new Error(result.error||"Impossibile piazzare la creatura.");
    const editor=await openCreatureEditor(selectedId);
    await editor.update({linked_token_sync_id:result.token_id,linked_token_name:result.name||sheet.name});
    state.cachedCreatures=(await listCreatures()).map(row=>row.creature);
    message("Token aggiornato: "+(result.name||sheet.name));
    await refreshMapOnce();return;
  }
  if(act==="snapshot-map"||act==="attack-map"){
    const isAttack=act==="attack-map";
    const attack=isAttack?{range_feet:state.attackRange,
      long_range_feet:state.attackLongRange,melee:state.attackMelee}:{};
    if(!tacticalViewer)tacticalViewer=new TacticalViewer({
      send:action,ownerId,notify:message,onCastAccepted:consumeAcceptedSlot
    });
    await tacticalViewer.open(state.tokenId,attack);
    return;
  }
  if(act==="begin-spell"){
    const casterId=document.querySelector("#cast-creature")?.value;
    const caster=await loadCreature(casterId);
    if(!caster)throw new Error("Scegli una scheda locale.");
    if(caster.data.linked_token_sync_id!==state.tokenId)
      throw new Error("Seleziona il token associato alla creatura. Piazza prima la sua miniatura.");
    const spell=state.visibleSpells?.[Number(document.querySelector("#cast-spell")?.value)];
    if(!spell)throw new Error("Scegli un incantesimo della creatura.");
    if(!Number.isInteger(state.castLevel)||state.castLevel<0||state.castLevel>9)
      throw new Error("Livello di slot non valido.");
    if(!tacticalViewer)tacticalViewer=new TacticalViewer({
      send:action,ownerId,notify:message,onCastAccepted:consumeAcceptedSlot
    });
    await tacticalViewer.open(state.tokenId);
    await tacticalViewer.beginSpell({spell,slotLevel:state.castLevel,
      context:{spellcasting_ability:caster.data.spellcasting_ability||"",
        spell_attack_bonus:caster.data.spell_attack_bonus||0,
        spell_save_dc:caster.data.spell_save_dc||0}});
    return;
  }
  if(act==="select-token"){state.tokenId=target.dataset.id;await render();return;}
  if(act==="move"||act==="move-up"||act==="move-down"){
    const direction=act==="move-up"?"up":act==="move-down"?"down":target.dataset.direction;
    if(!state.tokenId)throw new Error("Seleziona un token.");
    const result=await action("move_token",{token_id:state.tokenId,direction});
    if(!result.ok)throw new Error(result.error||"Movimento rifiutato");
    if(!result.moved)message("Movimento non disponibile sulla scena.");return;
  }
  if(act==="roll"){await roll(Number(target.dataset.sides));return;}
  if(act==="share-roll"){await shareRoll();return;}
}
async function handleSubmit(form){
  if(form.id==="pair-form"){
    const token=document.querySelector("#pair-secret")?.value.trim()||"";
    state.session=await pair(token,{remember:document.querySelector("#pair-remember")?.checked});
    state.paired=true;state.online=true;state.map=await map();
    await render();message("Desktop associato.");return;
  }
  if(form.id==="chat-form"){
    const body=text(document.querySelector("#chat-message")?.value);
    if(!body||body.length>1000)throw new Error("Messaggio vuoto o troppo lungo.");
    const author=text(document.querySelector("#chat-author")?.value)||"Giocatore";
    const event={id:"pwa_"+crypto.randomUUID(),kind:"chat",author:author.slice(0,80),
      timestamp:Math.floor(Date.now()/1000),text:body};
    const result=await action("chat_send",{event});
    if(!result.ok)throw new Error(result.error||"Messaggio rifiutato");
    document.querySelector("#chat-message").value="";
    await fetchChat();
  }
}
function listen(){
  document.addEventListener("click", async e=>{
    const button=e.target.closest("button[data-nav],button[data-act]");
    if(!button)return;
    if(button.disabled)return;
    button.disabled=true;
    try {
      await flushPendingFields();
      if(button.dataset.nav)await navigate(button.dataset.nav);
      else await handleAction(button);
    }catch(error){message(errorMessage(error),true);}
    finally{if(button.isConnected)button.disabled=false;}
  });
  app.addEventListener("submit",async e=>{
    if(!(e.target instanceof HTMLFormElement))return;
    e.preventDefault();
    const button=e.target.querySelector('[type="submit"]');if(button)button.disabled=true;
    try{await handleSubmit(e.target);}catch(error){message(errorMessage(error),true);}
    finally{if(button&&button.isConnected)button.disabled=false;}
  });
  const editable = "[data-field],[data-ability],[data-slot],[data-item-index],[data-condition],[data-token-condition]";
  app.addEventListener("input",e=>{
    const target=e.target;
    if(target?.id==="catalog-search"){
      state.catalogQuery=target.value;
      const results=document.querySelector("#catalog-results");
      if(results)results.innerHTML=renderCatalogRows();
      return;
    }
    if(!target?.matches("[data-field],[data-item-index]"))return;
    if(target.type==="number")return; // Partial numeric input is not valid until committed.
    clearTimeout(pendingFieldTimers.get(target));
    const editor=state.editor;
    pendingFieldTimers.set(target,setTimeout(()=>{
      pendingFieldTimers.delete(target);
      if(target.isConnected && state.editor===editor)
        handleField(target).catch(error=>message(errorMessage(error),true));
    },400));
  });
  app.addEventListener("change",e=>{
    const target=e.target;
    if(target?.dataset?.librarySelect){
      if(target.checked)state.librarySelectedIds.add(target.dataset.librarySelect);
      else state.librarySelectedIds.delete(target.dataset.librarySelect);
      const actions=app.querySelector("#library-selected-actions");
      if(actions)actions.innerHTML=state.librarySelectedIds.size ?
        btn("library-select-none","Deseleziona")+
        btn("library-export","Esporta ("+state.librarySelectedIds.size+")")+
        btn("library-delete","Elimina ("+state.librarySelectedIds.size+")","danger") : "";
      return;
    }
    if(target?.id==="catalog-category"){
      state.catalogCategory=target.value;state.catalogSelected=-1;
      render().catch(error=>message(errorMessage(error),true));return;
    }
    if(target?.id==="cast-creature"){
      state.castCreatureId=target.value;state.castSpellIndex=0;
      app.innerHTML=sessionView();return;
    }
    if(target?.id==="cast-spell"){
      state.castSpellIndex=Number(target.value)||0;return;
    }
    if(target?.dataset?.field==="attack_range_ui"){
      state.attackRange=Math.max(0,Math.min(10000,Number(target.value)||0));return;
    }
    if(target?.dataset?.field==="attack_long_ui"){
      state.attackLongRange=Math.max(0,Math.min(10000,Number(target.value)||0));return;
    }
    if(target?.dataset?.field==="attack_melee_ui"){
      state.attackMelee=target.checked;return;
    }
    if(target?.dataset?.field==="cast_slot_ui"){
      state.castLevel=Number(target.value);return;
    }
    if(!e.target?.matches(editable))return;
    clearTimeout(pendingFieldTimers.get(e.target));
    pendingFieldTimers.delete(e.target);
    handleField(e.target).catch(error=>message(errorMessage(error),true));
  });
  creatureInput.addEventListener("change",async()=>{
    const file=creatureInput.files?.[0];if(!file)return;
    try{
      const result=await importCreatureFile(file);
      const imported=Array.isArray(result)?result:[result];
      state.page="library";state.creatureId=imported.length===1?imported[0].creature.id:null;
      state.editor=null;state.sheet="stats";
      state.librarySelectedIds.clear();
      await render();
      message(imported.length===1 ? "Scheda importata e salvata offline." :
        "Importate "+imported.length+" creature e relativi contenuti homebrew.");
    }
    catch(error){message(errorMessage(error),true);}finally{creatureInput.value="";}
  });
  backupInput.addEventListener("change",async()=>{
    const file=backupInput.files?.[0];if(!file)return;
    try{await importBackup(file);await render();message("Backup ripristinato senza sovrascrivere le schede esistenti.");}
    catch(error){message(errorMessage(error),true);}finally{backupInput.value="";}
  });
  document.addEventListener("visibilitychange",()=>{
    if(document.hidden){
      const active=document.activeElement;
      if(active?.matches?.("[data-field],[data-item-index]"))
        active.dispatchEvent(new Event("change",{bubbles:true}));
    } else if(state.page==="session") {
      refreshConnection(true).then(()=>render()).catch(error=>message(errorMessage(error),true));
    }
  });
  window.addEventListener("online",()=>{
    if(state.page==="session")
      refreshConnection(true).then(()=>render()).catch(error=>message(errorMessage(error),true));
  });
}
// Allows tests and future app lifecycle handlers to release polling resources.
export function stopRealtime() { stopSubscriptions(); }

export async function mount(){
  listen();
  const dbOk=await import("./storage.js").then(m=>m.openStorage()).then(db=>{db.close();return true;});
  if(!dbOk)throw new Error("Archivio locale non disponibile.");
  const qrCode = takeQrPairCode();
  await refreshConnection(true);
  if(qrCode){
    try {
      state.session=await pair(qrCode,{remember:true});
      state.paired=true;state.online=true;state.page="session";
      message("Telefono associato tramite QR.");
    }catch(error){
      state.page="session";state.qrCode=qrCode;
      message("QR non valido o scaduto: "+errorMessage(error),true);
    }
  }
  state.cachedCreatures=(await listCreatures()).map(row=>({name:row.creature.name,id:row.creature.id}));
  await render();
  if(state.qrCode && state.page==="session"){
    const input=document.querySelector("#pair-secret");
    if(input)input.value=state.qrCode;
    state.qrCode="";
  }
}
