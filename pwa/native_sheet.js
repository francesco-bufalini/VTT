import {hitDicePools,minimumXpForCreature,experienceFloorPatch} from './character_core.js';
// Native-style sheet sections and mutations of the portable native schema.
// Math is owned by sheet_rules.js; this module never calls the desktop.
import {formulaReadout} from './sheet_rules_view.js';
import {formulaValue} from './sheet_rules.js';
import {contentForRules} from './source_edition.js';
import {featOriginLabel,featTraitOriginKey} from './feat_picker.js';
import {itemKind,resolveOwnedItem,armorDexterityBonus,armorDexterityLimit} from './item_controls.js';
import {classFeatureActive,metamagicPlan} from './feature_mechanics.js';
import {powerRestSelections,powerRestChoicePatch} from './trait_state_rules.js';
import {endTemporaryConditionPatch} from './species_powers.js';
import {clearStoredSpellPatch,storedSpellExtension,storedSpellTrackerId} from './spell_storing_item.js';
import {clearSpellImprintsPatch} from './spell_imprints.js';
export const SHEET_SECTIONS = [["info","Info"],
 ["battle","Azioni"],["magic","Magia"],["inventory","Inventario"],
 ["conditions","Condizioni"]];
export const ALIGNMENTS = [["Legale buono","Legale buono"],["Neutrale buono","Neutrale buono"],["Caotico buono","Caotico buono"],["Legale neutrale","Legale neutrale"],["Completamente neutrale","Completamente neutrale"],["Caotico neutrale","Caotico neutrale"],["Legale malvagio","Legale malvagio"],["Neutrale malvagio","Neutrale malvagio"],["Caotico malvagio","Caotico malvagio"]];
// Mirrors CreatureArea._confirm_miniature for the portable fields only.
export function miniaturePatch(creature,profile,kind){
 const id=String(profile?.id||'');
 if(!id||!['base','current'].includes(kind))throw Error('Miniatura non valida');
 if(kind==='current')return {current_miniature_id:id};
 const previousBase=String(creature.default_miniature_id||'');
 const previousCurrent=String(creature.current_miniature_id||'');
 const patch={default_miniature_id:id};
 if(!previousCurrent||previousCurrent===previousBase)patch.current_miniature_id=id;
 patch.size_name=String(profile.size_name||'Medium');
 patch.footprint=Math.max(0.5,Number(profile.footprint)||1);
 return patch;
}
export const DETAILS = [["overview","Panoramica"],["proficiency_choices","Competenze"],
 ["feats_catalog","Talenti"],["formula_bonuses","Bonus"],["resources","Tracker"],
 ["damage_defense_entries","Resistenze, immunità e vulnerabilità"],["origin_spell_grants","Incantesimi da origini"]];
export const SKILLS = [["acrobatics","Acrobazia","dex"],["animal handling","Addestrare Animali","wis"],["arcana","Arcano","int"],["athletics","Atletica","str"],["deception","Inganno","cha"],["history","Storia","int"],["insight","Intuizione","wis"],["intimidation","Intimidire","cha"],["investigation","Indagare","int"],["medicine","Medicina","wis"],["nature","Natura","int"],["perception","Percezione","wis"],["performance","Intrattenere","cha"],["persuasion","Persuasione","cha"],["religion","Religione","int"],["sleight of hand","Rapidità di Mano","dex"],["stealth","Furtività","dex"],["survival","Sopravvivenza","wis"]];
export const BONUS_TARGETS=[['ability_check','Tutte le prove di caratteristica (incl. iniziativa)'],['saving_throw','Tutti i tiri salvezza'],['ac','CA'],['initiative','Iniziativa'],['hp','PF massimi'],['attunement_max','Sintonie massime'],['speed','Camminata'],['proficiency','Competenza'],['passive_perception','Percezione passiva'],['passive_skill:investigation','Indagare passivo'],['pact_slot','Slot del Patto'],['spell_dc','CD incantesimi'],['spell_attack','Attacco incantesimi'],
 ...['str','dex','con','int','wis','cha'].flatMap(a=>[['ability:'+a,'Punteggio '+a.toUpperCase()],['ability_mod:'+a,'Modificatore '+a.toUpperCase()],['save:'+a,'TS '+a.toUpperCase()]]),
 ...SKILLS.map(([id,label])=>['skill:'+id,label]),...['climb','swim','fly','burrow'].map((id,i)=>['speed:'+id,['Scalata','Nuoto','Volo','Scavo'][i]]),
 ...Array.from({length:9},(_,i)=>['slot:'+(i+1),'Slot livello '+(i+1)])];
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const list=v=>Array.isArray(v)?v:[];
export const ROW_FIELDS = {
 classes:[["name","Classe"],["source","Fonte"],["subclass","Sottoclasse"],["subclass_source","Fonte sottoclasse"],["level","Livello","number",1,20]],
 proficiency_choices:[["kind","Tipo",[["skill","Abilità"],["expertise","Maestria"],["save","Tiro salvezza"],["weapon","Arma"],["armor","Armatura"],["tool","Strumento"],["language","Linguaggio"]]],["key","Competenza"],["origin_name","Origine"],["disabled","Disattivata","checkbox"]],
 backgrounds_catalog:[["name","Background"],["source","Fonte"],["disabled","Disattivato","checkbox"]],
  feats_catalog:[["name","Talento"],["source","Fonte"],["level","Livello del privilegio","number",1,20],["ability_choice","Caratteristica scelta",[['','Nessuna'],...['str','dex','con','int','wis','cha'].map(a=>[a,a.toUpperCase()])]],["origin_name","Origine"],["disabled","Disattivato","checkbox"]],
 formula_bonuses:[["target","Valore"], ["expression","Formula"],["origin_id","Origine"],["disabled","Disattivato","checkbox"]],
 dice_bonuses:[["target","Tiro",[['ability_check','Prove di caratteristica'],['saving_throw','Tiri salvezza'],['attack_roll','Tiri per colpire'],['damage_roll','Tiri di danno'],['initiative','Iniziativa'],['any_d20','Qualunque d20']]],["dice","Dadi (es. 1d4)"],["origin_id","Origine"],["disabled","Disattivato","checkbox"]],
 damage_defense_entries:[["key","Danno o condizione"],["rank","Difesa",[[-1,"Vulnerabilità"],[1,"Resistenza"],[2,"Immunità danno"],[3,"Immunità condizione"]]],["disabled","Disattivata","checkbox"]],
 origin_spell_grants:[["origin_id","Origine"],["origin_name","Nome origine"],["spell_id","Incantesimo"],["payment_mode","Consumo",[['free','Gratuito'],['slot','Slot incantesimo'],['tracker','Tracker']]],["tracker_id","Tracker"],["tracker_cost","Costo","number",1,999],["spellcasting_ability","Caratteristica",[["","Automatica"],["str","Forza"],["dex","Destrezza"],["con","Costituzione"],["int","Intelligenza"],["wis","Saggezza"],["cha","Carisma"]]],["disabled","Disattivata","checkbox"]]
};
export function benefitRequirements(row,attrs){
 const gate=row.requirements||{};
 return '<details><summary>Requisiti di livello</summary><div class="columns">'+
 control('Livello di riferimento',attrs+' data-requirement="scope"',gate.scope||'character',[['character','Personaggio'],['class','Classe']])+
 control('Livello minimo',attrs+' data-requirement="min_level"',gate.min_level??row.min_level??0,'number',0,20)+
 control('Livello massimo (vuoto: nessuno)',attrs+' data-requirement="max_level"',gate.max_level??'','number',0,20)+
 control('Nome classe',attrs+' data-requirement="class_name"',gate.class_name||'')+
 control('Fonte classe',attrs+' data-requirement="class_source"',gate.class_source||'')+'</div></details>';
}
export function requirementPatch(row,field,value){
 if(!['scope','min_level','max_level','class_name','class_source'].includes(field))throw Error('Requisito non valido');
 const gate={scope:'character',min_level:row.min_level??0,...row.requirements};
 if(field==='scope'&&!['character','class'].includes(value))throw Error('Ambito non valido');
 if(['min_level','max_level'].includes(field)){
  if(field==='max_level'&&value===''){delete gate.max_level;return gate;}
  value=Number(value);if(!Number.isInteger(value)||value<0||value>20)throw Error('Livello da 0 a 20');
 }
 gate[field]=value;
 if(gate.max_level!==undefined&&gate.max_level<gate.min_level)throw Error('Il massimo non può essere inferiore al minimo');
 return gate;
}
export function rowsFor(c,key){
 if(key==='classes'&&!list(c.classes).length&&c.class)return [{name:c.class,source:c.class_source||'',id:c.class_id||'',subclass:c.subclass||'',subclass_source:c.subclass_source||'',subclass_id:c.subclass_id||'',level:c.level||1}];
 if(key!=="proficiency_choices" || Array.isArray(c.proficiency_choices))return structuredClone(list(c[key]));
 return [['skill','skill_proficiencies'],['expertise','skill_expertise'],['save','saving_throw_proficiencies']].flatMap(([kind,field])=>list(c[field]).map(key=>({kind,key,origin_id:'',origin_name:'',disabled:false})));
}
// Same mutation contract as CreatureSheetController.change_hit_points().
export function hitPointPatch(c,delta,calculated){
 if(!Number.isInteger(delta)||Math.abs(delta)>99999)throw Error('Quantità PF non valida');
 if(delta>=0)return {current_hp:Math.min(Math.max(0,calculated.stats.max_hp),Number(c.current_hp||0)+delta)};
 let remaining=-delta;
 const absorb=value=>{const hp=Math.max(0,Number(value)||0),used=Math.min(hp,remaining);remaining-=used;return hp-used;};
 const temporary_hp=absorb(c.temporary_hp);
 return {temporary_hp,current_hp:absorb(c.current_hp)};
}
export function slotUsePatch(c,level,delta,calculated){
 if(!Number.isInteger(level)||level<0||level>9||!Number.isInteger(delta))throw Error('Slot non valido');
 const total=level===0?calculated.pact_slots.total:calculated.spell_slots[level-1].total;
 const spent=level===0?Number(c.pact_slots_spent||0):Number(c.spell_slots_spent?.[level]||0);
 const next=Math.max(0,Math.min(total,spent+delta));
 if(delta>0&&spent>=total)throw Error('Nessuno slot disponibile');
 if(level===0)return {pact_slots_spent:next};
 const rows=Array.from({length:10},(_,i)=>Number(c.spell_slots_spent?.[i]||0));rows[level]=next;
 return {spell_slots_spent:rows};
}
export function spellCastPlan(c,selection,requestedLevel,calculated,payment='auto'){
 if(!selection?.id||!Number.isInteger(requestedLevel)||requestedLevel<0||requestedLevel>9||!['auto','slot','pact'].includes(payment))throw Error('Lancio non valido');
 if(selection.action_kind!=='ability'&&classFeatureActive(c,calculated,'rage'))throw Error('Non puoi lanciare incantesimi mentre sei in Ira.');
 const level=Number(selection.level);if(!Number.isInteger(level)||level<0||level>9)throw Error('Livello incantesimo non disponibile nel catalogo locale');
 const grant=selection.grant_id?calculated.origin_spells.find(g=>g.id===selection.grant_id&&g.spell_id===selection.id):null;
 if(selection.grant_id&&!grant)throw Error('Concessione non più disponibile');
 if(grant?.casting_ability_unresolved)throw Error('Completa prima la caratteristica da incantatore concessa dal talento.');
 if(grant?.requires_context&&!selection.context_confirmed)throw Error('Conferma prima le condizioni richieste dal privilegio.');
 if(grant?.ritual_only){
  if(payment!=='auto'||requestedLevel!==0&&requestedLevel!==level)throw Error('Questa concessione permette soltanto un rituale, senza slot o potenziamento.');
  if(!selection.ritual_completed)throw Error('Conferma il completamento del rituale prima di risolvere l’incantesimo.');
 }
 if(!grant&&![...list(c.prepared_spells),...list(c.spells)].some(s=>(typeof s==='string'?s:s.id)===selection.id))throw Error('Incantesimo non disponibile nella scheda');
 // Cantrips are intrinsically slot-free. The only chargeable exception
 // is an explicitly linked limited-use tracker in structured source data.
 const cantrip=level===0;
 if(cantrip&&['slot','pact'].includes(payment))throw Error('Un trucchetto non usa slot.');
 const grantedMode=cantrip&&grant?.payment_mode!=='tracker'?'free':grant?.payment_mode||'free';
 // A source may grant a limited-use casting AND permit ordinary/Pact slots.
 // Explicit slot payments must never silently consume the daily tracker.
 if(grant&&payment!=='auto'&&!grant.slot_alternative&&
   !(grantedMode==='slot'&&['slot','pact'].includes(payment)))
   throw Error('Questa concessione non permette il lancio con slot.');
 const mode=grant?(grant.slot_alternative&&payment!=='auto'?payment:
   grantedMode==='slot'&&payment==='pact'?'pact':grantedMode):
   level===0?'free':payment==='pact'||payment==='auto'&&selection.pact?'pact':'slot';
 let patch={},slotLevel=0;
 if(mode==='tracker'){
  const tracker=calculated.trackers.find(t=>t.id===grant.tracker_id),cost=Math.max(1,Number(grant.tracker_cost)||1),spent=Math.max(Number(c.resource_tracker_spent?.[grant.tracker_id]||0),Number(tracker?.spent)||0);
  if(!tracker||spent+cost>tracker.max)throw Error('Risorsa insufficiente per questo incantesimo');
  patch={resource_tracker_spent:{...c.resource_tracker_spent,[tracker.id]:spent+cost}};slotLevel=level;
 }else if(mode==='slot'||mode==='pact'){
  slotLevel=mode==='pact'?calculated.pact_slots.level:requestedLevel||level;
  if(slotLevel<level||slotLevel<1)throw Error('Scegli uno slot almeno del livello dell’incantesimo');
  patch=slotUsePatch(c,mode==='pact'?0:slotLevel,1,calculated);
 }else slotLevel=level;
 if(grant?.active_key){
  if(c.active_class_features?.[grant.active_key])
   throw Error('La manifestazione celestiale è già attiva: terminala prima di attivarla di nuovo.');
  patch.active_class_features={...(c.active_class_features||{}),
    [grant.active_key]:{name:grant.origin_name||selection.name,
      spell_id:grant.spell_id,origin_id:grant.origin_id,
      duration_rounds:grant.duration_rounds||10,remaining_rounds:grant.duration_rounds||10}};
 }
 const ability=selection.caster_ability||c.spellcasting_ability||'int';
 const hit=calculated.values['casting_hit:'+ability],dc=calculated.values['casting_dc:'+ability];
 if(!Number.isFinite(hit)||!Number.isFinite(dc))throw Error('Caratteristica di lancio non disponibile');
 const innate=classFeatureActive(c,calculated,'innate_sorcery')&&
  String(selection.source_class||selection.casting_class||'').toLowerCase().split('|').includes('sorcerer');
 const meta=metamagicPlan({...c,...patch},selection,slotLevel,calculated);
 if(meta.cost){
  const spent={...(patch.resource_tracker_spent||c.resource_tracker_spent||{})};
  spent[meta.tracker.id]=Number(spent[meta.tracker.id]||0)+meta.cost;patch.resource_tracker_spent=spent;
 }
 // A spell that forces a saving throw ends Hide/Hidden Step invisibility
 // once it has been cast successfully. This does not affect its normal
 // spell payment, concentration or targeting resolution.
 const saves=selection.saving_throw??selection.savingThrow??selection.saves??[];
 if(Array.isArray(saves)&&saves.length||typeof saves==='string'&&saves.trim()){
   const current={...c,active_class_features:patch.active_class_features||c.active_class_features};
   Object.assign(patch,endTemporaryConditionPatch(current));
 }
 return {patch,slotLevel,context:{caster_name:c.name||'',spellcasting_ability:ability,spell_attack_bonus:hit,
  ...(selection.item_target?{item_target:structuredClone(selection.item_target)}:{}),
  spell_save_dc:dc+(innate?1:0),...(innate?{spell_attack_advantage:true}:{}),
  ...(meta.selection.names?.length?{metamagic:meta.selection,rules_version:c.rules_version||'2014'}:{}),source_level:c.level||1},spell:meta.spell};
}
export function recoveryPatch(c,event,trackers,calculated={}){
 if(!['short_rest','long_rest','turn'].includes(event))throw Error('Recupero non valido');
 const spent={...(c.resource_tracker_spent||{})};
 const ready={...(c.resource_recovery_ready||{})};
 const used={...(c.resource_recovery_used||{})};
 for(const row of trackers){
  if(row.disabled)continue;
  if(row.recharge===event||event==='long_rest'&&row.recharge==='short_rest'){
   delete spent[row.id];for(const id of row.legacy_ids||[])delete spent[id];
  }
  if(event!=='short_rest')continue;
  for(const rule of row.partial_recoveries||[]){
   if(rule.event!=='short_rest')continue;
   if(rule.mode==='optional_partial'){
    if(!used[rule.id])ready[rule.id]=true;
   }else if(rule.mode==='partial'){
    spent[row.id]=Math.max(0,Number(spent[row.id]||0)-Math.max(0,Number(rule.amount)||0));
    if(!spent[row.id])delete spent[row.id];
   }
  }
 }
 if(event==='long_rest'){for(const id of Object.keys(ready))delete ready[id];for(const id of Object.keys(used))delete used[id];}
 const patch={resource_tracker_spent:spent,resource_recovery_ready:ready,resource_recovery_used:used};
 if(event==='short_rest'||event==='long_rest')patch.active_class_features=c.active_class_features?.wild_shape?
  {wild_shape:structuredClone(c.active_class_features.wild_shape)}:{};
 if(event==='long_rest'){
  patch.created_spell_slots=[];
  // Spell-Storing Item ends at the next long rest. Keep the other
  // resources' already-recovered spent counters from this recovery pass.
  const expired=clearStoredSpellPatch(c);
  if(Object.keys(expired).length){
   patch.effect_extensions=expired.effect_extensions;
   patch.resource_trackers=expired.resource_trackers;
   delete spent[storedSpellTrackerId(c)];
  }
  const imprintClear=clearSpellImprintsPatch({
   ...c,effect_extensions:patch.effect_extensions||c.effect_extensions,
   resource_trackers:patch.resource_trackers||c.resource_trackers
  });
  patch.effect_extensions=imprintClear.effect_extensions;
  patch.resource_trackers=imprintClear.resource_trackers;
  patch.spell_imprint_prepared={};
  for(const id of Object.keys(spent)){
   if(id.startsWith('spell-imprint:'))delete spent[id];
  }
 }
 // Pact Magic and class spell slots retain their original explicit rest rules.
 if(event==='short_rest'||event==='long_rest')patch.pact_slots_spent=0;
 if(event==='long_rest')patch.spell_slots_spent=Array(10).fill(0);
 Object.assign(patch,powerRestChoicePatch(c,event,calculated));
 // The user's next turn ends short-lived racial invisibility. A rest also
 // clears its sheet condition without touching pre-existing invisibility.
 const temporary=endTemporaryConditionPatch(c);
 if(Object.keys(temporary).length){
   if(temporary.conditions)patch.conditions=temporary.conditions;
   if(event==='turn')patch.active_class_features=temporary.active_class_features;
 }
 return patch;
}

/**
 * A finished rest is a single atomic creature patch, including native feature
 * recovery, slot usage and the 2014/2024 HP/Hit Die rules. Rest duration and
 * interruptions are decided at the table rather than guessed from wall time.
 */
export function completeRest(record,event,calculated={},spend={},rollDie=sides=>1+Math.floor(Math.random()*sides)){
 if(!['short_rest','long_rest'].includes(event))throw Error('Tipo di riposo non valido');
 if(Number(record.current_hp||0)<1)throw Error('Serve almeno 1 PF per iniziare un riposo.');
 const pools=hitDicePools(record,calculated),version=String(record.rules_version||'2014');
 const patch=recoveryPatch(record,event,calculated.trackers||[],calculated);
 const totalHp=Math.max(0,Number(calculated.stats?.max_hp??record.max_hp??0));
 let healed=0;
 const rolls=[];
 const spent={};
 for(const pool of pools)if(pool.spent)spent['d'+pool.die]=pool.spent;
 if(event==='short_rest'){
  const selections=new Map(pools.map(p=>['d'+p.die,p]));
  for(const [key,raw] of Object.entries(spend||{})){
   const count=Number(raw),pool=selections.get(key);
   if(!pool||!Number.isInteger(count)||count<0||count>pool.available)
    throw Error('Dadi Vita insufficienti o non validi: '+key);
   if(!count)continue;
   spent[key]=(spent[key]||0)+count;
   for(let i=0;i<count;i++){
    const rolled=rollDie(pool.die);
    if(!Number.isInteger(rolled)||rolled<1||rolled>pool.die)throw Error('Risultato del Dado Vita non valido');
    const con=Number(calculated.abilities?.con?.modifier??calculated.values?.['ability_mod:con']??Math.floor((Number(record.abilities?.con||10)-10)/2));
    const gained=Math.max(version==='2024'?1:0,rolled+(Number.isFinite(con)?con:0));
    healed+=gained;
    rolls.push({die:pool.die,roll:rolled,modifier:con,healed:gained});
   }
  }
  patch.current_hp=Math.min(totalHp,Math.max(0,Number(record.current_hp)||0)+healed);
 }else{
  patch.current_hp=totalHp;
  patch.temporary_hp=0; // Temporary HP expire after a long rest.
  patch.death_save_successes=0;
  patch.death_save_failures=0;
  patch.exhaustion=Math.max(0,Math.trunc(Number(record.exhaustion||0))-1);
  // 2014: half the total Hit Dice (minimum one); 2024: all Hit Dice.
  let recover=version==='2024'?Infinity:Math.max(1,Math.floor(pools.reduce((sum,p)=>sum+p.total,0)/2));
  for(const pool of pools){
   const restored=Math.min(pool.spent,recover);
   recover-=restored;
   const leftover=pool.spent-restored;
   if(leftover)spent['d'+pool.die]=leftover;
   else delete spent['d'+pool.die];
  }
 }
 patch.hit_dice_spent=spent;
 return {patch,healed:Math.max(0,patch.current_hp-Math.max(0,Number(record.current_hp)||0)),rolls};
}


/**
 * Full, non-mutating rest forecast. Keep eligible recoveries visible even at
 * full capacity so the confirmation dialog describes everything the rest can
 * restore, instead of only currently spent resources.
 */
export function restRecoveryPreview(record,event,calculated={},spend={}){
 const minimum=completeRest(record,event,calculated,spend,()=>1);
 const maximum=completeRest(record,event,calculated,spend,sides=>sides);
 const entries=[];
 const add=(group,name,detail)=>entries.push({group,name,detail});
 const maxHp=Math.max(0,Number(calculated.stats?.max_hp??record.max_hp??0));
 const currentHp=Math.max(0,Number(record.current_hp)||0);
 const healing=event==='short_rest'?
  (minimum.healed===maximum.healed?String(minimum.healed):minimum.healed+'–'+maximum.healed):
  String(minimum.healed);
 add('Salute','Punti ferita',currentHp+' / '+maxHp+' PF · recupero '+healing+' PF');
 if(event==='long_rest'&&storedSpellExtension(record))
  add('Privilegi','Spell-Storing Item','L’incantesimo immagazzinato viene rimosso; puoi scegliere nuovamente oggetto e incantesimo');
 const pools=hitDicePools(record,calculated);
 for(const pool of pools){
  const chosen=event==='short_rest'?Number(spend?.['d'+pool.die]||0):0;
  const after=Math.max(0,Number(minimum.patch.hit_dice_spent?.['d'+pool.die]||0));
  add('Dadi Vita','d'+pool.die,
    pool.available+' / '+pool.total+' disponibili · '+
    (event==='short_rest'?chosen+' da spendere':(pool.spent-after)+' recuperati'));
 }
 for(const row of calculated.trackers||[]){
  if(row.disabled)continue;
  const full=row.recharge===event||event==='long_rest'&&row.recharge==='short_rest';
  const rules=event==='short_rest'?(row.partial_recoveries||[]).filter(rule=>rule.event==='short_rest'):[];
  if(!full&&!rules.length)continue;
  const max=Math.max(0,Number(row.max)||0);
  const before=Math.max(0,Math.min(max,Number(record.resource_tracker_spent?.[row.id]||0)));
  const after=Math.max(0,Math.min(max,Number(minimum.patch.resource_tracker_spent?.[row.id]||0)));
  const optional=rules.filter(rule=>rule.mode==='optional_partial'&&
    minimum.patch.resource_recovery_ready?.[rule.id]&&!record.resource_recovery_used?.[rule.id]).length;
  add('Risorse',row.name||row.id,
    (max-before)+' / '+max+' disponibili · '+Math.max(0,before-after)+' utilizzi recuperati'+
    (optional?' · '+optional+' recuperi opzionali pronti':''));
 }
 // Reselection rights are independent of resource recovery counts.
 for(const choice of powerRestSelections(record,calculated)){
  if(choice.recovery===event||event==='long_rest'&&choice.recovery==='short_rest')
   add('Scelte modificabili',choice.name,choice.label+' · puoi cambiare le opzioni dopo questo riposo');
 }
 const pact=Math.max(0,Number(calculated.pact_slots?.total)||0);
 if(pact){
  const spent=Math.max(0,Math.min(pact,Number(record.pact_slots_spent||0)));
  add('Magia','Slot del Patto (livello '+(calculated.pact_slots?.level||1)+')',
    (pact-spent)+' / '+pact+' disponibili · '+spent+' recuperati');
 }
 if(event==='long_rest'){
  for(const slot of calculated.spell_slots||[]){
   const max=Math.max(0,Number(slot.total)||0);
   if(!max)continue;
   const spent=Math.max(0,Math.min(max,Number(record.spell_slots_spent?.[slot.level]||0)));
   add('Magia','Slot incantesimo livello '+slot.level,
     (max-spent)+' / '+max+' disponibili · '+spent+' recuperati');
  }
  const exhausted=Math.max(0,Number(record.exhaustion)||0);
  add('Altri effetti','Indebolimento',
    exhausted+' livelli attuali · '+Math.min(1,exhausted)+' rimossi');
  add('Altri effetti','Punti ferita temporanei',
    (Math.max(0,Number(record.temporary_hp)||0))+' attuali · azzerati');
  const death=Number(record.death_save_successes||0)+Number(record.death_save_failures||0);
  add('Altri effetti','Tiri salvezza contro la morte',
    death+' segnati · azzerati');
 }
 return {minimum,maximum,entries,pools};
}

function control(label,attrs,value,type='text',min,max){
 if(Array.isArray(type)){
  const options=type.some(([v])=>String(v)===String(value??''))?type:[[value??'',value||'Non selezionato'],...type];
  return '<label>'+esc(label)+'<select '+attrs+'>'+options.map(([v,t])=>'<option value="'+esc(v)+'" '+(String(v)===String(value??'')?'selected':'')+'>'+esc(t)+'</option>').join('')+'</select></label>';
 }
 if(type==='checkbox')return '<label class="check"><input type="checkbox" '+attrs+' '+(value?'checked':'')+'>'+esc(label)+'</label>';
 return '<label>'+esc(label)+'<input type="'+type+'" '+attrs+' value="'+esc(value)+'" '+(min!==undefined?'min="'+min+'" max="'+max+'"':'')+'></label>';
}
export function nativeRows(c,key,catalogs={},startIndex=0){
 const rows=rowsFor(c,key);
 return rows.slice(startIndex).map((row,offset)=>{
  const i=offset+startIndex;
  if(!row||typeof row!=='object')return '<p class="hint">'+esc(row)+'</p>';
  const automatic=!!row.automatic;
  if(key==='formula_bonuses'&&(automatic||String(row.id||'').startsWith('auto|')))return '';
  return '<article class="native-entry"><div class="row between"><strong>'+esc(row.name||row.origin_name||row.key||'Voce '+(i+1))+'</strong>'+
   (!automatic?'<button class="btn small danger" data-act="native-remove" data-list="'+key+'" data-index="'+i+'">Rimuovi</button>':'<span class="tag">Da origine</span>')+'</div><div class="columns">'+ROW_FIELDS[key].map(([field,label,type,min,max])=>{
    const category=key==='classes'?(field==='name'?'classes':field==='subclass'?'subclasses':''):key==='feats_catalog'&&field==='name'?'feats':key==='backgrounds_catalog'&&field==='name'?'backgrounds':'';
    const candidates=contentForRules(list(catalogs[category]),c.rules_version).filter(ref=>key!=='classes'||field==='name'||ref.class_name===row.name&&(!row.source||ref.class_source===row.source));
    if(key==='backgrounds_catalog'&&field==='name'){
      return '<label>Background'+
        '<button type="button" class="background-reference-button" data-act="background-picker-open" data-background-index="'+i+'"'+
        ' aria-label="Cerca un background aggiuntivo"><span class="background-reference-value">'+esc(row.name||'Scegli un background')+'</span>'+
        '<span class="background-reference-search" aria-hidden="true">⌕</span></button></label>';
    }
    if(category&&candidates.length){
      const chosen=candidates.find(ref=>ref.name===row[field]&&(!row[field==='name'?'source':'subclass_source']||ref.source===row[field==='name'?'source':'subclass_source']));
      const selected=chosen?String(chosen.id||chosen.name+'|'+chosen.source):row[field]?'__current__':'';
      const options=[['','Nessuno'],...(!chosen&&row[field]?[['__current__',row[field]+' · importato']]:[]),...candidates.map(ref=>[String(ref.id||ref.name+'|'+ref.source),ref.name+' · '+ref.source])];
      return control(label,'data-native-pick="'+key+'" data-index="'+i+'" data-key="'+field+'" data-category="'+category+'"',selected,options);
    }
    if(key==='classes'&&['source','subclass_source'].includes(field))
      return '<div class="native-readonly-source"><span>'+esc(label)+'</span><strong>'+esc(row[field]||'—')+'</strong></div>';
    if(key==='proficiency_choices'&&field==='key'){
      if(['skill','expertise'].includes(row.kind))type=SKILLS.map(([id,name])=>{
        const owned=list(catalogs.calculated?.proficiencies);
        const expert=owned.includes('expertise:'+id);
        const trained=expert||owned.includes('skill:'+id);
        return [id,name+(row.kind==='expertise'?(expert?' ✓ Maestria':trained?' ✓ Competenza':''):
          trained?' ✓':'')];
      });
      if(row.kind==='save')type=['str','dex','con','int','wis','cha'].map(a=>[a,a.toUpperCase()]);
    }
    if(['formula_bonuses','dice_bonuses'].includes(key)&&field==='origin_id')type=[['','Senza origine'],...list(catalogs.origins).map(o=>[o.id,o.name])];
    if(key==='formula_bonuses'&&field==='target')type=[...BONUS_TARGETS,...list(catalogs.trackers).map(t=>['tracker:'+t.id,'Tracker · '+t.name]),...list(catalogs.attacks).flatMap(a=>[['attack_hit:'+a.id,'Colpire · '+a.name],['attack_damage:'+a.id,'Danni · '+a.name],['attack_range:'+a.id,'Gittata · '+a.name],['attack_long_range:'+a.id,'Gittata lunga · '+a.name]])];
    if(key==='origin_spell_grants'){
      if(field==='origin_id')type=list(catalogs.origins).map(o=>[o.id,o.name]);
      if(field==='spell_id')type=[['','Scegli incantesimo'],...list(catalogs.spells).filter(s=>!s.internal_grant).map(s=>[s.id,s.name+' · '+s.source])];
      if(field==='tracker_id')type=[['','Nessuno'],...list(catalogs.trackers).map(t=>[t.id,t.name])];
    }
    return control(label,'data-native-list="'+key+'" data-index="'+i+'" data-key="'+field+'"'+(automatic&&field!=='disabled'?' disabled':''),row[field],type,min,max);
   }).join('')+'</div>'+(key==='formula_bonuses'?benefitRequirements(row,'data-benefit-list="'+key+'" data-index="'+i+'"'):'')+
   (key==='formula_bonuses'?'<p class="hint" data-formula-preview="'+i+'">'+esc(formulaPreview(row.expression,catalogs.calculated))+'</p>':'')+
   (key==='origin_spell_grants'?'<p class="hint">'+list(row.spells).map(s=>esc(typeof s==='string'?s:s.name||s.id)).join(', ')+'</p>':'')+'</article>';
 }).join('')+'<button type="button" class="btn" data-act="native-add" data-list="'+key+'">＋ Aggiungi</button>';
}
export function formulaPreview(expression,calculated){
 try{return 'Risultato della formula: '+formulaValue(expression,calculated);}
 catch(error){return 'Formula non applicata: '+error.message;}
}
export function nativeRowPatch(c,key,index,field,value){
 const definition=ROW_FIELDS[key]?.find(row=>row[0]===field);
 if(!definition)throw Error('Campo non valido');
 const rows=rowsFor(c,key),row=rows[index];if(!row||typeof row!=='object')throw Error('Voce non valida');
 if(row.automatic&&field!=='disabled')throw Error('Modifica la voce dalla sua origine');
 if(key==='classes'&&['source','subclass_source'].includes(field))throw Error('La fonte deriva dal catalogo');
 if(definition[2]==='number' || field==='rank'){
  value=Number(value);if(!Number.isInteger(value)||(definition[3]!==undefined&&(value<definition[3]||value>definition[4])))throw Error('Valore fuori intervallo');
 }
 if(Array.isArray(definition[2])&&!definition[2].some(([v])=>String(v)===String(value)))throw Error('Scelta non valida');
 if(key==='classes'&&['name','source','subclass','subclass_source'].includes(field)&&row[field]!==value){
  row[['name','source'].includes(field)?'id':'subclass_id']='';
  if(field==='name')row.source=''; // Cannot retain the previous book when the class changes by free text.
  if(field==='subclass')row.subclass_source='';
  if(['name','source'].includes(field))Object.assign(row,{subclass:'',subclass_source:'',subclass_id:''});
 }
 row[field]=value;
 return collectionPatch(c,key,rows);
}
export function collectionPatch(c,key,rows){
 if(!ROW_FIELDS[key])throw Error('Elenco non valido');
 const patch={[key]:rows};
 if(key==='classes'){
  const total=rows.filter(row=>row.name).reduce((sum,row)=>sum+Number(row.level||1),0);if(total>20)throw Error('La somma dei livelli non può superare 20');
  const primary=rows[0]||{};
  Object.assign(patch,{class:primary.name||'',class_source:primary.source||'',class_id:primary.id||'',subclass:primary.subclass||'',subclass_source:primary.subclass_source||'',subclass_id:primary.subclass_id||'',level:total||1});
  Object.assign(patch,experienceFloorPatch(c,patch));
 }
 return patch;
}
// A displayed Custom Lineage variant is a choice on the canonical TCE race,
// not an independent rules source. The original race ID remains stable.
export function customLineageVariantPatch(c,key,selected={}){
 if(key!=='species'||!['darkvision','skill'].includes(selected.origin_sense_choice)||
    selected.canonical_race_name!=='Custom Lineage'||selected.source!=='TCE')return null;
 const root='race|tce|custom lineage';
 return {species:'Custom Lineage',species_source:'TCE',
   species_id:selected.canonical_race_id||'5etools:races:tce:custom%20lineage',
   subrace:'',subrace_id:'',subrace_source:'',
   origin_sense_choices:{...(c.origin_sense_choices||{}),
     [root]:selected.origin_sense_choice}};
}
export function referencePatch(c,key,selected={}){
 const custom=customLineageVariantPatch(c,key,selected);
 if(custom){
  // Changing away from Aasimar also clears its previous persistent form,
  // exactly as an ordinary species replacement does.
  if((c.species!=='Custom Lineage'||c.species_source!=='TCE')&&
     c.active_class_features?.['racial:celestial_revelation']){
    const active={...c.active_class_features};
    delete active['racial:celestial_revelation'];
    custom.active_class_features=active;
  }
  return custom;
 }
 const name=selected.name||'',source=selected.source||'',id=selected.id||'';
 const patch={...identityPatch(c,key,name),[key+'_id']:id,[key+'_source']:source};
 if(['species','subrace'].includes(key)&&
   (name!==c[key]||source!==(c[key+'_source']||''))&&
   c.active_class_features?.['racial:celestial_revelation']){
   const active={...c.active_class_features};
   delete active['racial:celestial_revelation'];
   patch.active_class_features=active;
 }
 if(key==='class'||key==='subclass'){
  const changed=name!==c[key]||source!==(c[key+'_source']||'');
  const classes=patch.classes||rowsFor(c,'classes');
  if(classes.length){Object.assign(classes[0],key==='class'?{name,source,id}:{subclass:name,subclass_source:source,subclass_id:id});patch.classes=classes;}
  if(key==='class'&&changed){
   Object.assign(patch,{subclass:'',subclass_source:'',subclass_id:''});
   if(classes.length)Object.assign(classes[0],{subclass:'',subclass_source:'',subclass_id:''});
  }
 }
 if(key==='species'&&source!==(c.species_source||''))Object.assign(patch,{subrace:'',subrace_id:'',subrace_source:''});
 return patch;
}
export function rowReferencePatch(c,key,index,field,selected={}){
 const rows=rowsFor(c,key),row=rows[index];if(!row||row.automatic)throw Error('Voce non modificabile');
 if(key==='classes'&&field==='subclass')Object.assign(row,{subclass:selected.name||'',subclass_source:selected.source||'',subclass_id:selected.id||''});
 else {
  Object.assign(row,{name:selected.name||'',source:selected.source||'',id:selected.id||''});
  if(key==='classes')Object.assign(row,{subclass:'',subclass_source:'',subclass_id:''});
 }
 return collectionPatch(c,key,rows);
}
// The total is derived from class rows; only individual class levels are editable.
export function primaryClassLevel(creature){
 const primary=rowsFor(creature,'classes')[0];
 return creature?.class?Math.max(1,Number(primary?.level||creature?.level||1)):0;
}
export function totalClassLevel(creature){
 const classes=rowsFor(creature,'classes').filter(row=>row?.name);
 return classes.length?classes.reduce((total,row)=>total+Number(row.level||1),0):
  (creature?.class?Number(creature?.level||1):0);
}
export function identityPatch(c,key,value){
 if(key==='level')throw Error('Il livello totale è calcolato automaticamente dalle classi');
 if(key==='xp'){
  const xp=Number(value),minimum=minimumXpForCreature(c);
  if(!Number.isSafeInteger(xp)||xp<0)throw Error('XP non validi');
  if(xp<minimum)throw Error('Il livello attuale richiede almeno '+minimum+' XP');
  return {xp};
 }
 if(key==='primary_class_level'){
  if(!c.class)throw Error('Seleziona prima la classe principale');
  const n=Number(value);
  if(!Number.isInteger(n)||n<1||n>20)throw Error('Livello della classe principale non valido');
  const classes=rowsFor(c,'classes');
  const others=classes.slice(1).filter(row=>row.name).reduce((total,row)=>total+Number(row.level||1),0);
  if(n+others>20)throw Error('La somma dei livelli delle classi non può superare 20');
  classes[0].level=n;
  const changes={classes,level:n+others};
  return {...changes,...experienceFloorPatch(c,changes)};
 }
 const patch={[key]:value};
 if(['species','subrace','background','class','subclass'].includes(key)&&value!==c[key])patch[key+'_id']='';
 if(key==='species'&&value!==c.species)Object.assign(patch,{subrace:'',subrace_id:'',subrace_source:''});
 if(key==='size_name')patch.footprint=({Tiny:1,Small:1,Medium:1,Large:2,Huge:3,Gargantuan:4})[value]||1;
 if(key==='visual_front_quarter_turns')patch[key]=Number(value);
 if(['class','subclass','level','class_source','subclass_source'].includes(key)){
  const classes=structuredClone(list(c.classes));
  if(classes.length){
   const extra=classes.slice(1).reduce((n,row)=>n+Number(row.level||1),0);
   if(key==='level'){if(value<=extra||value>20)throw Error('Livello totale non valido per le classi aggiuntive');classes[0].level=value-extra;}
   else {const mapped=({class:'name',class_source:'source',subclass:'subclass',subclass_source:'subclass_source'})[key];classes[0][mapped]=value;if(patch[key+'_id']!==undefined)classes[0][key==='class'?'id':'subclass_id']='';}
   patch.classes=classes;
  }
 }
 if(['class','class_source','subclass','subclass_source'].includes(key))
  Object.assign(patch,experienceFloorPatch(c,patch));
 return patch;
}
// Use the native 5etools race catalog for creature types, including subraces.
export function speciesCreatureType(creature,catalogs={}){
 if(creature?.kind==='monster'){
  const raw=creature.type??creature.stat_block?.type;
  return typeof raw==='string'?raw:raw?.type||'—';
 }
 const races=list(catalogs.races),species=String(creature?.species||''),source=String(creature?.species_source||'');
 if(!species)return '—';
 const same=(a,b)=>String(a||'').toLowerCase()===String(b||'').toLowerCase();
 const parent=races.find(r=>creature.species_id&&r.id===creature.species_id&&!r.raceName)||
  races.find(r=>!r.raceName&&same(r.name,species)&&(!source||same(r.source,source)));
 const subrace=String(creature?.subrace||''),subsource=String(creature?.subrace_source||'');
 const selected=subrace?races.find(r=>same(r.raceName,species)&&same(r.name,subrace)&&
  (!subsource||same(r.source,subsource))):null;
 // In 5etools the omitted creatureTypes property means Humanoid.
 const raw=selected?.creatureTypes??parent?.creatureTypes;
 const values=Array.isArray(raw)?(raw.length?raw:['humanoid']):raw?[raw]:parent?['humanoid']:[];
 const names={aberration:'Aberrazione',beast:'Bestia',celestial:'Celestiale',construct:'Costrutto',
  dragon:'Drago',elemental:'Elementale',fey:'Folletto',fiend:'Immondo',giant:'Gigante',
  humanoid:'Umanoide',monstrosity:'Mostruosità',ooze:'Melma',plant:'Vegetale',undead:'Non morto'};
 return values.map(v=>typeof v==='string'?v:v?.type||'').filter(Boolean)
  .map(v=>names[v.toLowerCase()]||v).join(', ')||'—';
}
// Species and subraces are separate picker entries. Native flattened
// references are not selectable as species.
export function availableReferenceRows(c,key,category,catalogs={}){
 return contentForRules(list(catalogs[category]),c.rules_version).filter(r=>r?.name &&
   (key!=='species'||!r.raceName) &&
   (key!=='subrace'||!!r.raceName&&r.raceName===c.species&&
     (!c.species_source||r.raceSource===c.species_source)&&
     Number(r.level||1)<=Math.max(Number(c.level)||1,
       (c.classes||[]).reduce((sum,row)=>sum+Math.max(0,Number(row.level)||0),0))) &&
   (key!=='subclass'||!!c.class&&(!r.class_name||r.class_name===c.class)&&(!c.class_source||!r.class_source||r.class_source===c.class_source)) &&
   (key!=='class'||c.rules_version!=='2024'||r.source!=='PHB'));
}
export function nativeSection(c,section,{field,area,panel,resources,resourcesEditor=resources,equipment='',armor='',attacks='',details='overview',catalogs={},calculated={}}){
 const cols=s=>'<div class="columns">'+s+'</div>';
 const select=(label,key,options,value=c[key])=>control(label,'data-field="'+key+'"',value,options);
 const reference=(label,key,category)=>{
   if(key==='background'){
     const current=c.background||'Nessuno',source=c.background_source||'';
     return '<label>'+esc(label)+
       '<button type="button" class="background-reference-button" data-act="background-picker-open" data-background-index="primary"'+
       ' aria-label="Cerca e seleziona il background principale">'+
       '<span class="background-reference-value">'+esc(current)+(source?' <small>· '+esc(source)+'</small>':'')+'</span>'+
       '<span class="background-reference-search" aria-hidden="true">⌕</span></button></label>';
   }
   const rows=availableReferenceRows(c,key,category,catalogs);
   const current=c[key]||'', source=c[key+'_source']||'';
   const active=rows.find(r=>key==='species'&&r.canonical_race_name===current&&
     (!source||r.source===source)&&
     c.origin_sense_choices?.['race|tce|custom lineage']===r.origin_sense_choice) ||
     rows.find(r=>r.name===current&&(!source||r.source===source)) ||
     rows.find(r=>c[key+'_id']&&r.id===c[key+'_id']&&(!source||r.source===source));
   const options=[['','Nessuno'],...(!active&&current?[['__current__',current+' · importato']]:[]),
     ...rows.map(r=>[String(r.id||r.name+'|'+(r.source||'')),r.name+(r.source?' · '+r.source:'')])];
   const chosen=active?String(active.id||active.name+'|'+(active.source||'')):current?'__current__':'';
   return '<label>'+esc(label)+'<select data-reference="'+esc(category)+'" data-reference-key="'+esc(key)+'" '+
     (!rows.length?'disabled':'')+'>'+
     options.map(([v,label])=>'<option value="'+esc(v)+'" '+(v===chosen?'selected':'')+'>'+esc(label)+'</option>').join('')+
     '</select>'+(current?'<span class="hint">Fonte: '+esc(active?.source||source||'Non disponibile')+'</span>':'')+'</label>';
 };
 const number=(label,key,value=c[key]??0,min=0,max=99999)=>field(label,key,value,'number','min="'+min+'" max="'+max+'"');
 const summary=rows=>'<dl class="native-summary">'+rows.map(([label,value])=>'<div><dt>'+esc(label)+'</dt><dd>'+esc(value??'—')+'</dd></div>').join('')+'</dl>';
 const speciesType=speciesCreatureType(c,catalogs);
 const secondaryClasses=rowsFor(c,'classes').slice(1);
 const feats=list(c.feats_catalog).map((feat,i)=>{
  const entry=typeof feat==='string'?{name:feat}:feat||{};
  const owner=featOriginLabel(entry,calculated);
  const level=Number(entry.level??entry.acquired_level??entry.origin_level);
  const levelText=Number.isInteger(level)&&level>=1&&level<=20?
    'Livello del privilegio: '+level:'';
  const originKey=featTraitOriginKey(entry);
  const book=String(entry.source||'').trim();
  const title=String(entry.name||'Talento')+(entry.spell_variant?' · '+String(entry.spell_variant).replace(/ Spells$/i,''):'');
  return '<div class="info-owned-feat-row">'+
   '<button type="button" class="info-owned-feat-open" data-act="feat-open-trait"'+
    ' data-feat-index="'+i+'" data-feat-origin="'+esc(originKey)+'"'+
    ' aria-label="Apri il tratto di '+esc(title)+'">'+
    '<span class="info-owned-feat-details"><strong>'+esc(title)+'</strong>'+
    '<span class="info-feat-origin">Origine · '+esc(owner)+'</span>'+
    (levelText?'<span class="info-feat-level">'+esc(levelText)+'</span>':'')+'</span>'+
    (book?'<span class="info-feat-book">'+esc(book)+'</span>':'')+
    '<span class="info-feat-chevron" aria-hidden="true">›</span></button>'+
   (entry.name?'<button type="button" class="info-owned-feat-remove" data-act="feat-remove"'+
    ' data-feat-key="'+esc(originKey)+'" title="Rimuovi talento" aria-label="Rimuovi il talento '+esc(title)+'">×</button>':'')+
   '</div>';
 }).join('')||'<p class="play-empty">Nessun talento registrato.</p>';
 const read=(target,label,signed=false,suffix='')=>formulaReadout(calculated,target,label,{signed,suffix});
 const nativeNote='';
 const skillPanels=()=>panel('Abilità','<dl class="native-summary">'+SKILLS.map(([id,label,ability])=>'<div><dt>'+esc(label)+' · '+ability.toUpperCase()+' '+(calculated.proficiencies?.includes('expertise:'+id)?'🎓🎓':calculated.proficiencies?.includes('skill:'+id)?'🎓':'')+'</dt><dd>'+read('skill:'+id,label,true)+'</dd></div>').join('')+'</dl>','stats-skills-panel')+
  panel('Altre competenze',summary([
    ['Abilità',SKILLS.filter(([key])=>(calculated.proficiencies||[]).some(id=>
      id==='skill:'+key||id==='expertise:'+key)).map(([,label])=>label).join(', ')||'Nessuna'],
    ['Maestrie',SKILLS.filter(([key])=>(calculated.proficiencies||[]).includes('expertise:'+key))
      .map(([,label])=>label).join(', ')||'Nessuna'],
    ...['tool','language','weapon','armor'].map((kind,i)=>[
      ['Strumenti','Linguaggi','Armi','Armature'][i],
      (calculated.proficiencies||[]).filter(key=>key.startsWith(kind+':'))
        .map(key=>key.slice(kind.length+1)).join(', ')||'Nessuno'])
  ]))+
  '';
 const statsIntro=()=>panel('Caratteristiche',
   '<div class="native-abilities" role="table" aria-label="Caratteristiche e tiri salvezza">'+
   '<div class="native-abilities-header" role="row">'+
   '<strong role="columnheader">Car.</strong><strong role="columnheader">Punteggio</strong>'+
   '<strong role="columnheader">Mod.</strong><strong role="columnheader">TS</strong></div>'+
   ['str','dex','con','int','wis','cha'].map(key=>
    '<div class="native-ability-row" role="row" data-ability-row="'+key+'">'+
    '<strong class="native-ability-name" role="rowheader">'+key.toUpperCase()+'</strong>'+
    '<div class="native-ability-score" role="cell">'+
    formulaReadout(calculated,'ability:'+key,'Punteggio '+key.toUpperCase(),{scoreAbility:key})+'</div>'+
    '<div class="native-ability-value" role="cell">'+read('ability_mod:'+key,'Modificatore '+key.toUpperCase(),true)+'</div>'+
    '<div class="native-ability-value" role="cell">'+read('save:'+key,'Tiro salvezza '+key.toUpperCase(),true)+'</div>'+
    '</div>').join('')+'</div>','stats-abilities-panel')+
  panel('Riepilogo','<dl class="native-summary"><div><dt>Bonus competenza</dt><dd>'+read('proficiency','Bonus competenza',true)+'</dd></div><div><dt>Percezione passiva</dt><dd>'+read('passive_perception','Percezione passiva')+'</dd></div></dl>','stats-summary-panel');
 if(section==='info')return panel('Identità',cols(
    select('Regole','rules_version',[['2014','2014'],['2024','2024']],c.rules_version||'2014')+
    field('Nome','name',c.name)+field('Fazione','party_id',c.party_id||'Default')+
    select('Allineamento','alignment',
      c.alignment&&!ALIGNMENTS.some(([id])=>id===c.alignment)?
        [...ALIGNMENTS,[c.alignment,c.alignment+' · importato']]:ALIGNMENTS,
      c.alignment||'Completamente neutrale')) )+
   panel('Aspetto',
    '<p class="sheet-section-description">Specie e tipo della creatura.</p>'+
    ((c.kind==='monster'||c.variant_rules_kind==='monster')?summary([['Razza / Specie',c.species],['Tipo',typeof c.type==='string'?c.type:c.stat_block?.type?.type||c.stat_block?.type||'—']])+
      '<label>GS<input data-native-cr value="'+esc(typeof c.stat_block?.cr==='object'?c.stat_block.cr.cr:c.stat_block?.cr||'0')+'"></label>':
      cols(reference('Razza / Specie','species','races')+reference('Sottorazza','subrace','races'))+
      summary([['Tipo',speciesType]]))+
    '<h3>Miniature</h3>'+
    summary([['Miniatura base',c.default_miniature_id||'Non assegnata'],['Forma attuale',c.current_miniature_id||'Non assegnata']])+
    '<div class="actions miniature-actions"><button class="btn" data-act="miniature-pick" data-miniature-kind="base">Scegli la miniatura di base</button><button class="btn" data-act="miniature-pick" data-miniature-kind="current">Scegli forma attuale</button></div>'+
    ''+
    cols(select('Taglia','size_name',[['Tiny','Minuscola'],['Small','Piccola'],['Medium','Media'],['Large','Grande'],['Huge','Enorme'],['Gargantuan','Mastodontica']],c.size_name||'Medium')+
      select('Fronte della miniatura','visual_front_quarter_turns',[[0,'−Z · 0°'],[1,'+X · 90°'],[2,'+Z · 180°'],[3,'−X · 270°']],c.visual_front_quarter_turns||0))+
    '')+
   panel('Background','<h3>Background principale</h3>'+reference('Background principale','background','backgrounds')+
     '<h3>Altri background</h3>'+nativeRows(c,'backgrounds_catalog',catalogs))+
   panel('Classi',
      '<p class="sheet-section-description">Classi e punti esperienza del personaggio.</p>'+
      '<div class="progression-summary"><span class="progression-total">Liv. totale <output aria-label="Livello totale automatico">'+esc(totalClassLevel(c))+'</output></span>'+
      number('XP','xp',Math.max(Number(c.xp)||0,minimumXpForCreature(c)),minimumXpForCreature(c),Number.MAX_SAFE_INTEGER)+'</div>'+
      cols(reference('Classe base','class','classes')+reference('Sottoclasse','subclass','subclasses')+
       (c.class?number('Livello classe principale','primary_class_level',primaryClassLevel(c),1,20):
        '<label>Livello classe principale<input type="number" value="0" disabled></label>')+
       '<h3>Classi secondarie</h3>'+(secondaryClasses.length?'':'<p class="hint">Nessuna classe secondaria.</p>')+
       nativeRows(c,'classes',catalogs,1)),'classes-progression-panel')+
   panel('Talenti',feats+'<div class="actions"><button type="button" class="btn small" data-act="feat-catalog">＋ Aggiungi talento</button></div>')+
   statsIntro()+
   skillPanels();
 if(section==='battle'){
  // Preserve legacy standalone native-section callers; PWA uses the shared
  // equipment view whenever one was passed.
  const inventory=list(c.inventory).map(resolveOwnedItem);
  const wornArmor=inventory.find(item=>list(item?.equipped_slots).includes('body')&&itemKind(item)==='armor');
  const shields=inventory.filter(item=>list(item?.equipped_slots).some(slot=>slot==='main'||slot==='off')&&itemKind(item)==='shield');
  const shieldBonus=shields.reduce((value,item)=>Math.max(value,Math.max(0,Number(item.ac)||0)),0);
  const dex=Number(calculated.values?.['ability_mod:dex']??0);
  const armorDex=wornArmor?armorDexterityBonus(wornArmor,dex):0;
  const dexCap=wornArmor?armorDexterityLimit(wornArmor):null;
  const rawMonsterAc=Array.isArray(c.stat_block?.ac)?c.stat_block.ac.find(row=>typeof row==='number'||row?.ac!==undefined):c.stat_block?.ac;
  const monsterAc=typeof rawMonsterAc==='object'?rawMonsterAc?.ac:rawMonsterAc;
  const naturalBase=(c.kind==='monster'||c.variant_rules_kind==='monster')?(monsterAc??10):(c.armor_class_base??10);
  const naturalFormula=String(c.armor_natural_formula||((c.kind==='character'&&Number(naturalBase)===10)?'10 + dex_mod':String(naturalBase)));
  const acFormula=wornArmor?String(Number(wornArmor.ac)||10)+
    (dexCap===0?' (senza DES)':' + ('+armorDex+' DES'+(dexCap===null?'':', max '+(dexCap>=0?'+':'')+dexCap)+')')+
    (shieldBonus?' + '+shieldBonus+' scudo':''):naturalFormula+(shieldBonus?' + '+shieldBonus+' scudo':'');
  const legacyDefense='<div class="battle-defense-values"><div class="battle-stat"><span>CA</span>'+
    formulaReadout(calculated,'ac','Classe armatura',{showBonus:false})+'</div></div>'+
    '<div class="battle-defense-settings">'+armor+
      '<div class="battle-ac-formula"><strong>'+(wornArmor?'Formula armatura indossata':'Formula CA naturale')+'</strong>'+
      '<output>'+esc(acFormula)+'</output></div>'+

    '</div>';
  return '<div class="battle-root">'+
   panel('Punti ferita',
    '<dialog id="hp-adjust-dialog" class="sheet-roll-dialog hp-adjust-dialog" aria-labelledby="hp-adjust-title">'+
     '<header class="hp-adjust-heading"><h2 id="hp-adjust-title">Punti ferita</h2>'+
     '<button type="button" class="hp-adjust-close" data-act="hp-adjust-cancel" aria-label="Chiudi" title="Chiudi">×</button></header>'+
     '<form id="hp-adjust-form">'+
      '<div class="hp-adjust-stats">'+
       '<label class="hp-adjust-stat" for="hp-adjust-current"><span>Attuali</span><input id="hp-adjust-current" type="number" inputmode="numeric" step="1" min="0" max="'+esc(Math.max(0,Number(calculated.stats?.max_hp??0),Number(c.current_hp)||0))+'" value="'+esc(c.current_hp??0)+'" required></label>'+
       '<div class="hp-adjust-stat hp-adjust-max"><span>Massimi</span>'+
        '<button type="button" data-act="hp-adjust-max" aria-label="Modifica PF massimi" title="Modifica PF massimi">'+esc(Math.max(0,Number(calculated.stats?.max_hp??0)))+' <span aria-hidden="true">✎</span></button></div>'+
       '<label class="hp-adjust-stat" for="hp-adjust-temporary"><span>Temporanei</span><input id="hp-adjust-temporary" type="number" inputmode="numeric" step="1" min="0" max="99999" value="'+esc(c.temporary_hp??0)+'" required></label>'+
      '</div>'+
      '<div class="hp-adjust-actions"><button type="button" class="btn" data-act="hp-restore" title="Riporta i PF attuali al massimo">↺ PF pieni</button>'+
       '<button type="submit" class="btn primary" id="hp-adjust-confirm">Salva PF</button></div>'+
     '</form>'+
     '<div class="hp-adjust-quick"><label for="hp-adjust-amount">Applica danni o cura</label>'+
      '<div class="hp-adjust-quick-row">'+
       '<input id="hp-adjust-amount" type="number" inputmode="numeric" step="1" min="1" max="99999" placeholder="Quantità" aria-label="Quantità di PF" value="">'+
       '<button type="button" class="btn danger" data-act="hp-adjust-apply" data-hp-mode="damage">− Danni</button>'+
       '<button type="button" class="btn primary" data-act="hp-adjust-apply" data-hp-mode="heal">＋ Cura</button>'+
      '</div></div>'+
    '</dialog>',
    'battle-hp-panel')+
   panel('Classe armatura',
    equipment?'<div class="battle-defense-settings">'+equipment+'</div>':legacyDefense,
    'battle-defense-panel')+
    (calculated.feature_damage_resistances?.length?'<p class="feature-defense-summary">Ira · Resistenza a contundenti, perforanti e taglienti</p>':'')+
    ((calculated.item_damage_resistances||[]).length?'<p class="feature-defense-summary">'+
      (calculated.item_damage_resistances||[]).map(row=>'Oggetto · '+esc(row.origin_name||'Infusione')+
        ' · Resistenza a '+esc(row.damage_type)).join(' · ')+'</p>':'')+
   panel('Movimento',
    '<h3>Velocità</h3><div class="derived-metrics">'+[['speed','Camminata'],['speed:climb','Scalata'],['speed:swim','Nuoto'],['speed:fly','Volo'],['speed:burrow','Scavo']].map(([key,label])=>'<div><span>'+label+'</span>'+read(key,label,false,' ft')+'</div>').join('')+'</div>'+
    '<h3>Salti · distanze massime</h3>'+summary([['In lungo · con rincorsa',(calculated.stats?.jumps?.long??0)+' ft'],['In lungo · da fermo',(calculated.stats?.jumps?.long??0)/2+' ft'],['In alto · con rincorsa',(calculated.stats?.jumps?.high??0)+' ft'],['In alto · da fermo',(calculated.stats?.jumps?.high??0)/2+' ft']])+
    ((c.kind==='monster'||c.variant_rules_kind==='monster')?number('Camminata base (ft)','speed_base',c.speed_base??c.speed??30):''),
    'battle-movement-panel')+
   resources+
   panel('Attacchi disponibili',attacks,'battle-attacks-panel')+
   '</div>';
 }
 return null;
}

// Action overview lives in an existing server-served module so the PWA needs no native route changes.
// Structured action economy overview; all computations remain local.
export const ACTION_GROUPS=[["action","Azione"],["bonus","Azione bonus"],["free","Azione gratuita"],["movement","Movimento"],["reaction","Reazione"]];
const defaults=[
["Attaccare","action","attacco","Effettua un attacco."],
["Scattare","action","generale","Ottieni movimento aggiuntivo pari alla tua velocità."],
["Disimpegnarsi","action","generale","Eviti gli attacchi di opportunità provocati dal movimento."],
["Schivare","action","generale","Ti concentri sulla difesa fino al turno successivo."],
["Aiutare","action","generale","Aiuta una creatura in una prova o in un attacco."],
["Nascondersi","action","prova","Effettua una prova di Furtività."],
["Cercare","action","prova","Effettua una prova di Percezione o Indagare."],
["Preparare","action","generale","Prepara un'azione da eseguire con la reazione."],
["Usare un oggetto","action","generale","Utilizza un oggetto che richiede un'azione."],
["Interagire con un oggetto","free","generale","Interazione semplice con un oggetto."],
["Muoversi","movement","movimento","Utilizza il movimento disponibile."],
["Attacco di opportunità","reaction","attacco","Attacco in mischia come reazione, quando consentito."]
];
const actionEsc=v=>String(v??"").replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;','\'':'&#39;'}[c]));
function timing(value){
 const s=String(value||"").toLowerCase();
 if(/reaction|reazione/.test(s))return "reaction";
 if(/bonus/.test(s))return "bonus";
 if(/free|gratuit|interact/.test(s))return "free";
 if(/move|movimento/.test(s))return "movement";
 return "action";
}
export function actionEntries(record,calculated={},spells=[]){
 const entries=defaults.map(([name,time,type,description])=>({name,time,type,description,tracker:""}));
 const add=(name,time,type,description,tracker)=>entries.push({name:String(name||type),time:timing(time),type,description:String(description||""),tracker:String(tracker||"")});
 for(const a of calculated.attacks||[])add(a.name,"action","attacco",a.description||a.damage,a.tracker_id);
 const known=new Set([...(record.prepared_spells||[]),...(record.known_spells||[]),...(record.spells||[])].map(x=>typeof x==="string"?x:String(x.id||x.spell_id||"")));
 for(const grant of [...(calculated.origin_spells||[]),...(record.origin_spell_grants||[])])
  if(!grant.disabled)known.add(String(grant.spell_id||""));
 for(const spell of spells){
  if(!known.has(String(spell.id||"")))continue;
  const time=Array.isArray(spell.time)?spell.time[0]?.unit:spell.casting_time||spell.time;
  const grant=[...(calculated.origin_spells||[]),...(record.origin_spell_grants||[])].find(g=>g.spell_id===spell.id&&!g.disabled);
  add(spell.name||spell.id,time,"incantesimo",spell.description||"",grant?.tracker_id||(Number(spell.level)>0?"Slot incantesimo":""));
 }
 for(const feature of [...(record.action_grants||[]),...(calculated.actions||[])])
  if(feature&&!feature.disabled)add(feature.name||feature.title,feature.action_type||feature.activation||feature.time,"capacità",feature.description||feature.text,feature.tracker_id);
 return entries;
}
export function actionEconomyView(record,calculated,spells=[]){
 const entries=actionEntries(record,calculated,spells);
 return ACTION_GROUPS.map(([id,title])=>'<section class="panel"><h2>'+title+'</h2>'+
  entries.filter(e=>e.time===id).map(e=>'<details class="native-entry"><summary><strong>'+actionEsc(e.name)+'</strong> · '+actionEsc(e.type)+(e.tracker?' · '+actionEsc(e.tracker):'')+'</summary><p>'+actionEsc(e.description)+'</p></details>').join('')+
  (!entries.some(e=>e.time===id)?'<p class="hint">Nessuna azione.</p>':'')+'</section>').join('');
}
