import {concentrationDamageCheck,concentrationEndPatch,CONCENTRATION_ROLL_CONTEXT} from './concentration_rules.js';
import {monsterActionUsePatch,monsterDetailPatch} from './monster_traits.js';
import {identityEntries,identityEntriesPatch} from './identity_aliases.js';
import {availableD20Rerolls,offerD20Reroll,chooseD20Reroll} from './d20_rerolls.js';
import {resolveVariant,applyVariantEdit,activeVariant,variantOwns,variantDamage,revertVariantDamage,validateVariants} from './creature_variants.js';
import {openVariantsDialog,variantSources} from './creature_variants_view.js';
import {featureCompanionRule,eligibleCompanionFeatureRules,matchesCompanionFeature,spellCompanionRule,companionSources,companionGrantActive,infusionCompanionRule,companionSpellEffectPatch,companionStatBlockView} from './companion_rules.js';
import {companionOwnerValues} from './companion_owner_stats.js';
import { battleActionPanels, abilityAttackRoll, monsterActionOptionsMarkup, actionGlyph, actionVariants, loadFeatureActionOverrides, loadGeneralActionSupplements, nativeClassFeatureActions } from "./action_economy.js";
import { SHEET_SECTIONS, DETAILS, ROW_FIELDS, BONUS_TARGETS, nativeSection, nativeRowPatch, rowsFor, totalClassLevel, collectionPatch, identityPatch, referencePatch, rowReferencePatch, availableReferenceRows, hitPointPatch, slotUsePatch, recoveryPatch, completeRest, restRecoveryPreview, miniaturePatch } from "./native_sheet.js";
import { activeItemOptionEffects, itemKind, requiresAttunement, isCatalogItem, createOwnedItem, changeOwnedItem, changeItemOverride, ownedItemDisplayName, changeEquippedWeaponSize, resolveOwnedItem, isSpellScroll, spellScrollName, spellScrollLevel, addSpellScroll, WEAPON_SIZES, targetableInventoryItems, clearInfusionPatch, validSlot, equipSlot, hasProperty, armorDexterityLabel } from "./item_controls.js";
import * as inventoryModule from "./item_controls.js";
import {itemAttunementCount,inventoryAttunementCounts} from "./item_controls.js";
import {inventoryAttunementControl} from "./sheet_rules_view.js";
import {structuredItemFacts} from "./item_detail_facts.js";
import { sessionSpellEntries, availableSpells, addSelectedSpell, removeSelectedSpell, spellId, spellEligible, spellsForEdition, castingSources, classSelectionCount, classSelectionWarnings, knownSpellProgress, knownClassSpellIds, knownClassCantripIds, changeKnownClassSpell, originChoiceMatches, applyOriginSpellChoice } from "./spell_selection.js";
import { loadActivatedAbilities, abilitiesForCreature } from "./activated_abilities.js";
import { status, session, pair, unpair, hasPairingCredential, map, action, subscribeMap, takeQrPairCode, conditionDefinitions } from "./client.js";
import { conditionOptions, conditionLabel, CONDITION_CATEGORIES, EXHAUSTION_CONDITION_CATEGORY, exhaustionLevel, exhaustionConditionRows, exhaustionSelectionPatch, conditionCatalogFrom5etools, mergeConditionCatalog } from "./condition_catalog.js";
import {exhaustionRemovablePatch,exhaustionRollModifier} from "./exhaustion_rules.js";
import { notificationsSupported, notificationsEnabled, toggleChatNotifications, notifyIncomingChat } from "./chat_notifications.js";
import {openSendDialog,pollIncomingShares} from './share_transfer.js';
import {exportInventoryItems} from './inventory_transfer.js';
import { listCreatures, listSubcreatures, createSubcreature, summonSubcreature, loadCreature, createCreature, createBestiaryMonster, importCreatureFile, exportCreature, exportCreatureBatch, exportCreatureArchive, exportHomebrewPackage, exportCatalogHomebrewEntry,
  removeCreature, openCreatureEditor, ownerId, syncLinkedTokenStatuses } from "./creatures.js";
import { TacticalViewer } from "./tactical_view.js";
import { tokenGroups, snapshotRevision, snapshotBlob, casterToken, SessionMapViewer } from "./session_map.js";
import { createDemoCreature } from "./demo.js";
import { CATALOG_CATEGORIES, catalogEntries, selectedSpellEntries, detailedEntry, flattenDescription, createQuickHomebrew, quickGrantPatch, deleteQuickHomebrew } from "./catalog_data.js";
import { collectTraitRows, groupTraitRows, withGrantedSpellPreviews, stateTraitNavigationKey } from "./trait_projection.js";
import { traitBenefitGroups, rollGrantTraitRow } from "./trait_benefits.js";
import { distributeTraitBenefits } from "./trait_benefit_distribution.js";
import {SENSE_OPTIONS,senseRange} from "./sense_rules.js";
import {applicableSpeciesRollModes} from './species_roll_modes.js';
import {BENEFIT_TYPES,PROFICIENCY_KINDS,DEFENSE_RANKS,DAMAGE_TYPES,traitRemovedIds,removeBenefitPatch,restoreBenefitPatch,addBenefitPatch,traitActivationPatch,traitIsActive} from "./trait_benefit_editor.js";
import { spellFacts } from "./spell_metadata.js";
import {EXTENSION_TARGETS,EXTENSION_OPERATIONS,EXTENSION_TRIGGERS,EXTENSION_FREQUENCIES,effectExtensionsFor,applyEffectExtensions,effectExtensionLabel} from "./effect_extensions.js";
import { exportBackup, importBackup, getRecord, setting } from "./storage.js";
import {serverBackups, serverBackupMarkup} from "./server_backups.js";
import { saveHomebrewDefinition, editHomebrewDefinition } from "./creatures.js";
import { isDocument, createDocumentDefinition, createOwnedDocument, editDocumentDefinition, documentInfo, documentStyle } from "./documents.js";
import { calculateSheet, loadRuleCatalogs, localClasses, classMechanicsRow, validBonusDice, applicableDiceBonuses, SKILLS } from "./sheet_rules.js";
import {healingHandsPatch,restTrainingPatch,endTemporaryConditionPatch,racialAbilityEffectFormula,racialAbilityTemporaryHpPatch} from "./species_powers.js";
import {featureRollTarget,featureRollFlatBonuses,featureRollExtensionBonuses} from './feature_rolls.js';
import {availableZeroHpResponses,resolveZeroHpDamage} from './zero_hp_responses.js';
import {benefitRequirements,requirementPatch,formulaPreview,spellCastPlan,describeSheetActivity} from './native_sheet.js';
import { calculationNote, refreshCalculatedValues, mountPlaySheet, refreshPlayReadouts, inventoryReadout, inventorySectionControls, formulaReadout, rollSheetDice, appendRollBonus, rollBattleDamage, sheetRollChatFields, isPersistentSpell,resourceLinkedSubclassTrait,subclassTrackerUsePatch } from "./sheet_rules_view.js";
import {preparePortraitImage,prepareMiniaturePortrait} from './character_portrait.js';
import {sheetRollOriginSegments,sheetScoreOriginSegments,sheetRollOriginHtml,sheetRollSymbol,damageRollSegments,rollDamageName,rollOptionalDice,attackGrantOrigin} from "./sheet_roll_origin.js";
import {armorClassBaseFormula} from './armor_class_formula.js';
import {traitStateActivationPatch,powerRestSelections,selectionRestLabel} from './trait_state_rules.js';
import {powerSelectionModels,powerSelectionTargets,powerSelectionPatch,powerApplicationPatch,powerSelectionCustomPatch,powerStateActivationPatch} from './power_selection.js';
import {claimFeatureItemPatch,featureItemPowers,featureItemGrants} from './feature_item_grants.js';
import {eligibleSpellStoringItems,eligibleStoredSpells,storeSpellInItemPatch,useStoredSpellPatch,storedSpellExtension,storedSpellMaxUses} from './spell_storing_item.js';
import {eligibleSpellImprintItems,eligibleSpellImprintSpells,storeSpellImprintPatch,useSpellImprintPatch,spellImprintExtension,spellImprintAtItem,spellImprintActive} from './spell_imprints.js';
import {onHitEffects,targetTokenHitEffects,hitEffectExpired} from './attack_hit_effects.js';
import {optionalRecoveryPatch,classFeatureActivationPatch,classFeatureEntries,classFeatureRollBonuses,applicableFeatRollBonuses,classFeatureRollAdvantage,classFeatureRollSources,resolveClassRollMode,wildShapePatch,endWildShapePatch,metamagicOptions} from './feature_mechanics.js';
import {changeTrackerUses,spendTrackerUses,hitDicePools,canLevelUp,constitutionHpAdjustment,minimumXpForLevel} from "./character_core.js";
import {availableXpLevels,levelUpSteps,classHitDieFaces,averageHitDie,levelUpHpPatch,levelUpProgressionImpact} from "./level_up.js";
import {pendingCharacterChoices,savePendingChoice,singleNewPendingChoice,choicesForTrait,knownProficiencyOptions,trainingProficiencyOptions,removeOwnedFeatPatch} from "./pending_choices.js";
import * as pendingChoicesModule from './pending_choices.js';
import {featGrantOrigins,featAlreadyOwned,addFeatWithOrigin,expandedSpellFeatOptions,featTraitOriginKey} from './feat_picker.js';
import {openDialog,closeDialog,dialogCloseButton,matchesSearch,pageResults,resultsFooter} from "./ui_primitives.js";
import {inventorySearchResults} from "./inventory_search.js";
import {isContentAvailableForRules} from './source_edition.js';

// A service worker can briefly serve an older item_controls.js alongside a
// newer ui.js on a slow connection. A named import added in a later release
// would reject the entire ESM graph and leave character sheets unmounted.
// Namespace access keeps the archive and character sheets usable during the
// transition; a completed offline-shell update restores all container actions.
const DEFAULT_INVENTORY_CONTAINER=inventoryModule.DEFAULT_INVENTORY_CONTAINER||"backpack";
const inventoryContainers=inventoryModule.inventoryContainers||((record={})=>{
  const rows=Array.isArray(record.inventory_containers)?record.inventory_containers:[];
  const seen=new Set([DEFAULT_INVENTORY_CONTAINER]);
  return [{id:DEFAULT_INVENTORY_CONTAINER,name:"Zaino"},...rows.flatMap(row=>{
    const id=String(row?.id||"").trim(),name=String(row?.name||"").trim();
    if(!id||!name||seen.has(id))return [];
    seen.add(id);return [{id,name}];
  })];
});
const itemContainerId=inventoryModule.itemContainerId||((item={},containers=[])=>{
  const id=String(item?.container_id||DEFAULT_INVENTORY_CONTAINER);
  return containers.some(row=>row.id===id)?id:DEFAULT_INVENTORY_CONTAINER;
});
const requiresUpdatedInventoryModule=()=>{
  throw Error("Modulo inventario non aggiornato. Riapri la PWA quando la connessione è disponibile.");
};
const moveInventoryItem=inventoryModule.moveInventoryItem||requiresUpdatedInventoryModule;
const createInventoryContainer=inventoryModule.createInventoryContainer||requiresUpdatedInventoryModule;
const deleteInventoryContainer=inventoryModule.deleteInventoryContainer||requiresUpdatedInventoryModule;
const setItemEquipped=inventoryModule.setItemEquipped||((inventory,index,enabled)=>{
  const rows=structuredClone(Array.isArray(inventory)?inventory:[]);
  const item=rows[index];
  if(!item)throw Error("Oggetto non trovato.");
  if(itemKind(item)==="document")throw Error("Un documento non è equipaggiabile.");
  if(!enabled){item.equipped=false;item.equipped_slots=[];return rows;}
  const kind=itemKind(item);
  if(["weapon","shield","armor"].includes(kind))
    return equipSlot(rows,kind==="armor"?"body":kind==="shield"?"off":"main",index);
  item.equipped=true;
  return rows;
});

// Game rules are explicit data, not patterns guessed from feature prose.
let companionRulesPromise=null;
async function companionRules(){
  companionRulesPromise??=fetch('/catalog/companion_spells.json')
    .then(response=>{if(!response.ok)throw Error('Regole famigli non disponibili.');return response.json();})
    .catch(error=>{companionRulesPromise=null;throw error;});
  return companionRulesPromise;
}
// Reusing a stored creature never automatically restores any of its resources.
async function askCompanionRest(row){
 if(!row?.reused)return;
 const stored=await loadCreature(row.id);
 if(!stored)return;
 const longRest=await new Promise(resolve=>{
  const dialog=document.createElement('dialog');
  dialog.id='companion-rest-dialog';dialog.className='sheet-roll-dialog magic-spell-dialog';
  dialog.innerHTML=actionDialogIntro('Sottocreatura già esistente',[
   {label:'Scheda conservata',value:stored.data.name},
   {label:'Punti ferita',value:String(stored.data.current_hp??0)+' / '+String(stored.data.max_hp??0)}
  ],'La scheda e le sue modifiche sono state conservate. Vuoi effettuare un riposo lungo?',
  '', 'companion-rest-close')+
  '<div class="actions magic-dialog-actions"><button type="button" class="btn primary" data-companion-rest-yes>Riposo lungo</button>'+
  '<button type="button" class="btn" data-companion-rest-no>Mantieni lo stato</button></div>';
  let done=false;const finish=value=>{if(done)return;done=true;resolve(value);closeDialog(dialog,{remove:true});};
  dialog.querySelector('[data-companion-rest-yes]').onclick=()=>finish(true);
  dialog.querySelector('[data-companion-rest-no]').onclick=()=>finish(false);
  dialog.querySelector('[data-act="companion-rest-close"]').onclick=()=>finish(false);
  dialog.addEventListener('close',()=>finish(false),{once:true});
  document.body.append(dialog);openDialog(dialog);
 });
 if(!longRest)return;
 const editor=await openCreatureEditor(row.id),record=editor.read(),calculated=await computeLocalData(record);
 await editor.update(completeRest(record,'long_rest',calculated).patch);await editor.flush();
}
async function createOptionCompanion(owner,infusion,calculated){
 const data=await companionRules(),rule=infusionCompanionRule(data,calculated.infusion_catalog,infusion.item_effects?.id||infusion.id,owner);
 if(!rule)return null;
 const choice=companionSources(rule,data,[],owner)[0];
 if(!choice)throw Error('Profilo della sottocreatura non disponibile.');
 const row=await summonSubcreature(owner.id,await choice.load(),{
  name:choice.name,source:choice.source,template_id:choice.template_id,rule_id:rule.id,
  origin_name:rule.names?.[0]||infusion.name,
  limit_per_owner_rule:rule.limit_per_owner_rule??1,grant:{kind:infusion.item_effects?'item_option':'inventory_infusion',id:infusion.id}
 });
 await askCompanionRest(row);return row;
}
async function summonSpellCompanion(ownerId,source,reference){
 const row=await summonSubcreature(ownerId,await source.load(),reference);
 await askCompanionRest(row);return row;
}
async function companionSpellChoices(spell,creature){
  const data=await companionRules();
  const rule=spellCompanionRule(data,spell,creature);
  if(!rule)return null;
  const sources=await variantSources([],await (await import('./storage.js')).listRecords('global','homebrew'));
  return {rule,choices:companionSources(rule,data,sources,creature)};
}
async function companionFeatureChoices(creature,calculated,originId){
  const data=await companionRules(),rule=featureCompanionRule(creature,calculated,data,originId);
  if(!rule)return null;
  const sources=rule.template?[]:await variantSources([],
    await (await import('./storage.js')).listRecords('global','homebrew'));
  return {rule,choices:companionSources(rule,data,sources,creature),originId};
}
function featureCompanionFields(context){
  if(!context)return '';
  const entries=context.choices||[],rule=context.rule;
  return '<section class="feature-companion-options"><h3>Sottocreatura</h3>'+
    '<label>Creatura da generare<select data-feature-companion>'+
      (entries.length?entries.map(entry=>'<option value="'+esc(entry.key)+'">'+esc(entry.name)+
      (entry.source?' · '+esc(entry.source):'')+'</option>').join(''):'<option value="">Nessuna creatura compatibile nel bestiario</option>')+
    '</select></label>'+
    (rule.allowed_sizes?.length?'<label>Taglia<select data-feature-companion-size>'+
      rule.allowed_sizes.map(size=>'<option value="'+esc(size)+'"'+(size==='Medium'?' selected':'')+'>'+esc(size)+'</option>').join('')+'</select></label>':'')+
    '<label>Nome della sottocreatura (facoltativo)<input data-feature-companion-name maxlength="120" placeholder="'+
      esc(entries[0]?.name||'Nome')+'"></label>'+
    (rule.duration?'<p class="hint">Durata: '+esc(rule.duration)+'.</p>':'')+
    '</section>';
}
async function createFeatureCompanion(parent,context,dialog){
  if(!context)return null;
  const {rule,choices,originId}=context;
  const key=dialog.querySelector('[data-feature-companion]')?.value;
  const choice=choices.find(entry=>entry.key===key);
  if(!choice)throw Error('Seleziona un mostro compatibile per il privilegio.');
  const size=dialog.querySelector('[data-feature-companion-size]')?.value||'';
  if(size&&!(rule.allowed_sizes||[]).includes(size))throw Error('Taglia non consentita.');
  const requested=String(dialog.querySelector('[data-feature-companion-name]')?.value||'').trim();
  if(requested.length>120)throw Error('Nome troppo lungo.');
  let loaded=await choice.load({size,name:requested});
  if(!loaded||typeof loaded!=='object')throw Error('Voce del bestiario non valida.');
  if(requested)loaded={...loaded,name:requested};
  const row=await summonSubcreature(parent.id,loaded,{
    ...choice,name:choice.name,display_name:requested,
    origin_name:rule.names?.[0]||'',feature_id:originId,rule_id:rule.id,
    grant:{kind:'feature',id:originId},
    duration:rule.duration||'',limit_per_owner_rule:rule.limit_per_owner_rule??1
  });
  await askCompanionRest(row);
  return row;
}
async function manualCompanionRules(owner,calculated){
  const data=await companionRules();
  return eligibleCompanionFeatureRules(owner,calculated,data,{manualOnly:true}).flatMap(rule=>{
    const feature=(calculated.features||[]).find(row=>matchesCompanionFeature(owner,calculated,rule,row));
    return feature?[{id:rule.id,name:rule.names?.[0]||rule.id,
      source:rule.class_name+(rule.subclass?' · '+rule.subclass:''),
      originId:feature.origin_id}]:[];
  });
}
async function openManualCompanionDialog(owner,descriptor){
  const calculated=await computeLocalData(owner);
  const context=await companionFeatureChoices(owner,calculated,descriptor.originId);
  if(!context||context.rule.id!==descriptor.id)throw Error('Privilegio non disponibile.');
  const dialog=document.createElement('dialog');
  dialog.className='sheet-roll-dialog magic-spell-dialog';
  dialog.id='companion-feature-dialog';
  dialog.innerHTML=actionDialogIntro(descriptor.name,[
    {label:'Origine',value:descriptor.source},
    {label:'Creazione',value:'Scheda mostro collegata al proprietario'}
  ],'', '', 'companion-feature-close')+
  featureCompanionFields(context)+
  '<p data-companion-result role="status"></p><div class="actions magic-dialog-actions">'+
  '<button type="button" class="btn primary" data-companion-confirm>Genera sottocreatura</button>'+
  '<button type="button" class="btn" data-companion-cancel>Annulla</button></div>';
  dialog.querySelectorAll('[data-companion-cancel],[data-act="companion-feature-close"]').forEach(button=>
    button.addEventListener('click',()=>closeDialog(dialog,{remove:true})));
  dialog.querySelector('[data-companion-confirm]').addEventListener('click',async event=>{
    const button=event.currentTarget;if(button.disabled)return;button.disabled=true;
    try{
      const current=state.editor?.read();
      if(!current||current.id!==owner.id)throw Error('Proprietario cambiato.');
      const fresh=await computeLocalData(current);
      const validated=await companionFeatureChoices(current,fresh,descriptor.originId);
      if(!validated||validated.rule.id!==descriptor.id||validated.rule.activation!=='manual')
        throw Error('Capacità non più disponibile.');
      const row=await createFeatureCompanion(current,validated,dialog);
      await state.editor?.flush();
      closeDialog(dialog,{remove:true});
      state.creatureId=row.id;state.editor=null;state.sheet='info';state.libraryMode=false;
      await render();message('Sottocreatura collegata a '+owner.name+'.');
    }catch(error){button.disabled=false;dialog.querySelector('[data-companion-result]').textContent=errorMessage(error);}
  });
  dialog.addEventListener('close',()=>dialog.remove(),{once:true});
  document.body.append(dialog);openDialog(dialog);
}


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
  after:"", localMessages:[], rollHistory:[], roll:null, diceSides:20, chatAuthor:"", stopMap:null, pollChat:null, renderTicket:0,
  sheetSearch:new Map(), sheetPopup:"", sheetPopupTitle:"", traitPopupKey:"", traitPopupConfirm:"", traitPopupDraftKind:"", traitPopupDraftTarget:"", traitRows:[], sheetSources:new Map(), librarySelectedIds:new Set(), libraryFilter:'all', libraryMiniatureId:'sariel', libraryMiniatures:[], libraryMiniatureLimit:36, libraryCreateKind:'character', libraryBestiaryEntries:[], libraryBestiaryKey:'', libraryBestiaryLimit:36, libraryBestiaryError:'', libraryMiniatureManuallySelected:false, sessionPane:"", disclosureState:new Map(),
  hostReachable:false, sheetNeedsRefresh:false, conditionCatalog:null, offlineConditionCatalog:null, desktopConditionCatalog:null, catalogCategory:"items", catalogQuery:"", catalogAssignCreatureId:'', catalogRows:[], catalogSelected:-1, catalogResultLimit:90, spellCatalog:null, spellCatalogComplete:false, spellDemandKey:"", spellScopedLoading:false, abilityCatalog:null, spellQuery:"", spellResultLimit:60, spellTarget:"prepared_spells", spellClass:'manual',spellKnownView:'all',spellLearnFilter:'all',magicSlotLevel:1,magicSlotPact:false,infusionPending:-1,spellCatalogError:"", magicPopup:"", openDocumentInstance:"",
  castCreatureId:"", castSpellIndex:0, castLevel:1, sessionCreatureErrors:[],
  attackRange:30, attackLongRange:0, attackMelee:false,
  inventorySelectedIndex:0, inventorySelectedIndices:new Set(), inventoryMenuIndex:-1, inventorySubtab:'items', inventorySelectedTabs:['all'], inventoryHighlightedIndices:[],inventorySearchLimit:75,inventorySearchMatches:[],inventorySearchCatalogError:'', scrollSpellQuery:'', pendingItemOwner:'', pendingItemContainer:'', pendingSpellChoiceId:'',
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
// Input/change handlers may already be writing when a popup closes. Include
// those commits in the flush so Escape cannot discard the last edited field.
const pendingFieldWrites = new Set();
let returnToBattleFromCompetences=false;
// Keep both forms of identity readable immediately after changing the popup,
// without rebuilding the active sheet or re-opening the dialog.
function refreshIdentityPresentation(creature){
 const header=app.querySelector('#sheet-play-view .play-character-portrait');
 if(!header||!creature)return;
 const other=header.querySelector('.play-identity-other-names');
 if(other){
  const names=identityEntries(creature,'names').filter(row=>!row.active);
  other.innerHTML=names.map(row=>'<span class="play-identity-alias">'+esc(row.value)+'</span>').join('');
  other.hidden=creature.identity_hide_other_names!==false||!names.length;
 }
 const factions=header.querySelector('.play-identity-factions-line');
 if(factions){
  const active=identityEntries(creature,'factions').filter(row=>row.active).map(row=>row.value);
  const list=factions.querySelector('.play-identity-faction-list');
  if(list)list.innerHTML=active.map(name=>'<span class="play-identity-faction">'+esc(name)+'</span>').join('');
  factions.hidden=!active.length;
 }
}
// The multi-identity editor writes a complete group atomically, preserving
// both the canonical legacy fields and the additional display identities.
async function saveIdentityGroup(target){
 const group=target.closest('[data-identity-group]');
 if(!group||!state.editor)return;
 const kind=group.dataset.identityGroup;
 if(!['names','factions'].includes(kind))return;
 // Blank rows are removed by focusout, not by unrelated autosaves while
 // the user is still about to type into a newly focused entry.
 const entries=[...group.querySelectorAll('.identity-entry')].map(row=>({
  value:row.querySelector('[data-identity-value]')?.value||'',
  active:Boolean(row.querySelector('[data-identity-active]')?.checked)
 }));
 if(kind==='names'&&!entries.some(row=>row.value.trim())){
  const first=group.querySelector('[data-identity-value]');
  if(first)first.value=state.editor.read().name;
  return;
 }
 if(kind==='names'){
  const selected=entries.findIndex(row=>row.active&&row.value.trim());
  const chosen=selected>=0?selected:entries.findIndex(row=>row.value.trim());
  for(const [index,row] of [...group.querySelectorAll('.identity-entry')].entries()){
   const check=row.querySelector('[data-identity-active]');
   if(check)check.checked=index===chosen;
  }
  entries.forEach((row,index)=>{row.active=index===chosen;});
 }
 const changes=identityEntriesPatch(state.editor.read(),kind,entries);
 await patch(changes);
 refreshIdentityPresentation(state.editor?.read());
}
function trackIdentityWrite(target){
 const write=saveIdentityGroup(target);
 pendingFieldWrites.add(write);
 void write.finally(()=>pendingFieldWrites.delete(write)).catch(()=>{});
 return write;
}
function trackFieldWrite(target) {
  const write=handleField(target);
  pendingFieldWrites.add(write);
  void write.finally(()=>pendingFieldWrites.delete(write)).catch(()=>{});
  return write;
}
let pendingDocumentWrites=Promise.resolve();
async function flushPendingFields() {
  const targets = [...pendingFieldTimers.keys()];
  for (const target of targets) {
    clearTimeout(pendingFieldTimers.get(target));
    pendingFieldTimers.delete(target);
    if (target.isConnected && state.editor)
      await (target.matches('[data-identity-value]')?trackIdentityWrite(target):trackFieldWrite(target));
  }
  await Promise.all([...pendingFieldWrites]);
  if(state.sheetPopup==='identity'){
    for(const group of app.querySelectorAll('#sheet-context-dialog [data-identity-group]'))
      await trackIdentityWrite(group);
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
// A character sheet must open from local storage even if one of its optional
// reference catalogs is slow or unavailable. Do not clear locally saved data.
function sheetLoadingDeadline(promise,ms,label){
  let timer;
  return Promise.race([Promise.resolve(promise),new Promise((_,reject)=>{
    timer=setTimeout(()=>{
      const error=new Error("Caricamento "+label+" oltre il tempo massimo.");
      error.code="SHEET_LOADING_TIMEOUT";
      reject(error);
    },ms);
  })]).finally(()=>clearTimeout(timer));
}

// Foreground requests only contain selected spells and, when preparing, the
// caster's eligible class list. A background download can later replace these
// partial references with the entire catalog without blocking navigation.
let fullSpellCatalogRequest=null;
function loadFullSpellCatalog(){
  if(state.spellCatalogComplete)return Promise.resolve(state.spellCatalog);
  if(!fullSpellCatalogRequest)fullSpellCatalogRequest=catalogEntries("spells").then(rows=>{
    const retained=(state.spellCatalog||[]).filter(row=>row.internal_grant===true);
    state.spellCatalog=[...new Map([...rows,...retained].map(row=>[row.id,row])).values()];
    state.spellCatalogComplete=true;
    state.spellCatalogError="";
    return rows;
  }).catch(error=>{
    state.spellCatalogError=errorMessage(error);
    throw error;
  }).finally(()=>{fullSpellCatalogRequest=null;});
  return fullSpellCatalogRequest;
}
// Refresh local shared-homebrew options without refetching the entire catalog.
async function refreshCharacterHomebrewOptions(){
  state.referenceCatalogs={};
  state.spellDemandKey='';
  state.inventorySearchCatalogError='';
  if(state.spellCatalogComplete){
    try{state.spellCatalog=[...new Map([...(await catalogEntries('spells')),
      ...(state.spellCatalog||[]).filter(row=>row.internal_grant===true)].map(row=>[row.id,row])).values()];refreshSpellPickers();}
    catch(error){console.warn('Impossibile aggiornare gli incantesimi homebrew locali',error);}
  }else state.spellCatalog=[];
}
function spellLearningClassNames(castingClasses=state.calculated?.casting_classes||[]){
  // The full catalogue loads lazily. Offer the ordinary class lists immediately
  // and add any other class names discovered when the catalogue finishes loading.
  const names=new Set();
  for(const member of castingClasses){
    if(member.spell_list_class_name||member.name)
      names.add(String(member.spell_list_class_name||member.name));
  }
  for(const spell of state.spellCatalog||[]){
    for(const value of Array.isArray(spell.classes)?spell.classes:[]){
      const name=typeof value==='string'?value:value?.name;
      if(name)names.add(String(name));
    }
  }
  return [...names].sort((a,b)=>a.localeCompare(b,'it',{sensitivity:'base'}));
}
function spellLearningFilterOptions(){
  return '<option value="all"'+(state.spellLearnFilter==='all'?' selected':'')+'>Tutte</option>'+
    spellLearningClassNames().map(name=>'<option value="'+esc(name)+'"'+
      (state.spellLearnFilter===name?' selected':'')+'>'+esc(name)+'</option>').join('');
}
function refreshSpellPickers(){
  // Do not recreate the modal: the player may be typing in its search field.
  const results=app.querySelector('#magic-tools-dialog[open] #spell-results');
  if(results&&['catalog','learn'].includes(state.magicPopup))results.innerHTML=renderSpellResults();
  const classFilter=app.querySelector('#magic-tools-dialog[open] #spell-learn-filter');
  if(classFilter){
    const selected=classFilter.value;
    classFilter.innerHTML=spellLearningFilterOptions();
    classFilter.value=selected;
  }
  const scroll=app.querySelector('#sheet-context-dialog[open] #scroll-spell-select');
  if(scroll){
    const selected=scroll.value;
    scroll.innerHTML=scrollSpellSelectOptions(state.scrollSpellQuery);
    if([...scroll.options].some(row=>row.value===selected))scroll.value=selected;
    updateScrollSpellLevels();
  }
}
function refreshWhenSpellsArrive(promise,creatureId,sheet){
  refreshSheetAfterLateLoad(promise,creatureId,sheet);
  Promise.resolve(promise).then(()=>{
    refreshSpellPickers();
    if(state.page==='session')void render();
  }).catch(()=>{});
}
function ensureVisibleSpells(creature,calculated){
  if(state.spellCatalogComplete)return null;
  const ids=new Set();
  for(const field of ['prepared_spells','spells','spellbook_spells','known_spells']){
    for(const entry of creature[field]||[])if(spellId(entry))ids.add(spellId(entry));
  }
  for(const row of [...(calculated.origin_spells||[]),...(creature.origin_spell_grants||[])]){
    if(row.spell_id)ids.add(row.spell_id);
  }
  // A preparing caster's known cantrips are no longer stored as prepared
  // spells, but the small on-demand lookup must still resolve their details.
  for(const member of calculated.casting_classes||[]){
    for(const id of creature.known_spell_overrides?.[member.id]?.added||[])ids.add(id);
    // An expanded racial list is eligible for every owned casting class,
    // even if the spell is not part of the class's ordinary server-side scope.
    for(const id of member.expanded_spell_ids||[])ids.add(id);
  }
  const scopes=[];
  if(state.sheet==='magic'&&state.magicPopup==='catalog'&&state.spellKnownView==='known'&&
    state.spellTarget==='prepared_spells'){
    const member=(calculated.casting_classes||[]).find(row=>row.id===state.spellClass);
    if(member?.mode==='Preparati')scopes.push({
      name:member.name,max_level:member.max_level
    });
  }
  if(!ids.size&&!scopes.length)return null;
  const key=JSON.stringify([[...ids].sort(),scopes,creature.id||'',state.sheet]);
  if(state.spellDemandKey===key)return null;
  state.spellDemandKey=key;
  state.spellScopedLoading=true;
  const request=selectedSpellEntries([...ids],scopes).then(rows=>{
    if(!state.spellCatalogComplete){
      const combined=new Map((state.spellCatalog||[]).map(row=>[row.id,row]));
      for(const row of rows)combined.set(row.id,row);
      state.spellCatalog=[...combined.values()];
    }
    state.spellCatalogError='';
    return rows;
  }).catch(error=>{
    // Let the next explicit navigation or refresh retry once connectivity
    // returns; failure never blocks rendering locally saved spells.
    if(state.spellDemandKey===key)state.spellDemandKey='';
    console.warn('VTT spell references unavailable; saved spells remain usable',error);
  }).finally(()=>{state.spellScopedLoading=false;});
  return request;
}
function requireFullSpellsForPicker(){
  if(state.spellCatalogComplete)return;
  const creatureId=state.creatureId,sheet=state.sheet;
  refreshWhenSpellsArrive(loadFullSpellCatalog(),creatureId,sheet);
}

let sheetLateRefreshTimer=null;
function refreshSheetAfterLateLoad(promise,creatureId,sheet){
  Promise.resolve(promise).then(()=>{
    if(sheetLateRefreshTimer)clearTimeout(sheetLateRefreshTimer);
    sheetLateRefreshTimer=setTimeout(()=>{
      sheetLateRefreshTimer=null;
      // Never replace an open editor/popup or a focused input merely because
      // an optional spell reference finished downloading. Its rows are already
      // cached and the next normal render will pick them up.
      if(document.querySelector('dialog[open]')||
        app.querySelector('input:focus,textarea:focus,select:focus'))return;
      if(state.page==='library'&&!state.libraryMode&&
        state.creatureId===creatureId&&state.sheet===sheet&&
        app.querySelector('#sheet-play-view')){
        void render();
      }
    },180);
  }).catch(error=>console.warn("Catalogo opzionale della scheda non disponibile",error));
}
function sheetLoadingView(){
  return '<section class="sheet-loading-view" role="status" aria-live="polite">'+
    '<span class="sheet-loading-indicator" aria-hidden="true"></span>'+
    '<h2>Caricamento della scheda</h2>'+
    '<p>Sto aprendo i dati salvati sul dispositivo.</p>'+
    '</section>';
}
// Exact icon keys used by CreatureArea._add_sheet_tab in the desktop.
const SHEET_TAB_GLYPHS={info:'information',battle:'weapon',
 magic:'spark',inventory:'inventory',conditions:'condition'};
const INFO_HEADING_ICONS={'Identità':'identity',
 'Classi':'progression','Talenti':'talents'};
const PLAY_SECTIONS=[['info','Info'],['battle','Azioni'],['magic','Poteri'],['inventory','Zaino']];
const SECTION_COPY={battle:['Azioni','Risorse e azioni disponibili.'],magic:['Poteri','Incantesimi e capacità pronti per il tuo turno.'],inventory:['Inventario','Equipaggiamento, oggetti e documenti.'],conditions:['Condizioni','Gestisci gli stati che influenzano il personaggio.'],info:['Info','Identità, aspetto e progressione del personaggio.'],json:['Editor avanzato','Documento completo della scheda.']};
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
  back.setAttribute('aria-label',creature?.parent_creature_id?'Torna al proprietario':'Torna alle creature');
  back.title=creature?.parent_creature_id?'Torna al proprietario':'Torna alle creature';
  const forms=document.querySelector('#creature-forms');
  if(forms){
    forms.hidden=!hasCreature||!state.editor;
    forms.innerHTML=actionGlyph('wild_shape');
    forms.classList.toggle('has-variant',Boolean(creature?.current_form_id));
    forms.title='Forme e varianti'+(creature?.current_form_id?' · '+(activeVariant(creature)?.name||creature.name):'');
  }
  if(label)label.textContent=hasCreature?(creature?.name||'Creatura'):
    state.page==='catalog'?'Catalogo':state.page==='session'?'Partita':'VTT Mobile';
  if(classLabel){
    const members=hasCreature?localClasses(creature||{}):[];
    const parentName=creature?.parent_creature_id?
      (state.cachedCreatures||[]).find(c=>c.id===creature.parent_creature_id)?.name:'';
    classLabel.textContent=parentName?'Famiglio di '+parentName:
      members.map(member=>member.name+' '+Math.max(1,Number(member.level)||1)).join(' · ');
    classLabel.hidden=!parentName&&!members.length;
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

// Each section is independent, including an empty selection. Migrate the
// former single "all" tab when restoring older navigation history.
function inventorySectionKeys(record){
  return ['items','scrolls','documents',...inventoryContainers(record).slice(1).map(row=>'container:'+row.id)];
}
function inventoryVisibleSections(record,selection=state.inventorySelectedTabs){
  const valid=inventorySectionKeys(record),chosen=Array.isArray(selection)?selection:[selection];
  if(chosen.includes('all'))return valid;
  const selected=valid.filter(key=>chosen.includes(key));
  return selected;
}
function setInventoryVisibleSections(record,selection){
  const selected=inventoryVisibleSections(record,selection);
  state.inventorySelectedTabs=selected;
  if(!selected.includes(state.inventorySubtab))state.inventorySubtab=selected[0]||'items';
  return selected;
}
function focusInventorySection(record,key){
  if(!inventorySectionKeys(record).includes(key))key='items';
  setInventoryVisibleSections(record,[...inventoryVisibleSections(record),key]);
  state.inventorySubtab=key;
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
    inventorySubtab:state.inventorySubtab,inventorySelectedTabs:[...state.inventorySelectedTabs],
    catalogSelected:state.catalogSelected
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
    state.inventorySelectedTabs=Array.isArray(screen.inventorySelectedTabs)?
      screen.inventorySelectedTabs.slice(0,100):
      screen.inventorySubtab==='all'?['all']:[state.inventorySubtab];
    state.catalogSelected=Number.isInteger(screen.catalogSelected)?screen.catalogSelected:-1;
    if(oldCreatureId!==state.creatureId||state.page!=='library'||state.libraryMode)state.editor=null;
    if(oldCreatureId!==state.creatureId)await refreshCharacterHomebrewOptions();
    state.sheetPopup='';state.magicPopup='';state.traitPopupKey='';
    await render();
    window.scrollTo(0,0);
    app.focus({preventScroll:true});
  }catch(error){message('Impossibile ripristinare la scheda: '+errorMessage(error),true);}
  finally{if(ticket===browserHistoryRestoreTicket)restoringBrowserHistory=false;}
}

async function download(blob, filename) {
  // The embedded desktop WebView cannot reliably fetch its own blob: URLs.
  // Send the original Blob directly to the native save dialog instead.
  if (typeof globalThis.vttDesktopSaveFile === "function") {
    await globalThis.vttDesktopSaveFile(blob, filename);
    return false; // Desktop reports its own save/cancel/error result.
  }
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url; link.download = filename; link.hidden = true;
  document.body.append(link); link.click(); link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60000);
  return true;
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
function archiveCreatureView(creature){
  if(creature.archive_unreadable||typeof creature.id!=="string"||
     typeof creature.name!=="string"||!creature.name.trim())
    throw new Error("Dati della scheda non leggibili.");
  validateVariants(creature);
  return resolveVariant(creature);
}
function readableArchiveCreatures(rows){
  return rows.flatMap(({creature})=>{
    try{return [archiveCreatureView(creature)];}catch{return [];}
  });
}
async function refreshSessionCreatures(){
  const rows=await listCreatures();
  const results=await Promise.all(rows.map(async({creature})=>{
    try{
      const record=archiveCreatureView(creature);
      return {record,calculated:await computeLocalData(record)};
    }catch(error){
      return {error:{id:creature.id,name:creature.name||"Creatura senza nome",message:errorMessage(error)}};
    }
  }));
  const available=results.filter(row=>row.record);
  state.cachedCreatures=available.map(row=>row.record);
  state.castSheets=new Map(available.map(row=>[row.record.id,row.calculated]));
  state.sessionCreatureErrors=results.filter(row=>row.error).map(row=>row.error);
  if(!state.cachedCreatures.some(row=>row.id===state.castCreatureId)){
    state.castCreatureId=state.cachedCreatures[0]?.id||"";
    state.castSpellIndex=0;
  }
}
async function navigate(page){
  if(!sections.has(page))return;
  if(page!=='catalog'){state.pendingItemOwner='';state.pendingItemContainer='';state.catalogAssignCreatureId='';}
  else if(state.editor)state.catalogAssignCreatureId=state.creatureId||'';
  if(state.editor){try{await flushPendingFields();}catch(error){message("Salvataggio bloccato: "+errorMessage(error),true);return;}}
  const openedCreatureId=state.page==="library"&&!state.libraryMode?state.creatureId:null;
  stopSubscriptions();if(page==="session")realtimeStopped=false;
  state.traitPopupKey='';state.sheetPopup="";state.page=page;state.libraryMode=page==="library";state.editor=null;state.magicPopup="";
  state.inventorySelectedIndices.clear();
  if(page==="library"){
    state.creatureId=null;
    state.inventorySelectedTabs=['all'];state.inventorySubtab='items';
  }
  // The archive index does not need to resolve every creature's active form.
  // A damaged legacy form must not prevent access to the other saved sheets.
  const archiveRows=await listCreatures();
  state.cachedCreatures=page==="library"?archiveRows.map(row=>row.creature):readableArchiveCreatures(archiveRows);
  if(page==="session")state.chatAuthor=state.cachedCreatures.find(creature=>creature.id===openedCreatureId)?.name||"";
  await render();
}
async function render() {
  const previousMagic=app.querySelector('#magic-tools-dialog[open]');
  const magicScroll=previousMagic?{
    kind:previousMagic.querySelector('.magic-tools-head h2')?.textContent,
    dialog:previousMagic.scrollTop,
    body:previousMagic.querySelector('.magic-tools-body')?.scrollTop||0,
    results:previousMagic.querySelector('#spell-results')?.scrollTop||0
  }:null;
  const ticket = ++state.renderTicket;
  syncNav();
  const viewKey=[state.page,state.libraryMode?'archive':'sheet',state.creatureId||'',state.sheet].join('|');
  // The header and the dock change synchronously. Change the central panel
  // at the same time instead of leaving the old Creature list visible until
  // asynchronous catalog requests and calculations finish.
  if(app.dataset.renderViewKey!==viewKey){
    app.innerHTML=sheetLoadingView();
    app.dataset.renderViewKey=viewKey;
  }
  try {
    let html = "";
    if (state.page === "library") html = await libraryView();
    else if (state.page === "catalog") html = await catalogView();
    else if (state.page === "session") {
      // A bad sheet must not prevent pairing, chat, or the other local casters.
      await refreshSessionCreatures();
      html=sessionView();
    }
    if(ticket !== state.renderTicket) return;
    syncNav();
    // A status refresh can redraw Partita while a manual QR code is already
    // entered. Do not discard it or silently revert the Remember preference.
    const pendingCode=state.page==="session"?app.querySelector("#pair-secret")?.value:"";
    const rememberPair=state.page==="session"?app.querySelector("#pair-remember")?.checked:undefined;
    app.innerHTML = html;
    app.dataset.renderViewKey=viewKey;
    syncLibrarySelectionUI();
    syncLibraryFilterUI();
    if(state.page==="session")sessionMapViewer.mount(app.querySelector("#session-map-canvas"),state.snapshotObjectUrl);
    if(pendingCode && app.querySelector("#pair-secret"))
      app.querySelector("#pair-secret").value=pendingCode;
    if(rememberPair!==undefined && app.querySelector("#pair-remember"))
      app.querySelector("#pair-remember").checked=rememberPair;
    app.dataset.page=state.page;
    app.dataset.renderedSheet=state.page==="library"&&!state.libraryMode?state.sheet:"";
    decorateSheetHeadings();
    organizeSheetPanels();
    // Live token synchronization can finish while the first character load
    // is pending. Apply at most one queued refresh after its main panel exists,
    // rather than canceling every in-flight render before the sheet can paint.
    if(state.page==='library'&&!state.libraryMode&&state.sheetNeedsRefresh){
      state.sheetNeedsRefresh=false;
      setTimeout(()=>{
        if(state.page==='library'&&!state.libraryMode&&ticket===state.renderTicket)
          void render();
      },0);
    }
    rememberUtilityDisclosures();
    mountTraitBenefitDialog();
    syncBrowserHistory();
    const magicDialog=app.querySelector('#magic-tools-dialog');
    if(magicDialog){
      magicDialog.addEventListener('close',()=>{state.magicPopup="";},{once:true});
      if(typeof magicDialog.showModal==='function')magicDialog.showModal();else magicDialog.setAttribute('open','');
      if(magicScroll&&magicScroll.kind===magicDialog.querySelector('.magic-tools-head h2')?.textContent){
        // The modal itself scrolls, not only its result list. Restoring just
        // .magic-tools-body used to silently reset the real scroll position.
        const restore=()=>{
          if(!magicDialog.isConnected)return;
          magicDialog.scrollTop=magicScroll.dialog;
          const body=magicDialog.querySelector('.magic-tools-body');
          const results=magicDialog.querySelector('#spell-results');
          if(body)body.scrollTop=magicScroll.body;
          if(results)results.scrollTop=magicScroll.results;
        };
        restore();
        if(typeof requestAnimationFrame==='function')requestAnimationFrame(restore);
      }
    }
    if(state.page==="session" && state.map) void refreshSessionSnapshot();
    if(state.paired && state.online && !realtimeStopped && !state.stopMap) startMap();
    if(state.paired && state.online && !realtimeStopped && !state.pollChat) startChat();
  } catch(error) {
    if(ticket !== state.renderTicket) return;
    console.error("VTT Mobile: rendering della scheda fallito", {page:state.page,sheet:state.sheet}, error);
    app.innerHTML = header("Errore", "Operazione non riuscita", errorMessage(error))+
      btn("refresh","Riprova","primary")+
      (state.page==="library"&&!state.libraryMode?btn("back","Torna alle creature"):"");
    app.dataset.renderedSheet='';
    app.dataset.renderViewKey='';
  }
}
// Offline-safe presets are real IDs from token_catalog_offline.json.
const LIBRARY_MINIATURE_PRESETS=[
 {id:'sariel',name:'Sariel',size_name:'Medium',footprint:1},
 {id:'gilliam',name:'Gilliam',size_name:'Medium',footprint:1},
 {id:'hobgoblin',name:'Hobgoblin',size_name:'Medium',footprint:1}
];
const libraryMiniatureOptions=()=>state.libraryMiniatures.length?state.libraryMiniatures:LIBRARY_MINIATURE_PRESETS;
function paintLibraryMiniatures(){
 const dialog=app.querySelector('#library-create-dialog');if(!dialog)return;
 const query=(dialog.querySelector('#library-miniature-search')?.value||'').toLocaleLowerCase('it').trim();
 const profiles=libraryMiniatureOptions();
 const filtered=profiles.filter(m=>matchesSearch(query,m.name,m.id));
 // The selected miniature must remain visible even in a large alphabetic
 // catalog where the first page would otherwise push it out of view.
 const selected=filtered.find(m=>m.id===state.libraryMiniatureId);
 const ordered=selected?[selected,...filtered.filter(m=>m.id!==selected.id)]:filtered;
 const matches=pageResults(ordered,state.libraryMiniatureLimit).items;
 const area=dialog.querySelector('.library-miniature-choices');
 const previousScroll=area?.scrollTop||0;
 if(area)area.innerHTML=matches.length?matches.map(m=>
  '<button type="button" data-act="library-miniature-select" data-miniature-id="'+esc(m.id)+
  '" class="library-miniature-option vtt-selectable" aria-pressed="'+(m.id===state.libraryMiniatureId)+'">'+
  actionGlyph('proficiency')+'<span>'+esc(m.name)+'</span></button>').join(''):
  '<p class="hint">Nessuna miniatura trovata.</p>';
 if(area)area.scrollTop=previousScroll;
 const progress=dialog.querySelector('.library-miniature-progress');
 if(progress)progress.textContent=filtered.length?matches.length+' di '+filtered.length+' miniature':'Nessun risultato';
 const more=dialog.querySelector('[data-act="library-miniature-more"]');
 if(more){
  const remaining=filtered.length-matches.length;
  more.hidden=remaining<=0;
  more.textContent=remaining>0?'Mostra altre '+Math.min(36,remaining):'';
 }
 const chosen=profiles.find(m=>m.id===state.libraryMiniatureId);
 const label=dialog.querySelector('.library-miniature-current');
 if(label)label.textContent=chosen?'Selezionata: '+chosen.name:state.libraryCreateKind==='monster'?'Nessuna miniatura (facoltativa)':'Seleziona una miniatura';
 const confirm=dialog.querySelector('[data-act="create"]');
 if(confirm)confirm.disabled=state.libraryCreateKind==='monster'?!state.libraryBestiaryKey:!chosen;
}

function selectBestiaryDefaultMiniature(){
 if(state.libraryCreateKind!=='monster'||state.libraryMiniatureManuallySelected)return;
 const entry=state.libraryBestiaryEntries.find(row=>row.key===state.libraryBestiaryKey);
 const candidate=entry?.miniature?.id;
 state.libraryMiniatureId=libraryMiniatureOptions().some(row=>row.id===candidate)?candidate:'';
}
function paintLibraryBestiary(){
 const dialog=app.querySelector('#library-create-dialog');if(!dialog)return;
 const search=dialog.querySelector('#library-bestiary-search');
 const query=search?.value||'';
 const filtered=state.libraryBestiaryEntries.filter(row=>matchesSearch(query,row.name,row.source));
 const selected=filtered.find(row=>row.key===state.libraryBestiaryKey);
 const ordered=selected?[selected,...filtered.filter(row=>row.key!==selected.key)]:filtered;
 const items=pageResults(ordered,state.libraryBestiaryLimit).items;
 const area=dialog.querySelector('.library-bestiary-choices');
 if(area)area.innerHTML=items.length?items.map(row=>
  '<button type="button" class="library-bestiary-option vtt-selectable'+(row.key===state.libraryBestiaryKey?' is-selected':'')+
  '" aria-pressed="'+(row.key===state.libraryBestiaryKey)+'" data-act="library-bestiary-select" data-bestiary-key="'+esc(row.key)+'">'+
  '<strong>'+esc(row.name)+'</strong><small>'+esc(row.source||'Bestiario')+'</small></button>').join(''):
  '<p class="hint">'+esc(state.libraryBestiaryError||(!state.libraryBestiaryEntries.length?'Caricamento bestiario…':'Nessun mostro trovato.'))+'</p>';
 const progress=dialog.querySelector('.library-bestiary-progress');
 if(progress)progress.textContent=filtered.length?items.length+' di '+filtered.length+' mostri':'';
 const more=dialog.querySelector('[data-act="library-bestiary-more"]');
 if(more){more.hidden=items.length>=filtered.length;more.textContent='Mostra altri '+Math.min(36,filtered.length-items.length);}
 const name=dialog.querySelector('#library-create-name');
 if(name)name.placeholder=state.libraryCreateKind==='monster'?
  (state.libraryBestiaryEntries.find(row=>row.key===state.libraryBestiaryKey)?.name||'Nome del mostro (facoltativo)'):'Nuova creatura';
 const confirm=dialog.querySelector('[data-act="create"]');
 if(confirm)confirm.disabled=state.libraryCreateKind==='monster'?!state.libraryBestiaryKey:
  !libraryMiniatureOptions().some(row=>row.id===state.libraryMiniatureId);
}
function paintLibraryCreateMode(){
 const dialog=app.querySelector('#library-create-dialog');if(!dialog)return;
 const monster=state.libraryCreateKind==='monster';
 dialog.querySelectorAll('[data-act="library-create-kind"]').forEach(button=>{
  const selected=button.dataset.kind===(monster?'monster':'character');
  button.classList.toggle('is-active',selected);button.setAttribute('aria-pressed',String(selected));
 });
 const bestiary=dialog.querySelector('#library-create-bestiary');
 if(bestiary)bestiary.hidden=!monster;
 const label=dialog.querySelector('[data-library-name-label]');
 if(label)label.textContent=monster?'Nome del mostro (facoltativo)':'Nome';
 paintLibraryBestiary();
 paintLibraryMiniatures();
}
async function loadLibraryBestiary(){
 state.libraryBestiaryError='';
 try{
  const {listRecords}=await import('./storage.js');
  state.libraryBestiaryEntries=await variantSources([],await listRecords('global','homebrew'));
 }catch(error){
  state.libraryBestiaryEntries=[];
  state.libraryBestiaryError=errorMessage(error);
 }
 paintLibraryBestiary();
}
async function loadLibraryMiniatures(){
 try{
  const response=await fetch('/catalog/miniatures.json');
  if(!response.ok)throw Error('catalogue');
  const data=await response.json();
  const profiles=Array.isArray(data.tokens)?data.tokens.filter(m=>typeof m?.id==='string'&&m.id&&typeof m.name==='string'):[];
  if(profiles.length){
   state.libraryMiniatures=profiles;
   if(state.libraryCreateKind==='character'&&!profiles.some(m=>m.id===state.libraryMiniatureId))
    state.libraryMiniatureId=profiles.find(m=>/^(human|commoner|adventurer|sariel|gilliam)/i.test(m.id))?.id||profiles[0].id;
  }
 }catch{
  state.libraryMiniatures=[];
  if(state.libraryCreateKind==='character'&&!LIBRARY_MINIATURE_PRESETS.some(m=>m.id===state.libraryMiniatureId))
   state.libraryMiniatureId=LIBRARY_MINIATURE_PRESETS[0].id;
 }
 selectBestiaryDefaultMiniature();
 paintLibraryMiniatures();
}

async function confirmCreatureDeletion(rows){
  const creatures=rows.map(row=>row.creature||row);
  if(!creatures.length)return false;
  const known=new Set(creatures.map(creature=>creature.id));
  // A parent deletion also removes its attached sheets. Show their names
  // before confirmation so the cascading operation is never surprising.
  for(const creature of [...creatures]){
    if(creature.parent_creature_id)continue;
    for(const child of await listSubcreatures(creature.id)){
      if(known.has(child.creature.id))continue;
      known.add(child.creature.id);creatures.push(child.creature);
    }
  }
  const amount=creatures.length;
  return new Promise(resolve=>{
    const dialog=document.createElement('dialog');
    dialog.id='library-delete-dialog';
    dialog.className='library-create-dialog library-delete-dialog';
    dialog.setAttribute('aria-labelledby','library-delete-title');
    dialog.setAttribute('aria-describedby','library-delete-warning');
    dialog.innerHTML='<div class="library-create-body">'+
      dialogCloseButton('library-delete-close','Chiudi','library-create-close')+
      '<h2 id="library-delete-title">Eliminare '+amount+' '+(amount===1?'creatura':'creature')+'?</h2>'+
      '<p id="library-delete-warning">'+(amount===1?'La seguente creatura verrà eliminata':'Le seguenti creature verranno eliminate')+
      ' dall’archivio locale. L’operazione non può essere annullata.</p>'+
      '<ul class="library-delete-list" aria-label="Creature da eliminare"></ul>'+
      '<div class="library-create-actions">'+
      '<button type="button" class="btn" data-library-delete-cancel>Annulla</button>'+
      '<button type="button" class="btn primary library-delete-confirm" data-library-delete-confirm>Elimina '+
      amount+' '+(amount===1?'creatura':'creature')+'</button></div></div>';
    const list=dialog.querySelector('.library-delete-list');
    for(const creature of creatures){
      const item=document.createElement('li');
      const name=document.createElement('strong');
      const kind=document.createElement('span');
      name.textContent=String(creature.name||'Creatura senza nome');
      kind.textContent=creature.parent_creature_id?'Sottocreatura collegata':
        creature.kind==='monster'?'Mostro':'Personaggio';
      item.append(name,kind);
      list.append(item);
    }
    let finished=false;
    const complete=confirmed=>{
      if(finished)return;
      finished=true;
      resolve(confirmed);
      closeDialog(dialog,{remove:true});
    };
    dialog.addEventListener('close',()=>complete(false),{once:true});
    for(const button of dialog.querySelectorAll('[data-act="library-delete-close"],[data-library-delete-cancel]'))
      button.addEventListener('click',event=>{event.stopPropagation();complete(false);});
    dialog.querySelector('[data-library-delete-confirm]').addEventListener('click',event=>{
      event.stopPropagation();complete(true);
    });
    dialog.addEventListener('click',event=>{if(event.target===dialog)complete(false);});
    document.body.append(dialog);
    openDialog(dialog);
    dialog.querySelector('[data-library-delete-cancel]').focus();
  });
}

function librarySelectionActions(){
 const count=state.librarySelectedIds.size;
 return count?
  '<button type="button" class="library-bulk-button library-bulk-export" data-act="library-export" aria-label="Esporta creature selezionate">'+
    '<span class="library-bulk-glyph" aria-hidden="true">'+actionGlyph('scroll')+'</span>'+
    '<span>Esporta</span></button>'+
  '<button type="button" class="library-bulk-button library-bulk-export" data-act="library-send" aria-label="Manda creature selezionate">'+
    '<span class="library-bulk-glyph" aria-hidden="true">'+actionGlyph('scroll')+'</span>'+
    '<span>Manda</span></button>'+
  '<button type="button" class="library-bulk-button library-bulk-delete" data-act="library-delete" aria-label="Elimina creature selezionate">'+
    '<span class="library-bulk-glyph library-bulk-delete-symbol" aria-hidden="true">×</span>'+
    '<span>Elimina</span></button>':'';
}
function syncLibrarySelectionUI(){
 const entries=[...app.querySelectorAll('.library-creature-entry')];
 const visible=entries.filter(e=>!e.hidden);
 const selecting=state.librarySelectedIds.size>0;
 // Once the final checkbox is unchecked, a new tap must open the creature
 // immediately; no stale synthetic-click suppression may linger.
 if(!selecting)libraryClickSuppression=null;
 app.querySelector('.library-index')?.classList.toggle('is-selecting',selecting);
 const all=app.querySelector('[data-library-select-all]');
 if(all){
  const selected=visible.filter(e=>state.librarySelectedIds.has(e.dataset.libraryId)).length;
  all.checked=visible.length>0&&selected===visible.length;
  all.indeterminate=selected>0&&selected<visible.length;
  all.disabled=!visible.length;
 }
 for(const entry of entries){
  const selected=state.librarySelectedIds.has(entry.dataset.libraryId);
  entry.classList.toggle('is-selected',selected);
  const checkbox=entry.querySelector('input[data-library-select]');
  if(checkbox)checkbox.checked=selected;
  const open=entry.querySelector('.creature-open');
  if(open)open.setAttribute('aria-pressed',String(selecting&&selected));
 }
 const master=app.querySelector('.library-list-header');
 if(master)master.hidden=!selecting;
 const actions=app.querySelector('#library-selected-actions');
 if(actions){actions.innerHTML=librarySelectionActions();actions.hidden=!selecting;}
}
function syncLibraryFilterUI(){
 const entries=[...app.querySelectorAll('.library-creature-entry')];
 for(const entry of entries)
  entry.hidden=(entry.dataset.librarySubcreature==='true'&&state.libraryFilter!=='monster')||
    (state.libraryFilter!=='all'&&entry.dataset.libraryKind!==state.libraryFilter);
 for(const button of app.querySelectorAll('[data-act="library-filter"]'))
  button.setAttribute('aria-pressed',String(button.dataset.kind===state.libraryFilter));
 const empty=app.querySelector('#library-no-results');
 if(empty)empty.hidden=!entries.length||entries.some(entry=>!entry.hidden);
 syncLibrarySelectionUI();
}
async function libraryView(){
 if(state.creatureId&&!state.libraryMode)return editorView();
 const rows=await listCreatures("default",{includeSubcreatures:true});
 const byId=new Map(rows.map(row=>[row.creature.id,row.creature]));
 const ids=new Set(rows.map(row=>row.creature.id));
 for(const id of state.librarySelectedIds)if(!ids.has(id))state.librarySelectedIds.delete(id);
 const list=rows.map(({creature:c})=>{
  const monster=c.kind==='monster';
  const species=c.species||c.race||(typeof c.stat_block?.type==='object'?c.stat_block.type.type:c.stat_block?.type)||c.type||'Razza non specificata';
  const classes=localClasses(c).map(m=>String(m.name)+' '+Math.max(1,Number(m.level)||1)).join(' · ');
  const subline=c.parent_creature_id?
    [c.companion_origin_name&&c.bestiary_ref?.name?
      c.companion_origin_name+' - '+c.bestiary_ref.name:'',
     'Di '+(byId.get(c.parent_creature_id)?.name||'creatura sconosciuta'),
     companionGrantActive(byId.get(c.parent_creature_id)||{},c)?'':'Non disponibile'].filter(Boolean).join(' · '):
    (classes||(c.level?'Liv. '+c.level:''));
  return '<div class="library-creature-entry" data-library-id="'+esc(c.id)+'" data-library-subcreature="'+Boolean(c.parent_creature_id)+'" data-library-kind="'+(monster?'monster':'character')+'">'+
   '<label class="library-batch-check" aria-label="Seleziona '+esc(c.name)+'">'+
   '<input type="checkbox" data-library-select="'+esc(c.id)+'" '+(state.librarySelectedIds.has(c.id)?'checked':'')+'>'+
   '<span class="library-check-graphic" aria-hidden="true">✓</span></label>'+
   '<article class="creature-card"><button type="button" class="creature-open" data-act="open" data-id="'+esc(c.id)+'" aria-label="Apri scheda di '+esc(c.name)+'">'+
   '<span class="library-creature-emblem">'+actionGlyph(monster?'shield':'proficiency')+'</span>'+
   '<span class="creature-info"><span class="creature-category">'+(c.archive_unreadable?'Da recuperare':c.parent_creature_id?'Famiglio':monster?'Mostro':'Personaggio')+'</span>'+
   '<span class="creature-name">'+esc(c.name)+'</span>'+
   '<span class="creature-meta"><span class="creature-details">'+esc(species)+'</span>'+
   (subline?'<span class="creature-classes">'+esc(subline)+'</span>':'')+
   '</span></span><span class="creature-open-chevron" aria-hidden="true">›</span></button></article></div>';
 }).join('');
 return '<section class="library-index" aria-label="Le tue creature">'+
  '<section class="library-home-hero"><h1>Le tue creature</h1>'+
  '<span class="library-hero-crest" aria-hidden="true"><span class="library-hero-crest-inner">'+actionGlyph('proficiency')+'</span></span>'+
  '<div class="library-filters" role="group" aria-label="Filtra creature">'+
   [['all','Tutte'],['character','Personaggi'],['monster','Mostri']].map(([kind,label])=>
    '<button type="button" data-act="library-filter" data-kind="'+kind+'" aria-pressed="'+(kind===state.libraryFilter)+'">'+label+'</button>').join('')+
  '</div>'+
  '<div class="library-list-header" '+(state.librarySelectedIds.size?'':'hidden')+'>'+
   '<label class="library-select-master"><input type="checkbox" data-library-select-all aria-label="Seleziona tutte le creature visibili">'+
   '<span class="library-check-graphic" aria-hidden="true">✓</span><span class="library-select-master-copy">Seleziona tutte</span></label>'+
   '<div id="library-selected-actions" class="library-selection-actions" '+(state.librarySelectedIds.size?'':'hidden')+'>'+librarySelectionActions()+'</div></div>'+
  '<div class="library-rows">'+(list||'<div class="library-empty">Nessuna creatura salvata.</div>')+'</div>'+
  (rows.length?'<div id="library-no-results" class="library-no-results" hidden>Nessuna creatura in questa categoria.</div>':'')+
  '</section>'+
  '<div class="library-home-shortcuts">'+
   '<button type="button" class="library-shortcut library-shortcut-main" data-act="library-add">'+
    '<span class="library-shortcut-icon">'+actionGlyph('proficiency')+'</span>'+
    '<span class="library-shortcut-copy"><strong>Nuova creatura</strong><small>Crea una scheda</small></span>'+
    '<span class="library-shortcut-arrow" aria-hidden="true">+</span></button>'+
   '<button type="button" class="library-shortcut" data-act="library-quick-import">'+
    '<span class="library-shortcut-icon">'+actionGlyph('scroll')+'</span>'+
    '<span class="library-shortcut-copy"><strong>Importa JSON</strong></span>'+
    '<span class="library-shortcut-arrow" aria-hidden="true">↗</span></button></div></section>'+
  '<details class="library-backup"><summary>'+
   '<span class="library-backup-symbol">'+actionGlyph('scroll')+'</span>'+
   '<span class="library-backup-copy"><strong>Backup e ripristino</strong></span>'+
   '<span class="library-backup-chevron" aria-hidden="true">⌄</span></summary>'+
   '<div class="library-backup-content"><div class="library-backup-actions">'+
    btn('backup','Esporta backup')+btn('restore-backup','Ripristina backup')+'</div>'+serverBackupMarkup()+'</div></details>'+
  '<dialog id="library-create-dialog" class="library-create-dialog" aria-labelledby="library-create-title">'+
   '<div class="library-create-body">'+dialogCloseButton('library-create-close','Chiudi','library-create-close')+
    '<h2 id="library-create-title">Nuova creatura</h2>'+
    '<div class="library-create-types" role="group" aria-label="Tipo di creatura">'+
     '<button type="button" class="library-create-type is-active" data-act="library-create-kind" data-kind="character" aria-pressed="true">'+actionGlyph('proficiency')+'Personaggio</button>'+
     '<button type="button" class="library-create-type" data-act="library-create-kind" data-kind="monster" aria-pressed="false">'+actionGlyph('book')+'Bestiario</button></div>'+
    '<div id="library-create-bestiary" class="library-create-bestiary" hidden>'+
     '<label class="library-create-field" for="library-bestiary-search">Razza dal bestiario'+
       '<input id="library-bestiary-search" type="search" placeholder="Cerca un mostro" autocomplete="off"></label>'+
     '<div class="library-bestiary-choices vtt-selection-list" role="group" aria-label="Mostri del bestiario"></div>'+
     '<div class="library-bestiary-pagination"><span class="library-bestiary-progress" aria-live="polite"></span>'+
       '<button type="button" class="library-miniature-more" data-act="library-bestiary-more" hidden>Mostra altri</button></div></div>'+
    '<label class="library-create-field" for="library-create-name"><span data-library-name-label>Nome</span>'+
     '<input id="library-create-name" type="text" maxlength="120" placeholder="Nuova creatura" autocomplete="off"></label>'+
    '<div class="library-create-miniature-title"><strong>Miniatura di base</strong><small class="library-miniature-current" role="status">Selezionata: Sariel</small></div>'+
    '<label class="library-miniature-search vtt-list-search" for="library-miniature-search">'+actionGlyph('search')+
     '<input id="library-miniature-search" type="search" placeholder="Cerca miniatura" autocomplete="off"></label>'+
    '<div class="library-miniature-choices vtt-selection-list" role="group" aria-label="Scegli miniatura"></div>'+
    '<div class="library-miniature-pagination"><span class="library-miniature-progress" aria-live="polite"></span>'+
     '<button type="button" class="library-miniature-more" data-act="library-miniature-more" hidden>Mostra altre</button></div>'+
    '<div class="library-create-actions">'+
     '<button type="button" class="btn" data-act="library-create-close">Annulla</button>'+
     '<button type="button" class="btn primary" data-act="create">Crea creatura</button></div>'+
   '</div></dialog>';
}
function catalogTargetCreature(){
  const id=state.pendingItemOwner||state.catalogAssignCreatureId||state.featAssignReturnId||state.creatureId||
    state.cachedCreatures?.[0]?.id;
  if(!id)return null;
  const opened=state.editor?.read();
  return opened?.id===id?opened:(state.cachedCreatures||[]).find(row=>row.id===id)||null;
}
function catalogRowsForTarget(){
  const target=catalogTargetCreature();
  return state.catalogRows.map((row,i)=>({row,i})).filter(({row})=>
    !target||isContentAvailableForRules(row,target.rules_version));
}
function renderCatalogRows() {
  const matches=catalogRowsForTarget()
    .filter(({row})=>matchesSearch(state.catalogQuery,row.name,row.source));
  const {items,shown,total}=pageResults(matches,state.catalogResultLimit);
  return (items.length?items.map(({row,i})=>
    '<button type="button" class="btn full catalog-entry vtt-selectable" data-act="catalog-open" data-index="'+i+'">'+
    '<span>'+esc(row.name||"Senza nome")+'</span><span class="tag">'+esc(row.source||row._category||"")+'</span></button>').join("") :
    '<p class="hint">Nessun risultato. Prova un altro termine o una categoria.</p>')+
    resultsFooter('catalog-more',shown,total,90);
}
async function catalogView() {
  state.catalogRows=await catalogEntries(state.catalogCategory);
  let chosen=state.catalogRows[state.catalogSelected];
  const target=catalogTargetCreature();
  if(chosen&&target&&!isContentAvailableForRules(chosen,target.rules_version)){
    state.catalogSelected=-1;chosen=null;
  }
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
      '<div class="separator"></div>'+(state.pendingItemOwner&&state.catalogCategory==='items'?'':'<label>Aggiungi alla scheda<select id="catalog-creature">')+
      (state.pendingItemOwner&&state.catalogCategory==='items'?'':state.cachedCreatures.map(c=>'<option value="'+esc(c.id)+'"'+((state.pendingItemOwner||state.catalogAssignCreatureId||state.featAssignReturnId||state.creatureId||state.cachedCreatures?.[0]?.id)===c.id?' selected':'')+'>'+esc(c.name)+'</option>').join(""))+
      (state.pendingItemOwner&&state.catalogCategory==='items'?'':'</select></label>')+'<div class="actions">'+btn("catalog-assign","Aggiungi contenuto alla creatura","primary")+
      (chosen._homebrew?btn('catalog-send','Manda'):'')+'</div>'+
      '':"")+
      (chosen._homebrew&&!(assignable&&(state.cachedCreatures||[]).length)?
        '<div class="actions">'+btn('catalog-send','Manda')+'</div>':'')+
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
      '</select></label><label class="vtt-list-search">Ricerca<input id="catalog-search" type="search" value="'+esc(state.catalogQuery)+
      '" placeholder="Nome o fonte"></label></div><p class="hint">'+
      catalogRowsForTarget().length+' voci nel catalogo · risultati caricati progressivamente</p>'+
      '<div id="catalog-results" class="catalog-results vtt-selection-list">'+renderCatalogRows()+'</div>')+
    (quickPanel?'<details class="archive-tools catalog-create"><summary>Crea contenuto personalizzato</summary>'+quickPanel+'</details>':''));
}

async function computeLocalData(record){
  let catalogs={},loadError="";
  const request=loadRuleCatalogs();
  try{catalogs=await sheetLoadingDeadline(request,3000,"delle regole");}
  catch(error){
    loadError="Cataloghi numerici offline non disponibili: "+errorMessage(error);
    if(error.code==='SHEET_LOADING_TIMEOUT')
      refreshSheetAfterLateLoad(request,record.id,state.sheet);
  }
  // Combine only the spell definitions already present in the local sheet,
  // scoped lookups, and bundled legacy rules. Never turn a calculation into
  // a blocking fetch of the complete compendium.
  const visibleSpells=[...(state.spellCatalog||[]),
    ...(record.prepared_spells||[]),...(record.spellbook_spells||[]),
    ...(record.known_spells||[])].filter(spell=>spell&&typeof spell==='object'&&spell.id);
  catalogs={...catalogs,spells:[...new Map([...(catalogs.spells||[]),...visibleSpells]
    .map(spell=>[spell.id,spell])).values()]};
  catalogs.abilityGrants={...(catalogs.abilityGrants||{}),artificer_infusions:(inventoryModule.expandedInfusionDefinitions||((rows)=>rows))(catalogs.abilityGrants?.artificer_infusions||[])};
  let companionData={};
  const companionRequest=companionRules();
  try{companionData=await sheetLoadingDeadline(companionRequest,3000,'dei compagni');}
  catch(error){
    loadError=[loadError,'Comandi dei compagni non disponibili: '+errorMessage(error)].filter(Boolean).join(' · ');
    if(error.code==='SHEET_LOADING_TIMEOUT')refreshSheetAfterLateLoad(companionRequest,record.id,state.sheet);
  }
  let linked=null;
  if(record.parent_creature_id){
    try{
      const parent=await loadCreature(record.parent_creature_id);
      if(parent?.data?.id===record.parent_creature_id&&
         parent.data.owner_id===record.owner_id&&!parent.data.parent_creature_id){
        const parentRecord=resolveVariant(parent.data);
        linked=companionOwnerValues(record,parentRecord,
          calculateSheet(parentRecord,catalogs),await companionRules());
      }
    }catch{ /* A missing owner must not prevent opening the saved familiar. */ }
  }
  const companionView=companionStatBlockView(record,companionData);
  const calculated=calculateSheet(linked?
    {...companionView,companion_owner_values:linked}:companionView,catalogs);
  // Internal racial powers must remain resolvable offline, even when the
  // native host has not supplied a full/selected spell catalogue yet.
  const ownedAreaIds=new Set((calculated.origin_spells||[]).map(row=>row.spell_id));
  const embedded=(calculated.racial_spell_definitions||[]).filter(row=>ownedAreaIds.has(row.id));
  if(embedded.length){
    const spellMap=new Map((state.spellCatalog||[]).map(row=>[row.id,row]));
    for(const definition of embedded)spellMap.set(definition.id,{...definition,...spellMap.get(definition.id)});
    state.spellCatalog=[...spellMap.values()];
  }
  const infusion_catalog=catalogs.abilityGrants?.artificer_infusions||[];
  const infusion_mechanics={...(catalogs.classMechanics||{}),feature_item_grants:catalogs.featureItemGrants||[]};
  const powerSelectionCatalog={...(catalogs.powerSelections||{}),optionalFeatureProgressions:catalogs.optionalFeatureProgressions||{},capacity_grants:featureItemGrants(record,calculated.features||[],catalogs.featureItemGrants||[])};
  const power_selections=powerSelectionModels(record,calculated,powerSelectionCatalog);
  // Spell-like class privileges are ordinary levelled spell definitions. Keep
  // their catalog details available offline and after an asynchronous refresh.
  const featureSpells=catalogs.featureSlotSpells?.spells||[];
  if(featureSpells.length){
    const definitions=new Map((state.spellCatalog||[]).map(row=>[row.id,row]));
    for(const definition of featureSpells)definitions.set(definition.id,definition);
    state.spellCatalog=[...definitions.values()];
  }
  return {...calculated,loadError,companion_view:companionView,companion_rules:companionData,combat_snapshot:state.map||null,
    power_selections,power_selection_catalog:powerSelectionCatalog,
    pending_choices:pendingCharacterChoices(record,calculated,{...catalogs,
      races:state.referenceCatalogs.races||[],subclasses:state.referenceCatalogs.subclasses||[]}),
    infusion_catalog,infusion_mechanics};
}

// Spells and nonspell powers share their popup header, facts and description.
function actionDialogIntro(name,facts=[],description='',meta='',closeAction=''){
 return '<header class="vtt-popup-heading"><h2>'+esc(name)+'</h2>'+
  (closeAction?dialogCloseButton(closeAction,'Chiudi',''):'')+'</header>'+
  (meta?'<p class="hint magic-spell-metadata">'+esc(meta)+'</p>':'')+
  (facts.length?'<dl class="magic-spell-facts">'+facts.map(({label,value})=>
   '<div class="magic-spell-fact"><dt>'+esc(label)+'</dt><dd>'+esc(value)+'</dd></div>').join('')+'</dl>':'')+
  '<div class="magic-spell-description">'+esc(description||'Descrizione non disponibile.')+'</div>';
}
function abilityPaymentField(ability,calculated){
 const cost=Math.max(0,Number(ability.cost??ability.resource_cost??0)||0),id=String(ability.tracker_id||'');
 if(!id||cost<=0&&ability.mode!=='toggle')return '';
 const tracker=(calculated.trackers||[]).find(row=>row.id===id&&!row.disabled);
 const remaining=tracker?Math.max(0,Number(tracker.max||0)-Number(tracker.spent||0)):0;
 if(ability.infusion_action)return '<p class="magic-ability-payment"><strong>Cariche dell’oggetto</strong> · '+
   esc(cost)+' · '+esc(remaining)+' disponibili</p>'+
   '<input type="hidden" data-ability-payment value="'+esc(id)+'">';
 return '<label>Tracker da consumare<select data-ability-payment>'+
  '<option value="'+esc(id)+'">'+esc(tracker?.name||ability.tracker||ability.resource_name||'Tracker associato')+
  ' · '+remaining+' disponibili</option>'+
  '<option value="">Nessun tracker</option></select></label>';
}
function selectionStateActivationPatch(record,calculated,id,options={}){
 return powerStateActivationPatch(record,calculated,calculated.power_selection_catalog||{},id)??
  traitStateActivationPatch(record,calculated.features,calculated.trait_state_catalog,id,calculated.trackers,options);
}
function abilityPaymentChoice(dialog){return dialog.querySelector('[data-ability-payment]')?.value;}

function classAbilityActivationPatch(c,calculated,ability,options={}){
 return classFeatureActivationPatch(c,calculated,ability.id,options);
}
// A granted item can offer a reusable typed power. Action economy and effects
// are sourced from the item grant, so unrelated classes can use the same UI.
async function openGrantedItemPowerDialog(c,calculated,ability,powers){
 const rows=Array.isArray(powers)?powers:[];
 const current=(await listCreatures()).map(row=>row.creature||row).filter(row=>row?.id);
 const nameById=new Map(current.map(row=>[String(row.id),String(row.name||row.id)]));
 if(!nameById.has(String(c.id)))nameById.set(String(c.id),String(c.name||'Sé stesso'));
 const mod=Number(calculated.abilities?.int?.modifier)||0;
 const prof=Number(calculated.stats?.proficiency)||2;
 const dieFormula=power=>String(power.damage_dice||power.damage||'').replace(/\s+/g,'');
 const dc=8+prof+mod;
 const label=power=>power.item_name+' · '+power.name;
 const details=power=>power.mode==='spell_attack'?
   'Attacco magico '+(Number(calculated.values?.['casting_hit:'+power.casting_ability])>=0?'+':'')+
   Number(calculated.values?.['casting_hit:'+power.casting_ability]??prof+mod)+
   ' · '+power.range_feet+' ft · '+dieFormula(power)+' '+power.damage_type:
   power.mode==='save_area'?'TS '+String(power.save_ability||'dex').toUpperCase()+' CD '+dc+
    ' · '+String(power.area_shape||'cone')+' '+power.area_length_feet+' ft · '+dieFormula(power)+' '+power.damage_type:
   'Raggio '+power.radius_feet+' ft · '+power.temp_hp.replace('int_mod',String(Math.max(Number(power.minimum_modifier)||0,mod)))+' PF temporanei';
 document.querySelector('#feature-item-power-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='feature-item-power-dialog';dialog.className='sheet-roll-dialog magic-spell-dialog';
 dialog.dataset.creatureId=String(c.id||'');
 dialog.innerHTML=actionDialogIntro(ability.name,[
  {label:'Azione',value:'Azione bonus'},
  {label:'Origine',value:'Oggetto concesso · '+ability.feature_name}
 ],'Attiva il cannone che possiedi. I tiri e la selezione dei bersagli partono dall’oggetto; controlla le distanze rispetto alla sua posizione, non a quella del personaggio.',
 'Privilegio legato a un oggetto','item-power-close')+
 '<div class="magic-ability-detail">'+rows.map((power,index)=>
   '<section class="infusion-dialog-active" data-item-power-row="'+index+'">'+
   '<h3>'+esc(label(power))+'</h3>'+
   '<p class="hint">'+esc(details(power))+'</p>'+
   '<p>'+esc(power.description||'')+'</p>'+
   (power.mode==='spell_attack'?
    '<div class="actions"><button class="btn primary" type="button" data-item-power="hit" data-item-power-index="'+index+'">Tira per colpire</button>'+
    '<button class="btn" type="button" data-item-power="damage" data-item-power-index="'+index+'">Tira danni (se colpisce)</button></div>':
    power.mode==='save_area'?
    '<div class="actions"><button class="btn primary" type="button" data-item-power="damage" data-item-power-index="'+index+'">Tira danni</button></div>'+
    '<p class="hint">TS Destrezza: metà danni se superato; l’area origina dal cannone.</p>':
    power.mode==='temporary_hp_area'?
    '<details><summary>Creature entro '+esc(power.radius_feet)+' ft dal cannone</summary>'+
    '<div class="session-condition-grid">'+[...nameById].map(([id,name])=>
     '<label class="check"><input type="checkbox" data-item-power-recipient="'+index+'" value="'+esc(id)+'"'+
      (id===String(c.id)?' checked':'')+'>'+esc(name)+'</label>').join('')+'</div></details>'+
    '<div class="actions"><button class="btn primary" type="button" data-item-power="temporary_hp" data-item-power-index="'+index+'">Tira e assegna PF temporanei</button></div>':'')+
   '</section>').join('')+'</div>'+
 '<p class="hint" data-item-power-result role="status"></p>'+
 '<div class="actions magic-dialog-actions"><button type="button" class="btn" data-act="item-power-close">Chiudi</button></div>';
 dialog.addEventListener('click',async event=>{
  const button=event.target.closest('[data-item-power]');
  if(!button)return;
  const power=rows[Number(button.dataset.itemPowerIndex)];
  if(!power)return;
  button.disabled=true;
  try{
   const saved=state.editor?.read();
   if(!saved||String(saved.id)!==dialog.dataset.creatureId)throw Error('Scheda non più disponibile.');
   const updated=await computeLocalData(saved);
   const valid=featureItemPowers(saved,updated,ability.class_feature_id).some(row=>
    row.grant_id===power.grant_id&&row.item_index===power.item_index&&row.id===power.id);
   if(!valid)throw Error('Il cannone selezionato non è più presente nell’inventario.');
   if(button.dataset.itemPower==='hit'){
    closeDialog(dialog,{remove:true});
    await handleAction({dataset:{act:'sheet-roll',target:'casting_hit:'+power.casting_ability,
      label:label(power)+' · Attacco magico'}});
   }else if(button.dataset.itemPower==='damage'){
    closeDialog(dialog,{remove:true});
    await handleAction({dataset:{act:'battle-damage-roll',
      damageFormula:dieFormula(power),damageType:power.damage_type,
      damageLabel:label(power),damageAttackId:''}});
   }else if(button.dataset.itemPower==='temporary_hp'){
    const ids=[...dialog.querySelectorAll('[data-item-power-recipient="'+button.dataset.itemPowerIndex+'"]:checked')]
     .map(input=>input.value);
    if(!ids.length)throw Error('Seleziona almeno una creatura entro il raggio.');
    const usedMod=Math.max(Number(power.minimum_modifier)||0,Number(updated.abilities?.int?.modifier)||0);
    const outcome=rollBattleDamage('1d8'+(usedMod>=0?'+':'')+usedMod,randomDie);
    if(!Number.isFinite(outcome.total))throw Error('Tiro dei PF temporanei non disponibile.');
    let applied=0;
    for(const recipientId of ids){
     const targetEditor=recipientId===String(saved.id)?state.editor:await openCreatureEditor(recipientId);
     const target=targetEditor.read();
     if(!target||String(target.id)!==recipientId)continue;
     await targetEditor.update({temporary_hp:Math.max(Number(target.temporary_hp)||0,outcome.total)});
     applied++;
    }
    // A cannon is an object with its own temporary HP, not a second creature.
    const own=state.editor.read(),inventory=structuredClone(own.inventory||[]);
    if(inventory[power.item_index]?.feature_item_grant_id===power.grant_id)
      inventory[power.item_index].temporary_hp=Math.max(Number(inventory[power.item_index].temporary_hp)||0,outcome.total);
    await state.editor.update({inventory});
    dialog.querySelector('[data-item-power-result]').textContent=
     'Protector: '+outcome.notation+' = '+outcome.total+' PF temporanei. Applicati a '+
     applied+' creature selezionate e al cannone.';
    message('Protector: '+outcome.total+' PF temporanei · '+applied+' creature.');
   }
  }catch(error){
   dialog.querySelector('[data-item-power-result]').textContent=errorMessage(error);
  }finally{button.disabled=false;}
 });
 dialog.querySelectorAll('[data-act="item-power-close"],[data-act="item-power-close"]')
  .forEach(button=>button.addEventListener('click',()=>closeDialog(dialog,{remove:true})));
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 document.body.append(dialog);openDialog(dialog);
}

// Reuse the standard item extension and tracker models; the player chooses
// the physical copy and the full Artificer spell from the 2014 catalog.
async function openSpellStoringItemDialog(creature,calculated,ability){
 const candidates=eligibleSpellStoringItems(creature);
 if(!candidates.length)throw Error('Aggiungi prima un’arma o un focus da incantatore all’inventario.');
 let spellCatalog=state.spellCatalog||[];
 try{spellCatalog=await loadFullSpellCatalog();}catch(error){
  if(!spellCatalog.length)throw Error('Catalogo incantesimi non disponibile. Riprova quando è stato caricato.');
 }
 const spells=eligibleStoredSpells(spellsForEdition(spellCatalog,creature.rules_version||'2014'));
 if(!spells.length)throw Error('Nessun incantesimo da Artefice di livello 1–2 con tempo di lancio 1 azione nel catalogo.');
 const old=storedSpellExtension(creature),oldName=old?.spell_name||'';
 document.querySelector('#spell-storing-item-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='spell-storing-item-dialog';dialog.className='sheet-roll-dialog magic-spell-dialog';
 dialog.dataset.creatureId=String(creature.id||'');
 const uses=storedSpellMaxUses(calculated.abilities?.int?.modifier);
 dialog.innerHTML=actionDialogIntro('Spell-Storing Item',[
  {label:'Origine',value:'Tratto · Spell-Storing Item'},
  {label:'Utilizzi',value:uses+' (2 × INT, minimo 2)'},
  {label:'Disponibilità',value:'Fino al prossimo riposo lungo'}
 ],'Scegli un’arma o un focus da incantatore che possiedi e un incantesimo da Artefice di 1° o 2° livello che richieda un’azione. Non occorre averlo preparato. Il possessore può produrre l’effetto senza spendere slot e si concentra se necessario.',
 old?'Attualmente immagazzinato: '+oldName:'Nessun incantesimo immagazzinato',
 'spell-storing-close')+
  '<label>Oggetto dell’inventario<select data-stored-item>'+
  candidates.map(({item,index})=>'<option value="'+index+'"'+
    (old?.target_instance_id&&item.instance_id===old.target_instance_id?' selected':'')+'>'+
    esc(item.name||item.id||'Oggetto')+' · copia '+(index+1)+'</option>').join('')+
  '</select></label>'+
  '<label>Cerca incantesimo<input data-stored-query type="search" placeholder="Nome incantesimo" autocomplete="off"></label>'+
  '<label>Incantesimo da immagazzinare<select data-stored-spell></select></label>'+
  '<div data-stored-spell-details class="inventory-prose"></div>'+
  '<p data-stored-error role="alert" class="warning"></p>'+
  '<div class="actions magic-dialog-actions"><button type="button" class="btn primary" data-stored-confirm>'+
    (old?'Sostituisci incantesimo':'Immagazzina incantesimo')+'</button>'+
  '<button type="button" class="btn" data-stored-cancel>Annulla</button></div>';
 const spellInput=dialog.querySelector('[data-stored-spell]'),
  query=dialog.querySelector('[data-stored-query]'),details=dialog.querySelector('[data-stored-spell-details]');
 const updateDetails=()=>{
  const spell=spells.find(row=>String(row.id)===spellInput.value);
  details.textContent=spell?('Livello '+spell.level+' · 1 azione\n'+
    flattenDescription(spell)):'Nessun incantesimo corrispondente.';
 };
 const filter=()=>{
  const q=query.value.trim().toLocaleLowerCase('it');
  const current=spellInput.value;
  const filtered=spells.filter(row=>!q||String(row.name||'').toLocaleLowerCase('it').includes(q));
  spellInput.innerHTML=filtered.map(row=>'<option value="'+esc(row.id)+'">'+
    esc(row.name)+' · livello '+esc(row.level)+'</option>').join('');
  if(filtered.some(row=>String(row.id)===current))spellInput.value=current;
  else if(!q&&old?.spell_id&&filtered.some(row=>String(row.id)===old.spell_id))
   spellInput.value=old.spell_id;
  dialog.querySelector('[data-stored-confirm]').disabled=!filtered.length;
  updateDetails();
 };
 query.addEventListener('input',filter);
 spellInput.addEventListener('change',updateDetails);
 filter();
 dialog.querySelectorAll('[data-stored-cancel],[data-act="spell-storing-close"]').forEach(button=>
  button.addEventListener('click',()=>closeDialog(dialog,{remove:true})));
 dialog.querySelector('[data-stored-confirm]').addEventListener('click',async event=>{
  const button=event.currentTarget;
  if(button.disabled)return;
  button.disabled=true;
  try{
   const current=state.editor?.read();
   if(!current||String(current.id)!==dialog.dataset.creatureId)throw Error('La scheda è cambiata.');
   const index=Number(dialog.querySelector('[data-stored-item]').value);
   const spell=spells.find(row=>String(row.id)===spellInput.value);
   if(!spell)throw Error('Scegli un incantesimo disponibile.');
   const fresh=await computeLocalData(current);
   // Recheck both the item and the spell at save time. No spell slots or
   // existing item instance are created or consumed by this operation.
   const patchData=storeSpellInItemPatch(current,fresh,index,spell,flattenDescription(spell),
    'pwa_instance_'+crypto.randomUUID());
   await patch(patchData);
   if(state.saveError)throw Error(state.saveError);
   await state.editor.flush();
   closeDialog(dialog,{remove:true});await render();
   message('Spell-Storing Item: '+spell.name+' immagazzinato nell’oggetto, '+uses+' utilizzi.');
  }catch(error){
   button.disabled=false;dialog.querySelector('[data-stored-error]').textContent=errorMessage(error);
  }
 });
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 document.body.append(dialog);openDialog(dialog);
}
// One dialog for any trait that grants a spell-to-item imprint. Source rules
// determine the item type, known class list, casting action and expiration.
// Unlike Spell-Storing Item, Hidden Ace's selection is once per long rest.
async function openSpellImprintDialog(creature,calculated,ability){
 const rule=(calculated.spell_imprint_rules||[]).find(row=>
  row.id===ability.imprint_rule_id);
 if(!rule)throw Error('Il privilegio di immagazzinamento non è disponibile.');
 const existing=spellImprintExtension(creature,rule);
 const already=creature.spell_imprint_prepared?.[rule.id]===true;
 const items=eligibleSpellImprintItems(creature,rule);
 if(!items.length&&!already)throw Error('Aggiungi prima una carta o un mazzo di carte all’inventario.');
 let catalog=state.spellCatalog||[];
 if(!already)try{catalog=await loadFullSpellCatalog();}catch(error){
  if(!catalog.length)throw Error('Catalogo degli incantesimi non disponibile.');
 }
 const spells=eligibleSpellImprintSpells(creature,calculated,
  spellsForEdition(catalog,creature.rules_version||'2014'),rule);
 if(!spells.length&&!already)throw Error('Nessun incantesimo della tua lista di classe rispetta i limiti di livello e tempo di lancio.');
 document.querySelector('#spell-imprint-dialog')?.remove();
 const dialog=document.createElement('dialog');dialog.id='spell-imprint-dialog';
 dialog.className='sheet-roll-dialog magic-spell-dialog';
 dialog.dataset.creatureId=String(creature.id||'');
 dialog.innerHTML=actionDialogIntro(rule.name||'Incantesimo nella carta',[
  {label:'Origine',value:'Tratto · '+(rule.origin_name||'')},
  {label:'Lancio',value:rule.cast_action_type==='bonus'?'Azione bonus':'Azione'},
  {label:'Durata',value:(rule.duration_hours||8)+' ore dalla preparazione'},
  {label:'Preparazione',value:'Una scelta per riposo lungo'}
 ],rule.description||'',existing?'Carta preparata: '+existing.spell_name:
   already?'Hai già usato questa scelta. È necessario un riposo lungo.':
   'Scegli una carta del tuo inventario e un incantesimo.',
 'spell-imprint-close')+
  (already?'<p class="hint">La carta è già stata preparata in questo ciclo di riposo. '+
    'Per cambiarla o prepararne un’altra completa un riposo lungo.</p>':
    '<label>Oggetto da incantare<select data-imprint-item>'+
    items.map(({item,index})=>'<option value="'+index+'">'+
      esc(item.name||item.id)+' · copia '+(index+1)+'</option>').join('')+'</select></label>'+
    '<label>Cerca incantesimo<input type="search" data-imprint-search autocomplete="off" placeholder="Nome incantesimo"></label>'+
    '<label>Incantesimo<select data-imprint-spell></select></label>'+
    '<div data-imprint-description class="inventory-prose"></div>')+
  '<p data-imprint-error class="warning" role="alert"></p>'+
  '<div class="actions magic-dialog-actions">'+
  (already?(existing&&spellImprintActive(existing)?
    '<button type="button" class="btn primary" data-imprint-cast>Lancia dalla carta · '+(rule.cast_action_type==='bonus'?'azione bonus':'azione')+'</button>':''):
    '<button type="button" class="btn primary" data-imprint-confirm>Prepara la carta</button>')+
  '<button type="button" class="btn" data-imprint-close>Chiudi</button></div>';
 const selector=dialog.querySelector('[data-imprint-spell]');
 if(selector){
  const search=dialog.querySelector('[data-imprint-search]');
  const refresh=()=>{
   const q=search.value.trim().toLocaleLowerCase('it'),previous=selector.value;
   const subset=spells.filter(spell=>!q||String(spell.name||'').toLocaleLowerCase('it').includes(q));
   selector.innerHTML=subset.map(spell=>'<option value="'+esc(spell.id)+'">'+
     esc(spell.name)+' · livello '+esc(spell.level)+'</option>').join('');
   if(subset.some(row=>row.id===previous))selector.value=previous;
   const selected=subset.find(row=>row.id===selector.value);
   dialog.querySelector('[data-imprint-confirm]').disabled=!selected;
   dialog.querySelector('[data-imprint-description]').textContent=selected?
     flattenDescription(selected):'Nessun incantesimo corrispondente.';
  };
  search.addEventListener('input',refresh);
  selector.addEventListener('change',refresh);
  refresh();
 }
 dialog.querySelectorAll('[data-imprint-close],[data-act="spell-imprint-close"]').forEach(button=>
  button.addEventListener('click',()=>closeDialog(dialog,{remove:true})));
 dialog.querySelector('[data-imprint-cast]')?.addEventListener('click',async event=>{
  const button=event.currentTarget;if(button.disabled)return;button.disabled=true;
  try{
   const current=state.editor?.read();
   if(!current||String(current.id)!==dialog.dataset.creatureId)
     throw Error('La scheda è cambiata.');
   const fresh=await computeLocalData(current);
   if(!(fresh.spell_imprint_rules||[]).some(r=>r.id===rule.id))
     throw Error('Il privilegio non è più disponibile.');
   const index=(current.inventory||[]).findIndex((item,i)=>
     spellImprintAtItem(current,i)?.imprint_rule_id===rule.id);
   if(index<0)throw Error('La carta è stata rimossa o sono trascorse otto ore.');
   const active=spellImprintAtItem(current,index);
   const update=useSpellImprintPatch(current,fresh,index);
   await patch(update);await state.editor.flush();
   closeDialog(dialog,{remove:true});await render();
   message(rule.name+' · '+(active.spell_name||'incantesimo')+
     ': lancio registrato come '+(rule.cast_action_type==='bonus'?'azione bonus':'azione')+
     '. Nessuno slot consumato. Risolvi bersagli, effetti e concentrazione normalmente.');
  }catch(error){
   button.disabled=false;
   dialog.querySelector('[data-imprint-error]').textContent=errorMessage(error);
  }
 });
 dialog.querySelector('[data-imprint-confirm]')?.addEventListener('click',async event=>{
  const button=event.currentTarget;if(button.disabled)return;
  button.disabled=true;
  try{
   const current=state.editor?.read();
   if(!current||String(current.id)!==dialog.dataset.creatureId)
    throw Error('La scheda è cambiata.');
   const fresh=await computeLocalData(current);
   const selectedRule=(fresh.spell_imprint_rules||[]).find(r=>r.id===rule.id);
   if(!selectedRule)throw Error('Privilegio non più disponibile.');
   const index=Number(dialog.querySelector('[data-imprint-item]')?.value);
   const spell=spells.find(row=>String(row.id)===String(selector.value));
   if(!spell)throw Error('Seleziona un incantesimo.');
   const update=storeSpellImprintPatch(current,fresh,rule.id,index,spell,
      flattenDescription(spell),'pwa_instance_'+crypto.randomUUID());
   await patch(update);
   if(state.saveError)throw Error(state.saveError);
   await state.editor.flush();
   closeDialog(dialog,{remove:true});await render();
   message(rule.name+': '+spell.name+' impresso nella carta. '+
     'Un lancio disponibile come '+(rule.cast_action_type==='bonus'?'azione bonus':'azione')+'.');
  }catch(error){
   button.disabled=false;
   dialog.querySelector('[data-imprint-error]').textContent=errorMessage(error);
  }
 });
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 document.body.append(dialog);openDialog(dialog);
}
async function activateClassAbility(c,calculated,ability,{onConfirmed=null,onClosed=null}={}){
 if(ability.class_feature_id==='spell_storing_item')
  return openSpellStoringItemDialog(c,calculated,ability);
 if(ability.mode==='metamagic'){
  state.sheet='magic';await render();message('Scegli un incantesimo: la Metamagia si configura nella finestra di lancio.');return;
 }
 const itemPowers=featureItemPowers(c,calculated,ability.class_feature_id);
 if(itemPowers.length)return openGrantedItemPowerDialog(c,calculated,ability,itemPowers);
 const enhanced=c.rules_version==='2024'&&['patient_defense','step_of_the_wind'].includes(ability.class_feature_id);
 const companionChoice=await companionFeatureChoices(c,calculated,ability.origin_id);
 const companion=companionChoice?.rule.activation==='resource'&&Number(ability.cost)>0?companionChoice:null;
 const itemGrant=(calculated.feature_item_grants||[]).find(row=>
  row.activation_action_id===ability.class_feature_id&&row.origin_id===ability.origin_id);
  document.querySelector('#class-feature-dialog')?.remove();
 const dialog=document.createElement('dialog');dialog.id='class-feature-dialog';dialog.className='sheet-roll-dialog magic-spell-dialog';
 dialog.dataset.creatureId=c.id;dialog.dataset.abilityId=ability.id;
 const recovery=ability.mode==='recovery',conversion=ability.mode==='conversion',pool=ability.mode==='heal_pool';
 dialog.innerHTML=actionDialogIntro(ability.name,[
  {label:'Azione',value:ability.time||ability.action_type||'Secondo il privilegio'},
  {label:'Origine',value:ability.origin_name||'Tratto di classe'}
 ],ability.description||'',ability.active?'Capacità attiva':'Capacità disponibile','feature-close')+
  abilityPaymentField(ability,calculated)+
  (pool?'<label>Punti ferita<input data-feature-amount type="number" min="1" max="'+esc(Math.max(1,(calculated.trackers||[]).find(t=>t.id===ability.tracker_id)?.max||1))+'" required></label><label class="check"><input data-feature-self type="checkbox" checked>Applica la cura a te stesso</label>':'')+
  (ability.mode==='heal_roll'?'<p>Tira 1d10 e aggiungi il livello da Guerriero. La cura si applica a te stesso.</p>':'')+
  (conversion?'<label>Livello slot<select data-feature-level>'+[1,2,3,4,5].map(n=>'<option>'+n+'</option>').join('')+'</select></label><label class="check"><input data-feature-create type="checkbox" checked>Crea uno slot (disattiva per convertire uno slot in punti)</label>':'')+
  (recovery?'<p>Massimo '+Math.ceil(Number((c.classes||[]).find(x=>String(x.name||'').toLowerCase()===String(ability.class_name||'').toLowerCase())?.level||c.level||0)/2)+' livelli di slot.</p>'+[1,2,3,4,5].map(n=>'<label>Slot di livello '+n+'<input data-feature-recover="'+n+'" type="number" min="0" max="'+Number(c.spell_slots_spent?.[n]||0)+'" value="0"></label>').join(''):'')+
  (enhanced?'<label class="check"><input data-feature-enhanced type="checkbox">Versione potenziata · 1 punto Focus</label>':'')+
  (ability.mode==='metamagic_roll'?'<p>Scegli i dadi da sostituire: devi utilizzare i nuovi risultati.</p>'+
   (ability.name==='Empowered Spell'?'<label>Numero di dadi<input data-feature-count type="number" min="1" max="'+Math.max(1,Number(calculated.values['ability_mod:cha'])||1)+'" required></label><label>Tipo di dado<select data-feature-sides>'+[4,6,8,10,12,20,100].map(n=>'<option value="'+n+'">d'+n+'</option>').join('')+'</select></label>':'<p>Ripeti 1d20 per il tiro per colpire fallito.</p>'):'')+
  (ability.mode==='context'?'<p>Conferma bersagli, condizioni e tiri indicati dal tratto. Il consumo sarà registrato alla conferma.</p>':'')+
  (itemGrant?'<label>Oggetto concesso<select data-feature-item-choice>'+itemGrant.items.map(item=>
    '<option value="'+esc(item.id)+'"'+(item.owned&&(!itemGrant.allow_duplicate_choices||itemGrant.max_owned&&item.owned>=itemGrant.max_owned)?' disabled':'')+'>'+esc(item.name)+(item.owned?' · posseduto ×'+item.owned:'')+'</option>').join('')+
    '</select></label>':'')+
  featureCompanionFields(companion)+
   '<p data-feature-result role="status"></p><div class="actions magic-dialog-actions"><button type="button" class="btn primary" data-feature-confirm>Conferma</button><button type="button" class="btn" data-feature-cancel>Annulla</button></div>';
 dialog.querySelectorAll('[data-feature-cancel],[data-act="feature-close"]').forEach(button=>button.addEventListener('click',event=>{event.stopPropagation();closeDialog(dialog,{remove:true});}));
 dialog.querySelector('[data-feature-confirm]').addEventListener('click',async event=>{
  if(event.currentTarget.disabled)return;
  const button=event.currentTarget;button.disabled=true;
  try{
   const current=state.editor?.read();if(current?.id!==dialog.dataset.creatureId)throw Error('La creatura è cambiata.');
   for(const input of dialog.querySelectorAll('[data-feature-amount],[data-feature-count]')){
     if(input.value.trim()===''||!input.checkValidity())throw Error('Inserisci un valore numerico valido.');
   }
   const fresh=await computeLocalData(current),options={amount:dialog.querySelector('[data-feature-amount]')?.value,
    level:dialog.querySelector('[data-feature-level]')?.value,create_slot:dialog.querySelector('[data-feature-create]')?.checked,
    apply_to_self:dialog.querySelector('[data-feature-self]')?.checked,enhanced:!!dialog.querySelector('[data-feature-enhanced]')?.checked,
    count:Number(dialog.querySelector('[data-feature-count]')?.value??1),sides:Number(dialog.querySelector('[data-feature-sides]')?.value||20),
    levels:[...dialog.querySelectorAll('[data-feature-recover]')].map(input=>Number(input.value)),
    tracker_id:abilityPaymentChoice(dialog)};
   if(ability.mode==='heal_roll')options.roll=randomDie(10);
   const liveCompanion=companion?await companionFeatureChoices(current,fresh,ability.origin_id):null;
    if(companion&&!liveCompanion)throw Error('Privilegio non più disponibile.');
    if(liveCompanion?.rule.activation==='resource'&&
       (!ability.tracker_id||options.tracker_id===''||Number(ability.cost)<1))
      throw Error('La capacità richiede una risorsa associata per evocare la creatura.');
    const changes=ability.mode==='trait_state'?
    selectionStateActivationPatch(current,fresh,ability.state_id,options):
    classAbilityActivationPatch(current,fresh,ability,options);
   if(itemGrant){
     const selected=dialog.querySelector('[data-feature-item-choice]')?.value;
     const itemChanges=claimFeatureItemPatch(current,fresh,itemGrant.id,selected,
       {activationActionId:ability.class_feature_id});
     Object.assign(changes,itemChanges);
   }
   const reroll=ability.mode==='metamagic_roll'?rollBattleDamage(ability.name==='Seeking Spell'?'1d20':options.count+'d'+options.sides,randomDie):null;
   await patch(changes);if(state.saveError)throw Error(state.saveError);
   await state.editor.flush();
    if(liveCompanion)await createFeatureCompanion(current,liveCompanion,dialog);
    dialog.dataset.confirmed='true';dialog.close();await render();
   if(onConfirmed)await onConfirmed({record:current,calculated:fresh,options,changes});
   if(reroll){state.roll={...reroll,label:ability.name,author:selectedName()};state.rollHistory.unshift({...state.roll});}
   message(reroll?ability.name+': '+reroll.notation+' → '+reroll.total+' · usa i nuovi risultati.':ability.mode==='heal_roll'?ability.name+': d10 '+options.roll+' · PF '+changes.current_hp:ability.name+' applicato.');
  }catch(error){button.disabled=false;dialog.querySelector('[data-feature-result]').textContent=errorMessage(error);}
 });
 dialog.addEventListener('close',()=>{
  if(dialog.dataset.confirmed!=='true'&&onClosed)onClosed();
  dialog.remove();
 },{once:true});document.body.append(dialog);
 openDialog(dialog);
}
// Fallback for a 2014 subclass ability whose tracker is modeled but its
// effects are not yet automated. The same dialog and atomic payment rules
// apply to every subclass, including variable-size resource pools.
async function activateSubclassTracker(c,calculated,trackerId,originId){
 const tracker=(calculated.trackers||[]).find(t=>t.id===trackerId&&!t.disabled);
 const linked=tracker&&resourceLinkedSubclassTrait(tracker,calculated.features||[],[],calculated);
 if(!linked||linked.origin_id!==originId||c.rules_version==='2024')
  throw Error('Capacità della sottoclasse non disponibile.');
 const available=Math.max(0,Number(tracker.max||0)-Number(tracker.spent||0));
 const companion=await companionFeatureChoices(c,calculated,originId);
  const minSlot=Number(companion?.rule?.alternative_slot_min||0);
  const paymentOptions=minSlot?[
    ...(available>0?[['tracker','Uso gratuito · '+tracker.name]]:[]),
    ...(calculated.spell_slots||[]).filter(row=>Number(row.level)>=minSlot&&Number(row.total)>Number(row.spent)).map(row=>['slot:'+row.level,'Slot di '+row.level+'° livello']),
    ...(calculated.pact_slots?.level>=minSlot&&calculated.pact_slots?.total>calculated.pact_slots?.spent?[['pact','Slot del Patto di '+calculated.pact_slots.level+'°']]:[])
  ]:[];
  if(available<1&&!paymentOptions.length)throw Error('Nessun utilizzo disponibile per '+linked.name+'.');
 const feature=(calculated.features||[]).find(f=>f.origin_id===originId);
 document.querySelector('#subclass-tracker-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='subclass-tracker-dialog';dialog.className='sheet-roll-dialog magic-spell-dialog';
 dialog.dataset.creatureId=c.id;
 dialog.innerHTML=actionDialogIntro(linked.name,[
  {label:'Origine',value:'Tratto · '+linked.name},
  {label:'Risorsa',value:tracker.name},
  {label:'Disponibili',value:available+' / '+tracker.max}
 ],feature?flattenDescription(feature):'',
 'Gli utilizzi verranno registrati. Gli effetti non ancora automatizzati vanno applicati manualmente.',
 'subclass-tracker-close')+
 (paymentOptions.length?'<label>Risorsa da utilizzare<select data-companion-payment>'+paymentOptions.map(([id,label])=>'<option value="'+esc(id)+'">'+esc(label)+'</option>').join('')+'</select></label>':
   available>1?'<label>Utilizzi da consumare<input type="number" data-subclass-amount min="1" max="'+
  esc(available)+'" step="1" required></label>':'')+
 featureCompanionFields(companion)+
  '<p data-subclass-result role="status"></p>'+
 '<div class="actions magic-dialog-actions"><button type="button" class="btn primary" data-subclass-confirm>Conferma utilizzo</button>'+
 '<button type="button" class="btn" data-subclass-cancel>Annulla</button></div>';
 dialog.querySelectorAll('[data-subclass-cancel],[data-act="subclass-tracker-close"]').forEach(button=>
  button.addEventListener('click',event=>{event.stopPropagation();closeDialog(dialog,{remove:true});}));
 dialog.querySelector('[data-subclass-confirm]').addEventListener('click',async event=>{
  const button=event.currentTarget;if(button.disabled)return;button.disabled=true;
  try{
   const current=state.editor?.read();
   if(!current||current.id!==dialog.dataset.creatureId)throw Error('La creatura è cambiata.');
   const amountInput=dialog.querySelector('[data-subclass-amount]');
   if(amountInput&&(amountInput.value.trim()===''||!amountInput.checkValidity()))
     throw Error('Inserisci un numero valido di utilizzi.');
   const raw=amountInput?.value??'1',amount=Number(raw);
   const fresh=await computeLocalData(current);
   const liveCompanion=companion?await companionFeatureChoices(current,fresh,originId):null;
   if(companion&&!liveCompanion)throw Error('Privilegio non più disponibile.');
   const pay=dialog.querySelector('[data-companion-payment]')?.value||'tracker';
   if(paymentOptions.length&&!paymentOptions.some(([id])=>id===pay))throw Error('Risorsa di evocazione non valida.');
   const changes=pay==='tracker'?subclassTrackerUsePatch(current,fresh,trackerId,originId,amount):pay==='pact'?slotUsePatch(current,0,1,fresh):pay.startsWith('slot:')?slotUsePatch(current,Number(pay.slice(5)),1,fresh):null;
   if(!changes)throw Error('Pagamento non consentito.');
   await patch(changes);
   if(state.saveError)throw Error(state.saveError);
   await state.editor.flush();
   if(liveCompanion)await createFeatureCompanion(current,liveCompanion,dialog);
   closeDialog(dialog,{remove:true});await render();
   message(linked.name+': '+(pay==='tracker'?amount+' utilizzo consumato.':'slot consumato.')+
    (liveCompanion?' Sottocreatura aggiornata.':' Effetti da gestire manualmente.'));
  }catch(error){
   button.disabled=false;
   dialog.querySelector('[data-subclass-result]').textContent=errorMessage(error);
  }
 });
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 document.body.append(dialog);openDialog(dialog);
}
// Uses the session's real token snapshot rather than the spell targeting
// command. Targeted abilities must select a recipient before paying any uses.
async function startTargetedAbility(c,ability,persistentKey,requested){
 if(!state.paired||!state.online)throw Error('Collega prima la partita al desktop.');
 const stored=await loadCreature(c.id);
 if(!stored)throw Error('Scheda locale non trovata.');
 state.map=await map();
 const caster=casterToken(stored.data,state.map,await ownerId());
 if(!caster)throw Error('Associa prima un token a questa creatura nella partita.');
 if(!tacticalViewer)tacticalViewer=new TacticalViewer({send:action,ownerId,notify:message});
 await tacticalViewer.open(String(caster.id));
 tacticalViewer.setAbilityTarget({
  name:ability.name,range_feet:Number(ability.target_range_feet||0),
  exclude_self:ability.exclude_self===true,
  onSelected:async selected=>{
   // The action confirmation remains editable, but the selected token is fixed.
   // Cancellation never spends a resource or creates any applied condition.
   await activateOtherAbility(c,ability,persistentKey,requested,selected);
  }
 });
}
// Area selection is client-side and non-destructive. The desktop remains the
// authority for LOS, position and saving throws; the PWA merely previews targets.
async function startAreaAbility(c,ability,persistentKey,requested){
 if(!state.paired||!state.online)return activateOtherAbility(c,ability,persistentKey,requested);
 const stored=await loadCreature(c.id);
 if(!stored)throw Error('Scheda locale non trovata.');
 state.map=await map();
 const caster=casterToken(stored.data,state.map,await ownerId());
 if(!caster)throw Error('Associa un token a questa creatura prima di selezionare l’area.');
 if(!tacticalViewer)tacticalViewer=new TacticalViewer({send:action,ownerId,notify:message});
 await tacticalViewer.open(String(caster.id));
 tacticalViewer.setAreaAbility({
  name:ability.name,shape:ability.area_shape,
  length_feet:Number(ability.area_length_feet||0),
  width_feet:Number(ability.area_width_feet||0),
  radius_feet:Number(ability.area_radius_feet||0),
  onSelected:async targets=>{
   await activateOtherAbility(c,ability,persistentKey,requested,{
    name:targets.length?targets.map(t=>t.name).join(', '):'Nessun bersaglio nell’area',
    affected_ids:targets.map(t=>t.id),affected:targets
   });
  }
 });
}
async function activateOtherAbility(c,ability,persistentKey,requested,selectedTarget=null){
 document.querySelector('#other-ability-dialog')?.remove();
 const dialog=document.createElement('dialog');dialog.id='other-ability-dialog';
 dialog.className='sheet-roll-dialog magic-spell-dialog';dialog.dataset.creatureId=c.id;
 const calculated=await computeLocalData(c);
 const companion=ability.companion_command?null:
   await companionFeatureChoices(c,calculated,ability.origin_id||ability.feature_id||'');
 const healPower=(calculated.racial_abilities||[]).find(power=>
   power.mode==='heal_dice'&&('activated:'+power.id===requested||power.id===ability.ability_id));
 const healRecipients=healPower&&!selectedTarget?(await listCreatures()).map(row=>row.creature||row)
   .filter(row=>row?.id):[];
 const shape=ability.area_shape==='line'?
   'Linea '+ability.area_length_feet+' × '+ability.area_width_feet+' ft':
   ability.area_shape==='cone'?'Cono '+ability.area_radius_feet+' ft':
   ability.area_shape==='circle'?'Raggio '+ability.area_radius_feet+' ft centrato su di te':'';
 const saveBase=ability.save_base||'con';
 const saveDC=8+Number(calculated.stats?.proficiency||2)+Number(calculated.abilities?.[saveBase]?.modifier||0);
 // Source-qualified feat save DCs inherit the actual choice made for the
 // granting spellcasting feat, never an unrelated global caster ability.
 const sourceAbility=power=>{
   const source=String(power?.save_ability_origin||'');
   if(!source)return power?.save_casting_ability||'con';
   const chosen=c.spellcasting_section_abilities?.['origin:'+source]||
     (c.origin_spell_grants||[]).find(row=>row.origin_id===source&&!row.disabled)?.spellcasting_ability||'';
   return ['int','wis','cha'].includes(chosen)?chosen:'';
 };
 const featAbility=sourceAbility(ability);
 const featDC=featAbility?8+Number(calculated.stats?.proficiency||2)+
   Number(calculated.abilities?.[featAbility]?.modifier||0):null;
 const saveStat={wis:'Saggezza',con:'Costituzione',int:'Intelligenza',cha:'Carisma',dex:'Destrezza',str:'Forza'};
 const targetedDetails=ability.mode==='targeted_save_damage'?
   '<div class="magic-ability-area"><dl class="magic-spell-facts">'+
   '<div class="magic-spell-fact"><dt>Danni extra</dt><dd>'+
     esc(ability.damage_formula||'—')+' '+esc(ability.damage_type||'')+'</dd></div>'+
   '<div class="magic-spell-fact"><dt>Tiro salvezza</dt><dd>'+
     esc(saveStat[ability.save_ability]||ability.save_ability||'')+' · CD '+esc(featDC??'da scegliere')+'</dd></div>'+
   '</dl>'+(featAbility?'':'<p class="hint">Seleziona prima la caratteristica da incantatore del talento che concede questa CD.</p>')+
   (selectedTarget&&ability.condition_on_failed_save?
     '<label class="check"><input type="checkbox" data-target-failed-save>Il bersaglio ha fallito il TS: applica '+esc(ability.effect_condition||'la condizione')+'</label>':
     '<p class="hint">Se non sei collegato alla partita, applica manualmente la condizione al bersaglio dopo un TS fallito.</p>')+
   '<p class="hint">Verifica che il bersaglio sia già stato danneggiato. Il tiro non deve essere stato effettuato nell’app. Un utilizzo per turno; rimuovi la condizione all’inizio del tuo turno successivo.</p></div>':'';
 const areaDetails=shape?'<div class="magic-ability-area"><dl class="magic-spell-facts">'+
   '<div class="magic-spell-fact"><dt>Area</dt><dd>'+esc(shape)+'</dd></div>'+
   '<div class="magic-spell-fact"><dt>Tiro salvezza</dt><dd>'+esc(saveStat[ability.save_ability]||ability.save_ability||'—')+' · CD '+esc(saveDC)+'</dd></div>'+
   (ability.damage_formula?'<div class="magic-spell-fact"><dt>Danni</dt><dd>'+
     esc(ability.damage_formula)+' '+esc(ability.damage_type)+'</dd></div>':'')+
   '</dl>'+(ability.mode==='choice_area'?'<label>Modalità del soffio<select data-dragonborn-breath-mode>'+
     (ability.options||[]).map(row=>'<option value="'+esc(row.id)+'">'+esc(row.name)+
       ' · TS '+esc((row.save_ability||'').toUpperCase())+'</option>').join('')+
     '</select></label>':'')+
   (ability.condition_on_failed_save&&ability.effect_condition?
      '<p class="hint">Scegli i bersagli che falliscono il TS e possono vederti o sentirti. La condizione dura '+
      esc(Number(ability.duration_rounds||0)>0?ability.duration_rounds+' round':'quanto indicato dal privilegio')+
      '; quando un bersaglio subisce danni può ripetere il TS. Gestisci manualmente la fine dell’effetto.</p>':'' )+
   '<p class="hint">Controlla i bersagli nell’area sulla mappa.</p></div>':'';
 dialog.innerHTML=actionDialogIntro(ability.name,[
  {label:'Azione',value:ability.time||'Secondo il privilegio'},
  {label:'Origine',value:ability.origin_name||ability.origin||'Tratto'},
  {label:'Attivazione',value:({bonus:'Azione bonus',action:'Azione',reaction:'Reazione',free:'Nessun costo'}[ability.time||ability.action_type||ability.activation_mode]||
   ability.time||ability.action_type||'Secondo il privilegio')},
  ...(selectedTarget?[{label:'Bersaglio',value:selectedTarget.name}]:[]),
  {label:'Consumo',value:Number(ability.cost)>0?ability.cost+' utilizzi':'Nessun consumo'}
 ],ability.description||'',
  ability.target_mode==='single_token'&&selectedTarget?
    'Bersaglio selezionato dalla mappa. Controlla gittata e requisiti della capacità prima di confermare.':
    ability.target_mode==='single_token'?'La partita non è collegata: scegli il bersaglio manualmente.':'',
  'other-ability-close')+
  abilityPaymentField(ability,calculated)+
  targetedDetails+areaDetails+
  (ability.condition_on_failed_save&&ability.area_shape&&selectedTarget?.affected_ids?.length?
    '<fieldset class="magic-ability-area"><legend>Bersagli che hanno fallito il tiro salvezza</legend>'+
    (selectedTarget.affected||selectedTarget.affected_ids.map(id=>({id,name:id}))).map(row=>
     '<label class="check"><input type="checkbox" data-area-failed-target="'+esc(row.id)+'">'+
       esc(row.name||row.id)+'</label>').join('')+'</fieldset>':'')+
  (healPower?(selectedTarget?
    '<p class="hint">Cura a contatto · '+esc(calculated.stats?.proficiency||0)+'d4. Il tiro viene effettuato alla conferma per il token selezionato.</p>':
    '<label>Creatura da curare<select data-heal-target>'+
       (healRecipients.length?healRecipients.map(row=>'<option value="'+esc(row.id)+'"'+
         (row.id===c.id?' selected':'')+'>'+esc(row.name||row.id)+'</option>').join(''):
         '<option value="'+esc(c.id)+'">Sé stesso</option>')+
     '</select></label><p class="hint">Cura a contatto: verifica che il destinatario sia entro 5 ft.</p>'):'')+
  featureCompanionFields(companion)+
  '<p data-ability-result role="status"></p>'+
  '<div class="actions magic-dialog-actions"><button type="button" class="btn primary" data-ability-confirm>Conferma</button>'+
  '<button type="button" class="btn" data-ability-cancel>Annulla</button></div>';
 dialog.querySelectorAll('[data-ability-cancel],[data-act="other-ability-close"]').forEach(button=>
  button.addEventListener('click',()=>closeDialog(dialog,{remove:true})));
 dialog.querySelector('[data-ability-confirm]').addEventListener('click',async event=>{
  const button=event.currentTarget;if(button.disabled)return;button.disabled=true;
  try{
   const current=state.editor?.read();
   if(!current||current.id!==dialog.dataset.creatureId)throw Error('La creatura è cambiata.');
   const fresh=await computeLocalData(current);
   const panels=battleActionPanels(fresh.companion_view||current,fresh,state.spellCatalog||[],state.featureActionOverrides||[],
    state.generalActionSupplements||[],readActionVariants(),
    abilitiesForCreature(current,state.abilityCatalog||[],fresh));
   const power=requested.startsWith('activated:')?
    abilitiesForCreature(current,state.abilityCatalog||[],fresh)
     .find(row=>String(row.id)===requested.slice('activated:'.length)):null;
   const currentAbility=panels.abilityEntries.find(row=>
     String(row.id||row.ability_id||row.name)===requested)||
    (power?{...power,cost:power.resource_cost??(power.tracker_id?1:0)}:null);
   if(!currentAbility)throw Error('Capacità non più disponibile.');
   if(currentAbility.infusion_action){
     const liveId=requested.startsWith('activated:')?requested.slice('activated:'.length):requested;
     const active=abilitiesForCreature(current,state.abilityCatalog||[],fresh)
       .find(row=>row.infusion_action&&row.id===liveId);
     if(!active||active.tracker_id!==currentAbility.tracker_id||
        Number(active.resource_cost)!==Number(currentAbility.cost??currentAbility.resource_cost??0))
       throw Error('La capacità dell’oggetto non è più disponibile.');
   }
   const liveCompanion=companion?await companionFeatureChoices(current,fresh,
     currentAbility.origin_id||currentAbility.feature_id||''):null;
   if(companion&&!liveCompanion)throw Error('Privilegio non più disponibile.');
   if(currentAbility.target_mode==='single_token'&&state.paired&&state.online){
     if(!selectedTarget?.id)throw Error('Seleziona un bersaglio sulla mappa prima di usare la capacità.');
     const currentMap=await map();
     if(!(currentMap.tokens||[]).some(token=>String(token.id)===String(selectedTarget.id)))
       throw Error('Il bersaglio selezionato non è più sulla mappa.');
     if(currentAbility.exclude_self&&String(selectedTarget.id)===String(casterToken(current,currentMap,await ownerId())?.id||''))
       throw Error('Questa capacità richiede una creatura diversa da te.');
   }
   const minimumCost=Number(liveCompanion?.rule.tracker_cost||1);
   if(liveCompanion?.rule.activation==='resource'&&
      (!currentAbility.tracker_id||Number(currentAbility.cost)<minimumCost))
      throw Error('La capacità richiede un tracker con il costo previsto dal privilegio.');
   const cost=liveCompanion?.rule.activation==='resource'?minimumCost:
     Math.max(0,Number(currentAbility.cost)||0),choice=abilityPaymentChoice(dialog);
   if(liveCompanion?.rule.activation==='resource'&&choice==='')
     throw Error('Questo privilegio richiede il consumo della risorsa associata.');
   if(choice!==undefined&&choice!==''&&choice!==currentAbility.tracker_id)
    throw Error('Tracker non collegato alla capacità.');
   const spend=choice===undefined||choice!=='';
   if(currentAbility.infusion_action&&cost>0&&(!spend||choice!==currentAbility.tracker_id))
     throw Error('La capacità richiede una carica del suo oggetto.');
   const mode=currentAbility.mode||'';
   const mandatory=['save_area','choice_area','temporary_defense','temporary_flight','temporary_condition','targeted_save_damage','tracked_action'].includes(mode);
   if(mandatory&&(!spend||choice!==currentAbility.tracker_id||cost!==1))
     throw Error('La capacità richiede un utilizzo del tracker associato.');
   const selectedMode=mode==='choice_area'?(currentAbility.options||[]).find(row=>
     row.id===dialog.querySelector('[data-dragonborn-breath-mode]')?.value):null;
   if(mode==='targeted_save_damage'&&!sourceAbility(currentAbility))
     throw Error('Scegli la caratteristica da incantatore di Scion of the Outer Planes prima di usare la capacità.');
   if(mode==='choice_area'&&!selectedMode)throw Error('Seleziona un soffio valido.');
   if(healPower?.mode==='heal_dice'){
     if(!spend||choice!==healPower.tracker_id)
       throw Error('Healing Hands richiede un utilizzo del tracker.');
     const candidates=(await listCreatures()).map(row=>row.creature||row).filter(row=>row?.id);
     const owned=selectedTarget?candidates.find(row=>
       String(row.linked_token_sync_id||'')===String(selectedTarget.id)||row.id===selectedTarget.id):
       candidates.find(row=>row.id===dialog.querySelector('[data-heal-target]')?.value);
     const targetId=owned?.id||(selectedTarget?null:current.id);
     const self=targetId===current.id;
     const healed=healingHandsPatch(current,fresh,healPower,randomDie,self?'self':null);
     await patch(healed.patch);
     let applied=self;
     if(targetId&&!self){
       try{
         const editor=await openCreatureEditor(targetId);
         const recipient=editor.read(),recipientStats=await computeLocalData(recipient);
         await editor.update({current_hp:Math.min(Math.max(0,Number(recipientStats.stats?.max_hp)||0),
           Math.max(0,Number(recipient.current_hp)||0)+healed.total)});
         applied=true;
       }catch(error){console.warn('Cura al destinatario non sincronizzata',error);}
     }
     closeDialog(dialog,{remove:true});await render();
     message(healPower.name+': '+healed.notation+' → '+healed.dice.join(' + ')+
       ' = '+healed.total+' PF. '+(applied?'PF aggiornati.':
         'Applica la cura al bersaglio sul desktop.'));return;
   }
   await patch(record=>{
    const changes=cost&&spend?spendTrackerUses(record,currentAbility.tracker_id,cost,fresh.trackers):{};
    if(spend)Object.assign(changes,racialAbilityTemporaryHpPatch(record,currentAbility,fresh));
    if(persistentKey){
     if(record.active_class_features?.[persistentKey])throw Error('Capacità già attiva.');
     changes.active_class_features={...(record.active_class_features||{}),
      [persistentKey]:{name:currentAbility.name,origin_id:currentAbility.persistent_origin_id||currentAbility.origin_id||currentAbility.feature_id||requested,
       rules_version:record.rules_version||'2014',enhanced:false,
       duration_rounds:Math.max(0,Number(currentAbility.duration_rounds)||0),
       damage_type:currentAbility.damage_type||'',
       ...(currentAbility.effect_condition?{
         effect_condition:currentAbility.effect_condition,
         added_condition:!((record.conditions||[]).some(value=>String(value).toLowerCase()===String(currentAbility.effect_condition).toLowerCase())),
         ends_on:currentAbility.ends_on||[]}: {})}};
     if(currentAbility.effect_condition){
       const existing=Array.isArray(record.conditions)?record.conditions:[];
       changes.conditions=existing.some(value=>String(value).toLowerCase()===String(currentAbility.effect_condition).toLowerCase())?
         existing:[...existing,currentAbility.effect_condition];
     }
    }
    return changes;
   });
   if(state.saveError)throw Error(state.saveError);
   await state.editor.flush();
   if(liveCompanion)await createFeatureCompanion(current,liveCompanion,dialog);
   const applyFailedSave=mode==='targeted_save_damage'&&
     dialog.querySelector('[data-target-failed-save]')?.checked===true;
   const areaFailedIds=mode==='save_area'&&currentAbility.condition_on_failed_save?
     [...dialog.querySelectorAll('[data-area-failed-target]:checked')].map(row=>row.dataset.areaFailedTarget)
       .filter(id=>selectedTarget?.affected_ids?.includes(id)):[];
   let conditionApplied=false,conditionFailure='';
   if(applyFailedSave&&selectedTarget?.id){
     try{
       const applied=await action('set_condition',{
         token_id:String(selectedTarget.id),condition_id:currentAbility.effect_condition,enabled:true});
       if(!applied?.ok)throw Error(applied?.error||'Condizione non applicata.');
       conditionApplied=true;
       state.map=await map();
     }catch(error){conditionFailure=errorMessage(error);}
   }
   let areaConditionApplied=0,areaConditionFailure='';
   if(areaFailedIds.length&&state.paired&&state.online){
     const latest=await map();
     for(const id of areaFailedIds){
       try{
         if(!(latest.tokens||[]).some(token=>String(token.id)===String(id)))
           throw Error('Bersaglio non più presente in partita.');
         const applied=await action('set_condition',{
           token_id:String(id),condition_id:currentAbility.effect_condition,enabled:true});
         if(!applied?.ok)throw Error(applied?.error||'Condizione non applicata.');
         areaConditionApplied++;
       }catch(error){areaConditionFailure=errorMessage(error);}
     }
     state.map=await map();
   }
   closeDialog(dialog,{remove:true});await render();
   const effectFormula=racialAbilityEffectFormula(currentAbility,fresh);
   const featureTarget=effectFormula?featureRollTarget(currentAbility):'';
   // Feature rolls are no longer thrown invisibly as part of activation: after
   // spending the reaction/use, open the shared popup so other owned traits
   // can contribute dice specifically to this feature's stable roll ID.
   const effectRoll=effectFormula&&!featureTarget?rollBattleDamage(effectFormula,randomDie):null;
   if(effectRoll){
     state.roll={...effectRoll,label:(currentAbility.roll_effect?.label||'Tiro capacità')+' · '+currentAbility.name,author:selectedName()};
     state.rollHistory.unshift({...state.roll});
   }
   const damage=['save_area','targeted_save_damage'].includes(mode)&&currentAbility.damage_formula?
     rollBattleDamage(currentAbility.damage_formula,randomDie):null;
   if(damage){
     state.roll={...damage,label:'Danni · '+currentAbility.name,author:selectedName()};
     state.rollHistory.unshift({...state.roll});
   }
   message(currentAbility.name+': '+(cost?'utilizzo registrato.':'effetto consultato.')+
     (effectRoll?' '+(currentAbility.roll_effect?.label||'Tiro')+': '+effectRoll.notation+' = '+(currentAbility.roll_effect?.label==='Riduzione danni'?Math.max(0,effectRoll.total):effectRoll.total)+'.':'')+
     (currentAbility.temp_hp?' PF temporanei aggiornati (non cumulabili).':'')+
     (damage?' Danni extra '+damage.notation+' = '+damage.total+' '+currentAbility.damage_type+'.':'')+
     (mode==='targeted_save_damage'?' TS '+(saveStat[currentAbility.save_ability]||currentAbility.save_ability)+
       ' CD '+(8+Number(fresh.stats?.proficiency||2)+Number(fresh.abilities?.[sourceAbility(currentAbility)]?.modifier||0))+'.'+
       (conditionApplied?' Condizione '+currentAbility.effect_condition+' applicata al token; rimuovila all’inizio del tuo prossimo turno.':
        conditionFailure?' Impossibile applicare la condizione: '+conditionFailure:
        ' Nessuna condizione applicata (TS riuscito o da gestire manualmente).'):'')+
     (mode==='save_area'?' TS '+(saveStat[currentAbility.save_ability]||currentAbility.save_ability||'—')+
       ' CD '+(8+Number(fresh.stats?.proficiency||2)+Number(fresh.abilities?.[currentAbility.save_base||'con']?.modifier||0))+
       (currentAbility.half_on_save?' (metà danni con TS riuscito).':'.')+
       (areaConditionApplied?' Spaventato applicato a '+areaConditionApplied+' bersagli.':'')+
       (areaConditionFailure?' Condizioni non completamente applicate: '+areaConditionFailure: currentAbility.condition_on_failed_save&&!areaConditionApplied?' Applica manualmente Spaventato ai bersagli che hanno fallito.':''):'')+
     (selectedMode?' '+selectedMode.name+' · TS '+selectedMode.save_ability.toUpperCase()+
       ' CD '+(8+Number(fresh.stats?.proficiency||2)+Number(fresh.abilities?.con?.modifier||0))+' · '+selectedMode.description:'')+
     (shape?' Effetti da applicare ai bersagli nell’area.':'')+
     (persistentKey?(currentAbility.duration_rounds===1?' Condizione attiva fino al prossimo turno o a un attacco, tiro danni o TS imposto.':' Effetto attivo per massimo 1 minuto; termina da Condizioni.') :''));
   if(featureTarget){
     const live=state.editor?.read();
     if(live?.id===current.id)openFeatureRollDialog(live,await computeLocalData(live),currentAbility,effectFormula);
   }
  }catch(error){button.disabled=false;dialog.querySelector('[data-ability-result]').textContent=errorMessage(error);}
 });
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 document.body.append(dialog);openDialog(dialog);
}
async function syncFormPresentation(c){
 if(c.linked_token_sync_id&&state.paired&&state.online){
  const result=await action('set_appearance',{token_id:c.linked_token_sync_id,owner_id:await ownerId(),
   miniature_id:c.current_miniature_id||c.default_miniature_id||'',display_name:c.name,size_name:c.size_name,footprint:c.footprint});
  if(!result.ok)throw Error(result.error||'Forma non applicata sul desktop.');
 }
}
async function applyFormPatch(c,changes){
 const proposed=resolveVariant(applyVariantEdit(state.editor.readBase(),changes));
 await syncFormPresentation(proposed);
 try{await patch(changes,{syncPresentation:false});await state.editor.flush();}
 catch(error){try{await syncFormPresentation(c);}catch{}throw error;}
}
function promptVariantOverflow(creatureId,formId,overflow){
 document.querySelector('#form-depleted-dialog')?.remove();
 const dialog=document.createElement('dialog');dialog.className='sheet-roll-dialog';dialog.id='form-depleted-dialog';
 dialog.innerHTML='<header class="vtt-popup-heading"><h2>Punti ferita della variante esauriti</h2>'+dialogCloseButton('form-keep-close','Chiudi','')+'</header><p>Restano '+esc(overflow)+' danni in eccesso. Applicarli alla scheda base e tornare alla forma base?</p><div class="actions"><button type="button" class="btn primary" data-form-restore>Applica danni e torna alla base</button><button type="button" class="btn" data-form-keep>Resta nella variante</button></div>';
 dialog.querySelectorAll('[data-form-keep],[data-act="form-keep-close"]').forEach(button=>button.addEventListener('click',event=>{event.stopPropagation();closeDialog(dialog,{remove:true});}));
 dialog.querySelector('[data-form-restore]').addEventListener('click',async event=>{
  const button=event.currentTarget;button.disabled=true;
  try{
   const current=state.editor?.readBase();
   if(current?.id!==creatureId||current.current_form_id!==formId||resolveVariant(current).current_hp>0)throw Error('La forma attuale è cambiata.');
   const proposed=revertVariantDamage(current,overflow);
   // First switch within one editor update; base HP are then edited while the
   // base is active. One transaction stores both decisions atomically.
   await state.editor.replaceBase(proposed);await state.editor.flush();await syncFormPresentation(state.editor.read());
   dialog.close();await render();
  }catch(error){button.disabled=false;message(errorMessage(error),true);}
 });
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});document.body.append(dialog);
 openDialog(dialog);
}
let inventoryCatalogRequest=null;
function ensureInventorySearchCatalog(){
  if(state.referenceCatalogs.items||inventoryCatalogRequest||state.inventorySearchCatalogError)return;
  inventoryCatalogRequest=catalogEntries('items').then(rows=>{
    state.referenceCatalogs.items=rows;
    paintInventorySearchResults();
    app.querySelector('#benefit-option-dialog [data-benefit-target-search]')?.dispatchEvent(new Event('input'));
  }).catch(error=>{
    state.inventorySearchCatalogError=errorMessage(error);
    paintInventorySearchResults();
  }).finally(()=>{inventoryCatalogRequest=null;});
}
function paintInventorySearchResults(){
  const area=app.querySelector('#inventory-search-results');
  if(!area||state.sheet!=='inventory'||!state.editor)return;
  const query=state.sheetSearch.get(state.creatureId+'|inventory')||'';
  if(!query.trim()){
    area.hidden=true;area.innerHTML='';
    state.inventorySearchMatches=[];
    return;
  }
  const c=state.editor.read();
  // Keep catalog indexes stable so tapping a result still opens that entry.
  const options=(state.referenceCatalogs.items||[]).map(row=>
    isContentAvailableForRules(row,c.rules_version)?row:null);
  const results=inventorySearchResults(c.inventory||[],
    options,query,state.inventorySearchLimit);
  state.inventorySearchMatches=results;
  area.hidden=false;
  area.innerHTML=(results.length?results.map((row,i)=>
    '<button type="button" class="inventory-search-result" data-act="inventory-search-result" data-search-result-index="'+i+
    '" aria-label="'+esc(row.kind==='owned'?row.quantity+' copie possedute di '+row.name:'Aggiungi '+row.name)+'">'+
    '<span class="inventory-search-result-count'+(row.kind==='catalog'?' is-add':'')+
    '" aria-hidden="true">'+(row.kind==='owned'?'×'+row.quantity:'+')+'</span>'+
    '<span class="inventory-search-result-copy"><strong>'+esc(row.name)+'</strong>'+
    (row.source?'<small>'+esc(row.source)+'</small>':'')+'</span>'+
    '<span class="inventory-search-result-chevron" aria-hidden="true">›</span></button>').join(''):
    '<p class="inventory-search-notice">Nessun oggetto corrispondente.</p>')+
    (results.length===state.inventorySearchLimit?
      '<button type="button" class="inventory-search-more" data-act="inventory-search-more">Mostra altri risultati</button>':'')+
    (!state.referenceCatalogs.items?
      '<p class="inventory-search-notice">'+
      (state.inventorySearchCatalogError?
        'Catalogo non disponibile. La ricerca negli oggetti posseduti resta attiva. '+
        '<button type="button" data-act="inventory-search-retry">Riprova</button>':
        'Caricamento del catalogo in corso…')+'</p>':'');
}
function openInventorySearchAddDialog(catalogIndex){
  const entry=state.referenceCatalogs.items?.[catalogIndex],creature=state.editor?.read();
  if(!entry||!creature||!entry.name||!isContentAvailableForRules(entry,creature.rules_version))throw Error('Oggetto del catalogo non disponibile per queste regole.');
  app.querySelector('#inventory-search-add-dialog')?.remove();
  const options=inventoryContainers(creature).map(row=>
    '<option value="'+esc(row.id)+'">'+esc(row.name)+'</option>').join('');
  const dialog=document.createElement('dialog');
  dialog.id='inventory-search-add-dialog';
  dialog.className='sheet-context-dialog inventory-search-add-dialog';
  dialog.dataset.catalogIndex=String(catalogIndex);
  dialog.innerHTML='<header class="sheet-context-head"><h2>Aggiungi '+esc(entry.name)+'</h2>'+
    dialogCloseButton('inventory-search-add-close','Chiudi','play-button')+'</header>'+
    '<div class="sheet-context-body inventory-search-add-fields">'+
    '<label>Sezione<select id="inventory-search-add-section">'+options+'</select></label>'+
    '<label>Quantità<input type="number" id="inventory-search-add-quantity" value="1" min="1" max="99999" step="1" required></label></div>'+
    '<footer class="pending-choice-actions"><button type="button" data-act="inventory-search-add-close">Annulla</button>'+
    '<button type="button" data-act="inventory-search-add-confirm">Aggiungi oggetto</button></footer>';
  dialog.addEventListener('close',()=>dialog.remove(),{once:true});
  app.append(dialog);
  openDialog(dialog);
}

const monsterDetailAttempts=new Set();
function loadMissingMonsterDetails(editor){
 const creature=editor.read(),stat=creature.stat_block||{};
 if(creature.kind!=='monster'||!stat.name||!stat.source||
  (!state.online&&!state.hostReachable)||stat.fluff&&(!stat.legendaryGroup||Number(stat.vtt_lair_details_version)>=2))return;
 const key=[creature.id,stat.name,stat.source].join('|');
 if(monsterDetailAttempts.has(key))return;
 monsterDetailAttempts.add(key);
 fetch('/catalog/bestiary/'+encodeURIComponent(stat.name)+'/'+encodeURIComponent(stat.source)+'.json')
  .then(response=>response.ok?response.json():null).then(async detail=>{
   if(!detail)return;
   const delta=monsterDetailPatch(editor.read(),detail);
   if(!Object.keys(delta).length)return;
   await editor.update(current=>monsterDetailPatch(current,detail));
   if(state.editor===editor)await render();
  }).catch(()=>{}); // Optional lore never blocks the local sheet or offline archive.
}
async function editorView() {
  const creatureId=state.creatureId;
  if(!state.editor){
    const editor=await sheetLoadingDeadline(openCreatureEditor(creatureId),7000,"dell'archivio locale");
    if(state.creatureId!==creatureId||state.libraryMode)return '';
    state.editor=editor;
  }
  if(state.sheet==='origins')state.sheet='info';
  const c = state.editor.read();
  loadMissingMonsterDetails(state.editor);
  // The persistent header owns creature identity and tab navigation.
  let body = "";
  // Start local calculation, descriptive references and spell lists together.
  // A slow optional request must not keep the main screen on the old archive.
  const pendingCalculation=computeLocalData(c),optionalTasks=[];
  if(state.sheet==='info'){
    optionalTasks.push(Promise.all(
      ["races","classes","subclasses","backgrounds","feats"].map(async key=>{
        if(state.referenceCatalogs[key])return;
        const request=catalogEntries(key).then(rows=>{
          state.referenceCatalogs[key]=rows;return rows;
        });
        try{await sheetLoadingDeadline(request,1600,"del catalogo "+key);}
        catch(error){
          if(error.code==='SHEET_LOADING_TIMEOUT')
            refreshSheetAfterLateLoad(request,creatureId,'info');
        }
      })
    ));
  }
  if(state.sheet==="battle"){
    optionalTasks.push((async()=>{
      const request=Promise.allSettled([loadFeatureActionOverrides(),loadGeneralActionSupplements()]);
      let results;
      try{results=await sheetLoadingDeadline(request,2200,"delle azioni di battaglia");}
      catch(error){
        results=[{status:'rejected',reason:error},{status:'rejected',reason:error}];
        if(error.code==='SHEET_LOADING_TIMEOUT')
          refreshSheetAfterLateLoad(request,creatureId,'battle');
      }
      const [featureRules,generalRules]=results;
      state.featureActionOverrides=featureRules.status==='fulfilled'?featureRules.value:[];
      state.generalActionSupplements=generalRules.status==='fulfilled'?generalRules.value:[];
      state.actionCatalogError=generalRules.status==='rejected'?
        'Le azioni opzionali non sono state caricate: '+errorMessage(generalRules.reason):'';
    })());
  }
  if((state.sheet==="magic"||state.sheet==="battle")&&!state.abilityCatalog){
    optionalTasks.push((async()=>{
      const request=loadActivatedAbilities().then(rows=>{state.abilityCatalog=rows;return rows;});
      try{await sheetLoadingDeadline(request,2200,"delle capacità");}
      catch(error){
        state.abilityCatalog=[];
        if(error.code==='SHEET_LOADING_TIMEOUT')
          refreshSheetAfterLateLoad(request,creatureId,state.sheet);
      }
    })());
  }
  await Promise.all(optionalTasks);
  const calculated=await pendingCalculation;
  if(state.creatureId!==creatureId||state.libraryMode)return '';
  if(state.sheet==='info'){
    // Class and race references load concurrently with numeric rules.
    // Resolve pending lineage choices only after both are available.
    const rules=await loadRuleCatalogs().catch(()=>({}));
    calculated.pending_choices=pendingCharacterChoices(c,calculated,{...rules,
      races:state.referenceCatalogs.races||[],subclasses:state.referenceCatalogs.subclasses||[]});
  }
  state.calculated=calculated;
  if(['battle','magic','conditions','info'].includes(state.sheet)||
      state.sheet==='inventory'&&inventoryVisibleSections(c).includes('scrolls')){
    const visibleRequest=ensureVisibleSpells(c,calculated);
    if(visibleRequest)refreshWhenSpellsArrive(visibleRequest,creatureId,state.sheet);
  }
  if(state.sheet==='inventory'&&inventoryVisibleSections(c).includes('scrolls'))
    requireFullSpellsForPicker();
  if(state.sheet==='magic'&&state.magicPopup){
    if(['choices','learn'].includes(state.magicPopup))
      requireFullSpellsForPicker();
  }
  let featDetails;
  if(state.sheet==='info'){
    const feats=Array.isArray(c.feats_catalog)?c.feats_catalog:[];
    const request=Promise.all(feats.map(async feat=>{
      const name=typeof feat==='string'?feat:feat?.name||'';
      const source=typeof feat==='string'?'':feat?.source||'';
      const match=(state.referenceCatalogs.feats||[]).find(row=>row.name?.toLowerCase()===name.toLowerCase()&&
        (!source||row.source?.toLowerCase()===source.toLowerCase()));
      try{return {description:flattenDescription(await detailedEntry('feats',match||{name,source}))};}
      catch{return {description:''};}
    }));
    try{featDetails=await sheetLoadingDeadline(request,1600,"delle descrizioni dei talenti");}
    catch(error){
      featDetails=[];
      if(error.code==='SHEET_LOADING_TIMEOUT')
        refreshSheetAfterLateLoad(request,creatureId,'info');
    }
  }
  // Resolve selected optional powers through the very same detailed
  // compendium source used by the trait and feature viewers.
  let battleOptionalTraits=[];
  if(state.sheet==='battle'&&(c.optional_features_catalog||[]).length){
    if(!state.referenceCatalogs.optional_features){
      const request=catalogEntries('optional_features').then(rows=>{
        state.referenceCatalogs.optional_features=rows;return rows;
      });
      try{await sheetLoadingDeadline(request,1800,"dei privilegi opzionali");}
      catch(error){
        if(error.code==='SHEET_LOADING_TIMEOUT')
          refreshSheetAfterLateLoad(request,creatureId,'battle');
      }
    }
    const request=Promise.all((c.optional_features_catalog||[]).map(async feature=>{
      const name=String(feature?.name||feature||''),source=String(feature?.source||'');
      const reference=(state.referenceCatalogs.optional_features||[]).find(row=>
        String(row.name||'').toLowerCase()===name.toLowerCase()&&
        (!source||String(row.source||'').toLowerCase()===source.toLowerCase()));
      let detail=reference||feature;
      if(reference)try{detail=await detailedEntry('optional_features',reference);}catch{}
      return {name,origin_id:feature?.origin_id||'',origin_key:feature?.origin_name||source,
        feature_key:'',description:flattenDescription(detail)||flattenDescription(feature)};
    }));
    try{battleOptionalTraits=await sheetLoadingDeadline(request,1800,"delle capacità opzionali");}
    catch(error){
      if(error.code==='SHEET_LOADING_TIMEOUT')
        refreshSheetAfterLateLoad(request,creatureId,'battle');
    }
  }
  state.battleOptionalTraits=battleOptionalTraits;
  const displayRecord=calculated.companion_view||c;
  body=nativeSection(displayRecord,state.sheet,{field,area,panel,resources:resourceView(c,false,state.sheet==='battle'),resourcesEditor:resourceView(c,true),equipment:inventoryEquipmentView(c,calculated),armor:'',attacks:attacksView(calculated,state.sheet==='battle'),details:state.detail,catalogs:{...state.referenceCatalogs,featDetails,origins:calculated.origins,trackers:calculated.trackers,attacks:calculated.attacks,calculated,spells:state.spellCatalog||[]},calculated})||"";
  if(state.sheet==="info"){
    const request=traitsView(displayRecord);
    try{body+=await sheetLoadingDeadline(request,2500,"dei tratti");}
    catch(error){
      if(error.code!=='SHEET_LOADING_TIMEOUT')throw error;
      body+=panel('Tratti','<p class="hint">I riferimenti stanno ancora caricando. Puoi usare la scheda nel frattempo.</p>');
      refreshSheetAfterLateLoad(request,creatureId,'info');
    }
  }
  switch(state.sheet){
  case "inventory": {
    // Catalog rows arrive independently: drawing the inventory must never wait
    // for a large catalog download (or for an unavailable offline resource).
    ensureInventorySearchCatalog();
    const inventory=Array.isArray(c.inventory)?c.inventory:[];
    const containers=inventoryContainers(c),selectedTabs=setInventoryVisibleSections(c,state.inventorySelectedTabs);
    const nav=inventorySectionControls(c,selectedTabs);
    const owned=inventory.map((item,index)=>({item,index})).filter(({item})=>!isDocument(item));
    const ordinary=owned.filter(({item})=>!isSpellScroll(item));
    const scrolls=owned.filter(({item})=>isSpellScroll(item));
    const attunements=owned.filter(({item})=>requiresAttunement(item));
    const selectedOrdinary=ordinary.filter(({item})=>
      selectedTabs.includes('container:'+itemContainerId(item,containers))||
      itemContainerId(item,containers)===DEFAULT_INVENTORY_CONTAINER&&selectedTabs.includes('items'));
    const visibleRows=[...selectedOrdinary,...(selectedTabs.includes('scrolls')?scrolls:[])];
    let selected=visibleRows.find(({index})=>index===state.inventorySelectedIndex);
    if(!selected){selected=visibleRows[0];state.inventorySelectedIndex=selected?.index??-1;}
    let resolvedDetail=selected?.item||{};
    if(selected&&isCatalogItem(selected.item)){
      if(!state.referenceCatalogs.items){
        const request=catalogEntries("items").then(rows=>{state.referenceCatalogs.items=rows;return rows;});
        try{await sheetLoadingDeadline(request,2500,"degli oggetti");}
        catch(error){
          if(error.code==='SHEET_LOADING_TIMEOUT')
            refreshSheetAfterLateLoad(request,creatureId,'inventory');
        }
      }
      const source=(state.referenceCatalogs.items||[]).find(row=>
        String(row.id||"")===String(selected.item.id||""));
      if(source){
        const request=detailedEntry("items",source);
        let detail;
        try{detail=await sheetLoadingDeadline(request,2000,"dei dettagli dell'oggetto");}
        catch(error){
          if(error.code==='SHEET_LOADING_TIMEOUT')
            refreshSheetAfterLateLoad(request,creatureId,'inventory');
        }
        if(detail)resolvedDetail={...detail,...selected.item,
          entries:detail.entries??selected.item.entries,
          description:detail.description??selected.item.description};
      }
    }
    const description=selected?panel("Descrizione · "+ownedItemDisplayName(selected.item),
      inventoryItemDescription(resolvedDetail,selected.index),"inventory-native-panel inventory-description-panel"):"";
    const showingItems=selectedTabs.some(key=>key==='items'||key.startsWith('container:'));
    body=nav+
      (showingItems?inventoryEquipmentView(c,calculated)+
        inventoryAttunementView(c,attunements)+
        inventoryCoinsView(c)+
        selectedTabs.filter(key=>key==='items'||key.startsWith('container:')).map(key=>
          inventoryContainerSections(c,ordinary,containers,state.inventorySelectedIndex,state.inventoryMenuIndex,key)).join(''):'')+
      (selectedTabs.includes('scrolls')?
        panel("Pergamene possedute",
          inventoryTable(scrolls,true,state.inventorySelectedIndex,state.inventoryMenuIndex),
          "inventory-native-panel inventory-scroll-panel")+
        panel("Nuova pergamena",scrollSpellCreatorView(),"inventory-native-panel inventory-scroll-create"):'');
    if(selectedTabs.includes('documents')){
      const documents=inventory.map((item,index)=>({item,index})).filter(({item})=>isDocument(item));
      const request=Promise.all(documents.map(({item})=>getRecord("global","homebrew",String(item.id||""))));
      let definitions;
      try{definitions=await sheetLoadingDeadline(request,3500,"dei documenti");}
      catch(error){
        definitions=documents.map(()=>null);
        if(error.code==='SHEET_LOADING_TIMEOUT')
          refreshSheetAfterLateLoad(request,creatureId,'inventory');
      }
      body+=panel("Documenti",
        (documents.length?documents.map(({item,index},i)=>documentRow(item,index,definitions[i])).join(""):
          '<p class="hint">Nessun documento.</p>')+
        '<div class="actions">'+btn("document-add","＋ Nuovo documento","primary")+'</div>',
        "inventory-native-panel inventory-documents-panel");
    }
    body+=description;
    break;
  }
  case "battle":
    // Keep native Poteri tracker panels available as contextual editors,
    // including the abilities relocated from Poteri into battle resources.
    body+='<div class="battle-power-archive" hidden>'+
      originPowersView(c,calculated,abilitiesForCreature(c,state.abilityCatalog||[],calculated),true)+'</div>';
    break;
  case "magic":
    body=magicOverview(c,calculated)+
      panel("Incantesimi disponibili",
        calculated.casting_classes.map(member=>{
          return '<section class="magic-source"><header class="magic-source-header">'+
            '<div class="magic-source-title"><h3>'+esc(member.name)+'</h3>'+
            castingStatisticsToggle(c,member.id)+
            (member.source?'<span class="hint">'+esc(member.source)+'</span>':'')+'</div>'+
            '<div class="magic-source-resources" aria-label="Risorse di lancio">'+magicSlotUsageChip()+
            (member.mode==='Preparati'?'<span class="magic-source-resource magic-selection-rest" title="Puoi riselezionare gli incantesimi dopo un riposo lungo"><span class="magic-source-resource-label">Riposo lungo</span></span>':'')+
            (member.mode==='Conosciuti'?(()=>{const trigger=calculated.power_selections?.find(row=>row.id==='class_spellcasting:'+member.id)?.layers.learned?.change_label;return trigger?'<span class="magic-source-resource magic-selection-rest" title="Quando cambiare gli incantesimi conosciuti"><span class="magic-source-resource-label">'+esc(trigger)+'</span></span>':'';})():'')+
            '</div></header>'+
            (castingStatisticsVisible(c,member.id)?castingStatistics(c,member.id,member.ability):'')+
            '<div class="magic-source-controls">'+
            (member.mode==='Preparati'?
              '<button type="button" class="btn small magic-selection-button" data-act="magic-select-spells" data-magic-class="'+esc(member.id)+'" data-magic-target="prepared_spells">Prepara incantesimi</button>':'')+
            '<button type="button" class="btn small magic-selection-button" data-act="magic-learn-select" data-magic-class="'+esc(member.id)+'">'+
              (member.selection_layers?.learned?.mode==='class_list'?
                'Gestisci incantesimi conosciuti':'Impara / Dimentica incantesimi')+'</button>'+
            '</div>'+
            spellList(c,'prepared_spells',member.id,calculated.casting_classes,{includeSlots:false})+'</section>';
        }).join('')+
        originPowersView(c,calculated)+
        manualMagicSources(c,calculated),
        'magic-panel')+
      optionBenefitPanels(c,calculated)+
       racialRestTrainingPanel(c,calculated)+
      magicToolsDialog(c,calculated);
    break;
  case "conditions":
    body=panel('Condizioni',
      '<div class="condition-sheet-header"><span class="condition-count"><strong data-condition-count>'+
        ((c.conditions||[]).filter(id=>id!=='exhaustion').length+(exhaustionLevel(c)>0?1:0))+
        '</strong> attive</span></div>'+
        conditionGrid(c.conditions,'data-condition',c.rules_version,exhaustionLevel(c)),
      'condition-sheet-panel');
    break;
  case "json":
    body = panel("Editor avanzato",'<p class="warning">Modifica JSON per campi non ancora presenti nella GUI. La scheda viene validata prima del salvataggio; ID e proprietario non possono cambiare.</p>'+
      '<label>Documento completo<textarea id="json-editor" rows="18" spellcheck="false" class="inline-code">'+
        esc(JSON.stringify(c,null,2))+'</textarea></label><div class="actions">'+
      btn("save-json","Salva modifiche JSON","primary")+'</div>');
    break;
  }
  return header(['info','json'].includes(state.sheet)?'Il personaggio':'Durante la sessione',...(SECTION_COPY[state.sheet]||['Scheda','']))+
    '<div data-local-sheet-calculations>'+body+(state.sheet==='info'?'':calculationNote(calculated,calculated.loadError))+'</div><p id="save-state" class="save-status'+(state.saveError?' error':'')+'" role="status" aria-live="polite">'+esc(state.saveError||'✓ Salvato sul dispositivo')+'</p><details class="archive-tools"><summary>Opzioni della scheda</summary><div class="actions">'+btn("export","Esporta JSON")+btn("send","Manda")+
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
     '<button type="button" class="btn small battle-resource-link" data-act="'+(t.item_bound?'tracker-item':'tracker-powers')+'" '+
       (t.item_bound?'data-item-index="'+esc(t.inventory_index)+'" ':'data-tracker-id="'+esc(t.id)+'" ')+
       'aria-label="Apri '+esc(t.name)+(t.item_bound?' in Inventario':' in Poteri')+'" title="Vai a '+(t.item_bound?'Inventario':'Poteri')+'">↗</button>'+
     '<details class="battle-resource-details"><summary aria-label="Origine e recupero di '+esc(t.name)+'" title="Origine e recupero">ⓘ</summary>'+
       '<span>'+esc(t.origin_name||'Senza origine')+' · '+
       esc(t.recharge_note||modes.find(([id])=>id===t.recharge)?.[1]||t.recharge||'Manuale')+'</span></details></div>';
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
  return '<article class="list-item"><div class="row between"><strong>'+esc(t.name)+'</strong><button type="button" class="btn small" data-act="'+(t.item_bound?'tracker-item':'tracker-powers')+'"'+
       (t.item_bound?' data-item-index="'+esc(t.inventory_index)+'"':'')+
       ' title="Apri in '+(t.item_bound?'Inventario':'Poteri')+'">↗ '+(t.item_bound?'Inventario':'Poteri')+
       '</button></div><p class="hint">'+esc(t.origin_name||'Senza origine')+' · '+
       esc(t.recharge_note||modes.find(([id])=>id===t.recharge)?.[1]||t.recharge||'Manuale')+'</p>'+(t.inactive?'<p class="hint">Non attivo: origine disattivata o requisito non soddisfatto. Utilizzi salvati: '+esc(used)+'</p>':'<div class="row">Disponibili: '+esc(Math.max(0,maximum-used))+' / '+formulaReadout(state.calculated,'tracker:'+t.id,'Massimo '+t.name)+'</div>')+actions+optionalButton+edit+'</article>';
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

function conditionGrid(active,attribute,edition="2014",exhaustion=0){
 const sheet=attribute==='data-condition';
 const applied=new Set(Array.isArray(active)?active:[]);
 const nativeOptions=conditionOptions(state.conditionCatalog,edition,active);
 const source=nativeOptions.find(row=>row.id==='exhaustion');
 // Numeric exhaustion becomes one selected virtual condition; session token
 // condition editors retain their existing native condition identifiers.
 const options=sheet?[
   ...nativeOptions.filter(row=>row.id!=='exhaustion'&&!/^exhaustion:[1-6]$/.test(row.id)),
   ...exhaustionConditionRows(edition,source)
 ]:nativeOptions;
 if(sheet&&exhaustion>0)applied.add('exhaustion:'+exhaustion);
 const knownCategories=[
   ...CONDITION_CATEGORIES.map(([category,title])=>({category,title})),
   ...(sheet?[{category:EXHAUSTION_CONDITION_CATEGORY,title:'Indebolimento'}]:[])
 ];
 const unknown=[...new Set(options.map(row=>row.category))]
   .filter(category=>!knownCategories.some(group=>group.category===category))
   .map(category=>({category,title:category}));
 return '<div class="condition-category-list" aria-label="Stati e afflizioni">'+
  [...knownCategories,...unknown].map(({category,title})=>{
   const rows=options.filter(row=>row.category===category);
   if(!rows.length)return "";
   const expanded=category==="conditions"||rows.some(row=>applied.has(row.id));
   return '<details class="condition-category" data-condition-category="'+esc(category)+'" '+(expanded?'open':'')+'>'+
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
        '<option value="-1"'+(index<0&&(!c['hand_'+slot+'_special']||['none','unarmed'].includes(c['hand_'+slot+'_special']))?' selected':'')+'>'+(slot==='body'?'Naturale':'Nessuno')+'</option>'+
        (slot!=='body'?[['improvised','Arma improvvisata']].map(([id,name])=>'<option value="'+id+'" '+(index<0&&c['hand_'+slot+'_special']===id?'selected':'')+'>'+name+'</option>').join(''):'')+
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
 const originalRows=withGrantedSpellPreviews(await collectTraitRows(c,state.calculated||{},
  {entries,detail:detailedEntry,isDocument,conditionLabel,
   conditionCatalog:state.conditionCatalog,spells:state.spellCatalog||[]}),
  state.calculated?.origin_spells||[],state.spellCatalog||[]);
 const benefitProjection={...(state.calculated||{}),
  activatable_abilities:abilitiesForCreature(c,state.abilityCatalog||[],state.calculated||{},
   {includeUnavailable:true})};
 const {rows,byKey:benefitsByTrait}=distributeTraitBenefits(originalRows,c,benefitProjection);
 const groups=groupTraitRows(rows);
 if(state.creatureId===c.id&&!state.libraryMode&&state.sheet==='info'){
   state.traitRows=rows;
   state.traitBenefitGroupsByKey=benefitsByTrait;
 }
 const renderCard=trait=>{
  const itemQuantity=trait.item_requires_attunement?trait.item_active_quantity:trait.item_quantity;
  const description=flattenDescription({entries:trait.entries});
  const benefitCount=(benefitsByTrait.get(trait.key)||[])
    .reduce((total,group)=>total+group.items.length,0);
  const active=!trait.inactive;
  const subtraits=pendingChoicesModule.permanentSubtraitsForTrait?.(trait,c,state.calculated?.pending_choices||[])||[];
  let nested=subtraits.length?'<div class="trait-subtraits" aria-label="Sotto-tratti e scelte permanenti">'+subtraits.map(sub=>
   '<button type="button" class="trait-subtrait trait-subtrait--depth-'+Math.min(2,sub.depth)+'" data-act="pending-choice-open"'+
    ' data-choice-id="'+esc(sub.choice_id)+'"'+(active?'':' disabled')+'>'+
    '<span class="trait-subtrait-mark" aria-hidden="true">└</span><span class="trait-subtrait-copy"><span class="trait-subtrait-title">'+esc(sub.title)+'</span>'+ 
    '<small>'+esc(sub.selection)+'</small></span><span class="trait-subtrait-chevron" aria-hidden="true">›</span></button>').join('')+'</div>':'';
  // Panoramica retains general origin benefits in the same editable popup.
  const selectionBenefits=(state.calculated?.power_selections||[]).filter(model=>
    [trait.feature_origin,trait.extension_choice_origin].filter(Boolean).includes(model.origin_id));
  const benefitChoices=selectionBenefits.map(model=>model.benefit_type==='object_extension'?
   '<button type="button" class="trait-subtrait" data-act="benefit-option-open" data-power-selection-id="'+esc(model.id)+'" data-power-option-id="'+esc(model.options[0].id)+'">Scegli oggetto · '+esc(model.title)+'</button>':
   model.benefit_type==='option_selection'?'<button type="button" class="trait-subtrait" data-act="power-selection-open" data-power-selection-id="'+esc(model.id)+'" data-power-stage="'+(model.layers.learned?'learned':'applied')+'">Scelte · '+esc(model.title)+'</button>':'').join('');
  nested+=benefitChoices;
  const benefitButton='<button type="button" class="trait-benefits-trigger" data-act="trait-benefits-open" data-trait-key="'+esc(trait.key)+'" aria-label="Gestisci benefici di '+esc(trait.name)+'" title="Gestisci benefici">'+
   (benefitCount?actionGlyph('proficiency'):'<span aria-hidden="true">＋</span>')+'</button>';
  return '<div class="trait-row'+(active?'':' trait-row--inactive')+'" data-trait-enabled="'+String(active)+'">'+benefitButton+
    '<details class="trait-card'+(active?'':' trait-inactive')+'" data-trait-key="'+esc(trait.key)+'" data-trait-origin="'+esc(trait.origin_key)+'" data-trait-feature="'+esc(trait.feature_origin||'')+'" data-trait-proficiency="'+esc(trait.proficiency_origin||'')+'">'+
    '<summary><span class="trait-title">'+esc(/^Descrizione · /.test(trait.name)?'Panoramica':trait.name)+'</span>'+
      (trait.category==='oggetti'&&trait.rank===0&&(trait.item_requires_attunement||itemQuantity>1)?
        '<span class="trait-item-quantity" aria-label="'+(trait.item_requires_attunement?'Sintonie attive ':'Quantità ')+itemQuantity+'">×'+itemQuantity+'</span>':'')+
      '<span class="trait-chevron" aria-hidden="true"><svg viewBox="0 0 24 16" width="22" height="15" fill="none"><path d="M3 6 L12 11 L21 6" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg></span></summary>'+
    '<div class="trait-content">'+
      (trait.description_html?'<div class="trait-description trait-state-description">'+trait.description_html+'</div>':
       description?'<p class="trait-description">'+esc(description)+'</p>':'')+
      (trait.source?'<span class="trait-book">'+esc(trait.source)+'</span>':'')+
    '</div></details>'+nested+'</div>';
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
 // Confirmation is scoped to one explicit deletion request, never a refresh.
 state.traitPopupConfirm='';
 const benefitProjection={...(state.calculated||{}),
  activatable_abilities:abilitiesForCreature(record,state.abilityCatalog||[],state.calculated||{},
   {includeUnavailable:true})};
 const groups=state.traitBenefitGroupsByKey?.get(trait.key)||
  distributeTraitBenefits(state.traitRows,record,benefitProjection).byKey.get(trait.key)||[];
 const isOwnedItem=trait.category==='oggetti'&&trait.rank===0&&
   String(trait.origin_key||'').startsWith('item:');
 const ownedCopies=isOwnedItem?(Array.isArray(trait.item_inventory_indices)&&
   trait.item_inventory_indices.length?trait.item_inventory_indices.map(index=>record.inventory?.[index]).filter(Boolean):
   (record.inventory||[]).filter(item=>String(item.id||'')===
     String(trait.item_id||String(trait.origin_key).slice(5)))):[];
 const passiveItem=isOwnedItem&&ownedCopies.length>0&&ownedCopies.every(item=>
   !['weapon','shield','armor'].includes(itemKind(item)));
 const attunedItem=isOwnedItem&&trait.item_requires_attunement;
 const itemQuantity=isOwnedItem?(attunedItem?trait.item_active_quantity:
   Math.max(1,ownedCopies.reduce((total,item)=>total+Math.max(0,Number(item.quantity??1)||0),0))):1;
 const hidden=[...new Set([...traitRemovedIds(record,trait),
  ...(/^Descrizione · /.test(trait.name)?
   (record.trait_benefit_removed?.['origin-benefits:'+trait.key]||[]):[])])];
 const ownedChoices=choicesForTrait(trait,record,state.calculated?.pending_choices||[]);
 const optionList=(options,selected='')=>options.map(([value,label])=>
  '<option value="'+esc(value)+'"'+(String(value)===String(selected)?' selected':'')+'>'+esc(label)+'</option>').join('');
 const formSelect=(label,name,options)=>'<label>'+esc(label)+'<select name="'+name+'">'+optionList(options)+'</select></label>';
 const formInput=(label,name,placeholder='',type='text')=>'<label>'+esc(label)+'<input name="'+name+'" type="'+type+'" placeholder="'+esc(placeholder)+'" required></label>';
 const kinds=BENEFIT_TYPES,draftKind=state.traitPopupDraftKind||'bonus',draftTarget=state.traitPopupDraftTarget||'';
 const featureRollOptions=(benefitProjection.activatable_abilities||[])
   .filter(row=>featureRollTarget(row)).map(row=>[featureRollTarget(row),'Tiro capacità · '+row.name]);
 const featureRollSeen=new Set();
 const featureRollTargets=featureRollOptions.filter(([id])=>{
   if(featureRollSeen.has(id))return false;featureRollSeen.add(id);return true;
 });
 const targets=[...BONUS_TARGETS,...featureRollTargets,['attack_roll','Tiro per colpire'],['damage_roll','Tiri di danno'],['any_d20','Qualunque d20']];
 const diceTargets=[['ability_check','Prove di caratteristica'],['saving_throw','Tiri salvezza'],['attack_roll','Tiri per colpire'],['damage_roll','Tiri di danno'],['initiative','Iniziativa'],['any_d20','Qualunque d20']];
 for(const choices of [targets,diceTargets])if(draftTarget&&!choices.some(([id])=>id===draftTarget))
   choices.unshift([draftTarget,'Questo tiro · '+draftTarget]);
 const trackerOptions=[['','Nessuno'],...(state.calculated?.trackers||[]).map(t=>[t.id,t.name])];
 const fields=[
  ['base_override',formSelect('Valore da sostituire','target',[
      ...['str','dex','con','int','wis','cha'].map(key=>['ability:'+key,'Punteggio · '+abilities[key]]),
      ['ac_unarmored','Classe armatura senza armatura'],
      ['attack_damage_base:unarmed','Danno base · Colpo senz’armi'],
      ...(state.calculated?.attacks||[]).filter(attack=>!String(attack.id||'').startsWith('unarmed'))
        .map(attack=>['attack_damage_base:'+attack.id,'Danno base · '+attack.name])
    ]).replace('name="target"','name="target" data-base-override-target')+
    formSelect('Operazione','mode',[
      ['replace','Sostituisce il valore base'],
      ['minimum','Impone un valore minimo'],
      ['alternative','Offre una formula alternativa']
    ]).replace('name="mode"','name="mode" data-base-override-mode')+
    formInput('Valore o formula','expression','Es. 19, 13 + dex_mod, 1d4')+
    '<p class="hint">Danno: sostituisce il dado base. Caratteristiche: usa valore minimo per oggetti come i guanti della forza. CA alternativa: vale solo senza armatura; lo scudo resta applicabile.</p>'],
  ['attack_count',formInput('Numero totale di attacchi con Azione','attacks_per_action','Es. 2','number')],
  ['bonus',formSelect('Tiro o valore','target',targets).replace('name="target"','name="target" data-trait-target')+
     formInput('Bonus (numero, formula o dadi)','expression','Es. +2, proficiency, 1d4')+
     '<details class="trait-bonus-extra"><summary>Opzioni per dadi nei tiri</summary>'+
     formSelect('Tipo di danno (facoltativo)','damage_type',[['','Nessuno'],...DAMAGE_TYPES.map(id=>[id,rollDamageName(id)])])+
     formSelect('Tracker associato','tracker_id',trackerOptions)+
     formInput('Utilizzi consumati','tracker_cost','1','number')+'</details>'],
  ['roll_mode',formSelect('Modalità','mode',[['advantage','Vantaggio'],['disadvantage','Svantaggio']])+
     formSelect('Tipo di tiro','target',[
      ['ability_check','Prove di caratteristica (incl. iniziativa)'],['saving_throw','Tiri salvezza'],
      ['attack_roll','Tiri per colpire'],['spell_attack','Attacchi magici'],
      ['any_d20','Qualunque tiro d20'],['initiative','Iniziativa'],
      ...targets.filter(([id])=>/^(ability_check:|skill:|save:|attack_hit:|casting_hit:)/.test(id))
     ]).replace('name="target"','name="target" data-trait-target')],
  ['d20_reroll',formSelect('Tiro d20','target',[
    ['any_d20','Qualunque d20'],['ability_check','Prove di caratteristica e abilità'],
    ['saving_throw','Tiri salvezza'],['attack_roll','Tiri per colpire'],
    ['spell_attack','Attacchi con incantesimi'],['initiative','Iniziativa'],
    ...targets.filter(([id])=>/^(ability_check:|skill:|save:|attack_hit:|casting_hit:)/.test(id))
   ])+formSelect('Condizione','trigger',[
    ['after_roll','Dopo il tiro'],['on_one','Solo se un d20 ha mostrato 1']
   ])+formSelect('Tracker (facoltativo)','tracker_id',trackerOptions)+
     formInput('Costo in utilizzi','tracker_cost','1','number')],
  ['proficiency',formSelect('Categoria','proficiency_kind',PROFICIENCY_KINDS)+formInput('Competenza','key','Es. perception, firearms, elvish')],
   ['senses',formSelect('Senso','sense_type',SENSE_OPTIONS)+formInput('Portata (ft)','range_feet','Es. 60','number')],
  ['defenses',formSelect('Difesa','rank',DEFENSE_RANKS)+formSelect('Danno o condizione','key',
    [...DAMAGE_TYPES.map(key=>[key,key]),...['blinded','charmed','deafened','frightened','grappled','paralyzed','petrified','poisoned','prone','restrained','stunned','unconscious'].map(key=>[key,key])])],
  ['resources',formInput('Nome risorsa','name')+formInput('Utilizzi massimi','max','Es. 3','number')+
    formSelect('Recupero','recharge',[['manual','Manuale'],['short_rest','Riposo breve'],['long_rest','Riposo lungo'],['turn','Inizio turno'],['d6','Ricarica d6']])],
  ['spells',formSelect('Incantesimo','spell_id',(state.spellCatalog||[]).filter(row=>row.id&&!row.internal_grant)
     .map(row=>[row.id,row.name+' · '+(row.source||'')]))+
     formSelect('Consumo','payment_mode',[['free','Gratuito'],['slot','Slot'],['tracker','Tracker']])+
     formSelect('Tracker','tracker_id',trackerOptions)+
     formSelect('Slot come alternativa','slot_alternative',[['false','No'],['true','Sì, oltre al tracker']])+
     formSelect('Caratteristica da incantatore','spellcasting_ability',[['','Da scegliere'],...Object.entries(abilities)])+
     '<label>Caratteristiche consentite (selezione, facoltativa)<input name="spellcasting_ability_options" placeholder="Es. int,wis,cha"></label>'],
  ['actions',formInput('Azione concessa','name')+
     formSelect('Tipo di azione','action_type',[['action','Azione'],['bonus','Azione bonus'],['reaction','Reazione'],['free','Nessun costo']])],
  ['effect_extensions',formSelect('Effetto modificato','target_kind',EXTENSION_TARGETS).replace('name="target_kind"','name="target_kind" data-extension-target-kind')+
     '<div data-extension-target-spell>'+
       formInput('Nome incantesimo o capacità','target_name','Es. Eldritch Blast, Bardic Inspiration')+
       '<label>ID del bersaglio (facoltativo)<input name="target_id" list="trait-feature-roll-ids" placeholder="ID del catalogo"></label>'+
       '<datalist id="trait-feature-roll-ids">'+featureRollOptions.map(([id,label])=>
         '<option value="'+esc(id.slice('feature_roll:'.length))+'" label="'+esc(label)+'"></option>').join('')+'</datalist></div>'+
     '<div data-extension-target-item hidden>'+
       formSelect('Copia dell’oggetto','target_item_index',(record.inventory||[])
         .map((item,index)=>[index,(item.name||item.id||'Oggetto')+' · copia '+(index+1)]))+
       '<p class="hint">La modifica viene legata a questa copia, non a tutti gli oggetti con lo stesso nome.</p></div>'+
     formSelect('Estensione','operation',EXTENSION_OPERATIONS)+
     '<label>Valore / formula (dove richiesto)<input name="value" placeholder="Es. 300, 10, cha_mod, 1d6"></label>'+
     formSelect('Momento di applicazione','trigger',EXTENSION_TRIGGERS)+
     formSelect('Frequenza','frequency',EXTENSION_FREQUENCIES)+
     '<label>Dettagli (facoltativi)<input name="description" placeholder="Effetti e condizioni specifiche"></label>']
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
      monsterActionOptionsMarkup({id:'trait:'+trait.key+':'+item.label,options:item.options})+
      (item.requirements?'<p class="trait-capability-requirements"><strong>Requisiti</strong> · '+esc(item.requirements)+'</p>':'')+
      (item.effects?.length?'<ul class="trait-capability-effects">'+item.effects.map(effect=>'<li>'+esc(effect)+'</li>').join('')+'</ul>':'')+
    '</article>':
    '<div class="trait-benefit-manage-row">'+
     '<div class="trait-benefit-entry"><span>'+esc(item.label)+'</span>'+
      (item.value?'<span class="trait-benefit-value">'+esc(sheetRollSymbol(item.value))+'</span>':'')+'</div>'+
     (group.type==='items'?'<button type="button" class="btn small" data-act="trait-feature-item-grant" data-grant-id="'+esc(item.grant_id)+'" data-item-id="'+esc(item.option_id)+'"'+(!item.available?' disabled':'')+'>'+ (!item.available?(item.owned?'Posseduto':'Limite raggiunto'):item.requires_activation?'Usa capacità':'Aggiungi')+'</button>':'')+
     (!trait.readonly&&!['items','attacks','armor_class','effects','granted_features'].includes(group.type)&&(group.type!=='roll_modes'||item.id.startsWith('roll_mode:trait:'))&&item.id?'<button type="button" class="trait-benefit-remove" data-act="trait-benefits-remove-request" data-benefit-id="'+esc(item.id)+'" data-benefit-type="'+esc(group.type)+'" aria-label="Elimina '+esc(item.label)+'" title="Elimina beneficio">×</button>':'')+
    '</div>').join('')+
   '</section>').join('');
 // Expose each structured choice only inside the popup of its granting trait.
 const skillNames=Object.fromEntries(SKILLS.map(([id,name])=>[id,name]));
 const chosenNames=key=>abilities[key]||skillNames[key]||
   (state.spellCatalog||[]).find(row=>row.id===key)?.name||key;
 const choiceBenefits=ownedChoices.length?
   '<section class="trait-benefit-group trait-benefit-group--choices">'+
   '<span class="trait-benefit-kind">Scelte dei benefici</span>'+
   ownedChoices.map(choice=>
     '<div class="trait-choice-row"><div class="trait-choice-copy"><strong>'+esc(choice.label)+'</strong>'+
     '<small>'+esc(choice.selected.length?choice.selected.map(chosenNames).join(' · '):
       'Nessuna opzione selezionata')+'</small>'+
     '<span class="trait-choice-count'+(choice.remaining?' trait-choice-count--pending':'')+'">'+
     esc(choice.selected.length)+' / '+esc(choice.count)+(choice.remaining?' · Da completare':' · Completa')+
     '</span></div><button type="button" data-act="pending-choice-open" data-choice-id="'+esc(choice.id)+'"'+
     ' aria-label="'+esc((choice.remaining?'Scegli ':'Modifica ')+choice.label)+'">'+
     (choice.remaining?'Scegli':'Modifica')+'</button></div>').join('')+'</section>':'';
 const dialog=document.createElement('dialog');
 dialog.id='trait-benefits-dialog';dialog.className='trait-benefits-dialog';
 dialog.dataset.traitKey=trait.key;
 dialog.setAttribute('aria-labelledby','trait-benefits-title');
 dialog.innerHTML='<header class="trait-benefits-dialog-head">'+
  '<h2 id="trait-benefits-title">Benefici · '+esc(trait.name)+
   (attunedItem||itemQuantity>1?'<span class="trait-item-quantity">×'+itemQuantity+'</span>':'')+'</h2>'+
  dialogCloseButton('trait-benefits-close','Chiudi','trait-benefits-close')+'</header>'+
  '<div class="trait-benefits-dialog-body">'+
   (passiveItem?'<div class="trait-activation-control trait-automatic-item">'+
     '<div class="trait-activation-copy"><span class="trait-activation-heading">Benefici automatici</span>'+
      '<span class="trait-activation-description">'+(attunedItem?
       (itemQuantity?'Benefici applicati a '+itemQuantity+' copie in sintonia':'Nessuna copia in sintonia'):
       'Attivi per ogni copia posseduta'+(itemQuantity>1?' · ×'+itemQuantity:''))+'</span></div></div>':
   '<div class="trait-activation-control" data-trait-activation>'+
    '<div class="trait-activation-copy"><span class="trait-activation-heading">'+(trait.readonly?'Stato attivo':'Stato del privilegio')+'</span>'+
     '<span class="trait-activation-description">'+(trait.inactive?'Benefici disattivati':'Benefici attivi')+'</span></div>'+
    '<button type="button" class="trait-activation-toggle" role="switch" aria-checked="'+String(!trait.inactive)+'" data-act="'+(trait.readonly?'trait-state-end':'trait-benefits-toggle')+'" aria-label="'+(trait.readonly?'Termina':trait.inactive?'Attiva':'Disattiva')+' '+esc(trait.name)+'">'+
     '<span class="trait-activation-thumb" aria-hidden="true"></span><span class="trait-activation-label">'+(trait.readonly?'Termina':trait.inactive?'Attiva':'Disattiva')+'</span></button>'+
   '</div>')+
   '<div class="trait-benefits">'+(benefits+choiceBenefits||'<p class="hint">Nessun beneficio concesso da questo tratto.</p>')+'</div>'+
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
 // Do not let a mode inappropriate for the selected target be saved.
 const baseTarget=dialog.querySelector('[data-base-override-target]');
 const baseMode=dialog.querySelector('[data-base-override-mode]');
 if(baseTarget&&baseMode){
   const sync=()=>{
     const target=baseTarget.value;
     const requiredMode=target==='ac_unarmored'?'alternative':
       target.startsWith('attack_damage_base:')?'replace':'';
     for(const option of baseMode.options)option.disabled=Boolean(requiredMode)&&option.value!==requiredMode||
       !requiredMode&&option.value==='alternative';
     if(baseMode.selectedOptions[0]?.disabled)baseMode.value=requiredMode||'replace';
   };
   baseTarget.addEventListener('change',sync);sync();
 }
 const extensionKind=dialog.querySelector('[data-extension-target-kind]');
 if(extensionKind){
   const syncTarget=()=>{
     const item=extensionKind.value==='item';
     dialog.querySelector('[data-extension-target-spell]').hidden=item;
     dialog.querySelector('[data-extension-target-item]').hidden=!item;
     const name=dialog.querySelector('[data-extension-target-spell] [name="target_name"]');
     if(name)name.required=!item;
   };
   extensionKind.addEventListener('change',syncTarget);syncTarget();
 }
 const trackerCost=dialog.querySelector('[data-trait-fields="bonus"] [name="tracker_cost"]');
 if(trackerCost)trackerCost.value='1';
 dialog.addEventListener('cancel',event=>{event.preventDefault();dismissTraitBenefitDialog();});
 dialog.addEventListener('click',event=>{
  if(event.target!==dialog)return;
  const rect=dialog.getBoundingClientRect();
  if(event.clientX<rect.left||event.clientX>rect.right||
     event.clientY<rect.top||event.clientY>rect.bottom)dismissTraitBenefitDialog();
 });
 openDialog(dialog);
}
// Removal confirmation is a local modal interaction, not a sheet render.
// Otherwise rebuilding the sheet can resurrect an old prompt or retarget a tap.
function setTraitBenefitRemovalConfirmation(item=null){
 const dialog=app.querySelector('#trait-benefits-dialog[open]');
 if(!dialog||dialog.dataset.traitKey!==state.traitPopupKey)return;
 dialog.querySelector('.trait-benefit-confirm')?.remove();
 state.traitPopupConfirm=item?.id||'';
 if(!item)return;
 const section=document.createElement('section');
 section.className='trait-benefit-confirm';
 section.setAttribute('role','alert');
 section.innerHTML='<p>Eliminare '+esc(item.label)+(item.value?' · '+esc(item.value):'')+'?</p>'+
   '<div class="actions"><button type="button" class="btn danger" data-act="trait-benefits-remove-confirm" data-benefit-id="'+esc(item.id)+'" data-benefit-type="'+esc(item.type)+'">Conferma eliminazione</button>'+
   '<button type="button" class="btn" data-act="trait-benefits-remove-cancel">Annulla</button></div>';
 dialog.querySelector('.trait-benefits')?.after(section);
 section.scrollIntoView?.({block:'nearest'});
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
// Exclusive, data-defined equipment models share the infusion card layout.
// The state catalog supplies both choices, their eligibility and effects.

function racialRestTrainingPanel(c,calculated){
 return (calculated.racial_rest_choices||[]).map(choice=>{
  if(choice.kind==='racial_option'){
   const key=c.trait_state_selection?.[choice.group]||'';
   return panel(choice.label||choice.trait,
    '<div class="infusion-overview"><strong>Stagione attuale</strong>'+
      '<span class="power-selection-rest">'+esc(selectionRestLabel(choice.recovery))+'</span></div>'+
    '<div class="infusion-dialog-item"><strong>'+esc(choice.option_labels?.[key]||'Da scegliere')+'</strong></div>'+
    '<div class="actions"><button type="button" class="btn primary" data-act="racial-option-open" data-racial-option-group="'+esc(choice.group)+'">'+
      (key?'Cambia stagione':'Scegli stagione')+'</button></div>',
    'armor-model-panel');
  }
  const selected=(c.proficiency_choices||[]).filter(row=>row.rest_training_group===choice.group);
  const entries=(choice.picks||[]).map((pick,i)=>{
   const row=selected[i],value=row?(row.kind==='skill'?'Abilità':row.kind==='weapon'?'Arma':'Strumento')+
     ' · '+row.key:'Da scegliere';
   return '<div class="infusion-dialog-item"><span>'+esc(pick.label||'Competenza')+
     '<small>'+esc(value)+'</small></span></div>';
  }).join('');
  return panel(choice.trait,
    '<div class="infusion-overview"><strong>Competenze temporanee</strong>'+
      '<span class="power-selection-rest">'+esc(selectionRestLabel(choice.recovery))+'</span></div>'+
    entries+'<div class="actions"><button type="button" class="btn primary" data-act="rest-training-open" data-training-group="'+esc(choice.group)+'">'+
    (selected.length?'Cambia competenze':'Scegli competenze')+'</button></div>',
    'armor-model-panel');
 }).join('');
}
async function openRacialRestTrainingDialog(group){
 const creature=state.editor?.read();
 if(!creature)throw Error('Apri prima una creatura.');
 const calculated=await computeLocalData(creature);
 const choice=(calculated.racial_rest_choices||[]).find(row=>row.group===group&&row.kind==='training');
 if(!choice)throw Error('Privilegio non disponibile.');
 const selected=(creature.proficiency_choices||[]).filter(row=>row.rest_training_group===group);
 const opt=(key,label,value)=>'<option value="'+esc(key)+'"'+(key===value?' selected':'')+'>'+esc(label)+'</option>';
 const skills=SKILLS.map(([key,label])=>['skill:'+key,label]);
 const weapons=trainingProficiencyOptions('weapon',creature).map(key=>['weapon:'+key,key]);
 const tools=trainingProficiencyOptions('tool',creature).map(key=>['tool:'+key,key]);
 const picks=(choice.picks||[]).map((pick,i)=>{
   const current=selected[i]?selected[i].kind+':'+selected[i].key:'';
   const groups=(pick.kinds||[]).map(kind=>{
     const options=kind==='skill'?skills:kind==='weapon'?weapons:tools;
     const label=kind==='skill'?'Abilità':kind==='weapon'?'Armi':'Strumenti';
     return '<optgroup label="'+label+'">'+options.map(([id,name])=>opt(id,name,current)).join('')+'</optgroup>';
   }).join('');
   return '<label>'+esc(pick.label||'Competenza')+
     '<select data-rest-training-pick="'+i+'">'+opt('','Scegli',current)+groups+'</select></label>';
 }).join('');
 app.querySelector('#racial-rest-training-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='racial-rest-training-dialog';
 dialog.className='sheet-roll-dialog magic-spell-dialog armor-model-dialog';
 dialog.dataset.trainingGroup=group;dialog.dataset.creatureId=creature.id;
 dialog.innerHTML=actionDialogIntro(choice.trait,[
   {label:'Cambio',value:selectionRestLabel(choice.recovery)},
   {label:'Origine',value:'Tratto · '+choice.trait},
   {label:'Durata',value:'Fino al prossimo riposo lungo'}
 ],choice.description||'','Specie · '+creature.species,'rest-training-close')+
 '<div class="magic-ability-detail">'+picks+'</div>'+
 '<p class="hint" data-rest-training-error role="status" hidden></p>'+
 '<div class="actions magic-dialog-actions"><button type="button" class="btn primary" data-act="rest-training-apply">Applica competenze</button>'+
 '<button type="button" class="btn" data-act="rest-training-close">Chiudi</button></div>';
 app.append(dialog);dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 openDialog(dialog);
}

const selectedPowerId=row=>typeof row==='string'?row:String(row?.id||'');
const selectedPowerLabel=(option,selection)=>{
 const label=option?.name||selectedPowerId(selection);
 const details=Array.isArray(selection?.subchoices)?selection.subchoices.join(', '):'';
 return label+(details?' · '+details:'');
};
const powerLayerNames={learned:'Imparati',prepared:'Preparati',applied:'Applicati'};
function learningSelectionDialogBody({title,closeAction,summary='',searchLabel,searchAttribute,resultsClass='',resultsId='',results='',filters='',extra='',footer=true}) {
 return '<div class="magic-tools-head"><h2>'+esc(title)+'</h2>'+
   dialogCloseButton(closeAction,'Chiudi','magic-tool-close')+'</div>'+
   '<div class="magic-tools-body">'+
   (summary?'<p class="magic-selection-warning" role="status">'+esc(summary)+'</p>':'')+
   (filters?filters:'')+
   '<label class="vtt-list-search magic-editor-search">'+esc(searchLabel)+
   '<input type="search" '+searchAttribute+' autocomplete="off" placeholder="Nome o fonte"></label>'+
   '<div '+(resultsId?'id="'+esc(resultsId)+'" ':'')+
   'class="catalog-results vtt-selection-list magic-editor-results '+esc(resultsClass)+
   '" role="list">'+results+'</div>'+extra+
   (footer?'<div class="actions"><button type="button" class="btn" data-act="'+esc(closeAction)+'">Chiudi</button></div>':'')+
   '</div>';
}
// The Fighting Style chooser uses exactly the same option rows and level
// grouping as the Artificer's infusion learner; only its actions differ.
const alreadyOwnedOptionNotice='<small class="magic-catalog-owned">Già posseduta</small>';
function learningPickerOptionRow({id,name,owned,detailsAction,toggleAction,idAttribute,label,required=false,locked=false,extra='',removeAction=''}) {
 return '<div class="magic-catalog-row vtt-selectable'+(owned?' is-selected':'')+'">'+
  '<button type="button" class="magic-catalog-name" data-act="'+esc(detailsAction)+'" '+idAttribute+'="'+esc(id)+
  '" aria-label="Dettagli di '+esc(name)+'">'+esc(name)+'</button>'+
  extra+(locked?alreadyOwnedOptionNotice:
    '<button type="button" class="magic-catalog-action'+(owned?' is-selected':'')+
    '" data-act="'+esc(toggleAction)+'" '+idAttribute+'="'+esc(id)+'"'+
    (required?' disabled title="Opzione obbligatoria"':'')+' aria-pressed="'+owned+'">'+esc(label)+'</button>'+
    removeAction)+'</div>';
}
function learningPickerOptionGroups(options,renderRow,levelOf,minLevel=0) {
 if(!options.length)return '<p class="hint">Nessuna opzione disponibile.</p>';
 const levels=[...new Set(options.map(row=>Math.max(minLevel,Number(levelOf(row))||minLevel)))]
  .sort((a,b)=>a-b);
 return '<div class="magic-groups">'+levels.map(level=>
  '<section class="magic-level"><div class="magic-level-heading"><h4>'+
  (level?'Livello '+level:'Opzioni base')+'</h4></div><div class="magic-entries">'+
  options.filter(row=>Math.max(minLevel,Number(levelOf(row))||minLevel)===level)
   .map(renderRow).join('')+'</div></section>').join('')+'</div>';
}
function optionBenefitPanels(c,calculated){
 return (calculated.power_selections||[]).filter(model=>model.benefit_type==='option_selection').map(model=>{
  const primary=model.layers.learned||model.layers.prepared;
  const byId=new Map(model.options.map(option=>[option.id,option]));
  const entries=primary?primary.selected.map(selectedPowerId):model.options.map(option=>option.id);
  const active=model.layers.applied?.selected||[];
  const summary=Object.entries(model.layers).filter(([,layer])=>layer.enabled).map(([stage,layer])=>
   '<span>'+esc(powerLayerNames[stage]||stage)+' '+layer.selected.length+(layer.limit===null?'':' / '+layer.limit)+
   (layer.change_label?' · '+esc(layer.change_label):'')+'</span>').join('');
  const controls=Object.entries(model.layers).filter(([stage,layer])=>stage!=='applied'&&layer.enabled&&!layer.automatic).map(([stage])=>
   '<button type="button" class="btn small magic-selection-button" data-act="power-selection-open" data-power-selection-id="'+esc(model.id)+'" data-power-stage="'+stage+'">'+
   (stage==='learned'?'Impara':'Prepara')+'</button>').join('');
  return panel(model.title,'<div class="benefit-option-list" data-selection-id="'+esc(model.id)+'">'+
   '<div class="infusion-overview">'+summary+'</div><div class="benefit-option-controls">'+controls+'</div>'+entries.map(id=>{
    const option=byId.get(id);if(!option)return '';
    return '<div class="magic-spell-row" data-power-option-id="'+esc(id)+'" data-option-active="'+
     active.some(row=>selectedPowerId(row)===id)+'"><span class="magic-spell-open">'+esc(option.name)+'</span></div>';
   }).join('')+'</div>');
 }).join('');
}
async function openBenefitSelectionDialog(id,stage){
 const record=state.editor?.read();if(!record)throw Error('Apri prima una creatura.');
 const calculated=await computeLocalData(record);
 const permanent=calculated.pending_choices.find(choice=>choice.model_id===id&&choice.stage===stage);
 if(permanent)return openCharacterChoice(permanent);
 const model=calculated.power_selections?.find(row=>row.id===id&&row.benefit_type==='option_selection');
 const layer=model?.layers?.[stage];
 if(!layer||layer.automatic||!['learned','prepared','applied'].includes(stage))
  throw Error('Selezione del privilegio non disponibile.');
 app.querySelector('#power-selection-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='power-selection-dialog';
 dialog.className='sheet-roll-dialog magic-tools-dialog benefit-selection-dialog';
 dialog.dataset.powerSelectionId=id;dialog.dataset.powerStage=stage;
 dialog.dataset.creatureId=record.id;dialog.dataset.benefitType=model.benefit_type;
 const selected=new Map((layer.selected||[]).map(row=>[selectedPowerId(row),row]));
 const learned=stage==='prepared'&&model.layers.learned?
  new Set((model.layers.learned.selected||[]).map(selectedPowerId)):null;
 const choices=(model.options||[]).filter(option=>
  (!option.min_level||model.level>=option.min_level||selected.has(option.id))&&
  (!learned||learned.has(option.id)||selected.has(option.id)));
 const choiceRow=option=>{
  const owned=selected.has(option.id),sub=option.subchoices,required=model.required?.includes(option.id);
  const locked=owned&&(stage==='learned'||stage==='prepared');
  const current=selected.get(option.id);
  const fields=sub?'<div class="power-selection-subchoices">'+
   Array.from({length:sub.count},(_,i)=>'<label>'+esc(sub.label||'Sotto-opzione')+' '+(i+1)+
    '<input type="text" data-power-subchoice="'+i+'" data-power-option="'+esc(option.id)+'" maxlength="70" value="'+
    esc(current?.subchoices?.[i]||'')+'" placeholder="'+esc(sub.placeholder||'Sotto-opzione')+'"'+(locked?' disabled':'')+'></label>').join('')+'</div>':'';
  const label=required?'Obbligatoria':model.selection_kind==='subtrait'?
   (owned?(sub?'Aggiorna':'Rimuovi'):'Scegli'):
   owned?(sub?'Aggiorna':stage==='learned'?'Dimentica':'Rimuovi'):
   stage==='learned'?'+ Impara':stage==='prepared'?'+ Prepara':'+ Applica';
  return learningPickerOptionRow({
   id:option.id,name:option.name,owned,required,locked,
   detailsAction:'power-selection-details',toggleAction:'power-selection-toggle',
   idAttribute:'data-power-option-id',label,extra:fields,
   removeAction:owned&&sub?'<button type="button" class="magic-catalog-action" data-act="power-selection-toggle"'+
    ' data-power-remove="true" data-power-option-id="'+esc(option.id)+'">Rimuovi</button>':''
  });
 };
 const renderChoices=shown=>learningPickerOptionGroups(shown,choiceRow,row=>row.min_level||0);

 const stageTitle=stage==='learned'?'Impara '+model.title:
  stage==='prepared'?'Prepara '+model.title:'Applica '+model.title;
 dialog.innerHTML=learningSelectionDialogBody({
  title:stageTitle,closeAction:'power-selection-close',
  summary:(powerLayerNames[stage]||stage)+' '+selected.size+
    (layer.limit!==null?' / '+layer.limit:'')+
    (layer.change_label?' · '+layer.change_label:''),
  searchLabel:'Cerca '+model.title,searchAttribute:'data-power-search',
  resultsClass:'learning-picker-results power-selection-results',
  results:renderChoices(choices),
  extra:stage==='learned'?'':(model.description?'<p class="hint">'+esc(model.description)+'</p>':''),
  footer:stage!=='learned'
 });
 // Render filtered choices just like the infusion learner. Hiding individual
 // rows is unreliable because the shared list stylesheet uses display:grid!important.
 const input=dialog.querySelector('[data-power-search]');
 const results=dialog.querySelector('.power-selection-results');
 input.addEventListener('input',()=>{
  results.innerHTML=renderChoices(choices.filter(row=>
   matchesSearch(input.value,row.name,row.source)));
 });
 app.append(dialog);dialog.addEventListener('close',()=>dialog.remove(),{once:true});openDialog(dialog);
}
async function benefitOptionDescription(option){
 if(!option.details)return option.description||'';
 const ref=option.details;
 const detail=await detailedEntry(ref.category,{name:ref.name,source:ref.source,_category:ref.category});
 return flattenDescription(detail)||option.description||'';
}
async function openBenefitOptionDialog(selectionId,optionId){
 const record=state.editor?.read();if(!record)throw Error('Apri prima una creatura.');
 const calculated=await computeLocalData(record),model=calculated.power_selections.find(row=>row.id===selectionId);
 const option=model?.options.find(row=>row.id===optionId);
 if(!option)throw Error('Opzione non disponibile.');
 const layer=model.layers.applied,target=layer?.target;
 const known=!model.layers.learned||model.layers.learned.selected.some(row=>selectedPowerId(row)===optionId);
 const applications=(layer?.selected||[]).filter(row=>selectedPowerId(row)===optionId).map(row=>{const index=(record.inventory||[]).findIndex(item=>(item.instance_id||item.id)===row.target_item_id);return {...(typeof row==='string'?{id:row}:row),inventory_index:index,target_name:record.inventory?.[index]?.name};});
 const active=applications.length>0,description=await benefitOptionDescription(option);
 if(state.editor?.read()?.id!==record.id)return;
 app.querySelector('#benefit-option-dialog')?.remove();
 const dialog=document.createElement('dialog');dialog.id='benefit-option-dialog';
 dialog.className='sheet-roll-dialog magic-spell-dialog benefit-option-dialog';
 dialog.dataset.powerSelectionId=selectionId;dialog.dataset.powerOptionId=optionId;
 dialog.dataset.creatureId=record.id;dialog.dataset.benefitType=model.benefit_type;dialog.dataset.selectedItem='';dialog.dataset.selectedCatalogIndex='';
 const facts=[{label:'Stato',value:active?'Applicata':known?'Conosciuta':'Da imparare'},
  ...(option.min_level?[{label:'Livello richiesto',value:String(option.min_level)}]:[]),
  ...(target?[{label:'Bersaglio',value:target.label||'Oggetto'}]:[]),
  ...(layer?.change_label?[{label:'Quando cambiare',value:layer.change_label}]:[])];
 const benefits=[...(option.attacks||[]).map(row=>row.name||row.trait),...(option.granted_features||[]),
  ...(option.numeric_grants||[]).map(row=>row.trait||row.id)];
 dialog.innerHTML=actionDialogIntro(option.name,facts,description||'Descrizione non disponibile nel catalogo.',model.title,'benefit-option-close')+
  (benefits.length?'<section class="infusion-dialog-active"><h3>Benefici</h3>'+benefits.map(name=>'<p>'+esc(name)+'</p>').join('')+'</section>':'')+
  (applications.length&&target?'<section class="infusion-dialog-active"><h3>Applicazioni attive</h3>'+applications.map(row=>
    '<div class="infusion-dialog-item"><span>'+esc(row.target_name||'Applicazione attiva')+'</span><button type="button" class="btn" '+
    'data-act="benefit-option-remove" data-index="'+(row.inventory_index??-1)+'">Disattiva</button></div>').join('')+'</section>':'')+
  (known&&target?'<label class="vtt-list-search inventory-global-search benefit-target-search"><input type="search" data-benefit-target-search '+
    'aria-label="'+esc(target.label||'Oggetto compatibile')+'" placeholder="'+esc(target.label||'Oggetto compatibile')+'" autocomplete="off"></label>'+
    '<div class="inventory-search-results vtt-selection-list benefit-target-results" role="list"></div>':'')+
  (known&&option.effect_choice?'<label>'+esc(option.effect_choice.label||'Scelta effetto')+'<select data-benefit-effect>'+option.effect_choice.options.map(value=>
   '<option value="'+esc(value)+'">'+esc(value)+'</option>').join('')+'</select></label>':'')+
  '<p class="hint" data-benefit-error role="status" hidden></p><div class="actions magic-dialog-actions">'+
  (known&&layer&&!layer.automatic?'<button type="button" class="btn primary" data-act="benefit-option-apply"'+(target?' disabled':'')+'>'+
   (active&&!target?'Disattiva':'Applica')+'</button>':'')+
  '<button type="button" class="btn" data-act="benefit-option-close">Chiudi</button></div>';
 if(known&&target){
  const input=dialog.querySelector('[data-benefit-target-search]'),results=dialog.querySelector('.benefit-target-results');
  const paint=()=>{
   const candidates=powerSelectionTargets(record,model,option).filter(({item})=>matchesSearch(input.value,item.name,item.source)).map(({item,index})=>({item,index}));
   if(target.allow_catalog&&input.value.trim().length>=2)candidates.push(...(state.referenceCatalogs.items||[]).map((entry,index)=>({entry,index})).filter(({entry})=>
    matchesSearch(input.value,entry.name,entry.source)&&isContentAvailableForRules(entry,record.rules_version)&&
    !record.inventory?.some(item=>item.id===entry.id)&&
    powerSelectionTargets({...record,inventory:[createOwnedItem(entry,'preview')]},model,option).length).slice(0,60).map(({entry,index})=>({item:entry,index,catalog:true})));
   results.innerHTML=candidates.map(({item,index,catalog})=>'<button type="button" class="inventory-search-result vtt-selectable" '+
    'data-act="benefit-target-choose" '+(catalog?'data-catalog-index':'data-index')+'="'+index+'"><span class="inventory-search-result-count" aria-hidden="true">'+
    (catalog?'+':'×'+Math.max(1,Number(item.quantity)||1))+'</span><span class="inventory-search-result-copy"><strong>'+esc(item.name||item.id)+
    '</strong>'+(item.source?'<small>'+esc(item.source)+'</small>':'')+'</span><span class="inventory-search-result-chevron" aria-hidden="true">›</span></button>').join('')||
    '<p class="inventory-search-notice">'+(target.allow_catalog?'Scegli un oggetto posseduto o cercane uno nel catalogo.':'Nessun oggetto equipaggiato compatibile.')+'</p>';
  };
  input.addEventListener('input',paint);paint();
  if(target.allow_catalog)ensureInventorySearchCatalog();
 }
 app.append(dialog);dialog.addEventListener('close',()=>dialog.remove(),{once:true});openDialog(dialog);
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
      String(a.source||'').localeCompare(String(b.source||''),'it'));
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
    '<label class="vtt-list-search">Incantesimo<input id="scroll-spell-query" type="search" autocomplete="off" placeholder="Cerca incantesimo…" value="'+esc(state.scrollSpellQuery)+'"></label>'+
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
      parts.push("CA "+(typeof ac==="object"?ac.base:ac)+" "+armorDexterityLabel(obj));
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
  const blocked=Boolean(main&&(hasProperty(main,"2H")||(versatile&&c.hand_grip_two_handed))&&
    c.hand_off_with_two_handed!==true);
  const rows=labels.map(([slot,label])=>{
    const selected=blocked&&slot==="off"?-1:
      inventory.findIndex(item=>Array.isArray(item.equipped_slots)&&item.equipped_slots.includes(slot));
    const special=blocked&&slot==="off"?"none":
      slot==="body"?"none":c["hand_"+slot+"_special"]==="improvised"?"improvised":"none";
    const options=[[-1,slot==="body"?"Nessuna armatura":"Nessuno"],
      ...(slot==="body"?[]:[["improvised","Arma improvvisata"]]),
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
  const {formula,sourceLabel}=armorClassBaseFormula(c,calculated);
  const attackSettings='<div class="equipment-attack-options">'+
    '<label class="equipment-attack-ability">Caratteristica attacchi<select data-field="attack_ability">'+
      [['str','Forza'],['dex','Destrezza'],['con','Costituzione'],['int','Intelligenza'],['wis','Saggezza'],['cha','Carisma']].map(([value,label])=>
        '<option value="'+value+'"'+((c.attack_ability||"str")===value?' selected':'')+'>'+label+'</option>').join('')+
    '</select></label>'+
    '<label class="check"><input type="checkbox" data-field="attack_ability_finesse_only"'+
      (c.attack_ability_finesse_only!==false?' checked':'')+'>Usa solo per armi accurate</label>'+
    (versatile?'<label class="check"><input type="checkbox" data-field="hand_grip_two_handed"'+
      (c.hand_grip_two_handed?' checked':'')+'>Due mani (Versatile)</label>':'')+
    '<label class="check equipment-offhand-override"><input type="checkbox" data-field="hand_off_with_two_handed"'+
      (c.hand_off_with_two_handed===true?' checked':'')+
      '>Secondaria libera con arma a due mani</label>'+
    '</div>';
  const defense='<div class="equipment-defense">'+
    '<div class="battle-defense-values"><div class="battle-stat"><span>CA totale</span>'+
      formulaReadout(calculated,'ac','Classe armatura',{showBonus:false})+'</div></div>'+
    '<div class="battle-ac-formula"><strong>'+esc(sourceLabel)+
      '</strong><output>'+esc(formula)+'</output></div>'+
    '<label class="check equipment-armor-speed-penalty"><input type="checkbox" data-field="armor_speed_limit_enabled"'+
      (c.armor_speed_limit_enabled!==false?' checked':'')+
      '>Applica penalità alla velocità per Forza insufficiente</label>'+
    (calculated.armor_effects?.speed_penalty?
      '<small class="hint">Velocità ridotta di '+calculated.armor_effects.speed_penalty+
      ' ft · Forza richiesta '+calculated.armor_effects.strength_required+'</small>':'')+
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
  const base=Math.max(0,Math.min(99,Number(c.attunement_max_base??3)||0));
  const max=state.calculated?.attunements?.maximum??state.calculated?.values?.attunement_max??base;
  const active=state.calculated?.attunements?.used??inventoryAttunementCounts(c.inventory,max).reduce((sum,n)=>sum+n,0);
  const lines=entries.map(({index})=>inventoryAttunementControl(c,index,state.calculated||{})).join('');
  return panel("Oggetti che richiedono sintonia",
    '<div class="inventory-attunement-meta"><span>Sintonie '+active+' / '+
      formulaReadout(state.calculated||{values:{attunement_max:max}},
        'attunement_max','Sintonie massime',{showBonus:false})+'</span>'+
    '</div>'+
    (lines||'<p class="hint">Nessun oggetto richiede sintonia.</p>'),
    "inventory-native-panel inventory-attunement");
}
function inventoryTable(entries,scrolls,selectedIndex,menuIndex,containers=[]){
  if(!entries.length)return '<p class="hint">Nessun '+(scrolls?'incantesimo su pergamena.':'oggetto.')+'</p>';
  const headings=scrolls?["Qtà","Livello","Incantesimo"]:["Slot","mo","Peso","Qtà","Fonte","Proprietà / CA","Nome"];
  return '<div class="inventory-table" role="table" aria-label="'+(scrolls?'Pergamene':'Oggetti')+'">'+
    '<div class="inventory-table-head" role="row">'+headings.map((x,i)=>
      '<span class="inventory-col-'+(scrolls?["quantity","level","name"][i]:
        ["equip","value","weight","quantity","source","property","name"][i])+'" role="columnheader">'+x+'</span>').join('')+'</div>'+
    entries.map(({item,index})=>{
      const kind=itemKind(item),slots=Array.isArray(item.equipped_slots)?item.equipped_slots:[],
        canEquip=['weapon','shield','armor'].includes(kind),
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
        displayName=scrolls?spellScrollName(item):ownedItemDisplayName(item),
        name=isCatalogItem(item)?'<strong>'+esc(displayName)+'</strong>':
          '<input class="inventory-item-name-input" aria-label="Nome oggetto" data-item-index="'+index+
          '" data-item-key="name" value="'+esc(item.name||"")+'">'+
          (item.infusion?.name?'<small class="inventory-item-extension"> - '+esc(item.infusion.name)+'</small>':''),
        nameCell='<span class="inventory-col-name">'+
          '<button type="button" class="inventory-select" data-act="inventory-select" data-index="'+index+
          '" aria-label="Mostra descrizione di '+esc(item.name)+'">'+(isCatalogItem(item)?name:scrolls?esc(displayName):'Dettagli')+'</button>'+
          (isCatalogItem(item)?'':name)+
          (scrolls?'':'<small class="inventory-mobile-properties">'+esc(inventoryProperties(item))+'</small>')+'</span>',
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
      return '<div class="inventory-table-row vtt-selectable'+(index===selectedIndex?' selected is-selected':'')+
        (item.attuned?' attuned':'')+'" role="row" data-inventory-row="'+index+'">'+cells.join('')+'</div>';
    }).join('')+'</div>';
}
function openInventoryContainerDelete(id){
  const editor=state.editor,record=editor?.read(),containers=inventoryContainers(record);
  const original=containers.find(row=>row.id===id);
  if(!original||id===DEFAULT_INVENTORY_CONTAINER)throw Error("Zaino non eliminabile.");
  document.querySelector('#inventory-container-delete-dialog')?.remove();
  const remaining=(record.inventory||[]).filter(item=>itemContainerId(item,containers)===id).length;
  const dialog=document.createElement('dialog');
  dialog.id='inventory-container-delete-dialog';dialog.className='sheet-context-dialog';
  dialog.setAttribute('aria-labelledby','inventory-container-delete-title');
  dialog.innerHTML='<div class="sheet-context-body"><h2 id="inventory-container-delete-title">Elimina sezione</h2>'+
    '<p>Vuoi eliminare la sezione <strong>'+esc(original.name)+'</strong>?</p>'+
    (remaining?'<p>La sezione contiene '+(remaining===1?'una voce':remaining+' voci')+'. Scegli dove trasferire gli oggetti prima di eliminarla.</p>'+
      '<label>Sposta gli oggetti in<select data-container-destination required><option value="">Seleziona una sezione</option>'+
      containers.filter(row=>row.id!==id).map(row=>'<option value="'+esc(row.id)+'">'+esc(row.name)+'</option>').join('')+'</select></label>':
      '<p>La sezione è vuota.</p>')+
    '<p data-container-delete-error role="alert"></p><div class="actions">'+
    '<button type="button" class="btn" data-container-delete-cancel>Annulla</button>'+
    '<button type="button" class="btn danger" data-container-delete-confirm'+(remaining?' disabled':'')+'>Elimina sezione</button></div></div>';
  const destination=dialog.querySelector('[data-container-destination]');
  const confirm=dialog.querySelector('[data-container-delete-confirm]');
  const cancel=dialog.querySelector('[data-container-delete-cancel]');
  const close=()=>{if(dialog.close)dialog.close();else dialog.remove();};
  let saving=false;
  destination?.addEventListener('change',()=>{confirm.disabled=!destination.value;});
  cancel.addEventListener('click',close);
  dialog.addEventListener('cancel',event=>{if(saving)event.preventDefault();});
  confirm.addEventListener('click',async()=>{
    if(confirm.disabled||saving)return;
    saving=true;confirm.disabled=true;cancel.disabled=true;if(destination)destination.disabled=true;
    try{
      if(state.editor!==editor)throw Error('La creatura è cambiata. Riapri la sezione da eliminare.');
      const current=editor.read(),freshContainers=inventoryContainers(current);
      const hasItems=(current.inventory||[]).some(item=>itemContainerId(item,freshContainers)===id);
      if(hasItems&&!destination?.value)throw Error('La sezione contiene oggetti. Riapri la finestra e scegli una destinazione.');
      await patch(deleteInventoryContainer(current,id,destination?.value||DEFAULT_INVENTORY_CONTAINER));
      await editor.flush();
      setInventoryVisibleSections(editor.read(),state.inventorySelectedTabs.filter(key=>key!=='container:'+id));
      state.inventoryMenuIndex=-1;close();await render();
    }catch(error){
      saving=false;confirm.disabled=!!destination&&!destination.value;cancel.disabled=false;
      if(destination)destination.disabled=false;
      dialog.querySelector('[data-container-delete-error]').textContent=errorMessage(error);
    }
  });
  dialog.addEventListener('close',()=>dialog.remove(),{once:true});
  document.body.append(dialog);
  openDialog(dialog);
  (destination||cancel).focus();
}
function inventoryContainerSections(record,entries,containers,selectedIndex,menuIndex,key){
  const active=key.startsWith('container:')?containers.find(row=>row.id===key.slice(10)):null;
  const destination=active?.id||DEFAULT_INVENTORY_CONTAINER;
  const rows=entries.filter(({item})=>itemContainerId(item,containers)===destination);
  const controls=active?'<div class="inventory-container-management">'+
    '<button type="button" class="btn small" data-act="inventory-container-rename" data-container-id="'+esc(active.id)+'">Rinomina sezione</button></div>':'';
  return '<div data-inventory-section="'+esc(key)+'">'+
    panel(active?.name||'Zaino',
      controls+inventoryTable(rows,false,selectedIndex,menuIndex,containers)+
      '<div class="actions"><button type="button" class="btn small" data-act="item-catalog" data-container-id="'+esc(destination)+'">＋ Dal catalogo</button>'+
      '<button type="button" class="btn small" data-act="new-homebrew-item" data-container-id="'+esc(destination)+'">＋ Homebrew</button></div>',
      "inventory-native-panel inventory-items-panel")+'</div>';
}
function inventoryItemDescription(obj,index){
  if(requiresAttunement(resolveOwnedItem(obj))&&state.calculated?.attunements)
    obj={...obj,attuned_count:state.calculated.attunements.counts[index]||0};
  const info=inventoryReadout(obj,inventoryProperties(obj),isSpellScroll(obj));
  const itemExtensions=effectExtensionsFor(state.calculated?.effect_extensions||[],
    {kind:'item',id:obj.id,name:obj.name,instance_id:obj.instance_id,inventory_index:index});
  const pairs=[['Tipo',info.type],...(obj.source?[['Fonte',String(obj.source)]]:[]),
    ...(obj.rarity&&obj.rarity!=='none'?[['Rarità',INVENTORY_RARITIES[String(obj.rarity).toLowerCase()]||obj.rarity]]:[]),
    ...info.facts.map(fact=>[fact.label,fact.value]),...(info.status.length?[['Stato',info.status.join(' · ')]]:[])];
  // The brief readout is not a replacement for complete structured metadata.
  const seen=new Set(pairs.map(([label])=>label.toLocaleLowerCase('it')));
  for(const [label,value] of structuredItemFacts(resolveOwnedItem(obj))){
    if(seen.has(label.toLocaleLowerCase('it')))continue;
    pairs.push([label,value]);seen.add(label.toLocaleLowerCase('it'));
  }
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
    (obj.id?'<button type="button" class="inventory-trait-link" data-act="inventory-open-trait" data-index="'+index+
      '">'+actionGlyph('proficiency')+'<span>Apri il tratto dell’oggetto</span><span aria-hidden="true">↗</span></button>':'')+
    '<dl class="inventory-detail-facts">'+pairs.map(([label,value])=>'<div><dt>'+esc(label)+'</dt><dd>'+esc(value)+'</dd></div>').join('')+'</dl>'+
    (properties!=='—'?'<section class="inventory-detail-section"><h3>Proprietà</h3><p>'+esc(properties)+'</p></section>':'')+
    (itemExtensions.length?'<section class="inventory-detail-section magic-effect-extensions">'+
       '<h3>Estensioni attive</h3><ul>'+itemExtensions.map(extension=>
       '<li><strong>'+esc(extension.origin_name||'Beneficio')+'</strong> · '+
       esc(effectExtensionLabel(extension,{cha_mod:state.calculated?.abilities?.cha?.modifier}))+
       (['spell_storing_item','spell_imprint'].includes(extension.stored_spell_feature)?
        '<div class="inventory-prose">'+esc(extension.spell_description||'')+'</div>'+
        (()=>{const tracker=(state.calculated?.trackers||[]).find(row=>row.id===extension.tracker_id);
         const remaining=tracker?Math.max(0,Number(tracker.max)-Number(tracker.spent||0)):0;
         const imprint=extension.stored_spell_feature==='spell_imprint';
         const valid=!imprint||spellImprintActive(extension);
         return '<div class="actions"><button type="button" class="btn small" data-act="spell-storing-use" data-index="'+index+'"'+
          (!valid||remaining<1?' disabled':'')+'>'+
          (imprint?'Lancia dalla carta · '+(extension.action_type==='bonus'?'azione bonus':'azione'):
            'Usa incantesimo')+' · '+esc(remaining)+' rimasti</button></div>';
        })():'')+
       '</li>').join('')+'</ul></section>':'')+
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
    ''+
    (requiresAttunement(obj)?inventoryAttunementControl(state.editor.read(),index,state.calculated||{}):'')+
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
function castingStatisticsVisible(c,section,defaultVisible=true){
 const saved=c.spellcasting_section_visibility?.[section];
 return typeof saved==='boolean'?saved:defaultVisible;
}
function castingStatisticsToggle(c,section,defaultVisible=true){
 const visible=castingStatisticsVisible(c,section,defaultVisible);
 const label=visible?'Nascondi CD e statistiche di lancio':'Mostra CD e statistiche di lancio';
 return '<button type="button" class="magic-source-visibility" data-act="casting-stats-toggle"'+
   ' data-casting-visibility-section="'+esc(section)+'" data-casting-default-visible="'+defaultVisible+
   '" aria-pressed="'+visible+'" aria-label="'+label+'" title="'+label+'">'+actionGlyph('eye')+'</button>';
}
function castingStatistics(c,section,ability,permitted=null){
 const available=Array.isArray(permitted)&&permitted.length?permitted:Object.keys(abilities);
 const saved=c.spellcasting_section_abilities?.[section];
 const selected=available.includes(saved)?saved:available.includes(ability)?ability:available[0]||'int';
 // A single, readable inline stat strip. Full names remain available to screen
 // readers and via the native select, while short labels fit narrow phones.
 return '<div class="casting-statistics" role="group" aria-label="Statistiche di lancio">'+
   '<label class="casting-stat casting-stat--ability">'+
     '<span class="casting-stat-label">Caratt.</span>'+
     '<select aria-label="Caratteristica degli incantesimi" title="Caratteristica degli incantesimi" data-casting-section="'+esc(section)+'">'+
       Object.entries(abilities).filter(([id])=>available.includes(id)).map(([id,label])=>
         '<option value="'+esc(id)+'" aria-label="'+esc(label)+'" title="'+esc(label)+'" '+
         (selected===id?'selected':'')+'>'+esc(({str:'FOR',dex:'DES',con:'COS',int:'INT',wis:'SAG',cha:'CAR'})[id]||id.toUpperCase())+'</option>').join('')+
     '</select></label>'+
   '<span class="casting-stat casting-stat--dc"><span class="casting-stat-label">CD</span>'+
     formulaReadout(state.calculated,'casting_dc:'+selected,'CD incantesimi',{bonusTarget:'spell_dc'})+'</span>'+
   '<span class="casting-stat casting-stat--attack"><span class="casting-stat-label">Att.</span>'+
     formulaReadout(state.calculated,'casting_hit:'+selected,'Attacco incantesimi',{signed:true,bonusTarget:'spell_attack'})+'</span></div>';
}
function slotCounter(level,total,spent){
 const key=level===0?'pact_slot':'slot:'+level;
 return '<div class="slot-counter">'+(total>0?'<button class="btn small" data-act="slot-use" data-level="'+level+'" '+(spent>=total?'disabled':'')+' aria-label="Consuma slot '+level+'">−</button><button class="btn small" data-act="slot-recover" data-level="'+level+'" '+(spent<=0?'disabled':'')+' aria-label="Recupera slot '+level+'">＋</button>':'')+'<span>'+Math.max(0,total-spent)+' / </span><button class="btn small slot-total" data-act="edit-bonus" data-target="'+key+'" data-calculated="'+key+'" aria-label="Bonus massimo slot '+level+'">'+total+'</button></div>';
}
// Class and Pact Magic slots share a projection. A tap opens actions first;
// no slot changes until the user selects Consuma or Ripristina.
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
// Spell source headers only identify their payment method. The detailed
// normal/Pact slot levels and remaining uses stay in the Slot overview.
function magicSlotUsageChip(){
 return '<span class="magic-source-resource" title="Slot incantesimo">'+
   '<span class="magic-source-resource-label">Slot</span></span>';
}
function magicTrackerUsageChip(tracker){
 const id=esc(tracker.id),name=esc(tracker.name||'Tracker');
 const max=Math.max(0,Number(tracker.max)||0);
 const spent=Math.max(0,Number(tracker.spent)||0);
 return '<span class="magic-source-resource magic-source-tracker" data-magic-tracker-id="'+id+'">'+
   '<span class="magic-source-resource-label">'+name+'</span>'+
   '<span class="magic-source-resource-counter"><strong data-tracker-remaining="'+id+'">'+
     Math.max(0,max-spent)+'</strong> / '+max+'</span>'+
   '<button type="button" data-act="tracker-less" data-tracker-id="'+id+'" '+
     'aria-label="Recupera un utilizzo di '+name+'" title="Recupera"'+
     (spent<=0?' disabled':'')+'>+</button>'+
   '<button type="button" data-act="tracker-more" data-tracker-id="'+id+'" '+
     'aria-label="Consuma un utilizzo di '+name+'" title="Consuma"'+
     (spent>=max?' disabled':'')+'>−</button></span>';
}
function originSpellSections(c,calculated,renderRow){
 // Preserve grouping by granting origin even when grants use different
 // payment methods or share a tracker with a different origin.
 const origins=new Map();
 for(const grant of calculated.origin_spells||[]){
   const origin=String(grant.origin_id||'other');
   if(!origins.has(origin))origins.set(origin,{
     name:grant.origin_name||'Origine non specificata',
     ability:grant.spellcasting_ability||'int',showStats:grant.casting_ability_not_required!==true,
     allowed:grant.spellcasting_ability_options?.length?grant.spellcasting_ability_options:[grant.spellcasting_ability||'int'],items:[],trackers:new Map(),
     usesSlots:false,missingTracker:false,hasFree:false
   });
   const group=origins.get(origin);
   const info=magicSpellInfo((state.spellCatalog||[]).find(s=>s.id===grant.spell_id)||
     {id:grant.spell_id,name:grant.spell_id});
   group.items.push({grant,info});
   const mode=grant.payment_mode||(grant.tracker_id?'tracker':
     ['known','prepared'].includes(grant.mode)?'slot':'free');
   if(mode==='slot'||grant.slot_alternative===true)group.usesSlots=true;
   // Tracker and slot alternatives are independent resources. Never hide
   // the tracker badge when the same privilege permits ordinary slots.
   if(mode==='tracker'){
     const tracker=(calculated.trackers||[]).find(t=>t.id===grant.tracker_id&&!t.disabled);
     if(tracker)group.trackers.set(tracker.id,tracker);
     else group.missingTracker=true;
   }else if(mode==='free')group.hasFree=true;
 }

 return [...origins.entries()].sort((a,b)=>a[1].name.localeCompare(b[1].name,'it',{sensitivity:'base'}))
   .map(([origin,group])=>{
     const badges=(group.usesSlots?magicSlotUsageChip():'')+
       [...group.trackers.values()].map(magicTrackerUsageChip).join('')+
       (group.missingTracker?'<span class="magic-source-resource magic-source-resource--warning">Tracker non disponibile</span>':'')+
       (group.hasFree&&!group.usesSlots&&!group.trackers.size&&!group.missingTracker?
         '<span class="magic-source-resource magic-source-resource--free">Senza costo</span>':'');
     return '<section class="magic-source magic-origin-panel" data-magic-origin="'+esc(origin)+'">'+
       '<header class="magic-source-header"><div class="magic-source-title"><h3>'+esc(group.name)+'</h3>'+
       castingStatisticsToggle(c,'origin:'+origin,group.showStats)+'</div>'+
       '<div class="magic-source-resources" aria-label="Risorse di lancio">'+badges+'</div></header>'+
       (castingStatisticsVisible(c,'origin:'+origin,group.showStats)?
         castingStatistics(c,'origin:'+origin,group.ability,group.allowed):'')+
       (calculated.active_celestial_form&&group.items.some(item=>
         item.grant.spell_id===calculated.active_celestial_form.spell_id)?
         '<div class="magic-active-form"><strong>Manifestazione attiva · 1 minuto</strong> '+
         '<button type="button" class="btn small" data-act="end-racial-power">Termina</button></div>':'')+
       (group.items.length?groupedMagicSpells(group.items,({grant,info})=>renderRow(grant,info)):'')+
       '</section>';
   }).join('');
}
function magicLevelSlotChip(level,slot,pact=false){
 const total=Math.max(0,Number(slot.total)||0),spent=Math.max(0,Number(slot.spent)||0);
 const remaining=Math.max(0,total-spent);
 return '<button type="button" class="magic-level-slot" data-act="slot-menu" data-level="'+level+'" data-pact="'+pact+'" '+
   ' title="Gestisci slot e visualizza gli incantesimi lanciabili"'+
   ' aria-haspopup="dialog" aria-label="'+(pact?'Patto':'Slot livello '+level)+': '+remaining+' di '+total+' rimanenti; apri il menu">'+
   (pact?'<span class="magic-pact-icon" aria-hidden="true">✦</span>':'')+
   '<strong data-slot-remaining="'+(pact?'pact':level)+'">'+remaining+'</strong><span> / '+total+'</span></button>';
}
// Slot and concentration resources stay visible even if every slot is spent.
function magicOverview(c,calculated){
 const classSlots=calculated.spell_slots||[];
 const pact=calculated.pact_slots||{};
 const entries=Array.from({length:9},(_,index)=>{
   const level=index+1,slot=classSlots[index]||{level,total:0,spent:0};
   if(Number(slot.total)<=0)return '';
   return '<div class="magic-overview-slot"><span class="magic-overview-level">'+level+'°</span>'+
     magicLevelSlotChip(level,slot)+'</div>';
 }).join('');
 const pactSlot=Number(pact.total)>0&&Number(pact.level)>0?
   '<div class="magic-overview-slot magic-overview-pact"><span class="magic-overview-level">Patto '+esc(pact.level)+'°</span>'+
   magicLevelSlotChip(Number(pact.level),pact,true)+'</div>':'';
 const active=(c.conditions||[]).includes('concentrating')||Boolean(c.concentrating_spell_id);
 const id=String(c.concentrating_spell_id||'');
 const name=id?((state.spellCatalog||[]).find(spell=>spell.id===id)?.name||id):'';
 return '<section class="magic-overview" aria-label="Slot e concentrazione">'+
   '<div class="magic-overview-heading"><h3>Slot incantesimo</h3>'+
   '<button type="button" class="btn small magic-overview-manage" data-act="magic-tool-open" data-magic-tool="slots">Gestisci slot</button></div>'+
   '<div class="magic-overview-slots">'+(entries||pactSlot?entries+pactSlot:
     '<p class="magic-overview-empty">Nessuno slot assegnato.</p>')+'</div>'+
   '<div class="magic-overview-concentration"><span class="magic-concentration-title">Concentrazione</span>'+
   '<span class="magic-concentration-current'+(active?' is-active':'')+'">'+
     esc(active?(name||'Attiva · nessun incantesimo'):'Non attiva')+'</span>'+
   '<button type="button" class="magic-overview-icon" data-act="concentration-open" aria-label="'+
     esc(active?'Sostituisci incantesimo di concentrazione':'Attiva concentrazione')+'" title="Aggiungi o sostituisci concentrazione">+</button>'+
   (active?'<button type="button" class="magic-overview-icon magic-overview-stop" data-act="stop-concentration" aria-label="Termina concentrazione" title="Termina concentrazione">×</button>':'')+
   '</div></section>';
}
function magicToolsDialog(c,calculated){
 const kind=state.magicPopup;
 if(!kind)return '';
 // Use only already-loaded spells to keep the modal fast offline.
 const spellChoices=new Map();
 for(const row of [...availableSpells(c),...sessionSpellEntries(c,calculated,state.spellCatalog||[])]){
   const id=spellId(row);
   if(id&&!spellChoices.has(id))spellChoices.set(id,magicSpellInfo(row).name||id);
 }
 const focusedId=String(c.concentrating_spell_id||'');
 if(focusedId&&!spellChoices.has(focusedId))
   spellChoices.set(focusedId,(state.spellCatalog||[]).find(spell=>spell.id===focusedId)?.name||focusedId);
 const concentration='<div class="magic-concentration-picker">'+
   '<p class="hint">La concentrazione può essere attiva anche senza indicare un incantesimo.</p>'+
   '<label>Incantesimo (facoltativo)<select id="concentration-spell">'+
     '<option value="">Nessun incantesimo specificato</option>'+
     [...spellChoices.entries()].sort((a,b)=>a[1].localeCompare(b[1],'it',{sensitivity:'base'}))
       .map(([id,name])=>'<option value="'+esc(id)+'"'+(id===focusedId?' selected':'')+'>'+esc(name)+'</option>').join('')+
   '</select></label>'+
   '<div class="actions"><button type="button" class="btn primary" data-act="concentration-set">'+
     ((c.conditions||[]).includes('concentrating')?'Aggiorna concentrazione':'Attiva concentrazione')+'</button></div></div>';
 // Shared slotUsePatch supplies tracker-style bounded counters.
 const slotTrackerRow=(level,slot,pact=false)=>{
   const maximum=Math.max(0,Number(slot?.total)||0),used=Math.max(0,Number(slot?.spent)||0);
   const remain=Math.max(0,maximum-used);
   const name=pact?'Patto · '+(Number(slot?.level)||'—')+'°':'Livello '+level;
   const scoreTarget=pact?'pact_slot':'slot:'+level;
   return '<div class="magic-slot-manager-row"><strong>'+esc(name)+'</strong>'+
     '<div class="magic-slot-manager-controls magic-tracker-controls">'+
       '<span class="magic-tracker-count"><strong>'+remain+'</strong> / '+
         '<button type="button" class="magic-slot-maximum" data-act="sheet-score-formula"'+
           ' data-target="'+scoreTarget+'" data-calculated="'+scoreTarget+'"'+
           ' data-label="Massimo '+esc(name)+'" title="Visualizza la formula del massimo"'+
           ' aria-label="Formula del massimo '+esc(name)+': '+maximum+'">'+maximum+'</button></span>'+
       '<button type="button" class="magic-tracker-change" data-act="slot-recover" data-level="'+(pact?0:level)+'"'+
         (used<=0?' disabled':'')+' aria-label="Ripristina uno slot '+esc(name)+'" title="Ripristina 1">+1</button>'+
       '<button type="button" class="magic-tracker-change" data-act="slot-use" data-level="'+(pact?0:level)+'"'+
         (used>=maximum?' disabled':'')+' aria-label="Consuma uno slot '+esc(name)+'" title="Consuma 1">−1</button>'+
     '</div></div>';
 };
 const classSlots=Array.from({length:9},(_,index)=>calculated.spell_slots?.[index]||{level:index+1,total:0,spent:0,base:0});
 const pact=calculated.pact_slots||{total:0,spent:0,base:0,level:0};
 const slots='<div class="magic-slot-manager">'+
   classSlots.map((slot,index)=>slotTrackerRow(index+1,slot)).join('')+
   slotTrackerRow(0,pact,true)+
   '<div class="actions"><button type="button" class="btn small" data-act="slots-restore">Ripristina tutti gli slot</button></div></div>';
 const selectedMember=calculated.casting_classes.find(member=>member.id===state.spellClass);
 const counts=selectedMember?classSelectionCount(c,selectedMember,calculated.casting_classes,state.spellCatalog||[]):null;
 const knownProgress=selectedMember?knownSpellProgress(c,selectedMember,calculated.casting_classes,state.spellCatalog||[]):null;
 // The same selection summary, class filter, search and result view serve
 // both learned and prepared stages. Only the title and row action change.
 const selectionSummary=[
   selectedMember?.mode==='Preparati'&&Number.isInteger(selectedMember.limit)&&selectedMember.limit>=0?
     'Preparati: '+counts.leveled+' / '+selectedMember.limit:'',
   knownProgress&&Number.isInteger(knownProgress.minimum)&&knownProgress.minimum>=0?
     'Conosciuti: '+knownProgress.known+' / '+knownProgress.minimum:'',
   selectedMember&&Number.isInteger(selectedMember.cantrips)&&selectedMember.cantrips>=0?
     'Trucchetti conosciuti: '+counts.cantrips+' / '+selectedMember.cantrips:''
 ].filter(Boolean).join(' · ');
 const classFilter='<label class="magic-learn-filter"><span>Filtra per classe</span>'+
   '<select id="spell-learn-filter" aria-label="Filtra per classe">'+
   spellLearningFilterOptions()+'</select></label>';
 const chosenLevel=Number(state.magicSlotLevel);
 const chosenPact=Boolean(state.magicSlotPact);
 const chosenSlot=chosenPact?calculated.pact_slots:
   (calculated.spell_slots||[]).find(slot=>Number(slot.level)===chosenLevel);
 const maximum=Math.max(0,Number(chosenSlot?.total)||0);
 const spent=Math.max(0,Number(chosenSlot?.spent)||0);
 const label=(chosenPact?'Slot del Patto':'Slot di livello '+chosenLevel);
 const castable=sessionSpellEntries(c,calculated,state.spellCatalog||[]).filter(spell=>{
   const info=magicSpellInfo(spell);
   if(info.level===null||info.level<1||info.level>chosenLevel)return false;
   if(!spell.grant_id)return true;
   const grant=(calculated.origin_spells||[]).find(row=>row.id===spell.grant_id);
   const mode=grant?.payment_mode||(grant?.tracker_id?'tracker':
     ['known','prepared'].includes(grant?.mode)?'slot':'free');
   return mode==='slot'||grant?.slot_alternative===true;
 });
 const slotSpells='<section class="magic-slot-spells"><h3>Incantesimi lanciabili</h3>'+
   '<p class="magic-editor-help">Livello '+chosenLevel+' o inferiore. Il lancio conferma lo slot nella schermata dell’incantesimo.</p>'+
   (castable.length?groupedMagicSpells(castable.map(spell=>({spell,info:magicSpellInfo(spell)})),({spell,info})=>{
     const index=availableSpells(c).findIndex(row=>spellId(row)===spell.id);
     const attrs=' data-act="power-spell" data-spell-key="'+(spell.grant_id?'origin':'prepared_spells')+'"'+
       (spell.grant_id?' data-grant-id="'+esc(spell.grant_id)+'"':
         ' data-spell-index="'+index+'" data-casting-class="'+esc(spell.casting_class||'manual')+'"');
     return '<div class="magic-slot-castable"><button type="button" class="magic-slot-spell-name"'+attrs+
       ' aria-label="Dettagli di '+esc(info.name)+'">'+esc(info.name)+'</button>'+
       '<button type="button" class="magic-slot-cast-button"'+attrs+
       ' aria-label="Lancia '+esc(info.name)+' con lo slot scelto">Lancia</button></div>';
   }):'<p class="hint">Nessun incantesimo lanciabile con questo slot.</p>')+'</section>';
 const slotMenu='<div class="magic-slot-popup"><p class="magic-slot-popup-count">'+
   esc(label)+' · <strong>'+Math.max(0,maximum-spent)+' / '+maximum+'</strong> disponibili</p>'+
   '<div class="magic-slot-popup-actions">'+
   '<button type="button" class="btn" data-act="slot-use" data-level="'+(chosenPact?0:chosenLevel)+'"'+
   (spent>=maximum?' disabled':'')+'>Consuma uno slot</button>'+
   '<button type="button" class="btn" data-act="slot-recover" data-level="'+(chosenPact?0:chosenLevel)+'"'+
   (spent<=0?' disabled':'')+'>Ripristina uno slot</button></div>'+
   slotSpells+'</div>';
 const views={
  'slot-menu':[label,slotMenu],
  concentration:['Concentrazione',concentration],
  slots:['Slot · Classi / Patto',slots],
  catalog:['Prepara incantesimi',''],
  learn:['Impara nuovi incantesimi',''],
  choices:['Scelte dalle origini',originChoicesView(calculated)||'<p class="hint">Nessuna scelta di incantesimi in sospeso.</p>']
 };
 if(!views[kind])return '';
 const [title,content]=views[kind];
 if(kind==='learn'||kind==='catalog'){
  // Both spell stages reuse the same picker as infusions, styles and maneuvers.
  return '<dialog id="magic-tools-dialog" class="sheet-roll-dialog magic-tools-dialog benefit-selection-dialog" aria-label="'+esc(title)+'">'+
   learningSelectionDialogBody({
    title,closeAction:'magic-tool-close',summary:selectionSummary,
    filters:classFilter,searchLabel:'Cerca incantesimo',
    searchAttribute:'id="spell-search" value="'+esc(state.spellQuery)+'"',
    resultsId:'spell-results',resultsClass:'learning-picker-results',
    results:renderSpellResults(),footer:false
   })+'</dialog>';
 }
 return '<dialog id="magic-tools-dialog" class="sheet-roll-dialog magic-tools-dialog" aria-label="'+esc(title)+'">'+
   '<div class="magic-tools-head"><h2>'+esc(title)+'</h2>'+
   dialogCloseButton('magic-tool-close','Chiudi '+title,'magic-tool-close')+'</div>'+
   '<div class="magic-tools-body">'+content+'</div></dialog>';
}
function magicSpellInfo(row){
  const id=spellId(row);
  const definition=(state.spellCatalog||[]).find(spell=>spell.id===id);
  const record=typeof row==='object'&&row?row:{};
  const rawLevel=definition?.level??record.level;
  const level=rawLevel===undefined||rawLevel===null?null:Number(rawLevel);
  return {id,name:text(definition?.name||record.name||(typeof row==='string'?row:id)),
    level:Number.isInteger(level)&&level>=0&&level<=9?level:null,
    internal_grant:definition?.internal_grant===true||record.internal_grant===true};
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
      (level===0?(entries.length&&entries.every(row=>row.info.internal_grant)?'Capacità':'Trucchetti'):level===null?'Livello non disponibile':'Livello '+level)+'</h4>'+badges+'</div>'+
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
     (mode==='tracker'?'<label>Slot alternativi<select data-origin-config="slot_alternative" data-grant-id="'+esc(grant.id)+'">'+
       [['false','Non consentiti'],['true','Consentiti']].map(([value,label])=>
         '<option value="'+value+'"'+(String(Boolean(grant.slot_alternative))===value?' selected':'')+'>'+label+'</option>').join('')+'</select></label>':'')+
     (grant.source_choice_id?'<button class="btn small" data-act="origin-choice-remove" data-grant-id="'+esc(grant.id)+'">Cambia scelta</button>':'')+
     '</details></div>';
 };
 if(!forBattle)return originSpellSections(c,calculated,configured);
 const sortGroups=(a,b)=>a[1].name.localeCompare(b[1].name,'it',{sensitivity:'base'});
 // A tracker must have a popup even when it has no spells or activated abilities.
 if(forBattle)for(const tracker of calculated.trackers||[]){
   if(!tracker.disabled)ensureResource('tracker:'+tracker.id,tracker.name,tracker);
 }
 for(const grant of calculated.origin_spells||[]){
   const spell=(state.spellCatalog||[]).find(s=>s.id===grant.spell_id);
   const info=magicSpellInfo(spell||{id:grant.spell_id,name:grant.spell_id});
   const mode=grant.payment_mode||(grant.tracker_id?'tracker':(['known','prepared'].includes(grant.mode)?'slot':'free'));
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
     if(!stats.has(origin)&&!item.grant.casting_ability_not_required)stats.set(origin,{name:item.grant.origin_name||'Origine',ability:item.grant.spellcasting_ability||'int',allowed:item.grant.spellcasting_ability_options?.length?item.grant.spellcasting_ability_options:[item.grant.spellcasting_ability||'int']});
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
       const extensions=effectExtensionsFor(calculated.effect_extensions,{kind:'ability',id:ability.id,name:ability.name});
       const cost=Math.max(0,Number(ability.resource_cost)||0),resource=ability.tracker_name||ability.resource_name||group.tracker?.name||'';
       return '<details class="magic-ability-entry power-privilege" data-ability-id="'+esc(ability.id)+'"'+(group.abilities.length===1?' open':'')+'><summary><span class="power-privilege-title"><span class="magic-ability-name">'+esc(ability.name)+'</span><span class="power-privilege-meta">'+esc(activation)+(cost?' · '+cost+' per uso':'')+'</span></span><span class="power-privilege-chevron" aria-hidden="true">⌄</span></summary>'+
         '<div class="magic-ability-detail"><dl class="power-privilege-facts"><div><dt>Origine</dt><dd>'+esc(ability.origin_name||ability.origin||'Origine non specificata')+'</dd></div>'+
         (ability.source?'<div><dt>Fonte</dt><dd>'+esc(ability.source)+'</dd></div>':'')+
         '<div><dt>Consumo</dt><dd>'+esc(cost?cost+' utilizzi'+(resource?' · '+resource:' · Risorsa non collegata'):'Nessun consumo di utilizzi')+'</dd></div></dl>'+
         '<div class="power-privilege-description"><h3>Descrizione</h3><p class="trait-description">'+esc(ability.description||'Descrizione non disponibile.')+'</p></div>'+
         (ability.area_shape?'<p class="hint">'+esc(ability.area_shape==='line'?
           'Linea '+ability.area_length_feet+' × '+ability.area_width_feet+' ft':
           'Cono '+ability.area_radius_feet+' ft')+
           (ability.damage_formula?' · '+esc(ability.damage_formula)+' '+esc(ability.damage_type):'')+
           (ability.attack_replacement?' · Sostituisce un attacco':'')+'</p>':'')+
         (ability.persistent_key&&c.active_class_features?.[ability.persistent_key]?
           '<div class="magic-active-form">'+(ability.duration_rounds===1?'Attivo · fino al prossimo turno':'Attivo · 1 minuto')+' <button type="button" class="btn small" data-act="condition-remove-ability" data-ability-key="'+esc(ability.persistent_key)+'">Termina</button></div>':'')+
         (extensions.length?'<div class="magic-effect-extensions"><h3>Estensioni attive</h3><ul>'+
           extensions.map(extension=>'<li><strong>'+esc(extension.origin_name||'Privilegio')+'</strong> · '+
             esc(effectExtensionLabel(extension,{cha_mod:calculated.abilities?.cha?.modifier}))+'</li>').join('')+
           '</ul></div>':'')+
         '<div class="actions">'+(ability.descriptive_only?'':'<button type="button" class="btn primary" data-act="battle-use-ability" data-ability-id="activated:'+esc(ability.id)+'"'+
         (ability.persistent_key&&c.active_class_features?.[ability.persistent_key]?' disabled':'')+'>Usa</button>')+
         '<button type="button" class="play-button power-origin-link" data-act="power-trait" data-origin-id="'+esc(ability.feature_id||ability.origin_id||'')+'">'+actionGlyph('proficiency')+'<span>Apri il tratto di origine</span></button></div></div></details>';
       }).join('')+'</div>':'';
   const activeForm=calculated.active_celestial_form;
   const ending=activeForm&&group.spells.some(row=>row.grant.spell_id===activeForm.spell_id)?
     '<div class="magic-active-form">Manifestazione attiva <button type="button" class="btn small" data-act="end-racial-power">Termina</button></div>':'';
   const popup=panel(group.name,header+ending+[...stats.entries()].map(([origin,meta])=>
     '<div class="magic-source-ability"><span class="hint">'+esc(meta.name)+'</span>'+
     castingStatistics(c,'origin:'+origin,meta.ability,meta.allowed)+'</div>').join('')+
     spellRows+abilityRows,'magic-panel magic-tracker-panel');
   return forBattle?'<div data-battle-power-group="'+esc(key)+'">'+popup+'</div>':popup;
 }).join('');
 return resourcePanels;
}
function originChoicesView(calculated){
 const choices=(calculated.origin_choices||[]).filter(choice=>choice.remaining>0)
   .sort((a,b)=>Number(b.id===state.pendingSpellChoiceId)-Number(a.id===state.pendingSpellChoiceId));
 if(!choices.length)return '';
 return panel('Scelte da origini',choices.map(choice=>{
  const eligible=spellsForEdition(state.spellCatalog||[],state.editor.read().rules_version||'2014');
  const offered=eligible.filter(spell=>originChoiceMatches(choice,spell).matches&&!choice.selected.some(selected=>selected.spell_id===spell.id));
  const supported=(state.spellCatalog||[]).some(spell=>originChoiceMatches(choice,spell).supported);
  return '<article class="native-entry pending-spell-choice'+(choice.id===state.pendingSpellChoiceId?' is-target':'')+
   '" data-pending-spell-choice="'+esc(choice.id)+'"><h3>'+esc(choice.origin_name)+' · Scegli ancora '+choice.remaining+'</h3><p class="hint">'+esc(choice.filters?.join(' oppure ')||choice.filter||'Elenco della concessione')+'</p>'+
   (choice.casting_ability_unresolved?'<p class="hint">Completa prima la caratteristica magica del talento da cui dipende questa concessione.</p>':offered.length?'<label>Incantesimo<select data-origin-choice="'+esc(choice.id)+'">'+groupedMagicOptions(offered)+'</select></label><label>Caratteristica<select data-choice-ability="'+esc(choice.id)+'">'+(choice.spellcasting_ability?'':'<option value="">Scegli…</option>')+Object.entries(abilities).filter(([key])=>!choice.spellcasting_ability_options?.length||choice.spellcasting_ability_options.includes(key)).map(([key,label])=>'<option value="'+key+'" '+(key===choice.spellcasting_ability?'selected':'')+'>'+label+'</option>').join('')+'</select></label><button class="btn" data-act="origin-choice-pick" data-choice-id="'+esc(choice.id)+'">Conferma scelta</button>':
     '<p class="hint">'+(supported?'Nessun incantesimo disponibile nel catalogo locale per questa concessione.':'Questa concessione richiede un filtro non ancora supportato; la scelta rimane salvata e visibile.')+'</p>')+'</article>';
 }).join(''));
}
function manualMagicSources(c,calculated){
  const groups=new Map(),classes=calculated.casting_classes||[];
  for(const spell of availableSpells(c)){
    if(castingSources(spell,classes,state.spellCatalog||[]).some(id=>
      classes.some(member=>member.id===id)))continue;
    const origin=String(spell?.origin_id||spell?.origin_name||'manual');
    if((calculated.origin_spells||[]).some(grant=>grant.spell_id===spellId(spell)&&
      String(grant.origin_id||'manual')===origin))continue;
    if(!groups.has(origin)){
      const known=calculated.origins?.find(row=>row.id===origin);
      groups.set(origin,{name:spell?.origin_name||known?.name||
        (origin==='manual'?'Aggiunti manualmente':origin),ability:spell?.spellcasting_ability||
        c.spellcasting_ability||classes[0]?.ability||'int'});
    }
  }
  return [...groups.entries()].sort((a,b)=>a[1].name.localeCompare(b[1].name,'it',{sensitivity:'base'}))
    .map(([id,meta])=>'<section class="magic-source magic-manual-source">'+
      '<header class="magic-source-header"><div class="magic-source-title"><h3>'+esc(meta.name)+'</h3>'+
      castingStatisticsToggle(c,id==='manual'?'manual':'origin:'+id)+'</div></header>'+
      (castingStatisticsVisible(c,id==='manual'?'manual':'origin:'+id)?
        castingStatistics(c,id==='manual'?'manual':'origin:'+id,meta.ability):'')+
      spellList(c,'prepared_spells','manual',classes,{originId:id,includeSlots:false})+'</section>').join('');
}
function spellList(c,key,classId=null,classes=[],{includeSlots=true,originId=null,minLevel=0}={}) {
  const rows=key==="prepared_spells"?availableSpells(c):
    Array.isArray(c[key])?c[key]:[];
  const member=classes.find(row=>row.id===classId);
  const autoCantrips=key==='prepared_spells'&&member?.mode==='Preparati'&&minLevel===0?
    knownClassCantripIds(c,member,state.spellCatalog||[]):new Set();
  const visible=rows.map((spell,i)=>({spell,i,info:magicSpellInfo(spell)}))
    .filter(({spell,info})=>info.level===null||info.level>=minLevel)
    .filter(({spell})=>(!classId||
      (classId==='manual'?!castingSources(spell,classes,state.spellCatalog||[]).some(id=>classes.some(member=>member.id===id)):
        castingSources(spell,classes,state.spellCatalog||[]).includes(classId)))&&
      (originId===null||String(spell?.origin_id||spell?.origin_name||'manual')===originId)&&
      !(classId==='manual'&&(state.calculated?.origin_spells||[]).some(grant=>grant.spell_id===spellId(spell)&&
        String(grant.origin_id||'manual')===String(spell?.origin_id||spell?.origin_name||'manual'))));
  const visibleIds=new Set(visible.map(({spell})=>spellId(spell)));
  for(const id of autoCantrips){
    if(visibleIds.has(id))continue;
    const spell=(state.spellCatalog||[]).find(row=>spellId(row)===id);
    if(spell&&Number(spell.level)===0)visible.push({spell,i:-1,info:magicSpellInfo(spell)});
  }
  return groupedMagicSpells(visible,({spell,i,info})=>{
    const auto=autoCantrips.has(spellId(spell))&&info.level===0;
    const attrs=auto?' data-spell-id="'+esc(spellId(spell))+'" data-casting-class="'+esc(classId||'')+'"':
      ' data-spell-key="'+esc(key)+'" data-spell-index="'+i+'" data-casting-class="'+esc(classId||'')+'"';
    return '<div class="magic-spell-row"><button type="button" class="magic-spell-open" data-act="power-spell"'+attrs+
      ' aria-label="Apri '+esc(info.name)+'">'+esc(info.name||'Incantesimo senza nome')+'</button>'+
      (auto?'<span class="magic-known-cantrip-label">Conosciuto</span>':
        '<button type="button" class="btn small magic-remove-spell" data-act="remove-spell" data-key="'+esc(key)+'" data-class-id="'+esc(classId||'')+'" data-index="'+i+'" title="Rimuovi" aria-label="Rimuovi '+esc(info.name)+'">×</button>')+
      '</div>';
  },{slotSummary:includeSlots&&key==='prepared_spells'?magicSlotSummary(state.calculated):null});
}
function spellSelectionWarning(member,count){
 const warnings=classSelectionWarnings(member,count);
 return warnings.length?'<p class="magic-selection-warning" role="status">⚠ '+esc(warnings.join(' · '))+'</p>':'';
}
function renderSpellResults(){
  const rows=state.spellCatalog||[],record=state.editor?.read()||{};
  if(!rows.length)return '<p class="hint">'+(state.spellScopedLoading||
    fullSpellCatalogRequest?'Caricamento degli incantesimi disponibili…':
    'Catalogo non disponibile. Gli incantesimi già salvati restano utilizzabili.')+'</p>';
  const query=state.spellQuery.trim();
  const classes=state.calculated?.casting_classes||[];
  const member=classes.find(row=>row.id===state.spellClass);
  const learning=state.magicPopup==='learn'&&Boolean(member);
  const target='prepared_spells';
  const preparing=member?.mode==='Preparati'&&target==='prepared_spells'&&!learning;
  if(!member&&!query)return '<p class="hint">Cerca un incantesimo per aggiungerlo alle concessioni della scheda.</p>';
  const prepared=availableSpells(record);
  const known=knownClassSpellIds(record,member,rows);
  const granted=new Map((state.calculated?.origin_spells||[]).filter(row=>row.spell_id)
    .map(row=>[String(row.spell_id),row]));
  const selected=new Set(prepared.filter(row=>!member||castingSources(row,classes,rows).includes(member.id)).map(spellId));
  const allowed=new Set(spellsForEdition(rows,record.rules_version||'2014'));
  const filterClass=String(state.spellLearnFilter||'all').toLowerCase();
  const matchesClassFilter=spell=>filterClass==='all'||
    (filterClass===String(member?.spell_list_class_name||member?.name||'').toLowerCase()&&spellEligible(spell,member))||
    (Array.isArray(spell.classes)?spell.classes:[]).some(name=>
      String(typeof name==='string'?name:name?.name).toLowerCase()===filterClass);
  const filtered=rows.filter(spell=>allowed.has(spell)&&!spell.internal_grant&&
    (preparing?Number(spell.level)>0&&Number(spell.level)<=member.max_level&&
        (known.has(spell.id)||granted.has(spell.id)):
      learning?Number(spell.level)<=member.max_level:
      !member||spellEligible(spell,member))&&
    matchesClassFilter(spell)&&
    matchesSearch(query,spell.name,spell.source))
    .sort((a,b)=>Number(a.level||0)-Number(b.level||0)||
      String(a.name||'').localeCompare(String(b.name||''),'it',{sensitivity:'base'}));
  const {items:found,shown,total}=pageResults(filtered,state.spellResultLimit);
  if(!found.length)return '<p class="hint">'+(preparing?
    'Nessun incantesimo conosciuto corrispondente. Puoi impararne altri con Impara incantesimi.':
    'Nessun incantesimo corrispondente.')+'</p>';
  return groupedMagicSpells(found.map(spell=>({spell,info:magicSpellInfo(spell)})),({spell,info})=>{
    const already=selected.has(spell.id);
    const preparedIndex=prepared.findIndex(row=>spellId(row)===spell.id&&
      (!member||castingSources(row,classes,rows).includes(member.id)));
    const details=preparedIndex>=0?
      ' data-spell-key="prepared_spells" data-spell-index="'+preparedIndex+
      '" data-casting-class="'+esc(member?.id||'manual')+'"':
      ' data-spell-id="'+esc(spell.id)+'"';
    const name='<button type="button" class="magic-catalog-name" data-act="power-spell"'+details+
      ' aria-label="Dettagli di '+esc(info.name)+'">'+esc(info.name)+'</button>';
    // Shared row template; the current selection stage controls the action.
    const owned=learning?known.has(spell.id):already;
    const grant=preparing?granted.get(spell.id):null;
    const label=learning?'+ Impara':member?'+ Prepara':'+ Aggiungi';
    return '<div class="magic-catalog-row vtt-selectable'+(owned?' is-selected':'')+'">'+name+
      (owned||grant?alreadyOwnedOptionNotice:
        '<button class="magic-catalog-action" type="button" aria-pressed="false" data-act="'+
        (learning?'spell-known-toggle':'spell-pick')+'"'+
        (learning?' data-spell-index="'+rows.indexOf(spell)+'" data-known="false" data-class-id="'+esc(member.id)+'"':
          ' data-index="'+rows.indexOf(spell)+'"')+
        ' aria-label="'+esc(label.slice(2)+' '+info.name)+'">'+esc(label)+'</button>')+
      '</div>';
  })+resultsFooter('spell-results-more',shown,total,60);
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
    '<label>Numero dadi<input id="die-count" type="number" min="1" max="20" value="1" required></label>'+
    '<label>Modificatore<input id="die-mod" type="number" min="-999" max="999"></label></div>'+
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
  openDialog(dlg);
}

// Activity belongs to the local archive, not to the life of a network session.
// Server echoes have the same IDs and are folded into the displayed timeline.
const LOCAL_CHAT_KEY='vtt-sheet-chat-history-v1';
let localChatWrite=Promise.resolve();
function redrawChatEvents(){
 const container=document.querySelector('#events');
 if(container){container.innerHTML=renderEvents();container.scrollTop=container.scrollHeight;}
}
function rememberChatEvent(event,{send=false}={}){
 if(!event?.id||state.localMessages.some(row=>row.id===event.id))return;
 state.localMessages.push(event);
 state.localMessages=state.localMessages.slice(-250);
 const snapshot=state.localMessages.slice();
 localChatWrite=localChatWrite.catch(()=>{}).then(()=>setting(LOCAL_CHAT_KEY,snapshot))
  .catch(error=>console.warn('Cronologia chat locale non salvata',error));
 redrawChatEvents();
 if(send&&state.paired&&state.online){
  locallySentEventIds.add(event.id);
  // Local writes must never depend on the desktop or block the sheet autosave.
  void action('chat_send',{event}).then(result=>{
   if(!result.ok)throw Error(result.error||'Evento non inviato');
  }).catch(error=>console.warn('Evento conservato solo in locale:',error));
 }
}
function sheetActivityAuthor(record){
 return String(record?.name||state.editor?.read()?.name||'Giocatore').slice(0,80);
}
function recordSheetAction(text,record=null){
 const body=String(text||'').trim();
 if(!body)return;
 rememberChatEvent({id:'pwa_'+crypto.randomUUID(),kind:'action',author:sheetActivityAuthor(record),
  timestamp:Math.floor(Date.now()/1000),text:body.slice(0,1000)},{send:true});
}
function recordSheetChange(before,after,requested){
 const changes=describeSheetActivity(before,after,requested);
 if(changes.length)recordSheetAction(changes.join(' · '),after);
}

function chatView(){
  return panel("Chat della partita",
    '<div class="row between chat-toolbar"><span class="chat-caption">'+
    (state.paired&&state.online?'Messaggi e tiri della partita · registro locale attivo':
      'Registro locale · le azioni restano visibili anche senza partita')+
    '</span>'+(notificationsSupported()?'<button type="button" class="btn chat-notify-toggle" data-act="toggle-chat-notifications" aria-label="Notifiche chat" title="Notifiche di sistema (mentre la PWA è attiva)">'+(notificationsEnabled()?'🔔 Attive':Notification.permission==='default'?'🔔 Autorizza':'🔕 Notifiche')+'</button>':'')+'<button type="button" class="btn chat-dice-trigger" data-act="open-chat-dice" aria-label="Apri lanciadadi" title="Lancia i dadi">🎲</button></div>'+
    '<div id="events" class="scroll-y" aria-live="polite">'+renderEvents()+'</div>'+
    '<form id="chat-form" class="stack" autocomplete="off">'+
    '<label>Scrivi come <select id="chat-author"><option value=""'+(!state.chatAuthor?' selected':'')+'>Giocatore</option>'+
    (state.cachedCreatures||[]).map(x=>'<option value="'+esc(x.name)+'"'+(state.chatAuthor===x.name?' selected':'')+'>'+esc(x.name)+'</option>').join("")+
    '</select></label><label>Messaggio<textarea id="chat-message" rows="2" maxlength="1000" placeholder="Messaggio o nota locale…" required></textarea></label>'+
    '<button type="submit" class="btn primary full">'+(state.paired&&state.online?'Invia messaggio':'Aggiungi alla chat locale')+'</button></form>');
}
function renderEvents(){
  const all=new Map();
  for(const event of [...state.messages,...state.localMessages])if(event?.id)all.set(event.id,event);
  const rows=[...all.values()].sort((a,b)=>(Number(a.timestamp)||0)-(Number(b.timestamp)||0)).slice(-80);
  return rows.length?rows.map(e=>
    '<article class="event"><div class="meta"><strong>'+esc(e.author||"Giocatore")+'</strong><span>'+
    esc(e.kind==="roll"?"Dadi":e.kind==="action"?"Azione":"Chat")+'</span></div>'+
    '<div class="body">'+esc(e.kind==="roll" ? ((e.label||e.die||"Tiro")+": "+e.total) :
      (e.text||""))+(e.kind==="roll"&&e.detail?'<div class="hint roll-event-detail">'+esc(e.detail)+'</div>':'')+
      '</div></article>').join("") :
    '<p class="hint">Nessun evento recente. Le azioni della scheda saranno registrate qui anche offline.</p>';
}
function sessionTokenDetails(token) {
  const edition=token.rules_version==="2024"?"2024":"2014";
  const conditionNames=Array.isArray(token.conditions)?[...new Set(token.conditions)].filter(Boolean).map(id=>{
    const row=(state.conditionCatalog?.editions?.[edition]||[]).find(item=>item.id===id);
    return conditionLabel(id,row?.name||"");
  }):[];
  const activeHitEffects=(Array.isArray(token.hit_effects)?token.hit_effects:[])
    .filter(effect=>!hitEffectExpired(effect,state.map));
  const attackEffects=activeHitEffects.map(effect=>
    String(effect.attack_name||'Attacco')+' · '+
    (effect.operation==='roll_mode'?effect.mode==='disadvantage'?'Svantaggio ai tiri per colpire':'Vantaggio ai tiri per colpire':
      effect.condition_id||'Condizione')+
    (effect.source_name?' · '+effect.source_name:''));
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
    (attackEffects.length?'<span class="session-status-line" title="'+esc(attackEffects.join(", "))+'">Effetti attacchi: '+esc(attackEffects.join(" · "))+'</span>':'')+
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
  const unavailable=state.sessionCreatureErrors.length?
    '<p class="warning" role="status" data-session-creature-errors>Schede non disponibili in Partita: '+
      esc(state.sessionCreatureErrors.map(row=>row.name).join(', '))+'. Le altre creature restano utilizzabili.</p>':'';
  return header('Al tavolo','La tua partita','Il tavolo condiviso, sempre a portata di mano.')+unavailable+
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
      html+='<dialog id="session-token-dialog" class="session-dialog" aria-label="Modifica token"><header class="vtt-popup-heading"><h2>⚙ '+esc(edited.name)+'</h2>'+dialogCloseButton('close-token-dialog','Chiudi','')+'</header>'+
        '<h3>Condizioni</h3>'+conditionGrid(edited.conditions,'data-token-condition',edited.rules_version||linked?.rules_version)+
        '<h3>Incantesimi applicati</h3>'+ (active||'<p class="hint">Nessun incantesimo attivo.</p>')+
        '<label class="vtt-list-search">Cerca incantesimo<input id="token-spell-query" type="search" placeholder="Nome incantesimo"></label>'+
        '<label>Incantesimo<select id="token-spell-select"></select></label>'+
        '<button type="button" class="btn small" data-act="apply-token-spell">＋ Applica incantesimo</button>'+
        '<h3>Miniatura</h3>'+
        (linked?''+
          '<label class="vtt-list-search">Cerca miniatura<input id="token-mini-query" type="search" placeholder="Nome miniatura"></label>'+
          '<label>Miniatura<select id="token-mini-select"></select></label>'+
          '<button type="button" class="btn small" data-act="apply-token-appearance">Applica miniatura</button>':
          '<p class="hint">La miniatura può essere cambiata dal dispositivo che controlla la scheda collegata.</p>')+
        '<div class="session-dialog-footer"><button type="button" class="btn" data-act="close-token-dialog">Chiudi</button></div></dialog>';
    }
  }
  html+='<dialog id="session-place-dialog" class="session-dialog" aria-label="Aggiungi token"><header class="vtt-popup-heading"><h2>Aggiungi token</h2>'+dialogCloseButton('close-place-dialog','Chiudi','')+'</header>'+
    '<label>La tua scheda<select id="place-creature">'+(state.cachedCreatures||[]).map(c=>
      '<option value="'+esc(c.id)+'">'+esc(c.name)+'</option>').join('')+'</select></label>'+
    '<label>Accanto al token<select id="place-reference">'+entries.map(t=>
      '<option value="'+esc(t.id)+'" '+(t.id===state.tokenId?'selected':'')+'>'+esc(t.name)+'</option>').join('')+'</select></label>'+
    '<label>Direzione<select id="place-direction"><option value="north">Nord</option><option value="east">Est</option><option value="south">Sud</option><option value="west">Ovest</option></select></label>'+
    '<div class="session-dialog-footer"><button class="btn primary" type="button" data-act="place-creature">Piazza token</button>'+
    '<button class="btn" type="button" data-act="close-place-dialog">Annulla</button></div></dialog>';
  return sessionLayout(html,desktop);
}

function openSessionDialog(dialog) { openDialog(dialog); }
function closeSessionDialog(dialog) { closeDialog(dialog); }
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
            await refreshSessionCreatures();
          }else if(state.page==='library'&&!state.libraryMode&&
            changed.includes(state.creatureId)){
            if(!state.editor||!app.querySelector('#sheet-play-view')){
              state.sheetNeedsRefresh=true;
            }else if(!app.contains(document.activeElement)||
                     document.activeElement.tagName==='BUTTON'){
              await render();
            }else{
              state.calculated=await computeLocalData(state.editor.read());
              refreshCalculatedValues(app,state.calculated);
            }
          }else if(state.page==='library'&&state.libraryMode){
            await render();
          }
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
async function refreshSharedCatalog(kind){
  state.cachedCreatures=readableArchiveCreatures(await listCreatures());
  await refreshCharacterHomebrewOptions();
  if(state.page==='catalog'){
    state.catalogSelected=-1;
    await render();
  }else if(state.page==='library'&&state.libraryMode)await render();
  else if(kind==='inventory'&&state.page==='library'&&!state.libraryMode){
    state.inventorySelectedIndices.clear();state.editor=null;await render();
  }
}
function startChat() {
  ++chatGeneration;
  clearInterval(state.pollChat);
  fetchChat();
  void pollIncomingShares(state.paired&&state.online,refreshSharedCatalog,message);
  state.pollChat=setInterval(()=>{ if(state.paired){fetchChat();void pollIncomingShares(state.online,refreshSharedCatalog,message);} },2500);
}
function randomDie(sides) {
  const range=0x100000000;
  const ceiling=Math.floor(range/sides)*sides;
  const values=new Uint32Array(1);
  do { crypto.getRandomValues(values); } while(values[0]>=ceiling);
  return 1+(values[0]%sides);
}
async function roll(sides) {
  const count=number(document.querySelector("#die-count")?.value||1,1);
  const modifier=number(document.querySelector("#die-mod")?.value,0);
  if(!Number.isInteger(count)||count<1||count>20||!Number.isInteger(modifier)||
     modifier < -999 || modifier > 999) throw new Error("Controlla il numero di dadi e il modificatore.");
  const rolls=Array.from({length:count},()=>randomDie(sides));
  const total=rolls.reduce((a,b)=>a+b,modifier);
  const notation=count+"d"+sides+(modifier<0?String(modifier):modifier?"+"+modifier:"");
  state.roll={sides,count,modifier,rolls,total,notation,detail:rolls.join(" + ")+
    (modifier?(" "+(modifier>0?"+ ":"− ")+Math.abs(modifier)):"")};
  state.rollHistory.unshift(state.roll);
  state.roll.chatStatus=state.paired&&state.online?'Invio in chat…':'Tiro registrato nella chat locale.';
  const feedback=document.querySelector("#dice-feedback");if(feedback)feedback.innerHTML=diceResult();
  const currentRoll=state.roll;
  try{
    await shareRoll({quiet:true});
    currentRoll.chatStatus=state.paired&&state.online?'✓ Inviato in chat':'✓ Salvato nella chat locale';
    if(state.paired&&state.online)await fetchChat();
  }catch(error){
    currentRoll.chatStatus='Tiro locale salvato · invio chat fallito: '+errorMessage(error);
  }
  if(state.roll===currentRoll&&feedback)feedback.innerHTML=diceResult();
}
async function shareRoll({quiet=false,roll=null}={}) {
  if(!roll&&!state.roll) return;
  const r=roll||state.roll;
  const event={id:"pwa_"+crypto.randomUUID(),kind:"roll",author:String(r.author||state.editor?.read()?.name||document.querySelector("#chat-author")?.value||state.chatAuthor||"Giocatore").slice(0,80),
    timestamp:Math.floor(Date.now()/1000),label:r.label||r.notation,
    ...sheetRollChatFields(r)};
  rememberChatEvent(event);
  if(state.paired&&state.online){
    locallySentEventIds.add(event.id);
    const result=await action("chat_send",{event});
    if(!result.ok)throw new Error(result.error||"Tiro non inviato");
    if(!quiet)message("Tiro condiviso nella chat.");
  }else if(!quiet)message("Tiro salvato nella chat locale.");
}
async function patch(patchValue,{syncPresentation=true}={}) {
  if(!state.editor) return;
  const before=state.editor.read();
  const status=document.querySelector("#save-state");
  if(status){ status.textContent="Salvataggio…"; status.classList.remove("error"); }
  try {
    await state.editor.update(patchValue);
    if(patchValue&&Object.hasOwn(patchValue,'inventory'))state.inventorySelectedIndices.clear();
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
    const current=editor.read();
    if(syncPresentation&&['name','current_miniature_id','size_name','footprint'].some(k=>before[k]!==current[k]))
      try{await syncFormPresentation(current);}catch(error){message('Scheda salvata. '+errorMessage(error),true);}
    if(status){ status.textContent="✓ Salvato in locale"; status.classList.remove("error"); }
    // Record only the actual committed difference, never a failed or no-op edit.
    if(state.editor===editor)recordSheetChange(before,editor.read(),patchValue);
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
  if(target.matches?.('[data-hp-autosave]')){
    if(!state.editor)return;
    // Both fields may be dirty while their independent debounce timers run.
    // Snapshot both values together so a delayed writer never restores
    // the old HP or temp HP saved by the other field's writer.
    const record=state.editor.read(),dialog=target.closest('#hp-adjust-dialog'),draft={};
    for(const key of ['current_hp','temporary_hp']){
      const input=dialog?.querySelector('[data-hp-autosave="'+key+'"]');
      const raw=input?.value.trim()||'';
      if(!raw)continue; // An empty intermediate edit is not zero.
      const value=Number(raw);
      const maximum=key==='temporary_hp'?99999:
        Math.max(Number(state.calculated?.stats?.max_hp)||0,Number(record.current_hp)||0);
      if(!Number.isSafeInteger(value)||value<0||value>maximum)
        throw Error('Inserisci PF interi tra 0 e '+maximum+'.');
      draft[key]=value;
    }
    if(Object.entries(draft).some(([key,value])=>value!==Number(record[key]||0)))
      await patch(draft);
    return;
  }
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
  if(target.dataset.itemContainer!==undefined){
    const destination=target.value;
    await patch(moveInventoryItem(creature,Number(target.dataset.itemContainer),destination));
    // Moving an item into a previously hidden section must not close its
    // editor or make the chosen item disappear after the rerender.
    focusInventorySection(state.editor.read(),destination===DEFAULT_INVENTORY_CONTAINER?
      'items':'container:'+destination);
    state.inventoryMenuIndex=-1;await render();return;
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
  if(target.dataset.documentIndex!==undefined){
    await persistDocumentEdit(Number(target.dataset.documentIndex),target.dataset.documentPart,creature);
    return;
  }
  if(target.dataset.equipSlot){
    const slot=target.dataset.equipSlot,index=Number(target.value);
    const special=target.value==='improvised'?'improvised':'none';
    const main=(creature.inventory||[]).find(item=>item.equipped_slots?.includes('main'));
    const mainResolved=main?resolveOwnedItem(main):null;
    const occupied=Boolean(mainResolved&&(
      hasProperty(mainResolved,'2H')||
      creature.hand_grip_two_handed&&hasProperty(mainResolved,'V')));
    if(slot==='off'&&occupied&&creature.hand_off_with_two_handed!==true&&target.value!=='-1')
      throw Error('Mano secondaria occupata.');
    const inventory=equipSlot(creature.inventory||[],slot,special!=='none'?-1:index,
       {allowOffhandWithTwoHanded:creature.hand_off_with_two_handed===true});
    const nextMain=inventory.find(item=>item.equipped_slots?.includes('main'));
    const nextResolved=nextMain?resolveOwnedItem(nextMain):null;
    const nextVersatile=nextResolved&&itemKind(nextResolved)==='weapon'&&hasProperty(nextResolved,'V');
    const grip=Boolean(creature.hand_grip_two_handed&&nextVersatile);
    if(slot==='main'&&grip&&creature.hand_off_with_two_handed!==true)for(const item of inventory)
      item.equipped_slots=(item.equipped_slots||[]).filter(v=>v!=='off');
    await patch({inventory,...(slot==='body'?{}:{['hand_'+slot+'_special']:special}),
      ...(slot==='main'?{hand_grip_two_handed:grip,
        ...(grip&&creature.hand_off_with_two_handed!==true?{hand_off_special:'none'}:{})}:{})});
    await render();return;
  }
  if(target.dataset.reference){
    const category=target.dataset.reference,key=target.dataset.referenceKey;
    if(!['species','subrace','background','class','subclass'].includes(key))throw Error('Riferimento non valido');
    if(target.value==='__current__')return;
    // Race and subrace references share IDs in 5etools. Look up only the
    // rows actually displayed in this picker, never in the entire catalog.
    const rows=availableReferenceRows(creature,key,category,state.referenceCatalogs);
    const selection=rows.find(r=>String(r.id||r.name+'|'+(r.source||''))===target.value);
    if(target.value&&(!selection||!isContentAvailableForRules(selection,creature.rules_version)))throw Error('Riferimento non disponibile per queste regole');
    const selected=selection||{};
    // Adding the first class is a level-up, not a silent reference change.
    if(key==='class'&&!creature.class&&selected.name){
      target.value='';
      await openLevelUpClassDialog({preferredNew:String(selected.id||selected.name+'|'+selected.source),
        suggestedCount:1});return;
    }
    const changes={...referencePatch(creature,key,selected),...(key==="background"?quickGrantPatch(creature,selected):{})};
    const changedClass=key==='class'&&selected.name&&
      (selected.name!==creature.class||selected.source!==(creature.class_source||''));
    const fromTotal=totalClassLevel(creature);
    await patch(changes);
    await render();
    if(changedClass)openLevelUpProgressDialog({className:selected.name,
      classSource:selected.source||'',classIndex:0,fromLevel:0,
      toLevel:Number(rowsFor(state.editor.read(),'classes')[0]?.level)||1,
      fromTotal,toTotal:totalClassLevel(state.editor.read())});
    return;
  }
  if(target.dataset.nativeList){
    const key=target.dataset.nativeList,field=target.dataset.key;
    if(key==='classes'&&field==='level'){
      const previous=rowsFor(creature,'classes')[Number(target.dataset.index)];
      const count=Number(target.value)-Number(previous?.level||1);
      if(previous?.name&&count>0){
        target.value=String(previous.level||1);
        await openLevelUpClassDialog({preferredIndex:Number(target.dataset.index),
          suggestedCount:count});return;
      }
    }
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
    if(!['payment_mode','tracker_id','tracker_cost','slot_alternative'].includes(key)||!state.calculated.origin_spells.some(g=>g.id===id))throw Error('Concessione non disponibile');
    let value=target.value;
    if(key==='tracker_cost'){value=Number(value);if(!Number.isInteger(value)||value<1||value>999)throw Error('Costo da 1 a 999');}
    if(key==='payment_mode'&&!['free','slot','tracker'].includes(value))throw Error('Consumo non valido');
   if(key==='slot_alternative'){
      value=value==='true';
      const grant=state.calculated.origin_spells.find(g=>g.id===id);
      if(value&&(!grant?.tracker_id||grant.payment_mode!=='tracker'))
        throw Error('Gli slot alternativi richiedono un incantesimo con tracker.');
    }
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
    if(target.value&&(!selected||!isContentAvailableForRules(selected,creature.rules_version)))throw Error('Riferimento non disponibile per queste regole');
    const index=Number(target.dataset.index);
    const previous=rowsFor(creature,'classes')[index];
    const changedClass=target.dataset.nativePick==='classes'&&target.dataset.key==='name'&&selected?.name&&
      (selected.name!==previous?.name||selected.source!==previous?.source);
    if(changedClass&&!previous?.name){
      target.value='';
      await openLevelUpClassDialog({preferredNew:String(selected.id||selected.name+'|'+selected.source),
        suggestedCount:1});return;
    }
    await patch(rowReferencePatch(creature,target.dataset.nativePick,index,target.dataset.key,selected));
    await render();
    return;
  }
  if(target.dataset.castingSection){
    if(!Object.hasOwn(abilities,target.value))throw Error('Caratteristica non valida');
    const section=target.dataset.castingSection;
    if(section.startsWith('origin:')){
      const source=section.slice(7);
      const grants=(state.calculated?.origin_spells||[]).filter(row=>row.origin_id===source);
      const allowed=grants[0]?.spellcasting_ability_options;
      if(Array.isArray(allowed)&&allowed.length&&!allowed.includes(target.value))
        throw Error('Caratteristica non ammessa da questo tratto.');
      if(grants.length&&(!allowed||!allowed.length)&&grants[0].spellcasting_ability&&
        grants[0].spellcasting_ability!==target.value)
        throw Error('La caratteristica di questo tratto è fissa.');
    }
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
    if(key==='current_hp'&&value<0&&variantOwns(state.editor.readBase(),'hp')){
      await patch({current_hp:0});await render();
      promptVariantOverflow(creature.id,creature.current_form_id,-value);return;
    }
    if(key==='armor_speed_limit_enabled'){
      await patch({armor_speed_limit_enabled:Boolean(value)});
      await render();return;
    }
    if(key==='hand_grip_two_handed'){
      const main=(creature.inventory||[]).find(item=>item.equipped_slots?.includes('main'));
      const usable=main&&itemKind(main)==='weapon'&&hasProperty(resolveOwnedItem(main),'V');
      if(!usable)throw Error('Nessuna arma versatile nella mano principale.');
      const inventory=structuredClone(creature.inventory||[]);
      if(value&&creature.hand_off_with_two_handed!==true)for(const item of inventory)
         item.equipped_slots=(item.equipped_slots||[]).filter(slot=>slot!=='off');
      await patch({hand_grip_two_handed:value,...(value&&creature.hand_off_with_two_handed!==true?
         {inventory,hand_off_special:'none'}:{})});
      await render();return;
    }
    if(key==='hand_off_with_two_handed'){
       const inventory=structuredClone(creature.inventory||[]);
       const main=inventory.find(item=>item.equipped_slots?.includes('main'));
       const mainResolved=main?resolveOwnedItem(main):null;
       const occupied=Boolean(mainResolved&&(
         hasProperty(mainResolved,'2H')||
         creature.hand_grip_two_handed&&hasProperty(mainResolved,'V')));
       if(!value&&occupied)for(const item of inventory)
         item.equipped_slots=(item.equipped_slots||[]).filter(slot=>slot!=='off');
       await patch({hand_off_with_two_handed:Boolean(value),...(!value&&occupied?
         {inventory,hand_off_special:'none'}:{})});
       await render();return;
     }
     if(key==='attack_ability'&&!['str','dex','con','int','wis','cha'].includes(value))
      throw Error('Caratteristica attacchi non valida.');
    if(key==='attack_ability_finesse_only'&&typeof value!=='boolean')
      throw Error('Ambito caratteristica attacchi non valido.');
    if(key==='primary_class_level'){
      const before=Number(rowsFor(creature,'classes')[0]?.level)||1;
      if(Number(value)>before){
        target.value=String(before);
        await openLevelUpClassDialog({preferredIndex:0,suggestedCount:Number(value)-before});
        return;
      }
    }
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
    if(['rules_version','xp','primary_class_level','attack_ability','attack_ability_finesse_only'].includes(key))await render();
     if(key==="name"){
      const title=app.querySelector(".editor-head h1");
      if(title) title.textContent=value;
    }
  } else if(target.dataset.ability){
    const key=target.dataset.ability, value=Number(target.value);
    if(!Number.isInteger(value)||value<1||value>30) throw new Error("Caratteristica da 1 a 30.");
    const modifierChange=key==='con'?await constitutionModifierChange(creature,value):null;
    await patch({abilities:{...creature.abilities,[key]:value}});
    if(modifierChange)openConstitutionHpDialog(creature.id,modifierChange.previous,modifierChange.next);
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
      try{
        await patch({inventory:changeOwnedItem(creature.inventory||[],index,key,value,
          {attunementMax:state.calculated?.attunements?.maximum??state.calculated?.values?.attunement_max??creature.attunement_max_base??3})});
      }catch(error){if(key==='attuned_count'||key==='attuned')await render();throw error;}
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
    const exhaustionPatch=exhaustionSelectionPatch(creature,target.dataset.condition,target.checked);
    if(exhaustionPatch){
      await patch(exhaustionPatch);
    }else{
      const entries=new Set(creature.conditions||[]);
      if(target.checked) entries.add(target.dataset.condition);
      else entries.delete(target.dataset.condition);
      await patch({conditions:[...entries],...(target.dataset.condition==='concentrating'&&!target.checked?{concentrating_spell_id:''}:{})});
    }
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
async function startTargetedCast(casterId,selection,requestedLevel,payment='auto',expectedToken='',companionSource=null){
  if(desktopHooks?.cast){
    await flushPendingFields();
    const result=await desktopHooks.cast({casterId,selection,requestedLevel,payment});
    if(companionSource?.rule?.grant_kind==='spell_effect'){
      const editor=state.editor&&state.creatureId===casterId?state.editor:await openCreatureEditor(casterId);
      await editor.update(companionSpellEffectPatch(editor.read(),companionSource.rule,selection.id));
    }
    if(companionSource)
      await summonSpellCompanion(casterId,companionSource,companionSource);
    return result;
  }
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
  const creature=resolveVariant(stored.data),calculated=await computeLocalData(creature);
  const plan=spellCastPlan(creature,selection,requestedLevel,calculated,payment);
  if(!tacticalViewer)tacticalViewer=new TacticalViewer({send:action,ownerId,notify:message});
  let charged=false;
  tacticalViewer.onCastAccepted=async()=>{
    if(charged)return;
    const editor=state.editor&&state.creatureId===casterId?
      state.editor:await openCreatureEditor(casterId);
    const current=editor.read();
    const accepted=spellCastPlan(current,selection,requestedLevel,await computeLocalData(current),payment);
    const effect=companionSource?.rule?.grant_kind==='spell_effect'?
      companionSpellEffectPatch(current,companionSource.rule,selection.id):{};
    if(Object.keys({...accepted.patch,...effect}).length)await editor.update({...accepted.patch,...effect});
    charged=true;
    if(companionSource){
      try{
        await summonSpellCompanion(casterId,companionSource,companionSource);
        message('Famiglio aggiunto alle sottocreature.');
      }catch(error){message('Evocazione registrata, ma scheda famiglio non creata: '+errorMessage(error),true);}
    }
    if(state.page==='session'){
      state.cachedCreatures=readableArchiveCreatures(await listCreatures());
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
async function saveInfoPortrait(input){
 const file=input.files?.[0];
 input.value='';
 if(!file)return;
 const editor=state.editor,creatureId=state.creatureId;
 if(!editor||state.sheet!=='info')return;
 try{
  const image=await preparePortraitImage(file);
  if(state.editor!==editor||state.creatureId!==creatureId||state.sheet!=='info')
   throw Error('La scheda è cambiata. Seleziona di nuovo la foto.');
  await patch({sheet_portrait_data:image});
  await render();
  message('Foto salvata nella scheda, disponibile anche offline.');
 }catch(error){message(errorMessage(error),true);}
}
function organizeSheetPanels(){
  if(state.page!=="library"||state.libraryMode||!state.editor)return;
  state.sheetSources=mountPlaySheet(app,{creature:state.editor.read(),calculated:state.calculated,sheet:state.sheet,view:{inventorySelectedIndex:state.inventorySelectedIndex,inventoryHighlightedIndices:state.inventoryHighlightedIndices,inventorySubtab:state.inventorySubtab,inventorySelectedTabs:inventoryVisibleSections(state.editor.read()),search:state.sheetSearch.get(state.creatureId+"|"+state.sheet)||"",battleActions:state.sheet==="battle"?battleActionPanels(state.calculated?.companion_view||state.editor.read(),state.calculated,state.spellCatalog||[],state.featureActionOverrides||[],state.generalActionSupplements||[],readActionVariants(),abilitiesForCreature(state.editor.read(),state.abilityCatalog||[],state.calculated)):null,battleAbilities:state.sheet==="battle"?abilitiesForCreature(state.editor.read(),state.abilityCatalog||[],state.calculated):[],battleSpells:state.sheet==="battle"?state.spellCatalog||[]:[],battleTraits:state.sheet==="battle"?[
  ...(state.calculated.features||[]).map(feature=>({name:feature.name||'',origin_id:feature.origin_id||'',origin_key:feature.origin_key||'',feature_key:feature.key||'',
    description:flattenDescription(feature)})),
  ...(state.battleOptionalTraits||[])]:[]},icon:actionGlyph,conditionLabel,conditionCatalog:state.conditionCatalog,inventoryProperties,isSpellScroll,spells:spellsForEdition(state.spellCatalog||[],state.editor.read().rules_version),classActions:nativeClassFeatureActions(state.editor.read(),state.calculated)});
  if(state.sheet==='inventory'){paintInventorySearchResults();syncInventorySelectionUI();}
  if(state.sheet==='info'){
    const root=app.querySelector('#sheet-play-view');
    const choices=state.calculated.pending_choices||[];
    const missing=choices.filter(choice=>choice.remaining>0);
    const levelReady=availableXpLevels(state.editor.read())>0;
    if(root&&(missing.length||levelReady)){
      const total=missing.reduce((n,choice)=>n+choice.remaining,0)+(levelReady?1:0);
      const notice=document.createElement('section');
      notice.className='pending-choices-notice';
      notice.setAttribute('aria-label','Scelte del personaggio da completare');
      notice.innerHTML='<div class="pending-choices-notice-head"><span aria-hidden="true">◇</span>'+
        '<strong>'+total+' '+(total===1?'scelta da completare':'scelte da completare')+'</strong></div>'+
        '<div class="pending-choices-notice-list">'+
        (levelReady?'<button type="button" data-act="level-up-open"><span>Level up <small>· Scegli la classe da livellare</small></span>'+
          '<span>↑ <span aria-hidden="true">›</span></span></button>':'')+
        missing.map(choice=>
          '<button type="button" data-act="pending-choice-open" data-choice-id="'+esc(choice.id)+'">'+
          '<span>'+esc(choice.name)+' <small>· '+esc(choice.label)+'</small></span>'+
          '<span>'+esc(choice.selected.length)+'/'+esc(choice.count)+' <span aria-hidden="true">›</span></span></button>').join('')+
        '</div>';
      // The order is identity, portrait/photo button, pending choices, then details.
      const portrait=root.querySelector(':scope > .play-character-portrait');
      const identity=root.querySelector(':scope > .play-identity');
      if(portrait)portrait.after(notice);
      else if(identity)identity.after(notice);
      else root.prepend(notice);
    }
    // Align the privilege-choice shortcut to the right of the Info title,
    // using the same page-header button treatment as the other sheets.
    const pageHead=app.querySelector('.page-head');
    if(pageHead&&(choices.length||levelReady)){
      pageHead.classList.add('play-info-page-title');
      const manage=document.createElement('button');
      manage.type='button';manage.className='play-button pending-choices-manage';
      manage.dataset.act='pending-choice-manage';
      manage.innerHTML=actionGlyph('settings')+'<span>Scelte dei privilegi</span>';
      pageHead.append(manage);
    }
  }
  // Opening a battle category also expands its action-timing groups.
  // Ability-check categories remain independently collapsible.
  for(const details of app.querySelectorAll('#sheet-play-view .play-battle-disclosure')){
    const key='battle-disclosure:'+details.dataset.battleAction;
    if(state.disclosureState.has(key))details.open=state.disclosureState.get(key);
    details.querySelector(':scope > summary')?.addEventListener('click',()=>{
      if(details.open)return;
      for(const group of details.querySelectorAll(':scope > .play-battle-action-group[data-action-timing]')){
        group.open=true;
        const groupKey='battle-timing:'+details.dataset.battleAction+':'+group.dataset.actionTiming;
        state.disclosureState.set(groupKey,true);
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
  dialog.innerHTML='<header class="sheet-context-head"><h2 id="sheet-context-title">'+esc(title)+'</h2>'+dialogCloseButton('sheet-context-close','Chiudi dettagli','play-button')+'</header><div class="sheet-context-body"></div>';
  dialog.querySelector('.sheet-context-body').append(source);
  if(source.tagName==='DETAILS')source.open=true;
  for(const details of source.querySelectorAll(':scope > .action-economy-main > details.action-economy-entry,:scope > details.action-tree'))details.open=true;
  app.append(dialog);
  dialog.addEventListener('cancel',event=>{event.preventDefault();void closeSheetContext().catch(error=>message(errorMessage(error),true));});
  dialog.addEventListener('click',event=>{if(event.target!==dialog)return;const rect=dialog.getBoundingClientRect();if(event.clientY<rect.top||event.clientY>rect.bottom||event.clientX<rect.left||event.clientX>rect.right)void closeSheetContext().catch(error=>message(errorMessage(error),true));});
  openDialog(dialog);
}
async function closeSheetContext(){
  const key=state.sheetPopup;
  await flushPendingFields();state.sheetPopup="";
  if(returnToBattleFromCompetences){state.sheet='battle';returnToBattleFromCompetences=false;}
  await render();
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
   .filter(row=>row?.id&&row?.name&&matchesSearch(query,row.name,row.source));
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
   '<div class="sheet-roll-dice-values">'+(part.kind==='flat'?
     '<span class="sheet-roll-die-value">'+esc(part.notation)+'</span>':
     (part.rolls||[]).map(n=>
       '<span class="sheet-roll-die-value">'+esc(n)+'</span>').join(''))+'</div></div>').join('')+'</div>';
}
function chosenRollBonuses(dialog){
 return [...(dialog.usedRollBonuses||[])];
}
function applyPostRollBonus(dialog,bonus){
 const previous=dialog.rollOutcome;
 if(!previous||!dialog.isConnected||dialog.appliedBonusIds?.has(bonus.selectionId))return null;
 const next={...appendRollBonus(previous,bonus,randomDie),label:previous.label,author:previous.author};
 dialog.rollOutcome=next;
 dialog.postRollBonuses=[...(dialog.postRollBonuses||[]),bonus];
 dialog.appliedBonusIds.add(bonus.selectionId);
 if(state.roll===previous)state.roll=next;
 const index=state.rollHistory.indexOf(dialog.rollHistoryEntry);
 if(index>=0)state.rollHistory[index]=next;
 dialog.rollHistoryEntry=next;
 const result=dialog.querySelector('[data-roll-result]');
 if(result){result.hidden=false;result.innerHTML=rollDieResultMarkup(next);}
 dialog.renderRollFormula?.();
 return next;
}
function recordRevisedRoll(dialog,next){
 const previous=dialog.rollOutcome;
 dialog.rollOutcome=next;
 if(state.roll===previous)state.roll=next;
 const index=state.rollHistory.indexOf(dialog.rollHistoryEntry);
 if(index>=0)state.rollHistory[index]=next;
 dialog.rollHistoryEntry=next;
 const result=dialog.querySelector('[data-roll-result]');
 if(result){result.hidden=false;result.innerHTML=rollDieResultMarkup(next);}
 return next;
}
function refreshD20RerollChoices(dialog,record,calculated){
 const container=dialog?.querySelector('[data-d20-rerolls]');
 if(!container)return;
 if(!dialog.rollOutcome){container.hidden=true;return;}
 const choices=availableD20Rerolls(record,calculated,dialog.dataset.rollTarget,dialog.rollOutcome)
   .filter(row=>!dialog.usedRerollIds?.has(String(row.id)));
 dialog.d20RerollSources=choices;
 const current=dialog.rollOutcome.d20_reroll;
 const select=current?'<div class="sheet-reroll-choice"><span>'+esc(current.source_name)+
   ': precedente '+esc(current.previous)+' · nuovo '+esc(current.new_roll)+'</span>'+
   '<button type="button" data-act="sheet-roll-choose-d20" data-d20-choice="previous" aria-pressed="'+(current.selected==='previous')+'">Tieni precedente</button>'+
   '<button type="button" data-act="sheet-roll-choose-d20" data-d20-choice="new" aria-pressed="'+(current.selected==='new')+'">Usa nuovo</button></div>':'';
 container.innerHTML=(choices.length?'<div class="sheet-reroll-title">Ritira un d20</div>'+
   choices.map((row,index)=>'<button type="button" class="sheet-reroll-source" data-act="sheet-roll-reroll-d20" data-d20-reroll="'+index+'">'+
     esc(row.origin_name||row.name||'Ritiro')+
     (row.tracker_id?' · '+esc(row.tracker_cost||1)+' utilizzo':'')+'</button>').join(''):'')+select;
 container.hidden=!choices.length&&!current;
}
async function announcePostRollBonus(updated){
 if(!updated)return;
 try{
  // The earlier chat event remains immutable: publish an explicit revision.
  await shareRoll({quiet:true,roll:{...updated,label:'Tiro aggiornato · '+updated.label}});
 }catch(error){message('Risultato aggiornato localmente; invio chat fallito: '+errorMessage(error),true);}
}
function rollBonusTerm(row){
 const flat=Object.hasOwn(row,'flat_bonus');
 return {key:'roll-extra:'+String(row.selectionId||row.id),kind:flat?'bonus':'dice',
  formula:flat?(row.flat_bonus>=0?'+':'')+row.flat_bonus:'+'+row.dice,expanded:'',...(row.damage_type?{damageType:rollDamageName(row.damage_type)}:{}),
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
  dialogCloseButton('roll-trait-cancel','Chiudi','trait-benefits-close')+'</header>'+
  '<div class="trait-benefits-dialog-body"><label>Tratto<select data-roll-trait-key>'+
  traits.map(row=>'<option value="'+esc(row.key)+'">'+esc(row.origin+' · '+row.name)+'</option>').join('')+
  '</select></label><div class="actions"><button type="button" class="btn primary" data-act="roll-trait-pick">Continua</button></div></div>';
 document.body.append(picker);picker.addEventListener('close',()=>picker.remove(),{once:true});
 picker.showModal?.();
}
async function openRollTraitOrigin(originId,{traitName='',originKey=''}={}){
 state.traitPopupKey='';state.traitPopupConfirm='';state.traitPopupDraftKind='';state.traitPopupDraftTarget='';
 state.sheet='info';await render();
 const record=state.editor?.read()||{};
 const trait=rollGrantTraitRow(state.traitRows||[],record,originId,{traitName,originKey});
 if(!trait){
   const isProficiency=originId==='proficiency:unattributed'||
     Object.values(state.calculated?.proficiency_sources||{}).some(sources=>
       Array.isArray(sources)&&sources.some(source=>source?.id===originId));
   if(isProficiency){
     // Unattributed proficiency or unavailable source metadata is not a trait.
     // Keep the real proficiency readout reachable without an add-bonus picker.
     app.querySelector('#sheet-play-view .play-skills-disclosure')?.scrollIntoView?.({block:'center'});
     message('Questa competenza è riepilogata in Info > Abilità.');
     return;
   }
   message('Origine non riconducibile a un tratto della creatura. Seleziona il tratto corretto.',true);
   await openRollTraitPicker('bonus','');return;
 }
 state.traitPopupKey=trait.key;mountTraitBenefitDialog();
}
function openConcentrationDamageDialog(check,creature,calculated){
 if(!check||!creature||state.editor?.read()?.id!==creature.id)return;
 document.querySelector('#concentration-damage-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='concentration-damage-dialog';
 dialog.className='sheet-roll-dialog sheet-roll-preview concentration-damage-dialog';
 dialog.dataset.creatureId=creature.id;
 const modifier=Number(calculated?.values?.['save:con']);
 const signed=Number.isFinite(modifier)?(modifier>=0?'+':'')+modifier:'—';
 dialog.innerHTML='<header class="sheet-context-head"><div><small>CONCENTRAZIONE · DANNI SUBITI</small><h2>Verifica concentrazione</h2></div>'+dialogCloseButton('concentration-close','Chiudi')+'</header>'+
  '<p class="concentration-damage-copy">Hai subito <strong>'+esc(check.damage)+'</strong> danni mentre mantieni la concentrazione.'+
  (check.spell_id?'<span class="concentration-spell-label">Incantesimo: '+esc(check.spell_id)+'</span>':'')+'</p>'+
  '<div class="concentration-damage-metrics"><div><span>CD tiro salvezza</span><strong>'+esc(check.dc)+'</strong></div>'+
  '<div><span>TS Costituzione</span><button type="button" class="concentration-save-button" data-act="concentration-save-roll" data-creature-id="'+esc(creature.id)+'" aria-label="Apri il tiro salvezza di concentrazione">'+esc(signed)+' '+actionGlyph('dice')+'</button></div></div>'+
  '<div class="actions concentration-damage-actions"><button type="button" class="btn small" data-act="concentration-end">Termina concentrazione</button></div>';
 document.body.append(dialog);
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 openDialog(dialog);
 return dialog;
}
// One reusable roller for feature-owned dice, e.g. Stone's Endurance and
// Hadozee Dodge. Its roll target and source survive in roll history and can
// be addressed by another trait's dice bonus or ability effect extension.
function openFeatureRollDialog(creature,calculated,ability,formula=''){
 const target=featureRollTarget(ability);
 if(!target||!formula)return null;
 const preview=damageRollTerms(formula);
 const optional=rollOptionalDice(creature,calculated,[
   ...applicableDiceBonuses(creature,target,state.spellCatalog||[],calculated),
   ...featureRollFlatBonuses(creature,calculated,ability),
   ...classFeatureRollBonuses(creature,calculated,target),
   ...applicableFeatRollBonuses(creature,calculated,target),
   ...featureRollExtensionBonuses(calculated,ability)
 ],{kind:'feature'});
 const dialog=openUnifiedRollDialog({kind:'feature',heading:ability.name,
   rollType:ability.roll_effect?.label||'Tiro della capacità',
   modifier:preview.modifier,formula:sheetRollOriginHtml(preview.segments,esc),
   bonuses:optional,creatureId:creature.id||'',target,
   damageFormula:formula,damageLabel:(ability.roll_effect?.label||'Tiro')+' · '+ability.name});
 dialog.dataset.featureRollTarget=target;
 dialog.dataset.featureRollOriginId=ability.origin_id||ability.feature_id||'';
 dialog.renderRollFormula=()=>{dialog.querySelector('[data-roll-formula]').innerHTML=sheetRollOriginHtml(
   [...damageRollTerms(formula).segments,...[...chosenRollBonuses(dialog),
     ...(dialog.postRollBonuses||[])].map(rollBonusTerm)],esc);};
 return dialog;
}
function openUnifiedRollDialog({kind,heading,rollLabel='',modifier,rollType,formula,bonuses=[],autoLabel='',creatureId='',target='',damageFormula='',damageType='',damageLabel=''}){
 document.querySelector('#sheet-roll-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='sheet-roll-dialog';dialog.className='sheet-roll-dialog sheet-roll-preview';
 dialog.dataset.rollKind=kind;dialog.dataset.creatureId=creatureId;
 dialog.rollBonuses=bonuses;dialog.usedRollBonuses=[];
 dialog.rollOutcome=null;dialog.rollHistoryEntry=null;dialog.postRollBonuses=[];dialog.appliedBonusIds=new Set();
 dialog.usedRerollIds=new Set();dialog.d20RerollSources=[];
 if(kind==='damage'||kind==='feature'){
   dialog.dataset.damageFormula=damageFormula;dialog.dataset.damageType=damageType;
   dialog.dataset.damageLabel=damageLabel;
   if(kind==='feature')dialog.dataset.rollTarget=target;
 }else{
   dialog.dataset.rollTarget=target;dialog.dataset.rollLabel=rollLabel;
 }
 const mode=(kind==='damage'||kind==='feature')
   ?'<option value="normal">Normale</option>'
   :'<option value="auto">Automatica'+esc(autoLabel)+'</option>'+
     '<option value="normal">Forza tiro normale</option>'+
     '<option value="advantage">Aggiungi vantaggio</option>'+
     '<option value="disadvantage">Aggiungi svantaggio</option>';
 const select='<label class="sheet-roll-mode-control">Modalità del tiro'+
   '<select data-roll-mode'+(kind==='damage'||kind==='feature'?' disabled aria-label="Questo tiro non prevede vantaggio o svantaggio"':'')+'>'+mode+'</select></label>';
 const bonusList='<section class="sheet-roll-math sheet-roll-formula sheet-roll-applicable">'+
   '<div class="sheet-roll-bonuses-head"><span>Bonus applicabili al tiro</span>'+
   '<button type="button" class="sheet-roll-add" data-act="sheet-roll-add-applicable" aria-label="Aggiungi tiro applicabile" title="Aggiungi tiro applicabile">+</button></div>'+
   (bonuses.length?'<div class="sheet-roll-bonus-list" data-roll-extra role="group" aria-label="Bonus disponibili">'+
     bonuses.map((row,i)=>{
       const racialMode=row.roll_mode==='advantage'||row.roll_mode==='disadvantage';
       const trackerLabel=row.tracker_id?(row.tracker_name||'Tracker')+' · '+(row.remaining??0)+' rim.':'Nessun tracker associato';
       const originAttrs=' data-origin-id="'+esc(row.origin_id||'')+'"'+
         ' data-origin-trait="'+esc(row.granting_trait||'')+'"'+
         ' data-origin-key="'+esc(row.origin_key||'')+'"';
       const traitLink=racialMode||row.passive_class_bonus||row.feat_conditional||!!(row.granting_trait&&row.origin_id);
       const targetTitle=traitLink?'Apri tratto · '+(row.granting_trait||row.origin_name||''):
         'Apri tracker '+trackerLabel;
       return '<div class="sheet-roll-bonus-item'+(racialMode?' sheet-roll-bonus-item--mode':'')+'">'+
         '<button type="button" class="sheet-roll-origin-term sheet-roll-bonus-term is-link" data-act="roll-origin-open"'+originAttrs+' title="Apri tratto">'+
           '<span class="sheet-roll-origin-symbol'+(racialMode?' sheet-roll-mode-symbol sheet-roll-mode-symbol--'+esc(row.roll_mode):'')+'">'+esc(row.roll_mode?
              row.roll_mode==='advantage'?'ADV':'DIS':Object.hasOwn(row,'flat_bonus')?
              (row.flat_bonus>=0?'+':'')+row.flat_bonus:'+'+row.dice)+'</span>'+
           (row.damage_type?'<span class="sheet-roll-origin-damage-type">'+esc(rollDamageName(row.damage_type))+'</span>':'')+
           '<span class="sheet-roll-origin-name">'+esc(racialMode?(row.granting_trait||row.origin_name||'Tratto'):(row.origin_name||'Bonus'))+'</span></button>'+
         (row.condition_label?
            '<div class="sheet-roll-bonus-condition" title="'+esc(row.condition_label)+'">'+
              '<span class="sheet-roll-bonus-condition-key">QUANDO</span>'+
              '<span class="sheet-roll-bonus-condition-text">'+esc(row.condition_label)+'</span>'+
            '</div>':'')+
         '<div class="sheet-roll-bonus-controls">'+
           '<button type="button" class="sheet-roll-use" data-act="sheet-roll-use-bonus" data-roll-use="'+i+'"'+(row.strict_tracker&&Number(row.remaining)<Number(row.tracker_cost)?' disabled title="Utilizzi esauriti"':'')+'>Usa</button>'+
           '<button type="button" class="sheet-roll-tracker-open" data-act="'+(traitLink?'roll-origin-open':'sheet-roll-open-tracker')+'"'+
             (traitLink?originAttrs:' data-roll-tracker-button="'+i+'"')+
             ' aria-label="'+esc(targetTitle)+'" title="'+esc(targetTitle)+'"'+
             (traitLink||row.tracker_id?'':' disabled')+'>'+
             actionGlyph('target')+'</button>'+
         '</div></div>';
     }).join('')+'</div>':'')+'</section>';
 dialog.innerHTML='<h2>'+esc(heading)+
   dialogCloseButton('close-sheet-roll','Chiudi','sheet-roll-close')+'</h2>'+
   '<div class="sheet-roll-math"><span>Modificatore totale</span><strong>'+esc((modifier>=0?'+':'')+modifier)+'</strong></div>'+
   '<div class="sheet-roll-math"><span>Tipo di tiro</span><strong>'+esc(rollType)+'</strong></div>'+
   '<div class="sheet-roll-math sheet-roll-formula"><span>Formula del tiro</span>'+
     '<div class="sheet-roll-formula-line"><div data-roll-formula>'+formula+'</div>'+
     '<button type="button" class="sheet-roll-add" data-act="sheet-roll-add-bonus" aria-label="Aggiungi bonus alla formula" title="Aggiungi bonus alla formula">+</button></div></div>'+
   '<div class="sheet-roll-result" data-roll-result hidden aria-live="polite"></div>'+
   (kind==='d20'?'<section class="sheet-roll-rerolls" data-d20-rerolls hidden aria-label="Ritiri d20 disponibili"></section>':'')+bonusList+
   '<div class="actions sheet-roll-actions">'+select+
     btn('roll-sheet-confirm',kind==='damage'?'Tira danni':kind==='feature'?'Tira':'Tira 1d20','primary')+'</div>';
 document.body.append(dialog);
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 openDialog(dialog);
 return dialog;
}
const editableScoreBaseTarget=target=>
  target==='hp'||target==='second_max'||target==='attunement_max'||
  /^ability:(?:str|dex|con|int|wis|cha)$/.test(target);

// Only changes to the *effective modifier* can propose HP changes.
async function constitutionModifierChange(record,nextScore){
 if(Number(record.abilities?.con)===nextScore)return null;
 const updated={...record,abilities:{...record.abilities,con:nextScore}};
 const [before,after]=await Promise.all([computeLocalData(record),computeLocalData(updated)]);
 const previous=Number(before.abilities?.con?.modifier),next=Number(after.abilities?.con?.modifier);
 return previous===next?null:{previous,next};
}

function openConstitutionHpDialog(creatureId,previous,next,{returnTitle=''}={}){
 const record=state.editor?.read();
 if(!record||record.id!==creatureId)return;
 const changes=constitutionHpAdjustment(record,previous,next);
 if(!changes)return;
 document.querySelector('#constitution-hp-dialog')?.remove();
 const delta=next-previous;
 const signed=value=>(value>=0?'+':'')+value;
 const dialog=document.createElement('dialog');
 dialog.id='constitution-hp-dialog';
 dialog.className='sheet-context-dialog pending-choice-dialog constitution-hp-dialog';
 dialog.innerHTML='<header class="sheet-context-head"><h2>Costituzione e punti ferita</h2>'+
   dialogCloseButton('constitution-hp-close','Chiudi','play-button')+'</header>'+
   '<div class="pending-choice-dialog-body">'+
     '<p>Il modificatore di Costituzione è cambiato da <strong>'+esc(signed(previous))+
       '</strong> a <strong>'+esc(signed(next))+'</strong> ('+esc(signed(delta))+').</p>'+
     '<p>Vuoi aggiornare i punti ferita di '+esc(signed(delta))+'?</p>'+
     '<div class="native-summary">'+
       '<div><dt>PF massimi</dt><dd>'+esc(record.max_hp_base??record.max_hp??1)+
         ' → '+esc(changes.max_hp_base)+'</dd></div>'+
       '<div><dt>PF attuali</dt><dd>'+esc(record.current_hp??0)+
         ' → '+esc(changes.current_hp)+'</dd></div></div>'+
   '</div><footer class="pending-choice-actions">'+
     '<button type="button" data-con-hp-keep>Mantieni PF</button>'+
     '<button type="button" class="btn primary" data-con-hp-apply>Aggiorna PF</button></footer>';
 dialog.addEventListener('close',async()=>{
   dialog.remove();
   const current=state.editor?.read();
   if(returnTitle&&current?.id===creatureId)
     try{openSheetScoreFormula(current,await computeLocalData(current),'ability:con',returnTitle);}
     catch(error){message(errorMessage(error),true);}
 },{once:true});
 dialog.querySelector('[data-con-hp-keep]').addEventListener('click',()=>closeDialog(dialog));
 dialog.querySelector('[data-con-hp-apply]').addEventListener('click',async event=>{
   const button=event.currentTarget;
   button.disabled=true;
   try{
     const current=state.editor?.read();
     if(!current||current.id!==creatureId)throw Error('La creatura è cambiata.');
     const calculated=await computeLocalData(current);
     if(Number(calculated.abilities?.con?.modifier)!==next)
       throw Error('Il modificatore di Costituzione è cambiato ancora.');
     const update=constitutionHpAdjustment(current,previous,next);
     if(update)await patch(update);
     await render();
     closeDialog(dialog);
   }catch(error){button.disabled=false;message(errorMessage(error),true);}
 });
 document.body.append(dialog);openDialog(dialog);
}

// A single restrained editor serves owned base scores, not derived figures.
// Keep the formula behind it as the navigation context, then refresh it after
// saving/cancelling to avoid presenting a stale computed total.
function openSheetBaseEditor(record,calculated,target,{returnTitle=''}={}){
 if(!editableScoreBaseTarget(target))throw Error('Questo valore è calcolato e non modificabile direttamente.');
 const ability=target.startsWith('ability:')?target.split(':')[1]:'';
 const isHp=target==='hp',isSecond=target==='second_max',isAttunement=target==='attunement_max';
 const title=isHp?'PF massimi':isSecond?'PF seconda forma':isAttunement?'Sintonie massime':abilities[ability];
 const value=isHp?(record.max_hp_base??record.max_hp??1):
   isSecond?(record.second_form_max_hp??0):isAttunement?(record.attunement_max_base??3):(record.abilities?.[ability]??10);
 const minimum=isSecond||isAttunement?0:1,maximum=isAttunement?99:ability?30:99999;
 const auto=calculated?.stats?.automatic_hp;
 document.querySelector('#sheet-score-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='sheet-score-dialog';
 dialog.className='sheet-roll-dialog sheet-roll-preview sheet-score-dialog sheet-base-editor';
 dialog.dataset.scoreTarget=target;
 dialog.dataset.returnFormulaTitle=returnTitle;
 dialog.innerHTML='<h2>Modifica valore base'+
   dialogCloseButton('close-score','Chiudi','sheet-roll-close')+'</h2>'+
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
 openDialog(dialog);
 dialog.querySelector('input')?.focus();
 dialog.querySelector('input')?.select();
 return dialog;
}
function openSheetSensesDialog(calculated={}){
 document.querySelector('#sheet-senses-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='sheet-senses-dialog';
 dialog.className='sheet-context-dialog sheet-senses-dialog';
 const data=calculated.senses||{},passive=calculated.values?.passive_perception??'—';
 const origins=(data.grants||[]).map(row=>
  '<li><strong>'+esc(row.origin_name||'Tratto')+'</strong><span>'+
  esc(SENSE_OPTIONS.find(([id])=>id===row.type)?.[1]||row.type)+
  ' · '+esc(senseRange(row.range_feet))+'</span></li>').join('');
 dialog.innerHTML='<header class="sheet-context-head"><h2>Sensi</h2>'+
  dialogCloseButton('sheet-senses-close','Chiudi','play-button')+'</header>'+
  '<div class="sheet-senses-body">'+
  '<button type="button" class="sheet-senses-passive" data-act="sheet-score-formula" data-target="passive_perception" data-label="Percezione passiva" aria-label="Mostra formula della percezione passiva">'+
  '<span>Percezione passiva</span><strong>'+esc(passive)+'</strong></button>'+
  '<div class="sheet-senses-table-wrap"><table class="sheet-senses-table"><thead><tr>'+
  ['Senso','Luce intensa','Luce fioca','Oscurità','Oscurità magica'].map(label=>'<th scope="col">'+label+'</th>').join('')+
  '</tr></thead><tbody>'+(data.rows||[]).map(row=>'<tr><th scope="row">'+esc(row.name)+'</th>'+
  [row.bright,row.dim,row.dark,row.magical].map(value=>'<td>'+esc(value)+'</td>').join('')+'</tr>').join('')+
  '</tbody></table></div>'+
  '<p class="sheet-senses-note">In luce fioca le prove di Percezione basate sulla vista subiscono svantaggio (−5 alla percezione passiva pertinente). La scurovisione tratta la luce fioca come intensa e l’oscurità non magica come fioca entro la sua portata; al buio non distingue i colori.</p>'+
  '<p class="sheet-senses-note">La percezione tellurica rileva vibrazioni tramite una superficie condivisa: non equivale a vedere. La vista cieca e la vista pura non dipendono dall’illuminazione entro la loro portata. Fuori portata valgono le condizioni della visione normale.</p>'+
  (origins?'<section class="sheet-senses-sources"><h3>Privilegi e origini</h3><ul>'+origins+'</ul></section>':'')+
  (state.editor?.read()?.species==='Custom Lineage'&&state.editor?.read()?.species_source==='TCE'?
   '<section class="sheet-senses-sources"><h3>Custom Lineage · Tratto variabile</h3>'+
   '<p class="sheet-senses-note">Le due versioni, con Scurovisione oppure Competenza in abilità, si selezionano dalla specie nella scheda Info. Entrambe concedono un talento.</p></section>':'')+
  '</div>';
 app.append(dialog);
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 dialog.addEventListener('click',event=>{if(event.target===dialog)dialog.close?.();});
 openDialog(dialog);
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
   dialogCloseButton('close-score-formula','Chiudi','sheet-roll-close')+'</h2>'+
   '<div class="sheet-roll-math"><span>Valore calcolato</span><strong>'+esc(value)+'</strong></div>'+
   '<div class="sheet-roll-math sheet-roll-formula"><span>Formula del valore</span>'+
   '<div class="sheet-roll-formula-line"><div data-score-formula>'+
   sheetRollOriginHtml(terms,esc)+'</div>'+
   '<button type="button" class="sheet-roll-add" data-act="sheet-score-add-bonus" title="Aggiungi un bonus tramite un tratto" aria-label="Aggiungi un bonus tramite un tratto">+</button></div></div>';
 document.body.append(dialog);
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 dialog.addEventListener('click',event=>{if(event.target===dialog)dialog.close?.();});
 openDialog(dialog);
 return dialog;
}
// Read-only changes, derived with the same numerical rules as the character
// sheet. "Preparabili" and "selezionabili" denote capacity, not auto-grants.
function levelUpImpactDetails(changes=[]){
 if(!changes.length)return '<p class="levelup-empty">Nessuna ulteriore variazione numerica.</p>';
 return '<ul class="levelup-impact-list">'+changes.map(item=>
   '<li><div class="levelup-impact-line"><span>'+esc(item.label)+'</span>'+
   '<strong>'+esc(item.from)+' → '+esc(item.to)+'</strong></div>'+
   (item.options?.length?'<details class="levelup-impact-options"><summary>Vedi le opzioni ('+
     esc(item.options.length)+')</summary><ul>'+item.options.map(name=>
     '<li>'+esc(name)+'</li>').join('')+'</ul></details>':'')+
   '</li>').join('')+'</ul>';
}
function levelUpImpactStep(row,{preview=false}={}){
 return '<section class="levelup-impact-step"><header><strong>Livello '+esc(row.level)+
   '</strong><small>Personaggio · livello '+esc(row.totalLevel)+'</small></header>'+
   (preview&&row.features?.length?'<ul class="levelup-impact-features">'+
     row.features.map(feature=>'<li>'+esc(feature.name)+'</li>').join('')+'</ul>':'')+
   levelUpImpactDetails(row.changes||[])+'</section>';
}
// The class row has already been saved. Render its entire gained level range,
// including features and outstanding decisions, without applying more grants.
function openLevelUpProgressDialog(plan){
 const steps=levelUpSteps(state.calculated||{},plan);
 if(!steps.length)return;
 const impactRows=Array.isArray(plan.impactRows)?plan.impactRows:[];
 const powersChanged=impactRows.some(row=>(row.changes||[]).some(change=>
   /(?:Incantesimi|Trucchetti|Slot|Patto|Infusioni)/i.test(change.label)));
 app.querySelector('#level-up-progress-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='level-up-progress-dialog';
 dialog.className='sheet-context-dialog pending-choice-dialog levelup-progress-dialog';
 const count=steps.length;
 const choiceCount=steps.reduce((n,row)=>n+row.choices.reduce((m,c)=>m+Number(c.remaining||0),0),0);
 const featureList=features=>features.map(feature=>
   '<li class="levelup-feature"><strong>'+esc(feature.name)+'</strong>'+
   (String(feature.origin_key||'').includes('|subclass|')?'<small>Sottoclasse</small>':'')+
   '</li>').join('');
 const choiceList=choices=>choices.map(choice=>
   '<button type="button" class="levelup-choice-link" data-level-up-choice-id="'+esc(choice.id)+'">'+
   '<span>'+esc(choice.label||choice.name||'Scelta disponibile')+
   '<small>'+esc(choice.name||'Privilegio')+'</small></span><span aria-hidden="true">›</span></button>').join('');
 dialog.innerHTML='<header class="sheet-context-head"><div><small>Avanzamento del personaggio</small>'+
   '<h2>Livellaggio · '+esc(plan.className)+'</h2></div>'+
   dialogCloseButton('level-up-placeholder-close','Chiudi','play-button')+'</header>'+
   '<div class="pending-choice-dialog-body levelup-progress-body">'+
     '<div class="levelup-summary"><strong>Classe '+esc(plan.fromLevel)+' → '+esc(plan.toLevel)+'</strong>'+
     '<span>Livello totale '+esc(plan.fromTotal)+' → '+esc(plan.toTotal)+'</span>'+
     '<small>'+esc(count)+' '+(count===1?'livello acquisito':'livelli acquisiti')+
     (Number.isFinite(plan.hpGain)?' · PF base '+(plan.hpGain>=0?'+':'')+esc(plan.hpGain):'')+
     (choiceCount?' · '+esc(choiceCount)+' '+(choiceCount===1?'scelta da completare':'scelte da completare'):'')+'</small></div>'+
     '<div class="levelup-steps">'+steps.map(row=>
       '<section class="levelup-step" aria-label="Livello '+esc(row.level)+' di '+esc(plan.className)+'">'+
       '<header><span class="levelup-step-index">'+esc(row.level)+'</span><div>'+
       '<strong>Livello '+esc(row.level)+'</strong><small>Personaggio · livello '+esc(row.totalLevel)+'</small></div></header>'+
       (row.features.length?'<ul class="levelup-features">'+featureList(row.features)+'</ul>':
         '<p class="levelup-empty">Nessun nuovo privilegio individuato nei dati locali.</p>')+
       (impactRows.length?'<div class="levelup-impact"><strong>Progressione</strong>'+
         levelUpImpactDetails(impactRows[row.level-plan.fromLevel-1]?.changes||[])+'</div>':'')+
       (row.choices.length?'<div class="levelup-choices"><strong>Scelte da fare</strong>'+
         choiceList(row.choices)+'</div>':'')+
       '</section>').join('')+'</div>'+
     '<p class="levelup-footer-note">I privilegi già definiti vengono applicati dalle regole della scheda. '+
     'I PF vengono aggiornati dalla selezione precedente; i dadi vita seguono la progressione delle classi.</p>'+
   '</div><footer class="pending-choice-actions">'+
     (powersChanged?'<button type="button" data-level-up-powers>Vai a Poteri</button>':'')+
     (choiceCount?'<button type="button" data-level-up-manage>Altre scelte</button>':'')+
     '<button type="button" data-level-up-close>Chiudi</button></footer>';
 dialog.querySelector('[data-level-up-close]').addEventListener('click',()=>closeDialog(dialog,{remove:true}));
 dialog.querySelector('[data-level-up-manage]')?.addEventListener('click',()=>{
   closeDialog(dialog,{remove:true});openPendingChoicesIndex();
 });
 dialog.querySelector('[data-level-up-powers]')?.addEventListener('click',async()=>{
   closeDialog(dialog,{remove:true});
   state.sheet='magic';await render();
 });
 for(const button of dialog.querySelectorAll('[data-level-up-choice-id]')){
   button.addEventListener('click',async()=>{
     const choice=(state.calculated?.pending_choices||[]).find(c=>c.id===button.dataset.levelUpChoiceId);
     if(!choice){message('Scelta non più disponibile.',true);return;}
     closeDialog(dialog,{remove:true});
     try{await openCharacterChoice(choice);}
     catch(error){message(errorMessage(error),true);}
   });
 }
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 app.append(dialog);openDialog(dialog);
}
// All level and HP choices are edited before changing the character.
async function openLevelUpClassDialog(preset={}){
 const record=state.editor?.read();
 if(!record)return;
 // Monsters use the same class progression, retaining their original bestiary stats.
 const isMonster=record.kind==='monster'||record.variant_rules_kind==='monster';
 const fromTotal=totalClassLevel(record);
 const maximum=20-fromTotal;
 if(maximum<1)throw Error('La creatura ha già 20 livelli di classe.');
 const xpAvailable=availableXpLevels(record);
 const owned=rowsFor(record,'classes').map((row,index)=>({...row,index})).filter(row=>row.name);
 const all=state.referenceCatalogs.classes||await catalogEntries('classes');
 state.referenceCatalogs.classes=all;
 const choices=all.filter(row=>row.name&&isContentAvailableForRules(row,record.rules_version));
 const idOf=row=>String(row.id||row.name+'|'+row.source);
 const existing=owned.map(row=>({value:'owned:'+row.index,
   label:row.name+' · '+(row.source||'Fonte non specificata')+' (livello '+row.level+')'}));
 const remaining=choices.filter(row=>!owned.some(member=>member.name.toLowerCase()===row.name.toLowerCase()));
 const unique=new Map();
 for(const row of remaining){
   const key=row.name.toLowerCase(),preferred=record.rules_version==='2024'?'XPHB':'PHB';
   if(!unique.has(key)||row.source===preferred)unique.set(key,row);
 }
 const newEntries=[...unique.values()].sort((a,b)=>a.name.localeCompare(b.name,'it'));
 if(!existing.length&&!newEntries.length)throw Error('Catalogo delle classi non disponibile.');
 const dialog=document.createElement('dialog');
 dialog.id='class-level-up-dialog';
 dialog.className='sheet-context-dialog pending-choice-dialog levelup-class-dialog';
 const opts=entries=>entries.map(row=>'<option value="'+esc(row.value)+'">'+esc(row.label)+'</option>').join('');
 const defaultCount=Math.max(1,Math.min(maximum,
   Number(preset.suggestedCount)||xpAvailable||1));
 dialog.innerHTML='<header class="sheet-context-head"><h2>Livellaggio</h2>'+
   dialogCloseButton('level-up-class-close','Chiudi','play-button')+'</header>'+
   '<div class="pending-choice-dialog-body levelup-class-fields">'+
   '<label>Classe da livellare<select data-level-up-class>'+
     (existing.length?'<optgroup label="Classi possedute">'+opts(existing)+'</optgroup>':'')+
     (newEntries.length?'<optgroup label="Altre classi">'+
       opts(newEntries.map(row=>({value:'new:'+idOf(row),label:row.name+' · '+row.source})))+
       '</optgroup>':'')+
   '</select></label>'+
   '<label>Livelli da acquisire<select data-level-up-count>'+
     Array.from({length:maximum},(_,i)=>'<option value="'+(i+1)+'"'+
       (i+1===defaultCount?' selected':'')+'>'+
       (i+1)+' '+(i===0?'livello':'livelli')+'</option>').join('')+
   '</select></label>'+
   '<p class="levelup-class-preview" data-level-up-preview></p>'+
   '<div class="levelup-hp-rows" data-level-up-hp-rows></div>'+
   '<section class="levelup-impact-preview" aria-label="Anteprima della progressione">'+
     '<h3>Cosa cambia con il livello</h3>'+
     '<div data-level-up-impact role="status"><p class="levelup-empty">Calcolo della progressione…</p></div>'+
     '<p class="levelup-footer-note">Gli aumenti di capacità non preparano automaticamente '+
       'incantesimi né insegnano o applicano infusioni: queste scelte restano nella scheda Poteri.</p>'+
   '</section>'+
   '<p class="levelup-footer-note" data-level-up-xp-note></p>'+
   '</div><footer class="pending-choice-actions">'+
   '<button type="button" data-level-up-cancel>Annulla</button>'+
   '<button type="button" class="btn primary" data-level-up-confirm>Conferma livellaggio</button></footer>';
 const classSelect=dialog.querySelector('[data-level-up-class]');
 const countSelect=dialog.querySelector('[data-level-up-count]');
 const hpRows=dialog.querySelector('[data-level-up-hp-rows]');
 const impactPanel=dialog.querySelector('[data-level-up-impact]');
 const impactCache=new Map();
 // The class chooser contains reference names; the numeric class catalog
 // is the authoritative source for each class's hit_die.
 let hitDiceCatalog=null,hitDiceLoad='loading';
 const hitDieFor=selected=>{
   if(!selected)return 0;
   const row=hitDiceCatalog?
     classMechanicsRow(hitDiceCatalog,selected.name,selected.source):null;
   return classHitDieFaces(row||{})||classHitDieFaces(selected.reference||{});
 };
 const rulesRequest=loadRuleCatalogs().then(rules=>{
   const visibleSpells=[...state.spellCatalog||[],
     ...record.prepared_spells||[],...record.spellbook_spells||[],
     ...record.known_spells||[]].filter(row=>row&&typeof row==='object'&&row.id);
   return {...rules,
     spells:[...new Map([...(rules.spells||[]),...visibleSpells].map(row=>[row.id,row])).values()]};
 });
 let impactGeneration=0;
 const projectionPlan=(selected,count)=>({
   classIndex:selected.index,className:selected.name,classSource:selected.source,
   classId:selected.reference?.id||'',fromLevel:selected.from,toLevel:selected.from+count,
   fromTotal,toTotal:fromTotal+count
 });
 const getImpact=async(selected,count)=>{
   const key=classSelect.value+'|'+count;
   if(!impactCache.has(key))impactCache.set(key,rulesRequest.then(rules=>
     levelUpProgressionImpact(record,projectionPlan(selected,count),rules,
       calculateSheet)));
   return impactCache.get(key);
 };
 const refreshImpact=async()=>{
   const generation=++impactGeneration;
   const selected=selectedClass(),count=Number(countSelect.value);
   impactPanel.innerHTML='<p class="levelup-empty">Calcolo della progressione…</p>';
   if(!selected||!Number.isInteger(count)||count<1)return;
   try{
     const rows=await getImpact(selected,count);
     if(generation!==impactGeneration||!dialog.isConnected)return;
     impactPanel.innerHTML=rows.map(row=>levelUpImpactStep(row,{preview:true})).join('')||
       '<p class="levelup-empty">Nessuna variazione disponibile.</p>';
   }catch(error){
     if(generation===impactGeneration&&dialog.isConnected)
       impactPanel.innerHTML='<p class="levelup-empty">Anteprima non disponibile: '+
         esc(errorMessage(error))+'</p>';
   }
 };
 if(preset.preferredIndex!==undefined&&existing.some(row=>row.value==='owned:'+preset.preferredIndex))
   classSelect.value='owned:'+preset.preferredIndex;
 if(preset.preferredNew&&[...classSelect.options].some(o=>o.value==='new:'+preset.preferredNew))
   classSelect.value='new:'+preset.preferredNew;
 const selectedClass=()=>{
   const value=classSelect.value||'';
   if(value.startsWith('owned:')){
     const row=owned.find(row=>row.index===Number(value.slice(6)));
     const reference=choices.find(ref=>row&&ref.name===row.name&&
       (!row.source||ref.source===row.source));
     return row?{name:row.name,source:row.source||'',index:row.index,
       from:Number(row.level)||1,reference:reference||row}:null;
   }
   const reference=choices.find(row=>idOf(row)===value.slice(4));
   return reference?{name:reference.name,source:reference.source||'',
     index:-1,from:0,reference}:null;
 };
 let previousSelection='';
 const paintPreview=()=>{
   const selected=selectedClass();
   const count=Number(countSelect.value)||1;
   const die=hitDieFor(selected);
   const con=Number(state.calculated?.abilities?.con?.modifier ??
     Math.floor((Number(record.abilities?.con??10)-10)/2));
   const values=previousSelection===classSelect.value?
     [...hpRows.querySelectorAll('[data-level-up-hp]')].map(input=>Number(input.value)): [];
   previousSelection=classSelect.value;
   const from=selected?.from||0;
   dialog.querySelector('[data-level-up-preview]').textContent=
     (selected?.name||'Classe')+' · livello '+from+' → '+(from+count)+
     ' · '+(isMonster?'livelli di classe':'personaggio')+' '+fromTotal+' → '+(fromTotal+count);
   const base=die?averageHitDie(die):0;
   hpRows.innerHTML='<strong>Incremento dei punti ferita</strong>'+
     (die?Array.from({length:count},(_,i)=>{
       // A monster's first class level adds average class HP to its existing statblock HP.
       const first=!isMonster&&fromTotal===0&&i===0;
       const expected=first?die:base;
       const value=Number.isInteger(values[i])&&values[i]>=1&&values[i]<=die?values[i]:expected;
       return '<label class="levelup-hp-row"><span>Livello '+(from+i+1)+
         ' <small>d'+die+(first?' · massimo iniziale':' · media '+base)+'</small></span>'+
         '<input type="number" inputmode="numeric" min="1" max="'+die+
         '" data-level-up-hp value="'+value+'" aria-label="Punti ferita dal dado al livello '+(from+i+1)+'">'+
         '<span class="levelup-hp-con"> '+(con>=0?'+':'−')+' '+Math.abs(con)+
         ' COS</span></label>';
     }).join(''):'<p class="levelup-footer-note">'+
       (hitDiceLoad==='loading'?'Caricamento dei dadi vita della classe…':
         'Dado vita non disponibile nelle regole locali per '+esc(selected?.name||'questa classe')+'.')+
       '</p>')+
     (die?'<output class="levelup-hp-total" data-level-up-hp-total></output>':'');
   const note=dialog.querySelector('[data-level-up-xp-note]');
   note.textContent=isMonster?
     'Il GS resta invariato. XP minimi per '+(fromTotal+count)+' livelli di classe: '+
       minimumXpForLevel(fromTotal+count).toLocaleString('it-IT')+'. Gli XP già superiori vengono mantenuti.':
     count>xpAvailable?'L’avanzamento manuale aggiornerà anche gli XP minimi del nuovo livello.':
     'Livelli disponibili con gli XP attuali: '+xpAvailable+'.';
   dialog.querySelector('[data-level-up-confirm]').disabled=!die;
   paintHpTotal();
   void refreshImpact();
 };
 const paintHpTotal=()=>{
   const selected=selectedClass(),die=hitDieFor(selected);
   const inputs=[...hpRows.querySelectorAll('[data-level-up-hp]')];
   if(!die||!inputs.length)return;
   const con=Number(state.calculated?.abilities?.con?.modifier ??
     Math.floor((Number(record.abilities?.con??10)-10)/2));
   const rolls=inputs.map(input=>Number(input.value));
   const valid=rolls.every(value=>Number.isInteger(value)&&value>=1&&value<=die);
   const output=hpRows.querySelector('[data-level-up-hp-total]');
   if(output)output.textContent=valid?'PF totali acquisiti: +'+
     rolls.reduce((sum,roll)=>sum+Math.max(1,roll+con),0):'Inserisci un valore valido per ogni dado.';
   dialog.querySelector('[data-level-up-confirm]').disabled=!valid;
 };
 classSelect.addEventListener('change',paintPreview);
 countSelect.addEventListener('change',paintPreview);
 hpRows.addEventListener('input',paintHpTotal);
 paintPreview();
 dialog.querySelector('[data-level-up-cancel]').addEventListener('click',()=>closeDialog(dialog,{remove:true}));
 dialog.querySelector('[data-level-up-confirm]').addEventListener('click',async event=>{
   const button=event.currentTarget;
   if(button.disabled)return;
   button.disabled=true;
   try{
     const current=state.editor?.read();
     if(!current||current.id!==record.id)throw Error('Creatura cambiata.');
     const rows=rowsFor(current,'classes'),count=Number(countSelect.value);
     const selected=selectedClass();
     const faces=hitDieFor(selected);
     if(!selected||!faces||!Number.isInteger(count)||count<1||totalClassLevel(current)+count>20)
       throw Error('Livellaggio non valido.');
     const rolls=[...hpRows.querySelectorAll('[data-level-up-hp]')].map(input=>Number(input.value));
     if(rolls.length!==count||rolls.some(value=>!Number.isInteger(value)||value<1||value>faces))
       throw Error('Controlla i PF assegnati a ciascun livello.');
     const con=Number(state.calculated?.abilities?.con?.modifier ??
       Math.floor((Number(current.abilities?.con??10)-10)/2));
     let name=selected.name,source=selected.source;
     let fromLevel=selected.from,toLevel=fromLevel+count,classIndex=selected.index;
     let changes;
     if(classIndex>=0){
       if(!rows[classIndex]?.name||rows[classIndex].name!==name)
         throw Error('Classe modificata nel frattempo.');
       rows[classIndex].level=toLevel;
       changes=collectionPatch(current,'classes',rows);
     }else{
       if(rows.some(row=>row.name?.toLowerCase()===name.toLowerCase()))
         throw Error('Classe già posseduta.');
       const newRow={name,source,id:selected.reference.id||'',level:count};
       const empty=rows.findIndex(row=>!row.name);
       if(empty>=0){rows[empty]=newRow;classIndex=empty;}
       else{classIndex=rows.length;rows.push(newRow);}
       changes=collectionPatch(current,'classes',rows);
     }
     Object.assign(changes,levelUpHpPatch(current,rolls,con,
       {firstCharacterLevel:!isMonster&&totalClassLevel(current)===0}));
     // Preserve the same per-level projection shown before confirmation.
     let impactRows=[];
     try{impactRows=await getImpact(selected,count);}
     catch(error){console.warn('Progressione del livellaggio non disponibile',error);}
     await patch(changes);
     closeDialog(dialog,{remove:true});
     await render();
     openLevelUpProgressDialog({className:name,classSource:source,classIndex,
       fromLevel,toLevel,fromTotal,toTotal:fromTotal+count,impactRows,hpGain:
         changes.max_hp_base-Number(current.max_hp_base??current.max_hp??0)});
   }catch(error){button.disabled=false;message(errorMessage(error),true);}
 });
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 app.append(dialog);openDialog(dialog);
 // Numeric rules often arrive after the initial dialog render. Repaint
 // without requiring the user to touch a selector or lose entered HP.
 void rulesRequest.then(rules=>{
   hitDiceCatalog=rules.classMechanics||null;
   hitDiceLoad='ready';
   if(dialog.isConnected)paintPreview();
 }).catch(error=>{
   hitDiceLoad='error';
   console.warn('Dadi vita del livellaggio non disponibili',error);
   if(dialog.isConnected)paintPreview();
 });
}
function openPendingChoicesIndex(){
 const choices=state.calculated?.pending_choices||[];
 const levelReady=availableXpLevels(state.editor?.read()||{})>0;
 if(!choices.length&&!levelReady)return;
 app.querySelector('#pending-choice-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='pending-choice-dialog';
 dialog.className='sheet-context-dialog pending-choice-dialog pending-choice-index';
 dialog.innerHTML='<header class="sheet-context-head"><h2>Scelte dei privilegi</h2>'+
   dialogCloseButton('pending-choice-close','Chiudi','play-button')+'</header>'+
   '<div class="pending-choice-dialog-body pending-choices-notice-list">'+
   (levelReady?'<button type="button" data-act="level-up-open"><span>Level up <small>· Scegli la classe da livellare</small></span>'+
     '<span>↑ <span aria-hidden="true">›</span></span></button>':'')+
   choices.map(choice=>'<button type="button" data-act="pending-choice-open" data-choice-id="'+esc(choice.id)+'">'+
     '<span>'+esc(choice.name)+' <small>· '+esc(choice.label)+'</small></span>'+
     '<span>'+esc(choice.selected.length)+'/'+esc(choice.count)+' <span aria-hidden="true">›</span></span></button>').join('')+
   '</div>';
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 app.append(dialog);
 openDialog(dialog);
}
// Shared by direct selection and automatic one-to-one follow-up choices.
// A magical choice uses the existing Magia selector; all other structured
// choices use the ordinary pending-choice modal.
async function openCharacterChoice(choice){
 if(app.querySelector('#trait-benefits-dialog'))dismissTraitBenefitDialog();
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
 openPendingChoiceDialog(choice);
}
function openPendingChoiceDialog(choice){
 app.querySelector('#pending-choice-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='pending-choice-dialog';
 dialog.className='sheet-context-dialog pending-choice-dialog';
 dialog.dataset.choiceId=choice.id;
 // Checkboxes can be unchecked before save, including for a single choice.
 const inputType='checkbox';
 const labels=Object.fromEntries(SKILLS.map(([id,name])=>[id,name]));
 Object.assign(labels,abilities);
 const known=knownProficiencyOptions(state.editor?.read()||{},state.calculated||{},choice);
 const rows=choice.options.map(key=>{
   const mixed=choice.proficiency_kind==='mixed',at=mixed?key.indexOf(':'):-1;
   const kind=mixed?key.slice(0,at):'',item=mixed?key.slice(at+1):key;
   const label=choice.option_labels?.[key]||
     (kind==='skill'?'Abilità · ':kind==='tool'?'Strumento · ':'')+(labels[item]||item);
   if(choice.kind==='ability_fixed')
    return '<div class="pending-choice-option vtt-selectable"><span class="vtt-choice-check" aria-hidden="true">✓</span><span>'+esc(label)+' · +'+esc(choice.amounts?.[key]||0)+'</span></div>';
   return '<label class="pending-choice-option vtt-selectable'+(choice.count===1?' pending-choice-option--single':'')+'"><input type="'+inputType+
     '" name="pending-options" value="'+esc(key)+'" '+(choice.selected.includes(key)?'checked':'')+
     '><span class="vtt-choice-check" aria-hidden="true">✓</span><span>'+esc(label)+'</span>'+
     (known.has(key)?'<span class="pending-choice-known" title="Competenza già posseduta" aria-label="Competenza già posseduta">✓</span>':'')+
     '</label>'+Array.from({length:choice.option_rows?.[key]?.subchoices?.count||0},(_,i)=>
       '<label class="pending-choice-detail" data-pending-detail-for="'+esc(key)+'">'+
       esc(choice.option_rows[key].subchoices.placeholder||'Scelta')+' '+(i+1)+
       '<input type="text" maxlength="70" data-pending-option="'+esc(key)+'" data-pending-detail="'+i+'" value="'+
       esc(choice.subchoices?.[key]?.[i]||'')+'"></label>').join('');
 }).join('');
 const customValues=choice.custom_values||[];
 const customRow=choice.custom_allowed?
   '<div class="pending-choice-option pending-choice-custom vtt-selectable'+(choice.count===1?' pending-choice-option--single':'')+'">'+
     '<label class="pending-choice-custom-label"><input type="checkbox" name="pending-options" value="__custom__"'+
     (customValues.length?' checked':'')+'><span class="vtt-choice-check" aria-hidden="true">✓</span><span>＋ Personalizzata…</span></label>'+
     '<input type="text" data-pending-custom-value maxlength="250" autocomplete="off" '+
     'placeholder="'+(choice.proficiency_kind==='mixed'?'Nome dello strumento personalizzato':'Nome dello strumento o della lingua')+'" value="'+esc(customValues.join(', '))+'"'+
     (customValues.length?'':' disabled')+' aria-label="Nomi personalizzati, separati da virgole">'+
   '</div>':'';
 dialog.innerHTML='<header class="sheet-context-head"><div><small>'+esc(choice.name)+'</small>'+
   '<h2>'+esc(choice.label)+'</h2></div>'+
   dialogCloseButton('pending-choice-close','Chiudi','play-button')+'</header>'+
   '<div class="pending-choice-dialog-body"><p class="pending-choice-instruction">'+
   (choice.kind==='ability_fixed'?'Incrementi già applicati automaticamente dalla fonte selezionata.':
    'Scegli fino a '+esc(choice.count)+' '+(choice.count===1?'opzione':'opzioni')+
    ' concesse dal privilegio. Le scelte sono associate alla loro origine.')+'</p>'+
   (choice.kind==='advancement_feat'?'<input type="search" data-pending-filter placeholder="Cerca un talento" aria-label="Cerca un talento">':'')+
   '<p class="pending-choice-progress" aria-live="polite">'+esc(choice.selected.length)+' / '+esc(choice.count)+' selezionate</p>'+
   (rows||customRow?'<div class="pending-choice-options vtt-selection-list">'+rows+customRow+'</div>':
    '<p class="hint">Nessuna opzione risolta dal catalogo locale. Le scelte già salvate rimangono inalterate.</p>')+
   '</div><footer class="pending-choice-actions"><button type="button" data-act="pending-choice-close">'+
   (choice.kind==='ability_fixed'?'Chiudi':'Annulla')+'</button>'+
   (choice.kind==='ability_fixed'?'':'<button type="button" data-act="pending-choice-save"'+(rows||customRow?'':' disabled')+'>Applica</button>')+'</footer>';
 const update=()=>{
   if(choice.kind==='ability_fixed')return;
   const checked=[...dialog.querySelectorAll('[name="pending-options"]:checked')];
   const custom=dialog.querySelector('[data-pending-custom-value]');
   const customChecked=checked.some(row=>row.value==='__custom__');
   const customNames=customChecked?(custom?.value||'').split(',').map(x=>x.trim()).filter(Boolean):[];
   if(custom)custom.disabled=!customChecked;
   const total=checked.filter(row=>row.value!=='__custom__').length+customNames.length;
   const detailsInvalid=[...dialog.querySelectorAll('[data-pending-detail-for]')].map(row=>{
     const chosen=checked.some(input=>input.value===row.dataset.pendingDetailFor);
     row.hidden=!chosen;return chosen&&!row.querySelector('input').value.trim();
   }).some(Boolean);
   const invalid=detailsInvalid||(customChecked&&(!customNames.length||customNames.some(name=>name.length>80)))||
     total>choice.count||new Set(customNames.map(x=>x.toLowerCase())).size!==customNames.length;
   const progress=dialog.querySelector('.pending-choice-progress');
   if(progress)progress.textContent=total+' / '+choice.count+' selezionate'+
     (invalid?' · Controlla i nomi personalizzati':'');
   for(const input of dialog.querySelectorAll('[name="pending-options"]')){
     input.disabled=!input.checked&&total>=choice.count;
   }
   const save=dialog.querySelector('[data-act="pending-choice-save"]');
   if(save)save.disabled=invalid;
 };
 dialog.addEventListener('change',update);
 dialog.addEventListener('input',update);
 dialog.querySelector('[data-pending-filter]')?.addEventListener('input',event=>{
   const query=String(event.target.value||'').trim().toLocaleLowerCase();
   for(const row of dialog.querySelectorAll('.pending-choice-options .pending-choice-option'))
     row.hidden=!!query&&!row.textContent.toLocaleLowerCase().includes(query);
 });
 dialog.querySelector('[data-pending-custom-value]')?.addEventListener('input',update);
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 app.append(dialog);
 update();
 openDialog(dialog);
}


async function openBackgroundPickerDialog(rawIndex='primary'){
 const editor=state.editor,record=editor?.read(),creatureId=state.creatureId;
 if(!editor||!record)throw Error('Apri prima la scheda del personaggio.');
 const index=rawIndex==='primary'?null:Number(rawIndex);
 if(index!==null&&(!Number.isSafeInteger(index)||index<0||!rowsFor(record,'backgrounds_catalog')[index]))
  throw Error('Background aggiuntivo non più disponibile.');
 document.querySelector('#background-picker-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='background-picker-dialog';
 dialog.className='feat-picker-dialog background-picker-dialog';
 dialog.setAttribute('aria-labelledby','background-picker-title');
 dialog.innerHTML='<header class="feat-picker-head"><div><small>PERSONAGGIO · ORIGINI</small>'+
   '<h2 id="background-picker-title">Scegli background</h2></div>'+
   dialogCloseButton('background-picker-close','Chiudi')+'</header>'+
   '<div class="feat-picker-body">'+
   '<label class="feat-picker-search">'+actionGlyph('search')+
   '<input type="search" data-background-search autocomplete="off" placeholder="Cerca per nome o fonte" aria-label="Cerca background"></label>'+
   '<div class="feat-picker-count" data-background-count>Caricamento background…</div>'+
   '<div class="feat-picker-results" data-background-results role="list"><p class="hint">Caricamento catalogo…</p></div>'+
   '<div class="feat-picker-detail" data-background-detail hidden></div>'+
   '<p class="feat-picker-feedback" data-background-feedback role="status" aria-live="polite"></p></div>';
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 document.body.append(dialog);
 openDialog(dialog);
 let rows=[],query='',limit=50,selected=-1,saving=false,loading=true,error='';
 const output=dialog.querySelector('[data-background-results]');
 const detail=dialog.querySelector('[data-background-detail]');
 const feedback=dialog.querySelector('[data-background-feedback]');
 const selectedName=index===null?record.background:
   rowsFor(record,'backgrounds_catalog')[index]?.name;
 const selectedSource=index===null?record.background_source:
   rowsFor(record,'backgrounds_catalog')[index]?.source;
 const current=entry=>entry&&entry.name===selectedName&&
   String(entry.source||'')===String(selectedSource||'');
 const repaint=()=>{
  if(!dialog.isConnected)return;
  if(loading){output.innerHTML='<p class="hint">Caricamento background…</p>';return;}
  if(error){output.innerHTML='<p class="hint">'+esc(error)+'</p>';return;}
  const found=rows.filter(row=>matchesSearch(query,row.name,row.source));
  dialog.querySelector('[data-background-count]').textContent=found.length+' background disponibili';
  output.innerHTML=(index===null?'<div class="feat-picker-row"><button type="button" class="feat-picker-row-name" data-background-clear>'+
     '<strong>Nessuno</strong><small>Rimuovi il background principale</small></button></div>':'')+
   found.slice(0,limit).map(row=>{
    const i=rows.indexOf(row),active=i===selected,owned=current(row);
    return '<div class="feat-picker-row'+(active?' is-selected':'')+'" role="listitem">'+
      '<button type="button" class="feat-picker-row-name" data-background-preview="'+i+'" aria-expanded="'+active+'">'+
      '<strong>'+esc(row.name)+'</strong><small>'+esc(row.source||'Fonte non specificata')+'</small></button>'+
      '<button type="button" class="feat-picker-add" data-background-choose="'+i+'"'+(owned||saving?' disabled':'')+'>'+
      (owned?'✓ Selezionato':'Scegli')+'</button></div>';
   }).join('')+
   (found.length>limit?'<button type="button" class="feat-picker-more" data-background-more>Mostra altri '+Math.min(50,found.length-limit)+'</button>':'');
  if(!found.length)output.innerHTML+='<p class="hint">Nessun background corrispondente.</p>';
 };
 dialog.querySelector('[data-background-search]').addEventListener('input',event=>{
  query=event.target.value;selected=-1;limit=50;detail.hidden=true;repaint();
 });
 dialog.addEventListener('click',async event=>{
  const button=event.target.closest('button');if(!button||saving)return;
  if(button.dataset.act==='background-picker-close'){closeDialog(dialog,{remove:true});return;}
  if(button.hasAttribute('data-background-more')){limit+=50;repaint();return;}
  if(button.hasAttribute('data-background-preview')){
    const i=Number(button.dataset.backgroundPreview),entry=rows[i];if(!entry)return;
    if(selected===i){selected=-1;detail.hidden=true;repaint();return;}
    selected=i;detail.hidden=false;detail.innerHTML='<p class="hint">Caricamento descrizione…</p>';repaint();
    const full=await detailedEntry('backgrounds',entry);
    if(!dialog.isConnected||selected!==i)return;
    detail.innerHTML='<header><strong>'+esc(full.name||entry.name)+'</strong><small>'+esc(entry.source||'')+'</small></header>'+
      '<div class="feat-picker-description">'+esc(flattenDescription(full)||'Descrizione non disponibile nel catalogo locale.')+'</div>';
    return;
  }
  if(!button.hasAttribute('data-background-choose')&&!button.hasAttribute('data-background-clear'))return;
  const entry=button.hasAttribute('data-background-clear')?{}:rows[Number(button.dataset.backgroundChoose)];
  if(!entry||state.editor!==editor||state.creatureId!==creatureId)
    throw Error('La scheda è cambiata: riapri il selettore.');
  const latest=editor.read();
  if(entry.name&&!availableReferenceRows(latest,'background','backgrounds',{backgrounds:rows})
      .some(row=>row===entry))
    throw Error('Background non consentito da queste regole.');
  saving=true;feedback.textContent='Salvataggio del background…';repaint();
  try{
    const changes=index===null?
      {...referencePatch(latest,'background',entry),...(entry.name?quickGrantPatch(latest,entry):{})}:
      rowReferencePatch(latest,'backgrounds_catalog',index,'name',entry);
    await patch(changes);
    closeDialog(dialog,{remove:true});
    await render();
  }catch(err){saving=false;feedback.textContent=errorMessage(err);repaint();}
 });
 try{
  const allBackgrounds=await catalogEntries('backgrounds');
  rows=availableReferenceRows(record,'background','backgrounds',{backgrounds:allBackgrounds});
  state.referenceCatalogs.backgrounds=allBackgrounds;
 }catch(err){error='Catalogo background non disponibile: '+errorMessage(err);}
 finally{loading=false;repaint();}
}

async function openFeatPickerDialog(){
 const editor=state.editor,record=editor?.read();
 if(!record)throw Error('Apri un personaggio prima di aggiungere talenti.');
 document.querySelector('#feat-picker-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='feat-picker-dialog';dialog.className='feat-picker-dialog';
 dialog.setAttribute('aria-labelledby','feat-picker-title');
 let candidates=[],query='',limit=48,selected=-1,originId='',loading=true,failed='',saving=false;
 const catalogs=await loadRuleCatalogs().catch(()=>({}));
 const origins=featGrantOrigins(record,state.calculated||{},catalogs.abilityGrants||{});
 const sections=[
  ['advancement','Privilegi di progressione'],['trait','Tratti che concedono talenti'],
  ['origin','Origini del personaggio'],['other','Aggiunta manuale']
 ];
 const choices='<option value="">Seleziona il tratto o l’origine…</option>'+
  sections.map(([group,label])=>{
   const options=origins.filter(row=>row.group===group);
   return options.length?'<optgroup label="'+esc(label)+'">'+options.map(row=>
    '<option value="'+esc(row.id)+'">'+esc(row.label)+'</option>').join('')+'</optgroup>':'';
  }).join('');
 dialog.innerHTML='<header class="sheet-context-head feat-picker-head"><div><small>PERSONAGGIO · TALENTI</small>'+
  '<h2 id="feat-picker-title">Aggiungi talento</h2></div>'+
  dialogCloseButton('feat-picker-close','Chiudi')+'</header>'+
  '<div class="feat-picker-body">'+
  '<label class="feat-picker-origin-label">Tratto di origine'+
  '<select data-feat-origin required>'+choices+'</select></label>'+
  '<p class="feat-picker-origin-note" data-feat-origin-note>Seleziona l’origine del talento.</p>'+
  '<label class="feat-picker-search">'+actionGlyph('search')+
  '<input type="search" data-feat-search placeholder="Cerca per nome o fonte" autocomplete="off" aria-label="Cerca talento"></label>'+
  '<div class="feat-picker-count" data-feat-count></div>'+
  '<div class="feat-picker-results" data-feat-results role="list">'+
  '<p class="hint">Caricamento talenti…</p></div>'+
  '<div class="feat-picker-detail" data-feat-detail hidden></div>'+
  '<p class="feat-picker-feedback" data-feat-feedback role="status" aria-live="polite"></p></div>';
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 document.body.append(dialog);
 openDialog(dialog);
 const resultList=dialog.querySelector('[data-feat-results]');
 const detail=dialog.querySelector('[data-feat-detail]');
 const status=dialog.querySelector('[data-feat-feedback]');
 const originNote=dialog.querySelector('[data-feat-origin-note]');
 const owned=()=>new Set((editor.read().feats_catalog||[]).map(x=>
  String(x?.name||x).toLowerCase()+'|'+String(x?.source||'').toLowerCase()));
 const visible=()=>candidates.filter(row=>matchesSearch(query,row.display_name||row.name,row.source));
 const paint=()=>{
  if(!dialog.isConnected)return;
  const filtered=visible(),known=owned(),shown=filtered.slice(0,limit);
  dialog.querySelector('[data-feat-count]').textContent=loading?'Caricamento catalogo…':
   failed?'Catalogo non disponibile':filtered.length+' talenti disponibili';
  if(failed){resultList.innerHTML='<p class="hint">'+esc(failed)+'</p>';return;}
  if(loading){resultList.innerHTML='<p class="hint">Caricamento talenti…</p>';return;}
  resultList.innerHTML=shown.map(row=>{
    const i=candidates.indexOf(row);
    const has=known.has(String(row.name).toLowerCase()+'|'+String(row.source||'').toLowerCase());
    const active=i===selected;
    return '<div class="feat-picker-row'+(active?' is-selected':'')+'" role="listitem">'+
      '<button type="button" class="feat-picker-row-name" data-feat-detail-index="'+i+
      '" aria-expanded="'+active+'" aria-label="Dettagli di '+esc(row.name)+'">'+
      '<strong>'+esc(row.display_name||row.name)+'</strong><small>'+esc(row.source||'Senza fonte')+'</small></button>'+
      '<button type="button" class="feat-picker-add'+(has?' is-selected':'')+
      '" data-feat-add-index="'+i+'"'+(has||saving?' disabled':'')+' aria-label="'+
      (has?'Talento già posseduto: ':'Aggiungi ')+esc(row.name)+'">'+
      (has?'✓ Posseduto':'+ Aggiungi')+'</button></div>';
  }).join('')||'<p class="hint">Nessun talento corrispondente.</p>';
  if(filtered.length>shown.length)resultList.innerHTML+='<button type="button" class="feat-picker-more" data-feat-more>Mostra altri '+Math.min(48,filtered.length-shown.length)+'</button>';
 };
 const showDetail=async i=>{
  const entry=candidates[i];if(!entry||!dialog.isConnected)return;
  if(selected===i){selected=-1;detail.hidden=true;paint();return;}
  selected=i;paint();detail.hidden=false;
  detail.innerHTML='<p class="hint">Caricamento descrizione…</p>';
  try{
   const full=await detailedEntry('feats',entry);
   if(!dialog.isConnected||selected!==i)return;
   const description=flattenDescription(full)||'Descrizione non disponibile nel catalogo locale.';
   detail.innerHTML='<header><strong>'+esc(entry.display_name||full.name||entry.name)+'</strong><small>'+esc(entry.source||'')+'</small>'+
    '<button type="button" data-feat-detail-close aria-label="Chiudi dettagli">×</button></header>'+
    '<div class="feat-picker-description">'+esc(description)+'</div>';
  }catch(error){if(dialog.isConnected&&selected===i)
   detail.innerHTML='<p class="hint">'+esc(errorMessage(error))+'</p>';}
 };
 dialog.addEventListener('input',event=>{
  if(!event.target.matches('[data-feat-search]'))return;
  query=event.target.value;limit=48;selected=-1;detail.hidden=true;paint();
 });
 dialog.addEventListener('change',event=>{
  if(!event.target.matches('[data-feat-origin]'))return;
  originId=event.target.value;
  const origin=origins.find(row=>row.id===originId);
  originNote.textContent=origin?.note||(
   originId==='manual'?'Il talento sarà aggiunto come tratto manuale.':
   origin?'Il talento rimarrà collegato a questa origine e comparirà fra i tratti.':
    'Seleziona da quale privilegio, specie o background proviene il talento.');
  status.textContent='';
 });
 dialog.addEventListener('click',async event=>{
  const button=event.target.closest('button');if(!button||saving)return;
  if(button.dataset.act==='feat-picker-close'){
   closeDialog(dialog,{remove:true});return;
  }
  if(button.hasAttribute('data-feat-detail-close')){
   selected=-1;detail.hidden=true;paint();return;
  }
  if(button.hasAttribute('data-feat-more')){limit+=48;paint();return;}
  if(button.hasAttribute('data-feat-detail-index')){
   await showDetail(Number(button.dataset.featDetailIndex));return;
  }
  if(!button.hasAttribute('data-feat-add-index'))return;
  const entry=candidates[Number(button.dataset.featAddIndex)];
  if(!entry||!originId){status.textContent='Seleziona prima il tratto di origine.';return;}
  if(editor!==state.editor){status.textContent='La scheda è cambiata: riapri il selettore.';return;}
  saving=true;status.textContent='Aggiunta del talento…';paint();
  try{
    const current=editor.read();
    const fresh=await computeLocalData(current);
    const rules=await loadRuleCatalogs();
    if(featAlreadyOwned(current,entry))throw Error('Talento già posseduto.');
    const patchData=addFeatWithOrigin(current,entry,originId,fresh,rules.abilityGrants||{});
    // Merge portable homebrew proficiency grants *after* the previous ASI feat
    // has been removed, otherwise switching talents can lose new grants.
    const granted=quickGrantPatch(current,{...entry,category:entry.category||entry._category||'feats'});
    const previousChoices=current.proficiency_choices||[];
    const newChoices=(granted.proficiency_choices||[]).filter(row=>
      !previousChoices.some(saved=>saved.origin_id===row.origin_id&&
        saved.kind===row.kind&&saved.key===row.key));
    const choices=patchData.proficiency_choices||previousChoices;
    await patch({...patchData,...(newChoices.length||patchData.proficiency_choices?
      {proficiency_choices:[...choices,...newChoices]}:{})});
    closeDialog(dialog,{remove:true});
    await render();
    message('Talento '+entry.name+' aggiunto alla scheda.');
  }catch(error){
    status.textContent=errorMessage(error);saving=false;paint();
  }
 });
 try{
  const all=await catalogEntries('feats');
  if(!dialog.isConnected)return;
  candidates=expandedSpellFeatOptions(all.filter(row=>row?.name&&row?.source&&isContentAvailableForRules(row,record.rules_version)),catalogs.classMechanics?.additional_spells||[])
    .sort((a,b)=>String(a.display_name||a.name).localeCompare(String(b.display_name||b.name),'it',{sensitivity:'base'}));
 }catch(error){failed='Impossibile caricare i talenti: '+errorMessage(error);}
 finally{loading=false;paint();}
}

function openRemoveFeatDialog(originKey){
 const record=state.editor?.read();
 if(!record)throw Error('Apri una creatura prima di rimuovere talenti.');
 removeOwnedFeatPatch(record,originKey);
 const feat=(record.feats_catalog||[]).map(row=>typeof row==='string'?{name:row}:row).find(row=>row?.name&&
   'feat|'+(row.id||String(row.name).trim().toLowerCase()+'|'+String(row.source||'').trim().toLowerCase())===originKey);
 if(!feat)throw Error('Talento non più disponibile.');
 app.querySelector('#feat-remove-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='feat-remove-dialog';dialog.className='sheet-context-dialog feat-remove-dialog';
 dialog.dataset.featKey=originKey;
 dialog.innerHTML='<header class="sheet-context-head"><h2>Rimuovere talento?</h2>'+
   dialogCloseButton('feat-remove-cancel','Chiudi','play-button')+'</header>'+
   '<div class="sheet-context-body"><p>Vuoi rimuovere <strong>'+esc(feat.name)+'</strong> dai talenti posseduti? '+
   'Le competenze scelte tramite questo talento non saranno più concesse.</p></div>'+
   '<footer class="pending-choice-actions"><button type="button" data-act="feat-remove-cancel">Annulla</button>'+
   '<button type="button" data-act="feat-remove-confirm">Rimuovi talento</button></footer>';
 dialog.addEventListener('close',()=>dialog.remove(),{once:true});
 app.append(dialog);
 openDialog(dialog);
}
async function handleAction(target){
  const act=target.dataset.act;
  if(act==='server-backup-now'){serverBackups.schedule(true);return;}
  if(['inventory-bulk-export','inventory-bulk-send','inventory-bulk-delete'].includes(act)){
    if(state.sheet!=='inventory'||!state.editor)throw Error('Apri prima un inventario.');
    await flushPendingFields();
    const record=state.editor.read(),indices=[...state.inventorySelectedIndices].sort((a,b)=>a-b);
    if(!indices.length||indices.some(i=>!record.inventory?.[i]))throw Error('Seleziona almeno un oggetto.');
    if(act==='inventory-bulk-delete'){
      if(!await confirmInventoryDeletion(indices.map(i=>record.inventory[i])))return;
      const inventory=structuredClone(record.inventory);
      for(const i of [...indices].reverse())inventory.splice(i,1);
      state.inventorySelectedIndices.clear();
      state.inventorySelectedIndex=0;state.sheetPopup='';
      await patch({inventory});await render();
      message('Eliminati '+indices.length+' oggetti dall’inventario.');
      return;
    }
    if(act==='inventory-bulk-send'){
      const title=indices.length===1?record.inventory[indices[0]].name:indices.length+' oggetti';
      await openSendDialog('inventory',title,()=>exportInventoryItems(record,indices),message);
      return;
    }
    const payload=await exportInventoryItems(record,indices);
    if(await download(new Blob([JSON.stringify(payload,null,2)],{type:'application/json'}),
      'vtt-inventario-selezionato.json'))
      message('Esportati '+indices.length+' oggetti con quantità e dati homebrew.');
    return;
  }


  if(act==='info-portrait-miniature'){
    if(!state.editor||state.sheet!=='info')throw Error('Apri prima la scheda Info.');
    const editor=state.editor,creatureId=state.creatureId;
    const miniatureId=editor.read().current_miniature_id||editor.read().default_miniature_id||'';
    target.disabled=true;
    try{
      await loadSessionMiniatures();
      const image=await prepareMiniaturePortrait(editor.read(),state.miniatureCatalog);
      const current=state.editor?.read();
      if(state.editor!==editor||state.creatureId!==creatureId||state.sheet!=='info'||
         (current?.current_miniature_id||current?.default_miniature_id||'')!==miniatureId)
        throw Error('La scheda o la miniatura è cambiata. Riprova.');
      await patch({sheet_portrait_data:image});
      await render();
      message('Immagine della miniatura salvata nella scheda, disponibile anche offline.');
    }finally{target.disabled=false;}
    return;
  }
  if(act==='info-portrait-remove'){
    if(!state.editor||state.sheet!=='info')throw Error('Apri prima la scheda Info.');
    await patch({sheet_portrait_data:''});
    await render();
    message('Foto rimossa dalla scheda.');
    return;
  }
  if(act==='inventory-search-more'){
    state.inventorySearchLimit+=75;
    paintInventorySearchResults();return;
  }
  if(act==='inventory-search-retry'){
    state.inventorySearchCatalogError='';
    ensureInventorySearchCatalog();
    paintInventorySearchResults();return;
  }
  if(act==='inventory-search-result'){
    const item=state.inventorySearchMatches[Number(target.dataset.searchResultIndex)];
    if(!item)throw Error('Risultato della ricerca non più disponibile.');
    if(item.kind==='catalog'){openInventorySearchAddDialog(item.catalogIndex);return;}
    const record=state.editor?.read();
    if(!record||!item.indices.length)throw Error('Oggetto posseduto non disponibile.');
    setInventoryVisibleSections(record,inventorySectionKeys(record));
    state.inventorySubtab='items';
    state.inventoryHighlightedIndices=item.indices.filter(index=>record.inventory?.[index]);
    state.inventorySelectedIndex=state.inventoryHighlightedIndices[0]??-1;
    state.sheetPopup='';
    state.sheetSearch.set(state.creatureId+'|inventory','');
    await render();
    app.querySelector('[data-inventory-search-index="'+state.inventorySelectedIndex+'"]')?.
      scrollIntoView?.({block:'center',behavior:'smooth'});
    return;
  }
  if(act==='inventory-search-add-close'){
    closeDialog(app.querySelector('#inventory-search-add-dialog'),{remove:true});return;
  }
  if(act==='inventory-search-add-confirm'){
    const dialog=app.querySelector('#inventory-search-add-dialog');
    const catalogIndex=Number(dialog?.dataset.catalogIndex);
    const entry=state.referenceCatalogs.items?.[catalogIndex];
    const record=state.editor?.read();
    if(!dialog||!entry||!record||!isContentAvailableForRules(entry,record.rules_version))throw Error('Oggetto del catalogo non disponibile per queste regole.');
    const quantity=Number(dialog.querySelector('#inventory-search-add-quantity')?.value);
    if(!Number.isSafeInteger(quantity)||quantity<1||quantity>99999)
      throw Error('La quantità deve essere compresa tra 1 e 99999.');
    const destination=dialog.querySelector('#inventory-search-add-section')?.value;
    if(!inventoryContainers(record).some(section=>section.id===destination))
      throw Error('Sezione inventario non valida.');
    const owned=createOwnedItem(entry,'pwa_'+crypto.randomUUID());
    owned.quantity=quantity;
    if(destination!==DEFAULT_INVENTORY_CONTAINER)owned.container_id=destination;
    const index=(record.inventory||[]).length;
    closeDialog(dialog,{remove:true});
    state.inventoryHighlightedIndices=[index];
    state.inventorySelectedIndex=index;
    state.sheetSearch.set(state.creatureId+'|inventory','');
    focusInventorySection(record,destination===DEFAULT_INVENTORY_CONTAINER?'items':'container:'+destination);
    await patch({inventory:[...(record.inventory||[]),owned]});
    await render();
    message(quantity+' × '+(entry.name||'Oggetto')+' aggiunti a '+
      (inventoryContainers(record).find(row=>row.id===destination)?.name||'Zaino')+'.');
    return;
  }
  if(act==='catalog-more'){
    state.catalogResultLimit+=90;
    const results=app.querySelector('#catalog-results');
    if(results){
      const previousScroll=results.scrollTop;
      results.innerHTML=renderCatalogRows();
      results.scrollTop=previousScroll;
    }
    return;
  }
  if(act==='spell-results-more'){
    state.spellResultLimit+=60;
    const results=app.querySelector('#spell-results');
    if(results){
      const previousScroll=results.scrollTop;
      results.innerHTML=renderSpellResults();
      results.scrollTop=previousScroll;
    }
    return;
  }
  if(act==='feat-open-trait'){
    const record=state.editor?.read();
    const index=Number(target.dataset.featIndex);
    const feat=record?.feats_catalog?.[index];
    if(!record||!Number.isInteger(index)||index<0||!feat)
      throw Error('Talento non più presente nella scheda.');
    const entry=typeof feat==='string'?{name:feat}:feat;
    const originKey=featTraitOriginKey(entry);
    state.sheet='info';state.sheetPopup='';state.sheetPopupTitle='';
    const findTrait=()=>state.traitRows.find(row=>row.category==='talenti'&&
      row.rank===0&&row.origin_key===originKey);
    if(!findTrait())await render();
    const trait=findTrait();
    if(!trait){message('Tratto del talento non disponibile nella scheda.',true);return;}
    const match=[...app.querySelectorAll('.play-info-traits .trait-card')]
      .find(card=>card.dataset.traitKey===trait.key);
    if(!match){message('La sezione Tratti non è disponibile.',true);return;}
    const disclosure=match.closest('.play-traits-disclosure');
    if(disclosure)disclosure.open=true;
    match.open=true;
    match.scrollIntoView?.({block:'center',behavior:'smooth'});
    match.querySelector('summary')?.focus?.({preventScroll:true});
    return;
  }
  if(act==='feat-remove'){
    openRemoveFeatDialog(target.dataset.featKey||'');return;
  }
  if(act==='feat-remove-cancel'){
    const dialog=app.querySelector('#feat-remove-dialog');
    closeDialog(dialog,{remove:true});
    return;
  }
  if(act==='feat-remove-confirm'){
    const dialog=app.querySelector('#feat-remove-dialog');
    const key=dialog?.dataset.featKey||'';
    if(!key)throw Error('Seleziona il talento da rimuovere.');
    const changes=removeOwnedFeatPatch(state.editor.read(),key);
    dialog.remove();await patch(changes);await render();return;
  }
  if(act==='level-up-open'){
    closeDialog(app.querySelector('#pending-choice-dialog'),{remove:true});
    await openLevelUpClassDialog();return;
  }
  if(act==='pending-choice-manage'){
    openPendingChoicesIndex();return;
  }
  if(act==='pending-choice-open'){
    const choice=(state.calculated?.pending_choices||[]).find(row=>row.id===target.dataset.choiceId);
    if(!choice)throw Error('Scelta non disponibile nella scheda.');
    await openCharacterChoice(choice);return;
  }
  if(act==='level-up-placeholder-close'){
    closeDialog(app.querySelector('#level-up-progress-dialog'),{remove:true});return;
  }
  if(act==='level-up-class-close'){
    closeDialog(app.querySelector('#class-level-up-dialog'),{remove:true});return;
  }
  if(act==='pending-choice-close'){
    const dialog=app.querySelector('#pending-choice-dialog');
    closeDialog(dialog,{remove:true});
    return;
  }
  if(act==='pending-choice-save'){
    const dialog=app.querySelector('#pending-choice-dialog');
    const choice=(state.calculated?.pending_choices||[]).find(row=>row.id===dialog?.dataset.choiceId);
    if(!choice)throw Error('La scelta è cambiata: riapri il selettore.');
    const customField=dialog.querySelector('[data-pending-custom-value]');
    const selected=[...dialog.querySelectorAll('[name="pending-options"]:checked')].flatMap(row=>
      row.value==='__custom__'?(customField?.value||'').split(',').map(v=>v.trim())
        .filter(Boolean).map(value=>'__custom__:'+value):[row.value]);
    const editor=state.editor,creatureId=state.creatureId,current=editor.read();
    // Validate once again against freshly derived grants before persisting.
    const fresh=await computeLocalData(current);
    const live=fresh.pending_choices.find(row=>row.id===choice.id);
    if(!live)throw Error('Il privilegio non concede più questa scelta.');
    const details=Object.fromEntries(selected.map(id=>[id,
      [...dialog.querySelectorAll('[data-pending-option]')].filter(input=>input.dataset.pendingOption===id)
        .map(input=>input.value)]));
    const update=savePendingChoice(current,live,selected,details);
    await patch(update);
    dialog.remove();await render();
    if(live.kind==='subclass'||live.kind==='subrace')return;
    // Render and inspect actual saved choices before opening anything else.
    // Several new pending choices or old unrelated choices must never open a
    // guessed next dialog. A re-opened modal/changed character wins.
    if(state.editor!==editor||state.creatureId!==creatureId||
       app.querySelector('#pending-choice-dialog'))return;
    const followUp=singleNewPendingChoice(fresh.pending_choices,
      state.calculated?.pending_choices||[],live);
    if(followUp)await openCharacterChoice(followUp);
    return;
  }
  if(act==='battle-action-jump'){
    const actionId=String(target.dataset.actionId||'');
    if(actionId==='ability_checks'){
      const checks=app.querySelector('#sheet-play-view [data-battle-action="checks"]');
      if(!checks)return;
      checks.open=true;
      state.disclosureState.set('battle-disclosure:checks',true);
      for(const group of checks.querySelectorAll('.play-battle-action-group[data-action-ability]')){
        group.open=true;
        state.disclosureState.set('battle-ability:'+group.dataset.actionAbility,true);
      }
      checks.scrollIntoView({behavior:'smooth',block:'start'});
      checks.querySelector(':scope > summary')?.focus({preventScroll:true});
      return;
    }
    const panel=app.querySelector('#sheet-play-view [data-battle-action="others"]');
    const action=[...panel?.querySelectorAll('[data-attack-id]')||[]]
      .find(node=>node.dataset.attackId===actionId);
    if(!panel||!action)return;
    panel.open=true;
    const timing=action.closest('.play-battle-action-group');
    if(timing)timing.open=true;
    state.disclosureState.set('battle-disclosure:others',true);
    if(timing)state.disclosureState.set('battle-timing:others:'+timing.dataset.actionTiming,true);
    action.scrollIntoView({behavior:'smooth',block:'center'});
    action.querySelector('.play-battle-attack-details>summary')?.focus({preventScroll:true});
    return;
  }
  if(act==='sheet-context'){if(target.dataset.sheetContext==='scroll-create')state.scrollSpellQuery='';state.sheetPopupTitle=target.title||target.querySelector('.play-row-copy strong')?.textContent||target.getAttribute('aria-label')||'Dettagli';state.sheetPopup=target.dataset.sheetContext;if(state.sheetPopup.startsWith('item:'))state.inventorySelectedIndex=Number(state.sheetPopup.slice(5));await render();return;}
  if(act==='sheet-context-close'){await closeSheetContext();return;}
  if(act==='battle-competences-open'){
    if(!state.editor)throw Error('Apri prima una creatura');
    returnToBattleFromCompetences=true;
    state.sheet='info';state.sheetPopup='tools';state.sheetPopupTitle='Competenze';
    await render();return;
  }
  if(act==='sheet-inspiration-toggle'){
    if(!state.editor)throw Error('Apri prima una creatura');
    await patch({inspiration:!Boolean(state.editor.read().inspiration)});
    await render();return;
  }
  if(act==='condition-remove'){
    const c=state.editor?.read(),id=String(target.dataset.conditionId||'');
    if(!c)throw Error('Creatura non disponibile.');
    const changes=exhaustionRemovablePatch(c,id);
    if(!changes)throw Error('Condizione non più attiva.');
    await patch(changes);await render();return;
  }
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
  if(act==='tracker-trait-use'){
    const creature=state.editor?.read();if(!creature)throw Error('Creatura non disponibile');
    const calculated=await computeLocalData(creature);
    await activateSubclassTracker(creature,calculated,
      String(target.dataset.trackerId||''),String(target.dataset.originId||''));
    return;
  }
  if(act==='end-racial-power'){
    const current=state.editor?.read();
    if(!current?.active_class_features?.['racial:celestial_revelation'])
      throw Error('Nessuna manifestazione celestiale attiva.');
    const active={...current.active_class_features};
    delete active['racial:celestial_revelation'];
    await patch({active_class_features:active});await render();return;
  }
  if(act==='battle-use-ability'){
    const c=state.editor?.read();if(!c)throw Error('Creatura non disponibile');
    const calculated=await computeLocalData(c);
    const panels=battleActionPanels(calculated.companion_view||c,calculated,state.spellCatalog||[],state.featureActionOverrides||[],
      state.generalActionSupplements||[],readActionVariants(),
      abilitiesForCreature(c,state.abilityCatalog||[],calculated));
    const requested=String(target.dataset.abilityId||'');
    const power=requested.startsWith('activated:')?
      abilitiesForCreature(c,state.abilityCatalog||[],calculated)
        .find(row=>String(row.id)===requested.slice('activated:'.length)):null;
    const ability=panels.abilityEntries.find(row=>
      String(row.id||row.ability_id||row.name)===requested)||
      (power?{...power,cost:power.resource_cost??(power.tracker_id?1:0)}:null);
    if(!ability)throw Error('Capacità non disponibile per questa creatura.');
    // Generic typed attack abilities open the same unified d20 popup as
    // ordinary weapons. No special-case code is needed for a specific race.
    if(ability.mode==='spell_imprint'){
      await openSpellImprintDialog(c,calculated,ability);return;
    }
    if(ability.roll_attack){
      const roll=abilityAttackRoll(ability,calculated);
      if(!roll)throw Error('L’attacco collegato a questa capacità non è disponibile.');
      await handleAction({dataset:{act:'sheet-roll',target:roll.target,label:roll.label}});
      return;
    }
    if(ability.rule_action_id==='wild_shape'||ability.id==='vtt_wild_shape'||ability.ability_id==='vtt_wild_shape'){
      await handleAction({dataset:{act:'miniature-pick',miniatureKind:'current',wildShape:'true'}});return;
    }
    if(ability.class_feature_id){
      await activateClassAbility(c,calculated,ability);return;
    }
    const persistentKey=String(target.dataset.persistentKey||ability.persistent_key||power?.persistent_key||'');
    if(ability.target_mode==='single_token'&&state.paired&&state.online){
      await startTargetedAbility(c,ability,persistentKey,requested);return;
    }
    if(ability.area_shape&&state.paired&&state.online){
      await startAreaAbility(c,ability,persistentKey,requested);return;
    }
    await activateOtherAbility(c,ability,persistentKey,requested);
    return;
  }
  if(act==='monster-action-use'){
    const creature=state.editor?.read();
    if(!creature)throw Error('Creatura non disponibile.');
    const calculated=await computeLocalData(creature);
    await patch(current=>monsterActionUsePatch(current,calculated,String(target.dataset.monsterActionId||'')));
    await render();return;
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
      await patch(selectionStateActivationPatch(c,calculated,key.slice('trait_state:'.length)));
      await render();return;
    }
    if(!Object.hasOwn(c.active_class_features||{},key))throw Error('Capacità non attiva.');
    if(key==='wild_shape'){
      await applyFormPatch(c,endWildShapePatch(c));await render();return;
    }
    const temporary=endTemporaryConditionPatch(c,key);
    if(Object.keys(temporary).length){await patch(temporary);await render();return;}
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
  if(act==='creature-variants'){
    await flushPendingFields();
    const editor=state.editor,creatureId=state.creatureId;
    const check=()=>{if(state.editor!==editor||state.creatureId!==creatureId)throw Error('La creatura è cambiata.');return editor.readBase();};
    const subcreatures=await listSubcreatures(creatureId);
    const manualCompanions=editor.readBase().parent_creature_id?[]:
      await manualCompanionRules(editor.read(),await computeLocalData(editor.read()));
    openVariantsDialog({read:check,notify:message,icon:actionGlyph,subcreatures:subcreatures.map(row=>({...row.creature,is_available:companionGrantActive(editor.readBase(),row.creature)})),
      manualCompanions,onCompanionFeature:async id=>{
        const descriptor=manualCompanions.find(row=>row.id===id);
        if(!descriptor)throw Error('Privilegio non disponibile.');
        check();await openManualCompanionDialog(editor.read(),descriptor);
      },
      addSubcreature:editor.readBase().parent_creature_id?null:async source=>{
        check();const loaded=await source.load();
        const saved=await createSubcreature(creatureId,loaded,source);
        await editor.flush();
        state.creatureId=saved.id;state.editor=null;state.sheet="info";state.libraryMode=false;
        await render();message("Scheda mostro collegata a "+editor.read().name+".");
      },
      openSubcreature:async id=>{
        if(!subcreatures.some(row=>row.creature.id===id))throw Error("Sottocreatura non disponibile.");
        await editor.flush();state.creatureId=id;state.editor=null;state.sheet="info";await render();
      },
      save:async changes=>{check();await patch(changes);await render();},
      switchForm:async id=>{check();await applyFormPatch(editor.read(),{current_form_id:id});await render();},
      sources:async()=>variantSources((await listCreatures()).map(r=>r.creature),await (await import('./storage.js')).listRecords('global','homebrew'))});
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
    dialog.innerHTML='<header class="vtt-popup-heading"><h2>'+(wildShape?'Forma selvatica':kind==='base'?'Miniatura di base':'Forma attuale')+'</h2>'+dialogCloseButton('miniature-close','Chiudi','')+'</header>'+
      (wildShape?'<p>Scegli l’aspetto rispettando i limiti del tratto. Un utilizzo verrà consumato alla conferma.</p><label>PF personalizzati della variante (0 per condividere i PF)<input data-form-hp type="number" min="0" max="99999" value="0"></label><p data-form-selection role="status">Nessuna forma selezionata.</p>':'')+
      '<label class="vtt-list-search">Cerca miniatura<input type="search" data-miniature-search autocomplete="off"></label>'+
      '<div class="miniature-results vtt-selection-list" role="list"></div>'+
      '<div class="actions">'+(wildShape?'<button type="button" class="btn primary" data-form-confirm disabled>Trasformati</button>':'')+'<button type="button" class="btn" data-miniature-close>Annulla</button></div>';
    const results=dialog.querySelector('.miniature-results');
    const search=dialog.querySelector('[data-miniature-search]');
    let miniatureLimit=60;
    const paint=()=>{
      const filtered=choices.filter(row=>matchesSearch(search.value,row.name,row.id));
      const {items,shown,total}=pageResults(filtered,miniatureLimit);
      results.innerHTML=(items.length?items.map(row=>
        '<button type="button" class="btn miniature-choice vtt-selectable'+(selectedProfile?.id===row.id?' is-selected':'')+'" aria-pressed="'+(selectedProfile?.id===row.id)+'" data-miniature-id="'+esc(row.id)+'">'+
        '<strong>'+esc(row.name)+'</strong><small>'+esc(row.size_name||'Medium')+' · '+esc(row.id)+'</small></button>').join(''):
        '<p class="hint">Nessuna miniatura trovata.</p>')+resultsFooter('miniature-more',shown,total,60);
    };
    search.addEventListener('input',()=>{miniatureLimit=60;paint();});
    results.addEventListener('click',event=>{
      if(event.target.closest('[data-act="miniature-more"]')){event.stopPropagation();miniatureLimit+=60;paint();}
    });
    dialog.querySelectorAll('[data-miniature-close],[data-act="miniature-close"]').forEach(button=>button.addEventListener('click',event=>{event.stopPropagation();closeDialog(dialog,{remove:true});}));
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
        selectedProfile=selectedProfile?.id===profile.id?null:profile;
        dialog.querySelector('[data-form-selection]').textContent=selectedProfile?.name||'Nessuna forma selezionata.';
        dialog.querySelector('[data-form-confirm]').disabled=!selectedProfile;
        for(const button of results.querySelectorAll('[data-miniature-id]')){
          const active=button.dataset.miniatureId===selectedProfile?.id;
          button.setAttribute('aria-pressed',String(active));button.classList.toggle('is-selected',active);
        }
        return;
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
    openDialog(dialog);
    search.focus();
    return;
  }
  if(act==='casting-stats-toggle'){
    if(state.sheet!=='magic'||!state.editor)return;
    const section=target.dataset.castingVisibilitySection;
    if(!section||!target.closest('.magic-source,.play-magic-class-card'))return;
    const creature=state.editor.read();
    const visible=castingStatisticsVisible(creature,section,target.dataset.castingDefaultVisible==='true');
    await patch({spellcasting_section_visibility:{
      ...creature.spellcasting_section_visibility,[section]:!visible
    }});
    await render();return;
  }
  if(act==='concentration-open'){
    if(state.sheet!=='magic')return;
    state.magicPopup='concentration';await render();return;
  }
  if(act==='concentration-set'){
    if(state.sheet!=='magic')return;
    const creature=state.editor.read();
    const id=String(app.querySelector('#concentration-spell')?.value||'');
    const conditions=new Set(creature.conditions||[]);conditions.add('concentrating');
    await patch({conditions:[...conditions],concentrating_spell_id:id});
    state.magicPopup='';await render();return;
  }
  if(act==='slot-menu'){
    if(state.sheet!=='magic')return;
    const level=Number(target.dataset.level),pact=target.dataset.pact==='true';
    if(!Number.isInteger(level)||level<1||level>9)return;
    state.magicSlotLevel=level;state.magicSlotPact=pact;
    state.magicPopup='slot-menu';await render();return;
  }
  if(act==='magic-learn-select'){
    state.sheetPopup='';
    if(state.sheet!=='magic')return;
    state.spellClass=target.dataset.magicClass||'manual';
    state.spellTarget='prepared_spells';
    state.magicPopup='learn';state.spellLearnFilter='all';
    state.spellQuery='';state.spellResultLimit=60;
    requireFullSpellsForPicker();await render();return;
  }
  if(act==='magic-learn-open'){
    state.magicPopup='learn';
    state.spellTarget='prepared_spells';
    state.spellQuery='';state.spellResultLimit=60;
    state.spellLearnFilter='all';requireFullSpellsForPicker();
    await render();return;
  }
  if(act==='magic-tool-open'||act==='magic-select-spells'){
    state.sheetPopup='';
    if(state.sheet!=='magic')return;
    const type=act==='magic-select-spells'?'catalog':target.dataset.magicTool;
    if(!['concentration','slots','catalog','choices'].includes(type))return;
    if(act==='magic-select-spells'||type==='catalog'){
      const classes=state.calculated?.casting_classes||[];
      state.spellClass=act==='magic-select-spells'?target.dataset.magicClass||classes[0]?.id||'manual':
        classes.some(row=>row.id===state.spellClass)?state.spellClass:classes[0]?.id||'manual';
      state.spellTarget='prepared_spells';
      state.spellLearnFilter='all';
      state.spellQuery='';state.spellResultLimit=60;
      state.spellKnownView=classes.find(row=>row.id===state.spellClass)?.mode==='Preparati'?'known':'all';
    }
    state.magicPopup=type;await render();return;
  }
  if(act==='magic-tool-close'){
    state.magicPopup="";
    const dialog=app.querySelector('#magic-tools-dialog');
    closeDialog(dialog,{remove:true});
    return;
  }
  if(act==='action-variants'){
    if(!actionVariants().length){
      try{await loadGeneralActionSupplements();}
      catch(error){throw Error('Regole varianti non disponibili: '+errorMessage(error));}
    }
    const dialog=document.createElement('dialog');dialog.className='sheet-roll-dialog action-variants-dialog';
    const enabled=readActionVariants();
    dialog.innerHTML='<header class="vtt-popup-heading"><h2>Regole varianti · 2014</h2>'+dialogCloseButton('action-variants-close','Chiudi','')+'</header><label class="vtt-list-search">Cerca una regola<input type="search" data-variant-search></label><div class="variant-list vtt-selection-list">'+actionVariants().map(row=>'<label class="check pending-choice-option vtt-selectable" data-variant-row><input type="checkbox" value="'+esc(row.id)+'" '+(enabled.includes(row.id)?'checked':'')+'><span class="vtt-choice-check" aria-hidden="true">✓</span><span>'+esc(row.name)+' <a target="_blank" rel="noopener" href="'+esc(row.source_url)+'">'+esc(row.source)+', p. '+esc(row.page)+'</a></span></label>').join('')+'</div><div class="actions"><button type="button" class="btn primary" data-save-variants>Applica</button><button type="button" class="btn" data-close-variants>Chiudi</button></div>';
    dialog.querySelector('[data-variant-search]').addEventListener('input',e=>{for(const row of dialog.querySelectorAll('[data-variant-row]'))row.hidden=!matchesSearch(e.target.value,row.textContent);});
    dialog.querySelector('[data-save-variants]').addEventListener('click',async()=>{try{const selected=[...dialog.querySelectorAll('input[type=checkbox]:checked')].map(el=>el.value);await patch({action_variants_2014:selected});dialog.remove();await render();}catch{message('Impossibile salvare le varianti sul dispositivo');}});
    dialog.querySelector('[data-close-variants]').addEventListener('click',()=>closeDialog(dialog,{remove:true}));
    dialog.querySelector('[data-act="action-variants-close"]').addEventListener('click',event=>{event.stopPropagation();closeDialog(dialog,{remove:true});});
    dialog.addEventListener('close',()=>dialog.remove(),{once:true});document.body.append(dialog);openDialog(dialog);return;
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
    const clickedSlot=state.magicPopup==='slot-menu'?
      (state.magicSlotPact?'pact:':'slot:')+state.magicSlotLevel:'';
    if(state.magicPopup==='slot-menu'){
      state.magicPopup='';
      const previous=app.querySelector('#magic-tools-dialog');
      if(previous)closeSessionDialog(previous);
    }
    const calculated=await computeLocalData(record);
    const key=act==='power-spell'?target.dataset.spellKey:'';
    const index=Number(target.dataset.spellIndex);
    const grantId=String(target.dataset.grantId||'');
    const classId=String(target.dataset.castingClass||'');
    const saved=key==='prepared_spells'?availableSpells(record)[index]:null;
    const grant=key==='origin'?calculated.origin_spells?.find(row=>row.id===grantId):null;
    const id=key==='origin'?grant?.spell_id:key?spellId(saved):target.dataset.spellId;
    if(!id)throw Error('Incantesimo non disponibile.');
    const entries=sessionSpellEntries(record,calculated,state.spellCatalog||[]);
    const entry=entries.find(row=>row.id===id&&String(row.grant_id||'')===grantId&&
      (key==='origin'||String(row.casting_class||'')===(classId==='manual'?'':classId)))||
      null;
    const catalogSpell=(state.spellCatalog||[]).find(row=>row.id===id);
    const stored=typeof saved==='object'&&saved?saved:{};
    const spell=entry||catalogSpell||stored;
    const detailed=await detailedEntry('spells',{...catalogSpell,...spell,_category:'spells'});
    const description=flattenDescription(detailed)||'Descrizione non disponibile nel catalogo locale.';
    const extendedSpell=applyEffectExtensions(detailed,calculated.effect_extensions,
      {kind:'spell',id,name:spell.name||detailed.name},
      {cha_mod:calculated.abilities?.cha?.modifier});
    const spellExtensions=extendedSpell.effect_extensions||[];
    // Object-targeted spells and infusions reuse typed eligibility, never prose
    // guessing. Catalogue/homebrew spells can declare item_target_selector.
    const targetSelector=detailed.item_target_selector||spell.item_target_selector||
      detailed.target_item_selector||spell.target_item_selector||null;
    const targetItems=targetSelector?targetableInventoryItems(record,targetSelector):[];
    const level=magicSpellInfo({...spell,id}).level;
    const options=[];
    if(entry&&level!==null){
      const assigned=calculated.origin_spells?.find(row=>row.id===entry.grant_id);
      const mode=assigned?.payment_mode||(assigned?.tracker_id?'tracker':level===0?'free':(['known','prepared'].includes(assigned?.mode)||!assigned)?'slot':'free');
      if(mode==='free'||level===0&&mode!=='tracker'){
        options.push(['auto:0',assigned?.ritual_only?'Rituale · senza slot':'Senza slot']);
      }else{
        if(mode==='tracker'){
          const pool=calculated.trackers.find(t=>t.id===assigned?.tracker_id&&!t.disabled);
          const cost=Math.max(1,Number(assigned?.tracker_cost)||1);
          if(pool&&pool.max-pool.spent>=cost)
            options.push(['auto:0','Usa il tracker previsto']);
        }
        if(mode==='slot'||assigned?.slot_alternative===true){
          for(const slot of calculated.spell_slots||[]){
            if(Number(slot.level)>=level&&Number(slot.total)-Number(slot.spent)>0)
              options.push(['slot:'+slot.level,'Slot '+slot.level+'° · '+(slot.total-slot.spent)+' disponibili']);
          }
          if(calculated.pact_slots?.level>=level&&calculated.pact_slots?.total>calculated.pact_slots?.spent)
            options.push(['pact:'+calculated.pact_slots.level,'Patto · '+calculated.pact_slots.level+'° livello']);
        }
      }
    }
    app.querySelector('#action-cast-dialog')?.remove();
    const dialog=document.createElement('dialog');dialog.className='sheet-roll-dialog magic-spell-dialog';dialog.id='action-cast-dialog';
    const companion=await companionSpellChoices({...spell,id},record).catch(error=>{
      message("Famigli: "+errorMessage(error),true);return null;
    });
    const metaChoices=metamagicOptions(record).filter(o=>!['Empowered Spell','Seeking Spell'].includes(o.name));
    dialog.innerHTML=actionDialogIntro(spell.name||id,spellFacts({...detailed,range:extendedSpell.range||detailed.range}),description,
      (level===0?(spell.internal_grant?'Capacità':'Trucchetto'):level===null?'Livello non specificato':'Livello '+level)+
      (detailed.school?' · '+detailed.school:'')+(detailed.source?' · '+detailed.source:''),'action-cast-cancel')+
      (detailed._description_warning?'<p class="hint">'+esc(detailed._description_warning)+'</p>':'')+
      (entry?.requires_context?'<label><input type="checkbox" id="action-cast-context"> '+esc(entry.requires_context)+'</label>':'')+
      (entry?.ritual_only?'<label><input type="checkbox" id="action-cast-ritual"> Ho completato il rituale, aggiungendo 10 minuti al normale tempo di lancio.</label>':'')+
      (spellExtensions.length?'<section class="magic-effect-extensions"><h3>Estensioni attive</h3><ul>'+
        spellExtensions.map(extension=>'<li><strong>'+esc(extension.origin_name||'Privilegio')+'</strong> · '+
          esc(effectExtensionLabel(extension,{cha_mod:calculated.abilities?.cha?.modifier}))+'</li>').join('')+
        '</ul></section>':'')+
      (entry&&options.length?
        '<label>Livello di lancio / risorsa<select id="action-cast-choice">'+options.map(([value,label])=>'<option value="'+esc(value)+'"'+(value===clickedSlot?' selected':'')+'>'+esc(label)+'</option>').join('')+'</select></label>':
        '<p class="hint">'+(entry?'Nessuna risorsa di lancio disponibile.':'Incantesimo non preparato: puoi consultarlo tra quelli imparati, ma non lanciarlo.')+'</p>')+
      (entry&&targetSelector?
        (targetItems.length?'<label>Oggetto bersaglio<select id="action-cast-item-target">'+
          targetItems.map(({item,index})=>'<option value="'+index+'">'+esc(item.name||item.id)+'</option>').join('')+'</select></label>':
         '<p class="warning">Nessun oggetto compatibile in inventario per questo incantesimo.</p>'):'')+
      (entry&&metaChoices.length?'<details class="metamagic-options"><summary>Metamagia</summary><label>Opzione<select data-metamagic-name><option value="">Nessuna</option>'+metaChoices.map(o=>'<option value="'+esc(o.name)+'">'+esc(o.name)+' · '+o.cost+' punti</option>').join('')+'</select></label><label class="check"><input data-metamagic-targets type="checkbox">Raddoppiato: confermo i requisiti di bersaglio del tratto per questa edizione</label><label class="check"><input data-metamagic-damage type="checkbox">Trasmutato: confermo che il danno originale sia elementale</label><label>Nuovo danno<select data-metamagic-element>'+['acid','cold','fire','lightning','poison','thunder'].map(e=>'<option>'+e+'</option>').join('')+'</select></label></details>':'')+
      (companion?'<label>Creatura evocata dal bestiario<select id="action-cast-companion">'+
        (companion.choices.length?companion.choices.map(source=>
          '<option value="'+esc(source.key)+'">'+esc(source.name)+(source.source?' · '+esc(source.source):'')+'</option>').join(''):
          '<option value="">Nessuna voce disponibile nel bestiario</option>')+
        '</select></label>':'')+
      '<div class="actions magic-dialog-actions">'+
      (entry&&options.length&&(!targetSelector||targetItems.length)?'<button type="button" class="btn primary" data-act="action-cast-confirm" data-spell-id="'+esc(entry.id)+'" data-grant-id="'+esc(entry.grant_id||'')+'" data-casting-class="'+esc(entry.casting_class||'')+'">'+(entry.ritual_only?'Concludi rituale':'Lancia')+'</button>':'')+
      '<button type="button" class="btn" data-act="action-cast-cancel">Chiudi</button></div>';
    app.appendChild(dialog);dialog.addEventListener('close',()=>dialog.remove(),{once:true});
    openDialog(dialog);
    return;
  }
  if(act==='action-cast-cancel'){
    const dialog=app.querySelector('#action-cast-dialog');
    closeDialog(dialog,{remove:true});
    return;
  }
  if(act==='action-cast-confirm'){
    const record=state.editor?.read();if(!record)throw Error('Scheda non disponibile.');
    const calculated=await computeLocalData(record);
    const selection=sessionSpellEntries(record,calculated,state.spellCatalog||[])
      .find(row=>row.id===target.dataset.spellId&&String(row.grant_id||'')===String(target.dataset.grantId||'')&&
         String(row.casting_class||'')===String(target.dataset.castingClass||''));
    if(!selection)throw Error('Incantesimo non più disponibile.');
    selection.context_confirmed=app.querySelector('#action-cast-context')?.checked===true;
    selection.ritual_completed=app.querySelector('#action-cast-ritual')?.checked===true;
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
    const companion=await companionSpellChoices({...detail,...selection},record);
    const companionKey=app.querySelector('#action-cast-companion')?.value||'';
    let companionSource=null;
    if(companion){
      companionSource=companion.choices.find(source=>source.key===companionKey);
      if(!companionSource)throw Error('Scegli una creatura valida dalla lista dell’incantesimo.');
    }
    const choice=app.querySelector('#action-cast-choice')?.value||'';
    const [payment,levelText]=choice.split(':');const level=Number(levelText);
    if(!['auto','slot','pact'].includes(payment)||!Number.isInteger(level)||level<0||level>9)
      throw Error('Risorsa di lancio non valida.');
    if(desktopHooks?.cast||(state.paired&&state.online)){
      app.querySelector('#action-cast-dialog')?.close();
      await startTargetedCast(record.id,structuredClone(selection),level,payment,'',
        companionSource?{...companionSource,spell_id:selection.id,rule:companion.rule,
          grant:companion.rule.grant_kind==='spell_effect'?{kind:'spell_effect',id:'spell:'+selection.id}:null,
          rule_id:companion.rule.id,origin_name:companion.rule.names?.[0]||selection.name,
          limit_per_owner_rule:companion.rule.limit_per_owner_spell??1}:null);return;
    }
    const plan=spellCastPlan(record,selection,level,calculated,payment);
    app.querySelector('#action-cast-dialog')?.close();
    const effect=companion?companionSpellEffectPatch(record,companion.rule,selection.id):{};
    if(Object.keys({...plan.patch,...effect}).length)await patch({...plan.patch,...effect});
    if(companionSource)await summonSpellCompanion(record.id,companionSource,{
      ...companionSource,spell_id:selection.id,rule_id:companion.rule.id,
      origin_name:companion.rule.names?.[0]||selection.name,
      grant:companion.rule.grant_kind==='spell_effect'?{kind:'spell_effect',id:'spell:'+selection.id}:null,
      limit_per_owner_rule:companion.rule.limit_per_owner_spell??1});
    await render();
    message('Lancio registrato nella scheda locale. Gli effetti sulla mappa richiedono una partita collegata.');
    return;
  }
  if(act==='spell-storing-use'){
    const current=state.editor?.read();
    if(!current)throw Error('Apri prima la scheda.');
    const calculated=await computeLocalData(current),index=Number(target.dataset.index);
    const imprint=spellImprintAtItem(current,index);
    const change=imprint?useSpellImprintPatch(current,calculated,index):
      useStoredSpellPatch(current,calculated,index);
    const extension=imprint||storedSpellExtension(current);
    await patch(change);await render();
    message((imprint?'Incantesimo dalla carta':'Spell-Storing Item')+' · '+
      (extension?.spell_name||'incantesimo')+
      ': lancio registrato come '+(imprint?'azione bonus':'azione')+
      ', senza usare slot. Risolvi gli effetti e l’eventuale concentrazione.');
    return;
  }
  if(act==='battle-attack-map'){
    const creature=state.editor?.read();
    if(!creature)throw Error('Apri prima una creatura.');
    if(!state.paired||!state.online)throw Error('Collega la partita al desktop per vedere la gittata sulla mappa.');
    const attackId=String(target.dataset.mapAttackId||'');
    const calculated=await computeLocalData(creature);
    // Generic attack actions reference the computed unarmed strike. A
    // 5-foot fallback is only needed for older or incomplete projections.
    const attack=(calculated.attacks||[]).find(row=>String(row.id)===attackId)||
      (attackId==='unarmed'?{id:'unarmed',name:'Colpo senz’armi',melee:true,range_feet:5}:null);
    if(!attack)throw Error('Attacco non più disponibile. Aggiorna la scheda.');
    const range=row=>({
      range_feet:Number(row.range_feet)||5,
      long_range_feet:Number(row.long_range_feet)||0,
      melee:Boolean(row.melee)
    });
    const liveMap=await map();
    const token=casterToken(creature,liveMap,await ownerId());
    if(!token)throw Error('Piazza o associa la creatura a un token prima di visualizzare la gittata.');
    if(!tacticalViewer)tacticalViewer=new TacticalViewer({send:action,ownerId,notify:message});
    await tacticalViewer.open(String(token.id),range(attack));
    // No confirmation for plain attacks: only supported, explicitly modeled
    // effects on the target may be applied, independently of dice rolls.
    if(onHitEffects(attack).length)tacticalViewer.setAttackEffects({
      name:attack.name,
      onConfirmed:async selected=>{
        const current=state.editor?.read();
        if(!current||current.id!==creature.id)throw Error('La creatura attaccante è cambiata.');
        const updated=await computeLocalData(current);
        const latestAttack=(updated.attacks||[]).find(row=>String(row.id)===attackId);
        if(!latestAttack||!onHitEffects(latestAttack).length)
          throw Error('Gli effetti di questo attacco non sono più disponibili.');
        const latestMap=await map();
        state.map=latestMap;
        if(!(latestMap.tokens||[]).some(row=>String(row.id)===String(selected.id)))
          throw Error('Il bersaglio non è più sulla mappa.');
        // Check range a second time in case a token moved while the popup was open.
        await action('target_attack',{
          token_id:String(token.id),target_id:String(selected.id),attack:range(latestAttack)
        }).then(result=>{if(!result?.ok)throw Error(result?.error||'Bersaglio fuori gittata.');});
        const result=await action('hit_attack',{
          token_id:String(token.id),owner_id:await ownerId(),target_id:String(selected.id),
          attack_id:latestAttack.id,attack_name:latestAttack.name,
          effects:onHitEffects(latestAttack)
        });
        if(!result?.ok)throw Error(result?.error||'Impossibile applicare gli effetti.');
        state.map=await map();
        message(latestAttack.name+': '+selected.name+' · '+result.effects_applied+' effetti applicati.');
      }
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
    const min=scoreTarget==='second_max'||scoreTarget==='attunement_max'?0:1,max=scoreTarget==='attunement_max'?99:ability?30:99999;
    if(!raw||!Number.isInteger(value)||value<min||value>max)
      throw Error('Inserisci un valore intero tra '+min+' e '+max);
    const creature=state.editor?.read();if(!creature)throw Error('Apri prima una creatura');
    const change=ability?{abilities:{...creature.abilities,[ability]:value}}:
      scoreTarget==='hp'?{max_hp_base:value}:scoreTarget==='attunement_max'?{attunement_max_base:value}:{second_form_max_hp:value};
    if(scoreTarget==='attunement_max'){
      const next=await computeLocalData({...creature,...change});
      const occupied=(creature.inventory||[]).reduce((sum,item)=>sum+itemAttunementCount(item),0);
      if(occupied>next.attunements.maximum)
        throw Error('Libera le sintonie in eccesso prima di ridurre il massimo.');
    }
    const returnTitle=String(dialog.dataset.returnFormulaTitle||'');
    const modifierChange=ability==='con'?await constitutionModifierChange(creature,value):null;
    await patch(change);
    dialog.close?.();dialog.remove();
    await render();
    if(modifierChange){
      openConstitutionHpDialog(creature.id,modifierChange.previous,modifierChange.next,{returnTitle});
      return;
    }
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
    const bonuses=rollOptionalDice(creature,calculated,[
      ...applicableDiceBonuses(creature,attackId?'attack_damage:'+attackId:'spell_damage',state.spellCatalog||[],calculated),
      ...classFeatureRollBonuses(creature,calculated,'attack_damage:'+attackId),
       ...applicableFeatRollBonuses(creature,calculated,'attack_damage:'+attackId)
     ],{kind:'damage',attackId});
    const dialog=openUnifiedRollDialog({kind:'damage',heading:label,modifier:preview.modifier,
      rollType:'Tiro per danni',formula:sheetRollOriginHtml(preview.segments,esc),
      bonuses,creatureId:creature.id||'',damageFormula:formula,damageLabel:label,damageType:type});
    dialog.dataset.damageAttackId=attackId;
    dialog.rollAttack=sourceAttack;
    dialog.renderRollFormula=()=>{dialog.querySelector('[data-roll-formula]').innerHTML=sheetRollOriginHtml(
        [...damageRollTerms(formula,type,dialog.rollAttack).segments,...[...chosenRollBonuses(dialog),...(dialog.postRollBonuses||[])].map(rollBonusTerm)],esc);};
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
  if(act==='sheet-sense-choice'){
   if(!state.editor)throw Error('Apri prima una creatura');
   const record=state.editor.read();
   if(record.species!=='Custom Lineage'||record.species_source!=='TCE')throw Error('Scelta non disponibile');
   const choice=String(target.dataset.senseChoice||'');
   if(!['darkvision','skill'].includes(choice))throw Error('Scelta non valida');
   await patch({origin_sense_choices:{...(record.origin_sense_choices||{}),['race|tce|custom lineage']:choice}});
   await render();
   openSheetSensesDialog(await computeLocalData(state.editor.read()));return;
  }
  if(act==='sheet-senses-open'){
   if(!state.editor)throw Error('Apri prima una creatura');
   openSheetSensesDialog(await computeLocalData(state.editor.read()));return;
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
    const kind='bonus';
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
    // Cost-free conditional modes may be unchecked before the d20 is rolled.
    // A paid resource remains consumed when explicitly activated.
    if(row?.roll_mode&&!row.tracker_id&&target.dataset.rollUsed==='true'&&!dialog.rollOutcome){
      dialog.usedRollBonuses=chosenRollBonuses(dialog).filter(item=>item.selectionId!==row.selectionId);
      target.dataset.rollUsed='false';target.textContent='Usa';
      dialog.renderRollFormula?.();
      return;
    }
    if(!row||target.dataset.rollUsed==='true'||dialog.appliedBonusIds.has(row.selectionId)||
      chosenRollBonuses(dialog).some(b=>b.selectionId===row.selectionId)||
      row.exclusive_group&&chosenRollBonuses(dialog).some(b=>b.exclusive_group===row.exclusive_group))return;
    // A situational d20 mode and power-attack penalty must be chosen
    // before the first d20 result, never in reaction to seeing a hit.
    if((row.roll_mode||row.require_before_roll)&&dialog.rollOutcome)
      throw Error('Questo beneficio va scelto prima di tirare il d20.');
    const creature=state.editor?.read();
    if(!creature||creature.id!==dialog.dataset.creatureId)throw Error('La creatura del tiro è cambiata');
    if(String(row.id||'').startsWith('racial:')){
      const current=await computeLocalData(creature);
      if(!(current.racial_roll_bonuses||[]).some(b=>b.id===row.id&&b.origin_id===row.origin_id))
        throw Error('Il privilegio razziale non è più disponibile.');
    }
    if(row.passive_class_bonus){
      // A passive conditional benefit is applied directly, without invoking
      // an ability action. Verify that its owner/level and formula still apply.
      const fresh=await computeLocalData(creature);
      const valid=classFeatureRollBonuses(creature,fresh,dialog.dataset.rollTarget).find(item=>
        item.id===row.id&&item.origin_id===row.origin_id&&item.passive_class_bonus);
      if(!valid)throw Error('Il beneficio non è più disponibile per questo tiro.');
      row.flat_bonus=valid.flat_bonus;
    }
    if(row.class_feature_id){
      // Uses the same feature confirmation and payment plan as Battle.
      const fresh=await computeLocalData(creature),rollTarget=dialog.dataset.rollKind==='damage'?
        'attack_damage:'+String(dialog.dataset.damageAttackId||''):dialog.dataset.rollTarget;
      const valid=classFeatureRollBonuses(creature,fresh,rollTarget).find(item=>
        item.id===row.id&&item.origin_id===row.origin_id);
      const action=classFeatureEntries(creature,fresh).find(item=>
        item.class_feature_id===row.class_feature_id);
      if(!valid||!action)throw Error('Privilegio non più disponibile per questo tiro.');
      target.disabled=true;
      await activateClassAbility(creature,fresh,action,{
        onClosed:()=>{if(target.isConnected&&target.dataset.rollUsed!=='true')target.disabled=false;},
        onConfirmed:()=>{
          if(!dialog.isConnected||dialog.dataset.rolling==='true')return;
          const selected={...row,...(Object.hasOwn(valid,'flat_bonus')?{flat_bonus:valid.flat_bonus}:{dice:valid.dice})};
          const revised=applyPostRollBonus(dialog,selected);
          if(!revised)dialog.usedRollBonuses.push(selected);
          target.textContent='Usato';target.dataset.rollUsed='true';target.disabled=true;
          dialog.renderRollFormula?.();
          if(revised)void announcePostRollBonus(revised);
        }
      });
      return;
    }
    if(row.tracker_id){
      const fresh=await computeLocalData(creature);
      const tracker=(fresh.trackers||[]).find(t=>t.id===row.tracker_id&&!t.disabled);
      if(!tracker)throw Error('Tracker non disponibile');
      const remaining=Number(tracker.max||0)-Number(tracker.spent||0);
      const cost=Math.max(1,Number(row.tracker_cost)||1);
      if(remaining<cost){
        if(row.strict_tracker)throw Error('Utilizzi esauriti: '+(tracker.name||'risorsa'));
        message('Attenzione: '+(tracker.name||'risorsa')+' esaurito; il bonus viene usato comunque.',true);
      }
      if(row.strict_tracker)await patch(current=>spendTrackerUses(current,row.tracker_id,cost,fresh.trackers));
      else{
        const used={...(creature.resource_tracker_spent||{})};
        used[row.tracker_id]=(Number(used[row.tracker_id])||0)+cost;
        await patch({resource_tracker_spent:used});
      }
      const trackerButton=dialog.querySelector('[data-roll-tracker-button="'+index+'"]');
      if(trackerButton){
        const summary=(tracker.name||'Tracker')+' · '+Math.max(0,remaining-Math.max(1,Number(row.tracker_cost)||1))+' rim.';
        trackerButton.title=summary;trackerButton.setAttribute('aria-label','Apri tracker '+summary);
      }
    }
    if(row.roll_mode){
      const freshRecord=state.editor.read(),current=await computeLocalData(freshRecord);
      const modeTarget=String(dialog.dataset.rollTarget||'');
      const racialAvailable=(current.racial_roll_modes||[]).some(rule=>rule.benefit_id===row.benefit_id);
      const featAvailable=applicableFeatRollBonuses(freshRecord,current,modeTarget)
        .some(rule=>rule.roll_mode===row.roll_mode&&rule.benefit_id===row.benefit_id);
      const classAvailable=classFeatureRollBonuses(freshRecord,current,modeTarget)
        .some(rule=>rule.roll_mode===row.roll_mode&&rule.id===row.id&&
          rule.origin_id===row.origin_id);
      if(!racialAvailable&&!featAvailable&&!classAvailable)
        throw Error('Il beneficio condizionale non è più disponibile.');
      dialog.usedRollBonuses.push(row);
      target.textContent=row.tracker_id?'Attivo':'Rimuovi';
      target.dataset.rollUsed='true';target.disabled=!!row.tracker_id;
      dialog.renderRollFormula?.();
      return;
    }
    const revised=applyPostRollBonus(dialog,row);
    if(!revised)dialog.usedRollBonuses.push(row);
    if(row.exclusive_group)for(const button of dialog.querySelectorAll('[data-roll-use]')){
      const other=dialog.rollBonuses[Number(button.dataset.rollUse)];
      if(other?.exclusive_group===row.exclusive_group&&other.selectionId!==row.selectionId)button.disabled=true;
    }
    target.textContent='Usato';target.dataset.rollUsed='true';target.disabled=true;
    dialog.renderRollFormula?.();
    if(revised)await announcePostRollBonus(revised);
    return;
  }
  if(act==='roll-origin-open'){
    const dialog=document.querySelector('#sheet-roll-dialog')||
      document.querySelector('#sheet-score-formula-dialog');
    const originId=String(target.dataset.originId||''),section=String(target.dataset.originSection||'');
    const traitName=String(target.dataset.originTrait||''),originKey=String(target.dataset.originKey||'');
    const fallbackTarget=dialog?.dataset.scoreTarget||dialog?.dataset.rollTarget||'';
    dialog?.close?.();dialog?.remove();
    if(originId||traitName){await openRollTraitOrigin(originId,{traitName,originKey});return;}
    if(section==='conditions'){state.sheet='conditions';await render();return;}
    // Never translate a provenance click into a blank add-bonus form.
    if(section==='proficiency_choices'){
      state.sheet='info';await render();
      state.sheetPopup='tools';state.sheetPopupTitle='Competenze';await render();return;
    }
    await openRollTraitPicker('bonus',fallbackTarget);return;
  }
  if(act==='concentration-close'){
    closeDialog(document.querySelector('#concentration-damage-dialog'),{remove:true});return;
  }
  if(act==='concentration-end'){
    const dialog=document.querySelector('#concentration-damage-dialog');
    const creature=state.editor?.read();
    if(!creature||creature.id!==dialog?.dataset.creatureId)throw Error('La creatura è cambiata.');
    await patch(concentrationEndPatch(creature));
    closeDialog(dialog,{remove:true});await render();return;
  }
  if(act==='sheet-roll'||act==='concentration-save-roll'){
    const concentration=act==='concentration-save-roll';
    const rollContext=concentration?CONCENTRATION_ROLL_CONTEXT:'';
    if(concentration)closeDialog(document.querySelector('#concentration-damage-dialog'),{remove:true});
    const creature=state.editor?.read();if(!creature)throw Error('Apri prima una creatura');
    const key=concentration?'save:con':String(target.dataset.target||'');
    // Conditional on-hit marks expire on the source's next combat turn.
    // Refresh the live initiative snapshot when opening a marked creature's roll.
    if((key.startsWith('attack_hit:')||key.startsWith('casting_hit:'))&&state.paired&&state.online)
      try{state.map=await map();}catch(error){console.warn('Snapshot del combattimento non aggiornato',error);}
    const calculated=await computeLocalData(creature),modifier=calculated.values[key];
    if(!Number.isFinite(modifier))throw Error('Valore del tiro non disponibile');
    const label=concentration?'TS Costituzione · concentrazione':target.dataset.label||'Tiro';
    // The 2024 Exhaustion penalty is mandatory: it modifies the actual d20
    // result and formula, never a selectable/spendable bonus or ability score.
    const exhaustionPenalty=exhaustionRollModifier(calculated.exhaustion_effects,key);
    const effectiveModifier=modifier+exhaustionPenalty;
    const exhaustionLevel=Number(creature.exhaustion??creature.exhaustion_level??0);
    const formulaData=exhaustionPenalty?{...calculated,
      values:{...calculated.values,[key]:effectiveModifier},
      roll_components:{...calculated.roll_components,
       [key]:[...(calculated.roll_components?.[key]||[]),{
        id:'exhaustion:roll:'+exhaustionLevel,
        origin_id:'state|condition:exhaustion:'+exhaustionLevel,
        origin_name:'Indebolimento · Livello '+exhaustionLevel,
        expression:String(exhaustionPenalty),value:exhaustionPenalty
       }]}}:calculated;
    const bonuses=rollOptionalDice(creature,calculated,[
       ...applicableDiceBonuses(creature,key,state.spellCatalog||[],calculated),
       ...classFeatureRollBonuses(creature,calculated,key),
       ...applicableSpeciesRollModes(creature,calculated,key),
       ...applicableFeatRollBonuses(creature,calculated,key)
      ],{kind:'d20'});
     let autoSources=classFeatureRollSources(creature,calculated,key,rollContext);
    const automatic=resolveClassRollMode(autoSources);
    const formulaMarkup=(chosen=[],choice='auto')=>{
      const selectedModes=chosen.filter(row=>row.roll_mode).map(row=>({
        mode:row.roll_mode,origin_id:row.origin_id,
        origin_name:row.origin_name,kind:'feature',condition_label:row.condition_label
      }));
      const resolved=resolveClassRollMode([...autoSources,...selectedModes],choice);
      return sheetRollOriginHtml(sheetRollOriginSegments(creature,formulaData,key,
        {mode:resolved.mode,modeSources:resolved.sources,cancelled:resolved.cancelled,
          diceBonuses:chosen.filter(row=>!row.roll_mode)}),esc);
    };
    const autoLabel=automatic.cancelled?' · vantaggio e svantaggio annullati':
      automatic.mode==='advantage'?' · vantaggio':
      automatic.mode==='disadvantage'?' · svantaggio':'';
    const dialog=openUnifiedRollDialog({kind:'d20',heading:rollHeading(label,key),rollLabel:label,modifier:effectiveModifier,
      rollType:rollCategory(key,calculated),formula:formulaMarkup(),bonuses,autoLabel,
      creatureId:creature.id||'',target:key});
    dialog.dataset.rollContext=rollContext;
    // A map-applied on-hit debuff must know the target of the affected attack.
    // Without an explicit target the source's target-specific penalty is not assumed.
    if((key.startsWith('attack_hit:')||key.startsWith('casting_hit:'))&&
       (creature.applied_hit_effects?.length||targetTokenHitEffects(creature,state.map).length)){
      const selection=document.createElement('label');
      selection.className='sheet-roll-mode-control';
      selection.textContent='Bersaglio dell’attacco';
      const choose=document.createElement('select');
      choose.dataset.rollTargetToken='true';
      const tokens=(state.map?.tokens||[]).filter(token=>token?.id);
      const candidates=[['','Nessuno specificato'],
        ...tokens.map(token=>[String(token.id),String(token.name||token.id)]),
        ['other','Altra creatura (diversa dalla fonte)']];
      choose.innerHTML=candidates.map(([id,name])=>
        '<option value="'+esc(id)+'">'+esc(name)+'</option>').join('');
      selection.append(choose);
      dialog.querySelector('.sheet-roll-formula')?.before(selection);
      choose.addEventListener('change',()=>{
        dialog.dataset.rollContext=choose.value?'attack_target:'+choose.value:'';
        autoSources=classFeatureRollSources(creature,calculated,key,dialog.dataset.rollContext);
        dialog.renderRollFormula?.();
      });
    }
    dialog.renderRollFormula=()=>{
      const formula=dialog.querySelector('[data-roll-formula]');
      const choice=dialog.querySelector('[data-roll-mode]').value;
      if(formula)formula.innerHTML=formulaMarkup([...chosenRollBonuses(dialog),...(dialog.postRollBonuses||[])],choice);
    };
    dialog.addEventListener('change',event=>{
      if(event.target.matches('[data-roll-mode]')){
        dialog.renderRollFormula();
      }
    });
    return;
  }
  if(act==='sheet-roll-choose-d20'){
    const dialog=document.querySelector('#sheet-roll-dialog');
    if(!dialog||!dialog.rollOutcome?.d20_reroll||dialog.dataset.rolling==='true')return;
    const next=chooseD20Reroll(dialog.rollOutcome,String(target.dataset.d20Choice||'previous'));
    recordRevisedRoll(dialog,next);
    refreshD20RerollChoices(dialog,state.editor.read(),await computeLocalData(state.editor.read()));
    await announcePostRollBonus(next);
    return;
  }
  if(act==='sheet-roll-reroll-d20'){
    const dialog=document.querySelector('#sheet-roll-dialog');
    if(!dialog||dialog.dataset.rollKind!=='d20'||!dialog.rollOutcome||dialog.dataset.rolling==='true')return;
    const creature=state.editor?.read();
    if(!creature||creature.id!==dialog.dataset.creatureId)throw Error('La creatura del tiro è cambiata.');
    const index=Number(target.dataset.d20Reroll);
    const listed=dialog.d20RerollSources?.[index];
    const calculated=await computeLocalData(creature);
    const source=availableD20Rerolls(creature,calculated,dialog.dataset.rollTarget,dialog.rollOutcome)
      .find(row=>row.id===listed?.id);
    if(!source||dialog.usedRerollIds.has(String(source.id)))throw Error('Ritiro non più disponibile.');
    // Pay before rolling; choosing to retain the old die does not refund a use.
    dialog.dataset.rolling='true';target.disabled=true;
    try{
      if(source.payment_mode==='inspiration')await patch({inspiration:false});
      else if(source.tracker_id)await patch(spendTrackerUses(creature,source.tracker_id,
        Math.max(1,Number(source.tracker_cost)||1),calculated.trackers));
      const next=chooseD20Reroll(offerD20Reroll(dialog.rollOutcome,randomDie,source),'previous');
      dialog.usedRerollIds.add(String(source.id));
      recordRevisedRoll(dialog,next);
      refreshD20RerollChoices(dialog,state.editor.read(),await computeLocalData(state.editor.read()));
      await announcePostRollBonus(next);
    }finally{delete dialog.dataset.rolling;}
    return;
  }
  if(act==='roll-sheet-confirm'){
    const dialog=document.querySelector('#sheet-roll-dialog');
    if(!dialog||dialog.dataset.rolling==='true'||
      dialog.dataset.rollKind==='feature'&&dialog.rollOutcome)return;
    const creature=state.editor?.read();
    if(!creature||creature.id!==dialog.dataset.creatureId)throw Error('La creatura del tiro è cambiata');
    const button=dialog.querySelector('[data-act="roll-sheet-confirm"]');
    dialog.dataset.rolling='true';
    if(button)button.disabled=true;
    try{
      const result=dialog.querySelector('[data-roll-result]');
      if(dialog.dataset.rollKind==='damage'||dialog.dataset.rollKind==='feature'){
        const chosen=chosenRollBonuses(dialog);
        const fullFormula=dialog.dataset.damageFormula+chosen.map(row=>
          Object.hasOwn(row,'flat_bonus')?(Number(row.flat_bonus)>=0?'+':'')+row.flat_bonus:'+'+row.dice).join('');
        const outcome=rollBattleDamage(fullFormula,randomDie);
        const featureTarget=dialog.dataset.featureRollTarget||'';
        state.roll={...outcome,label:(featureTarget?'Tiro capacità · ':'Danni · ')+dialog.dataset.damageLabel+
          (dialog.dataset.damageType?' · '+dialog.dataset.damageType:''),author:selectedName(),
          ...(featureTarget?{feature_roll_target:featureTarget,
            feature_origin_id:dialog.dataset.featureRollOriginId||''}:{})};
        state.rollHistory.unshift({...state.roll});
        result.hidden=false;
        result.innerHTML=rollDieResultMarkup(outcome);
        dialog.rollOutcome=state.roll;dialog.rollHistoryEntry=state.rollHistory[0];
        if(!featureTarget){
          const damageEnd=endTemporaryConditionPatch(state.editor.read());
          if(Object.keys(damageEnd).length)await patch(damageEnd);
        }
        // A paid class-feature modifier applies to one damage roll only.
        // Keep the existing optional weapon dice behavior unchanged.
        const oneShot=new Set(chosen.filter(row=>row.class_feature_id).map(row=>row.selectionId));
        if(oneShot.size){
          dialog.usedRollBonuses=dialog.usedRollBonuses.filter(row=>!oneShot.has(row.selectionId));
          for(const useButton of dialog.querySelectorAll('[data-roll-use]')){
            const item=dialog.rollBonuses[Number(useButton.dataset.rollUse)];
            if(oneShot.has(item?.selectionId)){
              useButton.disabled=false;useButton.dataset.rollUsed='false';useButton.textContent='Usa';
            }
          }
        }

      // The just-finished roll owns its chosen charges. Keep the granted
      // terms visible in the formula, but never auto-charge or auto-apply them
      // to a later d20 roll. Available bonuses remain visible below the result.
      dialog.postRollBonuses=[...chosen];
      dialog.appliedBonusIds=new Set(chosen.map(row=>row.selectionId));
      dialog.usedRollBonuses=[];
        // Usage was spent by the explicit Usa action. Rerolling in this dialog
        // must not silently consume the same tracker again.
        dialog.renderRollFormula?.();
      }else{
        const key=dialog.dataset.rollTarget,label=dialog.dataset.rollLabel;
        const calculated=await computeLocalData(creature),modifier=calculated.values[key];
        if(!Number.isFinite(modifier))throw Error('Modificatore non disponibile.');
        const chosen=chosenRollBonuses(dialog),numeric=chosen.filter(row=>!row.roll_mode);
        const choice=dialog.querySelector('[data-roll-mode]')?.value||'auto';
        const confirmed=chosen.filter(row=>row.roll_mode).map(row=>({
          mode:row.roll_mode,origin_id:row.origin_id,origin_name:row.origin_name,
          kind:'feature',condition_label:row.condition_label
        }));
        const automatic=classFeatureRollSources(creature,calculated,key,dialog.dataset.rollContext||'');
        const resolved=resolveClassRollMode([...automatic,...confirmed],choice);
        const penalty=exhaustionRollModifier(calculated.exhaustion_effects,key);
        dialog.usedRerollIds.clear();
        const outcome=rollSheetDice(modifier+penalty,numeric,randomDie,resolved.mode);
        state.roll={...outcome,label,author:selectedName()};
        state.rollHistory.unshift({...state.roll});
        result.hidden=false;
        result.innerHTML=rollDieResultMarkup(outcome);
        dialog.rollOutcome=state.roll;dialog.rollHistoryEntry=state.rollHistory[0];
        if(key.startsWith('attack_hit:')||key.startsWith('casting_hit:')){
          const attackEnd=endTemporaryConditionPatch(state.editor.read());
          if(Object.keys(attackEnd).length)await patch(attackEnd);
        }
        // Tracker uses were spent at selection time, never again on rerolls.
        // A reaction modifies one roll only, even when the same dialog rerolls.
         const oneShot=new Set(chosen.filter(row=>row.class_feature_id).map(row=>row.selectionId));
         if(oneShot.size){
           dialog.usedRollBonuses=dialog.usedRollBonuses.filter(row=>!oneShot.has(row.selectionId));
           for(const useButton of dialog.querySelectorAll('[data-roll-use]')){
             const item=dialog.rollBonuses[Number(useButton.dataset.rollUse)];
             if(oneShot.has(item?.selectionId)){
               useButton.disabled=false;useButton.dataset.rollUsed='false';useButton.textContent='Usa';
             }
           }
         }
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

      // The just-finished roll owns its chosen charges. Keep the granted
      // terms visible in the formula, but never auto-charge or auto-apply them
      // to a later d20 roll. Available bonuses remain visible below the result.
      dialog.postRollBonuses=[...numeric];
      dialog.appliedBonusIds=new Set(numeric.map(row=>row.selectionId));
      dialog.usedRollBonuses=chosen.filter(row=>row.roll_mode);
      for(const button of dialog.querySelectorAll('[data-roll-use]')){
        const selected=dialog.rollBonuses[Number(button.dataset.rollUse)];
        if(selected?.roll_mode&&button.dataset.rollUsed==='true'){
          button.disabled=true;button.textContent='Attivo';
        }
      }
        // Keep the next-roll formula in sync with the controls even after a
        // once-only bonus is consumed. Each click produces a new history entry.
        // Keep the per-dialog selection until the popup closes.
        dialog.renderRollFormula?.();
      }
      const calculatedAfter=await computeLocalData(state.editor.read());
      for(const button of dialog.querySelectorAll('[data-roll-use]')){
        const row=dialog.rollBonuses[Number(button.dataset.rollUse)];
        if(!row)continue;
        const usedForThisRoll=dialog.appliedBonusIds.has(row.selectionId);
        const tracker=row.tracker_id?calculatedAfter.trackers.find(t=>t.id===row.tracker_id):null;
        const remaining=tracker?Number(tracker.max)-Number(tracker.spent||0):Infinity;
        button.dataset.rollUsed=usedForThisRoll?'true':'false';
        button.textContent=usedForThisRoll?'Usato':'Usa';
        button.disabled=usedForThisRoll||!!(row.strict_tracker&&remaining<Math.max(1,Number(row.tracker_cost)||1))||
          !!(row.consumes_spell&&!calculatedAfter.origin_spells?.some(g=>g.spell_id===row.consumes_spell));
      }
      dialog.renderRollFormula?.();
      if(dialog.dataset.rollKind==='d20')
        refreshD20RerollChoices(dialog,state.editor.read(),calculatedAfter);
      try{await shareRoll({quiet:true});}
      catch(error){message('Tiro salvato localmente; invio chat non riuscito: '+errorMessage(error),true);}
    }finally{
      delete dialog.dataset.rolling;
      if(button&&button.isConnected)button.disabled=dialog.dataset.rollKind==='feature'&&!!dialog.rollOutcome;
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
    const c=state.editor.read();await patch(concentrationEndPatch(c));state.magicPopup='';await render();return;
  }
  if(['slot-use','slot-recover','slots-restore','slots-automatic'].includes(act)){
    const c=state.editor.read();
    if(act==='slots-automatic')await patch({spell_slots_manual:false,spell_slots_automatic:true});
    else if(act==='slots-restore')await patch({spell_slots_spent:Array(10).fill(0),pact_slots_spent:0});
    else {
      const calculated=await computeLocalData(c);
      await patch(current=>slotUsePatch(current,Number(target.dataset.level),act==='slot-use'?1:-1,calculated));
    }
    if((act==='slot-use'||act==='slot-recover')&&state.magicPopup==='slot-menu')state.magicPopup='';
    await render();return;
  }
  if(act==='hp-adjust-open'){
    const dialog=app.querySelector('#hp-adjust-dialog');
    if(!dialog)throw Error('Pannello punti ferita non disponibile.');
    openSessionDialog(dialog);
    configureHpAdjustDialog(dialog);
    dialog.querySelector('.hp-adjust-close')?.focus({preventScroll:true});
    return;
  }
  if(act==='hp-adjust-restore'){
    const creature=state.editor?.read();if(!creature)return;
    const calculated=await computeLocalData(creature);
    const value=Math.max(0,Number(calculated.stats?.max_hp)||0);
    await patch({current_hp:value});
    const input=target.closest('dialog')?.querySelector('#hp-adjust-current');
    if(input)input.value=String(value);
    return;
  }
  if(act==='hp-adjust-max'){
    const creature=state.editor?.read();
    if(!creature)throw Error('Apri prima una creatura.');
    openSheetScoreFormula(creature,await computeLocalData(creature),'hp','PF massimi');
    return;
  }
  if(act==='hp-adjust-apply'){
    const dialog=target.closest('#hp-adjust-dialog'),mode=target.dataset.hpMode;
    if(!dialog||!['damage','heal'].includes(mode))throw Error('Operazione sui PF non valida.');
    const raw=dialog.querySelector('#hp-adjust-amount')?.value.trim();
    const amount=Number(raw);
    if(!raw||!Number.isSafeInteger(amount)||amount<1||amount>99999)
      throw Error('Inserisci una quantità valida tra 1 e 99999.');
    if(!state.editor)throw Error('Apri prima una scheda.');
    let creature=state.editor.read(),calculated=await computeLocalData(creature);
    const draft=hpAdjustDraft(dialog,calculated);
    // Interrupt a potentially lethal damage entry before recording HP loss.
    // The player may ignore the response or cancel the damage entirely.
    let responseChoice;
    if(mode==='damage'&&availableZeroHpResponses({...creature,...draft},calculated,amount).length){
      closeSessionDialog(dialog);
      responseChoice=await chooseZeroHpResponse({...creature,...draft},calculated,amount);
      if(!responseChoice)return;
    }
    if(draft.current_hp!==Number(creature.current_hp||0)||draft.temporary_hp!==Number(creature.temporary_hp||0)){
      await patch(draft);
      creature=state.editor.read();
      calculated=await computeLocalData(creature);
    }
    const resolution=mode==='damage'&&responseChoice?.id?
      resolveZeroHpDamage(creature,calculated,amount,responseChoice.id,responseChoice.roll):null;
    const effectiveDamage=resolution?resolution.damage:amount;
    const damage=mode==='damage'&&!resolution?
      variantDamage(state.editor.readBase(),effectiveDamage):null;
    const concentrationCheck=mode==='damage'&&effectiveDamage>0?
      concentrationDamageCheck(creature,effectiveDamage):null;
    await patch(resolution?.patch||damage?.patch||hitPointPatch(creature,
      mode==='damage'?effectiveDamage:amount,calculated));
    closeSessionDialog(dialog);
    await render();
    if(concentrationCheck){
      const current=state.editor?.read();
      const popup=current&&current.id===creature.id?openConcentrationDamageDialog(concentrationCheck,current,state.calculated):null;
      if(popup&&damage?.overflow>0)popup.addEventListener('close',()=>promptVariantOverflow(creature.id,creature.current_form_id,damage.overflow),{once:true});
      else if(damage?.overflow>0)promptVariantOverflow(creature.id,creature.current_form_id,damage.overflow);
    }else if(damage?.overflow>0)promptVariantOverflow(creature.id,creature.current_form_id,damage.overflow);
    return;
  }
  if(act==='hp-adjust-cancel'){
    closeSessionDialog(app.querySelector('#hp-adjust-dialog'));
    return;
  }
  if(['hp-restore','hp-automatic'].includes(act)){
    const c=state.editor.read(),calculated=await computeLocalData(c);
    if(act==='hp-automatic'){
      if(!calculated.stats.automatic_hp.available)throw Error('PF automatici non disponibili');
      await patch({max_hp_base:calculated.stats.automatic_hp.value});
    }else if(act==='hp-restore')await patch({current_hp:Math.max(0,calculated.stats.max_hp)});

    await render();return;
  }
  if(act==='state-trait-jump'){
    const key=String(target.dataset.stateTrait||'');
    if(!key.startsWith('state|'))throw Error('Stato non riconosciuto.');
    state.sheet='info';state.sheetPopup='';state.sheetPopupTitle='';
    await render();
    const cards=[...app.querySelectorAll('.play-info-traits .trait-card')];
    const destination=stateTraitNavigationKey(key,state.traitRows,
      key.startsWith('state|infusion:')?
       activeItemOptionEffects(state.editor?.read()||{},state.calculated?.infusion_catalog||[],state.calculated?.features||[]):[]);
    const match=cards.find(card=>card.dataset.traitKey===destination);
    if(!match){message('Tratto dello stato non disponibile.',true);return;}
    const disclosure=match.closest('.play-traits-disclosure');
    if(disclosure)disclosure.open=true;
    match.open=true;match.scrollIntoView?.({block:'center'});
    return;
  }
  if(act==="tracker-item"){
    const index=Number(target.dataset.itemIndex),creature=state.editor?.read();
    if(!Number.isInteger(index)||index<0||!creature?.inventory?.[index])
      throw Error('Oggetto del tracker non disponibile.');
    const container=itemContainerId(creature.inventory[index],inventoryContainers(creature));
    state.inventorySelectedTabs=[container===DEFAULT_INVENTORY_CONTAINER?'items':'container:'+container];
    state.inventorySelectedIndex=index;state.sheet="inventory";await render();return;
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
    // Open on the very first catalog render: async UI tests and mobile taps
    // must not encounter a still-collapsed editor during a second render.
    state.pendingItemOwner=owner;state.pendingItemContainer=target.dataset.containerId||DEFAULT_INVENTORY_CONTAINER;
    state.disclosureState.set('catalog|'+state.sheet+'|Crea contenuto personalizzato',true);
    await navigate("catalog");
    const creator=app.querySelector(".catalog-create");
    if(creator)creator.open=true;
    const name=app.querySelector("#quick-name");
    name?.scrollIntoView?.({block:"center"});
    name?.focus();
    return;
  }
  if(act==='background-picker-open'){
    await openBackgroundPickerDialog(target.dataset.backgroundIndex||'primary');return;
  }
  if(act==='feat-catalog'){
    await openFeatPickerDialog();return;
  }
  if(act==='trait-state-end'){
    const trait=state.traitRows.find(row=>row.key===state.traitPopupKey);
    if(!trait?.readonly||!trait.state_key)throw Error('Stato non disponibile');
    const c=state.editor.read();
    if(trait.condition_id){
      const changes=exhaustionRemovablePatch(c,trait.condition_id);
      if(!changes)throw Error('Condizione non più attiva.');
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
      const id=String(trait.item_id||String(trait.origin_key).slice(5));
      const inventory=record.inventory||[];
      const indices=Array.isArray(trait.item_inventory_indices)&&trait.item_inventory_indices.length?
        trait.item_inventory_indices.filter(index=>String(inventory[index]?.id||'')===id):
        inventory.flatMap((item,index)=>String(item.id||'')===id?[index]:[]);
      if(indices.every(index=>!['weapon','shield','armor'].includes(itemKind(inventory[index]))))
        throw Error('I benefici degli oggetti comuni sono automatici.');
      const active=indices.some(index=>inventory[index].equipped===true||
        (inventory[index].equipped_slots||[]).length>0);
      const index=indices.find(index=>active?
        inventory[index].equipped===true||(inventory[index].equipped_slots||[]).length>0:true);
      if(index===undefined)throw Error('Oggetto non presente nell’inventario.');
      const updatedInventory=setItemEquipped(record.inventory,index,!active);
      // The equipment state is authoritative; clear stale manual overrides.
      const enabledPatch=traitActivationPatch(record,trait,true);
      await patch({...enabledPatch,inventory:updatedInventory});
    }else await patch(traitActivationPatch(record,trait,Boolean(trait.inactive)));
    await state.editor.flush();
    await render();return;
  }
  if(act==='trait-feature-item-grant'){
    const creature=state.editor?.read();
    if(!creature)throw Error('Personaggio non disponibile.');
    const calculated=await computeLocalData(creature);
    const grant=calculated.feature_item_grants?.find(row=>row.id===target.dataset.grantId);
    if(!grant||!state.traitRows.some(row=>row.key===state.traitPopupKey&&row.feature_origin===grant.origin_id))
      throw Error('Il beneficio non appartiene al tratto selezionato.');
    if(grant.activation_action_id){
      const ability=classFeatureEntries(creature,calculated).find(row=>row.class_feature_id===grant.activation_action_id);
      if(!ability)throw Error('Capacità di creazione non disponibile.');
      dismissTraitBenefitDialog();await activateClassAbility(creature,calculated,ability);return;
    }
    const changes=claimFeatureItemPatch(creature,calculated,target.dataset.grantId,target.dataset.itemId);
    await patch(changes);await render();return;
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
    let targetInventory=null;
    if(type==='effect_extensions'&&values.target_kind==='item'){
      const index=Number(values.target_item_index),inventory=state.editor.read().inventory||[];
      const item=inventory[index];
      if(!Number.isInteger(index)||index<0||!item||!item.id)throw Error('Seleziona un oggetto valido.');
      const quantity=Number(item.quantity??1);
      if(!Number.isSafeInteger(quantity)||quantity<1)throw Error('Quantità oggetto non valida.');
      // The chosen stack may contain identical physical copies. Split off
      // exactly one and attach a stable instance ID before saving the benefit.
      targetInventory=structuredClone(inventory);
      const selected=targetInventory[index];
      selected.instance_id=selected.instance_id||'pwa_instance_'+crypto.randomUUID();
      selected.standalone_instance=true;
      if(quantity>1){
        const rest=structuredClone(item),attuned=itemAttunementCount(item);
        selected.quantity=1;
        rest.quantity=quantity-1;rest.instance_id='pwa_instance_'+crypto.randomUUID();
        rest.equipped=false;rest.equipped_slots=[];
        if(requiresAttunement(resolveOwnedItem(item))){
          selected.attuned_count=Math.min(1,attuned);selected.attuned=selected.attuned_count>0;
          rest.attuned_count=Math.max(0,attuned-1);rest.attuned=rest.attuned_count>0;
        }
        targetInventory.splice(index+1,0,rest);
      }
      values.target_name=String(item.name||item.id);
      values.target_id=String(item.id);
      values.target_instance_id=String(selected.instance_id);
      if(quantity===1&&item.instance_id)targetInventory=null;
    }
    // Dice that modify a permanent score resolve once; a sheet redraw never
    // changes the rolled value or redirects the origin of the benefit.
    if(type==='bonus'&&validBonusDice(values.expression)){
      const targetKey=String(values.target||'');
      const rollable=['ability_check','saving_throw','attack_roll','damage_roll','any_d20','initiative','spell_attack'].includes(targetKey)||
        /^(ability_check:|skill:|save:|attack_hit:|attack_damage:|casting_hit:)/.test(targetKey);
      if(!rollable){
        values.rolled_total=rollBattleDamage(String(values.expression).replaceAll(' ',''),
          sides=>1+Math.floor(Math.random()*sides)).total;
      }
    }
    const changes=addBenefitPatch(state.editor.read(),trait,type,values,'trait:'+crypto.randomUUID());
    if(type==='bonus'&&!validBonusDice(values.expression)&&
       /Formula non applicata/.test(formulaPreview(values.expression,state.calculated)))
      throw Error('Formula non valida');
    await patch({...changes,...(targetInventory?{inventory:targetInventory}:{})});
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
    const dialog=target.closest?.('#trait-benefits-dialog[open]');
    if(!dialog||dialog!==app.querySelector('#trait-benefits-dialog[open]')||
       dialog.dataset.traitKey!==state.traitPopupKey)return;
    const trait=state.traitRows.find(row=>row.key===state.traitPopupKey);
    const id=target.dataset.benefitId,type=target.dataset.benefitType;
    const item=trait&&(state.traitBenefitGroupsByKey?.get(trait.key)||
      distributeTraitBenefits(state.traitRows,state.editor.read(),state.calculated).byKey.get(trait.key))
      ?.find(group=>group.type===type)?.items.find(row=>row.id===id);
    if(!item)throw Error('Beneficio non presente');
    setTraitBenefitRemovalConfirmation({...item,type});
    return;
  }
  if(act==='trait-benefits-remove-cancel'){
    setTraitBenefitRemovalConfirmation();
    return;
  }
  if(act==='trait-benefits-remove-confirm'){
    const trait=state.traitRows.find(row=>row.key===state.traitPopupKey);
    const id=target.dataset.benefitId,type=target.dataset.benefitType;
    if(!trait||id!==state.traitPopupConfirm)throw Error('Eliminazione non confermata');
    const group=(state.traitBenefitGroupsByKey?.get(trait.key)||
      distributeTraitBenefits(state.traitRows,state.editor.read(),state.calculated).byKey.get(trait.key))
      ?.find(row=>row.type===type&&row.items.some(item=>item.id===id));
    if(!group)throw Error('Beneficio non più presente');
    await patch(removeBenefitPatch(state.editor.read(),trait,{id,type}));
    await state.editor.flush();
    state.traitPopupConfirm='';
    await render();return;
  }
  if(act==='trait-benefits-restore'){
    const trait=state.traitRows.find(row=>row.key===state.traitPopupKey);
    if(!trait)throw Error('Tratto non disponibile');
    const record=state.editor.read();
    const restored=restoreBenefitPatch(record,trait);
    if(/^Descrizione · /.test(trait.name)){
      const removed={...restored.trait_benefit_removed};
      delete removed['origin-benefits:'+trait.key];
      restored.trait_benefit_removed=removed;
    }
    await patch(restored);
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
      if(key==='classes')throw Error('Aggiungi una nuova classe dal popup di livellaggio.');
      const defaults={proficiency_choices:{kind:"skill",key:"",origin_id:"",origin_name:"",disabled:false},
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
    await refreshCharacterHomebrewOptions();
    const owner=state.pendingItemOwner;
    if(owner&&state.catalogCategory==="items"){
      const editor=await openCreatureEditor(owner);
      const record=editor.read();
      const item=createOwnedItem({...created.data,id:created.id,name:created.name,
        source:created.source}, "pwa_"+crypto.randomUUID());
      if(state.pendingItemContainer&&inventoryContainers(record).some(row=>row.id===state.pendingItemContainer)&&state.pendingItemContainer!==DEFAULT_INVENTORY_CONTAINER)item.container_id=state.pendingItemContainer;
      const inventory=[...(record.inventory||[]),item];
      await editor.update({inventory});
      state.page="library";state.libraryMode=false;state.creatureId=owner;
      state.editor=editor;state.sheet="inventory";
      focusInventorySection(editor.read(),state.pendingItemContainer&&state.pendingItemContainer!==DEFAULT_INVENTORY_CONTAINER?
        'container:'+state.pendingItemContainer:'items');
      state.inventorySelectedIndex=inventory.length-1;state.pendingItemOwner="";state.pendingItemContainer="";
      await render();message("Oggetto homebrew aggiunto all'inventario.");return;
    }
    state.catalogSelected=-1;state.catalogQuery=created.name;
    await render();message('Contenuto personalizzato salvato in locale.');return;
  }
  if(act==='quick-delete'){
    if(!window.confirm('Eliminare questo contenuto personalizzato?'))return;
    await deleteQuickHomebrew(target.dataset.id);
    await refreshCharacterHomebrewOptions();
    state.catalogSelected=-1;state.catalogQuery='';await render();message('Contenuto eliminato.');return;
  }
  if(act==="catalog-open"){
    state.catalogSelected=Number(target.dataset.index);
    await render();window.scrollTo(0,0);app.focus({preventScroll:true});return;
  }
  if(act==="catalog-send"){
    const entry=state.catalogRows[state.catalogSelected];
    if(!entry?._homebrew||!entry.id)throw Error('Seleziona un contenuto homebrew da mandare.');
    await openSendDialog('homebrew',entry.name,()=>exportCatalogHomebrewEntry(entry),message);return;
  }
  if(act==="catalog-assign"){
    const cId=state.pendingItemOwner&&state.catalogCategory==="items"?state.pendingItemOwner:document.querySelector("#catalog-creature")?.value;
    const entry=state.catalogRows[state.catalogSelected];
    const stored=await loadCreature(cId);
    if(!stored||!entry)throw new Error("Seleziona contenuto e creatura.");
    const editor=await openCreatureEditor(cId),sheet=editor.read();
    if(!isContentAvailableForRules(entry,sheet.rules_version))throw Error('Questo materiale non è disponibile per le regole 2014.');
    const category=entry._category;
    if(category==="spells"){
      await editor.update(addSelectedSpell(sheet,entry,"prepared_spells"));
    }else if(["weapons","armor","tools","mundane_items","magic_items","items"].includes(category)){
      const item=createOwnedItem(entry,"pwa_"+crypto.randomUUID());
      if(state.pendingItemContainer&&state.pendingItemContainer!==DEFAULT_INVENTORY_CONTAINER&&inventoryContainers(sheet).some(row=>row.id===state.pendingItemContainer))item.container_id=state.pendingItemContainer;
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
      await editor.update(referencePatch(sheet,'species',entry));
    }else throw new Error("Categoria non assegnabile alla scheda.");
    state.cachedCreatures=readableArchiveCreatures(await listCreatures());
    if(state.pendingItemOwner&&category!=='feats'){
       state.page='library';state.libraryMode=false;state.creatureId=cId;state.editor=editor;
       state.sheet='inventory';
       focusInventorySection(editor.read(),state.pendingItemContainer&&
        state.pendingItemContainer!==DEFAULT_INVENTORY_CONTAINER?'container:'+state.pendingItemContainer:'items');
       state.inventorySelectedIndex=(editor.read().inventory||[]).length-1;
       state.pendingItemOwner='';state.pendingItemContainer='';await render();
     }
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
  if(act==="library-export"||act==="library-delete"||act==="library-send"){
    const rows=(await listCreatures("default",{includeSubcreatures:act==="library-delete"}))
      .filter(row=>state.librarySelectedIds.has(row.creature.id));
    if(!rows.length)throw new Error("Seleziona almeno una creatura.");
    if(act==="library-send"){
       if(rows.length>200)throw Error("Seleziona al massimo 200 creature.");
       const title=rows.length===1?rows[0].creature.name:rows.length+' creature';
       await openSendDialog('creature',title,async()=>{
         const blob=rows.length===1?await exportCreature(rows[0].creature.id):
           await exportCreatureBatch(rows.map(row=>row.creature.id));
         return JSON.parse(await blob.text());
       },message);
       return;
     }
     if(act==="library-export"){
      if(rows.length>200)throw new Error("Puoi esportare fino a 200 creature in un file.");
      if(await download(await exportCreatureBatch(rows.map(row=>row.creature.id)),"vtt-creature-selezionate.json"))
        message("Esportate "+rows.length+" creature e i loro contenuti homebrew.");
      return;
    }
    if(!await confirmCreatureDeletion(rows))return;
    let deleted=0;
    const selectedIds=new Set(rows.map(row=>row.creature.id));
    for(const row of rows){
      // An owner deletion already removes its selected descendants atomically.
      if(row.creature.parent_creature_id&&selectedIds.has(row.creature.parent_creature_id)){
        state.librarySelectedIds.delete(row.creature.id);
        continue;
      }
      if(await removeCreature(row.creature.id,"default",row.revision)){
        state.librarySelectedIds.delete(row.creature.id);deleted++;
      }
    }
    await render();message("Eliminate "+deleted+" creature dall'archivio locale.");return;
  }
  if(act==="library-filter"){
    if(!['all','character','monster'].includes(target.dataset.kind))return;
    state.libraryFilter=target.dataset.kind;
    syncLibraryFilterUI();return;
  }
  if(act==="library-add"){
    state.libraryCreateKind='character';state.libraryBestiaryKey='';state.libraryBestiaryLimit=36;
    state.libraryMiniatureManuallySelected=false;
    state.libraryMiniatureId='sariel';
    state.libraryMiniatureLimit=36;
    const dialog=app.querySelector('#library-create-dialog');
    if(dialog){
      const name=dialog.querySelector('#library-create-name');if(name)name.value='';
      const search=dialog.querySelector('#library-bestiary-search');if(search)search.value='';
      paintLibraryCreateMode();
      openDialog(dialog);
      void loadLibraryMiniatures();
    }
    return;
  }

  if(act==="library-create-kind"){
    if(!['character','monster'].includes(target.dataset.kind))return;
    state.libraryCreateKind=target.dataset.kind;
    state.libraryMiniatureManuallySelected=false;
    state.libraryMiniatureId=state.libraryCreateKind==='character'?
      (libraryMiniatureOptions().find(row=>row.id==='sariel')?.id||libraryMiniatureOptions()[0]?.id||''):'';
    selectBestiaryDefaultMiniature();
    paintLibraryCreateMode();
    if(state.libraryCreateKind==='monster'&&!state.libraryBestiaryEntries.length)void loadLibraryBestiary();
    return;
  }
  if(act==="library-bestiary-select"){
    const entry=state.libraryBestiaryEntries.find(row=>row.key===target.dataset.bestiaryKey);
    if(!entry)return;
    state.libraryBestiaryKey=entry.key;
    selectBestiaryDefaultMiniature();
    paintLibraryBestiary();paintLibraryMiniatures();
    return;
  }
  if(act==="library-bestiary-more"){
    state.libraryBestiaryLimit+=36;paintLibraryBestiary();
    return;
  }
  if(act==="library-miniature-select"){
    if(libraryMiniatureOptions().some(row=>row.id===target.dataset.miniatureId)){
      state.libraryMiniatureId=target.dataset.miniatureId;state.libraryMiniatureManuallySelected=true;paintLibraryMiniatures();
    }
    return;
  }
  if(act==="library-miniature-more"){
    const count=app.querySelectorAll('#library-create-dialog .library-miniature-option').length;
    state.libraryMiniatureLimit+=36;
    paintLibraryMiniatures();
    const area=app.querySelector('#library-create-dialog .library-miniature-choices');
    const choices=area?.querySelectorAll('.library-miniature-option');
    if(choices?.length>count)
      area.scrollTop=choices[count].offsetTop-choices[0].offsetTop;
    return;
  }
  if(act==="library-create-close"){
    const dialog=app.querySelector('#library-create-dialog');
    closeDialog(dialog);
    return;
  }
  if(act==="create"){
    const dialog=app.querySelector('#library-create-dialog');
    if(!dialog?.open)throw Error("Apri prima la creazione di una creatura.");
    const name=String(dialog.querySelector('#library-create-name')?.value||'').trim();
    const miniature=libraryMiniatureOptions().find(row=>row.id===state.libraryMiniatureId);
    state.magicPopup="";
    let row;
    if(state.libraryCreateKind==='monster'){
      const entry=state.libraryBestiaryEntries.find(source=>source.key===state.libraryBestiaryKey);
      if(!entry)throw Error('Seleziona una razza dal bestiario.');
      const stat=await entry.load();
      row=await createBestiaryMonster(stat,{display_name:name||entry.name,source:entry.source},'default',miniature||entry.miniature||null);
    }else{
      if(!miniature)throw Error("Seleziona una miniatura di base.");
      row=await createCreature('character',name||'Nuova creatura','default',miniature);
    }
    closeDialog(dialog);
    state.creatureId=row.id;state.libraryMode=false;state.editor=null;state.sheet="info";
    await refreshCharacterHomebrewOptions();
    state.inventorySelectedTabs=['all'];state.inventorySubtab='items';
    await render();return;
  }
  if(act==="import"||act==="library-quick-import"){
    const dialog=app.querySelector('#library-create-dialog');
    closeDialog(dialog);
    creatureInput.click();return;
  }
  if(act==="restore-backup"){backupInput.click();return;}
  if(act==="backup"){
    const blob=await exportBackup();
    if(await download(blob,"vtt-pwa-backup-"+new Date().toISOString().slice(0,10)+".json"))
      message("Backup esportato. Conservalo fuori dal browser.");
    return;
  }
  if(act==="open"){
    const id=target.dataset.id;
    if(state.librarySelectedIds.size){
      if(state.librarySelectedIds.has(id))state.librarySelectedIds.delete(id);
      else state.librarySelectedIds.add(id);
      syncLibrarySelectionUI();return;
    }
    state.magicPopup="";state.creatureId=id;state.libraryMode=false;state.sheet="info";state.editor=null;state.inventorySelectedIndices.clear();
    await refreshCharacterHomebrewOptions();
    state.inventorySelectedTabs=['all'];state.inventorySubtab='items';
    await render();return;
  }
  if(act==="back"){
    const parentId=state.editor?.readBase()?.parent_creature_id;
    if(parentId){
      await flushPendingFields();
      state.creatureId=parentId;state.editor=null;state.sheet="info";state.libraryMode=false;
      await render();
      return;
    }
    await navigate("library");
    window.scrollTo(0,0);app.focus({preventScroll:true});
    return;
  }
  if(act==="sheet"){
    state.magicPopup="";
    try{await state.editor?.flush();}catch(error){throw new Error("Salvataggio incompleto: "+errorMessage(error));}
    if(!state.creatureId)return;
    state.sheetPopup=target.dataset.openContext||"";state.sheetPopupTitle=target.title||"";state.page="library";state.libraryMode=false;state.inventorySelectedIndices.clear();state.sheet=['actions','traits'].includes(target.dataset.sheet)?(target.dataset.sheet==='traits'?'info':'battle'):target.dataset.sheet;await render();return;
  }
  if(act==="send"){
    await flushPendingFields();
    const record=state.editor?.read();
    if(!record)throw Error('Apri una creatura prima di mandarla.');
    await openSendDialog('creature',record.name,async()=>{
      await flushPendingFields();
      return JSON.parse(await (await exportCreature(record.id)).text());
    },message);
    return;
  }
  if(act==="export"){
    await state.editor?.flush();
    const c=state.editor.read();
    const rootId=c.parent_creature_id||c.id;
    const root=c.parent_creature_id?(await loadCreature(rootId))?.data:c;
    if(!root)throw Error("Proprietario della sottocreatura non disponibile.");
    if(await download(await exportCreature(rootId),filename(root.name)+".json"))
      message("Scheda esportata in formato VTT.");
    return;
  }
  if(act==="delete"){
    const record=state.editor.read();
    if(!await confirmCreatureDeletion([record]))return;
    await state.editor.flush();
    await removeCreature(record.id,"default",state.editor.revision);
    const parentId=record.parent_creature_id;
    state.creatureId=parentId||null;state.libraryMode=!parentId;state.editor=null;state.sheet="info";
    await render();message("Scheda eliminata.");return;
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
    const defaultPool=pools.find(pool=>pool.available>0);
    const diceControls=pools.map(pool=>'<label class="play-rest-die">'+
      '<span>d'+pool.die+' · '+pool.available+' / '+pool.total+' disponibili</span>'+
      '<input type="number" inputmode="numeric" data-rest-die="'+pool.die+
      '" min="0" max="'+pool.available+'" step="1" value="'+(pool===defaultPool?1:0)+'" aria-label="Dadi Vita d'+pool.die+' da spendere"></label>').join('');
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
      // Rest-based reselection rights are not resource tracker recoveries.
      const choices=powerRestSelections(current,calculated).filter(row=>
        row.recovery===event||event==='long_rest'&&row.recovery==='short_rest');
      const choiceHtml=choices.length?'<ul>'+choices.map(row=>
        '<li><strong>'+esc(row.name)+'</strong> · '+esc(row.label)+
        ' · opzioni riselezionabili in Poteri</li>').join('')+'</ul>':
        '<p>Nessuna nuova opzione da riselezionare.</p>';
      summary.innerHTML='<div class="play-rest-confirm"><h3>Riposo completato</h3>'+
        '<p><strong>'+result.healed+' PF recuperati.</strong></p>'+rolled+
        '<h4>Risorse recuperate</h4>'+recoveryHtml+
        '<h4>Scelte modificabili</h4>'+choiceHtml+
        '<button type="button" class="btn primary" data-act="sheet-context-close">Chiudi</button></div>';
    }catch(error){
      button.disabled=false;
      preview.querySelector('[data-rest-error]').textContent=errorMessage(error);
    }
    return;
  }


  if(act==='racial-option-open'){
    const record=state.editor?.read();
    if(!record)throw Error('Apri prima una creatura.');
    const calculated=await computeLocalData(record);
    const group=String(target.dataset.racialOptionGroup||'');
    const choice=(calculated.pending_choices||[]).find(row=>
      row.kind==='racial_option'&&row.group===group);
    if(!choice)throw Error('Scelta razziale non disponibile.');
    await openCharacterChoice(choice);return;
  }
  if(act==='rest-training-open'){
    await openRacialRestTrainingDialog(String(target.dataset.trainingGroup||''));
    return;
  }
  if(act==='rest-training-close'){
    closeDialog(app.querySelector('#racial-rest-training-dialog'),{remove:true});
    return;
  }
  if(act==='rest-training-apply'){
    const dialog=app.querySelector('#racial-rest-training-dialog');
    const current=state.editor?.read();
    if(!dialog?.open||!current||dialog.dataset.creatureId!==current.id)
      throw Error('Riapri il privilegio dalla scheda.');
    const fresh=await computeLocalData(current);
    const choice=(fresh.racial_rest_choices||[]).find(row=>row.group===dialog.dataset.trainingGroup);
    if(!choice)throw Error('Privilegio non disponibile.');
    const selected=[...dialog.querySelectorAll('[data-rest-training-pick]')]
      .sort((a,b)=>Number(a.dataset.restTrainingPick)-Number(b.dataset.restTrainingPick))
      .map(row=>row.value||'');
    const withoutOwn={...current,proficiency_choices:(current.proficiency_choices||[])
      .filter(row=>row.rest_training_group!==choice.group)};
    const outside=await computeLocalData(withoutOwn);
    const allowed={skill:SKILLS.map(([key])=>key),
      weapon:trainingProficiencyOptions('weapon',current),
      tool:trainingProficiencyOptions('tool',current),
      unavailable:outside.proficiencies||[]};
    const changes=restTrainingPatch(current,choice,selected,allowed);
    target.disabled=true;
    try{
      await patch(changes);
      if(state.saveError)throw Error(state.saveError);
      closeDialog(dialog,{remove:true});await render();
    }catch(error){
      target.disabled=false;
      const errorView=dialog.querySelector('[data-rest-training-error]');
      errorView.hidden=false;errorView.textContent=errorMessage(error);
    }
    return;
  }

  if(act==='benefit-option-open'){
    await openBenefitOptionDialog(target.dataset.powerSelectionId,target.dataset.powerOptionId);return;
  }
  if(act==='benefit-option-close'){
    closeDialog(app.querySelector('#benefit-option-dialog'),{remove:true});return;
  }
  if(act==='power-selection-details'){
    const dialog=app.querySelector('#power-selection-dialog');
    if(dialog?.open)await openBenefitOptionDialog(dialog.dataset.powerSelectionId,target.dataset.powerOptionId);
    return;
  }
  if(act==='benefit-target-choose'){
    const dialog=app.querySelector('#benefit-option-dialog');if(!dialog?.open)throw Error('Riapri il beneficio.');
    dialog.dataset.selectedItem=target.dataset.index??'';
    dialog.dataset.selectedCatalogIndex=target.dataset.catalogIndex??'';
    for(const row of dialog.querySelectorAll('[data-act="benefit-target-choose"]')){
      const selected=row===target;row.classList.toggle('is-selected',selected);row.setAttribute('aria-pressed',String(selected));
    }
    dialog.querySelector('[data-act="benefit-option-apply"]').disabled=false;return;
  }
  if(act==='benefit-option-apply'||act==='benefit-option-remove'){
    const dialog=app.querySelector('#benefit-option-dialog'),record=state.editor?.read();
    if(!dialog?.open||!record||record.id!==dialog.dataset.creatureId)throw Error('Riapri il beneficio.');
    const error=dialog.querySelector('[data-benefit-error]');target.disabled=true;
    try{
      const calculated=await computeLocalData(record),id=dialog.dataset.powerSelectionId,optionId=dialog.dataset.powerOptionId;
      const model=calculated.power_selections.find(row=>row.id===id),option=model?.options.find(row=>row.id===optionId);
      if(!option||!model.layers.applied)throw Error('Beneficio non più disponibile.');
      const targetRule=model.layers.applied.target;
      const active=model.layers.applied.selected.some(row=>selectedPowerId(row)===optionId);
      const apply=act==='benefit-option-remove'?false:targetRule?true:!active;
      let itemIndex=act==='benefit-option-remove'?Number(target.dataset.index??-1):Number(dialog.dataset.selectedItem||-1),current=record;
      if(apply&&targetRule){
        if(dialog.dataset.selectedCatalogIndex!==''){
          const entry=state.referenceCatalogs.items?.[Number(dialog.dataset.selectedCatalogIndex)];
          if(!targetRule.allow_catalog||!entry||!isContentAvailableForRules(entry,record.rules_version))throw Error('Oggetto non disponibile.');
          current={...record,inventory:[...(record.inventory||[]),createOwnedItem(entry,'pwa_'+crypto.randomUUID())]};
          itemIndex=current.inventory.length-1;
        }
        if(!powerSelectionTargets(current,model,option).some(row=>row.index===itemIndex))throw Error('Scegli un oggetto compatibile.');
      }
      const selection=option.effect_choice,value=dialog.querySelector('[data-benefit-effect]')?.value;
      const changes=powerApplicationPatch(current,calculated,calculated.power_selection_catalog,id,optionId,apply,
        {itemIndex,effectChoice:selection?{[selection.key]:value}:{}});
      if(state.editor?.read()?.id!==record.id)throw Error('La scheda è cambiata: riapri il beneficio.');
      await patch(changes);if(state.saveError)throw Error(state.saveError);await state.editor.flush();
      closeDialog(dialog,{remove:true});
      if(apply&&model.on_apply==='companion_grant')await createOptionCompanion(state.editor.read(),option,await computeLocalData(state.editor.read()));
      await render();
    }catch(info){target.disabled=false;error.hidden=false;error.textContent=errorMessage(info);}
    return;
  }
  if(act==='power-selection-open'){
    await openBenefitSelectionDialog(target.dataset.powerSelectionId,target.dataset.powerStage);return;
  }
  if(act==='power-selection-close'){
    closeDialog(app.querySelector('#power-selection-dialog'),{remove:true});return;
  }
  if(act==='power-selection-custom'){
    const dialog=app.querySelector('#power-selection-dialog'),record=state.editor?.read();
    if(!dialog?.open||!record||record.id!==dialog.dataset.creatureId)
      throw Error('Riapri la selezione dei poteri dalla scheda.');
    const calculated=await computeLocalData(record),id=dialog.dataset.powerSelectionId,
      stage=dialog.dataset.powerStage;
    const changes=powerSelectionCustomPatch(record,calculated,calculated.power_selection_catalog,
      id,stage,'homebrew:'+crypto.randomUUID(),
      dialog.querySelector('[data-power-custom-name]')?.value,
      dialog.querySelector('[data-power-custom-description]')?.value||'',{
        itemIndex:Number(dialog.querySelector('[data-power-target-index]')?.value??-1)
      });
    await patch(changes);closeDialog(dialog,{remove:true});await render();
    await openBenefitSelectionDialog(id,stage);return;
  }
  if(act==='power-selection-toggle'){
    const dialog=app.querySelector('#power-selection-dialog');
    const record=state.editor?.read();
    if(!dialog?.open||!record||record.id!==dialog.dataset.creatureId)
      throw Error('Riapri la selezione dei poteri dalla scheda.');
    const calculated=await computeLocalData(record),id=dialog.dataset.powerSelectionId;
    const stage=dialog.dataset.powerStage,model=calculated.power_selections?.find(row=>row.id===id);
    const option=model?.options.find(row=>row.id===target.dataset.powerOptionId);
    if(!option)throw Error('Opzione non disponibile.');
    if(stage==='applied'){await openBenefitOptionDialog(id,option.id);return;}
    const subchoices=option.subchoices&&target.dataset.powerRemove!=='true'?
      [...dialog.querySelectorAll('[data-power-subchoice][data-power-option="'+option.id+'"]')].map(input=>input.value):[];
    const changes=powerSelectionPatch(record,calculated,calculated.power_selection_catalog,id,stage,option.id,subchoices);
    await patch(changes);closeDialog(dialog,{remove:true});await render();
    await openBenefitSelectionDialog(id,stage);return;
  }
  if(act==='item-option-remove'||act==='infusion-clear'){
    const creature=state.editor?.read();
    if(!creature)throw Error('Apri prima una creatura.');
    if(target.dataset.selectionId){
      const calculated=await computeLocalData(creature);
      await patch(powerApplicationPatch(creature,calculated,calculated.power_selection_catalog,target.dataset.selectionId,target.dataset.optionId,false));
    }else await patch(clearInfusionPatch(creature,Number(target.dataset.index)));
    await render();return;
  }
  if(["inventory-container-add","inventory-container-rename","inventory-container-delete"].includes(act)){
    const record=state.editor?.read();if(!record)throw Error("Apri prima una creatura.");
    const containers=inventoryContainers(record),id=target.dataset.containerId;
    if(act==="inventory-container-add"){
      const name=window.prompt("Nome del nuovo contenitore:");if(name===null)return;
      const newId="container_"+crypto.randomUUID();
      await patch(createInventoryContainer(record,newId,name));
      focusInventorySection(state.editor.read(),'container:'+newId);
    }else if(act==="inventory-container-rename"){
      const original=containers.find(row=>row.id===id);if(!original||id===DEFAULT_INVENTORY_CONTAINER)throw Error("Contenitore non rinominabile.");
      const name=window.prompt("Rinomina contenitore:",original.name);if(name===null)return;
      const trimmed=name.trim();if(!trimmed||trimmed.length>80||containers.some(row=>row.id!==id&&row.name.toLowerCase()===trimmed.toLowerCase()))throw Error("Nome non valido o già utilizzato.");
      await patch({inventory_containers:containers.slice(1).map(row=>row.id===id?{...row,name:trimmed}:row)});
    }else{openInventoryContainerDelete(id);return;}
    state.inventoryMenuIndex=-1;await render();return;
  }
  if(act==="inventory-subtab"||act==="inventory-toggle-all"){
    const record=state.editor?.read();if(!record)throw Error("Apri prima una creatura.");
    const keys=inventorySectionKeys(record),selected=inventoryVisibleSections(record);
    if(act==="inventory-toggle-all"){
      setInventoryVisibleSections(record,selected.length===keys.length?['items']:keys);
      state.inventorySubtab='items';
    }else{
      const key=target.dataset.subtab;
      if(!keys.includes(key))throw Error("Sezione inventario non valida.");
      const next=selected.includes(key)?selected.filter(x=>x!==key):[...selected,key];
      setInventoryVisibleSections(record,next);
      state.inventorySubtab=next.includes(key)?key:next[0]||'items';
    }
    state.sheetPopup="";state.inventoryMenuIndex=-1;
    await render();return;
  }
  if(act==="inventory-open-trait"){
    const index=Number(target.dataset.index),item=state.editor?.read()?.inventory?.[index];
    if(!item?.id||isDocument(item))throw Error('Tratto dell’oggetto non disponibile.');
    state.sheetPopup='';state.sheet='info';await render();
    const trait=(state.traitRows||[]).find(row=>row.category==='oggetti'&&row.rank===0&&
      row.origin_key==='item:'+item.id);
    if(!trait){message('Il tratto dell’oggetto non è disponibile in questa scheda.',true);return;}
    const card=[...app.querySelectorAll('.trait-row [data-trait-key]')]
      .find(row=>row.dataset.traitKey===trait.key);
    card?.scrollIntoView?.({block:'center',behavior:'instant'});
    state.traitPopupDraftKind='';state.traitPopupDraftTarget='';
    state.traitPopupKey=trait.key;state.traitPopupConfirm='';state.traitPopupTrait=trait;
    mountTraitBenefitDialog();return;
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
  if(act==="inventory-equip-slot"){
     const record=state.editor.read(),index=Number(target.dataset.index),slot=target.dataset.slot;
     const owned=record.inventory?.[index];
     if(!owned||!['main','off','body'].includes(slot)||!validSlot(owned,slot)||
       slot==='main'&&itemKind(owned)==='shield')throw Error('Slot equipaggiamento non valido.');
     const equipped=Array.isArray(owned.equipped_slots)&&owned.equipped_slots.includes(slot);
     const main=record.inventory.find(item=>item.equipped_slots?.includes('main'));
     const resolved=main?resolveOwnedItem(main):null;
     if(!equipped&&slot==='off'&&record.hand_off_with_two_handed!==true&&resolved&&
       (hasProperty(resolved,'2H')||
        record.hand_grip_two_handed&&hasProperty(resolved,'V')))
       throw Error('Mano secondaria occupata. Puoi sbloccarla dal popup Equipaggiamento.');
     // A repeated press frees just the chosen slot without re-equipping the item.
     const inventory=equipSlot(record.inventory,slot,equipped?-1:index,
       {allowOffhandWithTwoHanded:record.hand_off_with_two_handed===true});
     inventory[index].equipped=inventory[index].equipped_slots.length>0;
     const nextMain=inventory.find(item=>item.equipped_slots?.includes('main'));
     const nextResolved=nextMain?resolveOwnedItem(nextMain):null;
     const grip=Boolean(nextResolved&&hasProperty(nextResolved,'V')&&record.hand_grip_two_handed);
     if(slot==='main'&&grip&&record.hand_off_with_two_handed!==true)
       for(const item of inventory)item.equipped_slots=(item.equipped_slots||[]).filter(s=>s!=='off');
     const trait=(state.traitRows||[]).find(row=>row.origin_key==='item:'+String(owned.id||''));
     const overrides=trait?traitActivationPatch(record,trait,inventory[index].equipped):{};
     await patch({...overrides,inventory,
       ...(slot==='main'?{hand_main_special:'none',hand_grip_two_handed:grip,
         ...((nextResolved&&hasProperty(nextResolved,'2H')||grip)&&
           record.hand_off_with_two_handed!==true?{hand_off_special:'none'}:{})}:{}),
       ...(slot==='off'?{hand_off_special:'none'}:{})});
     state.inventorySelectedIndex=index;
     await render();return;
   }
   if(act==="inventory-equip"){
    const record=state.editor.read(),index=Number(target.dataset.index);
    const owned=record.inventory?.[index];
    if(!owned)throw Error("Oggetto non trovato.");
    if(!['weapon','armor','shield'].includes(itemKind(owned)))throw Error("Questo oggetto è sempre attivo; non richiede equipaggiamento.");
    const enabled=!(owned.equipped===true||(owned.equipped_slots||[]).length>0);
    const inventory=setItemEquipped(record.inventory,index,enabled,
       {allowOffhandWithTwoHanded:record.hand_off_with_two_handed===true});
    const itemKey='item:'+String(owned.id||'');
    const trait=(state.traitRows||[]).find(row=>row.origin_key===itemKey);
    const overrides=trait?traitActivationPatch(record,trait,true):{};
    await patch({...overrides,inventory});
    state.inventorySelectedIndex=index;
    await render();return;
  }
  if(act==="inventory-attunement"){
    const creature=state.editor?.read(),index=Number(target.dataset.index),delta=Number(target.dataset.delta);
    if(!creature||![-1,1].includes(delta))throw Error('Sintonia non valida.');
    const current=state.calculated?.attunements?.counts[index]??itemAttunementCount(creature.inventory?.[index]);
    await patch({inventory:changeOwnedItem(creature.inventory||[],index,'attuned_count',current+delta,
      {attunementMax:state.calculated?.attunements?.maximum??creature.attunement_max_base??3})});
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
    if(!state.editor||!inventoryVisibleSections(state.editor.read()).includes("scrolls"))
      throw Error("Apri la sezione Pergamene della creatura.");
    const c=state.editor.read(),spellId=app.querySelector('#scroll-spell-select')?.value;
    const spell=spellsForEdition(state.spellCatalog||[],c.rules_version).find(s=>String(s.id)===spellId);
    const level=app.querySelector('#scroll-spell-level')?.value;
    if(!spell||level===undefined||level==='')throw Error("Seleziona un incantesimo e un livello.");
    const created=addSpellScroll(c.inventory||[],{...spell,description:flattenDescription(spell)},level,"pwa_"+crypto.randomUUID());
    state.inventorySelectedIndex=created.index;state.sheetPopup='';state.scrollSpellQuery='';
    await patch({inventory:created.inventory});await render();message("Pergamena aggiunta all'inventario.");return;
  }
  if(act==="item-catalog"){const owner=state.creatureId;state.catalogCategory="items";state.catalogSelected=-1;state.catalogQuery="";state.pendingItemOwner=owner;state.pendingItemContainer=target.dataset.containerId||DEFAULT_INVENTORY_CONTAINER;await navigate("catalog");return;}
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
  if(act==='spell-known-toggle'){
    const creature=state.editor.read(),classes=state.calculated?.casting_classes||[];
    const member=classes.find(row=>row.id===target.dataset.classId);
    if(!member)throw Error('Lista di classe non disponibile.');
    const spell=state.spellCatalog?.[Number(target.dataset.spellIndex)];
    if(!spell)throw Error('Incantesimo non trovato.');
    const wasKnown=target.dataset.known==='true';
    let change;
    if(member.mode==='Conosciuti'){
      const index=availableSpells(creature).findIndex(row=>spellId(row)===spell.id&&
        castingSources(row,classes,state.spellCatalog||[]).includes(member.id));
      change=wasKnown?removeSelectedSpell(creature,'prepared_spells',index,
        {classId:member.id,classes,catalog:state.spellCatalog||[]}):
        addSelectedSpell(creature,spell,'prepared_spells',
          {member,classes,catalog:state.spellCatalog||[],allowNonClass:!spellEligible(spell,member)});
    }else{
      change=changeKnownClassSpell(creature,member,spell,!wasKnown,state.spellCatalog||[]);
    }
    if(wasKnown&&member.mode==='Preparati'){
      const index=availableSpells(creature).findIndex(row=>spellId(row)===spell.id&&
        castingSources(row,classes,state.spellCatalog||[]).includes(member.id));
      if(index>=0)Object.assign(change,removeSelectedSpell(creature,'prepared_spells',index,
          {classId:member.id,classes,catalog:state.spellCatalog||[]}));
    }
    await patch(change);await render();return;
  }
  if(act==="spell-pick"){
    const index=Number(target.dataset.index);
    const spell=state.spellCatalog?.[index];
    if(!spell)throw Error("Seleziona un incantesimo valido.");
    const classes=state.calculated?.casting_classes||[],member=classes.find(row=>row.id===state.spellClass);
    await patch(addSelectedSpell(state.editor.read(),spell,state.spellTarget,{member,classes,catalog:state.spellCatalog||[],
      grantedSpells:state.calculated?.origin_spells||[]}));
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
    const sheet=resolveVariant(stored.data);
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
    state.cachedCreatures=readableArchiveCreatures(await listCreatures());
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
  if(act==="close-chat-dice"){closeDialog(document.querySelector("#chat-dice-dialog"),{remove:true});return;}
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
// Reuse the normal feature-roll dialog (and all its eligible bonus sources)
// for damage prevention. A result rolled outside the app may be entered instead.
async function chooseZeroHpResponse(creature,calculated,damage){
 const choices=availableZeroHpResponses(creature,calculated,damage);
 if(!choices.length)return {id:'',roll:null};
 document.querySelector('#zero-hp-response-dialog')?.remove();
 const dialog=document.createElement('dialog');
 dialog.id='zero-hp-response-dialog';
 dialog.className='sheet-roll-dialog magic-spell-dialog';
 const hp=Number(creature.current_hp)||0,temp=Number(creature.temporary_hp)||0;
 dialog.innerHTML=actionDialogIntro('Danni fino a 0 PF',[
  {label:'Danni in arrivo',value:String(damage)},
  {label:'PF',value:String(hp)+' attuali · '+String(temp)+' temporanei'}
 ],'Puoi prevenire il danno o restare a 1 PF se un privilegio lo permette. La capacità è facoltativa.',
 '', 'zero-hp-close')+
 '<label>Capacità<select data-zero-hp-choice><option value="">Non usare capacità</option>'+
 choices.map(a=>'<option value="'+esc(a.id)+'">'+esc(a.name)+
  ' · '+esc(a.damage_response.effect==='reduce_damage'?'Riduci il danno':'Resta a 1 PF')+
  '</option>').join('')+'</select></label>'+
 '<div data-zero-hp-roll-row hidden>'+
  '<p class="hint" data-zero-hp-formula></p>'+
  '<label>Risultato del tiro (anche esterno)<input type="number" min="0" max="99999" step="1" data-zero-hp-result placeholder="Inserisci il risultato"></label>'+
  '<button type="button" class="btn" data-zero-hp-roll>Tira con i bonus applicabili</button></div>'+
 '<p class="hint" data-zero-hp-note>Il danno verrà applicato normalmente.</p>'+
 '<p role="status" data-zero-hp-error></p>'+
 '<div class="actions magic-dialog-actions"><button type="button" class="btn primary" data-zero-hp-apply>Applica danno</button>'+
 '<button type="button" class="btn" data-zero-hp-cancel>Annulla</button></div>';
 const picker=dialog.querySelector('[data-zero-hp-choice]');
 const resultInput=dialog.querySelector('[data-zero-hp-result]');
 const row=dialog.querySelector('[data-zero-hp-roll-row]');
 const note=dialog.querySelector('[data-zero-hp-note]');
 const selected=()=>choices.find(x=>x.id===picker.value);
 picker.addEventListener('change',()=>{
  const ability=selected();
  resultInput.value='';
  row.hidden=ability?.damage_response.effect!=='reduce_damage';
  dialog.querySelector('[data-zero-hp-formula]').textContent=ability?.roll_effect?
   'Riduzione: '+racialAbilityEffectFormula(ability,calculated):'';
  note.textContent=ability?ability.damage_response.effect==='retain_one_hp'?
   'Nessun tiro. Resti a 1 PF, se non sei stato ucciso sul colpo. Consuma un utilizzo.':
   'La riduzione è sottratta al danno prima dei PF. Consuma un utilizzo.':
   'Il danno verrà applicato normalmente.';
 });
 dialog.querySelector('[data-zero-hp-roll]').addEventListener('click',()=>{
  const ability=selected();if(!ability?.roll_effect)return;
  const formula=racialAbilityEffectFormula(ability,calculated);
  const roller=openFeatureRollDialog(creature,calculated,ability,formula);
  if(roller)roller.addEventListener('close',()=>{
   if(Number.isFinite(roller.rollOutcome?.total)){
    resultInput.value=String(Math.max(0,Math.trunc(roller.rollOutcome.total)));
    note.textContent='Risultato registrato; conferma per applicare la riduzione ai danni.';
   }
  },{once:true});
 });
 let choice=null;
 const answer=new Promise(resolve=>dialog.addEventListener('close',()=>{
  resolve(choice);dialog.remove();
 },{once:true}));
 dialog.querySelectorAll('[data-zero-hp-cancel],[data-act="zero-hp-close"]').forEach(button=>
  button.addEventListener('click',()=>closeDialog(dialog)));
 dialog.querySelector('[data-zero-hp-apply]').addEventListener('click',()=>{
  const ability=selected();
  const raw=resultInput.value.trim(),roll=Number(raw);
  if(ability?.damage_response.effect==='reduce_damage'&&
      (!raw||!Number.isSafeInteger(roll)||roll<0||roll>99999)){
   dialog.querySelector('[data-zero-hp-error]').textContent='Inserisci il totale del tiro di riduzione, anche se effettuato fuori dall’app.';
   return;
  }
  choice={id:ability?.id||'',roll:ability?.damage_response.effect==='reduce_damage'?roll:null};
  closeDialog(dialog);
 });
 document.body.append(dialog);openDialog(dialog);
 return answer;
}
function configureHpAdjustDialog(dialog){
  const creature=state.editor?.read()||{};
  dialog.querySelector('#hp-adjust-current').value=String(creature.current_hp??0);
  dialog.querySelector('#hp-adjust-temporary').value=String(creature.temporary_hp??0);
  dialog.querySelector('#hp-adjust-amount').value='';
}
function hpAdjustDraft(dialog,calculated){
  const max=Math.max(0,Number(calculated.stats?.max_hp)||0);
  const get=(selector,upper,label)=>{
    const raw=dialog.querySelector(selector)?.value.trim();
    const value=Number(raw);
    if(!raw||!Number.isSafeInteger(value)||value<0||value>upper)
      throw Error(label+': inserisci un numero intero tra 0 e '+upper+'.');
    return value;
  };
  return {
    current_hp:get('#hp-adjust-current',Math.max(max,Number(state.editor?.read()?.current_hp)||0),'PF attuali'),
    temporary_hp:get('#hp-adjust-temporary',99999,'PF temporanei')
  };
}
async function handleSubmit(form){
  if(form.id==='hp-adjust-form'){
    const dialog=form.closest('#hp-adjust-dialog');
    if(!dialog||!state.editor)throw Error('Apri prima una scheda.');
    await flushPendingFields();
    return;
  }
  if(form.id==="pair-form"){
    const token=document.querySelector("#pair-secret")?.value.trim()||"";
    const pairedSession=await pair(token,{remember:document.querySelector("#pair-remember")?.checked});
    acceptSession(pairedSession);
    serverBackups.schedule();
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
    rememberChatEvent(event);
    if(state.paired&&state.online){
      locallySentEventIds.add(event.id);
      const result=await action("chat_send",{event});
      if(!result.ok)throw new Error(result.error||"Messaggio conservato solo in locale");
      await fetchChat();
    }
    document.querySelector("#chat-message").value="";
  }
}

let inventoryPressTimer=null,inventoryPressStart=null,inventoryClickSuppression=null;
function clearInventoryPress(){
  if(inventoryPressTimer!==null)clearTimeout(inventoryPressTimer);
  inventoryPressTimer=null;inventoryPressStart=null;
}
function syncInventorySelectionUI(){
  const root=app.querySelector('#sheet-play-view[data-sheet="inventory"]');
  if(!root)return;
  const count=state.editor?.read()?.inventory?.length||0;
  for(const index of state.inventorySelectedIndices)
    if(index<0||index>=count)state.inventorySelectedIndices.delete(index);
  const selecting=state.inventorySelectedIndices.size>0;
  if(!selecting&&inventoryClickSuppression&&performance.now()>=inventoryClickSuppression.until)
    inventoryClickSuppression=null;
  root.classList.toggle('is-inventory-selecting',selecting);
  const rows=[...root.querySelectorAll('[data-inventory-item-index]')];
  const all=root.querySelector('[data-inventory-select-all]');
  let visibleCount=0,selectedVisible=0;
  for(const row of rows){
    const index=Number(row.dataset.inventoryItemIndex);
    const checked=state.inventorySelectedIndices.has(index);
    row.classList.toggle('is-selected',checked);
    row.querySelector('[data-inventory-select]').checked=checked;
    if(!row.closest('[hidden]')){
      visibleCount++;
      if(checked)selectedVisible++;
    }
  }
  if(all){
    all.checked=visibleCount>0&&selectedVisible===visibleCount;
    all.indeterminate=selectedVisible>0&&selectedVisible<visibleCount;
    all.disabled=!visibleCount;
  }
  const toolbar=root.querySelector('[data-inventory-bulk]');
  if(toolbar)toolbar.hidden=!selecting;
  const label=root.querySelector('[data-inventory-selection-count]');
  if(label)label.textContent=state.inventorySelectedIndices.size+' '+(state.inventorySelectedIndices.size===1?'selezionato':'selezionati');
}
function toggleInventoryHoldSelection(index){
  if(!state.editor||state.page!=='library'||state.libraryMode||state.sheet!=='inventory')return;
  if(!app.querySelector('#sheet-play-view [data-inventory-item-index="'+index+'"]'))return;
  if(state.inventorySelectedIndices.has(index))state.inventorySelectedIndices.delete(index);
  else state.inventorySelectedIndices.add(index);
  syncInventorySelectionUI();
}
function confirmInventoryDeletion(items){
  if(!items.length)return Promise.resolve(false);
  return new Promise(resolve=>{
    const dialog=document.createElement('dialog');
    dialog.id='inventory-delete-dialog';dialog.className='library-create-dialog library-delete-dialog';
    const n=items.length;
    dialog.innerHTML='<div class="library-create-body">'+
      '<h2>Eliminare '+n+' '+(n===1?'oggetto':'oggetti')+'?</h2>'+
      '<p>Gli oggetti selezionati saranno rimossi dalla scheda. L’operazione non può essere annullata.</p>'+
      '<ul class="library-delete-list">'+items.map(item=>
        '<li><strong>'+esc(item.name||'Oggetto')+'</strong><span>Quantità: '+Math.max(1,Number(item.quantity)||1)+'</span></li>').join('')+'</ul>'+
      '<div class="library-create-actions"><button type="button" class="btn" data-inventory-delete-cancel>Annulla</button>'+
      '<button type="button" class="btn danger" data-inventory-delete-confirm>Elimina</button></div></div>';
    let settled=false;
    const finish=value=>{
      if(settled)return;settled=true;resolve(value);closeDialog(dialog,{remove:true});
    };
    dialog.addEventListener('close',()=>finish(false),{once:true});
    dialog.querySelector('[data-inventory-delete-cancel]').addEventListener('click',event=>{
      event.stopPropagation();finish(false);
    });
    dialog.querySelector('[data-inventory-delete-confirm]').addEventListener('click',event=>{
      event.stopPropagation();finish(true);
    });
    document.body.append(dialog);openDialog(dialog);
    dialog.querySelector('[data-inventory-delete-cancel]').focus();
  });
}

let libraryPressTimer=null;
let libraryPressStart=null;
let libraryClickSuppression=null;
function clearLibraryPress(){
 if(libraryPressTimer!==null)clearTimeout(libraryPressTimer);
 libraryPressTimer=null;libraryPressStart=null;
}
function toggleLibraryHoldSelection(id){
 if(!id||state.page!=='library'||!state.libraryMode)return;
 const entry=[...app.querySelectorAll('.library-creature-entry')]
  .find(row=>row.dataset.libraryId===id&&!row.hidden);
 if(!entry)return;
 if(state.librarySelectedIds.has(id))state.librarySelectedIds.delete(id);
 else state.librarySelectedIds.add(id);
 syncLibrarySelectionUI();
}
function listen(){
  // Require a fresh pointer press on the X inside an already-open dialog.
  // This prevents a mobile release/click from being retargeted after opening.
  let armedBenefitRemovalTarget=null;
  document.addEventListener('pointerdown',e=>{
    armedBenefitRemovalTarget=e.target?.closest?.('#trait-benefits-dialog[open] [data-act="trait-benefits-remove-request"]')||null;
  },true);
  // The roster is an ordinary tap target until held for 520 ms. Cancel
  // on movement so vertical scrolling never unexpectedly selects a card.
  document.addEventListener('pointerdown',e=>{
    clearLibraryPress();
    const button=e.target?.closest?.('.library-index .creature-open');
    if(!button||e.button!==0||state.page!=='library'||!state.libraryMode)return;
    libraryPressStart={id:button.dataset.id,x:e.clientX,y:e.clientY,pointerId:e.pointerId};
    libraryPressTimer=setTimeout(()=>{
      const id=libraryPressStart?.id;
      if(!id)return;
      libraryClickSuppression={id,until:performance.now()+900};
      toggleLibraryHoldSelection(id);
      clearLibraryPress();
    },520);
  },{passive:true});
  document.addEventListener('pointermove',e=>{
    if(!libraryPressStart||e.pointerId!==libraryPressStart.pointerId)return;
    if(Math.hypot(e.clientX-libraryPressStart.x,e.clientY-libraryPressStart.y)>11)
      clearLibraryPress();
  },{passive:true});
  document.addEventListener('pointerup',clearLibraryPress,{passive:true});
  document.addEventListener('pointercancel',clearLibraryPress,{passive:true});
  document.addEventListener('scroll',clearLibraryPress,true);
  document.addEventListener('contextmenu',e=>{
    const button=e.target?.closest?.('.library-index .creature-open');
    if(!button)return;
    e.preventDefault();clearLibraryPress();
    if(libraryClickSuppression?.id===button.dataset.id&&performance.now()<libraryClickSuppression.until)return;
    libraryClickSuppression={id:button.dataset.id,until:performance.now()+900};
    toggleLibraryHoldSelection(button.dataset.id);
  });
  document.addEventListener('click',e=>{
    const button=e.target?.closest?.('.library-index .creature-open');
    if(!button||!libraryClickSuppression||button.dataset.id!==libraryClickSuppression.id)return;
    if(performance.now()<libraryClickSuppression.until){
      e.preventDefault();e.stopImmediatePropagation();
    }
    libraryClickSuppression=null;
  },true);


  // Match the creature roster: a 520 ms hold selects, a short tap opens details.
  document.addEventListener('pointerdown',e=>{
    clearInventoryPress();
    const button=e.target?.closest?.('#sheet-play-view[data-sheet="inventory"] .inventory-play-item');
    if(!button||e.button!==0)return;
    const row=button.closest('[data-inventory-item-index]');
    if(!row)return;
    const index=Number(row.dataset.inventoryItemIndex);
    inventoryPressStart={index,x:e.clientX,y:e.clientY,pointerId:e.pointerId};
    inventoryPressTimer=setTimeout(()=>{
      const current=inventoryPressStart;
      if(!current)return;
      inventoryClickSuppression={index:current.index,until:performance.now()+900};
      toggleInventoryHoldSelection(current.index);
      clearInventoryPress();
    },520);
  },{passive:true});
  document.addEventListener('pointermove',e=>{
    if(!inventoryPressStart||e.pointerId!==inventoryPressStart.pointerId)return;
    if(Math.hypot(e.clientX-inventoryPressStart.x,e.clientY-inventoryPressStart.y)>11)
      clearInventoryPress();
  },{passive:true});
  document.addEventListener('pointerup',clearInventoryPress,{passive:true});
  document.addEventListener('pointercancel',clearInventoryPress,{passive:true});
  document.addEventListener('scroll',clearInventoryPress,true);
  document.addEventListener('contextmenu',e=>{
    const button=e.target?.closest?.('#sheet-play-view[data-sheet="inventory"] .inventory-play-item');
    if(!button)return;
    e.preventDefault();clearInventoryPress();
    const index=Number(button.closest('[data-inventory-item-index]')?.dataset.inventoryItemIndex);
    if(!Number.isInteger(index))return;
    if(inventoryClickSuppression?.index===index&&performance.now()<inventoryClickSuppression.until)return;
    inventoryClickSuppression={index,until:performance.now()+900};
    toggleInventoryHoldSelection(index);
  });
  document.addEventListener('click',e=>{
    const button=e.target?.closest?.('#sheet-play-view[data-sheet="inventory"] .inventory-play-item');
    if(!button)return;
    const index=Number(button.closest('[data-inventory-item-index]')?.dataset.inventoryItemIndex);
    if(inventoryClickSuppression?.index===index&&performance.now()<inventoryClickSuppression.until){
      e.preventDefault();e.stopImmediatePropagation();inventoryClickSuppression=null;return;
    }
    if(state.inventorySelectedIndices.size){
      e.preventDefault();e.stopImmediatePropagation();
      toggleInventoryHoldSelection(index);
    }
  },true);

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
      const card=e.target.closest('#sheet-play-view .play-health[data-act="hp-adjust-open"],#sheet-play-view .play-character-portrait[data-sheet-context="identity"]');
      if(card&&!e.target.closest('button,input,select,textarea,a,[role="button"]:not(.play-health):not(.play-character-portrait)')){
        try{await flushPendingFields();await handleAction(card);}
        catch(error){message(errorMessage(error),true);}
      }
      return;
    }
    // Modal dismissal is UI-only. Do it before any asynchronous field flush:
    // a dirty input, slow IndexedDB transaction or rerender cannot block X.
    const closeAction=button.dataset.act;
    // Adding an identity is a local DOM operation. Focus must happen during the
    // click, before asynchronous form flushes can let the browser refocus +.
    if(closeAction==='identity-add'){
      const kind=String(button.dataset.identityKind||'');
      const group=button.closest('[data-identity-group]');
      if(['names','factions'].includes(kind)&&group?.dataset.identityGroup===kind){
        const list=group.querySelector('.identity-entry-list');
        if(list){
          const previous=list.querySelector('.identity-entry');
          const row=previous?previous.cloneNode(true):document.createElement('div');
          if(!previous){
            row.className='identity-entry';
            row.innerHTML='<input type="text" data-identity-value="factions" maxlength="160">'+
              '<label class="identity-check" title="Fazione attiva"><input type="checkbox" data-identity-active="factions" aria-label="Attiva questa fazione">'+
              '<span aria-hidden="true">✓</span></label>';
          }
          const input=row.querySelector('[data-identity-value]');
          input.value='';
          input.setAttribute('aria-label',kind==='names'?'Nuovo nome':'Nuova fazione');
          row.querySelector('[data-identity-active]').checked=false;
          list.append(row);
          input.focus();
        }
      }
      return;
    }
    // A mobile file picker must open synchronously from the user's click,
    // never after an awaited IndexedDB write or rerender.
    if(closeAction==='info-portrait-pick'){
      button.closest('#sheet-context-dialog')?.querySelector('[data-info-portrait-file]')?.click();
      return;
    }
    if(closeAction==='trait-benefits-close'){
      dismissTraitBenefitDialog();return;
    }
    if(closeAction==='roll-trait-cancel'){
      const dialog=document.querySelector('#roll-trait-picker');
      closeDialog(dialog,{remove:true});
      return;
    }
    if(closeAction==='sheet-senses-close'){
     closeDialog(document.querySelector('#sheet-senses-dialog'),{remove:true});return;
    }
    if(closeAction==='close-score-formula'){
      const dialog=document.querySelector('#sheet-score-formula-dialog');
      closeDialog(dialog,{remove:true});
      return;
    }
    if(closeAction==='constitution-hp-close'){
      closeDialog(document.querySelector('#constitution-hp-dialog'));
      return;
    }
    if(closeAction==='close-sheet-roll'){
      const dialog=document.querySelector('#sheet-roll-dialog');
      closeDialog(dialog,{remove:true});
      return;
    }
    if(closeAction==='action-cast-cancel'||closeAction==='magic-tool-close'){
      if(closeAction==='magic-tool-close')state.magicPopup='';
      const dialog=document.querySelector(closeAction==='action-cast-cancel'?
       '#action-cast-dialog':'#magic-tools-dialog');
      closeDialog(dialog,{remove:true});
      return;
    }
    if(button.disabled)return;
    if(closeAction==='trait-benefits-remove-request'){
      // Keyboard and assistive clicks have detail=0 and need no pointer.
      if(e.detail>0&&armedBenefitRemovalTarget!==button)return;
      armedBenefitRemovalTarget=null;
    }
    button.disabled=true;
    try {
      await flushPendingFields();
      // A concurrent refresh invalidates a pending removal request. Other
      // actions preserve their existing behavior across field autosaves.
      if(closeAction==='trait-benefits-remove-request'&&!button.isConnected)return;
      const isDestination=Boolean(button.dataset.nav)||button.dataset.act==='sheet';
      if(button.dataset.nav)await navigate(button.dataset.nav);
      else await handleAction(button);
      if(isDestination){window.scrollTo(0,0);app.focus({preventScroll:true});}
    }catch(error){message(errorMessage(error),true);}
    finally{if(button.isConnected&&!button.hasAttribute('data-roll-used'))button.disabled=false;}
  });
  document.addEventListener('keydown',e=>{
    if(e.key==='Enter'&&!e.isComposing&&!e.shiftKey&&
      e.target.matches?.('input:not([type="button"]):not([type="submit"]):not([type="checkbox"]):not([type="radio"]),textarea,[contenteditable="true"]')){
      e.preventDefault();e.stopPropagation();e.target.blur();
    }
  },true);
  document.addEventListener('keydown',e=>{
    const card=e.target.closest?.('#sheet-play-view .play-health[role="button"],#sheet-play-view .play-character-portrait[role="button"]');
    if(e.target!==card||!['Enter',' '].includes(e.key))return;
    e.preventDefault();card.click();
  });
  app.addEventListener("submit",async e=>{
    if(!(e.target instanceof HTMLFormElement))return;
    e.preventDefault();
    const button=e.target.querySelector('[type="submit"]');if(button)button.disabled=true;
    try{await handleSubmit(e.target);}catch(error){message(errorMessage(error),true);}
    finally{if(button&&button.isConnected)button.disabled=false;}
  });
  const editable = "[data-item-container],[data-coin-code],[data-slot-weapon-size],[data-requirement],[data-origin-config],[data-tracker-field],[data-origin-enabled],[data-auto-bonus],[data-native-pick],[data-casting-section],[data-slot-total],[data-pact-total],[data-document-index],[data-equip-slot],[data-reference],[data-native-list],[data-native-cr],[data-field],[data-ability],[data-slot],[data-item-index],[data-item-override],[data-condition],[data-token-condition]";
  app.addEventListener('focusout',e=>{
    const target=e.target;
    if(!target?.matches?.('[data-identity-value]'))return;
    if(target.value.trim())return;
    const group=target.closest('[data-identity-group]');
    const rows=group?.querySelectorAll('.identity-entry')||[];
    if(rows.length>1||group?.dataset.identityGroup==='factions'){
      target.closest('.identity-entry')?.remove();
      trackIdentityWrite(group.querySelector('[data-identity-value]')||target)
       .catch(error=>message(errorMessage(error),true));
    }else if(group?.dataset.identityGroup==='names'&&state.editor){
      target.value=state.editor.read().name;
    }
  },true);
  app.addEventListener("input",e=>{
    const target=e.target;
    if(target?.matches('[data-hp-autosave]')){
      clearTimeout(pendingFieldTimers.get(target));
      const editor=state.editor;
      pendingFieldTimers.set(target,setTimeout(()=>{
        pendingFieldTimers.delete(target);
        if(target.isConnected&&state.editor===editor)
          trackFieldWrite(target).catch(error=>message(errorMessage(error),true));
      },500));
      return;
    }
    if(target?.id==='library-bestiary-search'){
      state.libraryBestiaryLimit=36;paintLibraryBestiary();return;
    }
    if(target?.id==='library-miniature-search'){
      state.libraryMiniatureLimit=36;
      paintLibraryMiniatures();
      const area=app.querySelector('#library-create-dialog .library-miniature-choices');
      if(area)area.scrollTop=0;
      return;
    }
    if(target?.matches('[data-identity-value]')){
      clearTimeout(pendingFieldTimers.get(target));
      const editor=state.editor;
      pendingFieldTimers.set(target,setTimeout(()=>{
        pendingFieldTimers.delete(target);
        if(target.isConnected&&state.editor===editor)
          trackIdentityWrite(target).catch(error=>message(errorMessage(error),true));
      },400));
      return;
    }
    if(target?.matches('[data-play-search]')){
      state.sheetSearch.set(state.creatureId+'|'+state.sheet,target.value);
      if(state.sheet==='inventory'){
        state.inventorySearchLimit=75;
        paintInventorySearchResults();
        return;
      }
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
      state.spellQuery=target.value;state.spellResultLimit=60;
      const matches=document.querySelector("#spell-results");
      if(matches)matches.innerHTML=renderSpellResults();
      return;
    }
    if(target?.id==="catalog-search"){
      state.catalogQuery=target.value;state.catalogResultLimit=90;
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
        trackFieldWrite(target).catch(error=>message(errorMessage(error),true));
    },400));
  });
  app.addEventListener("change",e=>{
    const target=e.target;
    if(target?.matches?.('[data-identity-hide-others]')){
      const hidden=Boolean(target.checked);
      const group=target.closest('[data-identity-group="names"]');
      if(group)group.dataset.showAllNames=String(!hidden);
      // Reflect the switch immediately instead of waiting for the IndexedDB
      // transaction: otherwise the popup and the nameplate briefly disagree.
      if(state.editor)refreshIdentityPresentation({
        ...state.editor.read(),identity_hide_other_names:hidden
      });
      const write=patch({identity_hide_other_names:hidden}).then(()=>
        refreshIdentityPresentation(state.editor?.read()));
      pendingFieldWrites.add(write);
      void write.finally(()=>pendingFieldWrites.delete(write))
        .catch(error=>message(errorMessage(error),true));
      return;
    }
    if(target?.matches?.('[data-info-portrait-file]')){
      void saveInfoPortrait(target);
      return;
    }
    if(target?.matches?.('[data-identity-value],[data-identity-active]')){
      if(target.matches('[data-identity-active="names"]')&&target.checked){
        for(const other of target.closest('[data-identity-group]')?.querySelectorAll('[data-identity-active="names"]')||[])
          if(other!==target)other.checked=false;
      }else if(target.matches('[data-identity-active="names"]')&&!target.checked){
        target.checked=true;return;
      }
      trackIdentityWrite(target).catch(error=>message(errorMessage(error),true));
      return;
    }
    if(target?.matches?.('[data-inventory-select-all]')){
      for(const row of app.querySelectorAll('#sheet-play-view [data-inventory-item-index]')){
        if(row.closest('[hidden]'))continue;
        const index=Number(row.dataset.inventoryItemIndex);
        if(target.checked)state.inventorySelectedIndices.add(index);
        else state.inventorySelectedIndices.delete(index);
      }
      syncInventorySelectionUI();return;
    }
    if(target?.matches?.('[data-inventory-select]')){
      const index=Number(target.dataset.inventorySelect);
      if(target.checked)state.inventorySelectedIndices.add(index);
      else state.inventorySelectedIndices.delete(index);
      syncInventorySelectionUI();return;
    }
    if(target?.matches?.('[data-library-select-all]')){
      for(const box of app.querySelectorAll('input[data-library-select]')){
        if(box.closest('.library-creature-entry')?.hidden)continue;
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
      state.spellTarget='prepared_spells';
      render().catch(error=>message(errorMessage(error),true));return;
    }
    if(target?.id==='spell-learn-filter'){
      state.spellLearnFilter=target.value||'all';
      const results=app.querySelector('#magic-tools-dialog #spell-results');
      if(results)results.innerHTML=renderSpellResults();
      return;
    }
    if(target?.id==="native-details"){
      if(!DETAILS.some(([key])=>key===target.value))return;
      flushPendingFields().then(()=>{state.detail=target.value;return render();})
        .catch(error=>message(errorMessage(error),true));return;
    }
    if(target?.id==='catalog-creature'){
      state.catalogAssignCreatureId=target.value;state.catalogSelected=-1;state.catalogResultLimit=90;
      render().catch(error=>message(errorMessage(error),true));return;
    }
    if(target?.id==="catalog-category"){
      state.catalogCategory=target.value;state.catalogSelected=-1;state.catalogResultLimit=90;
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
    trackFieldWrite(e.target).catch(error=>message(errorMessage(error),true));
  });
  creatureInput.addEventListener("change",async()=>{
    const file=creatureInput.files?.[0];if(!file)return;
    try{
      const result=await importCreatureFile(file);
      const imported=Array.isArray(result)?result:[result];
      state.page="library";state.creatureId=imported.length===1?imported[0].creature.id:null;
      state.libraryMode=imported.length!==1;state.editor=null;state.sheet="info";
      state.librarySelectedIds.clear();
      await refreshCharacterHomebrewOptions();
      await render();
      message(imported.length===1 ? "Scheda importata e salvata offline." :
        "Importate "+imported.length+" creature e relativi contenuti homebrew.");
    }
    catch(error){message(errorMessage(error),true);}finally{creatureInput.value="";}
  });
  backupInput.addEventListener("change",async()=>{
    const file=backupInput.files?.[0];if(!file)return;
    try{await importBackup(file);await refreshCharacterHomebrewOptions();await render();message("Backup ripristinato senza sovrascrivere le schede esistenti.");}
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
    serverBackups.schedule(true);
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
  async exportArchive(){await flushPendingFields();return exportCreatureArchive();},
  async open(id){await flushPendingFields();state.creatureId=id;state.libraryMode=false;state.sheet="info";state.editor=null;await refreshCharacterHomebrewOptions();await render();}
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
  try{
    const saved=await setting(LOCAL_CHAT_KEY);
    state.localMessages=Array.isArray(saved)?saved.filter(event=>
      event&&typeof event.id==='string'&&['chat','roll','action'].includes(event.kind)).slice(-250):[];
  }catch(error){console.warn('Cronologia chat locale non disponibile',error);}
  await render();
  if(typeof globalThis.vttDesktopSaveFile!=='function')
    void serverBackups.start();
  void loadBundledConditionCatalog();
  // Idle-only background prefetch: never gate the library, sheet or pairing.
  // The service worker also caches the complete catalog for later offline use.
  setTimeout(()=>{
    const preload=()=>loadFullSpellCatalog().catch(error=>
      console.warn('VTT optional spell prefetch unavailable',error));
    if(typeof window.requestIdleCallback==='function')
      window.requestIdleCallback(preload,{timeout:12000});
    else setTimeout(preload,1200);
  },2400);
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
