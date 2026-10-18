import { actionEconomyView, actionGlyph, actionVariants, loadFeatureActionOverrides, loadGeneralActionSupplements } from "./action_economy.js";
import { SHEET_SECTIONS, DETAILS, ROW_FIELDS, nativeSection, nativeRowPatch, rowsFor, collectionPatch, identityPatch, referencePatch, rowReferencePatch, hitPointPatch, slotUsePatch, recoveryPatch, miniaturePatch } from "./native_sheet.js";
import { itemKind, requiresAttunement, isCatalogItem, createOwnedItem, changeOwnedItem, changeItemOverride, resolveOwnedItem, WEAPON_SIZES, infusionLimits, learnedInfusions, learnInfusionPatch, applyInfusionPatch, clearInfusionPatch, forgetInfusionPatch, validSlot, equipSlot } from "./item_controls.js";
import { sessionSpellEntries, availableSpells, addSelectedSpell, removeSelectedSpell, spellId, spellEligible, spellsForEdition, castingSources, classSelectionCount, originChoiceMatches, applyOriginSpellChoice } from "./spell_selection.js";
import { loadActivatedAbilities, abilitiesForCreature } from "./activated_abilities.js";
import { status, session, pair, unpair, hasPairingCredential, map, action, subscribeMap, takeQrPairCode } from "./client.js";
import { listCreatures, loadCreature, createCreature, importCreatureFile, exportCreature,
  removeCreature, openCreatureEditor, ownerId, syncLinkedTokenStatuses } from "./creatures.js";
import { TacticalViewer } from "./tactical_view.js";
import { tokenGroups, snapshotRevision, snapshotBlob } from "./session_map.js";
import { createDemoCreature } from "./demo.js";
import { CATALOG_CATEGORIES, catalogEntries, detailedEntry, flattenDescription, createQuickHomebrew, quickGrantPatch, deleteQuickHomebrew } from "./catalog_data.js";
import { exportBackup, importBackup, getRecord } from "./storage.js";
import { saveHomebrewDefinition, editHomebrewDefinition } from "./creatures.js";
import { isDocument, createDocumentDefinition, createOwnedDocument, editDocumentDefinition, documentInfo, documentStyle } from "./documents.js";
import { calculateSheet, loadRuleCatalogs, localClasses, validBonusDice, applicableDiceBonuses } from "./sheet_rules.js";
import {benefitRequirements,requirementPatch,formulaPreview,spellCastPlan} from './native_sheet.js';
import { calculationNote, refreshCalculatedValues, formulaReadout, sheetRollFormula, rollSheetDice, sheetRollChatFields, sheetModifierBreakdown } from "./sheet_rules_view.js";
import {optionalRecoveryPatch} from './feature_mechanics.js';
import {changeTrackerUses} from "./character_core.js";

const app = document.querySelector("#app");
const nav = document.querySelector("#nav");
const connection = document.querySelector("#connection");
const creatureInput = document.querySelector("#import-creature");
const backupInput = document.querySelector("#import-backup");
const toastElement = document.querySelector("#toast");
const sheetSections = SHEET_SECTIONS;
const sectionMenu = document.querySelector("#section-menu");
const sections = new Set(["library", "catalog", "dice", "chat", "session"]);
const conditions = ["blinded","charmed","deafened","exhaustion","frightened",
  "grappled","incapacitated","invisible","paralyzed","petrified","poisoned",
  "prone","restrained","stunned","unconscious","concentrating","surprised","hidden","helped","dead"];
const abilities = {str:"Forza",dex:"Destrezza",con:"Costituzione",int:"Intelligenza",wis:"Saggezza",cha:"Carisma"};
const state = { page:"library", creatureId:null, editor:null, sheet:"info", detail:"overview", referenceCatalogs:{}, map:null,
  tokenId:"", editTokenId:"", liveSnapshot:null, snapshotObjectUrl:"", snapshotKey:"", snapshotPending:false, online:false, paired:false, session:null, errors:[], messages:[],
  after:"", rollHistory:[], roll:null, stopMap:null, pollChat:null, renderTicket:0,
  librarySelectedIds:new Set(),
  hostReachable:false, catalogCategory:"items", catalogQuery:"", catalogRows:[], catalogSelected:-1, spellCatalog:null, abilityCatalog:null, spellQuery:"", spellTarget:"prepared_spells", spellClass:'manual',spellCatalogError:"", openDocumentInstance:"",
  castCreatureId:"", castSpellIndex:0, castLevel:1,
  attackRange:30, attackLongRange:0, attackMelee:false,
  saving:false, saveError:"", pendingActions:0, busy:false };
let tacticalViewer=null;
let tokenStatusFingerprint="";
let tokenSyncQueue=Promise.resolve();
let mapGeneration=0;
let snapshotGeneration=0;
let snapshotCaptureQueue=Promise.resolve();
let previousMapFingerprint="";
let realtimeStopped=false;
let toastTimer = null;
let chatPollGenerationInFlight=-1;
let chatGeneration=0;
let currentGameSession="";
function releaseSessionSnapshot(){
  const url=state.snapshotObjectUrl;
  state.snapshotObjectUrl="";
  state.liveSnapshot=null;
  state.snapshotKey="";
  if(url)URL.revokeObjectURL(url);
}
function acceptSession(info){
  const next=String(info?.session??"");
  if(currentGameSession && next && next!==currentGameSession){
    // A different desktop game must not inherit the old chat cursor.
    state.messages=[];state.after="";state.map=null;state.tokenId="";
    releaseSessionSnapshot();++snapshotGeneration;
    previousMapFingerprint="";
    tokenStatusFingerprint="";
  }
  if(next)currentGameSession=next;
  state.session=info;
}
const pendingFieldTimers = new Map();
let pendingDocumentWrites=Promise.resolve();
async function flushPendingFields() {
  const targets = [...pendingFieldTimers.keys()];
  for (const target of targets) {
    clearTimeout(pendingFieldTimers.get(target));
    pendingFieldTimers.delete(target);
    if (target.isConnected && state.editor) await handleField(target);
  }
  await pendingDocumentWrites;
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
  toastElement.classList.toggle("error",error);
  toastTimer = setTimeout(() => { toastElement.hidden = true; }, 4500);
}
function errorMessage(error) {
  const code = Number(error?.status);
  if (code === 503) return "Apri una partita sul desktop per completare il collegamento.";
  if (code === 401) return "Associazione necessaria: inserisci il codice del desktop.";
  return error instanceof Error ? error.message : String(error);
}
// Exact icon keys used by CreatureArea._add_sheet_tab in the desktop.
const SHEET_TAB_GLYPHS={info:'information',stats:'skill',battle:'shield',actions:'weapon',
 magic:'spark',inventory:'inventory',traits:'proficiency',conditions:'condition',origins:'settings'};
const INFO_HEADING_ICONS={'Identità':'identity','Fisico':'physique',
 'Classi e progressione':'progression','Talenti':'talents'};
function syncNav() {
  document.querySelector("#sheet-navigation").innerHTML = state.page === "library" && state.creatureId ?
    '<p class="drawer-heading">Scheda creatura</p>'+sheetSections.map(([key,title]) =>
      '<button type="button" class="btn" data-act="sheet" data-sheet="'+key+'" aria-pressed="'+
      (state.sheet===key)+'">'+actionGlyph(SHEET_TAB_GLYPHS[key]||'information')+
       '<span>'+esc(title)+'</span></button>').join("") : "";
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
  link.href = url; link.download = filename; link.hidden = true;
  document.body.append(link); link.click(); link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60000);
}
function filename(value) { return text(value).replace(/[^a-zA-Z0-9_-]/g,"_").slice(0,60) || "creatura"; }
function selectedName() { return state.editor?.read().name || "Giocatore"; }
function stopSubscriptions() {
  ++chatGeneration;
  ++mapGeneration;
  ++snapshotGeneration;
  state.snapshotPending=false;
  releaseSessionSnapshot();
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
  if(page==="session")realtimeStopped=false;
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
    else if (state.page === "session") {
      state.cachedCreatures=(await listCreatures()).map(row=>row.creature);
      if(!state.spellCatalog)try{state.spellCatalog=await catalogEntries('spells');}catch{}
      state.castSheets=new Map(await Promise.all(state.cachedCreatures.map(async creature=>[creature.id,await computeLocalData(creature)])));
      html=sessionView();
    }
    if(ticket !== state.renderTicket) return;
    app.innerHTML = html;
    decorateSheetHeadings();
    if(state.page==="session" && state.map) void refreshSessionSnapshot();
    if(state.paired && !realtimeStopped && !state.stopMap) startMap();
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
  return header("Archivio delle creature", "Le tue creature", "Personaggi e mostri salvati sul dispositivo.")+
    '<div class="actions">'+btn("create","＋ Nuovo personaggio","primary")+
    btn("import","Importa JSON dal PC")+'</div>'+
    '<details class="archive-tools"><summary>Backup dell’archivio</summary><div class="actions">'+
    btn("backup","Esporta backup")+btn("restore-backup","Importa backup")+'</div></details>'+
    (rows.length?'<div class="actions">'+btn("library-select-all","Seleziona tutte")+
      '<span id="library-selected-actions">'+(state.librarySelectedIds.size ?
        btn("library-select-none","Deseleziona")+
        btn("library-export","Esporta ('+state.librarySelectedIds.size+')")+
        btn("library-delete","Elimina ('+state.librarySelectedIds.size+')","danger") : '')+
      '</span></div>':'')+list+
    '<p class="hint">Le creature sono salvate su questo dispositivo. Esporta periodicamente una copia di sicurezza: in alcune condizioni iOS può eliminare i dati locali dei siti.</p>';
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
      '<p class="hint">Bonus ed effetti strutturati vengono calcolati direttamente sul dispositivo.</p>':"")+
      (chosen._homebrew && String(chosen.id||"").startsWith("homebrew:quick_local:")?
        '<div class="actions"><button class="btn danger" data-act="quick-delete" data-id="'+esc(chosen.id)+'">Elimina personalizzato</button></div>':''));
  }
  const quickPanel=['items','feats','backgrounds'].includes(state.catalogCategory)?panel('Crea contenuto personalizzato',
    '<label>Nome<input id="quick-name" maxlength="120"></label>'+
    '<label>Descrizione<textarea id="quick-description" rows="3" maxlength="12000"></textarea></label>'+
    (state.catalogCategory==='items'?
      '<div class="columns"><label>Tipo<select id="quick-type">'+[['other','Altro'],['weapon','Arma'],['shield','Scudo'],['armor','Armatura'],['tool','Strumento'],['magic','Magico']].map(([id,name])=>'<option value="'+id+'">'+name+'</option>').join('')+'</select></label>'+
      '<label>Rarità<select id="quick-rarity">'+[['none','Nessuna'],['common','Comune'],['uncommon','Non comune'],['rare','Raro'],['very rare','Molto raro'],['legendary','Leggendario'],['artifact','Artefatto']].map(([id,name])=>'<option value="'+id+'">'+name+'</option>').join('')+'</select></label>'+
      '<label>Valore (mo)<input id="quick-value" type="number" min="0" max="100000000" value="0"></label></div>':
      '<p class="hint">Competenze concesse (fino a tre). Le scelte non ancora completate non vengono assegnate automaticamente.</p>'+
      Array.from({length:3},(_,i)=>'<div class="columns"><label>Tipo<select data-quick-kind="'+i+'">'+[['','Nessuna'],['skill','Abilità'],['expertise','Maestria'],['save','Tiro salvezza'],['weapon','Arma'],['armor','Armatura'],['tool','Strumento'],['language','Linguaggio']].map(([id,name])=>'<option value="'+id+'">'+name+'</option>').join('')+'</select></label><label>Competenza<input data-quick-key="'+i+'" placeholder="es. perception"></label></div>').join(''))+
    '<div class="actions">'+btn('quick-create','Crea nel catalogo locale','primary')+'</div>'):'';
  return header("Compendio", "Catalogo", "Fonti strutturate incluse in VTT. Il catalogo base è disponibile offline dopo l'installazione.")+
    panel("Esplora",'<div class="columns"><label>Sezione<select id="catalog-category">'+
      CATALOG_CATEGORIES.map(([id,label])=>
      '<option value="'+id+'" '+(state.catalogCategory===id?'selected':'')+'>'+label+'</option>').join("")+
      '</select></label><label>Ricerca<input id="catalog-search" type="search" value="'+esc(state.catalogQuery)+
      '" placeholder="Nome o fonte"></label></div><p class="hint">'+
      state.catalogRows.length+' voci nel catalogo · fino a 90 risultati per pagina</p>'+
      '<div id="catalog-results" class="catalog-results">'+renderCatalogRows()+'</div>')+
    quickPanel+detail;
}

async function computeLocalData(record){
  let catalogs={},loadError="";
  try{catalogs=await loadRuleCatalogs();}
  catch(error){loadError="Cataloghi numerici offline non disponibili: "+errorMessage(error);}
  return {...calculateSheet(record,catalogs),loadError,
    infusion_catalog:catalogs.abilityGrants?.artificer_infusions||[],
    infusion_mechanics:catalogs.classMechanics||{}};
}
async function editorView() {
  if(!state.editor) state.editor = await openCreatureEditor(state.creatureId);
  const c = state.editor.read();
  const tabs = sheetSections;
  const navigation = '<div class="editor-head">'+
    '<button type="button" class="btn small ghost" data-act="back">← Indietro</button>'+
    '<h1>'+esc(c.name)+'</h1></div>'+
    '<div class="row between editor-meta">'+tag(c.kind === "monster" ? "Mostro" : "Personaggio")+
    '<span id="save-state" class="save-status'+(state.saveError?" error":"")+'">'+
    (state.saveError ? esc(state.saveError) : "✓ Salvato in locale")+'</span></div>'+
    '<div class="current-section">'+esc(tabs.find(([key])=>key===state.sheet)?.[1] || "Info")+'</div>';
  let body = "";
  if(['info','origins'].includes(state.sheet)){
    await Promise.all(["races","classes","subclasses","backgrounds",...(state.sheet==='origins'?['feats']:[])].map(async key=>{
      if(!state.referenceCatalogs[key])try{state.referenceCatalogs[key]=await catalogEntries(key);}
      catch{ /* References stay editable offline. */ }
    }));
  }
  if(state.sheet==="actions"){
    const [featureRules,generalRules]=await Promise.allSettled([loadFeatureActionOverrides(),loadGeneralActionSupplements()]);
    state.featureActionOverrides=featureRules.status==='fulfilled'?featureRules.value:[];
    state.generalActionSupplements=generalRules.status==='fulfilled'?generalRules.value:[];
    state.actionCatalogError=generalRules.status==='rejected'?
      'Le azioni generali e le regole varianti non sono state caricate: '+errorMessage(generalRules.reason):'';
  }
  if((state.sheet==="actions"||state.sheet==="magic"||state.sheet==='origins'&&state.detail==='origin_spell_grants')&&!state.spellCatalog){
    try{state.spellCatalog=await catalogEntries("spells");state.spellCatalogError="";}
    catch(error){state.spellCatalogError=errorMessage(error);}
  }
  if(state.sheet==="magic"&&!state.abilityCatalog){
    try{state.abilityCatalog=await loadActivatedAbilities();}
    catch{state.abilityCatalog=[];}
  }
  const calculated=await computeLocalData(c);
  state.calculated=calculated;
  body=nativeSection(c,state.sheet,{field,area,panel,resources:resourceView(c,false),resourcesEditor:resourceView(c,true),equipment:equipmentView(c,['main','off'],false),armor:equipmentView(c,['body'],false),attacks:attacksView(calculated),details:state.detail,catalogs:{...state.referenceCatalogs,origins:calculated.origins,trackers:calculated.trackers,attacks:calculated.attacks,calculated,spells:state.spellCatalog||[]},calculated})||"";
  switch(state.sheet){
  case "inventory": {
    const inventory=Array.isArray(c.inventory)?c.inventory:[];
    const ordinary=inventory.map((item,index)=>({item,index})).filter(({item})=>!isDocument(item));
    const documents=inventory.map((item,index)=>({item,index})).filter(({item})=>isDocument(item));
    const definitions=await Promise.all(documents.map(({item})=>
      getRecord("global","homebrew",String(item.id||""))));
    body=panel("Oggetti nell’inventario",
      '<p class="hint">Gli oggetti del catalogo mantengono le proprietà originali; ogni copia ha quantità e stato di equipaggiamento propri.</p>'+
      (ordinary.length?ordinary.map(({item,index})=>inventoryRow(item,index)).join(""):
        '<p class="hint">Nessun oggetto.</p>')+
      '<div class="actions">'+btn("item-catalog","Cerca nel catalogo","primary")+
      btn("add-item","Crea oggetto locale")+'</div>')+
      panel("Documenti",'<p class="hint">Documenti personalizzati condivisi tra le copie della scheda. Stile e data sono specifici di ciascuna copia.</p>'+
      (documents.length?documents.map(({item,index},i)=>
        documentRow(item,index,definitions[i])).join(""):
        '<p class="hint">Nessun documento.</p>')+
      '<div class="actions">'+btn("document-add","＋ Nuovo documento","primary")+'</div>')+
      infusionPanel(c,calculated);
    break;
  }
  case "actions":
    body=(state.actionCatalogError?'<p class="hint action-catalog-warning" role="alert">'+
      esc(state.actionCatalogError)+'</p>':'')+
      (state.spellCatalogError?'<p class="hint action-catalog-warning" role="alert">Incantesimi non disponibili: '+
      esc(state.spellCatalogError)+'</p>':'')+
      actionEconomyView(c,calculated,state.spellCatalog||[],state.featureActionOverrides||[],
        state.generalActionSupplements||[],readActionVariants());
    break;
  case "magic":
    body=panel('Concentrazione',
      '<div class="magic-concentration"><span>'+esc((c.conditions||[]).includes('concentrating')?
        c.concentrating_spell_id||'Attiva':'Nessuna')+'</span>'+
      ((c.conditions||[]).includes('concentrating')?
        btn('stop-concentration','Interrompi','small'):'')+'</div>')+
      panel("Incantesimi disponibili",
        calculated.casting_classes.map(member=>{
          const count=classSelectionCount(c,member,calculated.casting_classes,state.spellCatalog||[]);
          return '<section class="magic-source"><header class="magic-source-header"><h3>'+esc(member.name)+'</h3>'+
            '<span class="hint">'+esc(member.source||'')+'</span></header>'+
            '<p class="hint magic-source-count">'+esc(member.mode)+' '+count.leveled+' / '+
            (member.limit<0?'—':member.limit)+' · Trucchetti '+count.cantrips+' / '+member.cantrips+'</p>'+
            castingStatistics(c,member.id,member.ability)+
            spellList(c,'prepared_spells',member.id,calculated.casting_classes)+'</section>';
        }).join('')+
        (!calculated.casting_classes.length||availableSpells(c).some(spell=>
          !castingSources(spell,calculated.casting_classes,state.spellCatalog||[]).some(id=>
            calculated.casting_classes.some(member=>member.id===id)))?
          '<section class="magic-source"><h3>Altri incantesimi</h3>'+
          castingStatistics(c,'manual',c.spellcasting_ability||calculated.casting_classes[0]?.ability||'int')+
          spellList(c,'prepared_spells','manual',calculated.casting_classes)+'</section>':''),
        'magic-panel')+
      panel('Slot · Classi / Patto','<div class="slot-table"><strong>Liv.</strong><strong>Classi</strong><strong>Patto</strong>'+calculated.spell_slots.map(slot=>{
        const level=slot.level,pact=calculated.pact_slots;
        return '<span>'+level+'°</span><div>'+slotCounter(level,slot.total,slot.spent)+
          '<details><summary>Usati / modifica base</summary><label>Slot usati<input type="number" min="0" max="99" data-slot="'+level+'" value="'+esc(c.spell_slots_spent?.[level]||0)+'"></label><label>Massimo base<input type="number" min="0" max="99" data-slot-total="'+level+'" value="'+esc(slot.base)+'"></label></details></div><div>'+(pact.level===level?slotCounter(0,pact.total,pact.spent):'—')+'</div>';
      }).join('')+'</div><details><summary>Impostazioni slot</summary><p>'+((c.spell_slots_manual||!c.spell_slots_automatic&&c.spell_slots_total?.some(n=>n>0))?'Massimi personalizzati':'Progressione automatica dalle classi')+'</p>'+btn('slots-automatic','Usa progressione automatica')+
      '<label>Slot del Patto · massimo base<input type="number" min="0" max="99" data-pact-total value="'+esc(calculated.pact_slots.base)+'"></label>'+field('Slot del Patto usati','pact_slots_spent',c.pact_slots_spent??0,'number','min="0" max="99"')+
      field('Livello slot del Patto','pact_slot_level',c.pact_slot_level??calculated.pact_slots.level,'number','min="1" max="9"')+'</details><div class="actions">'+btn('slots-restore','Ripristina tutti gli slot')+'</div>')+
      originChoicesView(calculated)+originPowersView(c,calculated)+
      panel("Libro degli incantesimi",spellList(c,"spellbook_spells",null,calculated.casting_classes),'magic-panel')+
      panel("Aggiungi dal catalogo",
        '<label>Classe / origine<select id="spell-class"><option value="manual">Altre concessioni</option>'+calculated.casting_classes.map(member=>'<option value="'+esc(member.id)+'" '+(member.id===state.spellClass?'selected':'')+'>'+esc(member.name)+'</option>').join('')+'</select></label>'+
        '<label>Destinazione<select id="spell-target">'+
        '<option value="prepared_spells"'+(state.spellTarget==="prepared_spells"?' selected':'')+'>Incantesimi disponibili</option>'+
        '<option value="spellbook_spells"'+(state.spellTarget==="spellbook_spells"?' selected':'')+'>Libro degli incantesimi</option></select></label>'+
        '<label>Cerca incantesimo<input id="spell-search" type="search" value="'+
        esc(state.spellQuery)+'" placeholder="Nome o fonte"></label>'+
        (state.spellCatalogError?'<p class="warning">'+esc(state.spellCatalogError)+'</p>':'')+
        '<div id="spell-results" class="catalog-results">'+renderSpellResults()+'</div>')+
      '<button class="btn full" data-act="sheet-details" data-detail="origin_spell_grants">Incantesimi concessi dalle origini</button>'+
      panel("Capacità",
        (abilitiesForCreature(c,state.abilityCatalog||[],calculated).map(ability=>
          '<article class="native-entry"><strong>'+esc(ability.name)+
          '</strong><p class="hint">'+esc(ability.origin)+
          (ability.activation_mode==="contextual"?' · Attivazione contestuale':
           typeof ability.activation_mode==="string"&&ability.activation_mode?' · '+esc(ability.activation_mode):'')+
          (ability.tracker_id?' · '+esc(ability.tracker_name)+' '+esc(ability.tracker_remaining)+' / '+esc(ability.tracker_max):'')+
          '</p>'+(ability.description?'<details><summary>Descrizione</summary><p>'+
          esc(ability.description)+'</p></details>':'')+'</article>').join("")||
          '<p class="hint">Nessuna capacità disponibile.</p>'));
    break;
  case "conditions":
    body=panel("Condizioni",field('Indebolimento · livello','exhaustion',c.exhaustion??0,'number','min="0" max="6"')+'<div class="condition-list">'+conditions.map(id=>
      '<label class="check"><input type="checkbox" data-condition="'+id+'" '+
      ((c.conditions||[]).includes(id)?'checked':'')+'>'+esc(conditionLabel(id))+'</label>').join('')+'</div>');
    break;
  case 'traits':body=await traitsView(c);break;
  case "json":
    body = panel("Editor avanzato",'<p class="warning">Modifica JSON per campi non ancora presenti nella GUI. La scheda viene validata prima del salvataggio; ID e proprietario non possono cambiare.</p>'+
      '<label>Documento completo<textarea id="json-editor" rows="18" spellcheck="false" class="inline-code">'+
        esc(JSON.stringify(c,null,2))+'</textarea></label><div class="actions">'+
      btn("save-json","Salva modifiche JSON","primary")+'</div>');
    break;
  }
  return navigation+'<div data-local-sheet-calculations>'+body+(state.sheet==='info'?'':calculationNote(calculated,calculated.loadError))+'</div><details class="archive-tools"><summary>Opzioni della scheda</summary><div class="actions">'+btn("export","Esporta JSON")+
    '<button type="button" class="btn" data-act="sheet" data-sheet="json">Editor JSON avanzato</button>'+
    btn("delete","Elimina scheda","danger")+'</div></details>';
}
function resourceView(c,configure=false){
 const active=state.calculated?.trackers||[],saved=Array.isArray(c.resource_trackers)?c.resource_trackers:[],origins=state.calculated?.origins||[];
 const trackers=configure?[...active,...saved.filter(t=>!active.some(a=>a.id===t.id)).map(t=>({...t,inactive:true}))]:active;
 const modes=[['manual','Manuale'],['short_rest','Riposo breve'],['long_rest','Riposo lungo'],['turn','Inizio turno'],['d6','Ricarica d6']];
 const options=(rows,value)=>rows.map(([id,name])=>'<option value="'+esc(id)+'" '+(id===value?'selected':'')+'>'+esc(name)+'</option>').join('');
 const control=(t,key,label,value,type='text')=>'<label>'+esc(label)+'<input type="'+type+'" data-tracker-field="'+key+'" data-tracker-id="'+esc(t.id)+'" value="'+esc(value??'')+'" '+(type==='number'?'min="0" max="99999"':'')+'></label>';
 const body=trackers.map(t=>{
  const base=saved.find(row=>row.id===t.id)||t,maximum=Math.max(0,Number(t.max)||0),used=Number(c.resource_tracker_spent?.[t.id])||0;
  const pick=(key,label,rows,value)=>'<label>'+label+'<select data-tracker-field="'+key+'" data-tracker-id="'+esc(t.id)+'">'+options(rows,value)+'</select></label>';
  const actions=!t.inactive?'<div class="row"><button class="btn small" data-act="tracker-less" data-tracker-id="'+esc(t.id)+'">Ripristina 1</button><button class="btn small" data-act="tracker-more" data-tracker-id="'+esc(t.id)+'">Consuma 1</button>'+(t.recharge==='d6'?'<button class="btn small" data-act="tracker-recharge" data-tracker-id="'+esc(t.id)+'">Ricarica d6 · '+esc(t.recharge_min||6)+'+</button>':'')+'</div>':'';
  const optional=(t.partial_recoveries||[]).filter(rule=>rule.mode==='optional_partial'&&c.resource_recovery_ready?.[rule.id]&&!c.resource_recovery_used?.[rule.id]);
  const optionalButton=optional.map(rule=>'<button type="button" class="btn small" data-act="tracker-optional-recovery" data-rule-id="'+esc(rule.id)+'">Recupero speciale · '+esc(rule.feature||rule.resource_name)+'</button>').join('');
  const edit=configure&&!t.automatic?'<div class="columns">'+control(t,'name','Nome',base.name)+control(t,'max','Massimo base',base.max,'number')+control(t,'max_formula','Formula del massimo',base.max_formula)+pick('origin_id','Origine',[['','Senza origine'],...(!origins.some(o=>o.id===base.origin_id)&&base.origin_id?[[base.origin_id,base.origin_name||base.origin_id]]:[]),...origins.map(o=>[o.id,o.name])],base.origin_id||'')+pick('recharge','Recupero',modes,base.recharge||'manual')+control(t,'recharge_min','Ricarica d6 da (1–6)',base.recharge_min||6,'number')+'<label class="check"><input type="checkbox" data-tracker-field="disabled" data-tracker-id="'+esc(t.id)+'" '+(base.disabled?'checked':'')+'>Disattivato</label></div>'+benefitRequirements(base,'data-benefit-tracker="'+esc(t.id)+'"')+(base.max_formula?'<p class="hint">'+esc(formulaPreview(base.max_formula,state.calculated))+'</p>':'')+'<button class="btn small danger" data-act="tracker-delete" data-tracker-id="'+esc(t.id)+'">Elimina</button>':'';
  return '<article class="list-item"><strong>'+esc(t.name)+'</strong><p class="hint">'+esc(t.origin_name||'Senza origine')+' · '+esc(modes.find(([id])=>id===t.recharge)?.[1]||t.recharge||'Manuale')+'</p>'+(t.inactive?'<p class="hint">Non attivo: origine disattivata o requisito non soddisfatto. Utilizzi salvati: '+esc(used)+'</p>':'<div class="row">Disponibili: '+esc(Math.max(0,maximum-used))+' / '+formulaReadout(state.calculated,'tracker:'+t.id,'Massimo '+t.name)+'</div>')+actions+optionalButton+edit+'</article>';
 }).join('');
 return panel('Risorse','<p class="hint">I valori massimi includono formule e bonus attivi. Il riposo breve ripristina le risorse previste e gli slot del Patto; quello lungo ripristina anche gli slot di classe. All’inizio del turno si recuperano solo le risorse previste.</p>'+(body||'<p class="hint">Nessuna risorsa disponibile.</p>')+'<div class="actions">'+btn('tracker-short','Riposo breve')+btn('tracker-long','Riposo lungo')+btn('tracker-turn','Inizio turno')+'</div>')+(configure?panel('Aggiungi tracker','<div class="columns"><label>Nome<input id="tracker-name" maxlength="120"></label><label>Utilizzi massimi<input type="number" id="tracker-max" min="0" max="99999" value="1"></label><label>Formula del massimo (opzionale)<input id="tracker-formula" placeholder="Es. 1 + cha_mod"></label><label>Origine<select id="tracker-origin">'+options([['','Senza origine'],...origins.map(o=>[o.id,o.name])],'')+'</select></label><label>Recupero<select id="tracker-recharge">'+options(modes.filter(([id])=>id!=='d6'),'manual')+'</select></label></div>'+btn('tracker-add','Aggiungi risorsa','primary')):'');
}

function conditionLabel(id){return ({blinded:"Accecato",charmed:"Affascinato",deafened:"Assordato",exhaustion:"Indebolimento",frightened:"Spaventato",grappled:"Afferrato",incapacitated:"Incapacitato",invisible:"Invisibile",paralyzed:"Paralizzato",petrified:"Pietrificato",poisoned:"Avvelenato",prone:"Prono",restrained:"Trattenuto",stunned:"Stordito",unconscious:"Privo di sensi",concentrating:"Concentrazione",surprised:"Sorpreso",hidden:"Nascosto",dead:"Morto"})[id]||id;}
function equipmentView(c,slots=['main','off','body'],boxed=true){
  const rows=Array.isArray(c.inventory)?c.inventory:[];
  const labels=[["main","Mano principale"],["off","Mano secondaria / scudo"],["body","Armatura indossata"]];
  const body='<div class="columns">'+labels.filter(([slot])=>slots.includes(slot)).map(([slot,label])=>{
      const index=rows.findIndex(item=>Array.isArray(item?.equipped_slots)&&item.equipped_slots.includes(slot));
      const eligible=rows.map((item,i)=>({item,i})).filter(({item})=>validSlot(item,slot));
      return '<label>'+label+'<select data-equip-slot="'+slot+'">'+
        '<option value="-1"'+(index<0&&(!c['hand_'+slot+'_special']||c['hand_'+slot+'_special']==='none')?' selected':'')+'>'+(slot==='body'?'Naturale':'Nessuno')+'</option>'+
        (slot!=='body'?[['unarmed',"Colpo senz’armi"],['improvised','Arma improvvisata']].map(([id,name])=>'<option value="'+id+'" '+(index<0&&c['hand_'+slot+'_special']===id?'selected':'')+'>'+name+'</option>').join(''):'')+
        eligible.map(({item,i})=>'<option value="'+i+'"'+(i===index?' selected':'')+'>'+
          esc(item.name||"Oggetto")+'</option>').join('')+'</select></label>';
    }).join('')+'</div>';
  return boxed?panel('Equipaggiamento',body):body;
}
function attacksView(calculated){
 return '<div data-attack-list>'+((calculated.attacks||[]).map(attack=>'<article class="native-entry"><h3>'+esc(attack.name)+'</h3><div class="row between"><span>Tiro per colpire '+formulaReadout(calculated,'attack_hit:'+attack.id,'Tiro per colpire',{signed:true})+'</span><span>Danni: '+esc(attack.damage)+' '+esc(attack.damage_type||'')+'</span></div><p class="hint">'+esc(attack.explanation)+(attack.offhand_bonus?' · Attacco secondario con azione bonus':'')+'</p><div class="row"><span>'+ (attack.melee?'Portata':'Gittata')+' '+formulaReadout(calculated,'attack_range:'+attack.id,'Portata', {suffix:' ft'})+'</span>'+(attack.long_range_feet?'<span>Lunga '+formulaReadout(calculated,'attack_long_range:'+attack.id,'Gittata lunga',{suffix:' ft'})+'</span>':'')+'</div></article>').join('')||'<p class="hint">Seleziona un’arma in una mano per renderne disponibile l’attacco.</p>')+'</div>';
}
async function traitsView(c){
 const groups=[],warnings=[];
 const load=async category=>{
  if(!state.referenceCatalogs[category])try{state.referenceCatalogs[category]=await catalogEntries(category);}
  catch{warnings.push('Riferimenti '+category+' non disponibili offline.');return [];}
  return state.referenceCatalogs[category];
 };
 const linked='<div class="actions">'+[['overview','Origini'],['proficiency_choices','Competenze'],['formula_bonuses','Bonus'],['resources','Tracker'],['origin_spell_grants','Incantesimi da origini']].map(([detail,label])=>'<button class="btn small" data-act="sheet-details" data-detail="'+detail+'">'+label+'</button>').join('')+'</div>';
 const card=entry=>{const description=flattenDescription(entry);return '<details class="trait-card"><summary>'+esc(entry.name)+'</summary>'+(description?'<p class="trait-description">'+esc(description)+'</p>':'')+linked+'</details>';};
 const addReference=async(category,name,source,title)=>{
  if(!name)return;
  const candidates=(await load(category)).filter(r=>r.name?.toLowerCase()===name.toLowerCase()&&(!source||r.source?.toLowerCase()===source.toLowerCase()));
  const row=candidates.length===1?candidates[0]:null;
  const entry=row?await detailedEntry(category,row):{name};
  groups.push('<h3>'+esc(title)+' · '+esc(name)+'</h3>'+card(entry));
 };
 const projected=state.calculated?.features||[];
 if(projected.length){
  const byOrigin=new Map();
  for(const feature of projected){
   const origin=feature.origin_key||'Altro';
   if(!byOrigin.has(origin))byOrigin.set(origin,[]);
   const active=!feature.disabled;
   byOrigin.get(origin).push('<details class="trait-card"><summary>'+esc(feature.name)+
    (feature.level>1?' · livello '+esc(feature.level):'')+
    (!active?' · disattivato':'')+'</summary><p class="trait-description">'+
    esc(flattenDescription(feature))+
    '</p><label class="check"><input type="checkbox" data-feature-origin="'+
    esc(feature.origin_id)+'" '+(active?'checked':'')+'>Beneficio attivo</label>'+
    linked+'</details>');
  }
  for(const [origin,rows] of byOrigin)
   groups.push('<h3>Privilegi · '+esc(origin.replaceAll('|',' · '))+'</h3>'+rows.join(''));
 }
 if(c.kind==='monster'&&!projected.length)for(const t of c.stat_block?.trait||[])groups.push(card(t));
 else{
  if(!projected.some(f=>f.origin_key?.startsWith('species|'))){
   await addReference('races',c.species,c.species_source,'Razza / Specie');
   if(c.subrace)await addReference('races',c.species+' ('+c.subrace+')',c.subrace_source,'Sottorazza');
  }
 }
 if(!projected.some(f=>f.origin_key?.startsWith('background|')))
  await addReference('backgrounds',c.background,c.background_source,'Background');
 if(!projected.some(f=>f.origin_key?.startsWith('class|'))){
 const features=await load('class_features'),subfeatures=await load('subclass_features');
 for(const member of localClasses(c)){
  const source=member.source||(c.rules_version==='2024'?'XPHB':'PHB');
  const selected=features.filter(f=>f.class_name?.toLowerCase()===member.name.toLowerCase()&&f.class_source?.toLowerCase()===source.toLowerCase()&&Number(f.level||0)<=Number(member.level));
  groups.push('<h3>Classe · '+esc(member.name)+' · '+esc(source)+'</h3>'+selected.map(card).join(''));
  const subclass=member.subclass||'',subsource=member.subclass_source||'';
  if(subclass){
    const selected=subfeatures.filter(f=>f.class_name?.toLowerCase()===member.name.toLowerCase()&&f.class_source?.toLowerCase()===source.toLowerCase()&&[f.subclass_name,f.subclass_short_name].some(name=>name?.toLowerCase()===subclass.toLowerCase())&&(!subsource||f.subclass_source?.toLowerCase()===subsource.toLowerCase())&&Number(f.level||0)<=Number(member.level));
    groups.push('<h3>Sottoclasse · '+esc(subclass)+'</h3>'+selected.map(card).join(''));
  }
 }
 }
 for(const feat of c.feats_catalog||[])if(feat?.name&&!feat.disabled&&
    !projected.some(f=>f.origin_key?.startsWith('feat|')&&
      (f.origin_key==='feat|'+String(feat.id||'').toLowerCase()||
       f.origin_key==='feat|'+String(feat.name).toLowerCase()+'|'+String(feat.source||'').toLowerCase())))
   await addReference('feats',feat.name,feat.source,'Talento');
 return panel('Tratti',(groups.join('')||'<p class="hint">Seleziona le origini della creatura per leggerne i tratti.</p>')+warnings.map(w=>'<p class="hint">'+esc(w)+'</p>').join(''))+panel('Tratti aggiuntivi',area('Note sui tratti','additional_traits',typeof c.additional_traits==='string'?c.additional_traits:''));
}
function documentRow(item,index,stored){
  const {title,body,style,addedAt}=documentInfo(item,stored?.data);
  const editable=!!stored;
  const selected=state.openDocumentInstance===String(item.instance_id||item.id);
  return '<details class="document-entry"'+(selected?' open':'')+' data-document-card="'+index+'">'+
    '<summary>'+esc(title)+' <span class="hint">'+(style==="lettera"?"Lettera":"Pergamena")+'</span></summary>'+
    '<div class="document-body">'+
    (addedAt?'<p class="hint">Aggiunto il '+esc(new Date(addedAt*1000).toLocaleDateString("it-IT"))+'</p>':'')+
    '<label>Visualizzazione<select data-document-index="'+index+'" data-document-part="style">'+
      '<option value="pergamena"'+(style==="pergamena"?' selected':'')+'>Pergamena</option>'+
      '<option value="lettera"'+(style==="lettera"?' selected':'')+'>Lettera</option></select></label>'+
    (editable?
      '<details class="document-edit"><summary>Modifica documento</summary>'+
      '<label>Titolo<input maxlength="160" data-document-index="'+index+'" data-document-part="title" value="'+esc(title)+'"></label>'+
      '<label>Testo<textarea maxlength="3500" rows="10" data-document-index="'+index+'" data-document-part="body">'+esc(body)+'</textarea></label>'+
      '<p class="hint">Salvataggio automatico. La definizione viaggia con la creatura esportata.</p></details>':
      '<p class="warning">Definizione homebrew non installata: documento visibile ma non modificabile.</p>')+
    '<div class="document-paper '+(style==="lettera"?'letter':'parchment')+'"><strong>'+esc(title)+'</strong><p>'+esc(body)+'</p></div>'+
    '<div class="actions"><button type="button" class="btn small danger" data-act="document-remove" data-index="'+index+'">Elimina copia</button></div>'+
    '</div></details>';
}
function infusionPanel(c,calculated){
  const caps=infusionLimits(c,calculated.infusion_mechanics);
  if(!caps.level)return "";
  const definitions=calculated.infusion_catalog||[],known=learnedInfusions(c,definitions);
  const options=definitions.filter(row=>caps.level>=Math.max(2,Number(row.min_level)||2));
  const select=(id,rows)=>'<select id="'+id+'">'+rows.map(([value,label])=>
    '<option value="'+esc(value)+'">'+esc(label)+'</option>').join('')+'</select>';
  const itemRows=(c.inventory||[]).map((item,index)=>[index,(item.name||item.id||"Oggetto")+
    (item.infusion?.id?' · ✦ '+(item.infusion.name||'Infuso'):'')]);
  const learned=known.map((entry,index)=>[index,entry.name+
    (entry.plan_item_name?' · '+entry.plan_item_name:'')]);
  const active=(c.inventory||[]).filter(item=>item.infusion?.creator_id===c.id).length;
  return panel('Infusioni · Artefice (TCE)',
    '<p class="hint">Conosciute '+known.length+'/'+caps.known+
    ' · Oggetti infusi '+active+'/'+caps.active+' · Livello Artefice '+caps.level+
    '. Gli effetti numerici sono calcolati in locale, i poteri descrittivi restano consultabili.</p>'+
    '<div class="columns"><label>Nuova infusione'+select('infusion-available',options.map(row=>[row.id,row.name]))+'</label>'+
    '<label>Oggetto dell’inventario'+select('infusion-item',itemRows)+'</label>'+
    '<label>Infusione conosciuta'+select('infusion-known',learned)+'</label></div>'+
    '<div class="actions">'+btn('infusion-learn','Impara')+
    btn('infusion-apply','Infondi oggetto')+
    btn('infusion-forget','Dimentica')+
    btn('infusion-clear','Termina infusione')+'</div>'+
    (definitions.length?'':'<p class="warning">Indice delle infusioni non caricato.</p>'));
}
function inventoryRow(item,index) {
  const obj=item&&typeof item==="object"?item:{name:String(item??"")};
  const kind=itemKind(obj),catalog=isCatalogItem(obj),effective=resolveOwnedItem(obj);
  const checked=(key)=>obj[key]===true?' checked':'';
  const enabled=(key,label)=>'<label class="check"><input type="checkbox" data-item-index="'+index+
    '" data-item-key="'+key+'"'+checked(key)+'>'+label+'</label>';
  const tags=[obj.source||"",obj.rarity||"",obj.type||""].filter(Boolean).join(" · ");
  const quantity=kind==="document"?
    '<span class="hint">Documento</span>':
    listField("Quantità",index,"quantity",obj.quantity??1,"number");
  const name=catalog?'<strong>'+esc(obj.name||"Oggetto")+'</strong>':
    listField("Nome",index,"name",obj.name||"");
  const desc=catalog?'<p class="hint">'+esc(typeof obj.description==="string"?obj.description:"")+'</p>':
    '<label>Descrizione<textarea data-item-index="'+index+'" data-item-key="description" rows="2">'+
    esc(obj.description||"")+'</textarea></label>';
  return '<article class="list-item inventory-entry"><div class="row between">'+name+
    '<button type="button" class="btn danger small" data-act="remove-item" data-index="'+index+'">Rimuovi</button></div>'+
    '<p class="hint">'+esc(tags||"Oggetto personale")+'</p>'+quantity+
    '<div class="inventory-switches">'+
    (!["weapon","shield","armor","document"].includes(kind)?enabled("equipped","Equipaggiato"):'')+
    (requiresAttunement(obj)?enabled("attuned","Sintonia"):'')+
    enabled("active","Attivo")+'</div>'+
    (obj.equipped_slots?.length?'<p class="hint">Slot: '+esc(obj.equipped_slots.join(", "))+'</p>':'')+
    '<details><summary>Proprietà della singola copia</summary>'+
    (kind==='weapon'?'<label>Taglia arma<select data-item-override="weapon_size" data-item-index="'+index+'">'+
      [['','Come la creatura'],...WEAPON_SIZES.map(size=>[size,size])].map(([v,label])=>'<option value="'+esc(v)+'" '+((obj.instance_overrides?.weapon_size||'')===v?'selected':'')+'>'+esc(label)+'</option>').join('')+'</select></label>'+
      [['damage','Dadi danno'],['versatile_damage','Dadi versatile'],['range','Gittata (ft)'],['bonus_weapon','Bonus magico arma']].map(([k,label])=>
        '<label>'+label+'<input data-item-override="'+k+'" data-item-index="'+index+'" placeholder="'+esc(String(obj[k]??''))+
          '" value="'+esc(obj.instance_overrides?.[k]??'')+'"></label>').join(''):
     ['armor','shield'].includes(kind)?
      [['ac','CA base'],['bonus_ac','Bonus CA']].map(([k,label])=>'<label>'+label+
        '<input data-item-override="'+k+'" data-item-index="'+index+'" placeholder="'+esc(String(obj[k]??''))+
        '" value="'+esc(obj.instance_overrides?.[k]??'')+'"></label>').join(''):'')+
    '<p class="hint">Valori effettivi: '+esc([effective.damage,effective.range,effective.ac].filter(x=>x!==undefined&&x!=='').join(' · ')||'Nessuna personalizzazione')+
    '. Per modificare una copia in una pila, la PWA la separa senza cambiare le altre.</p></details>'+
    '<details><summary>Dettagli oggetto</summary>'+desc+
    '<p class="hint">Identificativo: '+esc(obj.id||"Locale")+'</p></details></article>';
}
function listField(label,index,key,value,type="text") {
  return '<label>'+label+'<input type="'+type+'" data-item-index="'+index+'" data-item-key="'+key+
    '" value="'+esc(value)+'" '+(type==="number"?'min="0"':"")+'></label>';
}
function castingStatistics(c,section,ability){
 const selected=c.spellcasting_section_abilities?.[section]||ability;
 return '<div class="casting-statistics"><label>Caratteristica degli incantesimi<select data-casting-section="'+esc(section)+'">'+Object.entries(abilities).map(([id,label])=>'<option value="'+id+'" '+(selected===id?'selected':'')+'>'+esc(label)+'</option>').join('')+'</select></label><span>CD '+formulaReadout(state.calculated,'casting_dc:'+selected,'CD incantesimi',{bonusTarget:'spell_dc'})+'</span><span>Attacco '+formulaReadout(state.calculated,'casting_hit:'+selected,'Attacco incantesimi',{signed:true,bonusTarget:'spell_attack'})+'</span></div>';
}
function slotCounter(level,total,spent){
 const key=level===0?'pact_slot':'slot:'+level;
 return '<div class="slot-counter">'+(total>0?'<button class="btn small" data-act="slot-use" data-level="'+level+'" '+(spent>=total?'disabled':'')+' aria-label="Consuma slot '+level+'">−</button><button class="btn small" data-act="slot-recover" data-level="'+level+'" '+(spent<=0?'disabled':'')+' aria-label="Recupera slot '+level+'">＋</button>':'')+'<span>'+Math.max(0,total-spent)+' / </span><button class="btn small slot-total" data-act="edit-bonus" data-target="'+key+'" data-calculated="'+key+'" aria-label="Bonus massimo slot '+level+'">'+total+'</button></div>';
}
function magicSpellInfo(row){
  const id=spellId(row);
  const definition=(state.spellCatalog||[]).find(spell=>spell.id===id);
  const record=typeof row==='object'&&row?row:{};
  const rawLevel=definition?.level??record.level;
  const level=rawLevel===undefined||rawLevel===null?null:Number(rawLevel);
  return {id,name:text(definition?.name||record.name||(typeof row==='string'?row:id)),level:Number.isInteger(level)&&level>=0&&level<=9?level:null};
}
function groupedMagicSpells(items,renderRow){
  if(!items.length)return '<p class="hint magic-empty">Nessun incantesimo.</p>';
  const ordered=[...items].sort((a,b)=>(a.info.level??10)-(b.info.level??10)||
    a.info.name.localeCompare(b.info.name,'it',{sensitivity:'base'}));
  const groups=new Map();
  for(const item of ordered){
    const level=item.info.level;
    if(!groups.has(level))groups.set(level,[]);
    groups.get(level).push(item);
  }
  return '<div class="magic-groups">'+[...groups.entries()].map(([level,entries])=>
    '<section class="magic-level"><h4>'+(level===0?'Trucchetti':level===null?'Livello non disponibile':'Livello '+level)+'</h4>'+
    '<div class="magic-entries">'+entries.map(renderRow).join('')+'</div></section>').join('')+'</div>';
}
function groupedMagicOptions(spells){
  const rows=spells.map(spell=>({spell,info:magicSpellInfo(spell)})).sort((a,b)=>
    (a.info.level??10)-(b.info.level??10)||
    a.info.name.localeCompare(b.info.name,'it',{sensitivity:'base'}));
  const groups=new Map();
  for(const item of rows){
    if(!groups.has(item.info.level))groups.set(item.info.level,[]);
    groups.get(item.info.level).push(item);
  }
  return [...groups.entries()].map(([level,items])=>
    '<optgroup label="'+(level===0?'Trucchetti':level===null?'Livello non disponibile':'Livello '+level)+'">'+
    items.map(({spell,info})=>'<option value="'+esc(spell.id)+'">'+esc(info.name)+'</option>').join('')+
    '</optgroup>').join('');
}
function originPowersView(c,calculated){
 const groups=new Map();
 for(const grant of calculated.origin_spells||[]){
  const spell=(state.spellCatalog||[]).find(s=>s.id===grant.spell_id);
  const info=magicSpellInfo(spell||{id:grant.spell_id,name:grant.spell_id});
  const key=grant.origin_id||'other';
  if(!groups.has(key))groups.set(key,{name:grant.origin_name||'Origine',ability:grant.spellcasting_ability||'int',items:[]});
  groups.get(key).items.push({grant,spell,info});
 }
 return [...groups.entries()].map(([key,group])=>panel('Origine · '+group.name,
   castingStatistics(c,'origin:'+key,group.ability)+
   groupedMagicSpells(group.items,({grant,spell,info})=>{
     const mode=grant.payment_mode||(grant.tracker_id?'tracker':'free');
     const cost=Math.max(1,Number(grant.tracker_cost)||1);
     return '<div class="magic-spell-row"><button type="button" class="magic-spell-open" data-act="power-spell" data-spell-key="origin" data-grant-id="'+esc(grant.id)+'" aria-label="Apri '+esc(info.name)+'">'+esc(info.name)+'</button>'+
       '<details class="magic-origin-config"><summary aria-label="Configura '+esc(info.name)+'" title="Consumo e origine">⚙</summary>'+
       '<p class="hint">'+(mode==='free'?'Gratuito':mode==='slot'?'Slot incantesimo':'Tracker')+'</p>'+
       '<label>Modalità<select data-origin-config="payment_mode" data-grant-id="'+esc(grant.id)+'">'+[['free','Gratuito'],['slot','Slot incantesimo'],['tracker','Tracker']].map(([value,label])=>'<option value="'+value+'" '+(mode===value?'selected':'')+'>'+label+'</option>').join('')+'</select></label>'+
       '<label>Tracker<select data-origin-config="tracker_id" data-grant-id="'+esc(grant.id)+'"><option value="">Nessuno</option>'+calculated.trackers.map(t=>'<option value="'+esc(t.id)+'" '+(grant.tracker_id===t.id?'selected':'')+'>'+esc(t.name)+'</option>').join('')+'</select></label>'+
       '<label>Costo<input type="number" min="1" max="999" value="'+cost+'" data-origin-config="tracker_cost" data-grant-id="'+esc(grant.id)+'"></label>'+
       (grant.source_choice_id?'<button class="btn small" data-act="origin-choice-remove" data-grant-id="'+esc(grant.id)+'">Cambia scelta</button>':'')+
       '</details></div>';
   }),'magic-panel')).join('');
}
function originChoicesView(calculated){
 const choices=(calculated.origin_choices||[]).filter(choice=>choice.remaining>0);
 if(!choices.length)return '';
 return panel('Scelte da origini',choices.map(choice=>{
  const eligible=choice.spell_options?.length?state.spellCatalog||[]:spellsForEdition(state.spellCatalog||[],state.editor.read().rules_version||'2014');
  const offered=eligible.filter(spell=>originChoiceMatches(choice,spell).matches&&!choice.selected.some(selected=>selected.spell_id===spell.id));
  const supported=(state.spellCatalog||[]).some(spell=>originChoiceMatches(choice,spell).supported);
  return '<article class="native-entry"><h3>'+esc(choice.origin_name)+' · Scegli ancora '+choice.remaining+'</h3><p class="hint">'+esc(choice.filters?.join(' oppure ')||choice.filter||'Elenco della concessione')+'</p>'+
   (offered.length?'<label>Incantesimo<select data-origin-choice="'+esc(choice.id)+'">'+groupedMagicOptions(offered)+'</select></label><label>Caratteristica<select data-choice-ability="'+esc(choice.id)+'">'+(choice.spellcasting_ability?'':'<option value="">Scegli…</option>')+Object.entries(abilities).map(([key,label])=>'<option value="'+key+'" '+(key===choice.spellcasting_ability?'selected':'')+'>'+label+'</option>').join('')+'</select></label><button class="btn" data-act="origin-choice-pick" data-choice-id="'+esc(choice.id)+'">Conferma scelta</button>':
     '<p class="hint">'+(supported?'Nessun incantesimo disponibile nel catalogo locale per questa concessione.':'Questa concessione richiede un filtro non ancora supportato; la scelta rimane salvata e visibile.')+'</p>')+'</article>';
 }).join(''));
}
function spellList(c,key,classId=null,classes=[]) {
  const rows=key==="prepared_spells"?availableSpells(c):
    Array.isArray(c[key])?c[key]:[];
  const visible=rows.map((spell,i)=>({spell,i,info:magicSpellInfo(spell)}))
    .filter(({spell})=>!classId||
      (classId==='manual'?!castingSources(spell,classes,state.spellCatalog||[]).some(id=>classes.some(member=>member.id===id)):
        castingSources(spell,classes,state.spellCatalog||[]).includes(classId)));
  return groupedMagicSpells(visible,({i,info})=>
    '<div class="magic-spell-row"><button type="button" class="magic-spell-open" data-act="power-spell" data-spell-key="'+esc(key)+'" data-spell-index="'+i+'" data-casting-class="'+esc(classId||'')+'" aria-label="Apri '+esc(info.name)+'">'+esc(info.name||'Incantesimo senza nome')+'</button>'+
    '<button type="button" class="btn small magic-remove-spell" data-act="remove-spell" data-key="'+esc(key)+'" data-class-id="'+esc(classId||'')+'" data-index="'+i+'" title="Rimuovi" aria-label="Rimuovi '+esc(info.name)+'">×</button></div>');
}
function renderSpellResults(){
  const rows=state.spellCatalog||[];
  if(!rows.length)return '<p class="hint">Catalogo non disponibile. Gli incantesimi già salvati restano utilizzabili.</p>';
  const query=state.spellQuery.trim().toLocaleLowerCase();
  if(!query)return '<p class="hint">Digita un nome o una fonte per cercare nel catalogo.</p>';
  const editionSpells=new Set(spellsForEdition(rows,state.editor?.read().rules_version||'2014'));
  const found=rows.map((spell,index)=>({spell,index})).filter(({spell})=>
    (String(spell.name||"")+" "+String(spell.source||"")).toLocaleLowerCase().includes(query)&&
    editionSpells.has(spell)&&
    (state.spellClass==='manual'||!state.calculated?.casting_classes.some(member=>member.id===state.spellClass)||spellEligible(spell,state.calculated.casting_classes.find(member=>member.id===state.spellClass)))).slice(0,40);
  return found.length?groupedMagicSpells(found.map(({spell,index})=>({spell,index,info:magicSpellInfo(spell)})),({spell,index,info})=>
    '<button class="btn full catalog-entry magic-catalog-entry" type="button" data-act="spell-pick" data-index="'+index+'">'+esc(info.name)+'</button>'):
    '<p class="hint">Nessun incantesimo corrispondente.</p>';
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
      (e.text||""))+(e.kind==="roll"&&e.detail?'<div class="hint roll-event-detail">'+esc(e.detail)+'</div>':'')+
      '</div></article>').join("") :
    '<p class="hint">Nessun evento recente. La cronologia è disponibile mentre il desktop è collegato.</p>';
}
function sessionTokenRows(rows, turnId="") {
  return rows.map(token => '<div class="session-token-row'+(state.tokenId===token.id?' selected':'')+
    '" data-token-row="'+esc(token.id)+'">'+
    '<button type="button" class="session-token-name" data-act="select-token" data-id="'+esc(token.id)+
    '" aria-pressed="'+(state.tokenId===token.id)+'">'+
    (token.id===turnId?'<span class="session-turn" aria-label="Turno attivo">▶</span>':'')+
    '<span>'+esc(token.name)+(token.free?' <small>· libero</small>':'')+'</span></button>'+
    (token.initiative!==undefined?'<span class="session-initiative" title="Iniziativa">'+esc(token.initiative)+'</span>':'')+
    '<button class="btn small session-edit-btn" type="button" data-act="edit-token" data-id="'+esc(token.id)+
    '" aria-label="Modifica '+esc(token.name)+'" title="Condizioni, incantesimi e miniatura">⚙</button></div>').join('');
}
function sessionView() {
  const entries=Array.isArray(state.map?.tokens)?state.map.tokens:[];
  const groups=tokenGroups(state.map);
  const selected=entries.find(t=>t.id===state.tokenId);
  const online=state.online&&state.paired;
  const statusMarkup='<div class="row between"><span>'+tag(online?'Partita connessa':
    state.hostReachable?'Desktop attivo · nessuna partita':'Desktop non raggiungibile')+'</span>'+
    '<button type="button" class="btn small" data-act="check">Aggiorna</button></div>';
  const pairing='<form id="pair-form" class="stack"><label>Codice temporaneo del desktop'+
    '<input id="pair-secret" type="text" inputmode="text" minlength="16" maxlength="19" pattern="[a-fA-F0-9 -]{16,19}" autocomplete="off" placeholder="XXXX-XXXX-XXXX-XXXX" required></label>'+
    '<label class="check"><input id="pair-remember" type="checkbox" checked> Ricorda desktop</label>'+
    '<button type="submit" class="btn primary full">Collega alla partita</button></form>';
  let html=header('Partita','La tua partita','')+
    panel('Desktop',statusMarkup+(state.paired?'<div class="actions">'+btn('disconnect','Dissocia desktop','danger')+'</div>':pairing),'session-desktop');
  const image=state.snapshotObjectUrl;
  const snapshotMatches=state.liveSnapshot?.token_id===state.tokenId;
  html+='<section class="panel session-map-panel" aria-label="Mappa della partita">'+
    '<div class="session-map-stage">'+
    (image?'<img id="session-map-image" src="'+image+'" alt="Snapshot della mappa desktop" draggable="false">':'<div class="session-map-placeholder">⧉<span>'+(online?'Acquisizione mappa…':'Mappa disponibile quando il desktop è collegato')+'</span></div>')+
    (state.snapshotPending||image&&!snapshotMatches?'<span class="session-map-loading" role="status">Aggiornamento…</span>':'')+
    '</div>'+
    (selected?'<div class="session-selected-controls"><strong>'+esc(selected.name)+'</strong>'+
    '<div class="session-move-buttons" aria-label="Sposta il token">'+
    '<button type="button" class="btn small" data-act="move" data-direction="north" aria-label="Nord">↑</button>'+
    '<button type="button" class="btn small" data-act="move" data-direction="west" aria-label="Ovest">←</button>'+
    '<button type="button" class="btn small" data-act="move" data-direction="south" aria-label="Sud">↓</button>'+
    '<button type="button" class="btn small" data-act="move" data-direction="east" aria-label="Est">→</button>'+
    '<button type="button" class="btn small" data-act="move-up" aria-label="Quota più">+↑</button>'+
    '<button type="button" class="btn small" data-act="move-down" aria-label="Quota meno">−↓</button></div></div>':'')+
    '</section>';
  if(!state.paired)return html;
  html+='<section class="panel session-token-panel">'+
    '<div class="row between"><h2>'+(groups.active?'Combattimento · Round '+esc(groups.round):'Token sulla mappa')+
    '</h2>'+(groups.active?'<span class="tag">Iniziativa</span>':'')+'</div>'+
    (groups.participants.length?sessionTokenRows(groups.participants,groups.turnId):
      '<p class="hint">Nessun token sulla mappa.</p>')+
    (groups.active&&groups.outside.length?'<h3 class="session-outside-heading">Fuori dal combattimento</h3>'+
      sessionTokenRows(groups.outside):'')+
    '<button type="button" class="btn primary full session-add-token" data-act="open-place-token"'+
      (!online||!entries.length?' disabled':'')+'>＋ Aggiungi token da una tua scheda</button>'+
    '</section>';
  if(state.editTokenId){
    const edited=entries.find(t=>t.id===state.editTokenId);
    if(edited){
      const linked=(state.cachedCreatures||[]).find(c=>c.linked_token_sync_id===edited.id);
      const active=(edited.active_spell_ids||[]).map(id=>{
        const definition=(state.spellCatalog||[]).find(x=>x.id===id);
        return '<div class="row between session-applied-spell"><span>'+esc(definition?.name||id)+'</span>'+
          '<button type="button" class="btn small" data-act="remove-token-spell" data-spell-id="'+esc(id)+'">✕</button></div>';
      }).join('');
      html+='<dialog id="session-token-dialog" class="session-dialog" aria-label="Modifica token"><h2>⚙ '+esc(edited.name)+'</h2>'+
        '<h3>Condizioni</h3><div class="session-condition-grid">'+conditions.map(id=>
          '<label class="check"><input type="checkbox" data-token-condition="'+id+'" '+((edited.conditions||[]).includes(id)?'checked':'')+'>'+esc(id)+'</label>').join('')+'</div>'+
        '<h3>Incantesimi applicati</h3>'+ (active||'<p class="hint">Nessun incantesimo attivo.</p>')+
        '<label>Cerca incantesimo<input id="token-spell-query" type="search" placeholder="Nome incantesimo"></label>'+
        '<label>Incantesimo<select id="token-spell-select"></select></label>'+
        '<button type="button" class="btn small" data-act="apply-token-spell">＋ Applica incantesimo</button>'+
        '<h3>Miniatura</h3>'+
        (linked?'<p class="hint">Puoi cambiare la miniatura dei token associati alla tua scheda.</p>'+
          '<label>Cerca miniatura<input id="token-mini-query" type="search" placeholder="Nome miniatura"></label>'+
          '<label>Miniatura<select id="token-mini-select"></select></label>'+
          '<button type="button" class="btn small" data-act="apply-token-appearance">Applica miniatura</button>':
          '<p class="hint">La miniatura può essere cambiata dal dispositivo che controlla la scheda collegata.</p>')+
        '<div class="session-dialog-footer"><button type="button" class="btn" data-act="close-token-dialog">Chiudi</button></div></dialog>';
    }
  }
  html+='<dialog id="session-place-dialog" class="session-dialog" aria-label="Aggiungi token"><h2>Aggiungi token</h2>'+
    '<label>La tua scheda<select id="place-creature">'+(state.cachedCreatures||[]).map(c=>
      '<option value="'+esc(c.id)+'">'+esc(c.name)+'</option>').join('')+'</select></label>'+
    '<label>Accanto al token<select id="place-reference">'+entries.map(t=>
      '<option value="'+esc(t.id)+'" '+(t.id===state.tokenId?'selected':'')+'>'+esc(t.name)+'</option>').join('')+'</select></label>'+
    '<label>Direzione<select id="place-direction"><option value="north">Nord</option><option value="east">Est</option><option value="south">Sud</option><option value="west">Ovest</option></select></label>'+
    '<div class="session-dialog-footer"><button class="btn primary" type="button" data-act="place-creature">Piazza token</button>'+
    '<button class="btn" type="button" data-act="close-place-dialog">Annulla</button></div></dialog>';
  return html;
}

function openSessionDialog(dialog) {
  if(!dialog)return;
  if(typeof dialog.showModal==="function")dialog.showModal();
  else dialog.setAttribute("open","");
}
function closeSessionDialog(dialog) {
  if(!dialog)return;
  if(typeof dialog.close==="function")dialog.close();
  else dialog.removeAttribute("open");
}
function renderSessionIfIdle() {
  if(state.page!=="session")return;
  // A live poll must not close a modal or destroy a focused mobile editor.
  if(app.querySelector("dialog[open]"))return;
  const focused=document.activeElement;
  if(focused && app.contains(focused) && ["INPUT","SELECT","TEXTAREA"].includes(focused.tagName))return;
  const scroll=window.scrollY;
  app.innerHTML=sessionView();
  window.scrollTo(0,scroll);
}
async function refreshSessionSnapshot(force=false) {
  if(!state.paired||!state.online||state.page!=="session"||!state.map)return;
  const key=currentGameSession+"|"+state.tokenId+"|"+snapshotRevision(state.map);
  if(!force && key===state.snapshotKey)return;
  const generation=++snapshotGeneration;
  state.snapshotKey=key;
  state.snapshotPending=true;
  renderSessionIfIdle();
  // Godot's one-shot capture is not reentrant. Serialize requests, discarding
  // obsolete selections before allocating a new SubViewport on the desktop.
  const run=async()=>{
    if(generation!==snapshotGeneration)return;
    try {
      const owner=await ownerId();
      if(generation!==snapshotGeneration)return;
      const result=await action("snapshot",{token_id:state.tokenId,
        owner_id:owner,field_feet:120,attack:{}});
      if(generation!==snapshotGeneration)return;
      const blob=snapshotBlob(result);
      if(!blob)throw Error(result?.error||"Snapshot WebP non valido.");
      // Generate a new CSP-compatible URL only when fresh bytes arrive, not
      // every 2.5s poll or during rerenders. Drop the previous allocation.
      const newUrl=URL.createObjectURL(blob);
      const oldUrl=state.snapshotObjectUrl;
      state.snapshotObjectUrl=newUrl;
      state.liveSnapshot={token_id:result.token_id};
      // An open token editor deliberately blocks a whole session rerender.
      // Keep the image current without closing that dialog.
      const image=app.querySelector("#session-map-image");
      if(image)image.src=newUrl;
      if(oldUrl)URL.revokeObjectURL(oldUrl);
    }catch(error){
      if(generation!==snapshotGeneration)return;
      state.snapshotKey="";
      if(force)message("Snapshot: "+errorMessage(error),true);
    }finally{
      if(generation===snapshotGeneration){
        state.snapshotPending=false;
        renderSessionIfIdle();
      }
    }
  };
  snapshotCaptureQueue=snapshotCaptureQueue.catch(()=>{}).then(run);
  return snapshotCaptureQueue;
}
function fillSessionSpells(query="") {
  const select=app.querySelector("#token-spell-select");
  if(!select)return;
  const search=query.trim().toLocaleLowerCase("it");
  const rows=(state.spellCatalog||[]).filter(s=>s?.id&&s?.name&&
    (!search||s.name.toLocaleLowerCase("it").includes(search))).slice(0,65);
  select.innerHTML=rows.map(spell=>'<option value="'+esc(spell.id)+'">'+esc(spell.name)+'</option>').join("");
}
function fillSessionMiniatures(query="") {
  const select=app.querySelector("#token-mini-select");
  if(!select)return;
  const search=query.trim().toLocaleLowerCase("it");
  const rows=(state.miniatureCatalog||[]).filter(m=>m?.id&&m?.name&&
    (!search||m.name.toLocaleLowerCase("it").includes(search))).slice(0,65);
  select.innerHTML=rows.map(row=>'<option value="'+esc(row.id)+'">'+esc(row.name)+'</option>').join("");
}
async function loadSessionMiniatures() {
  if(state.miniatureCatalog)return;
  const result=await fetch("/catalog/miniatures.json",{cache:"no-store"});
  if(!result.ok)throw Error("Catalogo miniature non disponibile.");
  const data=await result.json();
  state.miniatureCatalog=Array.isArray(data.tokens)?data.tokens:[];
}
async function reopenTokenEditor() {
  renderSessionIfIdle();
  const dialog=app.querySelector("#session-token-dialog");
  if(dialog){
    openSessionDialog(dialog);
    fillSessionSpells();
    if(app.querySelector("#token-mini-select")){
      try{await loadSessionMiniatures();fillSessionMiniatures();}
      catch(error){message(errorMessage(error),true);}
    }
  }
}
async function refreshConnection(quiet=false) {
  // Offline does not mean unpaired: a stored credential can be validated again
  // when the host comes back, without requiring another single-use QR.
  state.paired=await hasPairingCredential();
  try {
    const result=await status();
    state.hostReachable=true;
    state.online=!!result.desktop_online;
    if(state.online){
      try {
        acceptSession(await session());state.paired=true;
      }catch(error){
        state.online=false;state.session=null;
        if(error.status===401){
          await unpair();state.paired=false;
        }else if(error.status!==503 && !quiet)message(errorMessage(error),true);
      }
    }else state.session=null;
  }catch(error){
    state.hostReachable=false;state.online=false;state.session=null;
  }
  if(!state.online){state.map=null;state.tokenId="";}
  syncNav();
}
function startMap() {
  state.stopMap?.();
  const generation=++mapGeneration;
  state.stopMap = subscribeMap(data=>{
    if(generation!==mapGeneration)return;
    const recovered=!state.online;
    const currentFingerprint=snapshotRevision(data);
    const changed=currentFingerprint!==previousMapFingerprint;
    previousMapFingerprint=currentFingerprint;
    state.map = data;
    state.online=true;
    state.hostReachable=true;
    if(recovered){
      syncNav();
      // The native board can restart while the PWA is open. Refresh its
      // session label without interrupting the recovered tactical view.
      session().then(info=>{
        if(state.page==="session"&&state.paired)acceptSession(info);
      }).catch(()=>{});
    }
    const entries=data?.tokens||[];
    // Match Android's local ownership boundary: public token status is
    // projected into the linked sheet only, never the server's private data.
    const fingerprint=JSON.stringify(entries.map(row=>[row.id,row.conditions,
      row.concentrating_spell_id,row.active_spell_ids,row.current_miniature_id,row.default_miniature_id]));
    if(fingerprint!==tokenStatusFingerprint){
      tokenSyncQueue=tokenSyncQueue.then(async()=>{
        if(generation!==mapGeneration)return;
        const current=state.editor&&state.creatureId?
          {id:state.creatureId,editor:state.editor}:null;
        const changed=await syncLinkedTokenStatuses(data,{liveEditor:current,spells:state.spellCatalog||[]});
        if(generation!==mapGeneration)return;
        tokenStatusFingerprint=fingerprint;
        if(changed.length){
          if(state.page==='session'){
            state.cachedCreatures=(await listCreatures()).map(row=>row.creature);
            state.castSheets=new Map(await Promise.all(state.cachedCreatures.map(async c=>[c.id,await computeLocalData(c)])));
          }else if(state.editor&&changed.includes(state.creatureId)){
            if(!app.contains(document.activeElement)||document.activeElement.tagName==='BUTTON')
              await render();
            else{
              state.calculated=await computeLocalData(state.editor.read());
              refreshCalculatedValues(app,state.calculated);
            }
          }else if(state.page==='library')await render();
        }
      }).catch(error=>{message("Sincronizzazione effetti: "+errorMessage(error),true);});
    }
    if(!entries.some(x=>x.id===state.tokenId)) state.tokenId="";
    if(!state.tokenId && entries.length) state.tokenId=entries[0].id;
    if(changed||recovered||!state.snapshotKey){
      renderSessionIfIdle();
      void refreshSessionSnapshot();
    }
  },error=>{
    if(generation!==mapGeneration)return;
    const wasOnline=state.online;
    state.online=false;
    state.hostReachable=!!error?.status;
    // Never leave stale token controls on screen. A temporary 503 or
    // network loss is recoverable: subscribeMap continues retrying.
    state.map=null;
    state.tokenId="";
    previousMapFingerprint="";
    state.snapshotKey="";
    ++snapshotGeneration;
    state.snapshotPending=false;
    tokenStatusFingerprint="";
    if(error?.status===401){
      state.paired=false;state.session=null;
      state.stopMap?.();state.stopMap=null;
      unpair().catch(()=>{}).finally(()=>
        render().catch(e=>message(errorMessage(e),true)));
      return;
    }
    syncNav();
    renderSessionIfIdle();
    if(wasOnline)message("Connessione persa. Riconnessione automatica in corso.");
  },2500);
}
async function fetchChat() {
  if(!state.paired || chatPollGenerationInFlight===chatGeneration)return;
  const generation=chatGeneration;
  chatPollGenerationInFlight=generation;
  try {
    const reply=await action("chat_poll",{after:state.after});
    if(generation!==chatGeneration || state.page!=="chat")return;
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
  }catch(error){
    if(generation===chatGeneration && state.page==="chat" && error.status===401){
      state.paired=false;
      stopSubscriptions();
      render().catch(e=>message(errorMessage(e),true));
      message(errorMessage(error),true);
    }
  }finally{
    if(chatPollGenerationInFlight===generation)chatPollGenerationInFlight=-1;
  }
}
function startChat() {
  ++chatGeneration;
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
async function shareRoll({quiet=false}={}) {
  if(!state.roll) return;
  if(!state.paired||!state.online) throw new Error("Collega prima una partita.");
  const r=state.roll;
  const event={id:"pwa_"+crypto.randomUUID(),kind:"roll",author:r.author||"Giocatore",
    timestamp:Math.floor(Date.now()/1000),label:r.label||r.notation,
    ...sheetRollChatFields(r)};
  const result=await action("chat_send",{event});
  if(!result.ok) throw new Error(result.error||"Tiro non inviato");
  if(!quiet)message("Tiro condiviso nella chat.");
}
async function patch(patchValue) {
  if(!state.editor) return;
  const status=document.querySelector("#save-state");
  if(status){ status.textContent="Salvataggio…"; status.classList.remove("error"); }
  try {
    await state.editor.update(patchValue);
    const editor=state.editor,revision=editor.revision;
    const calculated=await computeLocalData(editor.read());
    if(state.editor===editor&&revision===editor.revision){
      state.calculated=calculated;
      refreshCalculatedValues(app,calculated);
      const attacks=app.querySelector('[data-attack-list]');if(attacks)attacks.outerHTML=attacksView(calculated);
      const note=app.querySelector('[data-calculation-note]');
      if(note)note.outerHTML=calculationNote(calculated,calculated.loadError);
    }
    state.saveError="";
    if(status){ status.textContent="✓ Salvato in locale"; status.classList.remove("error"); }
  }catch(error) {
    state.saveError=errorMessage(error);
    if(status){ status.textContent="Errore salvataggio";status.classList.add("error"); }
    message("Modifica non salvata: "+state.saveError,true);
  }
}
async function persistDocumentEdit(index,part,creature){
  const item=creature.inventory?.[index];
  if(!isDocument(item))throw Error("Documento non trovato nell'inventario.");
  if(part==="style"){
    const field=app.querySelector('[data-document-index="'+index+'"][data-document-part="style"]');
    if(!field)return;
    const inventory=structuredClone(creature.inventory);
    inventory[index].display_style=documentStyle(field.value);
    await patch({inventory});
    const paper=app.querySelector('[data-document-card="'+index+'"] .document-paper');
    if(paper)paper.className="document-paper "+(inventory[index].display_style==="lettera"?"letter":"parchment");
    return;
  }
  if(part!=="title"&&part!=="body")return;
  const title=app.querySelector('[data-document-index="'+index+'"][data-document-part="title"]')?.value;
  const body=app.querySelector('[data-document-index="'+index+'"][data-document-part="body"]')?.value;
  if(title===undefined||body===undefined)throw Error("Editor documento non disponibile.");
  const activeEditor=state.editor,docId=item.id;
  pendingDocumentWrites=pendingDocumentWrites.catch(()=>{}).then(async()=>{
    const record=await getRecord("global","homebrew",docId);
    if(!record)throw Error("Definizione documento mancante: esporta un backup prima di continuare.");
    const updated=editDocumentDefinition(record.data,title,body);
    await editHomebrewDefinition(updated,record.revision);
    if(state.editor===activeEditor){
      const current=activeEditor.read();
      const rows=structuredClone(current.inventory||[]);
      for(const row of rows)if(row.id===docId)row.name=updated.name;
      await patch({inventory:rows});
      const summary=app.querySelector('[data-document-card="'+index+'"] summary');
      if(summary)summary.firstChild.textContent=updated.name+' ';
      const preview=app.querySelector('[data-document-card="'+index+'"] .document-paper');
      if(preview){
        const heading=preview.querySelector("strong"),paragraph=preview.querySelector("p");
        if(heading)heading.textContent=updated.name;
        if(paragraph)paragraph.textContent=body;
      }
    }
  });
  await pendingDocumentWrites;
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
  if(target.dataset.featureOrigin){
    const id=target.dataset.featureOrigin;
    if(!state.calculated?.features?.some(row=>row.origin_id===id))throw Error('Privilegio non disponibile');
    await patch({origin_enabled:{...creature.origin_enabled,[id]:target.checked}});
    await render();return;
  }
  if(target.dataset.itemOverride){
    await patch({inventory:changeItemOverride(creature.inventory||[],Number(target.dataset.itemIndex),target.dataset.itemOverride,target.value)});
    await render();return;
  }
  if(target.dataset.documentIndex!==undefined){
    await persistDocumentEdit(Number(target.dataset.documentIndex),target.dataset.documentPart,creature);
    return;
  }
  if(target.dataset.equipSlot){
    const slot=target.dataset.equipSlot,index=Number(target.value);
    const special=['unarmed','improvised'].includes(target.value)?target.value:'none';
    await patch({inventory:equipSlot(creature.inventory||[],slot,special!=='none'?-1:index),...(slot==='body'?{}:{['hand_'+slot+'_special']:special})});
    await render();return;
  }
  if(target.dataset.reference){
    const category=target.dataset.reference,key=target.dataset.referenceKey;
    if(!['species','subrace','background','class','subclass'].includes(key))throw Error('Riferimento non valido');
    if(target.value==='__current__')return;
    const rows=state.referenceCatalogs[category]||[];
    const selection=rows.find(r=>String(r.id||r.name+'|'+(r.source||''))===target.value);
    if(target.value&&!selection)throw Error('Riferimento non presente nel catalogo');
    const selected=selection||{};
    const changes={...referencePatch(creature,key,selected),...(key==="background"?quickGrantPatch(creature,selected):{})};
    await patch(changes);
    await render();
    return;
  }
  if(target.dataset.nativeList){
    const key=target.dataset.nativeList,field=target.dataset.key;
    if(key==='dice_bonuses'&&field==='dice'&&!validBonusDice(target.value))throw Error('Dadi: da 1 a 100 dadi d4, d6, d8, d10, d12, d20 o d100; modificatore opzionale');
    const changes=nativeRowPatch(creature,key,Number(target.dataset.index),field,target.type==="checkbox"?target.checked:target.value);
    if(field==='origin_id')changes[key][Number(target.dataset.index)].origin_name=state.calculated.origins.find(o=>o.id===target.value)?.name||'';
    await patch(changes);
    if(key==='formula_bonuses'&&field==='expression'){
      const preview=app.querySelector('[data-formula-preview="'+target.dataset.index+'"]');
      if(preview)preview.textContent=formulaPreview(target.value,state.calculated);
    }
    if(target.dataset.key==='kind'||key==='classes'&&field==='level')await render();
    return;
  }
  if(target.dataset.originConfig){
    const id=target.dataset.grantId,key=target.dataset.originConfig;
    if(!['payment_mode','tracker_id','tracker_cost'].includes(key)||!state.calculated.origin_spells.some(g=>g.id===id))throw Error('Concessione non disponibile');
    let value=target.value;
    if(key==='tracker_cost'){value=Number(value);if(!Number.isInteger(value)||value<1||value>999)throw Error('Costo da 1 a 999');}
    if(key==='payment_mode'&&!['free','slot','tracker'].includes(value))throw Error('Consumo non valido');
    const configs=structuredClone(creature.origin_spell_configs||{});configs[id]={...configs[id],[key]:value};
    await patch({origin_spell_configs:configs});await render();return;
  }
  if(target.dataset.trackerField){
    const key=target.dataset.trackerField,rows=structuredClone(creature.resource_trackers||[]),row=rows.find(t=>t.id===target.dataset.trackerId);
    if(!row||!['name','max','max_formula','recharge','origin_id','disabled','recharge_min'].includes(key))throw Error('Tracker non modificabile');
    let value=target.type==='checkbox'?target.checked:target.value;
    if(key==='name'&&(!value.trim()||value.length>120))throw Error('Nome tracker non valido');
    if(key==='recharge_min'){value=Number(value);if(!Number.isInteger(value)||value<1||value>6)throw Error('Soglia da 1 a 6');}
    if(key==='max'){value=Number(value);if(!Number.isInteger(value)||value<0||value>99999)throw Error('Massimo non valido');}
    if(key==='recharge'&&!['manual','short_rest','long_rest','turn','d6'].includes(value))throw Error('Recupero non valido');
    if(key==='origin_id')row.origin_name=state.calculated.origins.find(o=>o.id===value)?.name||'';
    row[key]=value;await patch({resource_trackers:rows});await render();return;
  }
  if(target.dataset.requirement){
    if(target.dataset.benefitTracker){
      const rows=structuredClone(creature.resource_trackers||[]),row=rows.find(t=>t.id===target.dataset.benefitTracker);if(!row)throw Error('Tracker non disponibile');
      row.requirements=requirementPatch(row,target.dataset.requirement,target.value);await patch({resource_trackers:rows});
    }else{
      const key=target.dataset.benefitList,rows=rowsFor(creature,key),row=rows[Number(target.dataset.index)];
      if(!['formula_bonuses','dice_bonuses'].includes(key)||!row||row.automatic)throw Error('Beneficio non modificabile');
      row.requirements=requirementPatch(row,target.dataset.requirement,target.value);await patch(collectionPatch(creature,key,rows));
    }
    await render();return;
  }
  if(target.dataset.originEnabled){
    const id=target.dataset.originEnabled,rows=structuredClone(creature.proficiency_origins||[]),row=rows.find(o=>o.id===id);
    if(row)row.disabled=!target.checked;else rows.push({id,name:state.calculated.origins.find(o=>o.id===id)?.name||id,disabled:!target.checked});
    await patch({proficiency_origins:rows,origin_enabled:{...creature.origin_enabled,[id]:target.checked}});await render();return;
  }
  if(target.dataset.autoBonus){
    const id=target.dataset.autoBonus,rows=rowsFor(creature,'formula_bonuses'),index=rows.findIndex(row=>row.id===id);
    const automatic=state.calculated.automatic_bonuses.find(row=>row.id===id);if(!automatic)throw Error('Bonus non disponibile');
    const row={...automatic,automatic:true,disabled:!target.checked};if(index>=0)rows[index]=row;else rows.push(row);
    await patch({formula_bonuses:rows});await render();return;
  }
  if(target.dataset.nativePick){
    if(target.value==='__current__')return;
    const rows=state.referenceCatalogs[target.dataset.category]||[];
    const selected=rows.find(row=>String(row.id||row.name+'|'+row.source)===target.value);
    if(target.value&&!selected)throw Error('Riferimento non valido');
    await patch(rowReferencePatch(creature,target.dataset.nativePick,Number(target.dataset.index),target.dataset.key,selected));
    await render();return;
  }
  if(target.dataset.castingSection){
    if(!Object.hasOwn(abilities,target.value))throw Error('Caratteristica non valida');
    await patch({spellcasting_section_abilities:{...creature.spellcasting_section_abilities,[target.dataset.castingSection]:target.value}});
    await render();return;
  }
  if(target.hasAttribute('data-slot-total')||target.hasAttribute('data-pact-total')){
    const value=Number(target.value);
    if(!Number.isInteger(value)||value<0||value>99)throw Error('Massimo slot non valido');
    const out=await computeLocalData(creature);
    // Freeze both groups when entering manual mode, retaining current totals.
    const totals=[0,...out.spell_slots.map(s=>s.base)],changes={spell_slots_manual:true,spell_slots_total:totals,pact_slots_total:out.pact_slots.base,pact_slot_level:out.pact_slots.level};
    if(target.hasAttribute('data-pact-total'))changes.pact_slots_total=value;
    else totals[Number(target.dataset.slotTotal)]=value;
    await patch(changes);await render();return;
  }
  if(target.hasAttribute("data-native-cr")){
    const value=target.value.trim();
    if(!/^(?:\d+(?:\.\d+)?|\d+\/[1-9]\d*)$/.test(value))throw Error("GS non valido");
    const stat=structuredClone(creature.stat_block||{});
    stat.cr=stat.cr&&typeof stat.cr==="object"?{...stat.cr,cr:value}:value;
    await patch({stat_block:stat});return;
  }
  if(target.dataset.field){
    const key=target.dataset.field;
    let value=target.type==="checkbox"?target.checked:target.value;
    if(target.type==="number") {
      value=Number(value);
      if(!Number.isFinite(value)) throw new Error("Inserisci un numero valido.");
    }
    if(target.validity&&!target.validity.valid)throw Error("Valore fuori intervallo");
    const changes=identityPatch(creature,key,value);
    if(key==='pact_slot_level'){
      const calculated=await computeLocalData(creature);
      Object.assign(changes,{spell_slots_manual:true,spell_slots_total:[0,...calculated.spell_slots.map(s=>s.base)],pact_slots_total:calculated.pact_slots.base});
    }
    const category=({species:"races",subrace:"races",class:"classes",subclass:"subclasses",background:"backgrounds"})[key];
    if(category){
      const matches=(state.referenceCatalogs[category]||[]).filter(r=>r.name===value);
      if(matches.length===1){changes[key+"_id"]=matches[0].id||"";changes[key+"_source"]=matches[0].source||"";}
    }
    await patch(changes);
    if(key==='rules_version'||key==='primary_class_level')await render();
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
    const value=target.type==="checkbox"?target.checked:target.value;
    await patch({inventory:changeOwnedItem(creature.inventory||[],index,key,value)});
  } else if(target.dataset.condition){
    const entries=new Set(creature.conditions||[]);
    if(target.checked) entries.add(target.dataset.condition);
    else entries.delete(target.dataset.condition);
    await patch({conditions:[...entries],...(target.dataset.condition==='concentrating'&&!target.checked?{concentrating_spell_id:''}:{})});
  }
}
async function refreshMapOnce() {
  const editing=Boolean(app.querySelector("#session-token-dialog[open]"));
  if(editing)closeSessionDialog(app.querySelector("#session-token-dialog"));
  state.map=await map();
  if(state.page==="session"){
    renderSessionIfIdle();
    void refreshSessionSnapshot(true);
    if(editing)await reopenTokenEditor();
  }
}

// Android and PWA use the same native targeting commands, not independent
// spell/area calculations. Never send a private creature sheet to the host.
async function startTargetedCast(casterId,selection,requestedLevel,payment='auto',expectedToken=''){
  if(!state.paired||!state.online)throw Error("Collega prima la partita al desktop.");
  const stored=await loadCreature(casterId);
  if(!stored)throw Error("Scheda locale non trovata.");
  const tokenId=String(stored.data.linked_token_sync_id||"");
  if(!tokenId||expectedToken&&expectedToken!==tokenId)
    throw Error("Seleziona il token associato alla creatura. Piazza prima la sua miniatura.");
  if(!state.map?.tokens?.some(row=>row.id===tokenId))
    throw Error("Il token della creatura non è sulla mappa attiva.");
  const calculated=await computeLocalData(stored.data);
  const plan=spellCastPlan(stored.data,selection,requestedLevel,calculated,payment);
  if(!tacticalViewer)tacticalViewer=new TacticalViewer({send:action,ownerId,notify:message});
  let charged=false;
  tacticalViewer.onCastAccepted=async()=>{
    if(charged)return;
    const editor=state.editor&&state.creatureId===casterId?
      state.editor:await openCreatureEditor(casterId);
    const current=editor.read();
    const accepted=spellCastPlan(current,selection,requestedLevel,await computeLocalData(current),payment);
    if(Object.keys(accepted.patch).length)await editor.update(accepted.patch);
    charged=true;
    if(state.page==='session'){
      state.cachedCreatures=(await listCreatures()).map(row=>row.creature);
      state.castSheets?.set(casterId,await computeLocalData(editor.read()));
    }else if(state.editor===editor)state.calculated=await computeLocalData(editor.read());
  };
  try{
    await tacticalViewer.open(tokenId);
    await tacticalViewer.beginSpell({spell:selection,slotLevel:plan.slotLevel,context:plan.context});
  }catch(error){
    tacticalViewer.close();
    throw error;
  }
}
function readActionVariants(){
 try{const choices=JSON.parse(window.localStorage.getItem('vtt.actionVariants.2014')||'[]');return Array.isArray(choices)?choices:[];}catch{return [];}
}
function decorateSheetHeadings(){
 for(const heading of app.querySelectorAll('.panel > h2, .native-entry > h3, .current-section')){
  if(heading.querySelector('.vtt-action-glyph,.vtt-info-icon'))continue;
  const title=heading.textContent.trim();
  const icon=INFO_HEADING_ICONS[title];
  if(icon)heading.insertAdjacentHTML('afterbegin','<img class="vtt-info-icon" src="/icons/info/'+icon+'.svg" alt="" aria-hidden="true">');
  else {
   const text=title.toLocaleLowerCase('it');
   const key=heading.classList.contains('current-section')?SHEET_TAB_GLYPHS[state.sheet]||'information':
     /inventari|oggett|equipaggia/.test(text)?'inventory':
     /ferit|salute|punti ferita/.test(text)?'healing':
     /risors|tracker/.test(text)?'reset':
     /caratterist|competenz/.test(text)?'proficiency':
     /abilit/.test(text)?'skill':
     /condizion/.test(text)?'condition':
     /attacc|battaglia|cosa posso/.test(text)?'weapon':
     /fisico|moviment|velocit/.test(text)?'movement':
     /classi/.test(text)?'book':
     /poter|incantesim|slot/.test(text)?'spark':
     /storia/.test(text)?'scroll':
     /tratt|privileg/.test(text)?'proficiency':'information';
   heading.insertAdjacentHTML('afterbegin',actionGlyph(key));
  }
  heading.classList.add('sheet-heading');
 }
}
async function handleAction(target){
  const act=target.dataset.act;
  if(act==="open-place-token"){
    if(!state.map?.tokens?.length)throw Error("Serve almeno un token di riferimento sulla mappa.");
    const dialog=app.querySelector("#session-place-dialog");
    openSessionDialog(dialog);
    return;
  }
  if(act==="close-place-dialog"){closeSessionDialog(app.querySelector("#session-place-dialog"));renderSessionIfIdle();return;}
  if(act==="edit-token"){
    const tokenId=String(target.dataset.id||"");
    if(!state.map?.tokens?.some(row=>row.id===tokenId))throw Error("Token non più presente.");
    state.editTokenId=tokenId;
    state.tokenId=tokenId;
    await render();
    await reopenTokenEditor();
    return;
  }
  if(act==="close-token-dialog"){closeSessionDialog(app.querySelector("#session-token-dialog"));renderSessionIfIdle();return;}
  if(act==="apply-token-spell"||act==="remove-token-spell"){
    const spellId=act==="remove-token-spell"?String(target.dataset.spellId||""):
      String(app.querySelector("#token-spell-select")?.value||"");
    if(!spellId)throw Error("Scegli un incantesimo.");
    const enabled=act==="apply-token-spell";
    const result=await action("set_token_spell",{token_id:state.editTokenId,spell_id:spellId,enabled});
    if(!result.ok)throw Error(result.error||"Effetto non applicato.");
    await refreshMapOnce();
    return;
  }
  if(act==="apply-token-appearance"){
    const tokenId=state.editTokenId;
    const linked=(state.cachedCreatures||[]).find(c=>c.linked_token_sync_id===tokenId);
    if(!linked)throw Error("La miniatura si modifica solo dalla scheda proprietaria.");
    const miniature=String(app.querySelector("#token-mini-select")?.value||"");
    if(!miniature||(state.miniatureCatalog||[]).every(m=>m.id!==miniature))
      throw Error("Scegli una miniatura del catalogo.");
    const result=await action("set_appearance",{token_id:tokenId,owner_id:await ownerId(),miniature_id:miniature});
    if(!result.ok)throw Error(result.error||"Miniatura non applicata.");
    await refreshMapOnce();
    return;
  }
  if(act==='miniature-pick'){
    if(!state.editor)throw Error('Apri prima una scheda.');
    const kind=target.dataset.miniatureKind;
    if(kind!=='base'&&kind!=='current')throw Error('Tipo di miniatura non valido.');
    const response=await fetch('/catalog/miniatures.json');
    if(!response.ok)throw Error('Catalogo miniature non disponibile offline. Collegati al desktop e riprova.');
    const catalog=await response.json();
    const choices=Array.isArray(catalog.tokens)?catalog.tokens.filter(row=>
      typeof row?.id==='string'&&row.id&&typeof row.name==='string'):[];
    if(!choices.length)throw Error('Il catalogo miniature è vuoto.');
    const creatureId=state.creatureId;
    const dialog=document.createElement('dialog');
    dialog.className='sheet-roll-dialog miniature-dialog';
    dialog.innerHTML='<h2>'+(kind==='base'?'Miniatura di base':'Forma attuale')+'</h2>'+
      '<p class="hint">Cerca per nome o ID. La scelta non scarica file 3D sul telefono.</p>'+
      '<label>Cerca miniatura<input type="search" data-miniature-search autocomplete="off"></label>'+
      '<div class="miniature-results" role="list"></div>'+
      '<div class="actions"><button type="button" class="btn" data-miniature-close>Chiudi</button></div>';
    const results=dialog.querySelector('.miniature-results');
    const search=dialog.querySelector('[data-miniature-search]');
    const paint=()=>{
      const query=search.value.trim().toLocaleLowerCase('it');
      const matches=choices.filter(row=>(row.name+' '+row.id).toLocaleLowerCase('it').includes(query)).slice(0,60);
      results.innerHTML=matches.length?matches.map(row=>
        '<button type="button" class="btn miniature-choice" data-miniature-id="'+esc(row.id)+'">'+
        '<strong>'+esc(row.name)+'</strong><small>'+esc(row.size_name||'Medium')+' · '+esc(row.id)+'</small></button>').join(''):
        '<p class="hint">Nessuna miniatura trovata.</p>';
    };
    search.addEventListener('input',paint);
    dialog.querySelector('[data-miniature-close]').addEventListener('click',()=>dialog.close());
    results.addEventListener('click',async event=>{
      const choice=event.target.closest('[data-miniature-id]');
      if(!choice)return;
      const id=choice.dataset.miniatureId;
      const profile=choices.find(row=>row.id===id);
      if(!profile||state.creatureId!==creatureId||!state.editor)return;
      choice.disabled=true;
      try{
        await patch(miniaturePatch(state.editor.read(),profile,kind));
        if(state.saveError)throw Error(state.saveError);
        dialog.close();
        await render();
        message('Miniatura salvata nella scheda locale.');
      }catch(error){choice.disabled=false;message(errorMessage(error),true);}
    });
    dialog.addEventListener('close',()=>dialog.remove(),{once:true});
    document.body.append(dialog);
    paint();
    if(dialog.showModal)dialog.showModal();else dialog.setAttribute('open','');
    search.focus();
    return;
  }
  if(act==='action-expand-all'){
    const details=[...app.querySelectorAll('.action-economy-dashboard details.action-tree, .action-economy-dashboard details.action-economy-entry')];
    const expand=details.some(row=>!row.open);
    for(const row of details)row.open=expand;
    target.textContent=expand?'Comprimi tutto':'Espandi tutto';
    target.setAttribute('aria-expanded',String(expand));
    return;
  }
  if(act==='action-variants'){
    if(!actionVariants().length){
      try{await loadGeneralActionSupplements();}
      catch(error){throw Error('Regole varianti non disponibili: '+errorMessage(error));}
    }
    const dialog=document.createElement('dialog');dialog.className='sheet-roll-dialog action-variants-dialog';
    const enabled=readActionVariants();
    dialog.innerHTML='<h2>Regole varianti · 2014</h2><label>Cerca una regola<input type="search" data-variant-search></label><div class="variant-list">'+actionVariants().map(row=>'<label class="check" data-variant-row><input type="checkbox" value="'+esc(row.id)+'" '+(enabled.includes(row.id)?'checked':'')+'><span>'+esc(row.name)+' <a target="_blank" rel="noopener" href="'+esc(row.source_url)+'">'+esc(row.source)+', p. '+esc(row.page)+'</a></span></label>').join('')+'</div><div class="actions"><button type="button" class="btn primary" data-save-variants>Applica</button><button type="button" class="btn" data-close-variants>Chiudi</button></div>';
    dialog.querySelector('[data-variant-search]').addEventListener('input',e=>{for(const row of dialog.querySelectorAll('[data-variant-row]'))row.hidden=!row.textContent.toLocaleLowerCase('it').includes(e.target.value.toLocaleLowerCase('it'));});
    dialog.querySelector('[data-save-variants]').addEventListener('click',async()=>{try{window.localStorage.setItem('vtt.actionVariants.2014',JSON.stringify([...dialog.querySelectorAll('input[type=checkbox]:checked')].map(el=>el.value)));dialog.remove();await render();}catch{message('Impossibile salvare le varianti sul dispositivo');}});
    dialog.querySelector('[data-close-variants]').addEventListener('click',()=>dialog.remove());
    dialog.addEventListener('cancel',()=>dialog.remove(),{once:true});document.body.append(dialog);dialog.showModal();return;
  }
  if(act==='action-open-spells'){
    state.sheet='magic';await render();return;
  }
  if(act==='action-cast-spell'||act==='power-spell'){
    const record=state.editor?.read();if(!record)throw Error('Apri una scheda prima del lancio.');
    const calculated=await computeLocalData(record);
    const key=act==='power-spell'?target.dataset.spellKey:'';
    const index=Number(target.dataset.spellIndex);
    const grantId=String(target.dataset.grantId||'');
    const classId=String(target.dataset.castingClass||'');
    const saved=key==='spellbook_spells'?record.spellbook_spells?.[index]:
      key==='prepared_spells'?availableSpells(record)[index]:null;
    const grant=key==='origin'?calculated.origin_spells?.find(row=>row.id===grantId):null;
    const id=key==='origin'?grant?.spell_id:key?spellId(saved):target.dataset.spellId;
    if(!id)throw Error('Incantesimo non disponibile.');
    const entries=sessionSpellEntries(record,calculated,state.spellCatalog||[]);
    const entry=entries.find(row=>row.id===id&&String(row.grant_id||'')===grantId&&
      (key==='origin'||String(row.casting_class||'')===(classId==='manual'?'':classId)))||
      (key==='spellbook_spells'?entries.find(row=>row.id===id):null);
    const catalogSpell=(state.spellCatalog||[]).find(row=>row.id===id);
    const stored=typeof saved==='object'&&saved?saved:{};
    const spell=entry||catalogSpell||stored;
    const detailed=await detailedEntry('spells',{...catalogSpell,...spell,_category:'spells'});
    const description=flattenDescription(detailed)||'Descrizione non disponibile nel catalogo locale.';
    const level=magicSpellInfo({...spell,id}).level;
    const options=[];
    if(entry&&level!==null){
      const assigned=calculated.origin_spells?.find(row=>row.id===entry.grant_id);
      const mode=assigned?.payment_mode||(level===0?'free':'slot');
      if(level===0||mode==='free'||mode==='tracker'){
        options.push(['auto:0',mode==='tracker'?'Usa il tracker previsto':'Senza slot']);
      }else{
        for(const slot of calculated.spell_slots||[]){
          if(Number(slot.level)>=level&&Number(slot.total)-Number(slot.spent)>0)
            options.push(['slot:'+slot.level,'Slot '+slot.level+'° · '+(slot.total-slot.spent)+' disponibili']);
        }
        if(!assigned&&calculated.pact_slots?.level>=level&&calculated.pact_slots?.total>calculated.pact_slots?.spent)
          options.push(['pact:'+calculated.pact_slots.level,'Patto · '+calculated.pact_slots.level+'° livello']);
      }
    }
    app.querySelector('#action-cast-dialog')?.remove();
    const dialog=document.createElement('dialog');dialog.className='sheet-roll-dialog magic-spell-dialog';dialog.id='action-cast-dialog';
    dialog.innerHTML='<h2>'+esc(spell.name||id)+'</h2>'+
      '<p class="hint magic-spell-metadata">'+(level===0?'Trucchetto':level===null?'Livello non specificato':'Livello '+level)+
      (spell.school?' · '+esc(spell.school):'')+(spell.source?' · '+esc(spell.source):'')+'</p>'+
      '<div class="magic-spell-description">'+esc(description)+'</div>'+
      (detailed._description_warning?'<p class="hint">'+esc(detailed._description_warning)+'</p>':'')+
      (entry&&options.length?
        '<label>Livello di lancio / risorsa<select id="action-cast-choice">'+options.map(([value,label])=>'<option value="'+esc(value)+'">'+esc(label)+'</option>').join('')+'</select></label>':
        '<p class="hint">'+(entry?'Nessuna risorsa di lancio disponibile.':'Incantesimo non preparato: puoi consultarlo dal libro, ma non lanciarlo.')+'</p>')+
      '<div class="actions magic-dialog-actions">'+
      (entry&&options.length?'<button type="button" class="btn primary" data-act="action-cast-confirm" data-spell-id="'+esc(entry.id)+'" data-grant-id="'+esc(entry.grant_id||'')+'" data-casting-class="'+esc(entry.casting_class||'')+'">Lancia</button>':'')+
      '<button type="button" class="btn" data-act="action-cast-cancel">Chiudi</button></div>';
    app.appendChild(dialog);dialog.addEventListener('close',()=>dialog.remove(),{once:true});
    if(typeof dialog.showModal==='function')dialog.showModal();else dialog.setAttribute('open','');
    return;
  }
  if(act==='action-cast-cancel'){
    const dialog=app.querySelector('#action-cast-dialog');
    if(dialog){if(typeof dialog.close==='function')dialog.close();else dialog.remove();}
    return;
  }
  if(act==='action-cast-confirm'){
    const record=state.editor?.read();if(!record)throw Error('Scheda non disponibile.');
    const calculated=await computeLocalData(record);
    const selection=sessionSpellEntries(record,calculated,state.spellCatalog||[])
      .find(row=>row.id===target.dataset.spellId&&String(row.grant_id||'')===String(target.dataset.grantId||'')&&
         String(row.casting_class||'')===String(target.dataset.castingClass||''));
    if(!selection)throw Error('Incantesimo non più disponibile.');
    const choice=app.querySelector('#action-cast-choice')?.value||'';
    const [payment,levelText]=choice.split(':');const level=Number(levelText);
    if(!['auto','slot','pact'].includes(payment)||!Number.isInteger(level)||level<0||level>9)
      throw Error('Risorsa di lancio non valida.');
    if(record.linked_token_sync_id&&state.paired&&state.online){
      app.querySelector('#action-cast-dialog')?.close();
      await startTargetedCast(record.id,structuredClone(selection),level,payment);return;
    }
    const plan=spellCastPlan(record,selection,level,calculated,payment);
    app.querySelector('#action-cast-dialog')?.close();
    if(Object.keys(plan.patch).length)await patch(plan.patch);
    await render();
    message('Lancio registrato nella scheda locale. Gli effetti sulla mappa richiedono una partita collegata.');
    return;
  }
  if(act==='combat-action'){
    const mode=target.dataset.mode;
    if(!['help','shove','prone','grapple'].includes(mode))throw Error('Azione non valida.');
    const record=state.editor?.read();
    if(!record?.id)throw Error('Seleziona prima una creatura.');
    const tokenId=record.linked_token_sync_id;
    if(!tokenId)throw Error('Piazza o associa la creatura a un token prima di scegliere il bersaglio.');
    const calculated=await computeLocalData(record);
    const kind=mode==='grapple'?'La presa':mode==='prone'?'Buttare prono':'Spingere';
    const rule=record.rules_version==='2024'?
      '2024 · '+kind+': TS Forza o Destrezza a scelta del bersaglio, CD '+
       (8+Number(calculated.abilities?.str?.modifier??0)+Number(calculated.stats?.proficiency??0))+
       '. Sostituisce un attacco con un colpo senz’armi'+(mode==='grapple'?' e richiede una mano libera.':'.'):
      '2014 · '+kind+': Atletica '+(Number(calculated.skills?.athletics??0)>=0?'+':'')+
       Number(calculated.skills?.athletics??0)+' contro Atletica o Acrobazia (a scelta del bersaglio). Sostituisce un attacco'+
       (mode==='grapple'?' e richiede una mano libera.':'.');
    if(!tacticalViewer)tacticalViewer=new TacticalViewer({send:action,ownerId,notify:message});
    await tacticalViewer.open(tokenId,{});
    tacticalViewer.setBasicAction({mode,rule});
    return;
  }
  if(act==='edit-score'){
    const ability=target.dataset.abilityKey;
    if(!Object.hasOwn(abilities,ability))throw Error('Caratteristica non valida');
    const creature=state.editor?.read();if(!creature)throw Error('Apri prima una creatura');
    document.querySelector('#sheet-score-dialog')?.remove();
    const dialog=document.createElement('dialog');dialog.className='sheet-roll-dialog sheet-score-dialog';
    dialog.id='sheet-score-dialog';dialog.dataset.abilityKey=ability;
    dialog.innerHTML='<h2>Punteggio base · '+esc(abilities[ability])+'</h2>'+
      '<p class="hint">Modifica il punteggio della caratteristica. I bonus dalle origini rimangono separati.</p>'+
      '<label>Valore base<input id="sheet-score-input" type="number" min="1" max="30" step="1" value="'+
      esc(creature.abilities?.[ability]??10)+'" aria-label="Punteggio base '+esc(abilities[ability])+'"></label>'+
      '<div class="actions">'+btn('save-score','Salva','primary')+btn('close-score','Annulla')+'</div>';
    document.body.append(dialog);dialog.addEventListener('close',()=>dialog.remove(),{once:true});
    if(dialog.showModal)dialog.showModal();else dialog.setAttribute('open','');
    dialog.querySelector('input')?.focus();return;
  }
  if(act==='save-score'){
    const dialog=document.querySelector('#sheet-score-dialog'),ability=dialog?.dataset.abilityKey;
    if(!ability||!Object.hasOwn(abilities,ability))throw Error('Caratteristica non valida');
    const input=dialog.querySelector('#sheet-score-input');
    const score=Number(input?.value);
    if(!input?.value||!Number.isInteger(score)||score<1||score>30)throw Error('Punteggio da 1 a 30');
    const creature=state.editor.read();
    await patch({abilities:{...creature.abilities,[ability]:score}});
    dialog.close?.();dialog.remove();return;
  }
  if(act==='close-score'){
    const dialog=document.querySelector('#sheet-score-dialog');
    dialog?.close?.();dialog?.remove();return;
  }
  if(act==='sheet-roll'){
    const creature=state.editor?.read();if(!creature)throw Error('Apri prima una creatura');
    const key=String(target.dataset.target||'');
    const calculated=await computeLocalData(creature),modifier=calculated.values[key];
    if(!Number.isFinite(modifier))throw Error('Valore del tiro non disponibile');
    const label=target.dataset.label||'Tiro',author=selectedName();
    const bonuses=applicableDiceBonuses(creature,key,state.spellCatalog||[]);
    document.querySelector('#sheet-roll-dialog')?.remove();
    const dialog=document.createElement('dialog');dialog.className='sheet-roll-dialog sheet-roll-preview';
    dialog.id='sheet-roll-dialog';dialog.dataset.rollTarget=key;
    dialog.dataset.rollLabel=label;dialog.dataset.creatureId=creature.id||'';
    dialog.innerHTML='<h2>'+esc(author)+' · '+esc(label)+'</h2>'+
      '<div class="sheet-roll-math"><span>Modificatore totale</span><strong>'+esc((modifier>=0?'+':'')+modifier)+'</strong></div>'+
      '<div class="sheet-roll-math"><span>Formula del tiro</span><strong data-roll-formula>'+
      esc(sheetRollFormula(modifier))+'</strong></div>'+
      '<p class="sheet-roll-components"><strong>Calcolo del modificatore:</strong> '+
      esc(sheetModifierBreakdown(calculated,key))+'</p>'+
      '<p class="hint sheet-roll-provenance"><strong>Origini e bonus applicati:</strong> '+
      esc(calculated.explanations?.[key]||'Valore calcolato dalla scheda e dalle origini attive')+'</p>'+
      (bonuses.length?'<fieldset class="sheet-roll-bonus-list"><legend>Dadi bonus disponibili</legend>'+
       '<p class="hint">Seleziona i dadi aggiuntivi prima di tirare. I bonus monouso scelti verranno consumati.</p>'+
       bonuses.map((row,index)=>'<label class="check"><input type="checkbox" data-roll-bonus="'+index+'">'+
         esc(row.origin_name||'Bonus')+' · '+esc(row.dice)+'</label>').join('')+'</fieldset>':'')+
      '<div class="sheet-roll-result" data-roll-result hidden aria-live="polite"></div>'+
      '<p class="hint" data-roll-chat-status>'+(state.paired&&state.online?
       'Il risultato verrà inviato automaticamente alla chat della partita.':'Tiro locale: nessuna partita collegata.')+'</p>'+
      '<div class="actions sheet-roll-actions">'+btn('roll-sheet-confirm','Tira 1d20','primary')+
      '<button type="button" class="btn" data-act="sheet-roll-edit-bonus" data-target="'+esc(key)+'">Origini e bonus ±</button>'+
      btn('close-sheet-roll','Chiudi')+'</div>';
    dialog.addEventListener('change',event=>{
      if(!event.target.matches('[data-roll-bonus]'))return;
      const selected=[...dialog.querySelectorAll('[data-roll-bonus]:checked')].map(input=>bonuses[Number(input.dataset.rollBonus)]).filter(Boolean);
      const formula=dialog.querySelector('[data-roll-formula]');
      if(formula)formula.textContent=sheetRollFormula(modifier,selected);
    });
    document.body.append(dialog);dialog.addEventListener('close',()=>dialog.remove(),{once:true});
    if(dialog.showModal)dialog.showModal();else dialog.setAttribute('open','');
    return;
  }
  if(act==='roll-sheet-confirm'){
    const dialog=document.querySelector('#sheet-roll-dialog');
    if(!dialog||dialog.dataset.rolled==='true')return;
    const creature=state.editor?.read();
    if(!creature||creature.id!==dialog.dataset.creatureId)throw Error('La creatura del tiro è cambiata');
    const key=dialog.dataset.rollTarget,label=dialog.dataset.rollLabel;
    const calculated=await computeLocalData(creature),modifier=calculated.values[key];
    const bonuses=applicableDiceBonuses(creature,key,state.spellCatalog||[]);
    const chosen=[...dialog.querySelectorAll('[data-roll-bonus]:checked')].map(input=>
       bonuses[Number(input.dataset.rollBonus)]).filter(Boolean);
    const outcome=rollSheetDice(modifier,chosen,randomDie);
    dialog.dataset.rolled='true';
    state.roll={...outcome,label,author:selectedName()};
    state.rollHistory.unshift({...state.roll});
    const result=dialog.querySelector('[data-roll-result]');
    result.hidden=false;
    result.innerHTML='<div class="dice-result">'+esc(outcome.total)+'</div>'+
      '<p><strong>Formula:</strong> '+esc(outcome.notation)+'</p>'+
      '<ol class="sheet-roll-breakdown">'+outcome.parts.map(part=>
       '<li><strong>'+esc(part.name)+'</strong> · '+esc(part.notation)+
       ' → ['+esc(part.rolls.join(', '))+']'+(part.flat?' '+esc((part.flat>0?'+ ':'− ')+Math.abs(part.flat)):'')+
       ' = '+esc(part.subtotal)+'</li>').join('')+'</ol>'+
      '<p class="sheet-roll-total">Modificatore '+esc((modifier>=0?'+':'')+modifier)+
      ' · risultato finale <strong>'+esc(outcome.total)+'</strong></p>';
    const rollButton=dialog.querySelector('[data-act="roll-sheet-confirm"]');
    if(rollButton)rollButton.hidden=true;
    for(const input of dialog.querySelectorAll('[data-roll-bonus]'))input.disabled=true;
    const consumed=new Set(chosen.filter(row=>row.consumes_spell).map(row=>row.consumes_spell));
    if(consumed.size){
      try{
        const live=state.editor.read(),contexts={...live.active_spell_context},enabled={...live.origin_enabled};
        for(const id of consumed){delete contexts[id];delete enabled['spell:'+id];}
        await patch({proficiency_origins:(live.proficiency_origins||[]).filter(o=>
           !consumed.has(String(o.id).slice(6))||o.group!=='spell'),
           active_spell_context:contexts,origin_enabled:enabled});
      }catch(error){message('Tiro registrato; consumo bonus non salvato: '+errorMessage(error),true);}
    }
    const chatStatus=dialog.querySelector('[data-roll-chat-status]');
    if(state.paired&&state.online){
      try{
        await shareRoll({quiet:true});
        if(chatStatus)chatStatus.textContent='Risultato inviato automaticamente alla chat della partita.';
      }catch(error){
        if(chatStatus)chatStatus.textContent='Tiro effettuato, ma invio chat non riuscito: '+errorMessage(error);
        message('Invio chat non riuscito: '+errorMessage(error),true);
      }
    }
    return;
  }
  if(act==='close-sheet-roll'){document.querySelector('#sheet-roll-dialog')?.remove();return;}
  if(act==='origin-choice-pick'){
    const c=state.editor.read(),calculated=await computeLocalData(c),choice=calculated.origin_choices.find(row=>row.id===target.dataset.choiceId);
    if(!choice)throw Error('Scelta non disponibile');
    const picker=[...app.querySelectorAll('[data-origin-choice]')].find(el=>el.dataset.originChoice===choice.id);
    const ability=[...app.querySelectorAll('[data-choice-ability]')].find(el=>el.dataset.choiceAbility===choice.id)?.value||'';
    const spell=state.spellCatalog?.find(row=>row.id===picker?.value);if(!spell)throw Error('Scegli un incantesimo');
    await patch(applyOriginSpellChoice(c,choice,spell,{ability}));await render();return;
  }
  if(act==='origin-choice-remove'){
    const c=state.editor.read();
    const rows=(c.origin_spell_grants||[]).filter(g=>g.id!==target.dataset.grantId);
    await patch({origin_spell_grants:rows});await render();return;
  }
  if(act==='origin-spend'){
    const c=state.editor.read(),calculated=await computeLocalData(c),grant=calculated.origin_spells.find(row=>row.id===target.dataset.grantId);
    if(!grant)throw Error('Concessione non disponibile');
    if(grant.payment_mode==='slot'){
      const picker=[...app.querySelectorAll('[data-origin-slot]')].find(el=>el.dataset.originSlot===grant.id);if(!picker||picker.value==='')throw Error('Nessuno slot disponibile');
      await patch(slotUsePatch(c,Number(picker.value),1,calculated));
    }else{
      const tracker=calculated.trackers.find(t=>t.id===grant.tracker_id),cost=Math.max(1,Number(grant.tracker_cost)||1);
      if(!tracker||tracker.max-tracker.spent<cost)throw Error('Utilizzi esauriti');
      await patch({resource_tracker_spent:{...c.resource_tracker_spent,[tracker.id]:tracker.spent+cost}});
    }
    await render();return;
  }
  if(act==='stop-concentration'){
    const c=state.editor.read();await patch({conditions:(c.conditions||[]).filter(id=>id!=='concentrating'),concentrating_spell_id:''});await render();return;
  }
  if(['slot-use','slot-recover','slots-restore','slots-automatic'].includes(act)){
    const c=state.editor.read();
    if(act==='slots-automatic')await patch({spell_slots_manual:false,spell_slots_automatic:true});
    else if(act==='slots-restore')await patch({spell_slots_spent:Array(10).fill(0),pact_slots_spent:0});
    else await patch(slotUsePatch(c,Number(target.dataset.level),act==='slot-use'?1:-1,await computeLocalData(c)));
    await render();return;
  }
  if(['hp-damage','hp-heal','hp-restore','hp-automatic'].includes(act)){
    const c=state.editor.read(),calculated=await computeLocalData(c);
    if(act==='hp-automatic'){
      if(!calculated.stats.automatic_hp.available)throw Error('PF automatici non disponibili');
      await patch({max_hp_base:calculated.stats.automatic_hp.value});
    }else if(act==='hp-restore')await patch({current_hp:Math.max(0,calculated.stats.max_hp)});
    else{
      const amount=Number(app.querySelector('#hp-amount')?.value);
      if(!Number.isInteger(amount)||amount<0||amount>99999)throw Error('Quantità PF non valida');
      await patch(hitPointPatch(c,amount*(act==='hp-damage'?-1:1),calculated));
    }
    await render();return;
  }
  if(act==="sheet-details"){
    if(!DETAILS.some(([key])=>key===target.dataset.detail))return;
    state.sheet="origins";state.detail=target.dataset.detail;await render();return;
  }
  if(act==='edit-bonus'||act==='sheet-roll-edit-bonus'){
    if(act==='sheet-roll-edit-bonus'){
      const dialog=document.querySelector('#sheet-roll-dialog');
      dialog?.close?.();dialog?.remove();
    }
    const c=state.editor.read(),targetKey=target.dataset.target;
    const rows=rowsFor(c,'formula_bonuses');
    if(!rows.some(row=>row.target===targetKey&&!row.automatic)){
      rows.push({id:'bonus_'+crypto.randomUUID(),target:targetKey,expression:'0',origin_id:'',origin_name:'',disabled:false,automatic:false});
      await patch({formula_bonuses:rows});
    }
    state.sheet='origins';state.detail='formula_bonuses';await render();
    const index=rows.findIndex(row=>row.target===targetKey&&!row.automatic);
    app.querySelector('[data-native-list="formula_bonuses"][data-index="'+index+'"][data-key="expression"]')?.focus();
    return;
  }
  if(act==="native-add"||act==="native-remove"){
    const key=target.dataset.list;if(!ROW_FIELDS[key])throw Error("Elenco non valido");
    const c=state.editor.read(),rows=rowsFor(c,key);
    if(act==="native-remove"){
      const index=Number(target.dataset.index);
      if(!rows[index]||rows[index].automatic)throw Error("Voce non rimovibile");
      rows.splice(index,1);
    }else{
      const defaults={classes:{name:"",source:"",level:1},
        proficiency_choices:{kind:"skill",key:"",origin_id:"",origin_name:"",disabled:false},
        feats_catalog:{name:"Nuovo talento",source:"",disabled:false},
        formula_bonuses:{id:"bonus_"+crypto.randomUUID(),target:"initiative",expression:"0",origin_id:"",origin_name:"",disabled:false,automatic:false},
        dice_bonuses:{id:'dice_'+crypto.randomUUID(),target:'ability_check',dice:'1d4',origin_id:'',origin_name:'',disabled:false},
        damage_defense_entries:{key:"fire",rank:1,origin_id:"",automatic:false},
        origin_spell_grants:{id:'grant_'+crypto.randomUUID(),origin_id:state.calculated.origins[0]?.id||'pwa_manual',origin_name:state.calculated.origins[0]?.name||'Personalizzato',spell_id:'',payment_mode:'free',tracker_id:'',tracker_cost:1,disabled:false}};
      rows.push(defaults[key]);
    }
    const changes=collectionPatch(c,key,rows);
    if(key==='origin_spell_grants'&&!state.calculated.origins.length)changes.proficiency_origins=[...(c.proficiency_origins||[]),{id:'pwa_manual',name:'Personalizzato',group:'custom',disabled:false}];
    await patch(changes);await render();return;
  }
  if(act==='quick-create'){
    const name=text(app.querySelector('#quick-name')?.value);
    const description=app.querySelector('#quick-description')?.value||'';
    const grants=[...app.querySelectorAll('[data-quick-kind]')].map(select=>{
      const key=app.querySelector('[data-quick-key="'+select.dataset.quickKind+'"]')?.value?.trim()||'';
      return {kind:select.value,key};
    }).filter(row=>row.kind&&row.key);
    const details=state.catalogCategory==='items'?{
      custom_item_type:app.querySelector('#quick-type')?.value,
      rarity:app.querySelector('#quick-rarity')?.value,
      value:Number(app.querySelector('#quick-value')?.value)
    }:{};
    const created=await createQuickHomebrew(state.catalogCategory,name,description,grants,details);
    state.catalogSelected=-1;state.catalogQuery=created.name;
    await render();message('Contenuto personalizzato salvato in locale.');return;
  }
  if(act==='quick-delete'){
    if(!window.confirm('Eliminare questo contenuto personalizzato?'))return;
    await deleteQuickHomebrew(target.dataset.id);
    state.catalogSelected=-1;state.catalogQuery='';await render();message('Contenuto eliminato.');return;
  }
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
      await editor.update(addSelectedSpell(sheet,entry,"prepared_spells"));
    }else if(["weapons","armor","tools","mundane_items","magic_items","items"].includes(category)){
      const item=createOwnedItem(entry,"pwa_"+crypto.randomUUID());
      await editor.update({inventory:[...(sheet.inventory||[]),item]});
    }else if(category==="feats"){
      const feat={id:entry.id||"",name:entry.name,source:entry.source||""};
      const current=Array.isArray(sheet.feats_catalog)?sheet.feats_catalog:[];
      if(current.some(row=>row.id===feat.id&&row.name===feat.name&&row.source===feat.source))
        throw new Error("Talento già presente in questa scheda.");
      await editor.update({feats_catalog:[...current,feat],...quickGrantPatch(sheet,entry)});
    }else if(category==="backgrounds"){
      await editor.update({background:entry.name,background_id:entry.id||"",background_source:entry.source||"",...quickGrantPatch(sheet,entry)});
    }else if(category==="races"){
      await editor.update({species:entry.name,species_source:entry.source||""});
    }else throw new Error("Categoria non assegnabile alla scheda.");
    state.cachedCreatures=(await listCreatures()).map(row=>row.creature);
    message("Contenuto aggiunto; i benefici strutturati sono calcolati localmente.");
    return;
  }
  if(act==="refresh"){await render();return;}
  if(act==="demo"){
    state.creatureId=await createDemoCreature();state.editor=null;state.sheet="info";
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
    state.creatureId=row.id;state.editor=null;state.sheet="info";await render();return;
  }
  if(act==="import"){creatureInput.click();return;}
  if(act==="restore-backup"){backupInput.click();return;}
  if(act==="backup"){
    const blob=await exportBackup();download(blob,"vtt-pwa-backup-"+new Date().toISOString().slice(0,10)+".json");
    message("Backup esportato. Conservalo fuori dal browser.");
    return;
  }
  if(act==="open"){state.creatureId=target.dataset.id;state.sheet="info";state.editor=null;await render();return;}
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
    if(!name||name.length>120||!Number.isInteger(maximum)||maximum<0||maximum>99999)
      throw new Error("Specifica nome e massimo valido della risorsa.");
    const record=state.editor.read();
    const trackers=structuredClone(record.resource_trackers||[]);
    trackers.push({id:"pwa_tracker_"+crypto.randomUUID(),name,max:maximum,
      max_formula:text(document.querySelector('#tracker-formula')?.value),origin_id:document.querySelector('#tracker-origin')?.value||'',origin_name:state.calculated.origins.find(o=>o.id===document.querySelector('#tracker-origin')?.value)?.name||'',recharge});
    await patch({resource_trackers:trackers});await render();return;
  }
  if(["tracker-more","tracker-less","tracker-delete","tracker-recharge"].includes(act)){
    const record=state.editor.read(),trackers=structuredClone(record.resource_trackers||[]);
    const calculated=await computeLocalData(record);
    const row=calculated.trackers.find(t=>t.id===target.dataset.trackerId)||(act==='tracker-delete'?trackers.find(t=>t.id===target.dataset.trackerId):null),index=trackers.findIndex(t=>t.id===row?.id);
    if(!row)throw new Error("Tracker non disponibile.");
    if(act==="tracker-delete"){
      if(index<0||row.automatic)throw Error('Modifica questa risorsa dalla sua origine');
      trackers.splice(index,1);
      const spent={...(record.resource_tracker_spent||{})};delete spent[row.id];
      await patch({resource_trackers:trackers,resource_tracker_spent:spent});
    }else{
      if(act==='tracker-recharge'){
        if(row.recharge!=='d6')throw Error('Questa risorsa non usa la ricarica d6');
        const die=randomDie(6),success=die>=Number(row.recharge_min||6),spent={...(record.resource_tracker_spent||{})};
        if(success){delete spent[row.id];await patch({resource_tracker_spent:spent});}
        await render();message(row.name+': d6 = '+die+' · '+(success?'Ricaricata':'Non ricaricata'));return;
      }
      // Reuse the domain operation; no stale zero-valued spent counters.
      await patch(changeTrackerUses(record,row.id,act==="tracker-more"?1:-1,calculated.trackers));
    }
    await render();return;
  }
  if(act==='tracker-optional-recovery'){
    const record=state.editor.read(),calculated=await computeLocalData(record);
    const change=optionalRecoveryPatch(record,target.dataset.ruleId,calculated.trackers);
    if(!change)throw Error('Questo recupero è già stato usato o non è disponibile dopo un riposo breve.');
    await patch(change);await render();return;
  }
  if(["tracker-short","tracker-long","tracker-turn"].includes(act)){
    const record=state.editor.read(),calculated=await computeLocalData(record);
    await patch(recoveryPatch(record,act==='tracker-long'?'long_rest':act==='tracker-turn'?'turn':'short_rest',calculated.trackers));await render();return;
  }
  if(['infusion-learn','infusion-apply','infusion-forget','infusion-clear'].includes(act)){
    const creature=state.editor.read(),calculated=await computeLocalData(creature);
    const definitions=calculated.infusion_catalog,mechanics=calculated.infusion_mechanics;
    const index=Number(app.querySelector('#infusion-item')?.value);
    const known=learnedInfusions(creature,definitions);
    const option=definitions.find(row=>row.id===app.querySelector('#infusion-available')?.value);
    const learned=known[Number(app.querySelector('#infusion-known')?.value)];
    let changes;
    if(act==='infusion-learn')changes=learnInfusionPatch(creature,option,definitions,mechanics,index);
    else if(act==='infusion-apply')changes=applyInfusionPatch(creature,learned,definitions,mechanics,index);
    else if(act==='infusion-forget')changes=forgetInfusionPatch(creature,learned);
    else changes=clearInfusionPatch(creature,index);
    await patch(changes);await render();return;
  }
  if(act==="item-catalog"){state.catalogCategory="items";state.catalogSelected=-1;state.catalogQuery="";await navigate("catalog");return;}
  if(act==="document-add"){
    if(!state.editor)throw Error("Apri una creatura prima di creare un documento.");
    const localId="doc_"+crypto.randomUUID().replace(/-/g,"");
    const definition=createDocumentDefinition(localId);
    await saveHomebrewDefinition(definition);
    const owned=createOwnedDocument(definition,"owned_doc_"+crypto.randomUUID().replace(/-/g,""));
    state.openDocumentInstance=owned.instance_id;
    const record=state.editor.read();
    await patch({inventory:[...(record.inventory||[]),owned]});
    await render();return;
  }
  if(act==="document-remove"){
    const index=Number(target.dataset.index),record=state.editor.read();
    const inventory=structuredClone(record.inventory||[]);
    if(!isDocument(inventory[index]))throw Error("Documento non valido.");
    inventory.splice(index,1);state.openDocumentInstance="";
    await patch({inventory});await render();return;
  }
  if(act==="add-item"){
    const c=state.editor.read();
    const inventory=Array.isArray(c.inventory)?[...c.inventory]:[];
    inventory.push({id:"local_"+crypto.randomUUID(),name:"Nuovo oggetto",quantity:1,description:"",
      source:"",custom_item_type:"other",equipped:false,equipped_slots:[],attuned:false,active:true});
    await patch({inventory});await render();return;
  }
  if(act==="remove-item"){
    const c=state.editor.read(),inventory=structuredClone(c.inventory||[]);
    inventory.splice(Number(target.dataset.index),1);
    await patch({inventory});await render();return;
  }
  if(act==="spell-pick"){
    const index=Number(target.dataset.index);
    const spell=state.spellCatalog?.[index];
    if(!spell)throw Error("Seleziona un incantesimo valido.");
    const classes=state.calculated?.casting_classes||[],member=classes.find(row=>row.id===state.spellClass);
    await patch(addSelectedSpell(state.editor.read(),spell,state.spellTarget,{member,classes,catalog:state.spellCatalog||[]}));
    await render();return;
  }
  if(act==="remove-spell"){
    const key=target.dataset.key,index=Number(target.dataset.index);
    await patch(removeSelectedSpell(state.editor.read(),key,index,{classId:target.dataset.classId==='manual'?null:target.dataset.classId,classes:state.calculated?.casting_classes||[],catalog:state.spellCatalog||[]}));await render();return;
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
    await unpair();stopSubscriptions();state.paired=false;state.session=null;state.map=null;
    state.messages=[];state.after="";state.tokenId="";currentGameSession="";
    await render();return;
  }
  if(act==="place-creature"||act==="claim-creature"){
    const selectedId=document.querySelector("#place-creature")?.value;
    const referenceId=String(document.querySelector("#place-reference")?.value||state.tokenId);
    const selectedToken=state.map?.tokens?.find(t=>t.id===referenceId);
    if(!selectedToken||!selectedId)throw new Error("Scegli un token di riferimento e una creatura locale.");
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
      rules_version:sheet.rules_version==="2024"?"2024":"2014",
      reach_feet:sheet.reach_feet??5,conditions:sheet.conditions||[],
      rules_version:sheet.rules_version||"2014",
      visual_front_quarter_turns:sheet.visual_front_quarter_turns??0};
    const direction=String(document.querySelector("#place-direction")?.value||"");
    if(act==="place-creature"&&!["north","east","south","west"].includes(direction))
      throw new Error("Seleziona una direzione cardinale.");
    const result=await action(act==="claim-creature"?"claim_free_token":"place_token",
      {token_id:referenceId,creature:visible,...(act==="place-creature"?{direction}:{})});
    if(!result.ok)throw new Error(result.error||"Impossibile piazzare la creatura.");
    const editor=await openCreatureEditor(selectedId);
    await editor.update({linked_token_sync_id:result.token_id,linked_token_name:result.name||sheet.name});
    state.cachedCreatures=(await listCreatures()).map(row=>row.creature);
    tokenStatusFingerprint="";
    message("Token aggiornato: "+(result.name||sheet.name));
    closeSessionDialog(app.querySelector("#session-place-dialog"));
    state.tokenId=result.token_id;
    await refreshMapOnce();return;
  }
  if(act==="snapshot-map"||act==="attack-map"){
    const isAttack=act==="attack-map";
    const attack=isAttack?{range_feet:state.attackRange,
      long_range_feet:state.attackLongRange,melee:state.attackMelee}:{};
    if(!tacticalViewer)tacticalViewer=new TacticalViewer({
      send:action,ownerId,notify:message
    });
    await tacticalViewer.open(state.tokenId,attack);
    return;
  }
  if(act==="cast-sheet-spell"||act==="cast-origin-spell"){
    const c=state.editor?.read();if(!c)throw Error("Apri una scheda prima del lancio.");
    const calculated=await computeLocalData(c);
    const selections=sessionSpellEntries(c,calculated,state.spellCatalog||[]);
    const spell=act==="cast-origin-spell"?
      selections.find(row=>row.grant_id===target.dataset.grantId):
      selections.find(row=>row.id===target.dataset.spellId&&
        (!target.dataset.castingClass||target.dataset.castingClass==='manual'||
         row.casting_class===target.dataset.castingClass));
    if(!spell)throw Error("Incantesimo non disponibile nella scheda.");
    const level=Number(app.querySelector('#sheet-cast-level')?.value??state.castLevel);
    if(!Number.isInteger(level)||level<0||level>9)throw Error("Livello di slot non valido.");
    state.castLevel=level;
    await startTargetedCast(c.id,structuredClone(spell),level,
      app.querySelector('#sheet-cast-payment')?.value||'auto');
    return;
  }
  if(act==="begin-spell"){
    const casterId=document.querySelector("#cast-creature")?.value;
    const spell=state.visibleSpells?.[Number(document.querySelector("#cast-spell")?.value)];
    if(!spell)throw new Error("Scegli un incantesimo della creatura.");
    await startTargetedCast(casterId,structuredClone(spell),state.castLevel,
      document.querySelector('#cast-payment')?.value||'auto',state.tokenId);
    return;
  }
  if(act==="select-token"){
    state.tokenId=target.dataset.id;
    await render();
    app.querySelector(".session-map-panel")?.scrollIntoView?.({behavior:"smooth",block:"start"});
    return;
  }
  if(act==="move"||act==="move-up"||act==="move-down"){
    const direction=act==="move-up"?"up":act==="move-down"?"down":target.dataset.direction;
    if(!state.tokenId)throw new Error("Seleziona un token.");
    const result=await action("move_token",{token_id:state.tokenId,direction});
    if(!result.ok)throw new Error(result.error||"Movimento rifiutato");
    if(!result.moved)message("Movimento non disponibile sulla scena.");
    else await refreshMapOnce();
    return;
  }
  if(act==="roll"){await roll(Number(target.dataset.sides));return;}
  if(act==="share-roll"){await shareRoll();return;}
}
async function handleSubmit(form){
  if(form.id==="pair-form"){
    const token=document.querySelector("#pair-secret")?.value.trim()||"";
    const pairedSession=await pair(token,{remember:document.querySelector("#pair-remember")?.checked});
    acceptSession(pairedSession);
    realtimeStopped=false;
    state.paired=true;state.online=true;
    state.messages=[];state.after="";state.tokenId="";
    // Pairing codes are one-time. A momentary map failure must not turn a
    // successful enrollment into a visible failure or require a new QR.
    try{state.map=await map();}catch{state.map=null;}
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
  document.addEventListener("keydown",e=>{
    if(e.key === "Escape" && sectionMenu.open){sectionMenu.open=false;sectionMenu.querySelector("summary").focus();}
  });
  document.addEventListener("click",e=>{
    if(!sectionMenu.contains(e.target))sectionMenu.open=false;
  });
  document.addEventListener("click", async e=>{
    const button=e.target.closest("button[data-nav],button[data-act]");
    if(!button)return;
    if(button.disabled)return;
    button.disabled=true;
    try {
      await flushPendingFields();
      sectionMenu.open=false;
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
  const editable = "[data-requirement],[data-origin-config],[data-tracker-field],[data-origin-enabled],[data-auto-bonus],[data-native-pick],[data-casting-section],[data-slot-total],[data-pact-total],[data-document-index],[data-equip-slot],[data-reference],[data-native-list],[data-native-cr],[data-field],[data-ability],[data-slot],[data-item-index],[data-item-override],[data-condition],[data-token-condition]";
  app.addEventListener("input",e=>{
    const target=e.target;
    if(target?.id==="token-spell-query"){fillSessionSpells(target.value);return;}
    if(target?.id==="token-mini-query"){fillSessionMiniatures(target.value);return;}
    if(target?.id==="spell-search"){
      state.spellQuery=target.value;
      const matches=document.querySelector("#spell-results");
      if(matches)matches.innerHTML=renderSpellResults();
      return;
    }
    if(target?.id==="catalog-search"){
      state.catalogQuery=target.value;
      const results=document.querySelector("#catalog-results");
      if(results)results.innerHTML=renderCatalogRows();
      return;
    }
    if(!target?.matches("[data-document-index],[data-field],[data-native-list],[data-native-cr],[data-item-index],[data-item-override]"))return;
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
    if(target?.id==="spell-target"){
      state.spellTarget=target.value==="spellbook_spells"?"spellbook_spells":"prepared_spells";return;
    }
    if(target?.id==='spell-class'){
      state.spellClass=target.value;
      const matches=app.querySelector('#spell-results');if(matches)matches.innerHTML=renderSpellResults();return;
    }
    if(target?.id==="native-details"){
      if(!DETAILS.some(([key])=>key===target.value))return;
      flushPendingFields().then(()=>{state.detail=target.value;return render();})
        .catch(error=>message(errorMessage(error),true));return;
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
    if(target?.id==="sheet-cast-level"){
      const level=Number(target.value);
      if(Number.isInteger(level)&&level>=0&&level<=9)state.castLevel=level;
      return;
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
      state.editor=null;state.sheet="info";
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
      if(active?.matches?.("[data-document-index],[data-field],[data-native-list],[data-native-cr],[data-item-index]"))
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
export function stopRealtime() { realtimeStopped=true;stopSubscriptions(); }

export async function mount(){
  realtimeStopped=false;
  listen();
  const dbOk=await import("./storage.js").then(m=>m.openStorage()).then(db=>{db.close();return true;});
  if(!dbOk)throw new Error("Archivio locale non disponibile.");
  const qrCode = takeQrPairCode();
  await refreshConnection(true);
  if(qrCode){
    try {
      acceptSession(await pair(qrCode,{remember:true}));
      state.paired=true;state.online=true;state.page="session";
      state.messages=[];state.after="";state.tokenId="";
      message("Telefono associato tramite QR.");
    }catch(error){
      state.page="session";state.qrCode=qrCode;
      message("QR non valido o scaduto: "+errorMessage(error),true);
    }
  }
  state.cachedCreatures=(await listCreatures()).map(row=>row.creature);
  await render();
  if(state.qrCode && state.page==="session"){
    const input=document.querySelector("#pair-secret");
    if(input)input.value=state.qrCode;
    state.qrCode="";
  }
}
