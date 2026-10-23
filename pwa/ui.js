import { battleActionPanels, actionGlyph, actionVariants, loadFeatureActionOverrides, loadGeneralActionSupplements, nativeClassFeatureActions } from "./action_economy.js";
import { SHEET_SECTIONS, DETAILS, ROW_FIELDS, BONUS_TARGETS, nativeSection, nativeRowPatch, rowsFor, collectionPatch, identityPatch, referencePatch, rowReferencePatch, hitPointPatch, slotUsePatch, recoveryPatch, completeRest, restRecoveryPreview, miniaturePatch } from "./native_sheet.js";
import { itemKind, requiresAttunement, isCatalogItem, createOwnedItem, changeOwnedItem, changeItemOverride, changeEquippedWeaponSize, resolveOwnedItem, isSpellScroll, spellScrollName, spellScrollLevel, addSpellScroll, WEAPON_SIZES, infusionLimits, infusionGrantingTrait, learnedInfusions, isInfusionPrepared, prepareInfusionPatch, compatibleInfusionTargets, targetableInventoryItems, learnInfusionPatch, applyInfusionPatch, clearInfusionPatch, forgetInfusionPatch, validSlot, equipSlot, hasProperty, setItemEquipped } from "./item_controls.js";
import { sessionSpellEntries, availableSpells, addSelectedSpell, removeSelectedSpell, spellId, spellEligible, spellsForEdition, castingSources, classSelectionCount, classSelectionWarnings, originChoiceMatches, applyOriginSpellChoice } from "./spell_selection.js";
import { loadActivatedAbilities, abilitiesForCreature } from "./activated_abilities.js";
import { status, session, pair, unpair, hasPairingCredential, map, action, subscribeMap, takeQrPairCode, conditionDefinitions } from "./client.js";
import { conditionOptions, conditionLabel, CONDITION_CATEGORIES, conditionCatalogFrom5etools, mergeConditionCatalog } from "./condition_catalog.js";
import { notificationsSupported, notificationsEnabled, toggleChatNotifications, notifyIncomingChat } from "./chat_notifications.js";
import { listCreatures, loadCreature, createCreature, importCreatureFile, exportCreature, exportCreatureBatch,
  removeCreature, openCreatureEditor, ownerId, syncLinkedTokenStatuses } from "./creatures.js";
import { TacticalViewer } from "./tactical_view.js";
import { tokenGroups, snapshotRevision, snapshotBlob, casterToken, SessionMapViewer } from "./session_map.js";
import { createDemoCreature } from "./demo.js";
import { CATALOG_CATEGORIES, catalogEntries, detailedEntry, flattenDescription, createQuickHomebrew, quickGrantPatch, deleteQuickHomebrew } from "./catalog_data.js";
import { collectTraitRows, groupTraitRows, withGrantedSpellPreviews } from "./trait_projection.js";
import { traitBenefitGroups, traitBenefitSources } from "./trait_benefits.js";
import {BENEFIT_TYPES,PROFICIENCY_KINDS,DEFENSE_RANKS,DAMAGE_TYPES,traitRemovedIds,removeBenefitPatch,restoreBenefitPatch,addBenefitPatch,traitActivationPatch,traitIsActive} from "./trait_benefit_editor.js";
import { spellFacts } from "./spell_metadata.js";
import { exportBackup, importBackup, getRecord } from "./storage.js";
import { saveHomebrewDefinition, editHomebrewDefinition } from "./creatures.js";
import { isDocument, createDocumentDefinition, createOwnedDocument, editDocumentDefinition, documentInfo, documentStyle } from "./documents.js";
import { calculateSheet, loadRuleCatalogs, localClasses, validBonusDice, applicableDiceBonuses, SKILLS } from "./sheet_rules.js";
import {benefitRequirements,requirementPatch,formulaPreview,spellCastPlan} from './native_sheet.js';
import { calculationNote, refreshCalculatedValues, mountPlaySheet, refreshPlayReadouts, inventoryReadout, formulaReadout, rollSheetDice, rollBattleDamage, sheetRollChatFields, isPersistentSpell } from "./sheet_rules_view.js";
import {sheetRollOriginSegments,sheetScoreOriginSegments,sheetRollOriginHtml,sheetRollSymbol,damageRollSegments,rollDamageName,rollOptionalDice,attackGrantOrigin} from "./sheet_roll_origin.js";
import {traitStateActivationPatch} from './trait_state_rules.js';
import {optionalRecoveryPatch,classFeatureActivationPatch,classFeatureRollAdvantage,classFeatureRollSources,resolveClassRollMode,wildShapePatch,endWildShapePatch,metamagicOptions} from './feature_mechanics.js';
import {changeTrackerUses,spendTrackerUses,hitDicePools} from "./character_core.js";
import {pendingCharacterChoices,savePendingChoice} from "./pending_choices.js";

const app = document.querySelector("#app");
const nav = document.querySelector("#nav");
const connection = document.querySelector("#connection");
const creatureInput = document.querySelector("#import-creature");
const backupInput = document.querySelector("#import-backup");
const toastElement = document.querySelector("#toast");
const sheetSections = SHEET_SECTIONS;
const sections = new Set(["library", "catalog", "session"]);
const abilities = {str:"Forza",dex:"Destrezza",con:"Costituzione",int:"Intelligenza",wis:"Saggezza",cha:"Carisma"};
const state = { page:"library", libraryMode:true, creatureId:null, editor:null, sheet:"info", detail:"overview", referenceCatalogs:{}, map:null,
  tokenId:"", editTokenId:"", liveSnapshot:null, snapshotObjectUrl:"", snapshotKey:"", snapshotPending:false, online:false, paired:false, session:null, errors:[], messages:[],
  after:"", rollHistory:[], roll:null, diceSides:20, chatAuthor:"", stopMap:null, pollChat:null, renderTicket:0,
  sheetSearch:new Map(), sheetPopup:"", sheetPopupTitle:"", traitPopupKey:"", traitPopupConfirm:"", traitPopupDraftKind:"", traitPopupDraftTarget:"", traitRows:[], sheetSources:new Map(), librarySelectedIds:new Set(), sessionPane:"", disclosureState:new Map(), battleOnlyClass:true,
  hostReachable:false, conditionCatalog:null, offlineConditionCatalog:null, desktopConditionCatalog:null, catalogCategory:"items", catalogQuery:"", catalogRows:[], catalogSelected:-1, spellCatalog:null, abilityCatalog:null, spellQuery:"", spellTarget:"prepared_spells", spellClass:'manual',infusionPending:-1,spellCatalogError:"", magicPopup:"", openDocumentInstance:"",
  castCreatureId:"", castSpellIndex:0, castLevel:1,
  attackRange:30, attackLongRange:0, attackMelee:false,
  inventorySelectedIndex:0, inventoryMenuIndex:-1, inventorySubtab:'items', scrollSpellQuery:'', pendingItemOwner:'', pendingSpellChoiceId:'',
  saving:false, saveError:"", pendingActions:0, busy:false };
let tacticalViewer=null;
const sessionMapViewer=new SessionMapViewer();
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
let chatNotificationBaseline = false;
const locallySentEventIds = new Set();
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
    state.messages=[];state.after="";state.map=null;state.tokenId="";chatNotificationBaseline=false;locallySentEventIds.clear();
    releaseSessionSnapshot();++snapshotGeneration;
    previousMapFingerprint="";
    tokenStatusFingerprint="";
    state.desktopConditionCatalog=null;state.conditionCatalog=state.offlineConditionCatalog;
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
function header(eyebrow,title,subtitle){
  return '<div class="page-head">'+(eyebrow?'<p class="eyebrow">'+esc(eyebrow)+'</p>':'')+'<h1>'+esc(title)+'</h1>'+
    (subtitle?'<p class="'+(eyebrow==="Errore"?'warning':'page-description')+'">'+esc(subtitle)+'</p>':'')+'</div>';
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
const SHEET_TAB_GLYPHS={info:'information',battle:'weapon',
 magic:'spark',inventory:'inventory',conditions:'condition'};
const INFO_HEADING_ICONS={'Identità':'identity',
 'Classi e progressione':'progression','Talenti':'talents'};
const PLAY_SECTIONS=[['info','Info'],['battle','Azioni'],['magic','Magia'],['inventory','Zaino']];
const SECTION_COPY={battle:['Azioni','Risorse e azioni disponibili.'],magic:['Magia','Incantesimi e capacità pronti per il tuo turno.'],inventory:['Inventario','Equipaggiamento, oggetti e documenti.'],conditions:['Condizioni','Gestisci gli stati che influenzano il personaggio.'],info:['Info','Identità, aspetto e progressione del personaggio.'],json:['Editor avanzato','Documento completo della scheda.']};
function navigationButton(key,title){
  const current=state.page==='library'&&!state.libraryMode&&
    (state.sheet===key||(key==='info'&&['conditions','json'].includes(state.sheet)));
  return '<button type="button" class="btn dock-destination" data-act="sheet" data-sheet="'+key+
    '" aria-pressed="'+current+'" aria-label="'+esc(title)+'">'+
    actionGlyph(SHEET_TAB_GLYPHS[key]||'information')+'<span class="destination-label">'+esc(title)+'</span></button>';
}
function syncNav(){
  const hasCreature=Boolean(state.creatureId)&&!state.libraryMode;
  const creature=hasCreature?(state.editor?.read()||(state.cachedCreatures||[]).find(c=>c.id===state.creatureId)):null;
  const label=document.querySelector('#creature-name'),classLabel=document.querySelector('#creature-classes');
  const back=document.querySelector('#creature-back'),primary=document.querySelector('#sheet-navigation');
  const dock=document.querySelector('#mobile-tabs');
  const sessionTab=document.querySelector('#dock-session');
  back.hidden=!hasCreature;
  if(label)label.textContent=hasCreature?(creature?.name||'Creatura'):
    state.page==='catalog'?'Catalogo':state.page==='session'?'Partita':'VTT Mobile';
  if(classLabel){
    const members=hasCreature?localClasses(creature||{}):[];
    classLabel.textContent=members.map(member=>member.name+' '+Math.max(1,Number(member.level)||1)).join(' · ');
    classLabel.hidden=!members.length;
  }
  primary.innerHTML=hasCreature?PLAY_SECTIONS.map(([key,title])=>navigationButton(key,title)).join(''):'';
  primary.hidden=!hasCreature;
  nav.hidden=hasCreature;
  dock.classList.toggle('has-creature',hasCreature);
  sessionTab.hidden=!hasCreature;
  sessionTab.innerHTML=actionGlyph('map')+'<span class="destination-label">Partita</span>';
  if(state.page==='session')sessionTab.setAttribute('aria-current','page');
  else sessionTab.removeAttribute('aria-current');
  for(const [page,glyph,title] of [['library','proficiency','Creature'],['catalog','book','Catalogo'],['session','map','Partita']]){
    const button=nav.querySelector('[data-nav="'+page+'"]');
    button.className='btn dock-destination';
    button.innerHTML=actionGlyph(glyph)+'<span class="destination-label">'+title+'</span>';
    if(state.page===page)button.setAttribute('aria-current','page');
    else button.removeAttribute('aria-current');
  }
  connection.textContent=state.paired&&state.online?'● Collegato':state.online?'● Desktop disponibile':state.hostReachable?'○ Nessuna partita':'○ Offline';
  connection.title=state.paired&&state.online?'Partita collegata':state.online?'Desktop in partita':state.hostReachable?'Nessuna partita aperta':'Archivio locale disponibile offline';
  connection.classList.toggle('connected',state.paired&&state.online);
}

/* A phone's system Back button traverses browser history. Keep each visible
   screen in the same history stack, including the library and secondary tabs. */
let browserHistoryReady=false;
let restoringBrowserHistory=false;
let browserHistoryRestoreTicket=0;
function screenSnapshot(){
  return {
    page:state.page,libraryMode:state.libraryMode,creatureId:state.creatureId,
    sheet:state.sheet,detail:state.detail,sessionPane:state.sessionPane,
    inventorySubtab:state.inventorySubtab,catalogSelected:state.catalogSelected
  };
}
function syncBrowserHistory(){
  if(restoringBrowserHistory)return;
  const screen=screenSnapshot();
  const previous=window.history.state?.__vttMobileScreen;
  if(!browserHistoryReady){
    window.history.replaceState({...window.history.state,__vttMobileScreen:screen},'',location.href);
    browserHistoryReady=true;
  }else if(JSON.stringify(previous)!==JSON.stringify(screen)){
    window.history.pushState({...window.history.state,__vttMobileScreen:screen},'',location.href);
  }
}
async function restoreBrowserScreen(screen){
  // Older installed builds stored the retired Abilità tab in browser history.
  if(screen?.sheet==='stats')screen={...screen,sheet:'info'};
  if(screen?.sheet==='actions')screen={...screen,sheet:'battle'};
  if(screen?.sheet==='traits')screen={...screen,sheet:'info'};
  if(!screen||!sections.has(screen.page)||!SHEET_SECTIONS.some(([key])=>key===screen.sheet))return;
  const ticket=++browserHistoryRestoreTicket;
  restoringBrowserHistory=true;
  try{
    await flushPendingFields();
    if(ticket!==browserHistoryRestoreTicket)return;
    if(state.page!==screen.page)stopSubscriptions();
    if(screen.page==='session')realtimeStopped=false;
    const oldCreatureId=state.creatureId;
    state.page=screen.page;
    state.libraryMode=Boolean(screen.libraryMode);
    state.creatureId=state.libraryMode?null:(screen.creatureId||null);
    state.sheet=screen.sheet;
    state.detail=screen.detail||'overview';
    state.sessionPane=screen.sessionPane||'';
    state.inventorySubtab=screen.inventorySubtab||'items';
    state.catalogSelected=Number.isInteger(screen.catalogSelected)?screen.catalogSelected:-1;
    if(oldCreatureId!==state.creatureId||state.page!=='library'||state.libraryMode)state.editor=null;
    state.sheetPopup='';state.magicPopup='';state.traitPopupKey='';
    await render();
    window.scrollTo(0,0);
    app.focus({preventScroll:true});
  }catch(error){message('Impossibile ripristinare la scheda: '+errorMessage(error),true);}
  finally{if(ticket===browserHistoryRestoreTicket)restoringBrowserHistory=false;}
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
async function navigate(page){
  if(!sections.has(page))return;
  if(page!=='catalog')state.pendingItemOwner='';
  if(state.editor){try{await flushPendingFields();}catch(error){message("Salvataggio bloccato: "+errorMessage(error),true);return;}}
  const openedCreatureId=state.page==="library"&&!state.libraryMode?state.creatureId:null;
  stopSubscriptions();if(page==="session")realtimeStopped=false;
  state.traitPopupKey='';state.sheetPopup="";state.page=page;state.libraryMode=page==="library";state.editor=null;state.magicPopup="";
  if(page==="library")state.creatureId=null;
  state.cachedCreatures=(await listCreatures()).map(row=>row.creature);
  if(page==="session")state.chatAuthor=state.cachedCreatures.find(creature=>creature.id===openedCreatureId)?.name||"";
  await render();
}
async function render() {
  const ticket = ++state.renderTicket;
  syncNav();
  try {
    let html = "";
    if (state.page === "library") html = await libraryView();
    else if (state.page === "catalog") html = await catalogView();
    else if (state.page === "session") {
      state.cachedCreatures=(await listCreatures()).map(row=>row.creature);
      if(!state.spellCatalog)try{state.spellCatalog=await catalogEntries('spells');}catch{}
      state.castSheets=new Map(await Promise.all(state.cachedCreatures.map(async creature=>[creature.id,await computeLocalData(creature)])));
      html=sessionView();
    }
    if(ticket !== state.renderTicket) return;
    syncNav();
    // A status refresh can redraw Partita while a manual QR code is already
    // entered. Do not discard it or silently revert the Remember preference.
    const pendingCode=state.page==="session"?app.querySelector("#pair-secret")?.value:"";
    const rememberPair=state.page==="session"?app.querySelector("#pair-remember")?.checked:undefined;
    app.innerHTML = html;
    syncLibrarySelectionUI();
    if(state.page==="session")sessionMapViewer.mount(app.querySelector("#session-map-canvas"),state.snapshotObjectUrl);
    if(pendingCode && app.querySelector("#pair-secret"))
      app.querySelector("#pair-secret").value=pendingCode;
    if(rememberPair!==undefined && app.querySelector("#pair-remember"))
      app.querySelector("#pair-remember").checked=rememberPair;
    app.dataset.page=state.page;
    app.dataset.renderedSheet=state.page==="library"&&!state.libraryMode?state.sheet:"";
    decorateSheetHeadings();
    organizeSheetPanels();
    rememberUtilityDisclosures();
    mountTraitBenefitDialog();
    syncBrowserHistory();
    const magicDialog=app.querySelector('#magic-tools-dialog');
    if(magicDialog){
      magicDialog.addEventListener('close',()=>{state.magicPopup="";},{once:true});
      if(typeof magicDialog.showModal==='function')magicDialog.showModal();else magicDialog.setAttribute('open','');
    }
    if(state.page==="session" && state.map) void refreshSessionSnapshot();
    if(state.paired && state.online && !realtimeStopped && !state.stopMap) startMap();
    if(state.paired && state.online && !realtimeStopped && !state.pollChat) startChat();
  } catch(error) {
    if(ticket !== state.renderTicket) return;
    app.innerHTML = header("Errore", "Operazione non riuscita", errorMessage(error))+
      btn("refresh","Riprova","primary");
  }
}
function librarySelectionActions(){
  const count=state.librarySelectedIds.size;
  return count?'<span class="library-selection-count">'+count+' selezionate</span>'+
    btn("library-export","Esporta ("+count+")")+
    btn("library-delete","Elimina ("+count+")","danger"):'';
}
function syncLibrarySelectionUI(){
  const boxes=[...app.querySelectorAll('input[data-library-select]')];
  const all=app.querySelector('[data-library-select-all]');
  if(all){
    const selected=boxes.filter(box=>box.checked).length;
    all.checked=boxes.length>0&&selected===boxes.length;
    all.indeterminate=selected>0&&selected<boxes.length;
  }
  const actions=app.querySelector('#library-selected-actions');
  if(actions){actions.innerHTML=librarySelectionActions();actions.hidden=!state.librarySelectedIds.size;}
}
async function libraryView() {
  if(state.creatureId && !state.libraryMode) return editorView();
  const rows=await listCreatures();
  const availableIds=new Set(rows.map(row=>row.creature.id));
  for(const id of state.librarySelectedIds)if(!availableIds.has(id))state.librarySelectedIds.delete(id);
  const allSelected=rows.length>0&&rows.every(row=>state.librarySelectedIds.has(row.creature.id));
  let list=rows.map(({creature:c})=>{
    const species=c.species||c.race||(typeof c.stat_block?.type==='object'?c.stat_block.type.type:c.stat_block?.type)||c.type||'Razza non specificata';
    const classNames=localClasses(c).map(member=>esc(member.name)+' '+Math.max(1,Number(member.level)||1)).join(' · ');
    return '<article class="creature-card">'+
      '<label class="library-batch-check" aria-label="Seleziona '+esc(c.name)+'">'+
      '<input type="checkbox" data-library-select="'+esc(c.id)+'" '+
      (state.librarySelectedIds.has(c.id)?'checked':'')+'></label>'+
      '<button type="button" class="creature-open" data-act="open" data-id="'+esc(c.id)+
      '" aria-label="Visualizza scheda di '+esc(c.name)+'">'+
      '<span class="creature-info"><span class="creature-name">'+esc(c.name)+'</span>'+
      '<span class="creature-meta"><span class="creature-details">'+esc(species)+'</span>'+
      (classNames?'<span class="creature-classes">'+classNames+'</span>':
        c.level?'<span class="creature-classes">Liv. '+esc(c.level)+'</span>':'')+
      '</span></span><span class="creature-open-chevron" aria-hidden="true">›</span></button></article>';
  }).join('');
  if(!list)list='<div class="empty library-empty"><strong>Nessuna creatura salvata</strong>'+
    '<p>Aggiungi un personaggio oppure importa una scheda esistente.</p>'+
    btn("demo","Prova personaggio demo","primary")+'</div>';
  return '<section class="library-index" aria-label="Archivio delle creature">'+
    '<div class="library-intro"><div class="library-title-block"><h1>Le tue creature</h1>'+
    '<span class="library-list-count"><span class="library-count-number">'+rows.length+'</span> '+(rows.length===1?'scheda':'schede')+'</span></div>'+
    '<button type="button" class="library-add-button" data-act="library-add" aria-label="Aggiungi personaggio" title="Aggiungi personaggio">'+
    '<span class="library-add-glyph" aria-hidden="true">+</span><span class="library-add-text" aria-hidden="true">Aggiungi</span></button></div>'+
    (rows.length?'<div class="library-list-header"><label class="library-batch-check library-select-master">'+
      '<input type="checkbox" data-library-select-all '+(allSelected?'checked':'')+'>'+
      '<span class="library-select-label">Seleziona tutte</span></label></div>':'')+
    '<div id="library-selected-actions" class="library-selection-actions" '+(state.librarySelectedIds.size?'':'hidden')+'>'+
      librarySelectionActions()+'</div>'+
    '<div class="library-rows">'+list+'</div></section>'+
    '<details class="library-backup"><summary>'+
      '<span class="library-backup-symbol" aria-hidden="true">↺</span>'+
      '<span class="library-backup-copy"><strong>Backup e ripristino</strong>'+
      '<small>Conserva una copia del tuo archivio locale</small></span>'+
      '<span class="library-backup-chevron" aria-hidden="true">⌄</span></summary>'+
      '<div class="library-backup-content"><p>Esporta una copia dei personaggi e dei contenuti locali, oppure importa un backup precedente.</p>'+
      '<div class="library-backup-actions">'+btn("backup","Esporta backup")+
      btn("restore-backup","Ripristina backup")+'</div></div></details>'+
    '<dialog id="library-create-dialog" class="library-create-dialog" aria-labelledby="library-create-title">'+
      '<div class="library-create-body"><button type="button" class="library-create-close" data-act="library-create-close" aria-label="Chiudi">×</button>'+
      '<h2 id="library-create-title">Aggiungi personaggio</h2>'+
      '<p>Vuoi creare una nuova scheda o importarne una esistente?</p>'+
      '<div class="library-create-options">'+btn("create","Crea personaggio","primary")+
      btn("import","Importa personaggio")+'</div></div></dialog>';
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
    detail='<button type="button" class="btn catalog-back" data-act="catalog-close">← Risultati del catalogo</button>'+panel("Dettagli · "+String(full.name||""),'<p class="hint">'+
      esc(full.source||"Fonte sconosciuta")+'</p><p class="notable catalog-description">'+
      esc(description||"Descrizione non disponibile nell'archivio locale.")+'</p>'+
      (full._description_warning?'<p class="warning">'+esc(full._description_warning)+'</p>':"")+
      (assignable && (state.cachedCreatures||[]).length?
      '<div class="separator"></div><label>Aggiungi alla scheda<select id="catalog-creature">'+
      state.cachedCreatures.map(c=>'<option value="'+esc(c.id)+'"'+(state.featAssignReturnId===c.id?' selected':'')+'>'+esc(c.name)+'</option>').join("")+
      '</select></label><div class="actions">'+btn("catalog-assign","Aggiungi contenuto alla creatura","primary")+'</div>'+
      '':"")+
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
      ''+
      Array.from({length:3},(_,i)=>'<div class="columns"><label>Tipo<select data-quick-kind="'+i+'">'+[['','Nessuna'],['skill','Abilità'],['expertise','Maestria'],['save','Tiro salvezza'],['weapon','Arma'],['armor','Armatura'],['tool','Strumento'],['language','Linguaggio']].map(([id,name])=>'<option value="'+id+'">'+name+'</option>').join('')+'</select></label><label>Competenza<input data-quick-key="'+i+'" placeholder="es. perception"></label></div>').join(''))+
    '<div class="actions">'+btn('quick-create','Crea nel catalogo locale','primary')+'</div>'):'';
  return header("Compendio", "Catalogo", "Fonti strutturate incluse in VTT. Il catalogo base è disponibile offline dopo l'installazione.")+
    (chosen?detail:panel("Esplora",'<div class="columns"><label>Sezione<select id="catalog-category">'+
      CATALOG_CATEGORIES.map(([id,label])=>
      '<option value="'+id+'" '+(state.catalogCategory===id?'selected':'')+'>'+label+'</option>').join("")+
      '</select></label><label>Ricerca<input id="catalog-search" type="search" value="'+esc(state.catalogQuery)+
      '" placeholder="Nome o fonte"></label></div><p class="hint">'+
      state.catalogRows.length+' voci nel catalogo · fino a 90 risultati per pagina</p>'+
      '<div id="catalog-results" class="catalog-results">'+renderCatalogRows()+'</div>')+
    (quickPanel?'<details class="archive-tools catalog-create"><summary>Crea contenuto personalizzato</summary>'+quickPanel+'</details>':''));
}

async function computeLocalData(record){
  let catalogs={},loadError="";
  try{catalogs=await loadRuleCatalogs();}
  catch(error){loadError="Cataloghi numerici offline non disponibili: "+errorMessage(error);}
  const calculated=calculateSheet(record,catalogs);
  return {...calculated,loadError,
    pending_choices:pendingCharacterChoices(record,calculated,catalogs),
    infusion_catalog:catalogs.abilityGrants?.artificer_infusions||[],
    infusion_mechanics:catalogs.classMechanics||{}};
}

function classAbilityActivationPatch(c,calculated,ability,options={}){
 return classFeatureActivationPatch(c,calculated,ability.id,options);
}
async function activateClassAbility(c,calculated,ability){
 if(ability.mode==='trait_state'){
   await patch(traitStateActivationPatch(c,calculated.features,calculated.trait_state_catalog,ability.state_id));
   await render();return;
 }
 if(ability.mode==='metamagic'){
  state.sheet='magic';await render();message('Scegli un incantesimo: la Metamagia si configura nella finestra di lancio.');return;
 }
 const enhanced=c.rules_version==='2024'&&['patient_defense','step_of_the_wind'].includes(ability.class_feature_id);
 if(ability.mode==='toggle'&&!enhanced){
  await patch(classAbilityActivationPatch(c,calculated,ability));await render();return;
 }
 document.querySelector('#class-feature-dialog')?.remove();
 const dialog=document.createElement('dialog');dialog.id='class-feature-dialog';dialog.className='sheet-roll-dialog';
 dialog.dataset.creatureId=c.id;dialog.dataset.abilityId=ability.id;
 const recovery=ability.mode==='recovery',conversion=ability.mode==='conversion',pool=ability.mode==='heal_pool';
 dialog.innerHTML='<h2>'+esc(ability.name)+'</h2><p class="trait-description">'+esc(ability.description)+'</p>'+
  (pool?'<label>Punti ferita<input data-feature-amount type="number" min="1" max="'+esc(Math.max(1,(calculated.trackers||[]).find(t=>t.id===ability.tracker_id)?.max||1))+'" value="1"></label><label class="check"><input data-feature-self type="checkbox" checked>Applica la cura a te stesso</label>':'')+
  (ability.mode==='heal_roll'?'<p>Tira 1d10 e aggiungi il livello da Guerriero. La cura si applica a te stesso.</p>':'')+
  (conversion?'<label>Livello slot<select data-feature-level>'+[1,2,3,4,5].map(n=>'<option>'+n+'</option>').join('')+'</select></label><label class="check"><input data-feature-create type="checkbox" checked>Crea uno slot (disattiva per convertire uno slot in punti)</label>':'')+
  (recovery?'<p>Massimo '+Math.ceil(Number((c.classes||[]).find(x=>x.name==='Wizard')?.level||c.level||0)/2)+' livelli di slot.</p>'+[1,2,3,4,5].map(n=>'<label>Slot di livello '+n+'<input data-feature-recover="'+n+'" type="number" min="0" max="'+Number(c.spell_slots_spent?.[n]||0)+'" value="0"></label>').join(''):'')+
  (enhanced?'<label class="check"><input data-feature-enhanced type="checkbox">Versione potenziata · 1 punto Focus</label>':'')+
  (ability.mode==='metamagic_roll'?'<p>Scegli i dadi da sostituire: devi utilizzare i nuovi risultati.</p>'+
   (ability.name==='Empowered Spell'?'<label>Numero di dadi<input data-feature-count type="number" min="1" max="'+Math.max(1,Number(calculated.values['ability_mod:cha'])||1)+'" value="1"></label><label>Tipo di dado<select data-feature-sides>'+[4,6,8,10,12,20,100].map(n=>'<option value="'+n+'">d'+n+'</option>').join('')+'</select></label>':'<p>Ripeti 1d20 per il tiro per colpire fallito.</p>'):'')+
  (ability.mode==='context'?'<p>Conferma bersagli, condizioni e tiri indicati dal tratto. Il consumo sarà registrato alla conferma.</p>':'')+
  '<p data-feature-result role="status"></p><div class="actions"><button type="button" class="btn primary" data-feature-confirm>Conferma</button><button type="button" class="btn" data-feature-cancel>Annulla</button></div>';
 dialog.querySelector('[data-feature-cancel]').addEventListener('click',()=>dialog.close());
 dialog.querySelector('[data-feature-confirm]').addEventListener('click',async event=>{
  if(event.currentTarget.disabled)return;
  const button=event.currentTarget;button.disabled=true;
  try{
   const current=state.editor?.read();if(current?.id!==dialog.dataset.creatureId)throw Error('La creatura è cambiata.');
   const fresh=await computeLocalData(current),options={amount:dialog.querySelector('[data-feature-amount]')?.value,
    level:dialog.querySelector('[data-feature-level]')?.value,create_slot:dialog.querySelector('[data-feature-create]')?.checked,
    apply_to_self:dialog.querySelector('[data-feature-self]')?.checked,enhanced:!!dialog.querySelector('[data-feature-enhanced]')?.checked,
    count:Number(dialog.querySelector('[data-feature-count]')?.value||1),sides:Number(dialog.querySelector('[data-feature-sides]')?.value||20),
    levels:[...dialog.querySelectorAll('[data-feature-recover]')].map(input=>Number(input.value))};
   if(ability.mode==='heal_roll')options.roll=randomDie(10);
   const changes=classAbilityActivationPatch(current,fresh,ability,options);
   const reroll=ability.mode==='metamagic_roll'?rollBattleDamage(ability.name==='Seeking Spell'?'1d20':options.count+'d'+options.sides,randomDie):null;
   await patch(changes);if(state.saveError)throw Error(state.saveError);
   await state.editor.flush();dialog.close();await render();
   if(reroll){state.roll={...reroll,label:ability.name,author:selectedName()};state.rollHistory.unshift({...state.roll});}
   message(reroll?ability.name+': '+reroll.notation+' → '+reroll.total+' · usa i nuovi risultati.':ability.mode==='heal_roll'?ability.name+': d10 '+options.roll+' · PF '+changes.current_hp:ability.name+' applicato.');
  }catch(error){button.disabled=false;dialog.querySelector('[data-feature-result]').textContent=errorMessage(error);}
 });
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});document.body.append(dialog);
 if(dialog.showModal)dialog.showModal();else dialog.setAttribute('open','');
}
async function applyFormPatch(c,changes){
 if(c.linked_token_sync_id&&state.paired&&state.online){
  const result=await action('set_appearance',{token_id:c.linked_token_sync_id,owner_id:await ownerId(),miniature_id:changes.current_miniature_id});
  if(!result.ok)throw Error(result.error||'Aspetto non applicato sul desktop.');
 }
 await patch(changes);if(state.saveError)throw Error(state.saveError);await state.editor.flush();
}
function promptEndWildShape(creatureId){
 const dialog=document.createElement('dialog');dialog.className='sheet-roll-dialog';dialog.id='form-depleted-dialog';
 dialog.innerHTML='<h2>Seconda forma esaurita</h2><p>I PF della seconda forma sono a 0. Ripristinare l’aspetto originale?</p><div class="actions"><button type="button" class="btn primary" data-form-restore>Ripristina aspetto</button><button type="button" class="btn" data-form-keep>Mantieni aspetto</button></div>';
 dialog.querySelector('[data-form-keep]').addEventListener('click',()=>dialog.close());
 dialog.querySelector('[data-form-restore]').addEventListener('click',async event=>{
  const button=event.currentTarget;button.disabled=true;
  try{const c=state.editor?.read();if(c?.id!==creatureId)throw Error('La creatura è cambiata.');
   await applyFormPatch(c,endWildShapePatch(c));dialog.close();await render();
  }catch(error){button.disabled=false;message(errorMessage(error),true);}
 });
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});document.body.append(dialog);
 if(dialog.showModal)dialog.showModal();else dialog.setAttribute('open','');
}
async function editorView() {
  if(!state.editor) state.editor = await openCreatureEditor(state.creatureId);
  if(state.sheet==='origins')state.sheet='info';
  const c = state.editor.read();
  // The persistent header owns creature identity and tab navigation.
  let body = "";
  if(state.sheet==='info'){
    await Promise.all(["races","classes","subclasses","backgrounds",...['feats']].map(async key=>{
      if(!state.referenceCatalogs[key])try{state.referenceCatalogs[key]=await catalogEntries(key);}
      catch{ /* References stay editable offline. */ }
    }));
  }
  if(state.sheet==="battle"){
    const [featureRules,generalRules]=await Promise.allSettled([loadFeatureActionOverrides(),loadGeneralActionSupplements()]);
    state.featureActionOverrides=featureRules.status==='fulfilled'?featureRules.value:[];
    state.generalActionSupplements=generalRules.status==='fulfilled'?generalRules.value:[];
    state.actionCatalogError=generalRules.status==='rejected'?
      'Le azioni generali e le regole varianti non sono state caricate: '+errorMessage(generalRules.reason):'';
  }
  if((state.sheet==="battle"||state.sheet==="magic"||state.sheet==="conditions"||state.sheet==="info"||state.sheet==="inventory"&&state.inventorySubtab==="scrolls")&&!state.spellCatalog){
    try{state.spellCatalog=await catalogEntries("spells");state.spellCatalogError="";}
    catch(error){state.spellCatalogError=errorMessage(error);}
  }
  if((state.sheet==="magic"||state.sheet==="battle")&&!state.abilityCatalog){
    try{state.abilityCatalog=await loadActivatedAbilities();}
    catch{state.abilityCatalog=[];}
  }
  const calculated=await computeLocalData(c);
  state.calculated=calculated;
  const featDetails=state.sheet==='info'?await Promise.all((Array.isArray(c.feats_catalog)?c.feats_catalog:[]).map(async feat=>{
    const name=typeof feat==='string'?feat:feat?.name||'',source=typeof feat==='string'?'':feat?.source||'';
    const match=(state.referenceCatalogs.feats||[]).find(row=>row.name?.toLowerCase()===name.toLowerCase()&&(!source||row.source?.toLowerCase()===source.toLowerCase()));
    try{return {description:flattenDescription(await detailedEntry('feats',match||{name,source}))};}
    catch{return {description:''};}
  })):undefined;
  // Resolve selected optional powers through the very same detailed
  // compendium source used by the trait and feature viewers.
  let battleOptionalTraits=[];
  if(state.sheet==='battle'&&(c.optional_features_catalog||[]).length){
    if(!state.referenceCatalogs.optional_features)
      try{state.referenceCatalogs.optional_features=await catalogEntries('optional_features');}
      catch{state.referenceCatalogs.optional_features=[];}
    battleOptionalTraits=await Promise.all((c.optional_features_catalog||[]).map(async feature=>{
      const name=String(feature?.name||feature||''),source=String(feature?.source||'');
      const reference=(state.referenceCatalogs.optional_features||[]).find(row=>
        String(row.name||'').toLowerCase()===name.toLowerCase()&&
        (!source||String(row.source||'').toLowerCase()===source.toLowerCase()));
      let detail=reference||feature;
      if(reference)try{detail=await detailedEntry('optional_features',reference);}catch{}
      return {name,origin_id:feature?.origin_id||'',origin_key:feature?.origin_name||source,
        feature_key:'',description:flattenDescription(detail)||flattenDescription(feature)};
    }));
  }
  state.battleOptionalTraits=battleOptionalTraits;
  body=nativeSection(c,state.sheet,{field,area,panel,resources:resourceView(c,false,state.sheet==='battle'),resourcesEditor:resourceView(c,true),equipment:inventoryEquipmentView(c,calculated),armor:'',attacks:attacksView(calculated,state.sheet==='battle'),details:state.detail,catalogs:{...state.referenceCatalogs,featDetails,origins:calculated.origins,trackers:calculated.trackers,attacks:calculated.attacks,calculated,spells:state.spellCatalog||[]},calculated})||"";
  if(state.sheet==="info")body+=await traitsView(c);
  switch(state.sheet){
  case "inventory": {
    const inventory=Array.isArray(c.inventory)?c.inventory:[];
    const isDocuments=state.inventorySubtab==="documents",isScrolls=state.inventorySubtab==="scrolls";
    const nav='<nav class="inventory-subtabs" role="tablist" aria-label="Sezioni inventario">'+
      [['items','Oggetti','inventory'],['scrolls','Pergamene','scroll'],['documents','Documenti','book']].map(([key,label,glyph])=>
        '<button type="button" role="tab" data-act="inventory-subtab" data-subtab="'+key+'" '+
        'aria-selected="'+(key===state.inventorySubtab)+'" aria-label="'+label+'">'+
        actionGlyph(glyph)+'<span>'+label+'</span></button>').join('')+'</nav>';
    if(isDocuments){
      const documents=inventory.map((item,index)=>({item,index})).filter(({item})=>isDocument(item));
      const definitions=await Promise.all(documents.map(({item})=>
        getRecord("global","homebrew",String(item.id||""))));
      body=nav+panel("Documenti",
        (documents.length?documents.map(({item,index},i)=>documentRow(item,index,definitions[i])).join(""):
          '<p class="hint">Nessun documento.</p>')+
        '<div class="actions">'+btn("document-add","＋ Nuovo documento","primary")+'</div>',
        "inventory-native-panel inventory-documents-panel");
    }else{
      const owned=inventory.map((item,index)=>({item,index})).filter(({item})=>!isDocument(item));
      const ordinary=owned.filter(({item})=>!isSpellScroll(item));
      const scrolls=owned.filter(({item})=>isSpellScroll(item));
      const attunements=owned.filter(({item})=>requiresAttunement(item));
      const visibleRows=isScrolls?scrolls:ordinary;
      let selected=visibleRows.find(({index})=>index===state.inventorySelectedIndex);
      if(!selected){selected=visibleRows[0];state.inventorySelectedIndex=selected?.index??-1;}
      let resolvedDetail=selected?.item||{};
      if(selected&&isCatalogItem(selected.item)){
        if(!state.referenceCatalogs.items)try{state.referenceCatalogs.items=await catalogEntries("items");}catch{state.referenceCatalogs.items=[];}
        const source=state.referenceCatalogs.items.find(row=>String(row.id||"")===String(selected.item.id||""));
        if(source){
          const detail=await detailedEntry("items",source);
          resolvedDetail={...detail,...selected.item,
            entries:detail.entries??selected.item.entries,
            description:detail.description??selected.item.description};
        }
      }
      const description=selected?panel("Descrizione · "+(selected.item.name||"Oggetto"),
        inventoryItemDescription(resolvedDetail,selected.index),"inventory-native-panel inventory-description-panel"):"";
      body=nav+(isScrolls?
        panel("Pergamene possedute",
          inventoryTable(scrolls,true,state.inventorySelectedIndex,state.inventoryMenuIndex),
          "inventory-native-panel inventory-scroll-panel")+
        panel("Nuova pergamena",scrollSpellCreatorView(),"inventory-native-panel inventory-scroll-create"):
        inventoryEquipmentView(c,calculated)+
        inventoryAttunementView(c,attunements)+
        inventoryCoinsView(c)+
        panel("Oggetti posseduti",
          inventoryTable(ordinary,false,state.inventorySelectedIndex,state.inventoryMenuIndex)+
          '<div class="actions">'+btn("item-catalog","Cerca nel catalogo","primary")+
          btn("new-homebrew-item","＋ Oggetto homebrew")+'</div>',
          "inventory-native-panel"))+
        description;
    }
    break;
  }
  case "battle":
    // Keep native Poteri tracker panels available as contextual editors,
    // including the abilities relocated from Poteri into battle resources.
    body+='<div class="battle-power-archive" hidden>'+
      originPowersView(c,calculated,abilitiesForCreature(c,state.abilityCatalog||[],calculated),true)+'</div>';
    break;
  case "magic":
    body=magicToolbar(calculated)+
      panel("Incantesimi disponibili",
        calculated.casting_classes.map(member=>{
          const count=classSelectionCount(c,member,calculated.casting_classes,state.spellCatalog||[]);
          return '<section class="magic-source"><header class="magic-source-header"><h3>'+esc(member.name)+'</h3>'+
            '<span class="hint">'+esc(member.source||'')+'</span></header>'+
            '<div class="magic-source-controls">'+
            '<button type="button" class="btn small magic-selection-button" data-act="magic-select-spells" data-magic-class="'+esc(member.id)+'" data-magic-target="prepared_spells">'+
            esc(member.mode==='Preparati'?'Prepara incantesimi':'Scegli incantesimi conosciuti')+'</button>'+
            (member.book?'<button type="button" class="btn small magic-selection-button" data-act="magic-select-spells" data-magic-class="'+esc(member.id)+'" data-magic-target="spellbook_spells">Aggiungi al libro</button>':'')+
            '</div>'+
            '<p class="hint magic-source-count">'+esc(member.mode)+' '+count.leveled+' / '+
            (member.limit<0?'—':member.limit)+' · Trucchetti '+count.cantrips+' / '+member.cantrips+'</p>'+
            spellSelectionWarning(member,count)+
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
      originPowersView(c,calculated)+
      infusionPanel(c,calculated)+
      magicToolsDialog(c,calculated);
    break;
  case "conditions":
    body=panel('Condizioni',
      '<div class="condition-sheet-header"><span class="condition-count"><strong data-condition-count>'+
        (c.conditions||[]).length+
        '</strong> attive</span>'+
        field('Indebolimento · livello','exhaustion',c.exhaustion??0,'number','min="0" max="6"')+
      '</div>'+conditionGrid(c.conditions,'data-condition',c.rules_version),'condition-sheet-panel');
    break;
  case "json":
    body = panel("Editor avanzato",'<p class="warning">Modifica JSON per campi non ancora presenti nella GUI. La scheda viene validata prima del salvataggio; ID e proprietario non possono cambiare.</p>'+
      '<label>Documento completo<textarea id="json-editor" rows="18" spellcheck="false" class="inline-code">'+
        esc(JSON.stringify(c,null,2))+'</textarea></label><div class="actions">'+
      btn("save-json","Salva modifiche JSON","primary")+'</div>');
    break;
  }
  return header(['info','json'].includes(state.sheet)?'Il personaggio':'Durante la sessione',...(SECTION_COPY[state.sheet]||['Scheda','']))+
    '<div data-local-sheet-calculations>'+body+(state.sheet==='info'?'':calculationNote(calculated,calculated.loadError))+'</div><p id="save-state" class="save-status'+(state.saveError?' error':'')+'" role="status" aria-live="polite">'+esc(state.saveError||'✓ Salvato sul dispositivo')+'</p><details class="archive-tools"><summary>Opzioni della scheda</summary><div class="actions">'+btn("export","Esporta JSON")+
    '<button type="button" class="btn" data-act="sheet" data-sheet="json">Editor JSON avanzato</button>'+
    btn("delete","Elimina scheda","danger")+'</div></details>';
}
function resourceView(c,configure=false,compact=false){
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
  if(compact){
   const remaining=Math.max(0,maximum-used);
   const compactActions='<div class="battle-resource-actions">'+
     '<button type="button" class="btn small" data-act="tracker-less" data-tracker-id="'+esc(t.id)+'" aria-label="Ripristina un utilizzo di '+esc(t.name)+'" title="Ripristina 1">−</button>'+
     '<button type="button" class="btn small" data-act="tracker-more" data-tracker-id="'+esc(t.id)+'" aria-label="Consuma un utilizzo di '+esc(t.name)+'" title="Consuma 1">＋</button>'+
     '<button type="button" class="btn small battle-resource-link" data-act="tracker-powers" data-tracker-id="'+esc(t.id)+'" aria-label="Apri '+esc(t.name)+' in Magia" title="Vai a Magia">↗</button>'+
     '<details class="battle-resource-details"><summary aria-label="Origine e recupero di '+esc(t.name)+'" title="Origine e recupero">ⓘ</summary>'+
       '<span>'+esc(t.origin_name||'Senza origine')+' · '+
       esc(modes.find(([id])=>id===t.recharge)?.[1]||t.recharge||'Manuale')+'</span></details></div>';
   return '<article class="battle-resource-row">'+
    '<div class="battle-resource-main"><strong>'+esc(t.name)+'</strong>'+
      '<span class="battle-resource-count"><b>'+esc(remaining)+'</b> / '+
        formulaReadout(state.calculated,'tracker:'+t.id,'Massimo '+t.name)+'</span></div>'+
    compactActions+
    (t.recharge==='d6'||optional.length?
      '<div class="battle-resource-extra">'+
        (t.recharge==='d6'?'<button type="button" class="btn small" data-act="tracker-recharge" data-tracker-id="'+esc(t.id)+'">Ricarica d6 · '+esc(t.recharge_min||6)+'+</button>':'')+
        optionalButton+'</div>':'')+
    '</article>';
  }
  return '<article class="list-item"><div class="row between"><strong>'+esc(t.name)+'</strong><button type="button" class="btn small" data-act="tracker-powers" title="Apri in Magia">↗ Magia</button></div><p class="hint">'+esc(t.origin_name||'Senza origine')+' · '+esc(modes.find(([id])=>id===t.recharge)?.[1]||t.recharge||'Manuale')+'</p>'+(t.inactive?'<p class="hint">Non attivo: origine disattivata o requisito non soddisfatto. Utilizzi salvati: '+esc(used)+'</p>':'<div class="row">Disponibili: '+esc(Math.max(0,maximum-used))+' / '+formulaReadout(state.calculated,'tracker:'+t.id,'Massimo '+t.name)+'</div>')+actions+optionalButton+edit+'</article>';
 }).join('');
 if(compact)return panel('Risorse',
   (body||'<p class="hint">Nessuna risorsa disponibile.</p>')+
   '<div class="battle-recovery-actions">'+
    '<button type="button" class="btn small" data-act="tracker-short">Riposo breve</button>'+
    '<button type="button" class="btn small" data-act="tracker-long">Riposo lungo</button>'+
    '<button type="button" class="btn small" data-act="tracker-turn">Inizio turno</button>'+
   '</div>','battle-resources-panel');
 return panel('Risorse','<p class="hint">I valori massimi includono formule e bonus attivi. Il riposo breve ripristina le risorse previste e gli slot del Patto; quello lungo ripristina anche gli slot di classe. All’inizio del turno si recuperano solo le risorse previste.</p>'+(body||'<p class="hint">Nessuna risorsa disponibile.</p>')+'<div class="actions">'+btn('tracker-short','Riposo breve')+btn('tracker-long','Riposo lungo')+btn('tracker-turn','Inizio turno')+'</div>')+(configure?panel('Aggiungi tracker','<div class="columns"><label>Nome<input id="tracker-name" maxlength="120"></label><label>Utilizzi massimi<input type="number" id="tracker-max" min="0" max="99999" value="1"></label><label>Formula del massimo (opzionale)<input id="tracker-formula" placeholder="Es. 1 + cha_mod"></label><label>Origine<select id="tracker-origin">'+options([['','Senza origine'],...origins.map(o=>[o.id,o.name])],'')+'</select></label><label>Recupero<select id="tracker-recharge">'+options(modes.filter(([id])=>id!=='d6'),'manual')+'</select></label></div>'+btn('tracker-add','Aggiungi risorsa','primary')):'');
}

function conditionGrid(active,attribute,edition="2014"){
 const applied=new Set(Array.isArray(active)?active:[]);
 const options=conditionOptions(state.conditionCatalog,edition,active);
 const knownCategories=CONDITION_CATEGORIES.map(([category,title])=>({category,title}));
 const unknown=[...new Set(options.map(row=>row.category))]
   .filter(category=>!knownCategories.some(group=>group.category===category))
   .map(category=>({category,title:category}));
 return '<div class="condition-category-list" aria-label="Stati e afflizioni">'+
  [...knownCategories,...unknown].map(({category,title})=>{
   const rows=options.filter(row=>row.category===category);
   if(!rows.length)return "";
   const expanded=category==="conditions"||rows.some(row=>applied.has(row.id));
   return '<details class="condition-category" '+(expanded?'open':'')+'>'+
     '<summary>'+esc(title)+' <span class="condition-category-count">'+rows.length+'</span></summary>'+
     '<div class="session-condition-grid condition-toggle-grid" role="group" aria-label="'+esc(title)+'">'+
     rows.map(({id,label})=>'<label class="check condition-toggle">'+
       '<input type="checkbox" '+attribute+'="'+esc(id)+'" '+(applied.has(id)?'checked':'')+'>'+
       '<span>'+esc(label)+'</span></label>').join('')+'</div></details>';
  }).join('')+'</div>';
}
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
function attacksView(calculated,compact=false){
 const rows=(calculated.attacks||[]).map(attack=>{
  if(compact)return '<article class="battle-attack-row">'+
    '<strong>'+esc(attack.name)+'</strong>'+
    '<div class="battle-attack-facts">'+
      '<span>Colpire '+formulaReadout(calculated,'attack_hit:'+attack.id,'Tiro per colpire',{signed:true})+'</span>'+
      '<span>Danni <b>'+esc(attack.damage)+' '+esc(attack.damage_type||'')+'</b></span>'+
      '<span>'+(attack.melee?'Portata ':'Gittata ')+
        formulaReadout(calculated,'attack_range:'+attack.id,'Portata',{suffix:' ft'})+'</span></div>'+
    '<details class="battle-attack-details"><summary>Dettagli attacco</summary>'+
      '<p>'+esc(attack.explanation||'')+(attack.offhand_bonus?' · Attacco secondario con azione bonus':'')+'</p>'+
      (attack.long_range_feet?'<p>Gittata lunga '+formulaReadout(calculated,'attack_long_range:'+attack.id,'Gittata lunga',{suffix:' ft'})+'</p>':'')+
    '</details></article>';
  return '<article class="native-entry"><h3>'+esc(attack.name)+'</h3><div class="row between"><span>Tiro per colpire '+formulaReadout(calculated,'attack_hit:'+attack.id,'Tiro per colpire',{signed:true})+'</span><span>Danni: '+esc(attack.damage)+' '+esc(attack.damage_type||'')+'</span></div><p class="hint">'+esc(attack.explanation)+(attack.offhand_bonus?' · Attacco secondario con azione bonus':'')+'</p><div class="row"><span>'+ (attack.melee?'Portata':'Gittata')+' '+formulaReadout(calculated,'attack_range:'+attack.id,'Portata', {suffix:' ft'})+'</span>'+(attack.long_range_feet?'<span>Lunga '+formulaReadout(calculated,'attack_long_range:'+attack.id,'Gittata lunga',{suffix:' ft'})+'</span>':'')+'</div></article>';
 }).join('');
 return '<div data-attack-list>'+ (rows||'<p class="hint">Seleziona un’arma in una mano per renderne disponibile l’attacco.</p>')+'</div>';
}
async function traitsView(c){
 const warnings=[];
 const entries=async category=>{
  if(!state.referenceCatalogs[category]){
   try{state.referenceCatalogs[category]=await catalogEntries(category);}
   catch{warnings.push('Catalogo '+category+' non disponibile offline.');return [];}
  }
  return state.referenceCatalogs[category];
 };
 const rows=withGrantedSpellPreviews(await collectTraitRows(c,state.calculated||{},
  {entries,detail:detailedEntry,isDocument,conditionLabel}),state.calculated?.origin_spells||[],state.spellCatalog||[]);
 const groups=groupTraitRows(rows);
 const benefitProjection={...(state.calculated||{}),
  activatable_abilities:abilitiesForCreature(c,state.abilityCatalog||[],state.calculated||{})};
 state.traitRows=rows;
 const renderCard=trait=>{
  const description=flattenDescription({entries:trait.entries});
  const benefitCount=traitBenefitGroups(trait,c,benefitProjection)
    .reduce((total,group)=>total+group.items.length,0);
  const active=!trait.inactive;
  // The icon is a separate control, not a nested button inside <summary>.
  // A chevron belongs exclusively to expanding the description.
  return '<div class="trait-row'+(active?'':' trait-row--inactive')+'" data-trait-enabled="'+String(active)+'"><button type="button" class="trait-benefits-trigger" data-act="trait-benefits-open" data-trait-key="'+esc(trait.key)+'" aria-label="Gestisci benefici di '+esc(trait.name)+'" title="Gestisci benefici">'+
      (benefitCount?actionGlyph('proficiency'):'<span aria-hidden="true">＋</span>')+'</button>'+
    '<details class="trait-card'+(active?'':' trait-inactive')+'" data-trait-key="'+esc(trait.key)+'" data-trait-origin="'+esc(trait.origin_key)+'" data-trait-feature="'+esc(trait.feature_origin||'')+'" data-trait-proficiency="'+esc(trait.proficiency_origin||'')+'">'+
    '<summary><span class="trait-title">'+esc(/^Descrizione · /.test(trait.name)?'Panoramica':trait.name)+'</span>'+
      '<span class="trait-chevron" aria-hidden="true"><svg viewBox="0 0 24 16" width="22" height="15" fill="none"><path d="M3 6 L12 11 L21 6" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg></span></summary>'+
    '<div class="trait-content">'+
      (description?'<p class="trait-description">'+esc(description)+'</p>':'')+
      (trait.source?'<span class="trait-book">'+esc(trait.source)+'</span>':'')+
    '</div></details></div>';
 };
 const originTitle=title=>String(title||'').replace(/^(?:Specie|Sottorazza|Classe|Sottoclasse|Background|Talento|Oggetto)\s*·\s*/i,'');
 const originKind=(category,origin)=>{
  if(category==='razza')return String(origin.key).startsWith('subrace|')?'Sottorazza':'Specie';
  if(category==='classi')return String(origin.key).includes('|subclass|')?'Sottoclasse':'Classe';
  if(category==='background')return 'Background';
  if(category==='mostro')return 'Mostro';
  if(category==='incantesimi')return 'Incantesimo';
  return 'Origine';
 };
 const content=groups.map(group=>'<section class="trait-category" data-trait-category="'+esc(group.id)+'" aria-label="'+esc(group.title)+'">'+
  (['stati','talenti','oggetti'].includes(group.id)?
   '<h3 class="trait-origin-title trait-category-heading"><span class="trait-origin-name">'+
    (group.id==='stati'?'Stati attivi':group.id==='talenti'?'Talenti':'Oggetti')+'</span></h3>':'')+
  group.origins.map(origin=>
   '<section class="trait-origin-group" data-trait-group="'+esc(origin.key)+'">'+
   (['stati','talenti','oggetti'].includes(group.id)?'':
    '<h3 class="trait-origin-title"><span class="trait-origin-kind">'+esc(originKind(group.id,origin))+'</span>'+
     '<span class="trait-origin-name">'+esc(originTitle(origin.title))+'</span></h3>')+
   origin.levels.map(tier=>
    (tier.level>=0&&!['stati','talenti','oggetti'].includes(group.id)?
     '<h4 class="trait-level">LIVELLO '+tier.level+'</h4>':'')+
    '<div class="trait-origin-cards">'+tier.rows.map(renderCard).join('')+'</div>'
   ).join('')+'</section>'
  ).join('')+'</section>').join('');
 return panel('Tratti',(content||'<p>Nessun privilegio da mostrare.</p>'))+
   (warnings.length?'<p class="trait-catalog-warnings">'+esc([...new Set(warnings)].join(' · '))+'</p>':'');
}
// Popup closure is synchronous: a save/refresh of unrelated fields must
// never hold an X button hostage or recreate a modal after it was dismissed.
function dismissTraitBenefitDialog(){
 state.traitPopupKey='';state.traitPopupConfirm='';
 state.traitPopupDraftKind='';state.traitPopupDraftTarget='';
 state.traitPopupTrait=null;
 const dialog=document.querySelector('#trait-benefits-dialog');
 if(dialog){
  if(dialog.open&&typeof dialog.close==='function')dialog.close();
  dialog.remove();
 }
}
// Benefits are edited only here. The disclosure never owns an edit form, and
// entering values does not persist anything until the explicit Salva action.
function mountTraitBenefitDialog(){
 if(!state.traitPopupKey||state.sheet!=='info'||!state.editor)return;
 const record=state.editor.read();
 const current=state.traitRows.find(row=>row.key===state.traitPopupKey);
 const trait=current||(state.traitPopupTrait?.key===state.traitPopupKey?
  {...state.traitPopupTrait,inactive:!traitIsActive(record,state.traitPopupTrait)}:null);
 if(!trait){state.traitPopupKey='';state.traitPopupConfirm='';state.traitPopupTrait=null;return;}
 state.traitPopupTrait=trait;
 const benefitProjection={...(state.calculated||{}),
  activatable_abilities:abilitiesForCreature(record,state.abilityCatalog||[],state.calculated||{})};
 const groups=traitBenefitGroups(trait,record,benefitProjection);
 const hidden=traitRemovedIds(record,trait);
 const optionList=(options,selected='')=>options.map(([value,label])=>
  '<option value="'+esc(value)+'"'+(String(value)===String(selected)?' selected':'')+'>'+esc(label)+'</option>').join('');
 const formSelect=(label,name,options)=>'<label>'+esc(label)+'<select name="'+name+'">'+optionList(options)+'</select></label>';
 const formInput=(label,name,placeholder='',type='text')=>'<label>'+esc(label)+'<input name="'+name+'" type="'+type+'" placeholder="'+esc(placeholder)+'" required></label>';
 const kinds=BENEFIT_TYPES,draftKind=state.traitPopupDraftKind||'bonus',draftTarget=state.traitPopupDraftTarget||'';
 const targets=[...BONUS_TARGETS,['attack_roll','Tiro per colpire'],['damage_roll','Tiri di danno'],['any_d20','Qualunque d20']];
 const diceTargets=[['ability_check','Prove di caratteristica'],['saving_throw','Tiri salvezza'],['attack_roll','Tiri per colpire'],['damage_roll','Tiri di danno'],['initiative','Iniziativa'],['any_d20','Qualunque d20']];
 for(const choices of [targets,diceTargets])if(draftTarget&&!choices.some(([id])=>id===draftTarget))
   choices.unshift([draftTarget,'Questo tiro · '+draftTarget]);
 const trackerOptions=[['','Nessuno'],...(state.calculated?.trackers||[]).map(t=>[t.id,t.name])];
 const fields=[
  ['bonus',formSelect('Tiro o valore','target',targets).replace('name="target"','name="target" data-trait-target')+
     formInput('Formula','expression','Es. 1 oppure proficiency')],
  ['dice',formSelect('Tipo di tiro','target',diceTargets).replace('name="target"','name="target" data-trait-target')+
     formInput('Dadi','dice','Es. 1d4')+
     formSelect('Tipo di danno (facoltativo)','damage_type',[['','Nessuno'],...DAMAGE_TYPES.map(id=>[id,rollDamageName(id)])])+
     formSelect('Tracker associato','tracker_id',trackerOptions)+
     formInput('Utilizzi consumati','tracker_cost','1','number')],
  ['proficiency',formSelect('Categoria','proficiency_kind',PROFICIENCY_KINDS)+formInput('Competenza','key','Es. perception, firearms, elvish')],
  ['defenses',formSelect('Difesa','rank',DEFENSE_RANKS)+formSelect('Danno o condizione','key',
    [...DAMAGE_TYPES.map(key=>[key,key]),...['blinded','charmed','deafened','frightened','grappled','paralyzed','petrified','poisoned','prone','restrained','stunned','unconscious'].map(key=>[key,key])])],
  ['resources',formInput('Nome risorsa','name')+formInput('Utilizzi massimi','max','Es. 3','number')+
    formSelect('Recupero','recharge',[['manual','Manuale'],['short_rest','Riposo breve'],['long_rest','Riposo lungo'],['turn','Inizio turno'],['d6','Ricarica d6']])],
  ['spells',formSelect('Incantesimo','spell_id',(state.spellCatalog||[]).filter(row=>row.id&&!row.internal_grant)
     .map(row=>[row.id,row.name+' · '+(row.source||'')]))+
     formSelect('Consumo','payment_mode',[['free','Gratuito'],['slot','Slot']])],
  ['actions',formInput('Azione concessa','name')+
     formSelect('Tipo di azione','action_type',[['action','Azione'],['bonus','Azione bonus'],['reaction','Reazione'],['free','Nessun costo']])]
 ];
 const benefits=groups.map(group=>'<section class="trait-benefit-group trait-benefit-group--'+esc(group.type)+'">'+
   '<span class="trait-benefit-kind">'+esc(group.title)+'</span>'+
   group.items.map(item=>group.type==='abilities'?
    '<article class="trait-capability" data-trait-capability="'+esc(item.label)+'">'+
      '<div class="trait-capability-head"><strong>'+esc(item.label)+'</strong>'+
      '<span class="trait-capability-status" data-capability-status="'+esc(item.status||'')+'">'+esc(item.status||'Attivabile')+'</span></div>'+
      '<div class="trait-capability-meta"><span>'+esc(item.timing||'Contestuale')+'</span>'+
        '<span>'+esc(item.cost||'Nessun costo')+'</span></div>'+
      (item.description?'<p class="trait-capability-description">'+esc(item.description)+'</p>':'')+
      (item.requirements?'<p class="trait-capability-requirements"><strong>Requisiti</strong> · '+esc(item.requirements)+'</p>':'')+
      (item.effects?.length?'<ul class="trait-capability-effects">'+item.effects.map(effect=>'<li>'+esc(effect)+'</li>').join('')+'</ul>':'')+
    '</article>':
    '<div class="trait-benefit-manage-row">'+
     '<div class="trait-benefit-entry"><span>'+esc(item.label)+'</span>'+
      (item.value?'<span class="trait-benefit-value">'+esc(sheetRollSymbol(item.value))+'</span>':'')+'</div>'+
     (!trait.readonly&&!['attacks','armor_class','roll_modes','effects','granted_features'].includes(group.type)&&item.id?'<button type="button" class="trait-benefit-remove" data-act="trait-benefits-remove-request" data-benefit-id="'+esc(item.id)+'" data-benefit-type="'+esc(group.type)+'" aria-label="Elimina '+esc(item.label)+'" title="Elimina beneficio">×</button>':'')+
    '</div>').join('')+
   '</section>').join('');
 const confirmId=state.traitPopupConfirm;
 const match=groups.flatMap(group=>group.items.map(item=>({...item,type:group.type}))).find(item=>item.id===confirmId);
 const dialog=document.createElement('dialog');
 dialog.id='trait-benefits-dialog';dialog.className='trait-benefits-dialog';
 dialog.setAttribute('aria-labelledby','trait-benefits-title');
 dialog.innerHTML='<header class="trait-benefits-dialog-head">'+
  '<h2 id="trait-benefits-title">Benefici · '+esc(trait.name)+'</h2>'+
  '<button type="button" class="trait-benefits-close" data-act="trait-benefits-close" aria-label="Chiudi">×</button></header>'+
  '<div class="trait-benefits-dialog-body">'+
   '<div class="trait-activation-control" data-trait-activation>'+
    '<div class="trait-activation-copy"><span class="trait-activation-heading">'+(trait.readonly?'Stato attivo':'Stato del privilegio')+'</span>'+
     '<span class="trait-activation-description">'+(trait.inactive?'Benefici disattivati':'Benefici attivi')+'</span></div>'+
    '<button type="button" class="trait-activation-toggle" role="switch" aria-checked="'+String(!trait.inactive)+'" data-act="'+(trait.readonly?'trait-state-end':'trait-benefits-toggle')+'" aria-label="'+(trait.readonly?'Termina':trait.inactive?'Attiva':'Disattiva')+' '+esc(trait.name)+'">'+
     '<span class="trait-activation-thumb" aria-hidden="true"></span><span class="trait-activation-label">'+(trait.readonly?'Termina':trait.inactive?'Attiva':'Disattiva')+'</span></button>'+
   '</div>'+
   '<div class="trait-benefits">'+(benefits||'<p class="hint">Nessun beneficio concesso da questo tratto.</p>')+'</div>'+
   (match?'<section class="trait-benefit-confirm" role="alert"><p>Eliminare '+esc(match.label)+(match.value?' · '+esc(match.value):'')+'?</p>'+
     '<div class="actions"><button type="button" class="btn danger" data-act="trait-benefits-remove-confirm" data-benefit-id="'+esc(match.id)+'" data-benefit-type="'+esc(match.type)+'">Conferma eliminazione</button>'+
     '<button type="button" class="btn" data-act="trait-benefits-remove-cancel">Annulla</button></div></section>':'')+
   (!trait.readonly&&hidden.length?'<button type="button" class="trait-benefits-restore" data-act="trait-benefits-restore">Ripristina benefici originali ('+hidden.length+')</button>':'')+
   (trait.readonly?'':'<div class="trait-benefits-dialog-actions"><button type="button" class="trait-benefits-add-toggle" data-act="trait-benefits-add" aria-label="Aggiungi beneficio" title="Aggiungi beneficio">＋</button></div>'+
   '<section class="trait-benefits-add-form"'+(state.traitPopupDraftKind?'':' hidden')+' data-trait-add-form>'+
    '<h3>Nuovo beneficio</h3>'+
    formSelect('Tipo di beneficio','benefit_type',kinds).replace('name="benefit_type"','name="benefit_type" data-trait-add-kind').replace('value="'+draftKind+'"','value="'+draftKind+'" selected')+
    fields.map(([kind,html])=>'<div class="trait-benefits-fields" data-trait-fields="'+kind+'"'+(kind===draftKind?'':' hidden')+'>'+html+'</div>').join('')+
    '<div class="actions"><button type="button" class="btn primary" data-act="trait-benefits-save">Salva beneficio</button>'+
    '<button type="button" class="btn" data-act="trait-benefits-cancel-add">Annulla</button></div>'+
   '</section>')+
  '</div>';
 app.append(dialog);
 if(draftTarget)for(const select of dialog.querySelectorAll('[data-trait-target]'))select.value=draftTarget;
 const trackerCost=dialog.querySelector('[data-trait-fields="dice"] [name="tracker_cost"]');
 if(trackerCost)trackerCost.value='1';
 dialog.addEventListener('cancel',event=>{event.preventDefault();dismissTraitBenefitDialog();});
 dialog.addEventListener('click',event=>{
  if(event.target!==dialog)return;
  const rect=dialog.getBoundingClientRect();
  if(event.clientX<rect.left||event.clientX>rect.right||
     event.clientY<rect.top||event.clientY>rect.bottom)dismissTraitBenefitDialog();
 });
 if(dialog.showModal)dialog.showModal();else dialog.setAttribute('open','');
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
      '</details>':
      '<p class="warning">Definizione homebrew non installata: documento visibile ma non modificabile.</p>')+
    '<div class="document-paper '+(style==="lettera"?'letter':'parchment')+'"><strong>'+esc(title)+'</strong><p>'+esc(body)+'</p></div>'+
    '<div class="actions"><button type="button" class="btn small danger" data-act="document-remove" data-index="'+index+'">Elimina copia</button></div>'+
    '</div></details>';
}
function infusionPanel(c,calculated){
 const caps=infusionLimits(c,calculated.infusion_mechanics,calculated.features||[]);
 if(!caps.level)return "";
 const trait=infusionGrantingTrait(c,calculated.features||[]);
 const definitions=calculated.infusion_catalog||[],known=learnedInfusions(c,definitions);
 const prepared=known.filter(row=>isInfusionPrepared(c,row,definitions));
 const active=(c.inventory||[]).map((item,index)=>({item,index}))
   .filter(({item})=>Number(item.quantity??1)>0&&item.infusion?.creator_id===c.id);
 const available=definitions.filter(row=>caps.level>=Math.max(2,Number(row.min_level)||2)&&
   (row.application_kind==='replicate'||!known.some(entry=>entry.id===row.id)))
   .sort((a,b)=>Number(a.min_level||2)-Number(b.min_level||2)||
     String(a.name).localeCompare(String(b.name),'it'));
 const choices=(id,entries)=>'<select id="'+id+'">'+entries.map(([key,label])=>
   '<option value="'+esc(key)+'">'+esc(label)+'</option>').join('')+'</select>';
 const optionsByLevel=[...new Set(available.map(row=>Math.max(2,Number(row.min_level)||2)))].map(level=>
   '<optgroup label="Livello '+level+'">'+available.filter(row=>Math.max(2,Number(row.min_level)||2)===level)
     .map(row=>'<option value="'+esc(row.id)+'">'+esc(row.name)+'</option>').join('')+'</optgroup>').join('');
 const summary='<div class="infusion-overview"><strong>Conosciute '+known.length+' / '+caps.known+
   '</strong><span>Preparate '+prepared.length+' / '+caps.active+'</span>'+
   '<span>Applicate '+active.length+' / '+caps.active+'</span></div>';
 const levels=[...new Set(known.map(row=>Math.max(2,Number(row.min_level)||2)))].sort((a,b)=>a-b);
 const learned=levels.map(level=>'<section class="infusion-level"><div class="magic-level-heading"><h4>Livello '+level+'</h4></div>'+
   known.map((entry,index)=>({entry,index})).filter(({entry})=>Math.max(2,Number(entry.min_level)||2)===level)
   .map(({entry,index})=>{
     const ready=isInfusionPrepared(c,entry,definitions);
     const applied=active.filter(({item})=>item.infusion?.id===entry.id&&
       (entry.plan_item_id?item.infusion?.plan_item_id===entry.plan_item_id:true));
     return '<div class="magic-spell-row infusion-entry"><span class="magic-spell-open">'+esc(entry.name)+
       (entry.plan_item_name?'<small>'+esc(entry.plan_item_name)+'</small>':'')+
       '<small class="infusion-status">'+(applied.length?'Applicata a '+esc(applied.map(({item})=>item.name||item.id).join(', ')):
         ready?'Preparata':'Conosciuta · non preparata')+'</small></span>'+
       '<button type="button" class="btn small" data-act="infusion-prepare" data-index="'+index+
         '" aria-label="'+(ready?'Rimuovi preparazione':'Prepara')+' '+esc(entry.name)+'">'+
         (ready?'Non preparare':'Prepara')+'</button>'+
       (ready?'<button type="button" class="btn small" data-act="infusion-start" data-index="'+index+
         '" aria-label="Applica '+esc(entry.name)+' a un oggetto">Applica</button>':'')+
       '<button type="button" class="btn small" data-act="infusion-forget" data-index="'+index+
         '" aria-label="Dimentica '+esc(entry.name)+'">×</button></div>'+
       applied.map(({item,index:itemIndex})=>'<div class="infusion-equipped"><span>'+esc(item.name||item.id)+
         ' · '+(item.equipped||item.attuned||(item.equipped_slots||[]).length?'In uso':'Non equipaggiato')+'</span>'+
         '<button type="button" class="btn small" data-act="infusion-clear" data-index="'+itemIndex+'">Rimuovi infusione</button></div>').join('');
   }).join('')+'</section>').join('')||'<p class="hint">Nessuna infusione conosciuta. Imparane una dal catalogo.</p>';
 const selected=known[state.infusionPending];
 const targets=selected?compatibleInfusionTargets(c,selected,definitions,calculated.features||[]):[];
 const targetPicker=selected?'<section class="infusion-target-picker"><h3>Applica '+esc(selected.name)+'</h3>'+
   '<p class="hint">Scegli un oggetto compatibile. I benefici funzionano quando è equipaggiato e, se necessario, in sintonia.</p>'+
   (targets.length?'<label>Oggetto bersaglio'+choices('infusion-item',targets.map(({item,index})=>[index,item.name||item.id]))+
      '</label><div class="actions">'+btn('infusion-confirm','Conferma','primary')+
      btn('infusion-cancel','Annulla')+'</div>':
      '<p class="warning">Nessun oggetto compatibile. Controlla tipo, rarità, equipaggiamento ed eventuali infusioni già applicate.</p>'+btn('infusion-cancel','Chiudi'))+'</section>':'';
 const learnForm=available.length?'<div class="infusion-learning"><h3>Impara un’infusione</h3>'+
   '<label>Infusioni disponibili<select id="infusion-available">'+optionsByLevel+'</select></label>'+
   '<details class="infusion-replication"><summary>Oggetto per Replicate Magic Item</summary>'+
      '<p class="hint">Scegli un oggetto magico replicabile dall’inventario solo se impari Replicate Magic Item.</p>'+
      '<label>Oggetto'+choices('infusion-plan',(c.inventory||[]).map((item,index)=>[index,item.name||item.id]))+
      '</label></details>'+btn('infusion-learn','Impara','primary')+'</div>':
   '<p class="hint">Non ci sono nuove infusioni disponibili per questo livello.</p>';
 return panel('Infusioni',summary+
   (!trait?'<p class="warning">Il tratto Infuse Item non è disponibile o è disattivato.</p>':
     '<p class="hint">Impara → Prepara → Applica a un oggetto. L’effetto è legato al tratto e all’oggetto infuso, non alla classe.</p>'+
      learned+learnForm+targetPicker)+
   (known.length>caps.known?'<p class="warning">Infusioni conosciute oltre il massimo consigliato: '+known.length+' / '+caps.known+'.</p>':'')+
   (prepared.length>caps.active?'<p class="warning">Infusioni preparate oltre il massimo di oggetti infondibili: '+prepared.length+' / '+caps.active+'.</p>':'')+
   (definitions.length?'':'<p class="warning">Indice delle infusioni non caricato.</p>'));
}

const INVENTORY_PROPERTY_LABELS={
  F:"Accurata",L:"Leggera",T:"Lancio",V:"Versatile",H:"Pesante",
  "2H":"Due mani",A:"Munizioni",R:"Portata",LD:"Caricamento",RLD:"Ricarica"
};
const INVENTORY_RARITIES={
  common:"Comune",uncommon:"Non comune",rare:"Raro","very rare":"Molto raro",
  legendary:"Leggendario",artifact:"Artefatto",varies:"Variabile"
};
// Search the spell library, not the item compendium, when creating scrolls.
function scrollSpellCandidates(query=''){
  const value=String(query||'').trim().toLocaleLowerCase('it');
  if(value.length<2)return [];
  const edition=state.editor?.read()?.rules_version||'2014';
  return spellsForEdition(state.spellCatalog||[],edition)
    .filter(spell=>spell?.id&&spell?.name&&!spell.internal_grant&&
      Number.isInteger(Number(spell.level))&&Number(spell.level)>=0&&Number(spell.level)<=9&&
      (String(spell.name).toLocaleLowerCase('it').includes(value)||
       String(spell.source||'').toLocaleLowerCase('it').includes(value)))
    .sort((a,b)=>String(a.name).localeCompare(String(b.name),'it')||
      String(a.source||'').localeCompare(String(b.source||''),'it')).slice(0,80);
}
function scrollSpellSelectOptions(query=''){
  const candidates=scrollSpellCandidates(query);
  const lead=String(query).trim().length<2?'Scrivi almeno 2 lettere':
    candidates.length?'Seleziona un incantesimo':'Nessun incantesimo trovato';
  return '<option value="">'+esc(lead)+'</option>'+
    candidates.map(spell=>'<option value="'+esc(spell.id)+'">'+
      esc(spell.name)+' · '+esc(Number(spell.level)===0?'Trucchetto':spell.level+'°')+
      (spell.source?' · '+esc(spell.source):'')+'</option>').join('');
}
function scrollSpellLevelOptions(spell){
  if(!spell)return '<option value="">Scegli prima un incantesimo</option>';
  const base=Number(spell.level);
  return Array.from({length:base===0?1:10-base},(_,i)=>base+i).map(level=>
    '<option value="'+level+'">'+(level===0?'Trucchetto':level+'° livello')+'</option>').join('');
}
function scrollSpellCreatorView(){
  const ready=Array.isArray(state.spellCatalog)&&state.spellCatalog.length>0;
  return '<div class="scroll-creator-fields">'+
    '<label>Incantesimo<input id="scroll-spell-query" type="search" autocomplete="off" placeholder="Cerca incantesimo…" value="'+esc(state.scrollSpellQuery)+'"></label>'+
    '<label>Selezione<select id="scroll-spell-select" aria-label="Incantesimo per la pergamena"'+(ready?'':' disabled')+'>'+
      scrollSpellSelectOptions(state.scrollSpellQuery)+'</select></label>'+
    '<label>Livello pergamena<select id="scroll-spell-level" aria-label="Livello della pergamena">'+scrollSpellLevelOptions(null)+'</select></label>'+
    '<div class="actions"><button type="button" class="btn primary" data-act="scroll-spell-add"'+(ready?'':' disabled')+'>Aggiungi pergamena</button></div>'+
    (ready?'':'<p class="warning">Elenco incantesimi non disponibile offline.</p>')+
    '</div>';
}
function updateScrollSpellLevels(){
  const select=app.querySelector('#scroll-spell-select');
  const level=app.querySelector('#scroll-spell-level');
  if(!level||!select)return;
  const spell=spellsForEdition(state.spellCatalog||[],state.editor?.read()?.rules_version)
    .find(row=>String(row.id)===select.value);
  level.innerHTML=scrollSpellLevelOptions(spell);
  level.disabled=!spell;
}
function inventoryProperties(item={}){
  const obj=resolveOwnedItem(item),kind=itemKind(obj),parts=[];
  if(kind==="weapon"){
    for(const raw of Array.isArray(obj.properties)?obj.properties:[])
      parts.push(INVENTORY_PROPERTY_LABELS[String(raw).split("|")[0].toUpperCase()]||String(raw));
  }
  if(kind==="armor"||kind==="shield"){
    const ac=obj.ac;
    if(kind==="shield")parts.push("CA +"+(typeof ac==="number"?ac:2));
    else if(ac != null && (typeof ac!=="object"||ac.base != null))
      parts.push("CA "+(typeof ac==="object"?ac.base:ac));
  }
  const rarity=String(obj.rarity||"").trim().toLowerCase();
  if(rarity&&rarity!=="none")parts.push(INVENTORY_RARITIES[rarity]||obj.rarity);
  return parts.join(" · ")||"—";
}
function inventoryGold(item){
  const obj=resolveOwnedItem(item),qty=Math.max(1,Number(item.quantity)||1);
  const gp=Number.isFinite(Number(obj.value_gp))&&obj.value_gp!==undefined?Number(obj.value_gp):
    obj.value!==undefined?Number(obj.value)/100:NaN;
  return Number.isFinite(gp)?Number((gp*qty).toFixed(2)).toLocaleString("it-IT"):"—";
}
function inventoryEquipmentView(c,calculated={}){
  const inventory=Array.isArray(c.inventory)?c.inventory:[];
  const labels=[["main","Mano principale"],["off","Mano secondaria"],["body","Armatura"]];
  const mainRow=inventory.find(item=>Array.isArray(item?.equipped_slots)&&item.equipped_slots.includes("main"));
  const main=mainRow?resolveOwnedItem(mainRow):null;
  const versatile=main&&itemKind(main)==="weapon"&&hasProperty(main,"V");
  const blocked=Boolean(main&&(hasProperty(main,"2H")||(versatile&&c.hand_grip_two_handed)));
  const rows=labels.map(([slot,label])=>{
    const selected=blocked&&slot==="off"?-1:
      inventory.findIndex(item=>Array.isArray(item.equipped_slots)&&item.equipped_slots.includes(slot));
    const special=blocked&&slot==="off"?"none":
      slot==="body"?"none":String(c["hand_"+slot+"_special"]||"none");
    const options=[[-1,slot==="body"?"Nessuna armatura":"Nessuno"],
      ...(slot==="body"?[]:[["unarmed","Colpo senz’armi"],["improvised","Arma improvvisata"]]),
      ...inventory.map((item,index)=>validSlot(item,slot)&&!(slot==="main"&&itemKind(item)==="shield")?
        [index,item.name||"Oggetto"]:null).filter(Boolean)];
    const selector='<select aria-label="'+esc(label)+'" data-equip-slot="'+slot+'"'+
      (slot==="off"&&blocked?' disabled':'')+'>'+
      options.map(([value,name])=>'<option value="'+value+'"'+
      ((selected>=0&&value===selected||selected<0&&(value===special&&special!=="none"||value===-1&&special==="none"))?' selected':'')+'>'+
      esc(name)+'</option>').join('')+'</select>';
    const weapon=inventory[selected],isWeapon=weapon&&itemKind(weapon)==="weapon";
    const size=slot==="body"?'':('<select aria-label="Taglia arma '+esc(label)+'" '+
      'data-slot-weapon-size="'+slot+'"'+(isWeapon?'':' disabled')+'>'+
      [['','Creatura ('+esc(c.size_name||"Medium")+')'],...WEAPON_SIZES.map(v=>[v,v])].map(([v,name])=>
        '<option value="'+esc(v)+'"'+((weapon?.instance_overrides?.weapon_size||'')===v?' selected':'')+'>'+
        esc(name)+'</option>').join('')+'</select>');
    return '<div class="inventory-slot-row"><span>'+esc(label)+'</span>'+selector+size+'</div>';
  });
  const wornRow=inventory.find(item=>Array.isArray(item?.equipped_slots)&&item.equipped_slots.includes("body")&&itemKind(item)==="armor");
  const armor=wornRow?resolveOwnedItem(wornRow):null;
  const shields=inventory.filter(item=>Array.isArray(item?.equipped_slots)&&
    item.equipped_slots.some(slot=>slot==="main"||slot==="off")&&itemKind(item)==="shield")
    .map(resolveOwnedItem);
  const shieldBonus=shields.reduce((value,item)=>Math.max(value,Number(item.ac)||0),0);
  const dex=Number(calculated.values?.["ability_mod:dex"]??0);
  const armorType=String(armor?.type||"").split("|")[0].toUpperCase();
  const dexCap=armor?.dexterity_max!==undefined?Number(armor.dexterity_max):armorType==="MA"?2:armorType==="HA"?0:99;
  const armorDex=armorType==="HA"&&Number(armor?.dexterity_max)===0?0:Math.min(dex,dexCap);
  const rawMonsterAc=Array.isArray(c.stat_block?.ac)?
    c.stat_block.ac.find(row=>typeof row==="number"||row?.ac!==undefined):c.stat_block?.ac;
  const monsterAc=typeof rawMonsterAc==="object"?rawMonsterAc?.ac:rawMonsterAc;
  const naturalBase=c.kind==="monster"?(monsterAc??10):(c.armor_class_base??10);
  const naturalFormula=String(c.armor_natural_formula||
    ((c.kind==="character"&&Number(naturalBase)===10)?"10 + dex_mod":String(naturalBase)));
  const formula=armor?
    String(Number(armor.ac)||10)+(armorDex?' + ('+armorDex+' DES)':'')+
      (shieldBonus?' + '+shieldBonus+' scudo':''):
    naturalFormula+(shieldBonus?' + '+shieldBonus+' scudo':'');
  const attackSettings='<div class="equipment-attack-options">'+
    '<label class="equipment-attack-ability">Caratteristica attacchi<select data-field="attack_ability">'+
      [['str','Forza'],['dex','Destrezza'],['con','Costituzione'],['int','Intelligenza'],['wis','Saggezza'],['cha','Carisma']].map(([value,label])=>
        '<option value="'+value+'"'+((c.attack_ability||"str")===value?' selected':'')+'>'+label+'</option>').join('')+
    '</select></label>'+
    '<label class="check"><input type="checkbox" data-field="attack_ability_finesse_only"'+
      (c.attack_ability_finesse_only!==false?' checked':'')+'>Usa solo per armi accurate</label>'+
    (versatile?'<label class="check"><input type="checkbox" data-field="hand_grip_two_handed"'+
      (c.hand_grip_two_handed?' checked':'')+'>Due mani (Versatile)</label>':'')+
    '</div>';
  const defense='<div class="equipment-defense">'+
    '<div class="battle-defense-values"><div class="battle-stat"><span>CA totale</span>'+
      formulaReadout(calculated,'ac','Classe armatura',{showBonus:false})+'</div></div>'+
    '<div class="battle-ac-formula"><strong>'+(armor?'Formula armatura indossata':'Formula CA naturale')+
      '</strong><output>'+esc(formula)+'</output></div>'+

    '</div>';
  return panel("Equipaggiamento",
    '<section class="equipment-weapons"><h3>Armi</h3>'+
      '<div class="inventory-slots">'+rows.slice(0,2).join('')+'</div>'+attackSettings+'</section>'+
    '<section class="equipment-armor"><h3>Armatura</h3>'+
      '<div class="inventory-slots">'+rows[2]+'</div>'+defense+'</section>',
    "inventory-native-panel inventory-equipment equipment-unified-panel");
}
const COIN_LABELS=[["cp","Rame"],["sp","Argento"],["ep","Elettro"],["gp","Oro"],["pp","Platino"]];
function inventoryCoinsView(c){
  const coins=c.coins&&typeof c.coins==="object"&&!Array.isArray(c.coins)?c.coins:{};
  const units=COIN_LABELS.map(([code,label])=>{
    const value=Number(coins[code]??0);
    const count=Number.isSafeInteger(value)&&value>=0?value:0;
    return '<label class="inventory-coin"><span title="'+label+'">'+code.toUpperCase()+'</span>'+
      '<input type="number" min="0" max="999999999" step="1" data-coin-code="'+code+
      '" aria-label="'+label+'" value="'+count+'"></label>';
  }).join('');
  const copper=COIN_LABELS.reduce((sum,[code],i)=>{
    const value=Number(coins[code]??0);
    return sum+(Number.isSafeInteger(value)&&value>=0?value:0)*[1,10,50,100,1000][i];
  },0);
  return panel("Monete possedute",'<div class="inventory-coin-grid">'+units+'</div>'+
    '<p class="inventory-coin-total">Equivalente: '+
    esc((copper/100).toLocaleString("it-IT",{maximumFractionDigits:2}))+' mo</p>',
    "inventory-native-panel inventory-coins-panel");
}
function inventoryAttunementView(c,entries){
  const max=Math.max(0,Math.min(99,Number(c.attunement_max_base??3)||0));
  const active=entries.filter(({item})=>item.attuned===true).length;
  const lines=entries.map(({item,index})=>
    '<label class="inventory-attunement-row"><input type="checkbox" data-item-index="'+index+
    '" data-item-key="attuned"'+(item.attuned?' checked':'')+'><span>'+esc(item.name||"Oggetto")+
    '</span></label>').join('');
  return panel("Oggetti che richiedono sintonia",
    '<div class="inventory-attunement-meta"><span>Sintonia '+active+'/'+max+' · Base</span>'+
    '<input type="number" aria-label="Massimo sintonia base" data-inventory-attunement-max min="0" max="99" value="'+max+'"></div>'+
    (lines||'<p class="hint">Nessun oggetto richiede sintonia.</p>'),
    "inventory-native-panel inventory-attunement");
}
function inventoryTable(entries,scrolls,selectedIndex,menuIndex){
  if(!entries.length)return '<p class="hint">Nessun '+(scrolls?'incantesimo su pergamena.':'oggetto.')+'</p>';
  const headings=scrolls?["Qtà","Livello","Incantesimo"]:["Eq.","mo","Peso","Qtà","Fonte","Proprietà / CA","Nome"];
  return '<div class="inventory-table" role="table" aria-label="'+(scrolls?'Pergamene':'Oggetti')+'">'+
    '<div class="inventory-table-head" role="row">'+headings.map((x,i)=>
      '<span class="inventory-col-'+(scrolls?["quantity","level","name"][i]:
        ["equip","value","weight","quantity","source","property","name"][i])+'" role="columnheader">'+x+'</span>').join('')+'</div>'+
    entries.map(({item,index})=>{
      const kind=itemKind(item),slots=Array.isArray(item.equipped_slots)?item.equipped_slots:[],
        canEquip=kind!=="document",
        eqIcon=canEquip?((item.equipped||slots.length)?"✓":""):(slots.includes("main")?"⚔":"")+
          (slots.includes("off")?"🛡":"")+(slots.includes("body")?"▣":""),
        qty=Math.max(1,Number(item.quantity)||1),
        controls='<div class="inventory-quantity-controls">'+
        '<button type="button" class="inventory-qty-btn" data-act="inventory-quantity" data-index="'+index+
        '" data-delta="'+(qty===1?'-1':'-1')+'" aria-label="'+(qty===1?"Rimuovi oggetto":"Diminuisci quantità")+'">'+(qty===1?"×":"−")+'</button>'+
        '<input type="number" aria-label="Quantità '+esc(item.name)+'" min="0" max="99999" '+
        'data-item-index="'+index+'" data-item-key="quantity" value="'+qty+'">'+
        '<button type="button" class="inventory-qty-btn" data-act="inventory-quantity" data-index="'+index+
        '" data-delta="1" aria-label="Aumenta quantità">+</button></div>',
        displayName=scrolls?spellScrollName(item):item.name||"Oggetto",
        name=isCatalogItem(item)?'<strong>'+esc(displayName)+'</strong>':
          '<input class="inventory-item-name-input" aria-label="Nome oggetto" data-item-index="'+index+
          '" data-item-key="name" value="'+esc(item.name||"")+'">',
        nameCell='<span class="inventory-col-name">'+
          '<button type="button" class="inventory-select" data-act="inventory-select" data-index="'+index+
          '" aria-label="Mostra descrizione di '+esc(item.name)+'">'+(isCatalogItem(item)?name:scrolls?esc(displayName):'Dettagli')+'</button>'+
          (isCatalogItem(item)?'':name)+
          (scrolls?'':'<small class="inventory-mobile-properties">'+esc(inventoryProperties(item))+'</small>')+
          '<button type="button" class="inventory-more" data-act="inventory-menu" data-index="'+index+
          '" aria-label="Opzioni '+esc(item.name)+'" aria-expanded="'+(menuIndex===index)+'">⋯</button>'+
          (menuIndex===index?'<span class="inventory-context-actions">'+
             '<button type="button" class="btn small danger" data-act="remove-item" data-index="'+index+'">Rimuovi</button>'+
             '<button type="button" class="btn small" data-act="inventory-view-catalog" data-index="'+index+'">Vedi nel bestiario</button></span>':'')+'</span>',
        equip='<span class="inventory-col-equip">'+(scrolls?'':canEquip?
          '<button type="button" class="inventory-equip-toggle'+((item.equipped||slots.length)?' is-equipped':'')+'" data-act="inventory-equip" data-index="'+index+
          '" title="'+((item.equipped||slots.length)?'Disequipaggia':'Equipaggia')+'" aria-label="'+((item.equipped||slots.length)?"Disequipaggia":"Equipaggia")+' '+esc(item.name)+'" aria-pressed="'+
          Boolean(item.equipped||slots.length)+'"><span class="inventory-equip-mark" aria-hidden="true">'+eqIcon+'</span></button>':
          '<span class="inventory-slotted-icon">'+(eqIcon||'')+'</span>')+'</span>';
      const cells=scrolls?[
        '<span class="inventory-col-quantity">'+controls+'</span>',
        '<span class="inventory-col-level">'+esc(spellScrollLevel(item))+'</span>',nameCell]:
        [equip,'<span class="inventory-col-value">'+esc(inventoryGold(item))+'</span>',
        '<span class="inventory-col-weight">'+esc(item.weight!==undefined?(Number(item.weight)*qty)+' lb':'—')+'</span>',
        '<span class="inventory-col-quantity">'+controls+'</span>',
        '<span class="inventory-col-source">'+esc(item.source||'')+'</span>',
        '<span class="inventory-col-property" title="'+esc(inventoryProperties(item))+'">'+esc(inventoryProperties(item))+'</span>',nameCell];
      return '<div class="inventory-table-row'+(index===selectedIndex?' selected':'')+
        (item.attuned?' attuned':'')+'" role="row" data-inventory-row="'+index+'">'+cells.join('')+'</div>';
    }).join('')+'</div>';
}
function inventoryItemDescription(obj,index){
  const info=inventoryReadout(obj,inventoryProperties(obj),isSpellScroll(obj));
  const pairs=[['Tipo',info.type],...(obj.source?[['Fonte',String(obj.source)]]:[]),
    ...(obj.rarity&&obj.rarity!=='none'?[['Rarità',INVENTORY_RARITIES[String(obj.rarity).toLowerCase()]||obj.rarity]]:[]),
    ...info.facts.map(fact=>[fact.label,fact.value]),...(info.status.length?[['Stato',info.status.join(' · ')]]:[])];
  const properties=inventoryReadout(obj,inventoryProperties({...obj,rarity:''}),isSpellScroll(obj)).properties||"—";
  const prose=flattenDescription(obj)||String(obj.description||'');
  const localEdit=!isCatalogItem(obj)?'<label>Descrizione<textarea data-item-index="'+index+
    '" data-item-key="description" rows="3">'+esc(obj.description||"")+'</textarea></label>':'';
  const overrides=itemKind(obj)==="weapon"?'<details class="inventory-overrides"><summary>Personalizza copia</summary>'+
    [['damage','Dadi danno'],['versatile_damage','Danno versatile'],['range','Gittata (ft)'],['bonus_weapon','Bonus magico']].map(([key,label])=>
      '<label>'+label+'<input data-item-override="'+key+'" data-item-index="'+index+
      '" value="'+esc(obj.instance_overrides?.[key]??'')+'"></label>').join('')+'</details>':
    ["armor","shield"].includes(itemKind(obj))?'<details class="inventory-overrides"><summary>Personalizza CA</summary>'+
    [['ac','CA base'],['bonus_ac','Bonus CA']].map(([key,label])=>'<label>'+label+
    '<input data-item-override="'+key+'" data-item-index="'+index+'" value="'+esc(obj.instance_overrides?.[key]??'')+'"></label>').join('')+
    '</details>':'';
  return '<div class="inventory-description">'+
    '<dl class="inventory-detail-facts">'+pairs.map(([label,value])=>'<div><dt>'+esc(label)+'</dt><dd>'+esc(value)+'</dd></div>').join('')+'</dl>'+
    (properties!=='—'?'<section class="inventory-detail-section"><h3>Proprietà</h3><p>'+esc(properties)+'</p></section>':'')+
    (localEdit?localEdit:prose?'<section class="inventory-detail-section"><h3>Descrizione</h3><div class="inventory-prose">'+esc(prose)+'</div></section>':'<p class="hint">Nessuna descrizione disponibile nel catalogo locale.</p>')+overrides+'</div>';
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
// All prepared lists share the same spell/pact resource projection.  A single
// click consumes one slot; recovery and maximum editing live in the tools popup.
function magicSlotSummary(calculated=state.calculated){
 const levels=new Map();
 for(const slot of calculated?.spell_slots||[]){
  if(Number(slot.total)>0)levels.set(Number(slot.level),{classSlot:slot,pact:null});
 }
 const pact=calculated?.pact_slots;
 if(pact&&Number(pact.total)>0&&Number(pact.level)>0){
  const lvl=Number(pact.level);
  const entry=levels.get(lvl)||{classSlot:null,pact:null};
  entry.pact=pact;levels.set(lvl,entry);
 }
 return levels;
}
function magicLevelSlotChip(level,slot,pact=false){
 const total=Math.max(0,Number(slot.total)||0),spent=Math.max(0,Number(slot.spent)||0);
 const remaining=Math.max(0,total-spent);
 return '<button type="button" class="magic-level-slot" data-act="slot-use" data-level="'+(pact?0:level)+'" '+
   (remaining===0?'disabled':'')+' title="'+(pact?'Patto':'Slot')+': consuma un utilizzo; recupera nelle impostazioni"'+
   ' aria-label="'+(pact?'Patto':'Slot livello '+level)+': '+remaining+' di '+total+' rimanenti; tocca per consumare">'+
   (pact?'<span class="magic-pact-icon" aria-hidden="true">✦</span>':'')+
   '<strong data-slot-remaining="'+(pact?'pact':level)+'">'+remaining+'</strong><span> / '+total+'</span></button>';
}
function magicToolbar(calculated){
 const actions=[
  ['concentration','condition','Concentrazione'],
  ['slots','reset','Slot e risorse di lancio'],
  ['book','book','Libro degli incantesimi'],
  ['catalog','search','Aggiungi incantesimi'],
  ['choices','settings','Scelte dalle origini']
 ];
 return '<details class="magic-utility-menu archive-tools"><summary>Gestisci poteri e incantesimi</summary><nav class="magic-toolbar" aria-label="Strumenti degli incantesimi">'+
   actions.map(([key,icon,label])=>'<button type="button" class="magic-tool-button" data-act="magic-tool-open" data-magic-tool="'+key+
    '" aria-label="'+esc(label)+'" title="'+esc(label)+'" aria-haspopup="dialog" aria-expanded="'+(state.magicPopup===key?'true':'false')+'">'+
    actionGlyph(icon)+'<span>'+esc(label)+'</span></button>').join('')+
   '<button type="button" class="magic-tool-button" data-act="sheet" data-sheet="info" aria-label="Apri tratti per gestire gli incantesimi dalle origini" title="Apri i tratti">'+actionGlyph('proficiency')+'<span>Gestisci incantesimi dalle origini</span></button>'+
   '</nav></details>';
}
function magicToolsDialog(c,calculated){
 const kind=state.magicPopup;
 if(!kind)return '';
 const concentration='<div class="magic-concentration"><span>'+esc((c.conditions||[]).includes('concentrating')?
   c.concentrating_spell_id||'Attiva':'Nessuna')+'</span>'+
   ((c.conditions||[]).includes('concentrating')?btn('stop-concentration','Interrompi','small'):'')+'</div>';
 const slots='<div class="slot-table magic-slots-editor"><strong>Liv.</strong><strong>Classi</strong><strong>Patto</strong>'+
   (calculated.spell_slots||[]).map(slot=>{
     const level=Number(slot.level),pact=calculated.pact_slots;
     return '<span>'+level+'°</span><div>'+
       '<span class="magic-slot-readout">'+esc(Math.max(0,slot.total-slot.spent))+' / '+esc(slot.total)+'</span>'+
       '<label>Usati<input type="number" min="0" max="99" data-slot="'+level+'" value="'+esc(c.spell_slots_spent?.[level]||0)+'"></label>'+
       '<details><summary>Massimo base</summary><input type="number" min="0" max="99" data-slot-total="'+level+'" value="'+esc(slot.base)+'"></details>'+
       '</div><div>'+(pact.level===level?'<span class="magic-slot-readout">'+
          esc(Math.max(0,pact.total-pact.spent))+' / '+esc(pact.total)+'</span>':'—')+'</div>';
   }).join('')+'</div>'+
   '<details class="magic-slot-settings"><summary>Impostazioni slot</summary><p class="hint">'+
   ((c.spell_slots_manual||!c.spell_slots_automatic&&c.spell_slots_total?.some(n=>n>0))?'Massimi personalizzati':'Progressione automatica dalle classi')+'</p>'+
   btn('slots-automatic','Usa progressione automatica')+
   '<label>Massimo base del Patto<input type="number" min="0" max="99" data-pact-total value="'+esc(calculated.pact_slots.base)+'"></label>'+
   field('Slot del Patto usati','pact_slots_spent',c.pact_slots_spent??0,'number','min="0" max="99"')+
   field('Livello slot del Patto','pact_slot_level',c.pact_slot_level??calculated.pact_slots.level,'number','min="1" max="9"')+
   '</details><div class="actions">'+btn('slots-restore','Ripristina tutti gli slot')+'</div>';
 const selectedMember=calculated.casting_classes.find(member=>member.id===state.spellClass);
 const selectedTarget=(!selectedMember||selectedMember.book)&&state.spellTarget==='spellbook_spells'?'spellbook_spells':'prepared_spells';
 const catalog='<label>Classe / origine<select id="spell-class"><option value="manual">Altre concessioni</option>'+
   calculated.casting_classes.map(member=>'<option value="'+esc(member.id)+'" '+(member.id===state.spellClass?'selected':'')+'>'+esc(member.name)+'</option>').join('')+
   '</select></label><label>Destinazione<select id="spell-target">'+
   '<option value="prepared_spells"'+(selectedTarget==='prepared_spells'?' selected':'')+'>'+
   esc(selectedMember?.mode==='Preparati'?'Incantesimi preparati':selectedMember?'Incantesimi conosciuti':'Incantesimi disponibili')+'</option>'+
   (!selectedMember||selectedMember.book?'<option value="spellbook_spells"'+(selectedTarget==='spellbook_spells'?' selected':'')+'>Libro degli incantesimi</option>':'')+
   '</select></label>'+
   (selectedMember?'<p class="magic-selection-summary">'+esc(selectedMember.name)+' · '+
     (selectedMember.mode==='Preparati'?'Preparati':'Conosciuti')+' '+classSelectionCount(c,selectedMember,calculated.casting_classes,state.spellCatalog||[]).leveled+
     ' / '+(selectedMember.limit<0?'—':selectedMember.limit)+'</p>'+
     spellSelectionWarning(selectedMember,classSelectionCount(c,selectedMember,calculated.casting_classes,state.spellCatalog||[])):'')+
   '<section class="magic-selection-current"><h3>'+esc(selectedTarget==='spellbook_spells'?'Nel libro':selectedMember?.mode==='Preparati'?'Preparati':'Conosciuti / disponibili')+'</h3>'+
   spellList(c,selectedTarget,selectedMember?.id||null,calculated.casting_classes,{includeSlots:false})+'</section>'+
   '<label>Cerca incantesimo<input id="spell-search" type="search" value="'+esc(state.spellQuery)+'" placeholder="Nome o fonte"></label>'+
   (state.spellCatalogError?'<p class="warning">'+esc(state.spellCatalogError)+'</p>':'')+
   '<div id="spell-results" class="catalog-results">'+renderSpellResults()+'</div>';
 const views={
  concentration:['Concentrazione',concentration],
  slots:['Slot · Classi / Patto',slots],
  book:['Libro degli incantesimi',spellList(c,'spellbook_spells',null,calculated.casting_classes)],
  catalog:['Gestisci incantesimi',catalog],
  choices:['Scelte dalle origini',originChoicesView(calculated)||'<p class="hint">Nessuna scelta di incantesimi in sospeso.</p>']
 };
 if(!views[kind])return '';
 const [title,content]=views[kind];
 return '<dialog id="magic-tools-dialog" class="sheet-roll-dialog magic-tools-dialog" aria-label="'+esc(title)+'">'+
   '<div class="magic-tools-head"><h2>'+esc(title)+'</h2>'+
   '<button type="button" class="magic-tool-close" data-act="magic-tool-close" aria-label="Chiudi '+esc(title)+'">×</button></div>'+
   '<div class="magic-tools-body">'+content+'</div></dialog>';
}
function magicSpellInfo(row){
  const id=spellId(row);
  const definition=(state.spellCatalog||[]).find(spell=>spell.id===id);
  const record=typeof row==='object'&&row?row:{};
  const rawLevel=definition?.level??record.level;
  const level=rawLevel===undefined||rawLevel===null?null:Number(rawLevel);
  return {id,name:text(definition?.name||record.name||(typeof row==='string'?row:id)),level:Number.isInteger(level)&&level>=0&&level<=9?level:null};
}
function groupedMagicSpells(items,renderRow,{slotSummary=null}={}){
  if(!items.length && !(slotSummary?.size))return '<p class="hint magic-empty">Nessun incantesimo.</p>';
  const ordered=[...items].sort((a,b)=>(a.info.level??10)-(b.info.level??10)||
    a.info.name.localeCompare(b.info.name,'it',{sensitivity:'base'}));
  const groups=new Map();
  for(const item of ordered){
    const level=item.info.level;
    if(!groups.has(level))groups.set(level,[]);
    groups.get(level).push(item);
  }
  for(const level of slotSummary?.keys()||[])if(!groups.has(level))groups.set(level,[]);
  const sorted=[...groups.entries()].sort((a,b)=>(a[0]??10)-(b[0]??10));
  return '<div class="magic-groups">'+sorted.map(([level,entries])=>{
    const slots=slotSummary?.get(level);
    const badges=slots?'<div class="magic-level-slots">'+
      (slots.classSlot?magicLevelSlotChip(level,slots.classSlot):'')+
      (slots.pact?magicLevelSlotChip(level,slots.pact,true):'')+'</div>':'';
    return '<section class="magic-level" data-magic-level="'+esc(level)+'"><div class="magic-level-heading"><h4>'+
      (level===0?'Trucchetti':level===null?'Livello non disponibile':'Livello '+level)+'</h4>'+badges+'</div>'+
      (entries.length?'<div class="magic-entries">'+entries.map(renderRow).join('')+'</div>':'')+'</section>';
  }).join('')+'</div>';
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
function originPowersView(c,calculated,abilitiesList=[],forBattle=false){
 const slots=new Map(),resources=new Map();
 const ensureResource=(key,name,tracker)=>{if(!resources.has(key))resources.set(key,{name,tracker,spells:[],abilities:[]});return resources.get(key);};
 const configured=(grant,info)=>{
   const mode=grant.payment_mode||(grant.tracker_id?'tracker':'free'),cost=Math.max(1,Number(grant.tracker_cost)||1);
   return '<div class="magic-spell-row"><button type="button" class="magic-spell-open" data-act="power-spell" data-spell-key="origin" data-grant-id="'+esc(grant.id)+'" aria-label="Apri '+esc(info.name)+'">'+esc(info.name)+'</button>'+
     '<button type="button" class="btn small" data-act="power-trait" data-origin-id="'+esc(grant.origin_id||'')+'" aria-label="Apri il tratto di '+esc(info.name)+'">↗</button>'+
     (mode==='tracker'?'<span class="hint magic-power-cost">−'+cost+'</span>':'')+
     '<details class="magic-origin-config"><summary aria-label="Configura '+esc(info.name)+'" title="Consumo">⚙</summary>'+
     '<p class="hint">'+(mode==='free'?'Gratuito':mode==='slot'?'Slot incantesimo':'Tracker')+'</p>'+
     '<label>Modalità<select data-origin-config="payment_mode" data-grant-id="'+esc(grant.id)+'">'+[['free','Gratuito'],['slot','Slot incantesimo'],['tracker','Tracker']].map(([value,label])=>'<option value="'+value+'" '+(mode===value?'selected':'')+'>'+label+'</option>').join('')+'</select></label>'+
     '<label>Tracker<select data-origin-config="tracker_id" data-grant-id="'+esc(grant.id)+'"><option value="">Nessuno</option>'+calculated.trackers.map(t=>'<option value="'+esc(t.id)+'" '+(grant.tracker_id===t.id?'selected':'')+'>'+esc(t.name)+'</option>').join('')+'</select></label>'+
     '<label>Costo<input type="number" min="1" max="999" value="'+cost+'" data-origin-config="tracker_cost" data-grant-id="'+esc(grant.id)+'"></label>'+
     (grant.source_choice_id?'<button class="btn small" data-act="origin-choice-remove" data-grant-id="'+esc(grant.id)+'">Cambia scelta</button>':'')+
     '</details></div>';
 };
 const sortGroups=(a,b)=>a[1].name.localeCompare(b[1].name,'it',{sensitivity:'base'});
 // A tracker must have a popup even when it has no spells or activated abilities.
 if(forBattle)for(const tracker of calculated.trackers||[]){
   if(!tracker.disabled)ensureResource('tracker:'+tracker.id,tracker.name,tracker);
 }
 for(const grant of calculated.origin_spells||[]){
   const spell=(state.spellCatalog||[]).find(s=>s.id===grant.spell_id);
   const info=magicSpellInfo(spell||{id:grant.spell_id,name:grant.spell_id});
   const mode=grant.payment_mode||(grant.tracker_id?'tracker':'free');
   const item={grant,spell,info};
   if(mode==='slot'){
     const id=grant.origin_id||'other';
     if(!slots.has(id))slots.set(id,{name:grant.origin_name||'Origine',ability:grant.spellcasting_ability||'int',items:[]});
     slots.get(id).items.push(item);
   }else{
     const tracker=mode==='tracker'?calculated.trackers.find(t=>t.id===grant.tracker_id):null;
     const key=mode==='tracker'?(grant.tracker_id?'tracker:'+grant.tracker_id:'missing'):'free';
     const group=ensureResource(key,tracker?.name|| (mode==='tracker'?'Tracker non disponibile':'Senza consumo'),tracker);
     group.spells.push(item);
   }
 }
 for(const ability of abilitiesList){
   const cost=Math.max(0,Number(ability.resource_cost??(ability.tracker_id?1:0))||0);
   const tracker=cost>0?calculated.trackers.find(t=>t.id===ability.tracker_id):null;
   const key=cost>0?(ability.tracker_id?'tracker:'+ability.tracker_id:'missing'):'free';
   const group=ensureResource(key,tracker?.name||(cost>0?'Tracker non disponibile':'Senza consumo'),tracker);
   if(!group.abilities.some(other=>other.id===ability.id))group.abilities.push(ability);
 }
 const slotPanels=[...slots.entries()].sort(sortGroups).map(([key,group])=>panel('Origine · '+group.name,
   castingStatistics(c,'origin:'+key,group.ability)+
   groupedMagicSpells(group.items,({grant,info})=>configured(grant,info)),'magic-panel')).join('');
 const resourcePanels=[...resources.entries()].sort((a,b)=>a[0]==='free'?1:b[0]==='free'?-1:sortGroups(a,b)).map(([key,group])=>{
   const stats=new Map();
   for(const item of group.spells){
     const origin=item.grant.origin_id||'other';
     if(!stats.has(origin))stats.set(origin,{name:item.grant.origin_name||'Origine',ability:item.grant.spellcasting_ability||'int'});
   }
   const header=(group.tracker?'<section class="power-resource-summary"><span class="power-section-label">Utilizzi disponibili</span><div class="magic-tracker-controls" data-magic-tracker-id="'+esc(group.tracker.id)+'">'+
     '<span class="magic-tracker-count"><strong data-tracker-remaining="'+esc(group.tracker.id)+'">'+
       esc(Math.max(0,Number(group.tracker.max||0)-Number(group.tracker.spent||0)))+'</strong> / '+
       esc(group.tracker.max||0)+'</span>'+
     '<button type="button" class="magic-tracker-change" data-act="tracker-less" data-tracker-id="'+esc(group.tracker.id)+'" aria-label="Recupera un utilizzo di '+esc(group.tracker.name)+'" '+
       (Number(group.tracker.spent||0)<=0?'disabled':'')+'>+1</button>'+
     '<button type="button" class="magic-tracker-change" data-act="tracker-more" data-tracker-id="'+esc(group.tracker.id)+'" aria-label="Consuma un utilizzo di '+esc(group.tracker.name)+'" '+
       (Number(group.tracker.spent||0)>=Number(group.tracker.max||0)?'disabled':'')+'>−1</button></div><p class="power-recovery">Recupero: '+esc(({short_rest:'Riposo breve',long_rest:'Riposo lungo',turn:'Inizio turno',manual:'Manuale',d6:'Ricarica d6'})[group.tracker.recharge]||group.tracker.recharge||'Manuale')+'</p></section>':'');
   const spellRows=group.spells.length?groupedMagicSpells(group.spells,({grant,info})=>configured(grant,info)):'';
   const abilityRows=group.abilities.length?
     '<div class="magic-ability-list">'+
     group.abilities.sort((a,b)=>String(a.name||'').localeCompare(String(b.name||''),'it')).map(ability=>{
       const activation=({action:'Azione',bonus:'Azione bonus',reaction:'Reazione',free:'Azione gratuita',movement:'Movimento',passive:'Passivo',contextual:'Secondo il privilegio'})[ability.action_type||ability.activation_mode]||ability.action_type||ability.activation_mode||'Secondo il privilegio';
       const cost=Math.max(0,Number(ability.resource_cost)||0),resource=ability.tracker_name||ability.resource_name||group.tracker?.name||'';
       return '<details class="magic-ability-entry power-privilege" data-ability-id="'+esc(ability.id)+'"'+(group.abilities.length===1?' open':'')+'><summary><span class="power-privilege-title"><span class="magic-ability-name">'+esc(ability.name)+'</span><span class="power-privilege-meta">'+esc(activation)+(cost?' · '+cost+' per uso':'')+'</span></span><span class="power-privilege-chevron" aria-hidden="true">⌄</span></summary>'+
         '<div class="magic-ability-detail"><dl class="power-privilege-facts"><div><dt>Origine</dt><dd>'+esc(ability.origin_name||ability.origin||'Origine non specificata')+'</dd></div>'+
         (ability.source?'<div><dt>Fonte</dt><dd>'+esc(ability.source)+'</dd></div>':'')+
         '<div><dt>Consumo</dt><dd>'+esc(cost?cost+' utilizzi'+(resource?' · '+resource:' · Risorsa non collegata'):'Nessun consumo di utilizzi')+'</dd></div></dl>'+
         '<div class="power-privilege-description"><h3>Descrizione</h3><p class="trait-description">'+esc(ability.description||'Descrizione non disponibile.')+'</p></div>'+
         '<button type="button" class="play-button power-origin-link" data-act="power-trait" data-origin-id="'+esc(ability.feature_id||ability.origin_id||'')+'">'+actionGlyph('proficiency')+'<span>Apri il tratto di origine</span></button></div></details>';
       }).join('')+'</div>':'';
   const popup=panel(group.name,header+[...stats.entries()].map(([origin,meta])=>
     '<div class="magic-source-ability"><span class="hint">'+esc(meta.name)+'</span>'+
     castingStatistics(c,'origin:'+origin,meta.ability)+'</div>').join('')+
     spellRows+abilityRows,'magic-panel magic-tracker-panel');
   return forBattle?'<div data-battle-power-group="'+esc(key)+'">'+popup+'</div>':popup;
 }).join('');
 return (forBattle?'':slotPanels)+resourcePanels;
}
function originChoicesView(calculated){
 const choices=(calculated.origin_choices||[]).filter(choice=>choice.remaining>0)
   .sort((a,b)=>Number(b.id===state.pendingSpellChoiceId)-Number(a.id===state.pendingSpellChoiceId));
 if(!choices.length)return '';
 return panel('Scelte da origini',choices.map(choice=>{
  const eligible=choice.spell_options?.length?state.spellCatalog||[]:spellsForEdition(state.spellCatalog||[],state.editor.read().rules_version||'2014');
  const offered=eligible.filter(spell=>originChoiceMatches(choice,spell).matches&&!choice.selected.some(selected=>selected.spell_id===spell.id));
  const supported=(state.spellCatalog||[]).some(spell=>originChoiceMatches(choice,spell).supported);
  return '<article class="native-entry pending-spell-choice'+(choice.id===state.pendingSpellChoiceId?' is-target':'')+
   '" data-pending-spell-choice="'+esc(choice.id)+'"><h3>'+esc(choice.origin_name)+' · Scegli ancora '+choice.remaining+'</h3><p class="hint">'+esc(choice.filters?.join(' oppure ')||choice.filter||'Elenco della concessione')+'</p>'+
   (offered.length?'<label>Incantesimo<select data-origin-choice="'+esc(choice.id)+'">'+groupedMagicOptions(offered)+'</select></label><label>Caratteristica<select data-choice-ability="'+esc(choice.id)+'">'+(choice.spellcasting_ability?'':'<option value="">Scegli…</option>')+Object.entries(abilities).map(([key,label])=>'<option value="'+key+'" '+(key===choice.spellcasting_ability?'selected':'')+'>'+label+'</option>').join('')+'</select></label><button class="btn" data-act="origin-choice-pick" data-choice-id="'+esc(choice.id)+'">Conferma scelta</button>':
     '<p class="hint">'+(supported?'Nessun incantesimo disponibile nel catalogo locale per questa concessione.':'Questa concessione richiede un filtro non ancora supportato; la scelta rimane salvata e visibile.')+'</p>')+'</article>';
 }).join(''));
}
function spellList(c,key,classId=null,classes=[],{includeSlots=true}={}) {
  const rows=key==="prepared_spells"?availableSpells(c):
    Array.isArray(c[key])?c[key]:[];
  const visible=rows.map((spell,i)=>({spell,i,info:magicSpellInfo(spell)}))
    .filter(({spell})=>!classId||
      (classId==='manual'?!castingSources(spell,classes,state.spellCatalog||[]).some(id=>classes.some(member=>member.id===id)):
        castingSources(spell,classes,state.spellCatalog||[]).includes(classId)));
  return groupedMagicSpells(visible,({i,info})=>
    '<div class="magic-spell-row"><button type="button" class="magic-spell-open" data-act="power-spell" data-spell-key="'+esc(key)+'" data-spell-index="'+i+'" data-casting-class="'+esc(classId||'')+'" aria-label="Apri '+esc(info.name)+'">'+esc(info.name||'Incantesimo senza nome')+'</button>'+
    '<button type="button" class="btn small magic-remove-spell" data-act="remove-spell" data-key="'+esc(key)+'" data-class-id="'+esc(classId||'')+'" data-index="'+i+'" title="Rimuovi" aria-label="Rimuovi '+esc(info.name)+'">×</button></div>',
    {slotSummary:includeSlots&&key==='prepared_spells'?magicSlotSummary(state.calculated):null});
}
function spellSelectionWarning(member,count){
 const warnings=classSelectionWarnings(member,count);
 return warnings.length?'<p class="magic-selection-warning" role="status">⚠ '+esc(warnings.join(' · '))+'</p>':'';
}
function renderSpellResults(){
  const rows=state.spellCatalog||[],record=state.editor?.read()||{};
  if(!rows.length)return '<p class="hint">Catalogo non disponibile. Gli incantesimi già salvati restano utilizzabili.</p>';
  const query=state.spellQuery.trim().toLocaleLowerCase('it');
  const classes=state.calculated?.casting_classes||[];
  const member=classes.find(row=>row.id===state.spellClass);
  const target=(!member||member.book)&&state.spellTarget==='spellbook_spells'?'spellbook_spells':'prepared_spells';
  if(!member&&!query)return '<p class="hint">Cerca un incantesimo per aggiungerlo alle concessioni della scheda.</p>';
  const prepared=availableSpells(record);
  const knownBook=new Set((record.spellbook_spells||[]).map(spellId));
  const selected=target==='spellbook_spells'?knownBook:
    new Set(prepared.filter(row=>!member||castingSources(row,classes,rows).includes(member.id)).map(spellId));
  const selectedRows=target==='spellbook_spells'?(record.spellbook_spells||[]):prepared;
  const allowed=new Set(spellsForEdition(rows,record.rules_version||'2014'));
  const found=rows.filter(spell=>allowed.has(spell)&&
    (!member||spellEligible(spell,member))&&
    (target!=='spellbook_spells'||Number(spell.level)>0)&&
    (!member?.book||target!=='prepared_spells'||Number(spell.level)===0||knownBook.has(spell.id))&&
    (!query||(String(spell.name||'')+' '+String(spell.source||'')).toLocaleLowerCase('it').includes(query)))
    .sort((a,b)=>Number(a.level||0)-Number(b.level||0)||
      String(a.name||'').localeCompare(String(b.name||''),'it',{sensitivity:'base'}))
    .slice(0,40);
  if(!found.length)return '<p class="hint">'+
    (member?.book&&target==='prepared_spells'&&!knownBook.size?
      'Aggiungi prima gli incantesimi al libro, poi torna alla preparazione.':'Nessun incantesimo corrispondente.')+
    '</p>';
  return groupedMagicSpells(found.map(spell=>({spell,info:magicSpellInfo(spell)})),({spell,info})=>{
    const already=selected.has(spell.id);
    const pickedIndex=selectedRows.findIndex(row=>spellId(row)===spell.id);
    return '<button class="btn full catalog-entry magic-catalog-entry" type="button" data-act="'+
      (already?'remove-spell':'spell-pick')+'" data-index="'+(already?pickedIndex:rows.indexOf(spell))+'"'+
      (already?' data-key="'+esc(target)+'" data-class-id="'+esc(member?.id||'manual')+'"':'')+
      '><span>'+esc(info.name)+'</span>'+
      '<span class="magic-selection-status">'+(already?'× Rimuovi':'+ Aggiungi')+'</span></button>';
  });
}
function diceResult(){
  if(!state.roll)return '';
  return '<div class="chat-dice-outcome"><div class="chat-dice-outcome-label">Risultato</div>'+
    '<div class="dice-result">'+esc(state.roll.total)+'</div>'+
    '<div class="chat-dice-formula"><span>Formula</span><strong>'+esc(state.roll.notation)+'</strong></div>'+
    '<div class="chat-dice-breakdown"><span>Sviluppo del tiro</span><strong>'+esc(state.roll.detail)+'</strong></div></div>'+
    '<p class="hint" data-dice-chat-status>'+(state.roll.chatStatus||'')+'</p>';
}
function diceView(){
  return '<h2 id="chat-dice-title">Lancia i dadi</h2><div class="columns">'+
    '<label>Numero dadi<input id="die-count" type="number" value="1" min="1" max="20"></label>'+
    '<label>Modificatore<input id="die-mod" type="number" value="0" min="-999" max="999"></label></div>'+
    '<div class="dice-options">'+[4,6,8,10,12,20,100].map(n=>
    '<button class="btn" type="button" data-act="select-die" data-sides="'+n+'" aria-pressed="'+(state.diceSides===n)+'">d'+n+'</button>').join("")+'</div>'+
    '<div class="actions"><button type="button" class="btn primary full" data-act="roll">Tira d'+state.diceSides+'</button></div>'+
    '<div id="dice-feedback" aria-live="polite">'+diceResult()+'</div>'+
    '<div class="actions"><button type="button" class="btn" data-act="close-chat-dice">Chiudi</button></div>';
}
function openDiceDialog(){
  if(document.querySelector("#chat-dice-dialog"))return;
  const dlg=document.createElement("dialog");
  dlg.id="chat-dice-dialog";dlg.className="sheet-roll-dialog chat-dice-dialog";
  dlg.setAttribute("aria-labelledby","chat-dice-title");dlg.innerHTML=diceView();
  dlg.addEventListener("close",()=>dlg.remove(),{once:true});document.body.append(dlg);
  if(typeof dlg.showModal==="function")dlg.showModal();else dlg.setAttribute("open","");
}
function chatView(){
  return panel("Chat della partita",
    '<div class="row between chat-toolbar"><span class="chat-caption">'+
    (state.paired&&state.online?'Messaggi e tiri della partita':'Chat disponibile con una partita collegata')+
    '</span>'+(notificationsSupported()?'<button type="button" class="btn chat-notify-toggle" data-act="toggle-chat-notifications" aria-label="Notifiche chat" title="Notifiche di sistema (mentre la PWA è attiva)">'+(notificationsEnabled()?'🔔 Attive':Notification.permission==='default'?'🔔 Autorizza':'🔕 Notifiche')+'</button>':'')+'<button type="button" class="btn chat-dice-trigger" data-act="open-chat-dice" aria-label="Apri lanciadadi" title="Lancia i dadi">🎲</button></div>'+
    (state.paired?
    '<div id="events" class="scroll-y" aria-live="polite">'+renderEvents()+'</div>'+
    '<form id="chat-form" class="stack" autocomplete="off">'+
    '<label>Scrivi come <select id="chat-author"><option value=""'+(!state.chatAuthor?' selected':'')+'>Giocatore</option>'+
    (state.cachedCreatures||[]).map(x=>'<option value="'+esc(x.name)+'"'+(state.chatAuthor===x.name?' selected':'')+'>'+esc(x.name)+'</option>').join("")+
    '</select></label><label>Messaggio<textarea id="chat-message" rows="2" maxlength="1000" placeholder="Messaggio alla partita…" required></textarea></label>'+
    '<button type="submit" class="btn primary full"'+(state.online?'':' disabled')+'>Invia messaggio</button></form>':''));
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
function sessionTokenDetails(token) {
  const edition=token.rules_version==="2024"?"2024":"2014";
  const conditionNames=Array.isArray(token.conditions)?[...new Set(token.conditions)].filter(Boolean).map(id=>{
    const row=(state.conditionCatalog?.editions?.[edition]||[]).find(item=>item.id===id);
    return conditionLabel(id,row?.name||"");
  }):[];
  const spellIds=Array.isArray(token.active_spell_ids)?[...new Set(token.active_spell_ids)]:[];
  const spellName=id=>(state.spellCatalog||[]).find(row=>row.id===id)?.name||id;
  const effects=spellIds.filter(Boolean).map(id=>spellName(id));
  if(token.concentrating_spell_id&&!spellIds.includes(token.concentrating_spell_id))
    effects.push("Concentrazione: "+spellName(token.concentrating_spell_id));
  const identity=[token.party_id?"Fazione: "+token.party_id:"",
    token.size_name?"Taglia: "+token.size_name:""].filter(Boolean);
  return '<span class="session-token-labels"><strong>'+esc(token.name)+
    (token.free?' <small>· libero</small>':'')+'</strong>'+
    (identity.length?'<span class="session-status-line">'+esc(identity.join(" · "))+'</span>':'')+
    (conditionNames.length?'<span class="session-status-line" title="'+esc(conditionNames.join(", "))+'">Stati: '+esc(conditionNames.join(", "))+'</span>':'')+
    (effects.length?'<span class="session-status-line" title="'+esc(effects.join(", "))+'">Incantesimi: '+esc(effects.join(", "))+'</span>':'')+
    '</span>';
}
function sessionTokenRows(rows, turnId="", activeEnvironment=false) {
  return rows.map(token => token.environment ?
    '<div class="session-token-row session-environment-row'+(activeEnvironment?' active':'')+'"' +
    (activeEnvironment?' aria-current="true"':'')+'>'+
    '<span class="session-token-name session-environment-name">'+
    (activeEnvironment?'<span class="session-turn" aria-label="Turno attivo">▶</span>':'')+
    '<span>'+esc(token.name||"Turno ambientale")+'</span></span>'+
    '<span class="session-initiative" title="Iniziativa">'+esc(token.initiative??20)+'</span></div>' :
    '<div class="session-token-row'+(state.tokenId===token.id?' selected':'')+
    '" data-token-row="'+esc(token.id)+'">'+
    '<button type="button" class="session-token-name" data-act="select-token" data-id="'+esc(token.id)+
    '" aria-pressed="'+(state.tokenId===token.id)+'">'+
    (token.id===turnId?'<span class="session-turn" aria-label="Turno attivo">▶</span>':'')+
    sessionTokenDetails(token)+'</button>'+
    (token.initiative!==undefined?'<span class="session-initiative" title="Iniziativa">'+esc(token.initiative)+'</span>':'')+
    '<button class="btn small session-edit-btn" type="button" data-act="edit-token" data-id="'+esc(token.id)+
    '" aria-label="Modifica '+esc(token.name)+'" title="Condizioni, incantesimi e miniatura">⚙</button></div>').join('');
}
function sessionLayout(table,desktop){
  const pane=state.sessionPane||(state.paired&&state.online?'table':'connection');
  const choices=[['table','Mappa'],['chat','Chat e dadi'],['connection','Collegamento']];
  return header('Al tavolo','La tua partita','Il tavolo condiviso, sempre a portata di mano.')+
    '<div class="session-switcher" role="group" aria-label="Sezioni della partita">'+choices.map(([key,title])=>'<button type="button" class="btn" data-act="session-pane" data-session-pane="'+key+'" aria-pressed="'+(pane===key)+'">'+title+'</button>').join('')+'</div>'+
    '<div data-session-content="connection"'+(pane==='connection'?'':' hidden')+'>'+desktop+'</div>'+
    '<div data-session-content="table"'+(pane==='table'?'':' hidden')+'>'+table+'</div>'+
    '<div data-session-content="chat"'+(pane==='chat'?'':' hidden')+'>'+chatView()+'</div>';
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
    '<button type="submit" class="btn primary full"'+(state.hostReachable?'':' disabled')+'>Collega alla partita</button></form>';
  const desktop=panel('Desktop',statusMarkup+(state.paired?'<div class="actions">'+btn('disconnect','Dissocia desktop','danger')+'</div>':pairing),'session-desktop');
  let html='';
  const image=state.snapshotObjectUrl;
  const snapshotMatches=state.liveSnapshot?.token_id===state.tokenId;
  html+='<section class="panel session-map-panel" aria-label="Mappa della partita">'+
    '<div class="session-map-stage">'+
    (image?'<canvas id="session-map-canvas" role="img" aria-label="Mappa della partita: trascina per spostarti, pizzica per ingrandire"></canvas>':'<div class="session-map-placeholder">⧉<span>'+(online?'Acquisizione mappa…':'Mappa disponibile quando il desktop è collegato')+'</span></div>')+
    (state.snapshotPending||image&&!snapshotMatches?'<span class="session-map-loading" role="status">Aggiornamento…</span>':'')+
    '</div>'+
    (selected?'<div class="session-selected-controls"><strong>'+esc(selected.name)+'</strong>'+
    '<div class="session-move-buttons" aria-label="Sposta il token">'+
    '<button type="button" class="btn small" data-act="move" data-direction="north" aria-label="Nord">↑</button>'+
    '<button type="button" class="btn small" data-act="move" data-direction="south" aria-label="Sud">↓</button>'+
    '<button type="button" class="btn small" data-act="move" data-direction="west" aria-label="Ovest">←</button>'+
    '<button type="button" class="btn small" data-act="move" data-direction="east" aria-label="Est">→</button>'+
    '<button type="button" class="btn small" data-act="move-up" aria-label="Quota più">+↑</button>'+
    '<button type="button" class="btn small" data-act="move-down" aria-label="Quota meno">−↓</button></div></div>':'')+
    '</section>';
  if(!online)return sessionLayout(html,desktop);
  html+='<section class="panel session-token-panel">'+
    '<div class="row between"><h2>'+(groups.active?'Combattimento · Round '+esc(groups.round):'Token sulla mappa')+
    '</h2>'+(groups.active?'<span class="tag">Iniziativa</span>':'')+'</div>'+
    (groups.participants.length?sessionTokenRows(groups.participants,groups.turnId,groups.activeEnvironment):
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
        '<h3>Condizioni</h3>'+conditionGrid(edited.conditions,'data-token-condition',edited.rules_version||linked?.rules_version)+
        '<h3>Incantesimi applicati</h3>'+ (active||'<p class="hint">Nessun incantesimo attivo.</p>')+
        '<label>Cerca incantesimo<input id="token-spell-query" type="search" placeholder="Nome incantesimo"></label>'+
        '<label>Incantesimo<select id="token-spell-select"></select></label>'+
        '<button type="button" class="btn small" data-act="apply-token-spell">＋ Applica incantesimo</button>'+
        '<h3>Miniatura</h3>'+
        (linked?''+
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
  return sessionLayout(html,desktop);
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
  const pendingCode=app.querySelector("#pair-secret")?.value||"";
  const rememberPair=app.querySelector("#pair-remember")?.checked;
  app.innerHTML=sessionView();
  sessionMapViewer.mount(app.querySelector("#session-map-canvas"),state.snapshotObjectUrl);
  if(pendingCode && app.querySelector("#pair-secret"))
    app.querySelector("#pair-secret").value=pendingCode;
  if(rememberPair!==undefined && app.querySelector("#pair-remember"))
    app.querySelector("#pair-remember").checked=rememberPair;
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
      sessionMapViewer.setImage(newUrl);
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
    // /api/status is intentionally public. An unpaired phone must NOT call
    // /api/session yet: its expected HTTP 401 must not overwrite the public
    // desktop-online result or disable the pairing button.
    if(state.online && state.paired){
      try {
        acceptSession(await session());state.paired=true;
      }catch(error){
        state.session=null;
        if(error.status===401){
          await unpair();state.paired=false;
        }else{
          state.online=false;
          if(error.status!==503 && !quiet)message(errorMessage(error),true);
        }
      }
    }else state.session=null;
  }catch(error){
    state.hostReachable=false;state.online=false;state.session=null;
  }
  if(!state.online){state.map=null;state.tokenId="";}
  // Fetch the same edition-dependent catalog used by the native token dialog.
  // Network failure cannot block offline creature editing.
  if(state.online && state.paired && !state.desktopConditionCatalog){
    try{
      state.desktopConditionCatalog=await conditionDefinitions();
      state.conditionCatalog=mergeConditionCatalog(state.offlineConditionCatalog,state.desktopConditionCatalog);
      if(state.page==="library"&&!state.libraryMode&&["conditions","battle"].includes(state.sheet))void render();
    }catch(error){console.warn("Desktop condition catalog unavailable; using bundled 5etools catalog",error);}
  }
  syncNav();
  if(state.online && state.paired && !realtimeStopped){
    if(!state.stopMap)startMap();
    if(!state.pollChat)startChat();
  }
  renderSessionIfIdle();
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
      row.concentrating_spell_id,row.active_spell_ids,row.current_miniature_id,row.default_miniature_id,
      row.party_id,row.size_name,row.footprint_cells]));
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
    if(generation!==chatGeneration)return;
    if(!reply.ok) throw new Error(reply.error||"Chat non disponibile");
    const initialHistory = !chatNotificationBaseline && !state.after;
    const incomingEvents = [];
    if(Array.isArray(reply.events) && reply.events.length){
      const ids=new Set(state.messages.map(e=>e.id));
      for(const entry of reply.events){
        if(!entry || !entry.id) continue;
        if(!ids.has(entry.id)){ state.messages.push(entry); ids.add(entry.id); if(!initialHistory && (entry.kind==="chat" || entry.kind==="roll") && !locallySentEventIds.has(entry.id)) incomingEvents.push(entry); }
        state.after=entry.id;
      }
      chatNotificationBaseline=true;
       state.messages=state.messages.slice(-100);
       for(const entry of incomingEvents){
         void notifyIncomingChat(entry, currentGameSession).catch(console.warn);
         if(document.visibilityState==="visible") message((entry.kind==="roll"?"🎲 ":"💬 ")+(entry.author||"Giocatore")+": "+(entry.kind==="roll"?((entry.label||entry.die||"Tiro")+": "+entry.total):(entry.text||"Messaggio")),false);
       }
      const container=document.querySelector("#events");
      if(state.page==="session"&&container){ container.innerHTML=renderEvents();container.scrollTop=container.scrollHeight; }
    }
  }catch(error){
    if(generation===chatGeneration && error.status===401){
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
  state.pollChat=setInterval(()=>{ if(state.paired) fetchChat(); },2500);
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
  state.roll.chatStatus=state.paired&&state.online?'Invio in chat…':'Tiro locale · partita non collegata.';
  const feedback=document.querySelector("#dice-feedback");if(feedback)feedback.innerHTML=diceResult();
  if(state.paired&&state.online){
    const currentRoll=state.roll;
    try{
      await shareRoll({quiet:true});
      currentRoll.chatStatus='✓ Inviato in chat';
      await fetchChat();
    }catch(error){
      currentRoll.chatStatus='Invio in chat non riuscito: '+errorMessage(error);
    }
    if(state.roll===currentRoll&&feedback)feedback.innerHTML=diceResult();
  }
}
async function shareRoll({quiet=false}={}) {
  if(!state.roll) return;
  if(!state.paired||!state.online) throw new Error("Collega prima una partita.");
  const r=state.roll;
  const event={id:"pwa_"+crypto.randomUUID(),kind:"roll",author:(document.querySelector("#chat-author")?.value||state.chatAuthor||"Giocatore").slice(0,80),
    timestamp:Math.floor(Date.now()/1000),label:r.label||r.notation,
    ...sheetRollChatFields(r)};
  locallySentEventIds.add(event.id);
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
      refreshPlayReadouts(app,editor.read(),calculated);
      syncNav();
      const attacks=app.querySelector('[data-attack-list]');if(attacks)attacks.outerHTML=attacksView(calculated,state.sheet==='battle');
      const note=app.querySelector('[data-calculation-note]');
      if(note)note.outerHTML=calculationNote(calculated,calculated.loadError);
    }
    state.saveError="";
    if(status){ status.textContent="✓ Salvato in locale"; status.classList.remove("error"); }
  }catch(error) {
    state.saveError=errorMessage(error);
    if(status){ status.textContent="Errore salvataggio";status.classList.add("error"); }
    message("Modifica non salvata: "+state.saveError,true);
    throw error;
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
    const result=await action("set_condition",{token_id:state.editTokenId||state.tokenId,
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
  if(target.dataset.coinCode){
    const denomination=target.dataset.coinCode;
    if(!COIN_LABELS.some(([code])=>code===denomination))throw Error("Moneta non valida.");
    if(target.value.trim()==="")throw Error("Inserisci una quantità di monete.");
    const amount=Number(target.value);
    if(!Number.isSafeInteger(amount)||amount<0||amount>999999999)
      throw Error("Quantità di monete non valida.");
    const coins=creature.coins&&typeof creature.coins==="object"&&!Array.isArray(creature.coins)?
      {...creature.coins}:{};
    coins[denomination]=amount;
    await patch({coins});
    const total=COIN_LABELS.reduce((sum,[code],i)=>sum+
      (Number(coins[code])||0)*[1,10,50,100,1000][i],0)/100;
    const output=app.querySelector(".inventory-coin-total");
    if(output)output.textContent="Equivalente: "+total.toLocaleString("it-IT",{maximumFractionDigits:2})+" mo";
    return;
  }
  if(target.dataset.slotWeaponSize){
    const slot=target.dataset.slotWeaponSize;
    const changed=changeEquippedWeaponSize(creature.inventory||[],slot,target.value);
    state.inventorySelectedIndex=changed.findIndex(item=>Array.isArray(item.equipped_slots)&&item.equipped_slots.includes(slot));
    await patch({inventory:changed});
    await render();return;
  }
  if(target.dataset.inventoryAttunementMax!==undefined){
    const max=Number(target.value);
    if(!Number.isInteger(max)||max<0||max>99)throw Error("Massimo di sintonia non valido.");
    await patch({attunement_max_base:max});
    await render();return;
  }
  if(target.dataset.documentIndex!==undefined){
    await persistDocumentEdit(Number(target.dataset.documentIndex),target.dataset.documentPart,creature);
    return;
  }
  if(target.dataset.equipSlot){
    const slot=target.dataset.equipSlot,index=Number(target.value);
    const special=['unarmed','improvised'].includes(target.value)?target.value:'none';
    const main=(creature.inventory||[]).find(item=>item.equipped_slots?.includes('main'));
    const mainResolved=main?resolveOwnedItem(main):null;
    const occupied=Boolean(mainResolved&&(
      hasProperty(mainResolved,'2H')||
      creature.hand_grip_two_handed&&hasProperty(mainResolved,'V')));
    if(slot==='off'&&occupied&&target.value!=='-1')
      throw Error('Mano secondaria occupata.');
    const inventory=equipSlot(creature.inventory||[],slot,special!=='none'?-1:index);
    const nextMain=inventory.find(item=>item.equipped_slots?.includes('main'));
    const nextResolved=nextMain?resolveOwnedItem(nextMain):null;
    const nextVersatile=nextResolved&&itemKind(nextResolved)==='weapon'&&hasProperty(nextResolved,'V');
    const grip=Boolean(creature.hand_grip_two_handed&&nextVersatile);
    if(slot==='main'&&grip)for(const item of inventory)
      item.equipped_slots=(item.equipped_slots||[]).filter(v=>v!=='off');
    await patch({inventory,...(slot==='body'?{}:{['hand_'+slot+'_special']:special}),
      ...(slot==='main'?{hand_grip_two_handed:grip,
        ...(grip?{hand_off_special:'none'}:{})}:{})});
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
    if(key==='hand_grip_two_handed'){
      const main=(creature.inventory||[]).find(item=>item.equipped_slots?.includes('main'));
      const usable=main&&itemKind(main)==='weapon'&&hasProperty(resolveOwnedItem(main),'V');
      if(!usable)throw Error('Nessuna arma versatile nella mano principale.');
      const inventory=structuredClone(creature.inventory||[]);
      if(value)for(const item of inventory)item.equipped_slots=(item.equipped_slots||[]).filter(slot=>slot!=='off');
      await patch({hand_grip_two_handed:value,...(value?{inventory,hand_off_special:'none'}:{})});
      await render();return;
    }
    if(key==='attack_ability'&&!['str','dex','con','int','wis','cha'].includes(value))
      throw Error('Caratteristica attacchi non valida.');
    if(key==='attack_ability_finesse_only'&&typeof value!=='boolean')
      throw Error('Ambito caratteristica attacchi non valido.');
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
    if(['rules_version','primary_class_level','attack_ability','attack_ability_finesse_only'].includes(key))await render();
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
    if(key==="quantity"&&String(value).trim()==="")throw Error("Inserisci una quantità o 0 per rimuovere.");
    if(key==="quantity"&&Number(value)===0){
      state.sheetPopup="";
      const inventory=structuredClone(creature.inventory||[]);
      inventory.splice(index,1);
      state.inventorySelectedIndex=index>0?index-1:0;
      await patch({inventory});
      await render();
    }else{
      await patch({inventory:changeOwnedItem(creature.inventory||[],index,key,value)});
      // Text editors are debounced: don't destroy their DOM and caret while
      // the user is typing a name or a custom description.
      if(key==="name"||key==="description"){
        if(key==="name"&&index===state.inventorySelectedIndex){
          const heading=app.querySelector(".inventory-description-panel>h2");
          if(heading)heading.textContent="Descrizione · "+value;
        }
      }else await render();
    }
  } else if(target.dataset.condition){
    const entries=new Set(creature.conditions||[]);
    if(target.checked) entries.add(target.dataset.condition);
    else entries.delete(target.dataset.condition);
    await patch({conditions:[...entries],...(target.dataset.condition==='concentrating'&&!target.checked?{concentrating_spell_id:''}:{})});
    // Update active status chips and their description sources on every edit.
    await render();
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
let desktopHooks=null;
async function startTargetedCast(casterId,selection,requestedLevel,payment='auto',expectedToken=''){
  if(desktopHooks?.cast){await flushPendingFields();return desktopHooks.cast({casterId,selection,requestedLevel,payment});}
  if(!state.paired||!state.online)throw Error("Collega prima la partita al desktop.");
  const stored=await loadCreature(casterId);
  if(!stored)throw Error("Scheda locale non trovata.");
  state.map=await map();
  const token=casterToken(stored.data,state.map,await ownerId());
  if(!token)throw Error("La partita è collegata, ma questa scheda non ha un token associato sulla mappa. Usa Partita → Piazza token per associarla.");
  const tokenId=String(token.id);
  if(expectedToken&&expectedToken!==tokenId)
    throw Error("Seleziona in Partita il token associato a questa creatura.");
  if(stored.data.linked_token_sync_id!==tokenId){
    const editor=state.editor&&state.creatureId===casterId?state.editor:await openCreatureEditor(casterId);
    await editor.update({linked_token_sync_id:tokenId,linked_token_name:token.name||stored.data.name});
  }
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
 const selected=state.editor?.read()?.action_variants_2014;
 if(Array.isArray(selected))return selected;
 // Older versions kept these globally; the fallback is read-only until saved
 // explicitly for this character, so other characters keep distinct choices.
 try{const choices=JSON.parse(window.localStorage.getItem('vtt.actionVariants.2014')||'[]');return Array.isArray(choices)?choices:[];}catch{return [];}
}
function decorateSheetHeadings(){
 for(const heading of app.querySelectorAll('.panel > h2, .native-entry > h3, .current-section')){
  if(heading.querySelector('.vtt-action-glyph,.vtt-info-icon'))continue;
  const title=heading.textContent.trim();
  const icon=INFO_HEADING_ICONS[title];
  if(title==='Aspetto')heading.insertAdjacentHTML('afterbegin',actionGlyph('eye'));
  else if(icon)heading.insertAdjacentHTML('afterbegin','<img class="vtt-info-icon" src="/icons/info/'+icon+'.svg" alt="" aria-hidden="true">');
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
function organizeSheetPanels(){
  if(state.page!=="library"||state.libraryMode||!state.editor)return;
  state.sheetSources=mountPlaySheet(app,{creature:state.editor.read(),calculated:state.calculated,sheet:state.sheet,view:{inventorySelectedIndex:state.inventorySelectedIndex,inventorySubtab:state.inventorySubtab,search:state.sheetSearch.get(state.creatureId+"|"+state.sheet)||"",battleActions:state.sheet==="battle"?battleActionPanels(state.editor.read(),state.calculated,state.spellCatalog||[],state.featureActionOverrides||[],state.generalActionSupplements||[],readActionVariants(),abilitiesForCreature(state.editor.read(),state.abilityCatalog||[],state.calculated),state.battleOnlyClass):null,battleOnlyClass:state.battleOnlyClass,battleAbilities:state.sheet==="battle"?abilitiesForCreature(state.editor.read(),state.abilityCatalog||[],state.calculated):[],battleSpells:state.sheet==="battle"?state.spellCatalog||[]:[],battleTraits:state.sheet==="battle"?[
  ...(state.calculated.features||[]).map(feature=>({name:feature.name||'',origin_id:feature.origin_id||'',origin_key:feature.origin_key||'',feature_key:feature.key||'',
    description:flattenDescription(feature)})),
  ...(state.battleOptionalTraits||[])]:[]},icon:actionGlyph,conditionLabel,conditionCatalog:state.conditionCatalog,inventoryProperties,isSpellScroll,spells:spellsForEdition(state.spellCatalog||[],state.editor.read().rules_version),classActions:nativeClassFeatureActions(state.editor.read(),state.calculated)});
  if(state.sheet==='info'){
    const root=app.querySelector('#sheet-play-view');
    const choices=state.calculated.pending_choices||[];
    const missing=choices.filter(choice=>choice.remaining>0);
    if(root&&missing.length){
      const total=missing.reduce((n,choice)=>n+choice.remaining,0);
      const notice=document.createElement('section');
      notice.className='pending-choices-notice';
      notice.setAttribute('aria-label','Scelte del personaggio da completare');
      notice.innerHTML='<div class="pending-choices-notice-head"><span aria-hidden="true">◇</span>'+
        '<strong>'+total+' '+(total===1?'scelta da completare':'scelte da completare')+'</strong></div>'+
        '<div class="pending-choices-notice-list">'+missing.map(choice=>
          '<button type="button" data-act="pending-choice-open" data-choice-id="'+esc(choice.id)+'">'+
          '<span>'+esc(choice.name)+' <small>· '+esc(choice.label)+'</small></span>'+
          '<span>'+esc(choice.selected.length)+'/'+esc(choice.count)+' <span aria-hidden="true">›</span></span></button>').join('')+
        '</div>';
      root.prepend(notice);
    }
    // Completed choices remain editable; the warning itself is only for
    // missing decisions. Reuse one editor for every structured origin.
    const competence=root?.querySelector('.play-competence-tools');
    if(competence&&choices.length){
      const manage=document.createElement('button');
      manage.type='button';manage.className='pending-choices-manage';
      manage.dataset.act='pending-choice-manage';
      manage.textContent='Scelte dei privilegi';
      competence.append(manage);
    }
  }
  // Preserve expanded combat cards across sheet rerenders. Opening a parent
  // from its heading reveals the index first, without auto-opening its children.
  for(const details of app.querySelectorAll('#sheet-play-view .play-battle-disclosure')){
    const key='battle-disclosure:'+details.dataset.battleAction;
    if(state.disclosureState.has(key))details.open=state.disclosureState.get(key);
    details.querySelector(':scope > summary')?.addEventListener('click',()=>{
      if(details.open)return;
      for(const group of details.querySelectorAll(':scope > .play-battle-action-group')){
        group.open=false;
        const groupKey=group.dataset.actionAbility?'battle-ability:'+group.dataset.actionAbility:
          'battle-timing:'+details.dataset.battleAction+':'+group.dataset.actionTiming;
        state.disclosureState.set(groupKey,false);
      }
    });
    details.addEventListener('toggle',()=>{
      if(details.isConnected)state.disclosureState.set(key,details.open);
    });
  }
  // Remember timing groups and ability groups independently across rerenders.
  for(const details of app.querySelectorAll('#sheet-play-view .play-battle-action-group')){
    const panel=details.closest('.play-battle-disclosure')?.dataset.battleAction||'';
    const key=details.dataset.actionAbility?'battle-ability:'+details.dataset.actionAbility:
      'battle-timing:'+panel+':'+details.dataset.actionTiming;
    if(state.disclosureState.has(key))details.open=state.disclosureState.get(key);
    details.addEventListener('toggle',()=>{
      if(details.isConnected)state.disclosureState.set(key,details.open);
    });
  }

  if(!state.sheetPopup)return;
  const source=state.sheetSources.get(state.sheetPopup);
  if(!source){state.sheetPopup="";return;}
  const dialog=document.createElement('dialog');dialog.id='sheet-context-dialog';dialog.className='sheet-context-dialog';dialog.dataset.context=state.sheetPopup;
  const title=state.sheetPopupTitle||source.querySelector('h2,h3,summary,strong')?.textContent.trim()||source.getAttribute('aria-label')||'Dettagli e modifica';
  dialog.setAttribute('aria-labelledby','sheet-context-title');
  dialog.innerHTML='<header class="sheet-context-head"><h2 id="sheet-context-title">'+esc(title)+'</h2><button type="button" class="play-button" data-act="sheet-context-close" aria-label="Chiudi dettagli">'+actionGlyph('cross')+'</button></header><div class="sheet-context-body"></div>';
  dialog.querySelector('.sheet-context-body').append(source);
  if(source.tagName==='DETAILS')source.open=true;
  for(const details of source.querySelectorAll(':scope > .action-economy-main > details.action-economy-entry,:scope > details.action-tree'))details.open=true;
  app.append(dialog);
  dialog.addEventListener('cancel',event=>{event.preventDefault();void closeSheetContext().catch(error=>message(errorMessage(error),true));});
  dialog.addEventListener('click',event=>{if(event.target!==dialog)return;const rect=dialog.getBoundingClientRect();if(event.clientY<rect.top||event.clientY>rect.bottom||event.clientX<rect.left||event.clientX>rect.right)void closeSheetContext().catch(error=>message(errorMessage(error),true));});
  if(dialog.showModal)dialog.showModal();else dialog.setAttribute('open','');
}
async function closeSheetContext(){
  const key=state.sheetPopup;
  await flushPendingFields();state.sheetPopup="";await render();
  [...app.querySelectorAll('#sheet-play-view [data-sheet-context]')].find(node=>node.dataset.sheetContext===key)?.focus({preventScroll:true});
}
function rememberUtilityDisclosures(){
  for(const details of app.querySelectorAll('.archive-tools, .catalog-create, .play-skills-disclosure, .play-traits-disclosure')){
    const key=state.page+'|'+(state.libraryMode?'archive':state.sheet)+'|'+((details.classList.contains('play-skills-disclosure')||details.classList.contains('play-traits-disclosure'))?(state.creatureId+'|'):'')+details.querySelector(':scope > summary')?.textContent;
    if(state.disclosureState.has(key))details.open=state.disclosureState.get(key);
    details.addEventListener('toggle',()=>{if(details.isConnected)state.disclosureState.set(key,details.open);});
  }
}
function fillAppliedSpellOptions(query=''){
 const select=app.querySelector('#condition-spell-picker');if(!select)return;
 const rules=state.editor?.read()?.rules_version||'2014';
 const matches=spellsForEdition(state.spellCatalog||[],rules).filter(isPersistentSpell)
   .filter(row=>row?.id&&row?.name&&String(row.name).toLocaleLowerCase('it').includes(String(query).trim().toLocaleLowerCase('it'))).slice(0,120);
 select.innerHTML=matches.map(row=>'<option value="'+esc(row.id)+'">'+esc(row.name)+(row.source?' · '+esc(row.source):'')+'</option>').join('');
}
// D20 checks and weapon damage use one sheet-roll popup structure.
// Damage has no advantage/disadvantage in 5e; its mode selector is read-only.
// Keep the title about *what* the character is rolling, and this second
// row about *which kind* of roll it is. Do not repeat the roll name.
function rollHeading(label,target){
 const text=String(label||'Tiro').trim();
 if(target.startsWith('save:')){
   const stat=target.slice(5);
   if(/^tiro\s+(?:di\s+)?salvezza\b/i.test(text))
     return abilities[stat]||text;
 }
 if(target.startsWith('attack_hit:')||target.startsWith('casting_hit:'))
   return text.replace(/^tiro\s+per\s+colpire\s*[·:–-]\s*/i,'')||text;
 return text;
}
function rollCategory(target,calculated){
 if(target.startsWith('skill:')){
   const stat=SKILLS.find(([id])=>id===target.slice(6))?.[2];
   return 'Prova di abilità'+(abilities[stat]?' · '+abilities[stat]:'');
 }
 if(target==='initiative')return 'Prova di abilità · Destrezza';
 if(target.startsWith('ability_check:')||target.startsWith('ability_mod:'))
   return 'Prova di caratteristica';
 if(target.startsWith('save:'))return 'Tiro salvezza';
 if(target.startsWith('casting_hit:'))return 'Tiro per colpire · Incantesimo';
 if(target.startsWith('attack_hit:')){
   const attack=(calculated?.attacks||[]).find(a=>'attack_hit:'+a.id===target);
   if(attack)return 'Tiro per colpire · '+(attack.melee?'Mischia':'Distanza');
   return 'Tiro per colpire';
 }
 return 'Tiro d20';
}
function damageRollTerms(formula,damageType='',attack=null){
 const validated=rollBattleDamage(formula,()=>1); // Preview never consumes randomness.
 const segments=damageRollSegments(validated,damageType,attack).map(row=>({
   ...row,damageType:rollDamageName(row.damageType)
 }));
 return {modifier:validated.modifier,segments};
}
function currentlyAvailableRollBonus(original,available){
 if(!original)return null;
 return available.find(row=>String(row.id||'')===String(original.id||'')&&
   String(row.origin_id||'')===String(original.origin_id||'')&&
   String(row.dice||'')===String(original.dice||'')&&
   String(row.target||'')===String(original.target||''))||null;
}
function rollDieResultMarkup(outcome){
 return '<div class="dice-result">'+esc(outcome.total)+'</div>'+
  '<div class="sheet-roll-dice-groups" aria-label="Risultati dei singoli dadi">'+
  (outcome.parts||[]).map(part=>
   '<div class="sheet-roll-dice-group"><span class="sheet-roll-dice-label">'+esc(part.notation)+'</span>'+
   '<div class="sheet-roll-dice-values">'+(part.rolls||[]).map(n=>
     '<span class="sheet-roll-die-value">'+esc(n)+'</span>').join('')+'</div></div>').join('')+'</div>';
}
function chosenRollBonuses(dialog){
 return [...(dialog.usedRollBonuses||[])];
}
function rollBonusTerm(row){
 return {key:'roll-extra:'+String(row.selectionId||row.id),kind:'dice',
  formula:'+'+row.dice,expanded:'',...(row.damage_type?{damageType:rollDamageName(row.damage_type)}:{}),
  originId:row.origin_id||'',originName:row.origin_name||'Bonus',
  section:row.origin_id?'':'formula_bonuses'};
}
// Roll popups navigate only to concrete owned traits. The picker always uses
// the current calculated trait projection (including equipped item traits).
async function openRollTraitPicker(kind='bonus',target=''){
 state.traitPopupKey='';state.traitPopupConfirm='';state.traitPopupDraftKind='';state.traitPopupDraftTarget='';
 state.sheet='info';await render();
 const traits=(state.traitRows||[]).filter(trait=>!trait.inactive&&!trait.readonly);
 if(!traits.length){message('Nessun tratto disponibile a cui associare il beneficio.',true);return;}
 document.querySelector('#roll-trait-picker')?.remove();
 const picker=document.createElement('dialog');picker.id='roll-trait-picker';picker.className='trait-benefits-dialog';
 picker.dataset.benefitKind=kind;picker.dataset.benefitTarget=target;
 picker.innerHTML='<header class="trait-benefits-dialog-head"><h2>Seleziona il tratto che concede il bonus</h2>'+
  '<button type="button" class="trait-benefits-close" data-act="roll-trait-cancel" aria-label="Chiudi">×</button></header>'+
  '<div class="trait-benefits-dialog-body"><label>Tratto<select data-roll-trait-key>'+
  traits.map(row=>'<option value="'+esc(row.key)+'">'+esc(row.origin+' · '+row.name)+'</option>').join('')+
  '</select></label><div class="actions"><button type="button" class="btn primary" data-act="roll-trait-pick">Continua</button></div></div>';
 document.body.append(picker);picker.addEventListener('close',()=>picker.remove(),{once:true});
 picker.showModal?.();
}
async function openRollTraitOrigin(originId){
 state.traitPopupKey='';state.traitPopupConfirm='';state.traitPopupDraftKind='';state.traitPopupDraftTarget='';
 state.sheet='info';await render();
 const record=state.editor?.read()||{};
 const candidates=(state.traitRows||[]).map(row=>({
  row,score:row.feature_origin===originId||row.proficiency_origin===originId?5:
    row.origin_key===originId?4:traitBenefitSources(row,record).has(originId)?3:0
 })).filter(item=>item.score>0).sort((a,b)=>b.score-a.score||b.row.rank-a.row.rank);
 const trait=candidates[0]?.row;
 if(!trait){
   message('Origine non riconducibile a un tratto della creatura. Seleziona il tratto corretto.',true);
   await openRollTraitPicker('bonus','');return;
 }
 state.traitPopupKey=trait.key;mountTraitBenefitDialog();
}
function openUnifiedRollDialog({kind,heading,rollLabel='',modifier,rollType,formula,bonuses=[],autoLabel='',creatureId='',target='',damageFormula='',damageType='',damageLabel=''}){
 document.querySelector('#sheet-roll-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='sheet-roll-dialog';dialog.className='sheet-roll-dialog sheet-roll-preview';
 dialog.dataset.rollKind=kind;dialog.dataset.creatureId=creatureId;
 dialog.rollBonuses=bonuses;dialog.usedRollBonuses=[];
 if(kind==='damage'){
   dialog.dataset.damageFormula=damageFormula;dialog.dataset.damageType=damageType;
   dialog.dataset.damageLabel=damageLabel;
 }else{
   dialog.dataset.rollTarget=target;dialog.dataset.rollLabel=rollLabel;
 }
 const mode=kind==='damage'
   ?'<option value="normal">Normale</option>'
   :'<option value="auto">Automatica'+esc(autoLabel)+'</option>'+
     '<option value="normal">Forza tiro normale</option>'+
     '<option value="advantage">Aggiungi vantaggio</option>'+
     '<option value="disadvantage">Aggiungi svantaggio</option>';
 const select='<label class="sheet-roll-mode-control">Modalità del tiro'+
   '<select data-roll-mode'+(kind==='damage'?' disabled aria-label="I danni non prevedono vantaggio o svantaggio"':'')+'>'+mode+'</select></label>';
 const bonusList='<section class="sheet-roll-math sheet-roll-formula sheet-roll-applicable">'+
   '<div class="sheet-roll-bonuses-head"><span>Bonus applicabili al tiro</span>'+
   '<button type="button" class="sheet-roll-add" data-act="sheet-roll-add-applicable" aria-label="Aggiungi tiro applicabile" title="Aggiungi tiro applicabile">+</button></div>'+
   (bonuses.length?'<div class="sheet-roll-bonus-list" data-roll-extra role="group" aria-label="Bonus disponibili">'+
     bonuses.map((row,i)=>{
       const trackerLabel=row.tracker_id?(row.tracker_name||'Tracker')+' · '+(row.remaining??0)+' rim.':'Nessun tracker associato';
       return '<div class="sheet-roll-bonus-item">'+
         '<button type="button" class="sheet-roll-origin-term sheet-roll-bonus-term is-link" data-act="roll-origin-open" data-origin-id="'+esc(row.origin_id||'')+'" title="Apri tratto">'+
           '<span class="sheet-roll-origin-symbol">+'+esc(row.dice)+'</span>'+
           (row.damage_type?'<span class="sheet-roll-origin-damage-type">'+esc(rollDamageName(row.damage_type))+'</span>':'')+
           '<span class="sheet-roll-origin-name">'+esc(row.origin_name||'Bonus')+'</span></button>'+
         '<div class="sheet-roll-bonus-controls">'+
           '<button type="button" class="sheet-roll-use" data-act="sheet-roll-use-bonus" data-roll-use="'+i+'">Usa</button>'+
           '<button type="button" class="sheet-roll-tracker-open" data-act="sheet-roll-open-tracker" data-roll-tracker-button="'+i+'" aria-label="Apri tracker '+esc(trackerLabel)+'" title="'+esc(trackerLabel)+'"'+(row.tracker_id?'':' disabled')+'>'+
             actionGlyph('target')+'</button>'+
         '</div></div>';
     }).join('')+'</div>':'')+'</section>';
 dialog.innerHTML='<h2>'+esc(heading)+
   '<button type="button" class="sheet-roll-close" data-act="close-sheet-roll" aria-label="Chiudi" title="Chiudi">×</button></h2>'+
   '<div class="sheet-roll-math"><span>Modificatore totale</span><strong>'+esc((modifier>=0?'+':'')+modifier)+'</strong></div>'+
   '<div class="sheet-roll-math"><span>Tipo di tiro</span><strong>'+esc(rollType)+'</strong></div>'+
   '<div class="sheet-roll-math sheet-roll-formula"><span>Formula del tiro</span>'+
     '<div class="sheet-roll-formula-line"><div data-roll-formula>'+formula+'</div>'+
     '<button type="button" class="sheet-roll-add" data-act="sheet-roll-add-bonus" aria-label="Aggiungi bonus alla formula" title="Aggiungi bonus alla formula">+</button></div></div>'+
   bonusList+'<div class="sheet-roll-result" data-roll-result hidden aria-live="polite"></div>'+
   '<div class="actions sheet-roll-actions">'+select+
     btn('roll-sheet-confirm',kind==='damage'?'Tira danni':'Tira 1d20','primary')+'</div>';
 document.body.append(dialog);
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 if(dialog.showModal)dialog.showModal();else dialog.setAttribute('open','');
 return dialog;
}
const editableScoreBaseTarget=target=>
  target==='hp'||target==='second_max'||
  /^ability:(?:str|dex|con|int|wis|cha)$/.test(target);

// A single restrained editor serves owned base scores, not derived figures.
// Keep the formula behind it as the navigation context, then refresh it after
// saving/cancelling to avoid presenting a stale computed total.
function openSheetBaseEditor(record,calculated,target,{returnTitle=''}={}){
 if(!editableScoreBaseTarget(target))throw Error('Questo valore è calcolato e non modificabile direttamente.');
 const ability=target.startsWith('ability:')?target.split(':')[1]:'';
 const isHp=target==='hp',isSecond=target==='second_max';
 const title=isHp?'PF massimi':isSecond?'PF seconda forma':abilities[ability];
 const value=isHp?(record.max_hp_base??record.max_hp??1):
   isSecond?(record.second_form_max_hp??0):(record.abilities?.[ability]??10);
 const minimum=isSecond?0:1,maximum=ability?30:99999;
 const auto=calculated?.stats?.automatic_hp;
 document.querySelector('#sheet-score-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='sheet-score-dialog';
 dialog.className='sheet-roll-dialog sheet-roll-preview sheet-score-dialog sheet-base-editor';
 dialog.dataset.scoreTarget=target;
 dialog.dataset.returnFormulaTitle=returnTitle;
 dialog.innerHTML='<h2>Modifica valore base'+
   '<button type="button" class="sheet-roll-close" data-act="close-score" aria-label="Chiudi" title="Chiudi">×</button></h2>'+
   '<div class="sheet-base-editor-body">'+
     '<p class="sheet-base-editor-eyebrow">'+esc(title)+'</p>'+
     '<label class="sheet-base-editor-field" for="sheet-score-input">Valore base'+
       '<input id="sheet-score-input" type="number" inputmode="numeric" step="1" min="'+minimum+
       '" max="'+maximum+'" value="'+esc(value)+'" aria-label="Valore base '+esc(title)+'"></label>'+
     (isHp?'<div class="sheet-base-editor-auto">'+
       '<button type="button" class="sheet-base-editor-auto-button" data-act="sheet-base-auto-hp"'+
         (auto?.available?'':' disabled')+'>Calcola automaticamente</button>'+
       '<small>'+(auto?.available?'Progressione di classe · '+esc(auto.value)+' PF':
         'Calcolo automatico non disponibile per questa creatura')+'</small>'+
       '</div>':'')+
     '<div class="sheet-base-editor-actions">'+
       '<button type="button" data-act="close-score" class="sheet-base-editor-cancel">Annulla</button>'+
       '<button type="button" data-act="save-score" class="sheet-base-editor-save">Salva</button>'+
     '</div></div>';
 document.body.append(dialog);
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 if(dialog.showModal)dialog.showModal();else dialog.setAttribute('open','');
 dialog.querySelector('input')?.focus();
 dialog.querySelector('input')?.select();
 return dialog;
}
function openSheetScoreFormula(record,calculated,target,label){
 const value=Number(calculated?.values?.[target]);
 if(!Number.isFinite(value))throw Error('Valore calcolato non disponibile');
 document.querySelector('#sheet-score-formula-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='sheet-score-formula-dialog';
 dialog.className='sheet-roll-dialog sheet-roll-preview sheet-score-formula-dialog';
 dialog.dataset.scoreTarget=target;
 const title=label||({hp:'PF massimi',second_max:'PF seconda forma',
   passive_perception:'Percezione passiva',proficiency:'Bonus competenza',
   ac:'Classe armatura'})[target]||target;
 const terms=sheetScoreOriginSegments(record,calculated,target).map(row=>
   row.kind==='base'&&editableScoreBaseTarget(target)?{...row,editBaseTarget:target}:row);
 dialog.innerHTML='<h2>'+esc(title)+
   '<button type="button" class="sheet-roll-close" data-act="close-score-formula" aria-label="Chiudi" title="Chiudi">×</button></h2>'+
   '<div class="sheet-roll-math"><span>Valore calcolato</span><strong>'+esc(value)+'</strong></div>'+
   '<div class="sheet-roll-math sheet-roll-formula"><span>Formula del valore</span>'+
   '<div class="sheet-roll-formula-line"><div data-score-formula>'+
   sheetRollOriginHtml(terms,esc)+'</div>'+
   '<button type="button" class="sheet-roll-add" data-act="sheet-score-add-bonus" title="Aggiungi un bonus tramite un tratto" aria-label="Aggiungi un bonus tramite un tratto">+</button></div></div>';
 document.body.append(dialog);
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 dialog.addEventListener('click',event=>{if(event.target===dialog)dialog.close?.();});
 if(dialog.showModal)dialog.showModal();else dialog.setAttribute('open','');
 return dialog;
}
function openPendingChoicesIndex(){
 const choices=state.calculated?.pending_choices||[];
 if(!choices.length)return;
 app.querySelector('#pending-choice-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='pending-choice-dialog';
 dialog.className='sheet-context-dialog pending-choice-dialog pending-choice-index';
 dialog.innerHTML='<header class="sheet-context-head"><h2>Scelte dei privilegi</h2>'+
   '<button type="button" class="play-button" data-act="pending-choice-close" aria-label="Chiudi">×</button></header>'+
   '<div class="pending-choice-dialog-body pending-choices-notice-list">'+
   choices.map(choice=>'<button type="button" data-act="pending-choice-open" data-choice-id="'+esc(choice.id)+'">'+
     '<span>'+esc(choice.name)+' <small>· '+esc(choice.label)+'</small></span>'+
     '<span>'+esc(choice.selected.length)+'/'+esc(choice.count)+' <span aria-hidden="true">›</span></span></button>').join('')+
   '</div>';
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 app.append(dialog);
 if(dialog.showModal)dialog.showModal();else dialog.setAttribute('open','');
}
function openPendingChoiceDialog(choice){
 app.querySelector('#pending-choice-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='pending-choice-dialog';
 dialog.className='sheet-context-dialog pending-choice-dialog';
 dialog.dataset.choiceId=choice.id;
 const multiple=choice.kind==='proficiency'&&choice.count>1;
 const inputType=multiple?'checkbox':'radio';
 const labels=Object.fromEntries(SKILLS.map(([id,name])=>[id,name]));
 Object.assign(labels,abilities);
 const rows=choice.options.map(key=>'<label class="pending-choice-option"><input type="'+inputType+
   '" name="pending-options" value="'+esc(key)+'" '+(choice.selected.includes(key)?'checked':'')+
   '><span>'+esc(labels[key]||key)+'</span></label>').join('');
 dialog.innerHTML='<header class="sheet-context-head"><div><small>'+esc(choice.name)+'</small>'+
   '<h2>'+esc(choice.label)+'</h2></div>'+
   '<button type="button" class="play-button" data-act="pending-choice-close" aria-label="Chiudi">×</button></header>'+
   '<div class="pending-choice-dialog-body"><p class="pending-choice-instruction">'+
   'Scegli fino a '+esc(choice.count)+' '+(choice.count===1?'opzione':'opzioni')+
   ' concesse dal privilegio. Le scelte sono associate alla loro origine.</p>'+
   '<p class="pending-choice-progress" aria-live="polite">'+esc(choice.selected.length)+' / '+esc(choice.count)+' selezionate</p>'+
   (rows?'<div class="pending-choice-options">'+rows+'</div>':
    '<p class="hint">Nessuna opzione risolta dal catalogo locale. Le scelte già salvate rimangono inalterate.</p>')+
   '</div><footer class="pending-choice-actions"><button type="button" data-act="pending-choice-close">Annulla</button>'+
   '<button type="button" data-act="pending-choice-save"'+(rows?'':' disabled')+'>Applica</button></footer>';
 const update=()=>{
   const checked=[...dialog.querySelectorAll('[name="pending-options"]:checked')];
   const progress=dialog.querySelector('.pending-choice-progress');
   if(progress)progress.textContent=checked.length+' / '+choice.count+' selezionate';
   for(const input of dialog.querySelectorAll('[name="pending-options"]')){
     input.disabled=!input.checked&&checked.length>=choice.count;
   }
 };
 dialog.addEventListener('change',update);
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 app.append(dialog);
 update();
 if(dialog.showModal)dialog.showModal();else dialog.setAttribute('open','');
}
async function handleAction(target){
  const act=target.dataset.act;
  if(act==='pending-choice-manage'){
    openPendingChoicesIndex();return;
  }
  if(act==='pending-choice-open'){
    const choice=(state.calculated?.pending_choices||[]).find(row=>row.id===target.dataset.choiceId);
    if(!choice)throw Error('Scelta non disponibile nella scheda.');
    if(choice.kind==='spell'){
      app.querySelector('#pending-choice-dialog')?.remove();
      state.pendingSpellChoiceId=choice.source_choice_id;
      state.sheet='magic';state.magicPopup='choices';await render();
      const row=[...app.querySelectorAll('[data-pending-spell-choice]')]
        .find(node=>node.dataset.pendingSpellChoice===choice.source_choice_id);
      row?.scrollIntoView?.({block:'nearest'});
      row?.querySelector('select')?.focus?.({preventScroll:true});
      return;
    }
    openPendingChoiceDialog(choice);return;
  }
  if(act==='pending-choice-close'){
    const dialog=app.querySelector('#pending-choice-dialog');
    if(dialog?.close)dialog.close();else dialog?.remove();
    return;
  }
  if(act==='pending-choice-save'){
    const dialog=app.querySelector('#pending-choice-dialog');
    const choice=(state.calculated?.pending_choices||[]).find(row=>row.id===dialog?.dataset.choiceId);
    if(!choice)throw Error('La scelta è cambiata: riapri il selettore.');
    const selected=[...dialog.querySelectorAll('[name="pending-options"]:checked')].map(row=>row.value);
    const current=state.editor.read();
    // Validate once again against freshly derived grants before persisting.
    const fresh=await computeLocalData(current);
    const live=fresh.pending_choices.find(row=>row.id===choice.id);
    if(!live)throw Error('Il privilegio non concede più questa scelta.');
    await patch(savePendingChoice(current,live,selected));
    dialog.remove();await render();return;
  }
  if(act==='battle-toggle-class-only'){
    state.battleOnlyClass=!state.battleOnlyClass;await render();return;
  }
  if(act==='battle-expand-all'||act==='battle-collapse-all'){
    const expanded=act==='battle-expand-all';
    for(const details of app.querySelectorAll('#sheet-play-view .play-battle-disclosure, #sheet-play-view .play-battle-action-group')){
      details.open=expanded;
      const panel=details.closest('.play-battle-disclosure')?.dataset.battleAction||'';
      const key=details.classList.contains('play-battle-disclosure')?
        'battle-disclosure:'+details.dataset.battleAction:
        details.dataset.actionAbility?'battle-ability:'+details.dataset.actionAbility:
        'battle-timing:'+panel+':'+details.dataset.actionTiming;
      state.disclosureState.set(key,expanded);
    }
    return;
  }
  if(act==='sheet-context'){if(target.dataset.sheetContext==='scroll-create')state.scrollSpellQuery='';state.sheetPopupTitle=target.title||target.querySelector('.play-row-copy strong')?.textContent||target.getAttribute('aria-label')||'Dettagli';state.sheetPopup=target.dataset.sheetContext;if(state.sheetPopup.startsWith('item:'))state.inventorySelectedIndex=Number(state.sheetPopup.slice(5));await render();return;}
  if(act==='sheet-context-close'){await closeSheetContext();return;}
  if(act==='condition-add-spell'){
    const c=state.editor?.read();if(!c)throw Error('Creatura non disponibile');
    const id=app.querySelector('#condition-spell-picker')?.value||'';
    const spell=spellsForEdition(state.spellCatalog||[],c.rules_version).find(row=>row.id===id&&isPersistentSpell(row));
    if(!spell)throw Error('Scegli un incantesimo con durata non istantanea.');
    const originId='spell:'+id,origins=structuredClone(c.proficiency_origins||[]);
    const row=origins.find(row=>row?.id===originId);
    if(row)Object.assign(row,{group:'spell',name:'Incantesimo · '+spell.name,applied:true,disabled:false});
    else origins.push({id:originId,group:'spell',name:'Incantesimo · '+spell.name,applied:true,disabled:false,automatic:false});
    await patch({proficiency_origins:origins,origin_enabled:{...(c.origin_enabled||{}),[originId]:true}});
    state.sheetPopup='';await render();return;
  }
  if(act==='condition-remove-spell'){
    const c=state.editor?.read();if(!c)throw Error('Creatura non disponibile');
    const id=String(target.dataset.spellId||''),originId='spell:'+id;
    if(!(c.proficiency_origins||[]).some(row=>row.id===originId&&row.group==='spell'))throw Error('Incantesimo non applicato');
    const origins=(c.proficiency_origins||[]).filter(row=>!(row.id===originId&&row.group==='spell'));
    const contexts={...(c.active_spell_context||{})};delete contexts[id];
    const enabled={...(c.origin_enabled||{})};delete enabled[originId];
    const changes={proficiency_origins:origins,active_spell_context:contexts,origin_enabled:enabled};
    for(const field of ['formula_bonuses','dice_bonuses','resource_trackers','proficiency_choices','damage_defense_entries','origin_spell_grants']){
      if(Array.isArray(c[field]))changes[field]=c[field].filter(row=>row?.origin_id!==originId&&row?.parent_origin!==originId);
    }
    await patch(changes);await render();return;
  }
  if(act==='condition-add-ability'){
    const c=state.editor?.read();if(!c)throw Error('Creatura non disponibile');
    const key=app.querySelector('#condition-ability-picker')?.value||'';
    const calculated=await computeLocalData(c);
    const ability=nativeClassFeatureActions(c,calculated).find(row=>row.class_feature_id===key);
    if(!ability)throw Error('Capacità non disponibile.');
    await activateClassAbility(c,calculated,ability);return;
  }
  if(act==='battle-use-ability'){
    const c=state.editor?.read();if(!c)throw Error('Creatura non disponibile');
    const calculated=await computeLocalData(c);
    const panels=battleActionPanels(c,calculated,state.spellCatalog||[],state.featureActionOverrides||[],
      state.generalActionSupplements||[],readActionVariants(),
      abilitiesForCreature(c,state.abilityCatalog||[],calculated),state.battleOnlyClass);
    const requested=String(target.dataset.abilityId||'');
    const power=requested.startsWith('activated:')?
      abilitiesForCreature(c,state.abilityCatalog||[],calculated)
        .find(row=>String(row.id)===requested.slice('activated:'.length)):null;
    const ability=panels.abilityEntries.find(row=>
      String(row.id||row.ability_id||row.name)===requested)||
      (power?{...power,cost:power.resource_cost??(power.tracker_id?1:0)}:null);
    if(!ability)throw Error('Capacità non disponibile per questa creatura.');
    if(ability.rule_action_id==='wild_shape'||ability.id==='vtt_wild_shape'||ability.ability_id==='vtt_wild_shape'){
      await handleAction({dataset:{act:'miniature-pick',miniatureKind:'current',wildShape:'true'}});return;
    }
    if(ability.class_feature_id){
      await activateClassAbility(c,calculated,ability);return;
    }
    const cost=Math.max(0,Number(ability.cost)||0);
    const persistentKey=String(target.dataset.persistentKey||'');
    if(persistentKey){
      await patch(current=>{
        if(current.active_class_features?.[persistentKey])throw Error('Capacità già attiva.');
        const changes=cost?spendTrackerUses(current,ability.tracker_id,cost,calculated.trackers):{};
        changes.active_class_features={...(current.active_class_features||{}),
          [persistentKey]:{name:ability.name,origin_id:ability.origin_id||ability.feature_id||requested,
            rules_version:current.rules_version||'2014',enhanced:false}};
        return changes;
      });
      await render();
      return;
    }
    if(cost){
      await patch(current=>spendTrackerUses(current,ability.tracker_id,cost,calculated.trackers));
    }
    await render();
    message(cost?'Uso di '+ability.name+' registrato · '+cost+' utilizzi consumati.':
      ability.name+': consulta la descrizione per applicarne gli effetti.');
    return;
  }
  if(act==='tracker-reset'){
    const creature=state.editor?.read();
    if(!creature)throw Error('Creatura non disponibile.');
    const calculated=await computeLocalData(creature);
    const id=String(target.dataset.trackerId||'');
    const row=(calculated.trackers||[]).find(tracker=>String(tracker.id)===id&&!tracker.disabled);
    if(!row)throw Error('Risorsa non disponibile.');
    await patch(current=>{
      const spent={...(current.resource_tracker_spent||{})};
      delete spent[id];
      return {resource_tracker_spent:spent};
    });
    await render();
    return;
  }
  if(act==='condition-remove-ability'){
    const c=state.editor?.read();if(!c)throw Error('Creatura non disponibile');
    const key=String(target.dataset.abilityKey||'');
    if(key.startsWith('trait_state:')){
      const calculated=await computeLocalData(c);
      await patch(traitStateActivationPatch(c,calculated.features,calculated.trait_state_catalog,key.slice('trait_state:'.length)));
      await render();return;
    }
    if(!Object.hasOwn(c.active_class_features||{},key))throw Error('Capacità non attiva.');
    if(key==='wild_shape'){
      await applyFormPatch(c,endWildShapePatch(c));await render();return;
    }
    const effects={...(c.active_class_features||{})};delete effects[key];
    await patch({active_class_features:effects});await render();return;
  }


  if(act==='sheet-proxy'){
    const source=state.sheetSources.get(target.dataset.sheetSource);if(!source)throw Error('Controllo non disponibile');
    if(source.disabled)return;
    if(source.dataset.magicTool){state.sheetPopup='';app.querySelector('#sheet-context-dialog')?.close?.();}
    await handleAction(source);return;
  }
  if(act==='session-pane'){state.sessionPane=target.dataset.sessionPane;await render();return;}
  if(act==='catalog-close'){state.catalogSelected=-1;await render();return;}
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
    const wildShape=target.dataset.wildShape==='true';
    let selectedProfile=null;
    const dialog=document.createElement('dialog');
    dialog.className='sheet-roll-dialog miniature-dialog';
    dialog.innerHTML='<h2>'+(wildShape?'Forma selvatica':kind==='base'?'Miniatura di base':'Forma attuale')+'</h2>'+
      (wildShape?'<p>Scegli l’aspetto rispettando i limiti del tratto. Un utilizzo verrà consumato alla conferma.</p><label>PF della seconda forma (0 per nessuna riserva)<input data-form-hp type="number" min="0" max="99999" value="0"></label><p data-form-selection role="status">Nessuna forma selezionata.</p>':'')+
      '<label>Cerca miniatura<input type="search" data-miniature-search autocomplete="off"></label>'+
      '<div class="miniature-results" role="list"></div>'+
      '<div class="actions">'+(wildShape?'<button type="button" class="btn primary" data-form-confirm disabled>Trasformati</button>':'')+'<button type="button" class="btn" data-miniature-close>Annulla</button></div>';
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
    if(wildShape)dialog.querySelector('[data-form-confirm]').addEventListener('click',async event=>{
      const button=event.currentTarget;if(button.disabled||!selectedProfile)return;button.disabled=true;
      try{
        const current=state.editor?.read();if(!current||state.creatureId!==creatureId)throw Error('La creatura è cambiata.');
        const calculated=await computeLocalData(current);
        const changes=wildShapePatch(current,calculated,selectedProfile,dialog.querySelector('[data-form-hp]').value);
        await applyFormPatch(current,changes);dialog.close();await render();message('Forma selvatica applicata.');
      }catch(error){button.disabled=false;message(errorMessage(error),true);}
    });
    results.addEventListener('click',async event=>{
      const choice=event.target.closest('[data-miniature-id]');
      if(!choice)return;
      const id=choice.dataset.miniatureId;
      const profile=choices.find(row=>row.id===id);
      if(!profile||state.creatureId!==creatureId||!state.editor)return;
      if(wildShape){
        selectedProfile=profile;dialog.querySelector('[data-form-selection]').textContent=profile.name;
        dialog.querySelector('[data-form-confirm]').disabled=false;return;
      }
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
  if(act==='magic-tool-open'||act==='magic-select-spells'){
    state.sheetPopup='';
    if(state.sheet!=='magic')return;
    const type=act==='magic-select-spells'?'catalog':target.dataset.magicTool;
    if(!['concentration','slots','book','catalog','choices'].includes(type))return;
    if(act==='magic-select-spells'){
      state.spellClass=target.dataset.magicClass||'manual';
      state.spellTarget=target.dataset.magicTarget==='spellbook_spells'?'spellbook_spells':'prepared_spells';
      state.spellQuery='';
    }
    state.magicPopup=type;await render();return;
  }
  if(act==='magic-tool-close'){
    state.magicPopup="";
    const dialog=app.querySelector('#magic-tools-dialog');
    if(dialog){if(typeof dialog.close==='function')dialog.close();else dialog.remove();}
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
    dialog.querySelector('[data-save-variants]').addEventListener('click',async()=>{try{const selected=[...dialog.querySelectorAll('input[type=checkbox]:checked')].map(el=>el.value);await patch({action_variants_2014:selected});dialog.remove();await render();}catch{message('Impossibile salvare le varianti sul dispositivo');}});
    dialog.querySelector('[data-close-variants]').addEventListener('click',()=>dialog.remove());
    dialog.addEventListener('cancel',()=>dialog.remove(),{once:true});document.body.append(dialog);dialog.showModal();return;
  }
  if(act==='action-open-spells'){
    state.sheet='magic';await render();return;
  }
  if(act==='battle-cast-resource-spell'){
    const creature=state.editor?.read();
    if(!creature)throw Error('Apri una creatura prima di lanciare.');
    const calculated=await computeLocalData(creature);
    const grantId=String(target.dataset.grantId||'');
    const grant=(calculated.origin_spells||[]).find(row=>String(row.id)===grantId);
    const mode=grant?.payment_mode||(grant?.tracker_id?'tracker':'free');
    if(!grant||!['tracker','free'].includes(mode))
      throw Error('Concessione dell’incantesimo non disponibile.');
    const selection=sessionSpellEntries(creature,calculated,state.spellCatalog||[])
      .find(row=>row.id===grant.spell_id&&String(row.grant_id||'')===grantId);
    if(!selection)throw Error('Incantesimo non disponibile per questa creatura.');
    // Use the same validated spell-casting plan and targeting path as the
    // normal spell dialog; 0 means automatic payment for tracker/free grants.
    const plan=spellCastPlan(creature,selection,0,calculated,'auto');
    target.disabled=true;
    try{
      if(desktopHooks?.cast||(state.paired&&state.online)){
        await startTargetedCast(creature.id,structuredClone(selection),0,'auto');
      }else{
        if(Object.keys(plan.patch).length)await patch(plan.patch);
        await render();
        message('Lancio registrato nella scheda locale. Gli effetti sulla mappa richiedono una partita collegata.');
      }
    }catch(error){
      target.disabled=false;
      throw error;
    }
    return;
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
    // Object-targeted spells and infusions reuse typed eligibility, never prose
    // guessing. Catalogue/homebrew spells can declare item_target_selector.
    const targetSelector=detailed.item_target_selector||spell.item_target_selector||
      detailed.target_item_selector||spell.target_item_selector||null;
    const targetItems=targetSelector?targetableInventoryItems(record,targetSelector):[];
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
    const metaChoices=metamagicOptions(record).filter(o=>!['Empowered Spell','Seeking Spell'].includes(o.name));
    dialog.innerHTML='<h2>'+esc(spell.name||id)+'</h2>'+
      '<p class="hint magic-spell-metadata">'+(level===0?'Trucchetto':level===null?'Livello non specificato':'Livello '+level)+
      (spell.school?' · '+esc(spell.school):'')+(spell.source?' · '+esc(spell.source):'')+'</p>'+
      '<dl class="magic-spell-facts">'+spellFacts(detailed).map(({label,value})=>
         '<div class="magic-spell-fact"><dt>'+esc(label)+'</dt><dd>'+esc(value)+'</dd></div>').join('')+'</dl>'+ 
       '<div class="magic-spell-description">'+esc(description)+'</div>'+
      (detailed._description_warning?'<p class="hint">'+esc(detailed._description_warning)+'</p>':'')+
      (entry&&options.length?
        '<label>Livello di lancio / risorsa<select id="action-cast-choice">'+options.map(([value,label])=>'<option value="'+esc(value)+'">'+esc(label)+'</option>').join('')+'</select></label>':
        '<p class="hint">'+(entry?'Nessuna risorsa di lancio disponibile.':'Incantesimo non preparato: puoi consultarlo dal libro, ma non lanciarlo.')+'</p>')+
      (entry&&targetSelector?
        (targetItems.length?'<label>Oggetto bersaglio<select id="action-cast-item-target">'+
          targetItems.map(({item,index})=>'<option value="'+index+'">'+esc(item.name||item.id)+'</option>').join('')+'</select></label>':
         '<p class="warning">Nessun oggetto compatibile in inventario per questo incantesimo.</p>'):'')+
      (entry&&metaChoices.length?'<details class="metamagic-options"><summary>Metamagia</summary><label>Opzione<select data-metamagic-name><option value="">Nessuna</option>'+metaChoices.map(o=>'<option value="'+esc(o.name)+'">'+esc(o.name)+' · '+o.cost+' punti</option>').join('')+'</select></label><label class="check"><input data-metamagic-targets type="checkbox">Raddoppiato: confermo i requisiti di bersaglio del tratto per questa edizione</label><label class="check"><input data-metamagic-damage type="checkbox">Trasmutato: confermo che il danno originale sia elementale</label><label>Nuovo danno<select data-metamagic-element>'+['acid','cold','fire','lightning','poison','thunder'].map(e=>'<option>'+e+'</option>').join('')+'</select></label></details>':'')+
      '<div class="actions magic-dialog-actions">'+
      (entry&&options.length&&(!targetSelector||targetItems.length)?'<button type="button" class="btn primary" data-act="action-cast-confirm" data-spell-id="'+esc(entry.id)+'" data-grant-id="'+esc(entry.grant_id||'')+'" data-casting-class="'+esc(entry.casting_class||'')+'">Lancia</button>':'')+
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
    const detail=await detailedEntry('spells',{...selection,_category:'spells'});
    const selector=detail.item_target_selector||selection.item_target_selector||
      detail.target_item_selector||selection.target_item_selector||null;
    if(selector){
      const index=Number(app.querySelector('#action-cast-item-target')?.value);
      const matches=targetableInventoryItems(record,selector);
      const choice=matches.find(row=>row.index===index);
      if(!choice)throw Error('Scegli un oggetto bersaglio compatibile.');
      // Identity is preserved for the online targeting pipeline and local casts.
      selection.item_target={inventory_index:index,
        item_id:String(choice.item.id||''),instance_id:String(choice.item.instance_id||'')};
    }
    const metaName=app.querySelector('[data-metamagic-name]')?.value||'';
    if(metaName)selection.metamagic={names:[metaName],eligible_targeting:!!app.querySelector('[data-metamagic-targets]')?.checked,
      eligible_damage:!!app.querySelector('[data-metamagic-damage]')?.checked,damage_type:app.querySelector('[data-metamagic-element]')?.value||''};
    const choice=app.querySelector('#action-cast-choice')?.value||'';
    const [payment,levelText]=choice.split(':');const level=Number(levelText);
    if(!['auto','slot','pact'].includes(payment)||!Number.isInteger(level)||level<0||level>9)
      throw Error('Risorsa di lancio non valida.');
    if(desktopHooks?.cast||(state.paired&&state.online)){
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
  if(act==='battle-attack-map'){
    const creature=state.editor?.read();
    if(!creature)throw Error('Apri prima una creatura.');
    if(!state.paired||!state.online)throw Error('Collega la partita al desktop per vedere la gittata sulla mappa.');
    const attackId=String(target.dataset.mapAttackId||'');
    const calculated=await computeLocalData(creature);
    const attack=(calculated.attacks||[]).find(row=>String(row.id)===attackId);
    if(!attack)throw Error('Attacco non più disponibile. Aggiorna la scheda.');
    const liveMap=await map();
    const token=casterToken(creature,liveMap,await ownerId());
    if(!token)throw Error('Piazza o associa la creatura a un token prima di visualizzare la gittata.');
    if(!tacticalViewer)tacticalViewer=new TacticalViewer({send:action,ownerId,notify:message});
    await tacticalViewer.open(String(token.id),{
      range_feet:Number(attack.range_feet)||5,
      long_range_feet:Number(attack.long_range_feet)||0,
      melee:Boolean(attack.melee)
    });
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
  if(act==='edit-score'||act==='sheet-score-edit-base'){
    const scoreTarget=act==='edit-score'?
      'ability:'+String(target.dataset.abilityKey||''):
      String(target.dataset.scoreBaseTarget||'');
    if(!editableScoreBaseTarget(scoreTarget))throw Error('Valore base non modificabile');
    const creature=state.editor?.read();if(!creature)throw Error('Apri prima una creatura');
    const formula=document.querySelector('#sheet-score-formula-dialog');
    const returnTitle=formula?.querySelector('h2')?.firstChild?.textContent||'';
    if(formula){formula.close?.();formula.remove();}
    openSheetBaseEditor(creature,await computeLocalData(creature),scoreTarget,{returnTitle});
    return;
  }
  if(act==='sheet-base-auto-hp'){
    const dialog=document.querySelector('#sheet-score-dialog');
    if(dialog?.dataset.scoreTarget!=='hp')throw Error('Calcolo non applicabile');
    const creature=state.editor?.read(),calculated=await computeLocalData(creature);
    const automatic=calculated?.stats?.automatic_hp;
    if(!automatic?.available||!Number.isFinite(Number(automatic.value)))
      throw Error('PF automatici non disponibili');
    const input=dialog.querySelector('#sheet-score-input');
    input.value=String(Math.max(1,Math.trunc(automatic.value)));
    input.focus();return;
  }
  if(act==='save-score'){
    const dialog=document.querySelector('#sheet-score-dialog');
    const scoreTarget=String(dialog?.dataset.scoreTarget||'');
    if(!editableScoreBaseTarget(scoreTarget))throw Error('Valore base non modificabile');
    const input=dialog.querySelector('#sheet-score-input'),raw=input?.value?.trim();
    const value=Number(raw),ability=scoreTarget.startsWith('ability:')?scoreTarget.split(':')[1]:'';
    const min=scoreTarget==='second_max'?0:1,max=ability?30:99999;
    if(!raw||!Number.isInteger(value)||value<min||value>max)
      throw Error('Inserisci un valore intero tra '+min+' e '+max);
    const creature=state.editor?.read();if(!creature)throw Error('Apri prima una creatura');
    const change=ability?{abilities:{...creature.abilities,[ability]:value}}:
      scoreTarget==='hp'?{max_hp_base:value}:{second_form_max_hp:value};
    const returnTitle=String(dialog.dataset.returnFormulaTitle||'');
    await patch(change);
    dialog.close?.();dialog.remove();
    await render();
    if(returnTitle){
      const current=state.editor?.read();
      if(current)openSheetScoreFormula(current,await computeLocalData(current),scoreTarget,returnTitle);
    }
    return;
  }
  if(act==='close-score'){
    const dialog=document.querySelector('#sheet-score-dialog');
    const scoreTarget=dialog?.dataset.scoreTarget||'';
    const returnTitle=dialog?.dataset.returnFormulaTitle||'';
    dialog?.close?.();dialog?.remove();
    if(returnTitle&&state.editor){
      const creature=state.editor.read();
      openSheetScoreFormula(creature,await computeLocalData(creature),scoreTarget,returnTitle);
    }
    return;
  }
  if(act==='battle-damage-roll'){
    const formula=String(target.dataset.damageFormula||'');
    if(!formula||!state.editor)throw Error('Danni non disponibili.');
    const type=String(target.dataset.damageType||''),label=String(target.dataset.damageLabel||'Attacco');
    const attackId=String(target.dataset.damageAttackId||'');
    const creature=state.editor.read(),calculated=await computeLocalData(creature);
    const attack=(calculated.attacks||[]).find(row=>
      String(row.id)===attackId&&
      String(row.damage||'').replace(/\s+/g,'')===formula.replace(/\s+/g,''));
    const attackOrigin=attackGrantOrigin(calculated,attackId);
    const sourceAttack=attack?{...attack,origin_id:attackOrigin}:null;
    const preview=damageRollTerms(formula,type,sourceAttack);
    const bonuses=rollOptionalDice(creature,calculated,
      applicableDiceBonuses(creature,'attack_damage:'+attackId,state.spellCatalog||[]),
      {kind:'damage',attackId});
    const dialog=openUnifiedRollDialog({kind:'damage',heading:label,modifier:preview.modifier,
      rollType:'Tiro per danni',formula:sheetRollOriginHtml(preview.segments,esc),
      bonuses,creatureId:creature.id||'',damageFormula:formula,damageLabel:label,damageType:type});
    dialog.dataset.damageAttackId=attackId;
    dialog.rollAttack=sourceAttack;
    dialog.renderRollFormula=()=>{dialog.querySelector('[data-roll-formula]').innerHTML=sheetRollOriginHtml(
        [...damageRollTerms(formula,type,dialog.rollAttack).segments,...chosenRollBonuses(dialog).map(rollBonusTerm)],esc);};
    return;
  }
  if(act==='roll-trait-cancel'){
    const picker=document.querySelector('#roll-trait-picker');
    picker?.close?.();picker?.remove();return;
  }
  if(act==='roll-trait-pick'){
    const picker=document.querySelector('#roll-trait-picker');
    const key=picker?.querySelector('[data-roll-trait-key]')?.value;
    if(!state.traitRows.some(row=>row.key===key))throw Error('Tratto non disponibile');
    const kind=picker.dataset.benefitKind,targetKey=picker.dataset.benefitTarget;
    picker.close?.();picker.remove();
    state.traitPopupKey=key;state.traitPopupConfirm='';
    state.traitPopupDraftKind=kind;state.traitPopupDraftTarget=targetKey;
    mountTraitBenefitDialog();return;
  }
  if(act==='sheet-score-formula'){
    const creature=state.editor?.read();
    if(!creature)throw Error('Apri prima una creatura');
    const targetKey=String(target.dataset.calculated||target.dataset.target||'');
    if(!targetKey)throw Error('Valore non specificato');
    openSheetScoreFormula(creature,await computeLocalData(creature),targetKey,
      String(target.dataset.label||target.getAttribute('aria-label')||''));
    return;
  }
  if(act==='close-score-formula'){
    const dialog=document.querySelector('#sheet-score-formula-dialog');
    dialog?.close?.();dialog?.remove();return;
  }
  if(act==='sheet-score-add-bonus'){
    const dialog=document.querySelector('#sheet-score-formula-dialog');
    if(!dialog)return;
    const targetKey=String(dialog.dataset.scoreTarget||'');
    dialog.close?.();dialog.remove();
    await openRollTraitPicker('bonus',targetKey);return;
  }
  if(act==='sheet-roll-add-bonus'||act==='sheet-roll-add-applicable'){
    const dialog=document.querySelector('#sheet-roll-dialog');
    if(!dialog)return;
    const kind=act==='sheet-roll-add-bonus'?'bonus':'dice';
    const target=dialog.dataset.rollKind==='damage'?
      'attack_damage:'+String(dialog.dataset.damageAttackId||''):String(dialog.dataset.rollTarget||'');
    dialog.close?.();dialog.remove();
    await openRollTraitPicker(kind,target);return;
  }
  if(act==='sheet-roll-open-tracker'){
    const dialog=document.querySelector('#sheet-roll-dialog');
    const row=dialog?.rollBonuses[Number(target.dataset.rollTrackerButton)];
    const trackerId=String(row?.tracker_id||'');
    if(!trackerId)throw Error('Il bonus non ha un tracker associato.');
    const creature=state.editor?.read();
    if(!creature||creature.id!==dialog.dataset.creatureId)throw Error('La creatura del tiro è cambiata');
    dialog.close?.();dialog.remove();
    // Reuse the existing resource-detail popup instead of creating a second
    // tracker editor, keeping its counter, source and recovery controls.
    state.sheet='battle';state.sheetPopup='';await render();
    const button=[...app.querySelectorAll('#sheet-play-view [data-resource-tracker] .play-resource-info')]
      .find(node=>node.closest('[data-resource-tracker]')?.dataset.resourceTracker===trackerId);
    if(!button)throw Error('Tracker non disponibile nella scheda Battaglia');
    await handleAction(button);
    return;
  }
  if(act==='sheet-roll-use-bonus'){
    const dialog=document.querySelector('#sheet-roll-dialog');
    if(!dialog||dialog.dataset.rolling==='true')return;
    const index=Number(target.dataset.rollUse),row=dialog.rollBonuses[index];
    if(!row||chosenRollBonuses(dialog).some(b=>b.selectionId===row.selectionId))return;
    const creature=state.editor?.read();
    if(!creature||creature.id!==dialog.dataset.creatureId)throw Error('La creatura del tiro è cambiata');
    if(row.tracker_id){
      const fresh=await computeLocalData(creature);
      const tracker=(fresh.trackers||[]).find(t=>t.id===row.tracker_id&&!t.disabled);
      if(!tracker)throw Error('Tracker non disponibile');
      const remaining=Number(tracker.max||0)-Number(tracker.spent||0);
      if(remaining<Math.max(1,Number(row.tracker_cost)||1))
        message('Attenzione: '+(tracker.name||'risorsa')+' esaurito; il bonus viene usato comunque.',true);
      const used={...(creature.resource_tracker_spent||{})};
      used[row.tracker_id]=(Number(used[row.tracker_id])||0)+Math.max(1,Number(row.tracker_cost)||1);
      await patch({resource_tracker_spent:used});
      const trackerButton=dialog.querySelector('[data-roll-tracker-button="'+index+'"]');
      if(trackerButton){
        const summary=(tracker.name||'Tracker')+' · '+Math.max(0,remaining-Math.max(1,Number(row.tracker_cost)||1))+' rim.';
        trackerButton.title=summary;trackerButton.setAttribute('aria-label','Apri tracker '+summary);
      }
    }
    dialog.usedRollBonuses.push(row);
    target.textContent='Usato';target.dataset.rollUsed='true';target.disabled=true;
    dialog.renderRollFormula?.();
    return;
  }
  if(act==='roll-origin-open'){
    const dialog=document.querySelector('#sheet-roll-dialog')||
      document.querySelector('#sheet-score-formula-dialog');
    const originId=String(target.dataset.originId||''),section=String(target.dataset.originSection||'');
    const fallbackTarget=dialog?.dataset.scoreTarget||dialog?.dataset.rollTarget||'';
    dialog?.close?.();dialog?.remove();
    if(originId){await openRollTraitOrigin(originId);return;}
    if(section==='conditions'){state.sheet='conditions';await render();return;}
    // Never translate a provenance click into a blank add-bonus form.
    if(section==='proficiency_choices'){
      state.sheet='info';await render();
      state.sheetPopup='tools';state.sheetPopupTitle='Competenze';await render();return;
    }
    await openRollTraitPicker('bonus',fallbackTarget);return;
  }
  if(act==='sheet-roll'){
    const creature=state.editor?.read();if(!creature)throw Error('Apri prima una creatura');
    const key=String(target.dataset.target||'');
    const calculated=await computeLocalData(creature),modifier=calculated.values[key];
    if(!Number.isFinite(modifier))throw Error('Valore del tiro non disponibile');
    const label=target.dataset.label||'Tiro';
    const bonuses=rollOptionalDice(creature,calculated,
      applicableDiceBonuses(creature,key,state.spellCatalog||[]),{kind:'d20'});
    const autoSources=classFeatureRollSources(creature,calculated,key);
    const automatic=resolveClassRollMode(autoSources);
    const formulaMarkup=(chosen=[],choice='auto')=>{
      const resolved=resolveClassRollMode(autoSources,choice);
      return sheetRollOriginHtml(sheetRollOriginSegments(creature,calculated,key,
        {mode:resolved.mode,modeSources:resolved.sources,cancelled:resolved.cancelled,
          diceBonuses:chosen}),esc);
    };
    const autoLabel=automatic.cancelled?' · vantaggio e svantaggio annullati':
      automatic.mode==='advantage'?' · vantaggio':
      automatic.mode==='disadvantage'?' · svantaggio':'';
    const dialog=openUnifiedRollDialog({kind:'d20',heading:rollHeading(label,key),rollLabel:label,modifier,
      rollType:rollCategory(key,calculated),formula:formulaMarkup(),bonuses,autoLabel,
      creatureId:creature.id||'',target:key});
    dialog.renderRollFormula=()=>{
      const formula=dialog.querySelector('[data-roll-formula]');
      const choice=dialog.querySelector('[data-roll-mode]').value;
      if(formula)formula.innerHTML=formulaMarkup(chosenRollBonuses(dialog),choice);
    };
    dialog.addEventListener('change',event=>{
      if(event.target.matches('[data-roll-mode]'))dialog.renderRollFormula();
    });
    return;
  }
  if(act==='roll-sheet-confirm'){
    const dialog=document.querySelector('#sheet-roll-dialog');
    if(!dialog||dialog.dataset.rolling==='true')return;
    const creature=state.editor?.read();
    if(!creature||creature.id!==dialog.dataset.creatureId)throw Error('La creatura del tiro è cambiata');
    const button=dialog.querySelector('[data-act="roll-sheet-confirm"]');
    dialog.dataset.rolling='true';
    if(button)button.disabled=true;
    try{
      const result=dialog.querySelector('[data-roll-result]');
      if(dialog.dataset.rollKind==='damage'){
        const chosen=chosenRollBonuses(dialog);
        const fullFormula=dialog.dataset.damageFormula+chosen.map(row=>'+'+row.dice).join('');
        const outcome=rollBattleDamage(fullFormula,randomDie);
        state.roll={...outcome,label:'Danni · '+dialog.dataset.damageLabel+
          (dialog.dataset.damageType?' · '+dialog.dataset.damageType:''),author:selectedName()};
        state.rollHistory.unshift({...state.roll});
        result.hidden=false;
        result.innerHTML=rollDieResultMarkup(outcome);
        // Usage was spent by the explicit Usa action. Rerolling in this dialog
        // must not silently consume the same tracker again.
        dialog.renderRollFormula?.();
      }else{
        const key=dialog.dataset.rollTarget,label=dialog.dataset.rollLabel;
        const calculated=await computeLocalData(creature),modifier=calculated.values[key];
        if(!Number.isFinite(modifier))throw Error('Modificatore non disponibile.');
        const chosen=chosenRollBonuses(dialog);
        const choice=dialog.querySelector('[data-roll-mode]')?.value||'auto';
        const resolved=resolveClassRollMode(classFeatureRollSources(creature,calculated,key),choice);
        const outcome=rollSheetDice(modifier,chosen,randomDie,resolved.mode);
        state.roll={...outcome,label,author:selectedName()};
        state.rollHistory.unshift({...state.roll});
        result.hidden=false;
        result.innerHTML=rollDieResultMarkup(outcome);
        // Tracker uses were spent at selection time, never again on rerolls.
        const consumed=new Set(chosen.filter(row=>row.consumes_spell).map(row=>row.consumes_spell));
        if(consumed.size){
          // The next throw is independent. Previously consumed spell bonuses
          // must not be selectable or silently re-applied on a second click.
          dialog.usedRollBonuses=dialog.usedRollBonuses.filter(row=>!consumed.has(row.consumes_spell));
          for(const button of dialog.querySelectorAll('[data-roll-use]')){
            const row=dialog.rollBonuses[Number(button.dataset.rollUse)];
            if(consumed.has(row?.consumes_spell)){button.disabled=true;button.textContent='Esaurito';}
          }
          try{
            const live=state.editor.read(),contexts={...live.active_spell_context},enabled={...live.origin_enabled};
            for(const id of consumed){delete contexts[id];delete enabled['spell:'+id];}
            await patch({proficiency_origins:(live.proficiency_origins||[]).filter(o=>
              !consumed.has(String(o.id).slice(6))||o.group!=='spell'),
              active_spell_context:contexts,origin_enabled:enabled});
          }catch(error){message('Tiro registrato; consumo bonus non salvato: '+errorMessage(error),true);}
        }
        // Keep the next-roll formula in sync with the controls even after a
        // once-only bonus is consumed. Each click produces a new history entry.
        // Keep the per-dialog selection until the popup closes.
        dialog.renderRollFormula?.();
      }
      if(state.paired&&state.online){
        try{await shareRoll({quiet:true});}
        catch(error){

          message('Invio chat non riuscito: '+errorMessage(error),true);
        }
      }
    }finally{
      delete dialog.dataset.rolling;
      if(button&&button.isConnected)button.disabled=false;
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
      const level=Number(picker.value);
      await patch(current=>slotUsePatch(current,level,1,calculated));
    }else{
      const tracker=calculated.trackers.find(t=>t.id===grant.tracker_id),cost=Math.max(1,Number(grant.tracker_cost)||1);
      if(!tracker||tracker.max-tracker.spent<cost)throw Error('Utilizzi esauriti');
      await patch(current=>{
        const spent=Number(current.resource_tracker_spent?.[tracker.id]||0);
        if(spent+cost>tracker.max)throw Error('Utilizzi esauriti');
        return {resource_tracker_spent:{...current.resource_tracker_spent,[tracker.id]:spent+cost}};
      });
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
    else {
      const calculated=await computeLocalData(c);
      await patch(current=>slotUsePatch(current,Number(target.dataset.level),act==='slot-use'?1:-1,calculated));
    }
    await render();return;
  }
  if(act==='hp-damage'||act==='hp-heal'){
    const dialog=app.querySelector('#hp-adjust-dialog');
    if(!dialog)throw Error('Pannello punti ferita non disponibile.');
    const damage=act==='hp-damage';
    dialog.dataset.hpMode=damage?'damage':'heal';
    dialog.querySelector('#hp-adjust-title').textContent=damage?'Infliggi danni':'Cura punti ferita';
    dialog.querySelector('#hp-adjust-confirm').textContent=damage?'Applica danni':'Applica cura';
    const amount=dialog.querySelector('#hp-adjust-amount');
    amount.value='1';
    openSessionDialog(dialog);
    amount.focus();
    return;
  }
  if(act==='hp-adjust-cancel'){
    closeSessionDialog(app.querySelector('#hp-adjust-dialog'));
    return;
  }
  if(['hp-restore','hp-restore-second','hp-automatic'].includes(act)){
    const c=state.editor.read(),calculated=await computeLocalData(c);
    if(act==='hp-automatic'){
      if(!calculated.stats.automatic_hp.available)throw Error('PF automatici non disponibili');
      await patch({max_hp_base:calculated.stats.automatic_hp.value});
    }else if(act==='hp-restore')await patch({current_hp:Math.max(0,calculated.stats.max_hp)});
    else if(act==='hp-restore-second'){
      const maximum=Number(calculated.values?.second_max??c.second_form_max_hp??0);
      if(!Number.isFinite(maximum)||maximum<=0)throw Error('Imposta prima il massimo della seconda forma.');
      await patch({second_form_hp:Math.max(0,maximum)});
    }
    await render();return;
  }
  if(act==="tracker-powers"){state.magicPopup="";state.sheet="magic";await render();return;}
  if(act==="power-trait"){
    const id=target.dataset.originId||'';
    state.sheet="info";state.sheetPopup="";state.sheetPopupTitle="";
    await render();
    const cards=[...app.querySelectorAll('.play-info-traits .trait-card')];
    const feature=(state.calculated?.features||[]).find(f=>f.origin_id===id);
    const parts=id.split('|'),current=state.editor?.read()||{};
    let normalized=id;
    if(parts[0]==='race'&&String(current.species||'').toLowerCase()===parts.slice(2).join('|')){
      normalized='species|'+(current.species_id||parts.slice(2).join('|'))+'|'+parts[1];
    }else if(parts[0]==='subrace'&&String(current.subrace||'').toLowerCase()===parts.slice(2).join('|')){
      const raceKey=(current.species_id||String(current.species||'').toLowerCase());
      normalized='species|'+raceKey+'|'+String(current.species_source||'').toLowerCase();
    }else if(parts[0]==='feat'){
      const feat=(current.feats_catalog||[]).find(row=>
        String(row.name||'').toLowerCase()===parts.slice(2).join('|')&&
        String(row.source||'').toLowerCase()===parts[1]);
      if(feat)normalized='feat|'+(feat.id||parts.slice(2).join('|')+'|'+parts[1]);
    }
    const matchedByName=feature?cards.find(card=>{
      const name=String(card.querySelector('.trait-title')?.textContent||'').trim().toLowerCase();
      return (card.dataset.traitOrigin===feature.origin_key||
        card.dataset.traitFeature===feature.origin_id)&&
        (name===String(feature.name||'').toLowerCase()||
         name.startsWith(String(feature.name||'').toLowerCase()+' ·'));
    }):null;
    const match=cards.find(card=>card.dataset.traitFeature===id)||
      cards.find(card=>card.dataset.traitProficiency===id)||
      matchedByName||
      cards.find(card=>card.dataset.traitOrigin===id||card.dataset.traitOrigin===normalized||
        (feature?.origin_key&&card.dataset.traitOrigin===feature.origin_key));
    if(match){
      const disclosure=match.closest('.play-traits-disclosure');
      if(disclosure)disclosure.open=true;
      match.open=true;match.scrollIntoView?.({block:'center'});
    }
    else {
      // A missing provenance should never open the retired origins editor.
      message('Tratto non trovato nella scheda.');
    }
    return;
   }
  if(act==="new-homebrew-item"){
    const owner=state.creatureId||"";
    state.catalogCategory="items";state.catalogSelected=-1;state.catalogQuery="";
    await navigate("catalog");
    state.pendingItemOwner=owner;
    const creator=app.querySelector(".catalog-create");
    if(creator)creator.open=true;
    const name=app.querySelector("#quick-name");
    name?.scrollIntoView?.({block:"center"});
    name?.focus();
    return;
  }
  if(act==='feat-catalog'){
    state.featAssignReturnId=state.creatureId;
    state.catalogCategory='feats';state.catalogSelected=-1;state.catalogQuery='';
    await navigate('catalog');return;
  }
  if(act==='trait-state-end'){
    const trait=state.traitRows.find(row=>row.key===state.traitPopupKey);
    if(!trait?.readonly||!trait.state_key)throw Error('Stato non disponibile');
    const c=state.editor.read();
    if(trait.condition_id){
      const changes={conditions:(c.conditions||[]).filter(id=>id!==trait.condition_id)};
      if(trait.condition_id==='concentrating')changes.concentrating_spell_id='';
      await patch(changes);
      dismissTraitBenefitDialog();await render();return;
    }
    dismissTraitBenefitDialog();
    if(trait.spell_id)await handleAction({dataset:{act:'condition-remove-spell',spellId:trait.spell_id}});
    else await handleAction({dataset:{act:'condition-remove-ability',abilityKey:trait.state_key}});
    return;
  }
  if(act==='trait-benefits-open'){
    if(state.sheet!=='info')return;
    state.traitPopupDraftKind='';state.traitPopupDraftTarget='';
    const key=target.dataset.traitKey;
    if(!state.traitRows.some(row=>row.key===key))throw Error('Tratto non disponibile');
    state.traitPopupKey=key;state.traitPopupConfirm='';
    state.traitPopupTrait=state.traitRows.find(row=>row.key===key);
    mountTraitBenefitDialog();return;
  }
  if(act==='trait-benefits-toggle'){
    const trait=state.traitRows.find(row=>row.key===state.traitPopupKey)||
      (state.traitPopupTrait?.key===state.traitPopupKey?state.traitPopupTrait:null);
    if(!trait)throw Error('Tratto non disponibile');
    const record=state.editor.read();
    if(trait.category==='oggetti'&&trait.rank===0&&String(trait.origin_key||'').startsWith('item:')){
      const id=String(trait.origin_key).slice(5);
      const active=(record.inventory||[]).some(item=>String(item.id||'')===id&&
        (item.equipped===true||(item.equipped_slots||[]).length>0));
      const index=(record.inventory||[]).findIndex(item=>String(item.id||'')===id&&
        (active?(item.equipped===true||(item.equipped_slots||[]).length>0):true));
      if(index<0)throw Error('Oggetto non presente nell’inventario.');
      const inventory=setItemEquipped(record.inventory,index,!active);
      // The equipment state is authoritative; clear stale manual overrides.
      const enabledPatch=traitActivationPatch(record,trait,true);
      await patch({...enabledPatch,inventory});
    }else await patch(traitActivationPatch(record,trait,Boolean(trait.inactive)));
    await state.editor.flush();
    await render();return;
  }
  if(act==='trait-benefits-close'){dismissTraitBenefitDialog();return;}
  if(act==='trait-benefits-add'||act==='trait-benefits-cancel-add'){
    const editor=app.querySelector('#trait-benefits-dialog [data-trait-add-form]');
    if(editor)editor.hidden=act!=='trait-benefits-add';
    if(act==='trait-benefits-cancel-add'){
      state.traitPopupDraftKind='';state.traitPopupDraftTarget='';
    }
    return;
  }
  if(act==='trait-benefits-save'){
    const dialog=app.querySelector('#trait-benefits-dialog');
    const type=dialog?.querySelector('[data-trait-add-kind]')?.value||'';
    const fields=dialog?.querySelector('[data-trait-fields="'+type+'"]');
    const trait=state.traitRows.find(row=>row.key===state.traitPopupKey);
    if(!fields||!trait)throw Error('Tratto o campi mancanti');
    const values=Object.fromEntries([...fields.querySelectorAll('[name]')].map(node=>[node.name,node.value]));
    const changes=addBenefitPatch(state.editor.read(),trait,type,values,'trait:'+crypto.randomUUID());
    // Validate before committing, but do not write any draft field on input.
    if(type==='bonus'&&/Formula non applicata/.test(formulaPreview(values.expression,state.calculated)))
      throw Error('Formula non valida');
    if(type==='dice'&&!validBonusDice(values.dice))throw Error('Formula dei dadi non valida');
    await patch(changes);
    await state.editor.flush();
    // A persisted record may become visible before the asynchronous rerender.
    // Hide the now-committed draft synchronously to prevent an editable stale
    // form from lingering after Save, without discarding it on save failure.
    const form=dialog?.querySelector('[data-trait-add-form]');
    if(form)form.hidden=true;
    state.traitPopupConfirm='';state.traitPopupDraftKind='';state.traitPopupDraftTarget='';
    await render();return;
  }
  if(act==='trait-benefits-remove-request'){
    const trait=state.traitRows.find(row=>row.key===state.traitPopupKey);
    const id=target.dataset.benefitId;
    if(!trait||!traitBenefitGroups(trait,state.editor.read(),state.calculated)
      .some(group=>group.items.some(item=>item.id===id)))throw Error('Beneficio non presente');
    state.traitPopupConfirm=id;
    await render();return;
  }
  if(act==='trait-benefits-remove-cancel'){
    state.traitPopupConfirm='';
    await render();return;
  }
  if(act==='trait-benefits-remove-confirm'){
    const trait=state.traitRows.find(row=>row.key===state.traitPopupKey);
    const id=target.dataset.benefitId,type=target.dataset.benefitType;
    if(!trait||id!==state.traitPopupConfirm)throw Error('Eliminazione non confermata');
    const group=traitBenefitGroups(trait,state.editor.read(),state.calculated)
      .find(row=>row.type===type&&row.items.some(item=>item.id===id));
    if(!group)throw Error('Beneficio non più presente');
    await patch(removeBenefitPatch(state.editor.read(),trait,{id,type}));
    await state.editor.flush();
    state.traitPopupConfirm='';
    await render();return;
  }
  if(act==='trait-benefits-restore'){
    const trait=state.traitRows.find(row=>row.key===state.traitPopupKey);
    if(!trait)throw Error('Tratto non disponibile');
    await patch(restoreBenefitPatch(state.editor.read(),trait));
    await state.editor.flush();
    state.traitPopupConfirm='';
    await render();return;
  }
  if(act==="sheet-details"||act==="trait-benefit-open"||
      act==='edit-bonus'||act==='sheet-roll-edit-bonus'){
    state.sheet='info';state.sheetPopup='';state.traitPopupKey='';
    await render();
    const disclosure=app.querySelector('.play-traits-disclosure');
    if(disclosure){disclosure.open=true;disclosure.scrollIntoView?.({block:'nearest'});}
    message('Apri l’icona prima del nome di un tratto per gestire i benefici.');
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
        backgrounds_catalog:{name:"",source:"",disabled:false},
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
    const owner=state.pendingItemOwner;
    if(owner&&state.catalogCategory==="items"){
      const editor=await openCreatureEditor(owner);
      const record=editor.read();
      const item=createOwnedItem({...created.data,id:created.id,name:created.name,
        source:created.source}, "pwa_"+crypto.randomUUID());
      const inventory=[...(record.inventory||[]),item];
      await editor.update({inventory});
      state.page="library";state.libraryMode=false;state.creatureId=owner;
      state.editor=editor;state.sheet="inventory";state.inventorySubtab="items";
      state.inventorySelectedIndex=inventory.length-1;state.pendingItemOwner="";
      await render();message("Oggetto homebrew aggiunto all'inventario.");return;
    }
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
    await render();window.scrollTo(0,0);app.focus({preventScroll:true});return;
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
      const existing=(sheet.backgrounds_catalog||[]);
      const duplicate=[{name:sheet.background,source:sheet.background_source},...existing]
        .some(row=>row.name===entry.name&&String(row.source||"")===String(entry.source||""));
      if(duplicate)throw Error("Background già presente in questa scheda.");
      const changes=sheet.background?{backgrounds_catalog:[...existing,{name:entry.name,id:entry.id||"",source:entry.source||""}]}:
        {background:entry.name,background_id:entry.id||"",background_source:entry.source||""};
      await editor.update({...changes,...quickGrantPatch(sheet,entry)});
    }else if(category==="races"){
      await editor.update({species:entry.name,species_source:entry.source||""});
    }else throw new Error("Categoria non assegnabile alla scheda.");
    state.cachedCreatures=(await listCreatures()).map(row=>row.creature);
    if(category==='feats'&&state.featAssignReturnId===cId){
      state.featAssignReturnId='';state.creatureId=cId;state.editor=editor;
      state.page='library';state.libraryMode=false;state.sheet='info';
      state.sheetPopup='';await render();
    }
    message("Contenuto aggiunto; i benefici strutturati sono calcolati localmente.");
    return;
  }
  if(act==="refresh"){await render();return;}
  if(act==="demo"){
    state.creatureId=await createDemoCreature();state.libraryMode=false;state.editor=null;state.sheet="info";
    await render();message("Eroe dimostrativo creato solo su questo dispositivo.");return;
  }
  if(act==="library-export"||act==="library-delete"){
    const rows=(await listCreatures()).filter(row=>state.librarySelectedIds.has(row.creature.id));
    if(!rows.length)throw new Error("Seleziona almeno una creatura.");
    if(act==="library-export"){
      if(rows.length>200)throw new Error("Puoi esportare fino a 200 creature in un file.");
      download(await exportCreatureBatch(rows.map(row=>row.creature.id)),"vtt-creature-selezionate.json");
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
  if(act==="library-add"){
    const dialog=app.querySelector('#library-create-dialog');
    if(dialog){if(typeof dialog.showModal==='function')dialog.showModal();else dialog.setAttribute('open','');}
    return;
  }
  if(act==="library-create-close"){
    const dialog=app.querySelector('#library-create-dialog');
    if(dialog){if(typeof dialog.close==='function')dialog.close();else dialog.removeAttribute('open');}
    return;
  }
  if(act==="create"){
    state.magicPopup="";
    const row=await createCreature("character","Nuovo personaggio");
    state.creatureId=row.id;state.libraryMode=false;state.editor=null;state.sheet="info";await render();return;
  }
  if(act==="import"){
    const dialog=app.querySelector('#library-create-dialog');
    if(dialog?.open){if(typeof dialog.close==='function')dialog.close();else dialog.removeAttribute('open');}
    creatureInput.click();return;
  }
  if(act==="restore-backup"){backupInput.click();return;}
  if(act==="backup"){
    const blob=await exportBackup();download(blob,"vtt-pwa-backup-"+new Date().toISOString().slice(0,10)+".json");
    message("Backup esportato. Conservalo fuori dal browser.");
    return;
  }
  if(act==="open"){state.magicPopup="";state.creatureId=target.dataset.id;state.libraryMode=false;state.sheet="info";state.editor=null;await render();return;}
  if(act==="back"){
    await navigate("library");
    window.scrollTo(0,0);app.focus({preventScroll:true});
    return;
  }
  if(act==="sheet"){
    state.magicPopup="";
    try{await state.editor?.flush();}catch(error){throw new Error("Salvataggio incompleto: "+errorMessage(error));}
    if(!state.creatureId)return;
    state.sheetPopup=target.dataset.openContext||"";state.sheetPopupTitle=target.title||"";state.page="library";state.libraryMode=false;state.sheet=['actions','traits'].includes(target.dataset.sheet)?(target.dataset.sheet==='traits'?'info':'battle'):target.dataset.sheet;await render();return;
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
    state.creatureId=null;state.libraryMode=true;state.editor=null;await render();message("Scheda eliminata.");return;
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
      await patch(current=>{
        const spent={...(current.resource_tracker_spent||{})};delete spent[row.id];
        return {resource_trackers:(current.resource_trackers||[]).filter(tracker=>tracker.id!==row.id),
          resource_tracker_spent:spent};
      });
    }else{
      if(act==='tracker-recharge'){
        if(row.recharge!=='d6')throw Error('Questa risorsa non usa la ricarica d6');
        const die=randomDie(6),success=die>=Number(row.recharge_min||6);
        if(success)await patch(current=>{
          const spent={...(current.resource_tracker_spent||{})};delete spent[row.id];
          return {resource_tracker_spent:spent};
        });
        await render();message(row.name+': d6 = '+die+' · '+(success?'Ricaricata':'Non ricaricata'));return;
      }
      // Reuse the domain operation; no stale zero-valued spent counters.
      await patch(current=>changeTrackerUses(current,row.id,act==="tracker-more"?1:-1,calculated.trackers));
    }
    await render();return;
  }
  if(act==='tracker-optional-recovery'){
    const record=state.editor.read(),calculated=await computeLocalData(record);
    await patch(current=>{
      const change=optionalRecoveryPatch(current,target.dataset.ruleId,calculated.trackers);
      if(!change)throw Error('Questo recupero è già stato usato o non è disponibile dopo un riposo breve.');
      return change;
    });await render();return;
  }
  if(["tracker-short","tracker-long","tracker-turn"].includes(act)){
    const record=state.editor.read(),calculated=await computeLocalData(record);
    if(act==='tracker-turn'){
      await patch(current=>recoveryPatch(current,'turn',calculated.trackers));await render();return;
    }
    const dialog=app.querySelector('#sheet-context-dialog');
    if(!dialog||dialog.dataset.context!=='rests')throw Error('Apri il pannello Riposi prima di continuare.');
    const event=act==='tracker-long'?'long_rest':'short_rest';
    const extra=dialog.querySelector('.sheet-context-body');
    extra.querySelector('.play-rest-choices')?.setAttribute('hidden','');
    extra.querySelector('[data-rest-preview]')?.remove();
    const pools=event==='short_rest'?hitDicePools(record,calculated):[];
    const diceControls=pools.map(pool=>'<label class="play-rest-die">'+
      '<span>d'+pool.die+' · '+pool.available+' / '+pool.total+' disponibili</span>'+
      '<input type="number" inputmode="numeric" data-rest-die="'+pool.die+
      '" min="0" max="'+pool.available+'" step="1" value="0" aria-label="Dadi Vita d'+pool.die+' da spendere"></label>').join('');
    const preview=document.createElement('section');
    preview.className='play-rest-confirm';preview.dataset.restPreview=event;
    preview.innerHTML='<h3>Conferma '+(event==='long_rest'?'riposo lungo':'riposo breve')+'</h3>'+
      (event==='short_rest'?
        '<div class="play-rest-dice"><strong>Dadi Vita da spendere</strong>'+
          (diceControls||'<p>Nessun Dado Vita disponibile.</p>')+'</div>':'')+
      '<div class="play-rest-recovery" data-rest-recoveries aria-live="polite"></div>'+
      (event==='short_rest'&&pools.length?
        '<div data-rest-roll-controls hidden>'+
          '<label>Come determinare i risultati dei Dadi Vita<select data-rest-roll-mode>'+
            '<option value="roll">Tira in app</option><option value="manual">Inserisci i risultati</option>'+
          '</select></label>'+
          '<label data-rest-manual-label hidden>Risultato di ciascun dado, separato da virgole'+
            '<input type="text" data-rest-manual-results placeholder="Es. 5, 7, 3" autocomplete="off" inputmode="text">'+
          '</label></div>':'')+
      '<p data-rest-error class="warning" role="alert"></p>'+
      '<div class="actions"><button type="button" class="btn primary" data-act="tracker-rest-confirm">Conferma riposo</button>'+
      '<button type="button" class="btn" data-act="tracker-rest-back">Indietro</button></div>';
    extra.append(preview);
    const updateForecast=()=>{
      const dice={},error=preview.querySelector('[data-rest-error]');
      error.textContent='';
      for(const control of preview.querySelectorAll('[data-rest-die]')){
        const amount=Number(control.value);
        if(!Number.isInteger(amount)||amount<0||amount>Number(control.max)){
          error.textContent='Scegli una quantità valida di Dadi Vita.';
          preview.querySelector('[data-act="tracker-rest-confirm"]').disabled=true;
          return;
        }
        dice['d'+control.dataset.restDie]=amount;
      }
      // No random rolls and no write to the creature during the forecast.
      const forecast=restRecoveryPreview(record,event,calculated,dice);
      const chosen=Object.values(dice).reduce((sum,n)=>sum+n,0);
      preview.dataset.restDice=JSON.stringify(dice);
      const grouped=new Map();
      for(const entry of forecast.entries){
        if(!grouped.has(entry.group))grouped.set(entry.group,[]);
        grouped.get(entry.group).push(entry);
      }
      preview.querySelector('[data-rest-recoveries]').innerHTML=
        '<h4>Recuperi previsti</h4>'+
        [...grouped.entries()].map(([group,rows])=>
          '<section class="play-rest-recovery-group"><h5>'+esc(group)+'</h5><ul>'+
          rows.map(row=>'<li><strong>'+esc(row.name)+'</strong><span>'+esc(row.detail)+'</span></li>').join('')+
          '</ul></section>').join('');
      const modeArea=preview.querySelector('[data-rest-roll-controls]');
      if(modeArea)modeArea.hidden=chosen===0;
      const manualLabel=preview.querySelector('[data-rest-manual-label]');
      if(manualLabel)manualLabel.hidden=chosen===0||preview.querySelector('[data-rest-roll-mode]').value!=='manual';
      preview.querySelector('[data-act="tracker-rest-confirm"]').disabled=false;
    };
    preview.querySelectorAll('[data-rest-die]').forEach(control=>control.addEventListener('input',updateForecast));
    preview.querySelector('[data-rest-roll-mode]')?.addEventListener('change',updateForecast);
    updateForecast();
    return;
  }
  if(act==='tracker-rest-back'){
    const dialog=app.querySelector('#sheet-context-dialog');
    dialog?.querySelector('[data-rest-preview]')?.remove();
    dialog?.querySelector('.play-rest-choices')?.removeAttribute('hidden');
    return;
  }
  if(act==='tracker-rest-confirm'){
    const dialog=app.querySelector('#sheet-context-dialog');
    const preview=dialog?.querySelector('[data-rest-preview]');
    if(!preview||preview.dataset.restDone==='true')throw Error('Conferma del riposo non disponibile.');
    const event=preview.dataset.restPreview,dice=JSON.parse(preview.dataset.restDice||'{}');
    const current=state.editor.read(),calculated=await computeLocalData(current);
    const manual=preview.querySelector('[data-rest-roll-mode]')?.value==='manual';
    const values=manual?String(preview.querySelector('[data-rest-manual-results]')?.value||'').split(/[,;\s]+/).filter(Boolean).map(Number):[];
    const expected=Object.values(dice).reduce((sum,n)=>sum+Number(n||0),0);
    const diceOrder=hitDicePools(current,calculated).filter(pool=>dice['d'+pool.die]>0)
      .flatMap(pool=>Array(Number(dice['d'+pool.die])).fill(pool.die));
    if(manual&&(values.length!==expected||values.some((number,i)=>!Number.isInteger(number)||number<1||number>diceOrder[i]))){
      preview.querySelector('[data-rest-error]').textContent='Inserisci un risultato valido per ciascuno dei '+expected+' Dadi Vita.';return;
    }
    const button=preview.querySelector('[data-act="tracker-rest-confirm"]');button.disabled=true;
    try{
      let result;
      await patch(record=>{
        let index=0;
        result=completeRest(record,event,calculated,dice,manual?()=>values[index++]:randomDie);
        return result.patch;
      });
      if(state.saveError)throw Error(state.saveError);
      await state.editor.flush();
      preview.dataset.restDone='true';
      const summary=dialog.querySelector('.sheet-context-body');
      const rolled=result.rolls.length?'<ul>'+result.rolls.map(r=>
        '<li>d'+r.die+' = '+r.roll+' · COS '+(r.modifier>=0?'+':'')+r.modifier+
        ' · recupero potenziale '+r.healed+' PF</li>').join('')+'</ul>':'';
      // Report the actual saved differences, not a generic recovery message.
      const recovered=[];
      for(const row of calculated.trackers||[]){
        const before=Math.max(0,Number(current.resource_tracker_spent?.[row.id]||0));
        const after=Math.max(0,Number(result.patch.resource_tracker_spent?.[row.id]||0));
        if(before>after)recovered.push(row.name+': '+(before-after)+' usi');
      }
      const pactBefore=Math.max(0,Number(current.pact_slots_spent||0));
      const pactAfter=Math.max(0,Number(result.patch.pact_slots_spent??pactBefore));
      if(pactBefore>pactAfter)recovered.push('Slot del Patto: '+(pactBefore-pactAfter));
      const beforeSlots=current.spell_slots_spent||[],afterSlots=result.patch.spell_slots_spent;
      if(Array.isArray(afterSlots))for(let level=1;level<Math.max(beforeSlots.length,afterSlots.length);level++){
        const restored=Math.max(0,Number(beforeSlots[level]||0)-Number(afterSlots[level]||0));
        if(restored)recovered.push('Slot livello '+level+': '+restored);
      }
      const beforeDice=hitDicePools(current,calculated);
      for(const pool of beforeDice){
        const restored=Math.max(0,pool.spent-Number(result.patch.hit_dice_spent?.['d'+pool.die]||0));
        if(restored)recovered.push('Dadi Vita d'+pool.die+': '+restored);
      }
      const exhaustion=Math.max(0,Number(current.exhaustion||0)-Number(result.patch.exhaustion??current.exhaustion??0));
      if(exhaustion)recovered.push('Indebolimento: '+exhaustion+' livello rimosso');
      const recoveryHtml=recovered.length?'<ul>'+recovered.map(row=>'<li>'+esc(row)+'</li>').join('')+'</ul>':
        '<p>Nessun altro recupero effettuato.</p>';
      summary.innerHTML='<div class="play-rest-confirm"><h3>Riposo completato</h3>'+
        '<p><strong>'+result.healed+' PF recuperati.</strong></p>'+rolled+
        '<h4>Risorse recuperate</h4>'+recoveryHtml+
        '<button type="button" class="btn primary" data-act="sheet-context-close">Chiudi</button></div>';
    }catch(error){
      button.disabled=false;
      preview.querySelector('[data-rest-error]').textContent=errorMessage(error);
    }
    return;
  }
  if(['infusion-learn','infusion-prepare','infusion-start','infusion-confirm',
      'infusion-cancel','infusion-forget','infusion-clear'].includes(act)){
    const creature=state.editor.read(),calculated=await computeLocalData(creature);
    const definitions=calculated.infusion_catalog,mechanics=calculated.infusion_mechanics;
    const features=calculated.features||[],known=learnedInfusions(creature,definitions);
    const selected=known[Number(target.dataset.index??state.infusionPending)];
    if(act==='infusion-start'){
      if(!selected||!isInfusionPrepared(creature,selected,definitions))throw Error('Prepara prima l’infusione.');
      state.infusionPending=Number(target.dataset.index);state.sheetPopup='infusions';state.sheetPopupTitle='Applica infusione';await render();return;
    }
    if(act==='infusion-cancel'){state.infusionPending=-1;state.sheetPopup='';await render();return;}
    let changes;
    if(act==='infusion-learn'){
      const option=definitions.find(row=>row.id===app.querySelector('#infusion-available')?.value);
      changes=learnInfusionPatch(creature,option,definitions,mechanics,Number(app.querySelector('#infusion-plan')?.value??-1),features);
    }else if(act==='infusion-prepare'){
      changes=prepareInfusionPatch(creature,selected,definitions,features,!isInfusionPrepared(creature,selected,definitions));
    }else if(act==='infusion-confirm'){
      if(!selected)throw Error('Infusione non selezionata.');
      const index=Number(app.querySelector('#infusion-item')?.value);
      changes=applyInfusionPatch(creature,selected,definitions,mechanics,index,features);
      state.infusionPending=-1;state.sheetPopup='';
    }else if(act==='infusion-forget'){
      changes=forgetInfusionPatch(creature,selected);
      state.infusionPending=-1;state.sheetPopup='';
    }else changes=clearInfusionPatch(creature,Number(target.dataset.index));
    await patch(changes);await render();return;
  }
  if(act==="inventory-subtab"){
    const subtab=target.dataset.subtab;
    if(!["items","scrolls","documents"].includes(subtab))throw Error("Sottoscheda inventario non valida.");
    state.inventorySubtab=subtab;state.sheetPopup="";state.inventoryMenuIndex=-1;
    await render();return;
  }
  if(act==="inventory-select"){
    state.inventorySelectedIndex=Number(target.dataset.index);
    state.inventoryMenuIndex=-1;
    await render();return;
  }
  if(act==="inventory-menu"){
    const index=Number(target.dataset.index);
    state.inventoryMenuIndex=state.inventoryMenuIndex===index?-1:index;
    await render();return;
  }
  if(act==="inventory-view-catalog"){
    const item=state.editor.read().inventory?.[Number(target.dataset.index)];
    if(!item)throw Error("Oggetto non trovato.");
    state.catalogCategory="items";state.catalogQuery=String(item.name||"");
    state.catalogSelected=-1;await navigate("catalog");return;
  }
  if(act==="inventory-equip"){
    const record=state.editor.read(),index=Number(target.dataset.index);
    const owned=record.inventory?.[index];
    if(!owned)throw Error("Oggetto non trovato.");
    const enabled=!(owned.equipped===true||(owned.equipped_slots||[]).length>0);
    const inventory=setItemEquipped(record.inventory,index,enabled);
    const itemKey='item:'+String(owned.id||'');
    const trait=(state.traitRows||[]).find(row=>row.origin_key===itemKey);
    const overrides=trait?traitActivationPatch(record,trait,true):{};
    await patch({...overrides,inventory});
    state.inventorySelectedIndex=index;
    await render();return;
  }
  if(act==="inventory-quantity"){
    const record=state.editor.read(),index=Number(target.dataset.index);
    const qty=Number(record.inventory?.[index]?.quantity??1)+Number(target.dataset.delta||0);
    if(!Number.isInteger(qty)||qty<0||qty>99999)throw Error("Quantità fuori intervallo.");
    if(qty===0){
      state.sheetPopup="";
      const rows=structuredClone(record.inventory||[]);
      rows.splice(index,1);
      state.inventorySelectedIndex=Math.max(0,index-1);
      await patch({inventory:rows});
    }else await patch({inventory:changeOwnedItem(record.inventory,index,"quantity",qty)});
    await render();return;
  }
  if(act==="scroll-spell-add"){
    if(state.inventorySubtab!=="scrolls"||!state.editor)throw Error("Apri la sezione Pergamene della creatura.");
    const c=state.editor.read(),spellId=app.querySelector('#scroll-spell-select')?.value;
    const spell=spellsForEdition(state.spellCatalog||[],c.rules_version).find(s=>String(s.id)===spellId);
    const level=app.querySelector('#scroll-spell-level')?.value;
    if(!spell||level===undefined||level==='')throw Error("Seleziona un incantesimo e un livello.");
    const created=addSpellScroll(c.inventory||[],{...spell,description:flattenDescription(spell)},level,"pwa_"+crypto.randomUUID());
    state.inventorySelectedIndex=created.index;state.sheetPopup='';state.scrollSpellQuery='';
    await patch({inventory:created.inventory});await render();message("Pergamena aggiunta all'inventario.");return;
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
    state.sheetPopup="item:"+(record.inventory||[]).length;state.sheetPopupTitle="Nuovo documento";
    await patch({inventory:[...(record.inventory||[]),owned]});
    await render();return;
  }
  if(act==="document-remove"){
    const index=Number(target.dataset.index),record=state.editor.read();
    const inventory=structuredClone(record.inventory||[]);
    if(!isDocument(inventory[index]))throw Error("Documento non valido.");
    inventory.splice(index,1);state.openDocumentInstance="";state.sheetPopup="";
    await patch({inventory});await render();return;
  }
  if(act==="remove-item"){
    const c=state.editor.read(),inventory=structuredClone(c.inventory||[]);
    const index=Number(target.dataset.index);
    inventory.splice(index,1);
    state.inventorySelectedIndex=Math.max(0,index-1);
    state.inventoryMenuIndex=-1;state.sheetPopup="";
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
    await unpair();stopSubscriptions();state.sessionPane='connection';state.paired=false;state.session=null;state.map=null;
    state.messages=[];state.after="";state.tokenId="";currentGameSession="";state.desktopConditionCatalog=null;state.conditionCatalog=state.offlineConditionCatalog;
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
    if(state.tokenId!==target.dataset.id)sessionMapViewer.reset();
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
  if(act==="toggle-chat-notifications"){
    try {
      const enabled=await toggleChatNotifications();
      // Permission UI can temporarily background the app. Do not rebuild the
      // entire session screen after the permission prompt closes.
      const button=document.querySelector('[data-act="toggle-chat-notifications"]');
      if(button)button.textContent=enabled?"🔔 Attive":"🔕 Notifiche";
      message(enabled?"Notifiche abilitate.":"Notifiche disabilitate.");
    } catch(error) { message(errorMessage(error),true); }
    return;
  }
  if(act==="open-chat-dice"){openDiceDialog();return;}
  if(act==="close-chat-dice"){const dlg=document.querySelector("#chat-dice-dialog");if(dlg){if(typeof dlg.close==="function")dlg.close();else dlg.remove();}return;}
  if(act==="select-die"){
    state.diceSides=Number(target.dataset.sides);
    const dlg=document.querySelector("#chat-dice-dialog");
    dlg?.querySelectorAll("[data-act='select-die']").forEach(button=>button.setAttribute("aria-pressed",String(Number(button.dataset.sides)===state.diceSides)));
    const rollButton=dlg?.querySelector("[data-act='roll']");
    if(rollButton)rollButton.textContent="Tira d"+state.diceSides;
    return;
  }
  if(act==="roll"){await roll(state.diceSides);return;}
}
async function handleSubmit(form){
  if(form.id==='hp-adjust-form'){
    const dialog=form.closest('#hp-adjust-dialog');
    const mode=dialog?.dataset.hpMode;
    if(mode!=='damage'&&mode!=='heal')throw Error('Operazione sui PF non valida.');
    const amount=Number(form.querySelector('#hp-adjust-amount')?.value);
    if(!Number.isSafeInteger(amount)||amount<1||amount>99999)throw Error('Inserisci un valore di PF tra 1 e 99999.');
    if(!state.editor)throw Error('Apri prima una scheda.');
    const creature=state.editor.read(),calculated=await computeLocalData(creature);
    const changes=hitPointPatch(creature,mode==='damage'?-amount:amount,calculated);
    await patch(changes);
    closeSessionDialog(dialog);
    await render();
    if(mode==='damage'&&creature.active_class_features?.wild_shape&&creature.second_form_hp>0&&changes.second_form_hp===0)
      promptEndWildShape(creature.id);
    return;
  }
  if(form.id==="pair-form"){
    const token=document.querySelector("#pair-secret")?.value.trim()||"";
    const pairedSession=await pair(token,{remember:document.querySelector("#pair-remember")?.checked});
    acceptSession(pairedSession);
    realtimeStopped=false;
    state.paired=true;state.online=true;state.sessionPane='table';
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
    state.chatAuthor=author==="Giocatore"?"":author;
    const event={id:"pwa_"+crypto.randomUUID(),kind:"chat",author:author.slice(0,80),
      timestamp:Math.floor(Date.now()/1000),text:body};
    const result=await action("chat_send",{event});
    if(!result.ok)throw new Error(result.error||"Messaggio rifiutato");
    document.querySelector("#chat-message").value="";
    await fetchChat();
  }
}
function listen(){
  window.addEventListener('popstate',event=>{void restoreBrowserScreen(event.state?.__vttMobileScreen);});
  document.addEventListener("change",e=>{
    if(e.target?.id==="chat-author")state.chatAuthor=e.target.value||"";
    if(e.target?.matches('[data-trait-add-kind]')){
      const dialog=e.target.closest('#trait-benefits-dialog');
      for(const fields of dialog?.querySelectorAll('[data-trait-fields]')||[])
        fields.hidden=fields.dataset.traitFields!==e.target.value;
    }
  });
  document.addEventListener("click", async e=>{
    const button=e.target.closest("button[data-nav],button[data-act]");
    if(!button){
      // An HP card is a single click target, except for its own controls.
      const card=e.target.closest('#sheet-play-view .play-health[data-act="sheet-context"]');
      if(card&&!e.target.closest('button,input,select,textarea,a,[role="button"]:not(.play-health)')){
        try{await flushPendingFields();await handleAction(card);}
        catch(error){message(errorMessage(error),true);}
      }
      return;
    }
    // Modal dismissal is UI-only. Do it before any asynchronous field flush:
    // a dirty input, slow IndexedDB transaction or rerender cannot block X.
    const closeAction=button.dataset.act;
    if(closeAction==='trait-benefits-close'){
      dismissTraitBenefitDialog();return;
    }
    if(closeAction==='roll-trait-cancel'){
      const dialog=document.querySelector('#roll-trait-picker');
      if(dialog){if(dialog.open&&dialog.close)dialog.close();dialog.remove();}
      return;
    }
    if(closeAction==='close-score-formula'){
      const dialog=document.querySelector('#sheet-score-formula-dialog');
      if(dialog){if(dialog.open&&dialog.close)dialog.close();dialog.remove();}
      return;
    }
    if(closeAction==='close-sheet-roll'){
      const dialog=document.querySelector('#sheet-roll-dialog');
      if(dialog){if(dialog.open&&dialog.close)dialog.close();dialog.remove();}
      return;
    }
    if(closeAction==='action-cast-cancel'||closeAction==='magic-tool-close'){
      if(closeAction==='magic-tool-close')state.magicPopup='';
      const dialog=document.querySelector(closeAction==='action-cast-cancel'?
       '#action-cast-dialog':'#magic-tools-dialog');
      if(dialog){if(dialog.open&&dialog.close)dialog.close();dialog.remove();}
      return;
    }
    if(button.disabled)return;
    button.disabled=true;
    try {
      await flushPendingFields();
      const isDestination=Boolean(button.dataset.nav)||button.dataset.act==='sheet';
      if(button.dataset.nav)await navigate(button.dataset.nav);
      else await handleAction(button);
      if(isDestination){window.scrollTo(0,0);app.focus({preventScroll:true});}
    }catch(error){message(errorMessage(error),true);}
    finally{if(button.isConnected&&!button.hasAttribute('data-roll-used'))button.disabled=false;}
  });
  document.addEventListener('keydown',e=>{
    const card=e.target.closest?.('#sheet-play-view .play-health[role="button"]');
    if(e.target!==card||!['Enter',' '].includes(e.key))return;
    e.preventDefault();card.click();
  });
  // Right-click (and touch long-press where the browser emits contextmenu)
  // opens the same per-item actions as the explicit touch-friendly ⋯ button.
  app.addEventListener("contextmenu",e=>{
    const row=e.target?.closest?.("[data-inventory-row]");
    if(!row||state.sheet!=="inventory"||!state.editor)return;
    e.preventDefault();
    const index=Number(row.dataset.inventoryRow);
    if(!Number.isInteger(index))return;
    state.inventoryMenuIndex=index;
    state.inventorySelectedIndex=index;
    render().catch(error=>message(errorMessage(error),true));
  });
  app.addEventListener("submit",async e=>{
    if(!(e.target instanceof HTMLFormElement))return;
    e.preventDefault();
    const button=e.target.querySelector('[type="submit"]');if(button)button.disabled=true;
    try{await handleSubmit(e.target);}catch(error){message(errorMessage(error),true);}
    finally{if(button&&button.isConnected)button.disabled=false;}
  });
  const editable = "[data-coin-code],[data-slot-weapon-size],[data-inventory-attunement-max],[data-requirement],[data-origin-config],[data-tracker-field],[data-origin-enabled],[data-auto-bonus],[data-native-pick],[data-casting-section],[data-slot-total],[data-pact-total],[data-document-index],[data-equip-slot],[data-reference],[data-native-list],[data-native-cr],[data-field],[data-ability],[data-slot],[data-item-index],[data-item-override],[data-condition],[data-token-condition]";
  app.addEventListener("input",e=>{
    const target=e.target;
    if(target?.matches('[data-play-search]')){
      state.sheetSearch.set(state.creatureId+'|'+state.sheet,target.value);
      const query=target.value.trim().toLocaleLowerCase('it');
      for(const row of app.querySelectorAll('#sheet-play-view [data-play-filter]'))row.hidden=!row.dataset.playFilter.includes(query);
      return;
    }
    if(target?.id==="scroll-spell-query"){
      state.scrollSpellQuery=target.value;
      const select=app.querySelector('#scroll-spell-select');
      if(select)select.innerHTML=scrollSpellSelectOptions(target.value);
      updateScrollSpellLevels();return;
    }
    if(target?.id==="condition-spell-search"){fillAppliedSpellOptions(target.value);return;}
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
    if(target?.matches?.('[data-library-select-all]')){
      for(const box of app.querySelectorAll('input[data-library-select]')){
        box.checked=target.checked;
        if(box.checked)state.librarySelectedIds.add(box.dataset.librarySelect);
        else state.librarySelectedIds.delete(box.dataset.librarySelect);
      }
      syncLibrarySelectionUI();return;
    }
    if(target?.dataset?.librarySelect){
      if(target.checked)state.librarySelectedIds.add(target.dataset.librarySelect);
      else state.librarySelectedIds.delete(target.dataset.librarySelect);
      syncLibrarySelectionUI();return;
    }
    if(target?.id==="scroll-spell-select"){updateScrollSpellLevels();return;}
    if(target?.id==="spell-target"){
      state.spellTarget=target.value==="spellbook_spells"?"spellbook_spells":"prepared_spells";
      render().catch(error=>message(errorMessage(error),true));return;
    }
    if(target?.id==='spell-class'){
      state.spellClass=target.value;
      state.spellTarget='prepared_spells';
      state.spellQuery='';
      render().catch(error=>message(errorMessage(error),true));return;
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
      state.libraryMode=imported.length!==1;state.editor=null;state.sheet="info";
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
    // The archive remains fully editable; refresh only connection indicators.
    refreshConnection(true).catch(error=>message(errorMessage(error),true));
  });
}
// Allows tests and future app lifecycle handlers to release polling resources.
export function stopRealtime() { realtimeStopped=true;stopSubscriptions(); }

// The public 5etools catalog ships with the PWA and is precached. Load it
// after first paint so an offline desktop never delays the creature archive.
async function loadBundledConditionCatalog(){
 try{
  const response=await fetch("/catalog/effects_5etools.json");
  if(!response.ok)throw Error("HTTP "+response.status);
  const local=conditionCatalogFrom5etools(await response.json());
  state.offlineConditionCatalog=local;
  state.conditionCatalog=mergeConditionCatalog(local,state.desktopConditionCatalog);
  if((state.page==="library"&&!state.libraryMode&&["conditions","battle"].includes(state.sheet))||
    (state.page==="session"&&state.editTokenId))await render();
 }catch(error){console.warn("Bundled 5etools effects not available; using standard conditions",error);}
}

// Notification taps should return to the live chat, not just focus the page.
function openChatFromNotification(){
  if(!state.paired) return;
  if(state.page!=="session") void navigate("session");
  else { state.sessionPane="chat"; void render(); }
}
window.addEventListener("message", event => {
  if(event.origin===location.origin && event.data?.type==="OPEN_CHAT") openChatFromNotification();
});
// Desktop-only callers reuse the same editor and its pending-write barrier.
export const desktopSheetSession={
  configure(hooks){desktopHooks=hooks;},
  currentId:()=>state.creatureId,
  flush:flushPendingFields,
  notify:message,
  showLibrary:()=>navigate('library'),
  async exportArchive(){await flushPendingFields();return exportCreatureBatch((await listCreatures()).map(row=>row.creature.id));},
  async open(id){await flushPendingFields();state.creatureId=id;state.libraryMode=false;state.sheet="info";state.editor=null;await render();}
};
export async function mount(){
  realtimeStopped=false;
  if(new URLSearchParams(location.search).get("open")==="chat") {
    history.replaceState(null,"",location.pathname);
    state.sessionPane="chat";
  }
  listen();
  const dbOk=await import("./storage.js").then(m=>m.openStorage()).then(db=>{db.close();return true;});
  if(!dbOk)throw new Error("Archivio locale non disponibile.");
  const qrCode=takeQrPairCode();
  // Possession of a local credential is unrelated to reachability. Render
  // IndexedDB creatures FIRST: an offline desktop must never gate the editor.
  state.paired=await hasPairingCredential();
  if(qrCode){state.page="session";state.sessionPane="connection";}
  state.cachedCreatures=(await listCreatures()).map(row=>row.creature);
  await render();
  void loadBundledConditionCatalog();
  if(qrCode){
    const input=document.querySelector("#pair-secret");
    if(input)input.value=qrCode;
  }
  // Pairing from #pair is an AUTHENTICATION step, not a reconnect: an
  // unpaired phone naturally gets HTTP 401 from /api/session. Do not run
  // refreshConnection() first or let that 401 suppress the QR exchange.
  // Keep the local creature library available while the request is pending.
  void (async()=>{
    if(qrCode){
      try {
        acceptSession(await pair(qrCode,{remember:true}));
        state.paired=true;state.online=true;state.hostReachable=true;
        state.page="session";state.sessionPane="table";
        state.messages=[];state.after="";state.tokenId="";
        try{state.map=await map();}catch{state.map=null;}
        await render();
        void refreshConnection(true).catch(error=>console.warn("QR reconnect check unavailable",error));
        message("Telefono associato tramite QR.");
      }catch(error){
        // A one-time code may have been redeemed before /api/session failed.
        // pair() remembers the issued bearer so a reconnect can recover.
        await refreshConnection(true);
        if(state.paired&&state.online){
          state.page="session";state.sessionPane="table";
          await render();
          message("Telefono associato tramite QR.");
        }else{
          state.page="session";state.sessionPane="connection";
          await render();
          const input=document.querySelector("#pair-secret");
          if(input)input.value=qrCode;
          message("Associazione QR non riuscita: "+errorMessage(error),true);
        }
      }
    }else{
      await refreshConnection(true);
    }
  })().catch(error=>console.warn("VTT desktop unavailable; local archive stays open",error));
}
