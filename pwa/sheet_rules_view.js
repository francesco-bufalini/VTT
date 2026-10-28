import {hitDicePools,spendTrackerUses} from './character_core.js';
import {isPortraitDataUrl} from './character_portrait.js';
import {classFeatureRollResourceBonuses} from './feature_mechanics.js';
// Render local/offline calculations; no desktop sessions or API calls.
import {ABILITIES,SKILLS,localClasses} from "./sheet_rules.js";
import {actionGlyphKey,actionGlyph} from "./action_economy.js";
import {itemKind,resolveOwnedItem,ownedItemDisplayName,requiresAttunement,itemAttunementCount,inventoryAttunementCounts,spellScrollLevel,spellScrollName,activeInfusions,hasProperty,validSlot,armorDexterityLabel} from "./item_controls.js";
import * as inventoryModule from "./item_controls.js";
const DEFAULT_INVENTORY_CONTAINER=inventoryModule.DEFAULT_INVENTORY_CONTAINER||"backpack";
const inventoryContainers=inventoryModule.inventoryContainers||((record={})=>{
 const rows=Array.isArray(record.inventory_containers)?record.inventory_containers:[];
 const seen=new Set([DEFAULT_INVENTORY_CONTAINER]);
 return [{id:DEFAULT_INVENTORY_CONTAINER,name:'Zaino'},...rows.flatMap(row=>{
  const id=String(row?.id||'').trim(),name=String(row?.name||'').trim();
  if(!id||!name||seen.has(id))return [];
  seen.add(id);return [{id,name}];
 })];
});
const itemContainerId=inventoryModule.itemContainerId||((item={},containers=[])=>{
 const id=String(item?.container_id||DEFAULT_INVENTORY_CONTAINER);
 return containers.some(row=>row.id===id)?id:DEFAULT_INVENTORY_CONTAINER;
});
import {isDocument} from "./documents.js";
import {conditionOptions,conditionDescriptionHtml,exhaustionLevel,exhaustionConditionRows} from "./condition_catalog.js";
import {matchesSearch} from './ui_primitives.js';

export function inventorySectionControls(record,selected=[]){
 const containers=inventoryContainers(record);
 const tabs=[['items','Zaino','inventory'],['scrolls','Pergamene','scroll'],['documents','Documenti','book'],
  ...containers.slice(1).map(row=>['container:'+row.id,row.name,'inventory'])];
 return '<nav class="inventory-subtabs inventory-container-tabs" role="group" aria-label="Sezioni inventario · selezione multipla">'+
  '<button type="button" class="inventory-add-container-tab" data-act="inventory-container-add" aria-label="Aggiungi sezione inventario">＋</button>'+

  tabs.map(([key,label,glyph])=>{
   const custom=key.startsWith('container:');
   const toggle='<button type="button" data-act="inventory-subtab" data-subtab="'+esc(key)+
    '" aria-pressed="'+selected.includes(key)+'" aria-label="'+esc(label)+'">'+actionGlyph(glyph)+'<span>'+esc(label)+'</span></button>';
   return custom?'<span class="inventory-custom-section">'+toggle+
    '<button type="button" class="inventory-section-remove" data-act="inventory-container-delete" data-container-id="'+esc(key.slice(10))+
    '" aria-label="Elimina sezione '+esc(label)+'" title="Elimina sezione '+esc(label)+'">×</button></span>':toggle;
  }).join('')+'</nav>';
}
export function inventoryAttunementControl(record,index,calculated={},showName=true){
 const item=record.inventory?.[index]||{},quantity=Math.max(0,Math.floor(Number(item.quantity??1)||0));
 const maximum=calculated.attunements?.maximum??calculated.values?.attunement_max??record.attunement_max_base??3;
 const counts=calculated.attunements?.counts||inventoryAttunementCounts(record.inventory,maximum);
 const count=counts[index]||0,used=counts.reduce((sum,n)=>sum+n,0);
 const limit=Math.max(count,Math.min(quantity,Math.max(0,maximum-used+count)));
 return '<div class="inventory-popup-attunement" data-attunement-row="'+index+'">'+
  '<span class="inventory-attunement-copy"><strong>'+esc(showName?item.name||'Oggetto':'Sintonie dedicate')+'</strong>'+
  '<small>'+count+' / '+quantity+' copie · '+used+' / '+maximum+' sintonie totali</small></span>'+
  '<div class="inventory-attunement-controls">'+
  '<button type="button" data-act="inventory-attunement" data-index="'+index+'" data-delta="-1" aria-label="Rimuovi una sintonia da '+esc(item.name)+'"'+(count<=0?' disabled':'')+'>−</button>'+
  '<input type="number" min="0" max="'+limit+'" step="1" data-item-index="'+index+'" data-item-key="attuned_count" value="'+count+'" aria-label="Sintonie dedicate a '+esc(item.name)+'">'+
  '<button type="button" data-act="inventory-attunement" data-index="'+index+'" data-delta="1" aria-label="Aggiungi una sintonia a '+esc(item.name)+'"'+(count>=limit?' disabled':'')+'>+</button></div></div>';
}
// Lightweight inline portraits: share the same unmistakable character/monster
// identity in the archive, persistent header, and creature sheet. No extra
// network asset is required when the PWA is running offline.
export function creatureFaceIcon(kind='character'){
 const common='class="creature-face" viewBox="0 0 64 64" fill="none" stroke="currentColor" stroke-width="2.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"';
 if(kind==='monster')return '<svg '+common+'>'+
  '<path d="M18 18 9 5l1 21 8 3M46 18 55 5l-1 21-8 3"/>'+
  '<path d="M23 13 15 21l-3 17 9 15 11 7 11-7 9-15-3-17-8-8-9 3z"/>'+
  '<path d="m17 27 12 4-6 5-7-2m31-7-12 4 6 5 7-2"/>'+
  '<path d="m28 39 4 3 4-3M21 44q11 8 22 0l-3 11-4-8-4 6-4-6-4 8z"/>'+
  '<path d="M18 21 25 16m21 5-7-5"/></svg>';
 return '<svg '+common+'>'+
  '<path d="M19 22 7 11l6 23 7 1M45 22l12-11-6 23-7 1"/>'+
  '<path d="M19 21q1-13 13-13t13 13l1 18q-2 12-14 18-12-6-14-18z"/>'+
  '<path d="M19 25q4-13 14-12 10-1 13 12M20 23l7-6 5 1 5-5 8 10"/>'+
  '<path d="m23 32 7-2-2 4-5-1m18-1-7-2 2 4 5-1"/>'+
  '<path d="m32 34-2 9h4m-8 4q6 4 12 0"/>'+
  '<path d="M20 38q-1 8 3 12m21-12q1 8-3 12"/></svg>';
}
const esc=v=>String(v??"—").replace(/[&<>"']/g,c=>({
  "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const signed=value=>value===null||value===undefined?"—":Number(value)>=0?"+"+value:String(value);
const metric=(label,value)=>'<div class="derived-metric"><span>'+esc(label)+'</span><strong>'+esc(value)+'</strong></div>';
function skillTrainingIcon(rank){
 if(rank!==1&&rank!==2)return '';
 const label=rank===2?'Maestria':'Competenza';
 const shape=rank===2?
  '<path d="M3.5 7.5 8 11l4-6 4 6 4.5-3.5-2 10.5h-13z"/><path d="M6 21h12"/>':
  '<path d="m12 2.5 2.9 6 6.6.9-4.8 4.7 1.2 6.6L12 17.5l-5.9 3.2 1.2-6.6-4.8-4.7 6.6-.9z"/>';
 return '<span class="play-skill-rank play-skill-rank--'+(rank===2?'expertise':'proficient')+
  '" role="img" aria-label="'+label+'" title="'+label+'"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round" aria-hidden="true">'+shape+'</svg></span>';
}
// Choose the fastest available movement mode, preserving the current calculated speed keys.
export function fastestMovement(data={}){
 const modes=[['speed','Camminata'],['speed:climb','Scalata'],['speed:swim','Nuoto'],
  ['speed:fly','Volo'],['speed:burrow','Scavo']];
 const options=modes.map(([key,label])=>{
  const statKey=key==='speed'?'walk':key.slice('speed:'.length);
  const raw=data.values?.[key]??data.stats?.speeds?.[statKey];
  const value=raw===null||raw===undefined||raw===''?NaN:Number(raw);
  return {key,label,value};
 }).filter(item=>Number.isFinite(item.value)&&item.value>=0);
 return options.reduce((best,item)=>!best||item.value>best.value?item:best,null)||
  {key:'speed',label:'Camminata',value:null};
}
// Read recovery rules from the effective tracker (automatic or custom).
export function trackerRecoveryText(tracker={}) {
 const labels={short_rest:'riposo breve',long_rest:'riposo lungo',turn:'inizio turno',manual:'manuale'};
 if(tracker.recharge_note)return 'Recupero: '+String(tracker.recharge_note);
 const mode=String(tracker.recharge||'manual');
 if(mode==='d6'){
  const n=Number(tracker.recharge_min);
  const minimum=Number.isInteger(n)&&n>=1&&n<=6?n:6;
  return 'Ricarica: d6 · '+minimum+'+';
 }
 return 'Recupero: '+(labels[mode]||'non specificato');
}
/** Expand a modifier using effective abilities, training and residual bonuses. */
export function sheetModifierBreakdown(data,target){
 const total=Number(data?.values?.[target]);
 if(!Number.isFinite(total))return 'Modificatore non disponibile';
 const sign=value=>(Number(value)>=0?'+':'')+Number(value);
 const pieces=[];
 let subtotal=0;
 const push=(label,value)=>{
  if(!Number.isFinite(value))return;
  pieces.push(label+' '+sign(value));subtotal+=value;
 };
 const abilityFrom=key=>Number(data?.values?.['ability_mod:'+key]);
 const proficiency=Number(data?.values?.proficiency||0);
 if(target.startsWith('ability_check:')||target.startsWith('ability_mod:')){
  const key=target.split(':')[1],score=Number(data?.values?.['ability:'+key]);
  if(Number.isFinite(score))push('⌊('+score+' − 10)/2⌋',Math.floor((score-10)/2));
 }else if(target==='initiative')push('Mod. DES',abilityFrom('dex'));
 else if(target.startsWith('save:')){
  const key=target.slice(5);
  push('Mod. '+key.toUpperCase(),abilityFrom(key));
  if(data?.proficiencies?.includes('save:'+key))push('Competenza',proficiency);
 }else if(target.startsWith('skill:')){
  const skill=target.slice(6),definition=SKILLS.find(row=>row[0]===skill);
  if(definition)push('Mod. '+definition[2].toUpperCase(),abilityFrom(definition[2]));
  const rank=data?.proficiencies?.includes('expertise:'+skill)?2:
   data?.proficiencies?.includes('skill:'+skill)?1:0;
  if(rank)push(rank===2?'Maestria':'Competenza',proficiency*rank);
 }
 if(!pieces.length)return 'Modificatore calcolato: '+sign(total);
 const other=total-subtotal;
 if(Math.abs(other)>0.000001)push('Altri bonus',other);
 return pieces.join(' + ').replaceAll(' + Altri bonus -',' − Altri bonus ')+
  ' = '+sign(total);
}
/** Preview does not consume randomness: opening a modifier is not a roll. */
export function sheetRollFormula(modifier,bonuses=[],mode='normal'){
 const number=Number(modifier);
 if(!Number.isFinite(number))throw Error('Modificatore del tiro non disponibile');
 // ADV/DIS are game-rule labels in the UI and chat. The actual dice and
 // highest/lowest selection remain handled by rollSheetDice, not this caption.
 const fixed=(mode==='advantage'?'ADV · ':mode==='disadvantage'?'DIS · ':'')+
   '1d20'+(number<0?' − '+Math.abs(number):' + '+number);
 return fixed+bonuses.map(row=>Number.isSafeInteger(row.flat_bonus)?
   (row.flat_bonus<0?' − ':' + ')+Math.abs(row.flat_bonus):
   ' + '+String(row.dice)).join('');
}
export function rollSheetDice(modifier,bonuses=[],die,mode='normal'){
 if(typeof die!=='function')throw Error('Generatore dadi non disponibile');
 const base=Number(modifier);
 if(!Number.isFinite(base))throw Error('Modificatore non valido');
 const d20=die(20);
 if(!Number.isInteger(d20)||d20<1||d20>20)throw Error('Risultato d20 non valido');
 const rolls=[d20];
 if(['advantage','disadvantage'].includes(mode)){
  const second=die(20);if(!Number.isInteger(second)||second<1||second>20)throw Error('Risultato d20 non valido');rolls.push(second);
 }
 const kept=mode==='advantage'?Math.max(...rolls):mode==='disadvantage'?Math.min(...rolls):d20;
 const parts=[{name:mode==='advantage'?'d20 · vantaggio':mode==='disadvantage'?'d20 · svantaggio':'d20',notation:sheetRollFormula(0,[],mode).split(' + ')[0],rolls,subtotal:kept}];
 for(const bonus of bonuses){
  if(Object.hasOwn(bonus,'flat_bonus')){
   const flat=Number(bonus.flat_bonus);
   if(!Number.isSafeInteger(flat)||Math.abs(flat)>10000)
    throw Error('Bonus fisso non valido');
   parts.push({name:String(bonus.origin_name||'Bonus'),notation:(flat>=0?'+':'')+flat,
    rolls:[],subtotal:flat,flat,kind:'flat'});
   continue;
  }
  const notation=String(bonus.dice||'').replaceAll(' ','');
  const match=notation.match(/^([1-9]\d*)d(4|6|8|10|12|20|100)([+-]\d+)?$/i);
  if(!match||Number(match[1])>100)throw Error('Dadi bonus non validi');
  const count=Number(match[1]),sides=Number(match[2]),flat=Number(match[3]||0);
  const rolls=Array.from({length:count},()=>{
   const value=die(sides);
   if(!Number.isInteger(value)||value<1||value>sides)throw Error('Risultato dado non valido');
   return value;
  });
  parts.push({name:String(bonus.origin_name||'Bonus'),notation,rolls,
   subtotal:rolls.reduce((sum,value)=>sum+value,flat),flat});
 }
 const total=parts.reduce((sum,row)=>sum+row.subtotal,base);
 const notation=sheetRollFormula(base,bonuses,mode);
 const detail=parts.map(row=>row.kind==='flat'?
   row.name+' [bonus fisso '+row.notation+'] = '+row.subtotal:
   row.name+' ['+row.rolls.join(', ')+']'+(row.flat?(row.flat>0?' + ':' − ')+Math.abs(row.flat):'')+' = '+row.subtotal).join(' · ')+
  ' · modificatore '+(base>=0?'+':'')+base+' · totale '+total;
 return {sides:20,count:rolls.length,modifier:base,rolls,total,notation,detail,parts};
}

// Apply an optional bonus to an already rolled outcome. Its d20 (and any
// advantage/disadvantage dice) are preserved: only the granted dice are rolled.
export function appendRollBonus(outcome={},bonus={},die){
 if(!Array.isArray(outcome.parts)||!outcome.parts.length||
    !Number.isSafeInteger(outcome.total)||typeof die!=='function')
   throw Error('Risultato del tiro non disponibile.');
 let part;
 if(Object.hasOwn(bonus,'flat_bonus')){
   const flat=Number(bonus.flat_bonus);
   if(!Number.isSafeInteger(flat)||Math.abs(flat)>10000)throw Error('Bonus fisso non valido');
   part={name:String(bonus.origin_name||'Bonus'),notation:(flat>=0?'+':'')+flat,
     rolls:[],subtotal:flat,flat,kind:'flat'};
 }else{
   const notation=String(bonus.dice||'').replaceAll(' ','');
   const match=notation.match(/^([1-9]\d*)d(4|6|8|10|12|20|100)([+-]\d+)?$/i);
   if(!match||Number(match[1])>100)throw Error('Dadi bonus non validi');
   const count=Number(match[1]),sides=Number(match[2]),flat=Number(match[3]||0);
   const rolls=Array.from({length:count},()=>{
     const value=die(sides);
     if(!Number.isInteger(value)||value<1||value>sides)throw Error('Risultato dado non valido');
     return value;
   });
   part={name:String(bonus.origin_name||'Bonus'),notation,rolls,
     subtotal:rolls.reduce((total,value)=>total+value,flat),flat};
 }
 // Typed bonus damage must retain its own damage type, rather than
 // silently inheriting the underlying weapon's damage type.
 if(bonus.damage_type){
   part.damage_type=String(bonus.damage_type);
   const typeName={force:'Forza',radiant:'Radiante',necrotic:'Necrotico',
     fire:'Fuoco',cold:'Freddo',lightning:'Fulmine',acid:'Acido',
     poison:'Veleno',psychic:'Psichico',thunder:'Tuono'}[part.damage_type]||part.damage_type;
   part.name+=' · '+typeName;
 }
 const total=outcome.total+part.subtotal;
 const addition=part.kind==='flat'?part.notation:'+'+part.notation;
 const note=part.kind==='flat'?
   part.name+' [bonus fisso '+part.notation+'] = '+part.subtotal:
   part.name+' ['+part.rolls.join(', ')+']'+
     (part.flat?(part.flat>0?' + ':' − ')+Math.abs(part.flat):'')+' = '+part.subtotal;
 const previousDetail=String(outcome.detail||'').replace(/ · totale -?\d+$/,'');
 return {...outcome,total,parts:[...outcome.parts,part],
   notation:String(outcome.notation||'')+addition,
   detail:previousDetail+' · '+note+' · totale '+total};
}

/** Roll an explicitly calculated weapon-damage formula, never evaluate arbitrary text. */
export function rollBattleDamage(formula,die){
 if(typeof die!=='function')throw Error('Generatore dadi non disponibile');
 const notation=String(formula||'').replace(/\s+/g,'');
 if(!notation||notation.length>120||!/^[+]?[0-9dD+\-]+$/.test(notation))
  throw Error('Formula danni non supportata');
 const terms=notation.match(/[+-]?[^+-]+/g)||[];
 if(!terms.length||terms.join('')!==notation||terms.length>24)throw Error('Formula danni non valida');
 let modifier=0,totalCount=0;
 const parts=[];
 for(const term of terms){
  const dice=term.match(/^\+?([1-9]\d*)d(2|3|4|6|8|10|12|20|100)$/i);
  if(dice){
   const count=Number(dice[1]),sides=Number(dice[2]);
   totalCount+=count;
   if(totalCount>100)throw Error('Troppi dadi nella formula');
   const rolls=Array.from({length:count},()=>die(sides));
   if(rolls.some(value=>!Number.isInteger(value)||value<1||value>sides))throw Error('Risultato dado non valido');
   parts.push({name:'Danni',notation:count+'d'+sides,rolls,subtotal:rolls.reduce((sum,value)=>sum+value,0)});
  }else if(/^[+-]?\d+$/.test(term)){
   modifier+=Number(term);
   if(!Number.isSafeInteger(modifier)||Math.abs(modifier)>9999)throw Error('Modificatore danni fuori limite');
  }else throw Error('Formula danni non supportata');
 }
 if(!parts.length)throw Error('La formula non prevede dadi da tirare');
 const rolls=parts.flatMap(part=>part.rolls);
 const total=parts.reduce((sum,part)=>sum+part.subtotal,modifier);
 return {sides:Number(parts[0].notation.split('d')[1]),count:rolls.length,modifier,rolls,total,
  notation,parts,detail:parts.map(part=>part.notation+' ['+part.rolls.join(', ')+'] = '+part.subtotal).join(' · ')+
   (modifier?' · modificatore '+(modifier>=0?'+':'')+modifier:'')+' · totale '+total};
}
/** Match the desktop DiceChatSync.valid_event protocol for combined dice rolls. */
export function sheetRollChatFields(result){
 const base={count:result.count,modifier:result.modifier,rolls:result.rolls,
   total:result.total,notation:result.notation,detail:result.detail};
 if(!Array.isArray(result.parts)||result.parts.length<=1)
  return {...base,die:'d'+result.sides};
 const terms=result.parts.map(part=>{
  const match=String(part.notation||'').match(/d([0-9]+)/i);
  const sides=Number(match?.[1]);
  if(!Number.isInteger(sides)||sides<2||sides>1000)throw Error('Dado del tiro non valido');
  return {count:part.rolls.length,sides,sign:1,rolls:[...part.rolls]};
 });
 const count=terms.reduce((n,row)=>n+row.count,0);
 if(count<1||count>100)throw Error('Il limite di condivisione è 100 dadi per tiro');
 return {...base,die:'formula',terms,count,
   modifier:Number(result.modifier)+result.parts.reduce((sum,row)=>sum+Number(row.flat||0),0)};
}
// A single readout contract is shared by every native-style section. Refresh
// only the outputs, leaving focused editors and pending user input in place.
export function calculatedValue(data,target,{signed:sign=false,suffix=""}={}){
  const value=data?.values?.[target];
  return (sign?signed(value):value??"—")+suffix;
}
export function formulaReadout(data,target,label,{signed:sign=false,suffix="",bonusTarget=target,scoreAbility='',showBonus=true}={}){
  const rollable=/^(?:ability_check:|ability_mod:|save:|skill:|attack_hit:|casting_hit:)/.test(target)||target==='initiative';
  const rollTarget=target.startsWith('ability_mod:')?'ability_check:'+target.slice('ability_mod:'.length):target;
  const act=scoreAbility||!rollable?'sheet-score-formula':'sheet-roll';
  const actualTarget=scoreAbility?'ability:'+scoreAbility:rollable?rollTarget:target;
  // The retired ± control used to jump into a general creature editor. Every
  // calculated number now opens its own origin-aware formula popup instead.
  return '<span class="sheet-formula"><button type="button" class="sheet-result'+
    (scoreAbility?' score-editor-trigger':'')+'" data-act="'+act+
    '" data-target="'+esc(actualTarget)+'" data-label="'+esc(label)+
    '" data-calculated="'+esc(target)+'" data-signed="'+sign+'" data-suffix="'+esc(suffix)+
    '" title="'+esc(data?.explanations?.[target]||label)+'" aria-label="'+esc(label)+'">'+
    esc(calculatedValue(data,target,{signed:sign,suffix}))+'</button>'+

    '</span>';
}
export function calculationNote(data,loadError=""){
  const warnings=[...new Set([...(data?.warnings||[]),...(loadError?[loadError]:[])])];
  return '<details class="calculation-note" data-calculation-note><summary>Calcoli e copertura della scheda</summary>'+
    '<p class="hint">Calcolato localmente sul dispositivo, anche offline.</p>'+
    (warnings.length?'<ul>'+warnings.map(w=>'<li>'+esc(w)+'</li>').join('')+'</ul>':'')+'</details>';
}
export function refreshCalculatedValues(root,data){
  const fastest=fastestMovement(data);
  for(const label of root.querySelectorAll('[data-fastest-movement-label]'))label.textContent=fastest.label;
  for(const output of root.querySelectorAll('[data-fastest-movement-value]'))output.dataset.calculated=fastest.key;
  for(const output of root.querySelectorAll('[data-calculated]')){
    output.textContent=calculatedValue(data,output.dataset.calculated,{
      signed:output.dataset.signed==='true',suffix:output.dataset.suffix||''});
    output.title=data.explanations?.[output.dataset.calculated]||'';
  }
}
export function localSheetView(section,data,loadError=""){
  if(!["info","stats","battle","magic"].includes(section))return "";
  const stats=data.stats||{},ability=data.abilities||{};
  const warnings=[...new Set([...(data.warnings||[]),...(loadError?[loadError]:[])])];
  const note='<p class="hint">Calcolato localmente sul dispositivo, anche offline. Nessuna scheda viene inviata al computer.</p>'+
    (warnings.length?'<details class="derived-warnings"><summary>'+warnings.length+
      ' aspetti non completamente supportati</summary><ul>'+warnings.map(s=>'<li>'+esc(s)+'</li>').join('')+'</ul></details>':'');
  let body="";
  if(section==="stats"){
    body='<h3>Caratteristiche e modificatori effettivi</h3>'+
      '<div class="derived-metrics">'+ABILITIES.map(id=>
        metric(id.toUpperCase(),signed(ability[id]?.modifier)+" · "+(ability[id]?.score??"—"))).join("")+
        metric("Bonus competenza",signed(stats.proficiency))+
        metric("Percezione passiva",stats.passive_perception??"—")+
        metric("Indagare passivo",stats.passive_investigation??"—")+'</div>'+
      '<details><summary>Tiri salvezza</summary><div class="derived-metrics">'+
        ABILITIES.map(id=>metric(id.toUpperCase(),signed(data.saves?.[id]))).join("")+
      '</div></details><details><summary>Abilità</summary><div class="derived-metrics">'+
        SKILLS.map(([id,name])=>metric(name,signed(data.skills?.[id]))).join("")+
      '</div></details>';
  }else if(section==="info"){
    body='<div class="derived-metrics">'+metric("Bonus competenza",signed(stats.proficiency))+
      metric("CA",stats.armor_class)+metric("Iniziativa",signed(stats.initiative))+
      metric("PF massimi",stats.max_hp)+metric("Camminata",(stats.speeds?.walk??"—")+" ft")+
      '</div>';
  }else if(section==="battle"){
    const speeds=stats.speeds||{};
    body='<div class="derived-metrics">'+metric("Classe armatura",stats.armor_class)+
      metric("Iniziativa",signed(stats.initiative))+metric("PF massimi",stats.max_hp)+
      metric("Percezione passiva",stats.passive_perception)+
      metric("Indagare passivo",stats.passive_investigation)+
      metric("Camminata",(speeds.walk??"—")+" ft")+
      ["climb","swim","fly","burrow"].filter(id=>speeds[id]>0).map(id=>
        metric(({climb:"Scalata",swim:"Nuoto",fly:"Volo",burrow:"Scavo"})[id],
        speeds[id]+" ft")).join("")+'</div>'+
      (stats.automatic_hp?.available?'<p class="hint">PF teorici da progressione classi: '+
        esc(stats.automatic_hp.value)+'</p>':'');
  }else if(section==="magic"){
    const slots=(data.spell_slots||[]).filter(x=>x.total>0||x.spent>0);
    body='<div class="derived-metrics">'+slots.map(s=>
      metric("Slot livello "+s.level,Math.max(0,s.total-s.spent)+" / "+s.total)).join("")+
      (data.pact_slots?.total>0?metric("Magia del Patto",
        (data.pact_slots.total-data.pact_slots.spent)+" / "+data.pact_slots.total+
        " · livello "+data.pact_slots.level):'')+'</div>'+
      (!slots.length&&!data.pact_slots?.total?'<p class="hint">Nessuno slot presente.</p>':'');
  }
  return '<section class="panel derived-local" data-local-sheet-calculations>'+
    '<h2>Valori calcolati sulla scheda</h2>'+note+body+'</section>';
}


// Display only recorded inventory data; instance overrides use the same resolver
// as the sheet's equipment calculations. Unknown weight/value stay unknown.
export function inventoryReadout(item={},propertyText='',spellScroll=false){
 const effective=resolveOwnedItem(item),kind=isDocument(item)?'document':spellScroll||String(effective.type||'').split('|')[0].toUpperCase()==='SC'?'scroll':itemKind(effective);
 const kinds={weapon:['Arma','weapon'],shield:['Scudo','shield'],armor:['Armatura','armor'],tool:['Strumento','proficiency'],magic:['Oggetto magico','spark'],document:['Documento','scroll'],scroll:['Pergamena','scroll'],other:['Oggetto','inventory']};
 const [type,glyph]=kinds[kind]||kinds.other;
 const numeric=value=>(typeof value==='number'||typeof value==='string')&&value!==null&&value!==undefined&&String(value).trim()!==''&&Number.isFinite(Number(value))&&Number(value)>=0?Number(value):null;
 const quantity=Math.max(1,Math.floor(Number(item.quantity)||1));
 const weight=numeric(effective.weight),gp=numeric(effective.value_gp),copper=numeric(effective.value);
 const value=gp??(copper===null?null:copper/100);
 const format=value=>Number(value.toFixed(2)).toLocaleString('it-IT');
 const facts=[];
 if(kind==='scroll'){const level=numeric(effective.spell_level??effective.spellLevel??effective.level);if(level!==null)facts.push({label:'Incantesimo',value:level===0?'Trucchetto':level+'° livello',glyph:'spark'});}
 if(kind==='weapon'&&effective.damage)facts.push({label:'Danno',value:String(effective.damage)+(effective.damage_type?' '+effective.damage_type:''),glyph:'weapon'});
 if(effective.ac!==null&&effective.ac!==undefined){const ac=typeof effective.ac==='object'?effective.ac.base:effective.ac;if(ac!==null&&ac!==undefined&&String(ac)!=='')facts.push({label:'CA',value:(kind==='shield'?'+':'')+ac,glyph:'shield'});}
 if(kind==='armor')facts.push({label:'Destrezza alla CA',value:armorDexterityLabel(effective),glyph:'shield'});
 if(effective.range)facts.push({label:'Gittata',value:effective.range+' ft',glyph:'target'});
 if(weight!==null)facts.push({label:quantity>1?'Peso totale':'Peso',value:format(weight*quantity)+' lb',glyph:'inventory'});
 if(value!==null)facts.push({label:quantity>1?'Valore totale':'Valore',value:format(value*quantity)+' mo',glyph:'coins'});
 const slots={main:'Mano principale',off:'Mano secondaria',body:'Indossato'};
 const status=(Array.isArray(item.equipped_slots)?item.equipped_slots:[]).map(slot=>slots[slot]||slot);
 if(item.equipped&&!status.length&&['weapon','armor','shield'].includes(kind))status.push('Equipaggiato');
 const attuned=requiresAttunement(effective)?itemAttunementCount(item):item.attuned?1:0;
 if(attuned)status.push('In sintonia'+(attuned>1?' ×'+attuned:''));else if(requiresAttunement(effective))status.push('Richiede sintonia');
 if(item.active===false)status.push('Disattivato');
 if(item.infusion)status.push('Infuso');
 const properties=String(propertyText==='—'?'':propertyText||'').split(' · ').filter(part=>
   !(facts.some(fact=>fact.label==='CA')&&/^CA(?:\s|\+|$)/i.test(part))).join(' · ');
 return {kind,type,glyph,quantity,displayName:ownedItemDisplayName(item),
   source:String(item.source||''),properties,facts,status,
  weight:kind==='document'?null:weight===null?null:weight*quantity,value:kind==='document'?null:value===null?null:value*quantity};
}

// Share one power identity and resource grouping between structured class actions,
// activated catalog abilities and origin-granted spells. Catalog powers own the
// detail popup; a native class action supplies a fallback when no catalog row exists.
const powerName=value=>String(value||'').normalize('NFKD').replace(/[\u0300-\u036f]/g,'')
 .trim().toLocaleLowerCase('it').replace(/\s+/g,' ');
const powerIdentity=power=>{
 const id=String(power.ability_id||power.id||power.rule_action_id||power.class_feature_id||'');
 const name=powerName(power.name);
 if(id==='vtt_wild_shape'||id==='wild_shape'||name==='wild shape'||name==='forma selvatica')return 'wild_shape';
 return name;
};
// Persistent self-effects are explicit: never turn a condition inflicted on a
// target into a toggle on the actor. Native class-feature activations and
// explicitly typed self/toggle powers have reversible sheet state.
export function persistentBattleAbility(row={}){
 const power=row.power||{},action=row.classAction||{};
 if(power.persistent_key||action.persistent_key||action.mode==='trait_state'||['rage','reckless_attack','innate_sorcery','patient_defense','step_of_the_wind'].includes(action.class_feature_id)||
   power.id==='vtt_wild_shape'||action.rule_action_id==='wild_shape')return true;
 const sources=[power,action],isSelf=field=>['self','actor','owner','caster'].includes(String(field||'').toLowerCase());
 return sources.some(source=>{
  if(source.toggleable===true||source.persistent===true||
     ['toggle','sustained'].includes(String(source.activation_mode||'').toLowerCase()))return true;
  const effect=source.effect||source.effects;
  const typed=Array.isArray(effect)?effect:[effect];
  return typed.some(e=>e&&typeof e==='object'&&
   (e.kind==='condition'||e.type==='condition'||e.condition)&&
   isSelf(e.target||source.target));
 });
}
// Resolve actual casting times from structured spell data, including non-combat
// times (e.g. 1 minute) rather than a generic "Secondo il privilegio".
export function spellCastingTimeLabel(spell){
 const raw=Array.isArray(spell?.time)?spell.time[0]:spell?.time??spell?.casting_time;
 if(raw==null||raw==='')return '';
 const original=typeof raw==='object'?raw.unit??raw.type??raw.name:raw;
 const text=String(original||'').trim().toLocaleLowerCase('it').replace(/[_-]/g,' ').replace(/\s+/g,' ');
 const parsed=text.match(/^(\d+)\s+(.+)$/);
 const number=Math.max(1,Number(raw?.number??(parsed?parsed[1]:1))||1);
 const unit=(parsed?parsed[2]:text).trim();
 const forms={
  action:['Azione','azioni'],azione:['Azione','azioni'],
  bonus:['Azione bonus','azioni bonus'],'bonus action':['Azione bonus','azioni bonus'],
  'azione bonus':['Azione bonus','azioni bonus'],
  reaction:['Reazione','reazioni'],reazione:['Reazione','reazioni'],
  free:['Azione gratuita','azioni gratuite'],
  minute:['minuto','minuti'],minutes:['minuto','minuti'],minuto:['minuto','minuti'],minuti:['minuto','minuti'],
  hour:['ora','ore'],hours:['ora','ore'],ora:['ora','ore'],ore:['ora','ore'],
  round:['round','round'],rounds:['round','round'],
  day:['giorno','giorni'],days:['giorno','giorni']
 };
 const found=forms[unit];
 if(!found)return String(original||'').trim();
 return number===1?found[0]:number+' '+found[1];
}
const spellActionTime=spell=>{
 const raw=Array.isArray(spell?.time)?spell.time[0]:spell?.time??spell?.casting_time;
 const value=typeof raw==='object'&&raw?raw.unit||raw.type||raw.name:raw;
 const key=String(value||'').trim().toLowerCase().replaceAll('_',' ');
 const unit=key.replace(/^\d+\s+/,'');
 if(Number(raw?.number??1)!==1)return 'contextual';
 return ({action:'action',bonus:'bonus','bonus action':'bonus',reaction:'reaction',free:'free',
  azione:'action','azione bonus':'bonus',reazione:'reaction'})[unit]||'contextual';
};

// Every tracker-linked bonus uses one projection in the Resources tab, whether
// it is a flat modifier, a bonus die, or an attack-specific extra damage die.
// Sources must still be enabled and their tracker must exist.
export function trackerRollBonusRows(record={},calculated={}){
 const trackers=new Set((calculated.trackers||[]).filter(t=>!t.disabled).map(t=>t.id));
 const enabled=row=>!row.disabled&&record.origin_enabled?.[row.origin_id]!==false&&
  !(record.proficiency_origins||[]).some(origin=>origin?.id===row.origin_id&&origin.disabled);
 const classes=classFeatureRollResourceBonuses(record,calculated);
 const attacks=(calculated.trait_state_optional_dice||[]).map(row=>({
  ...row,name:row.name||row.origin_name||'Danno aggiuntivo',
  targets:['attack_damage:'+row.attack_id]}));
 const user=[...(record.dice_bonuses||[]),...(record.formula_bonuses||[])]
  .filter(row=>row?.tracker_id&&enabled(row))
  .flatMap(row=>{
   const dice=String(row.dice||'').trim(),flat=Number(row.flat_bonus??row.expression);
   if(!dice&&!Number.isFinite(flat))return [];
   return [{...row,name:row.name||row.origin_name||'Bonus',
    targets:Array.isArray(row.targets)?row.targets:[row.target],
    ...(dice?{dice}:{flat_bonus:flat})}];
  });
 const seen=new Set();
 return [...classes,...attacks,...user].filter(row=>{
  if(!row.tracker_id||!trackers.has(row.tracker_id)||!enabled(row))return false;
  const key=[row.tracker_id,row.id||row.name,row.dice||row.flat_bonus,(row.targets||[]).join('|')].join('::');
  if(seen.has(key))return false;
  seen.add(key);return true;
 });
}
export function trackerRollBonusTargets(row={},calculated={}){
 const labels={
  ability_check:'Prove di caratteristica',saving_throw:'Tiri salvezza',
  attack_roll:'Tiri per colpire',damage_roll:'Tiri per i danni',
  any_d20:'Tiri d20',initiative:'Iniziativa',
  spell_attack:'Attacchi con incantesimi',spell_damage:'Danni degli incantesimi'
 };
 const values=(Array.isArray(row.targets)?row.targets:[row.target]).filter(Boolean);
 const display=target=>{
  if(labels[target])return labels[target];
  if(target.startsWith('attack_damage:')||target.startsWith('attack_hit:')){
   const attack=(calculated.attacks||[]).find(a=>a.id===target.split(':').slice(1).join(':'));
   return (target.startsWith('attack_damage:')?'Danni':'Tiri per colpire')+
    (attack?' · '+attack.name:' · attacco');
  }
  if(target.startsWith('save:'))return 'TS '+target.slice(5).toUpperCase();
  if(target.startsWith('skill:'))return 'Prova · '+target.slice(6);
  if(target.startsWith('ability_check:')||target.startsWith('ability_mod:'))
   return 'Prova '+target.split(':')[1].toUpperCase();
  return target.replaceAll('_',' ');
 };
 return [...new Set(values.map(display))].join(' · ')||'Tiro specificato dal tratto';
}

export function battleResourcePowers(calculated={},classAbilities=[],activated=[],spells=[]){
 const trackers=(calculated.trackers||[]).filter(row=>!row.disabled);
 const keyFor=(cost,trackerId)=>{
  if(!cost)return 'free';
  return trackers.some(t=>String(t.id)===String(trackerId||''))?'tracker:'+trackerId:'missing';
 };
 const rows=[];
 for(const power of activated){
  if(!power?.id||power.action_type==='passive'||power.activation_mode==='passive')continue;
  const cost=Math.max(0,Number(power.resource_cost??(power.tracker_id?1:0))||0);
  rows.push({kind:'ability',source:'activated',id:'activated:'+power.id,name:power.name,
   tracker_id:power.tracker_id||'',cost,key:keyFor(cost,power.tracker_id),
   timing:power.action_type||power.activation_mode||'contextual',power});
 }
 for(const action of classAbilities){
  // Armor Model choices now belong to their dedicated Powers panel, not the
  // generic combat-action resources. Their mechanics remain native/data-driven.
  if(action.mode==='trait_state'&&String(action.state_id||'').startsWith('armor_model:'))continue;
  const id=String(action.id||action.ability_id||action.name||'');
  // The native action projector can describe a granted class action twice
  // (once as an action grant and once as its structured feature).
  const repeated=rows.some(row=>row.source==='class'&&(
   row.id===id||(powerIdentity(row.classAction)===powerIdentity(action)&&
    String(row.tracker_id||'')===String(action.tracker_id||''))));
  if(repeated)continue;
  const cost=Math.max(0,Number(action.cost??0)||0);
  const identity=powerIdentity(action);
  const same=action.mode==='trait_state'?null:rows.find(row=>row.kind==='ability'&&row.source==='activated'&&(
   (identity==='wild_shape'&&powerIdentity(row.power)==='wild_shape')||
   (action.origin_id&&row.power.feature_id===action.origin_id)||
   (identity&&identity===powerIdentity(row.power)&&
    String(row.tracker_id||'')===String(action.tracker_id||''))));
  if(same){
   // When the action has more accurate resource metadata, keep one catalog
   // detail row, but use the native power's resolved cost and tracker.
   if(action.tracker_id&&!same.tracker_id){
    same.tracker_id=action.tracker_id;
    same.cost=cost;
    same.key=keyFor(cost,action.tracker_id);
   }
   if(!same.classAction?.class_feature_id||action.class_feature_id)same.classAction=action;
   if(action.time&&action.time!=='contextual')same.timing=action.time;
   continue;
  }
  rows.push({kind:'ability',source:'class',id,name:action.name,
   tracker_id:action.tracker_id||'',cost,key:keyFor(cost,action.tracker_id),
   timing:action.time||'contextual',classAction:action});
 }
 for(const grant of calculated.origin_spells||[]){
  if(!grant?.id||!grant.spell_id)continue;
  const mode=grant.payment_mode||(grant.tracker_id?'tracker':'free');
  if(mode==='slot')continue;
  const cost=mode==='tracker'?Math.max(1,Number(grant.tracker_cost)||1):0;
  const spell=spells.find(row=>row.id===grant.spell_id);
  rows.push({kind:'spell',id:String(grant.id),name:spell?.name||grant.name||grant.spell_name||grant.spell_id,
   tracker_id:grant.tracker_id||'',cost,key:mode==='tracker'?keyFor(cost,grant.tracker_id):'free',
   timing:spellActionTime(spell),
   casting_time_label:spellCastingTimeLabel(spell)||spellCastingTimeLabel(grant)||'Tempo non specificato',grant});
 }
 return rows;
}

// A subclass trait that owns a tracker is usable even if its effects are not
// automated. Its payment is user-confirmed, allowing pooled/variable costs.
// No tracker and no modeled action means no Resources entry.
export function resourceLinkedSubclassTrait(tracker={},features=[],powers=[]){
 const id=String(tracker.origin_id||'');
 if(tracker.disabled||!id.startsWith('feature:class|')||!id.includes('|subclass|'))return null;
 if(powers.some(row=>row.kind==='ability'&&row.tracker_id===tracker.id))return null;
 const feature=features.find(row=>row.origin_id===id&&!row.disabled&&!row.inactive);
 return feature?{origin_id:id,name:feature.name,tracker_id:tracker.id}:null;
}

// Validate the source again when the confirmation is submitted, never trust
// the DOM's tracker ID or its previously rendered available uses.
export function subclassTrackerUsePatch(record={},calculated={},trackerId='',originId='',amount=1){
 const tracker=(calculated.trackers||[]).find(t=>String(t.id)===String(trackerId));
 const linked=tracker&&resourceLinkedSubclassTrait(tracker,calculated.features||[]);
 if(!linked||linked.origin_id!==originId||record.rules_version==='2024')
  throw Error('Capacità della sottoclasse non disponibile.');
 return spendTrackerUses(record,tracker.id,amount,calculated.trackers);
}

// Play presentation reuses the existing editors and delegated actions. Only
// transient layout state lives here; rules, storage and payment stay unchanged.
export function isPersistentSpell(spell){
 if(spell?.has_duration===true)return true;
 if(spell?.has_duration===false)return false;
 const raw=spell?.duration;
 if(Array.isArray(raw))return raw.some(row=>typeof row==='object'&&row!==null?row.type!=='instant':typeof row==='string'&&!/instant|istantan/i.test(row));
 if(raw&&typeof raw==='object')return raw.type!=='instant';
 return typeof raw==='string'&&!!raw.trim()&&!/instant|istantan/i.test(raw);
}
export function mountPlaySheet(app,{creature:c,calculated:d,sheet,view={},icon,conditionLabel,conditionCatalog=null,inventoryProperties=()=>'',isSpellScroll=()=>false,spells=[],classActions=[]}){
 const root=app.querySelector('[data-local-sheet-calculations]');
 if(!root||sheet==='json')return new Map();
 const bank=document.createElement('div');bank.className='sheet-editor-bank';bank.hidden=true;
 while(root.firstChild)bank.append(root.firstChild);
 root.append(bank);
 const sources=new Map();
 const bind=(key,node)=>{if(node){if(!node.isConnected)bank.append(node);node.dataset.playSource=key;sources.set(key,node);}return key;};
 const target=(key,selector)=>bind(key,bank.querySelector(selector));
 const btn=(title,glyph,attrs='',content='')=>'<button type="button" class="play-button" '+attrs+' aria-label="'+esc(title)+'" title="'+esc(title)+'">'+(glyph?icon(glyph):'')+(content||'<span>'+esc(title)+'</span>')+'</button>';
 const edit=(key,title,glyph='settings')=>btn(title,glyph,'data-act="sheet-context" data-sheet-context="'+esc(key)+'"','<span class="sr-only">'+esc(title)+'</span>');
 const go=(key,title,glyph,subtitle='',trailing='')=>'<button type="button" class="play-list-row" data-act="sheet-context" data-sheet-context="'+esc(key)+'">'+(glyph?icon(glyph):'')+'<span class="play-row-copy"><strong>'+esc(title)+'</strong>'+(subtitle?'<small>'+esc(subtitle)+'</small>':'')+'</span>'+(trailing?'<span class="play-row-end">'+trailing+'</span>':'<span class="play-chevron" aria-hidden="true">›</span>')+'</button>';
 const proxy=(node,title,glyph,content='',className='')=>{
  if(!node)return '';
  const key='proxy:'+sources.size;bind(key,node);
  return btn(title,glyph,'data-act="sheet-proxy" data-sheet-source="'+key+'"'+(node.disabled?' disabled':''),content);
 };
 const card=(title,body,tools='',extra='',attrs='')=>'<section class="play-card '+extra+'"'+(attrs?' '+attrs:'')+'><header class="play-card-head"><h2>'+esc(title)+'</h2>'+tools+'</header>'+body+'</section>';
 const output=(key,sign=false,suffix='')=>'<output data-calculated="'+esc(key)+'" data-signed="'+sign+'" data-suffix="'+esc(suffix)+'">'+esc(calculatedValue(d,key,{signed:sign,suffix}))+'</output>';
 const scoreOutput=(key,label,sign=false,suffix='')=>'<button type="button" class="play-score-value" data-act="sheet-score-formula" data-target="'+esc(key)+'" data-label="'+esc(label)+'" data-calculated="'+esc(key)+'" data-signed="'+sign+'" data-suffix="'+esc(suffix)+'" aria-label="Formula: '+esc(label)+'">'+esc(calculatedValue(d,key,{signed:sign,suffix}))+'</button>';
 const val=(key)=>'<span data-read-field="'+key+'">'+esc(c[key]??0)+'</span>';
 const roll=(key,label,body,glyph='')=>btn(label,glyph,'data-act="sheet-roll" data-target="'+esc(key)+'" data-label="'+esc(label)+'"',body||output(key,true));
 const heading=(node)=>node?.querySelector(':scope > h2')?.textContent.trim()||'';
 const panels=[...bank.querySelectorAll(':scope > .panel')];
 panels.forEach((node,i)=>bind('panel:'+i,node));
 const panelNamed=(name)=>panels.find(node=>heading(node).includes(name));
 const infused=activeInfusions(c,d.infusion_catalog||[],d.features||[]);
 const availableConditions=conditionOptions(conditionCatalog,c.rules_version,c.conditions||[]);
 const activeConditions=availableConditions.filter(row=>row.id!=='exhaustion'&&
   (c.conditions||[]).includes(row.id));
 const currentExhaustion=exhaustionLevel(c);
 if(currentExhaustion){
   const exhaustionSource=availableConditions.find(row=>row.id==='exhaustion');
   activeConditions.push(exhaustionConditionRows(c.rules_version,exhaustionSource)[currentExhaustion-1]);
 }
 for(const row of activeConditions){
  const detail=document.createElement("section");
  detail.innerHTML=conditionDescriptionHtml(row);
  bind("condition:"+row.id,detail);
 }
 const list=(title,rows,empty='Nessuna voce.')=>card(title,rows||'<p class="play-empty">'+esc(empty)+'</p>');
 let html='';
 if(sheet==='battle'){
  target('hp','.battle-hp-panel');target('defense','.battle-defense-panel');target('movement','.battle-movement-panel');
  // Both battle entry points display the exact same editor and computed AC.
  bind('equipment',bank.querySelector('.battle-defense-panel'));
  const max=Math.max(1,Number(d.values?.hp)||1),hp=Number(c.current_hp)||0;
  html='<section class="play-health" role="button" tabindex="0" data-act="hp-adjust-open" aria-label="Gestisci punti ferita"><header><span>Punti ferita</span><div class="play-health-tools">'+btn('Riposi e recuperi','rest_short','data-act="sheet-context" data-sheet-context="rests"','<span>Riposi</span>')+'</div></header><div class="play-hp-number"><span class="play-hp-reading">'+val('current_hp')+'<small> / '+output('hp')+'</small></span></div><progress data-hp-progress value="'+hp+'" max="'+max+'" aria-label="Punti ferita rimanenti"></progress><div class="play-health-extra"><span>Temporanei <b>'+val('temporary_hp')+'</b></span></div></section>';
  const fastest=fastestMovement(d);
  const vital=(context,title,glyph,label,key,suffix='',fastestLabel=false)=>
    '<div class="play-button play-vital-card">'+
      '<button type="button" class="play-vital-manage" data-act="sheet-context" data-sheet-context="'+context+'" aria-label="Gestisci '+esc(title)+'" title="Gestisci '+esc(title)+'">'+icon(glyph)+
      '<small'+(fastestLabel?' data-fastest-movement-label':'')+'>'+esc(label)+'</small></button>'+
      scoreOutput(key,title,false,suffix).replace(' data-calculated=',
        (fastestLabel?' data-fastest-movement-value':'')+' data-calculated=')+
    '</div>';
  html+='<div class="play-vitals">'+
    vital('defense','Classe armatura','shield','CA','ac')+
    roll('initiative','Iniziativa','<small>Iniziativa</small>'+output('initiative',true),'lightning')+
    vital('movement','Movimento e velocità','dash',fastest.label,fastest.key,' ft',true)+'</div>';
  const appliedSpells=(c.proficiency_origins||[]).filter(row=>row?.group==='spell'&&String(row.id||'').startsWith('spell:')&&!row.disabled&&c.origin_enabled?.[row.id]!==false);
  const activeAbilities=Object.entries(c.active_class_features||{});
  const statusTag=(key,label,glyph='')=>'<button type="button" class="play-status-tag" data-act="state-trait-jump" data-state-trait="'+esc('state|'+key)+'" title="'+esc(label)+'">'+glyph+esc(label)+'</button>';
  html+='<div class="play-status-strip">'+btn('Condizioni, incantesimi e capacità','condition','data-act="sheet" data-sheet="conditions"','<span>Stati</span>')+
   activeConditions.map(({id,label})=>statusTag('condition:'+id,label)).join('')+
   appliedSpells.map(row=>statusTag(String(row.id),String(row.name||row.id).replace(/^Incantesimo · /,''),'✦ ')).join('')+
   activeAbilities.map(([key,value])=>statusTag(key,value?.name||key,'✧ ')).join('')+
   infused.map(row=>statusTag('infusion:'+row.id,row.name,'✦ ')).join('')+'</div>';
  const rest=document.createElement('div');
  rest.innerHTML='<div class="play-rest-choices">'+
    [['tracker-short','rest_short','Riposo breve'],['tracker-long','rest_long','Riposo lungo'],['tracker-turn','reset','Inizio turno']].map(([a,g,l])=>btn(l,g,'data-act="'+a+'"')).join('')+
    '</div>';
  bind('rests',rest);
  // Link each tracker to the exact power group exposed by the spell/ability
  // editor, and offer direct ability details in the collapsible list.
  const powerGroups=new Map();
  for(const wrapper of bank.querySelectorAll('[data-battle-power-group]')){
   const key=wrapper.dataset.battlePowerGroup,source=wrapper.querySelector('.magic-tracker-panel');
   if(!source)continue;
   bind('power-resource:'+key,source);
   const abilities=[...source.querySelectorAll('.magic-ability-entry')].map(node=>{
    const id=node.dataset.abilityId,detailKey='power-ability:'+id;
    bind(detailKey,node.cloneNode(true));
    return {key:detailKey,id,name:node.querySelector('.magic-ability-name')?.textContent||id,
      info:node.querySelector('.power-privilege-meta')?.textContent||''};
   });
   powerGroups.set(key,abilities);
  }
  const powerRows=battleResourcePowers(d,view.battleActions?.abilityEntries||[],view.battleAbilities||[],view.battleSpells||spells);
  const rollBonuses=trackerRollBonusRows(c,d);
  const bonusRows=trackerId=>rollBonuses.filter(row=>row.tracker_id===trackerId).map(row=>{
   const value=Object.hasOwn(row,'flat_bonus')?String(Number(row.flat_bonus)>=0?'+':'')+row.flat_bonus:'+'+row.dice;
   const originId=row.origin_id||'';
   const content='<span><strong>'+esc(value+' · '+(row.name||'Bonus'))+'</strong><small>'+esc(trackerRollBonusTargets(row,d))+'</small></span>';
   return '<div class="play-resource-power-row play-resource-bonus-row" data-roll-bonus-id="'+esc(row.id||row.name||'')+'">'+
    (originId?'<button type="button" class="play-resource-power-open" data-act="power-trait" data-origin-id="'+esc(originId)+'" aria-label="Apri il tratto di origine del bonus">'+icon('proficiency')+content+'</button>':
      '<span class="play-resource-power-open">'+icon('proficiency')+content+'</span>')+'</div>';
  }).join('');
  const traits=view.battleTraits||[];
  const cleanOrigin=id=>String(id||'').replace(/^feature:/,'');
  const featureFor=(ids=[],name='')=>{
   const candidates=ids.map(cleanOrigin).filter(Boolean);
   for(const id of candidates){
    const exact=traits.filter(feature=>[feature.origin_id,feature.feature_key]
      .some(value=>value&&cleanOrigin(value)===id));
    if(exact.length===1)return exact[0];
   }
   const parent=traits.filter(feature=>feature.origin_key&&candidates.includes(cleanOrigin(feature.origin_key)));
   if(parent.length===1)return parent[0];
   const normalized=powerName(name);
   const named=normalized?traits.filter(feature=>powerName(feature.name)===normalized):[];
   return named.length===1?named[0]:null;
  };
  const timeLabels={action:'Azione',bonus:'Azione bonus',reaction:'Reazione',free:'Azione gratuita',
    movement:'Movimento',contextual:'Secondo il privilegio'};
  // A resource popup must keep its original counters and editors, while also
  // presenting the real originating trait and a full reset.
  for(const tracker of d.trackers||[]){
   if(tracker.disabled)continue;
   const key='tracker:'+tracker.id,source=sources.get(powerGroups.has(key)?'power-resource:'+key:'resource:'+tracker.id)||
     [...bank.querySelectorAll('.battle-resource-row')].find(node=>node.querySelector('[data-tracker-id]')?.dataset.trackerId===tracker.id);
   if(!source)continue;
   const origin=featureFor([tracker.origin_id,tracker.origin_feature_key],tracker.origin_name);
   const originId=origin?.origin_id||tracker.origin_id||'';
   const label=origin?.name||tracker.origin_name||'';
   const detail='<section class="play-resource-origin-details">'+
     (label?'<div class="play-resource-origin-facts"><span>Tratto di origine</span><strong>'+esc(label)+'</strong></div>':'')+
     (origin?.description?'<p class="trait-description">'+esc(origin.description)+'</p>':'')+
     (originId?'<button type="button" class="play-button power-origin-link" data-act="power-trait" data-origin-id="'+esc(originId)+'">'+icon('proficiency')+'<span>Apri il tratto di origine</span></button>':'')+
     '<button type="button" class="play-resource-reset" data-act="tracker-reset" data-tracker-id="'+esc(tracker.id)+'"'+
     (Number(tracker.spent||0)===0?' disabled':'')+'>Ripristina tutti gli utilizzi</button></section>';
   source.insertAdjacentHTML('beforeend',bonusRows(tracker.id)+detail);
  }
  const abilityButtons=(key,filtered=null)=>(filtered||powerRows.filter(row=>row.key===key))
   .filter(row=>!row.classAction?.roll_bonus).map(row=>{
   const tracker=(d.trackers||[]).find(t=>String(t.id)===String(row.tracker_id));
   const available=tracker?Math.max(0,Number(tracker.max||0)-Number(tracker.spent||0)):0;
   // Abilities can confirm "Nessun tracker" even if their resource is spent.
   // Spells still require the normal resource check.
   const disabled=row.kind==='spell'&&row.cost>0&&
    (!tracker||tracker.disabled||available<row.cost);
   const glyph=icon(row.kind==='spell'?'spell_cast':
     actionGlyphKey({...row.classAction,...row.power,name:row.name,type:'Capacità'}));
   const caption=row.kind==='spell'?row.casting_time_label:
     (timeLabels[row.timing]||row.timing||'Secondo il privilegio');
   const note=row.kind==='spell'?(row.cost>1?' · Costo '+row.cost:''):
     (row.cost?' · Costo '+row.cost:'');
   if(row.kind==='spell')return '<div class="play-resource-power-row" data-power-spell-id="'+esc(row.id)+'">'+
    '<button type="button" class="play-resource-power-open" data-act="power-spell" data-spell-key="origin" data-grant-id="'+esc(row.id)+'"'+
    ' aria-label="Dettagli '+esc(row.name)+'">'+glyph+'<span><strong>'+esc(row.name)+'</strong><small>'+esc(caption+note)+'</small></span></button>'+
    '<button type="button" class="play-resource-use" data-act="battle-cast-resource-spell" data-grant-id="'+esc(row.id)+'"'+(disabled?' disabled':'')+
    ' aria-label="Lancia '+esc(row.name)+'">Lancia</button></div>';
   const id=row.id,action=row.classAction||{},power=row.power||{};
   const trait=featureFor([power.feature_id,power.origin_id,action.origin_id,action.feature_id],
     action.feature||row.name);
   const originId=trait?.origin_id||power.feature_id||power.origin_id||action.origin_id||'';
   const originLabel=trait?.name?'Tratto · '+trait.name:
     power.origin_name||action.origin_name||power.origin||action.origin_id||'';
   const description=trait?.description||power.description||action.description||'';
   const detail=document.createElement('section');
   detail.className='panel play-battle-power-detail';
   detail.innerHTML='<h2>'+esc(row.name)+'</h2>'+
    '<dl class="power-privilege-facts">'+
     '<div><dt>Origine</dt><dd>'+esc(originLabel||'Non specificata')+'</dd></div>'+
     '<div><dt>Attivazione</dt><dd>'+esc(caption)+'</dd></div>'+
     (row.cost?'<div><dt>Costo</dt><dd>'+esc(row.cost+' utilizzi'+(tracker?' · '+tracker.name:''))+'</dd></div>':'')+'</dl>'+
    (description?'<div class="power-privilege-description"><h3>Descrizione del tratto</h3><p class="trait-description">'+esc(description)+'</p></div>':'')+
    (originId?'<button type="button" class="play-button power-origin-link" data-act="power-trait" data-origin-id="'+esc(originId)+'">'+icon('proficiency')+'<span>Apri il tratto di origine</span></button>':'');
   const powerDetail=(powerGroups.get(key)||[]).find(ability=>row.power&&String(ability.id)===String(power.id));
   const context=bind(powerDetail?.key||'battle-power:'+id,detail);
   const persistent=persistentBattleAbility(row);
   const statusKey=power.id==='vtt_wild_shape'||action.rule_action_id==='wild_shape'?'wild_shape':
     power.persistent_key||action.persistent_key||action.class_feature_id||'battle:'+String(id);
   const active=persistent&&(
    !!c.active_class_features?.[statusKey]||action.mode==='trait_state'&&action.active===true);
   const use=persistent?'Attiva':'Usa';
   const useId=persistent&&action.class_feature_id&&action.id?action.id:id;
   return '<div class="play-resource-power-row" data-ability-id="'+esc(id)+'">'+
    '<button type="button" class="play-resource-power-open" data-act="sheet-context" data-sheet-context="'+esc(context)+'"'+
    ' aria-label="Dettagli '+esc(row.name)+'">'+glyph+'<span><strong>'+esc(row.name)+'</strong>'+
    '<small>'+esc(caption+note)+'</small></span></button>'+
    (active?'<button type="button" class="play-resource-use play-resource-use--active" data-act="condition-remove-ability" data-ability-key="'+esc(statusKey)+'"'+
    ' aria-label="Disattiva '+esc(row.name)+'">Disattiva</button>':
    '<button type="button" class="play-resource-use" data-act="battle-use-ability" data-ability-id="'+esc(useId)+'"'+
    (persistent?' data-persistent-key="'+esc(statusKey)+'"':'')+
    (disabled?' disabled':'')+' aria-label="'+esc(use+' '+row.name)+'">'+esc(use)+'</button>')+'</div>';
  }).join('');
  const resources=(d.trackers||[]).filter(t=>!t.disabled).map(t=>{
   const left=Math.max(0,t.max-t.spent),key='tracker:'+t.id;
   const source=[...bank.querySelectorAll('.battle-resource-row')].find(node=>node.querySelector('[data-tracker-id]')?.dataset.trackerId===t.id);
   bind('resource:'+t.id,source);
   const context=powerGroups.has(key)?'power-resource:'+key:'resource:'+t.id;
   const linked=resourceLinkedSubclassTrait(t,d.features||[],powerRows);
   const reference=linked?'<div class="play-resource-power-row" data-linked-subclass-resource="'+esc(t.id)+'">'+
    '<button type="button" class="play-resource-power-open" data-act="power-trait" data-origin-id="'+esc(linked.origin_id)+'"'+
    ' aria-label="Apri il tratto '+esc(linked.name)+'">'+icon('proficiency')+
    '<span><strong>'+esc(linked.name)+'</strong><small>Capacità di sottoclasse · '+esc(trackerRecoveryText(t))+'</small></span></button>'+
    '<button type="button" class="play-resource-use" data-act="tracker-trait-use" data-tracker-id="'+esc(t.id)+'"'+
    ' data-origin-id="'+esc(linked.origin_id)+'"'+/* Alternative slot payments may be available even with zero tracker uses.
      The activation dialog validates eligibility and available resources. */''+
    ' aria-label="Usa '+esc(linked.name)+'">Usa</button></div>':'';
   return '<div class="play-resource-group" data-resource-tracker="'+esc(t.id)+'"><div class="play-resource"><button class="play-resource-info" type="button" data-act="sheet-context" data-sheet-context="'+esc(context)+'" aria-label="Gestisci '+esc(t.name)+'">'+
    '<span class="play-resource-copy"><strong class="play-resource-name">'+esc(t.name)+'</strong><small class="play-resource-recovery">'+esc(trackerRecoveryText(t))+'</small></span>'+
    '<span class="play-resource-count">'+left+' <small>/ '+esc(t.max)+'</small></span></button>'+
    '</div>'+bonusRows(t.id)+abilityButtons(key)+reference+'</div>';
  }).join('');
  // Unlimited abilities belong to their granting trait rather than to a
  // fictitious free-use tracker. Keep paid powers under their real trackers.
  const freeByTrait=new Map();
  for(const row of powerRows.filter(row=>row.key==='free')){
   const action=row.classAction||{},power=row.power||{},grant=row.grant||{};
   const originId=grant.origin_id||power.feature_id||power.origin_id||
    action.origin_id||action.feature_id||'';
   const trait=featureFor([originId],action.feature_name||row.name);
   const key=trait?.origin_id||originId||'unattributed:'+row.id;
   if(!freeByTrait.has(key))freeByTrait.set(key,{
    id:key,name:trait?.name||grant.origin_name||power.origin_name||
     action.feature_name||row.name,rows:[]});
   freeByTrait.get(key).rows.push(row);
  }
  const privilegeGroup=(id,title,body,sourceId='',status='Privilegio')=>
   '<div class="play-resource-ungrouped play-resource-privilege" data-resource-privilege="'+esc(id)+'">'+
    '<div class="play-resource"><span class="play-resource-copy">'+
     '<strong class="play-resource-name">'+esc(title)+'</strong>'+
     '<small class="play-resource-recovery">'+esc(status)+'</small></span>'+
     (sourceId?'<button type="button" class="play-resource-trait-link" data-act="power-trait" data-origin-id="'+esc(sourceId)+'" aria-label="Apri il tratto '+esc(title)+'">'+icon('details')+'</button>':'')+
    '</div>'+body+'</div>';
  const freePrivileges=[...freeByTrait.values()].map(group=>
   privilegeGroup(group.id,group.name,abilityButtons('free',group.rows),
    group.id.startsWith('unattributed:')?'':group.id));
  // Basic-rule and trait-granted rows share the same clear action style.
  // Unavailable rules stay clickable so their matching action and explanation
  // can still be inspected. Spellcasting jumps straight to the Powers tab.
  // A feat can provide an independent second-weapon capacity without
  // changing the basic-rule availability for two Light weapons.
  const actionLink=(id,name,time,available=true,extra='',count=0,grantId='',grantName='')=>
   '<div class="play-resource-power-row play-resource-rule'+(available?'':' play-resource-rule--inactive')+
    (id==='attack'?' play-resource-rule--attack':'')+'" data-rule-action="'+esc(id)+'">'+
    '<button type="button" class="play-resource-power-open" data-act="'+
    (id==='spell_cast'?'action-open-spells':'battle-action-jump')+'" data-action-id="'+esc(id)+'"'+
    ' aria-label="'+esc(name)+'">'+icon(id==='ability_checks'?'skill':actionGlyphKey({id,name,time}))+
    '<span><strong>'+esc(name)+'</strong><small>'+esc(extra||(
     available?({action:'Azione',bonus:'Azione bonus',reaction:'Reazione'}[time]||'Disponibile'):
     'Non disponibile'))+'</small></span></button>'+
    (count>1?(grantId?'<button type="button" class="play-battle-attacks-per-action" data-act="power-trait"'+
      ' data-origin-id="'+esc(grantId)+'" title="Apri il privilegio '+esc(grantName||'Multiattacco')+'"'+
      ' aria-label="Apri il privilegio '+esc(grantName||'Multiattacco')+', '+count+' attacchi per azione">':
      '<span class="play-battle-attacks-per-action" aria-label="'+count+' attacchi per azione">')+
     '×'+count+(grantId?'</button>':'</span>'):'')+'</div>';
  const basic=view.battleActions?.basicActions||[];
  const base=id=>basic.find(row=>row.id===id)||{id,available:false};
  const grants=(d.attack_count_benefits||[]).filter(row=>Number(row.attacks_per_action)>1);
  const maxCount=Math.max(1,Number(base('attack').attack_count)||1,
   ...grants.map(row=>Number(row.attacks_per_action)));
  const mainGrant=grants.find(row=>Number(row.attacks_per_action)===maxCount);
  const maxTrait=mainGrant?featureFor([mainGrant.origin_id],mainGrant.origin_name):null;
  const maxGrantOrigin=maxTrait?.origin_id||mainGrant?.origin_id||'';
  const baseRuleNames={
   attack:'Azione di attacco',opportunity:'Attacco di opportunità',
   spell_cast:'Lanciare un incantesimo',two_weapon:'Attacco con arma secondaria',
   ability_checks:'Prova abilità'
  };
  const rulesOfBase=[
   ['attack','action'],['opportunity','reaction'],
   ['spell_cast','action'],['two_weapon','bonus'],['ability_checks','action']
  ];
  const basicRules=privilegeGroup('basic-rules','Regole di base',
   rulesOfBase.map(([id,time])=>{
    const row=base(id),available=row.available!==false;
    const hint=id==='spell_cast'?'Slot':
     id==='attack'?'Azione':
     !available?(row.unavailable_reason||
      (id==='opportunity'?'È necessario poter effettuare un attacco in mischia.':
       'Manca l’equipaggiamento richiesto.')):'';
    return actionLink(id,baseRuleNames[id],time,available,hint,
     id==='attack'?maxCount:0,
     id==='attack'?maxGrantOrigin:'',
     id==='attack'?(maxTrait?.name||mainGrant?.origin_name||'Multiattacco'):'');
   }).join(''),'','Azioni e requisiti base');
  // Dual Wielder 2014 is displayed under its own granting feat. Its capacity
  // may be usable while the separate base-rule offhand row stays locked.
  const offhand=view.battleActions?.offhandEligibility||{};
  const feat=offhand.feat;
  const featTrait=feat?featureFor([feat.origin_id,feat.feature_id,feat.origin_key],feat.name||'Dual Wielder'):null;
  const featId=featTrait?.origin_id||feat?.origin_id||'';
  const featPrivileges=feat?[privilegeGroup('feat-dual-wielder',featTrait?.name||feat.name||'Dual Wielder',
   actionLink('two_weapon','Attacco con arma secondaria','bonus',!!offhand.feat_available,
    offhand.feat_available?'Azione bonus':offhand.feat_reason||'Equipaggiamento non idoneo'),
   featId,'Talento · combattimento con due armi')]:[];
  // Trait-specific timing overrides (for example Cunning Action) are
  // capacities of the feature that changes the normal action economy.
  const changedByTrait=new Map();
  for(const action of view.battleActions?.overriddenActions||[]){
   const id=action.action_change_origin,trait=featureFor([id],action.action_change_feature);
   const key=trait?.origin_id||id;
   if(!key||!action.id||changedByTrait.get(key)?.some(a=>a.id===action.id))continue;
   if(!changedByTrait.has(key))changedByTrait.set(key,[]);
   changedByTrait.get(key).push(action);
  }
  const overriddenPrivileges=[...changedByTrait.entries()].map(([id,actions])=>{
   const trait=featureFor([id],actions[0].action_change_feature);
   const title=trait?.name||actions[0].action_change_feature||'Privilegio';
   const names={action:'Azione',bonus:'Azione bonus',reaction:'Reazione',free:'Nessun costo',movement:'Movimento'};
   return privilegeGroup('timing:'+id,title,actions.map(action=>
    actionLink(action.id,action.name,action.time,true,
     (names[action.original_time]||'Azione')+' → '+(names[action.time]||action.time))).join(''),
    trait?.origin_id||id,'Modifica il tipo di azione');
  });
  // Missing trackers are exceptional and must remain visible, not be
  // misrepresented as cost-free privileges.
  const missingPowers=abilityButtons('missing');
  const untracked=(missingPowers?'<div class="play-resource-ungrouped" data-ability-resource="missing">'+
   '<div class="play-resource"><span class="play-resource-heading">Tracker non disponibile</span></div>'+
    missingPowers+'</div>':'')+
   freePrivileges.join('')+featPrivileges.join('')+
   overriddenPrivileges.join('')+basicRules;
  // Keep buttons independent from the summary to preserve their actions.
  const disclosure=(key,title,glyph,body,open=false,tools='')=>'<section class="play-card play-battle-shell">'+
   '<details class="play-battle-disclosure" data-battle-action="'+esc(key)+'"'+(open?' open':'')+'>'+
   '<summary class="play-battle-summary">'+icon(glyph)+'<h2>'+esc(title)+'</h2></summary>'+body+'</details>'+
   (tools?'<div class="play-battle-heading-tools">'+tools+'</div>':'')+'</section>';

  html+='<div class="play-battle-expansion-tools" role="group" aria-label="Espansione delle azioni">'+
   btn('Espandi tutto','increase','data-act="battle-expand-all"')+
   btn('Collassa tutto','decrease','data-act="battle-collapse-all"')+'</div>';
  if(resources+untracked)html+=disclosure('resources','Risorse','reset',
   resources+untracked||'<p class="play-empty">Nessuna risorsa o capacità disponibile.</p>',true);
  if(view.battleActions?.attacks)html+=disclosure('attacks','Attacchi','weapon',
   view.battleActions?.attacks||'<p class="play-empty">Nessuna opzione di attacco.</p>',true,
   btn('Equipaggiamento','weapon','data-act="sheet-context" data-sheet-context="equipment"','<span>Equipaggiamento</span>'));
  if(view.battleActions?.others)html+=disclosure('others','Azioni','hand',
   view.battleActions?.others||'<p class="play-empty">Nessun’altra azione disponibile.</p>');
  if(view.battleActions?.checks)html+=disclosure('checks','Prove abilità','skill',
   view.battleActions?.checks||'<p class="play-empty">Nessuna prova disponibile.</p>');
 }
 if(sheet==='info'){
  const identity=panelNamed('Identità');bind('identity',identity);
  const classMembers=localClasses(c),totalClassLevel=classMembers.reduce((sum,member)=>sum+Math.max(1,Number(member.level)||1),0);
  const classNames=classMembers.map(member=>member.name+' '+Math.max(1,Number(member.level)||1)).join(' · ');
  const portrait=isPortraitDataUrl(c.sheet_portrait_data)?c.sheet_portrait_data:'';
  const identityMarkup='<div class="play-identity"><h2 data-read-field="name">'+esc(c.name)+'</h2>'+
   '<p>'+esc([c.species,c.subrace].filter(Boolean).join(' · '))+'</p>'+
   (classMembers.length?'<p class="play-identity-classes">'+esc(classNames+' · Liv. totale '+totalClassLevel)+'</p>':'')+
   edit('identity','Modifica identità','settings')+'</div>';
  html='<section class="play-character-portrait'+(portrait?' has-portrait':'')+'" aria-label="Identità e foto del personaggio">'+
   (portrait?'<figure class="play-portrait-frame"><img src="'+esc(portrait)+'" alt="Ritratto di '+esc(c.name)+'"></figure>':'')+
   identityMarkup+
   '<div class="play-portrait-controls"><button type="button" class="play-portrait-pick" data-act="info-portrait-pick">'+
   icon('eye')+'<span>'+(portrait?'Cambia foto':'Aggiungi foto')+'</span></button>'+
   (portrait?'<button type="button" class="play-portrait-remove" data-act="info-portrait-remove" aria-label="Rimuovi foto del personaggio">'+
    icon('cross')+'<span>Rimuovi</span></button>':'')+
   '</div><input type="file" data-info-portrait-file accept="image/*" aria-label="Seleziona la foto del personaggio" hidden>'+
   '</section>';
  html+='<div class="play-passives"><span>'+esc(c.alignment||'Completamente neutrale')+'</span><span>Regole '+esc(c.rules_version||'2014')+'</span></div>';
  for(const node of panels.filter(n=>n!==identity)){
   const title=heading(node),i=panels.indexOf(node);
   if(['Caratteristiche','Riepilogo','Abilità','Altre competenze','Tratti'].includes(title))continue;
   const sub=title==='Aspetto'?
    ['Specie '+(c.species||'da definire'),c.subrace||'',c.size_name||'Medium'].filter(Boolean).join(' · '):
    title==='Background'?([c.background,...(c.backgrounds_catalog||[]).filter(row=>!row.disabled).map(row=>row.name)].filter(Boolean).join(' · ')||'Nessun background assegnato'):
    title==='Classi'?
     [classNames||'Nessuna classe assegnata',c.subclass||'',
      c.xp!=null?c.xp+' XP':''].filter(Boolean).join(' · '):
    title==='Talenti'?(c.feats_catalog||[]).map(f=>typeof f==='string'?f:f.name).join(' · '):'';
   html+=go('panel:'+i,title,title==='Aspetto'?'eye':title==='Talenti'?'spark':'book',sub);
  }
  // Show the actual ability modifier, never the ability-check total, while keeping the click target as the check.
  html+='<div class="play-abilities">'+ABILITIES.map(key=>'<article class="play-ability"><header><span>'+key.toUpperCase()+'</span>'+'</header>'+roll('ability_check:'+key,'Prova di '+key.toUpperCase(),output('ability_mod:'+key,true))+'<small>Punteggio '+scoreOutput('ability:'+key,'Punteggio '+key.toUpperCase())+'</small>'+roll('save:'+key,'Tiro salvezza '+key.toUpperCase(),'<small>TS</small>'+output('save:'+key,true))+'</article>').join('')+'</div>';
  html+='<div class="play-ability-quickstats">'+
   '<button type="button" class="play-quickstat" data-act="sheet-context" data-sheet-context="tools" aria-label="Apri altre competenze">'+icon('proficiency')+'<span>Competenza</span><strong>'+output('proficiency',true)+'</strong></button>'+
   '<button type="button" class="play-quickstat" data-act="sheet-senses-open" aria-label="Sensi e percezione passiva">'+icon('eye')+'<span>Sensi</span><strong>Passiva '+output('passive_perception')+'</strong></button>'+
   '<button type="button" class="play-quickstat" data-act="sheet-movement-open" aria-label="Apri velocità e movimento">'+icon('dash')+'<span>Movimento</span><strong>'+output(fastestMovement(d).key,false,' ft').replace(' data-calculated=',' data-fastest-movement-value data-calculated=')+'</strong></button></div>';
  // Competences are one flat, line-divided section rather than another card.
  // Skills expand inline while equipment/language proficiencies retain their
  // existing full editor, including the button for changing selections.
  const tools=panelNamed('Altre competenze');bind('tools',tools);
  html+='<section class="play-competences" aria-labelledby="play-competences-heading">'+
   '<h2 id="play-competences-heading" class="play-section-divider"><span>Competenze</span></h2>'+
   '<details class="play-skills-disclosure">'+
    '<summary class="play-competence-heading">'+icon('skill')+'<strong>Abilità</strong></summary>'+
    '<div class="play-skills-content">'+
     '<div class="play-skills-tools">'+proxy(bank.querySelector('[data-detail="proficiency_choices"]'),'Modifica competenze','settings')+'</div>'+
     '<label class="play-search vtt-list-search">'+icon('search')+'<input type="search" data-play-search value="'+esc(view.search||'')+'" placeholder="Cerca un’abilità" aria-label="Cerca un’abilità"></label>'+
     '<div class="play-skills">'+SKILLS.map(([key,label,ability])=>{
       const rank=(d.proficiencies||[]).includes('expertise:'+key)?2:(d.proficiencies||[]).includes('skill:'+key)?1:0;
       return '<div data-play-filter="'+esc(label.toLocaleLowerCase('it'))+'">'+roll('skill:'+key,label,
        '<span class="play-skill-name">'+esc(label)+skillTrainingIcon(rank)+'<small>'+ability.toUpperCase()+
        (rank===2?' · Maestria':rank===1?' · Competente':'')+'</small></span><b>'+output('skill:'+key,true)+'</b>')+'</div>';
      }).join('')+'</div>'+
    '</div></details>'+
   '<div class="play-competence-tools">'+go('tools','Altre competenze','proficiency')+'</div>'+
   '</section>';
  // Tratti is a permanent Info section like Competenze; only each trait's
  // description can be expanded. Keep all benefit controls visible.
  const traits=panelNamed('Tratti');
  if(traits){
   const content=[...traits.children].filter(child=>child.tagName!=='H2')
     .map(child=>child.outerHTML).join('');
   html+='<section class="play-info-traits" aria-labelledby="play-info-traits-heading">'+
    '<h2 id="play-info-traits-heading" class="play-section-divider"><span>Tratti</span></h2>'+
    '<div class="play-info-traits-content">'+content+'</div></section>';
  }
 }
 if(sheet==='magic'){
  const overview=bank.querySelector('.magic-overview');
  const slots=[...overview?.querySelectorAll('.magic-level-slot')||[]];
  // Keep the slot card even for noncasters, but show only levels with
  // a positive maximum (spent-all slots still remain visible).
  const slotContents=slots.map(node=>
    proxy(node,node.getAttribute('aria-label')||'Gestisci slot','',
      '<small>'+esc(node.dataset.pact==='true'?'Patto '+node.dataset.level+'°':node.dataset.level+'°')+'</small>'+
      '<b>'+esc(node.textContent.trim())+'</b>')).join('');
  html=card('Slot incantesimo','<div class="play-slots">'+
    (slotContents||'<p class="play-slots-empty">Nessuno slot assegnato.</p>')+'</div>',
    proxy(overview?.querySelector('.magic-overview-manage'),'Gestisci slot','reset'));
  const concentrated=(c.conditions||[]).includes('concentrating')||Boolean(c.concentrating_spell_id);
  const concentratedId=String(c.concentrating_spell_id||'');
  const concentratedName=concentratedId?
    (spells.find(spell=>spell.id===concentratedId)?.name||concentratedId):'';
  html+='<section class="play-magic-concentration" aria-label="Concentrazione">'+
    '<strong>Concentrazione</strong>'+
    '<span class="play-magic-concentration-status'+(concentrated?' is-active':'')+'">'+
      esc(concentrated?(concentratedName||'Attiva · nessun incantesimo'):'Non attiva')+'</span>'+
    '<div class="play-magic-concentration-actions">'+
      proxy(overview?.querySelector('[data-act="concentration-open"]'),
        concentrated?'Sostituisci concentrazione':'Attiva concentrazione','',
        '<span aria-hidden="true">+</span>')+
      (concentrated?proxy(overview?.querySelector('[data-act="stop-concentration"]'),
        'Termina concentrazione','', '<span aria-hidden="true">×</span>'):'')+
    '</div></section>';
  for(const source of bank.querySelectorAll('.magic-source')){
   const title=source.querySelector('.magic-source-title h3, h3')?.textContent||'Poteri';
   const granted=source.classList.contains('magic-origin-panel');
   // Source counters live in the hidden legacy bank. Project them into the
   // actual mobile header instead of silently dropping them. The readouts are
   // taken from the resolved pools; spend/recover still delegates to the
   // original tracker action, so shared trackers never diverge.
   const resources=[...source.querySelectorAll('.magic-source-header .magic-source-resource')]
     .map(resource=>{
      const label=resource.querySelector('.magic-source-resource-label')?.textContent.trim()||
        (resource.querySelector('strong,button')?'':resource.textContent.trim());
      const counter=resource.querySelector('.magic-source-resource-counter')?.textContent.trim()||
        resource.querySelector('strong')?.textContent.trim()||'';
      const trackerId=resource.dataset.magicTrackerId||'';
      const controls=[...resource.querySelectorAll('button[data-act]')].map(button=>
        proxy(button,button.getAttribute('aria-label')||button.title||'Gestisci risorsa','',
          '<span aria-hidden="true">'+esc(button.textContent.trim())+'</span>')).join('');
      return '<span class="play-magic-source-resource"'+
        (trackerId?' data-play-magic-tracker="'+esc(trackerId)+'"':'')+'>'+
        (label?'<span class="play-magic-source-resource-name">'+esc(label)+'</span>':'')+
        (counter?'<strong class="play-magic-source-resource-count">'+esc(counter)+'</strong>':'')+
        controls+'</span>';
     }).join('');
   const trackerId=source.querySelector('.magic-source-header [data-magic-tracker-id]')?.dataset.magicTrackerId||'';
   const rows=[...source.querySelectorAll('.magic-spell-row')].map(row=>{
    const node=row.querySelector('[data-act="power-spell"]');if(!node)return '';
    const level=row.closest('[data-magic-level]')?.dataset.magicLevel;
    const levelLabel=level==='0'?'Trucchetto':level&&level!=='null'?level+'°':'';
    const cost=granted?row.querySelector('.magic-power-cost')?.textContent.trim()||'':'';
    return '<div class="play-spell'+(granted?' play-magic-origin-spell':'')+'">'+
      proxy(node,node.textContent,'spark','<span>'+esc(node.textContent)+'</span>'+
        (levelLabel?'<small class="play-spell-level">'+esc(levelLabel)+'</small>':'')+
        (cost?'<small class="play-magic-spell-cost">'+esc(cost)+'</small>':''))+'</div>';
   }).join('');
   // The casting selector and actions share the same per-source editor, both
   // for class spells and for grants from items, traits and other origins.
   const castingDetails=source.querySelector('.casting-statistics')?.outerHTML||'';
   const choices=[...source.querySelectorAll('.magic-source-controls .magic-selection-button')]
     .map(node=>proxy(node,node.textContent.trim(),'book','<span>'+esc(node.textContent.trim())+'</span>')).join('');
   html+=card(title,'<div class="play-magic-inline-casting">'+castingDetails+'</div>'+
     (choices?'<div class="play-magic-selection">'+choices+'</div>':'')+
     (rows||'<p class="play-empty">Nessun incantesimo disponibile.</p>'),
     resources?'<div class="play-magic-source-resources" aria-label="Risorse di lancio">'+resources+'</div>':'',
     'play-magic-class-card'+(granted?' play-magic-granted-card':''),
     granted&&trackerId?'data-magic-origin-tracker="'+esc(trackerId)+'"':'');
  }
  const originPanels=[...bank.querySelectorAll(':scope > .panel')].filter(n=>heading(n)!=='Incantesimi disponibili');
  originPanels.forEach((node,i)=>{
   if(heading(node).startsWith('Modelli di armatura')){
     bind('armor-models',node);
     const counters=[...node.querySelector('.infusion-overview')?.children||[]]
       .map(row=>'<span class="play-magic-source-resource">'+esc(row.textContent.trim())+'</span>').join('');
     const rows=[...node.querySelectorAll('.armor-model-entry')].map(row=>{
       const id=row.dataset.armorModelId||'';
       const active=row.dataset.armorModelActive==='true';
       const available=row.dataset.armorModelAvailable==='true';
       const name=row.querySelector('.magic-spell-open')?.firstChild?.textContent?.trim()||'Modello';
       const status=active?'Attivo':available?'Non attivo':'Armatura richiesta';
       return '<div class="play-spell play-infusion-row play-armor-model-row">'+
        '<button type="button" class="play-button" data-act="armor-model-open" data-armor-model-id="'+esc(id)+
         '" aria-label="Apri modello '+esc(name)+' · '+status+'">'+
        icon('shield')+'<span class="play-infusion-name">'+esc(name)+'</span>'+
        '<span class="play-infusion-state'+(active?' is-active':'')+'" title="'+status+'" aria-label="'+status+'">'+
         '<span aria-hidden="true">'+(active?'✓':'○')+'</span></span></button></div>';
     }).join('');
     html+=card('Modelli di armatura',rows||'<p class="play-empty">Nessun modello disponibile.</p>',
       counters?'<div class="play-magic-source-resources" aria-label="Stato modelli di armatura">'+counters+'</div>':'',
       'play-magic-class-card play-infusion-card play-armor-model-card');
     return;
   }
   if(heading(node).startsWith('Infusioni')){
     bind('infusions',node);
     const counters=[...node.querySelector('.infusion-overview')?.children||[]]
       .map(row=>'<span class="play-magic-source-resource">'+esc(row.textContent.trim())+'</span>').join('');
     const known=[...node.querySelectorAll('.infusion-entry')];
     const rows=known.map(row=>{
       const index=row.dataset.infusionIndex;
       const applied=row.dataset.infusionActive==='true';
       const name=row.querySelector('.magic-spell-open')?.firstChild?.textContent?.trim()||'Infusione';
       const itemName=row.querySelector('.magic-spell-open>small:not(.infusion-status)')?.textContent.trim()||'';
       const status=applied?'Attiva':'Conosciuta';
       return '<div class="play-spell play-infusion-row"><button type="button" class="play-button" data-act="infusion-open" data-index="'+esc(index)+'" aria-label="Apri '+esc(name)+' · '+status+'">'+
         icon('infusion')+'<span class="play-infusion-name">'+esc(name)+
         (itemName?'<small>'+esc(itemName)+'</small>':'')+'</span>'+
         '<span class="play-infusion-state'+(applied?' is-active':'')+'" title="'+status+'" aria-label="'+status+'"><span aria-hidden="true">'+(applied?'✓':'○')+'</span></span>'+
         '</button></div>';
     }).join('');
     html+=card('Infusioni',
       '<div class="play-magic-selection">'+
       btn('Impara infusioni','book','data-act="infusion-picker-open" data-mode="learn"','<span>Impara</span>')+'</div>'+
       (rows||'<p class="play-empty">Nessuna infusione conosciuta.</p>'),
       counters?'<div class="play-magic-source-resources" aria-label="Riepilogo infusioni">'+counters+'</div>':'',
       'play-magic-class-card play-infusion-card');
     return;
   }
   const key='power:'+i;
   bind(key,node);
   const count=node.querySelectorAll('.magic-spell-row,.magic-ability-entry').length;
   // Spell rows already belong to the right tracker (or origin) in the
   // native power panel. Expose those same entries without opening it.
   const spellRows=[...node.querySelectorAll('.magic-spell-row')].map(row=>{
    const spell=row.querySelector('[data-act="power-spell"]');
    if(!spell)return '';
    const name=spell.textContent.trim(),level=row.closest('[data-magic-level]')?.dataset.magicLevel;
    const cost=row.querySelector('.magic-power-cost')?.textContent.trim()||'';
    const levelLabel=level==='0'?'Trucchetto':level&&level!=='null'?level+'°':'';
    return '<div class="play-spell play-magic-origin-spell">'+
      proxy(spell,'Apri '+name,'spark','<span>'+esc(name)+'</span>'+
        (levelLabel?'<small class="play-spell-level">'+esc(levelLabel)+'</small>':'')+
        (cost?'<small class="play-magic-spell-cost">'+esc(cost)+'</small>':''))+'</div>';
   }).join('');
   const trackerId=node.querySelector('[data-magic-tracker-id]')?.dataset.magicTrackerId||'';
   html+='<section class="play-magic-origin-group"'+
     (trackerId?' data-magic-origin-tracker="'+esc(trackerId)+'"':'')+'>'+
     go(key,heading(node),'spark',count+(count===1?' potere':' poteri'))+
     (spellRows?'<div class="play-magic-origin-spells">'+spellRows+'</div>':'')+
     '</section>';
  });
 }
 if(sheet==='inventory'){
  const containers=inventoryContainers(c);
  const keys=['items','scrolls','documents',...containers.slice(1).map(row=>'container:'+row.id)];
  const requested=Array.isArray(view.inventorySelectedTabs)?view.inventorySelectedTabs:[view.inventorySubtab||'items'];
  const selected=keys.filter(key=>requested.includes(key)||requested.includes('all'));
  const showingItems=selected.some(key=>key==='items'||key.startsWith('container:'));
  html+=inventorySectionControls(c,selected);
  html+='<div class="inventory-bulk-bar" data-inventory-bulk hidden>'+
    '<label class="inventory-bulk-master"><input type="checkbox" data-inventory-select-all aria-label="Seleziona tutti gli oggetti visibili"><span class="inventory-check-graphic" aria-hidden="true">✓</span><span>Seleziona tutti</span></label>'+
    '<strong data-inventory-selection-count>0 selezionati</strong>'+
    '<div class="inventory-bulk-actions">'+
    '<button type="button" class="library-bulk-button" data-act="inventory-bulk-export">Esporta</button>'+
    '<button type="button" class="library-bulk-button" data-act="inventory-bulk-send">Manda</button>'+
    '<button type="button" class="library-bulk-button library-bulk-delete" data-act="inventory-bulk-delete">Elimina</button>'+
    '</div></div>';
  if(showingItems){
    target('equipment','.inventory-equipment');target('attunement','.inventory-attunement');
    const coinPanel=bank.querySelector('.inventory-coins-panel');
    const coinFields=coinPanel?.querySelector('.inventory-coin-grid')?.outerHTML||'';
    const coinTotal=coinPanel?.querySelector('.inventory-coin-total')?.outerHTML||'';
    coinPanel?.remove();
    const equipped=(c.inventory||[]).filter(item=>item.equipped_slots?.length).map(item=>item.name).filter(Boolean).join(' · ');
    html+='<div class="inventory-shortcuts">'+
      go('equipment','Armi e armature','weapon',equipped||'Mani e armatura')+
      go('attunement','Sintonia','spark',(d.attunements?.used??inventoryAttunementCounts(c.inventory,d.values?.attunement_max??c.attunement_max_base??3).reduce((sum,n)=>sum+n,0))+
        ' / '+(d.attunements?.maximum??d.values?.attunement_max??c.attunement_max_base??3)+' sintonie')+
      '<section class="inventory-play-coins" aria-label="Monete possedute">'+
        '<div class="inventory-play-coins-title">'+icon('coins')+'<strong>Monete</strong></div>'+
        '<div class="inventory-play-coins-fields">'+coinFields+coinTotal+'</div>'+
      '</section></div>';
  }
  const attunements=d.attunements?.counts||inventoryAttunementCounts(c.inventory,d.values?.attunement_max??c.attunement_max_base??3);
  const readouts=(c.inventory||[]).map((item,i)=>inventoryReadout(requiresAttunement(resolveOwnedItem(item))?
    {...item,attuned_count:attunements[i]||0}:item,inventoryProperties(item),isSpellScroll(item)));
  if(showingItems){
    const owned=readouts.filter(info=>info.kind!=='document');
    const totals=key=>{const known=owned.filter(item=>item[key]!==null);return {count:known.length,value:known.reduce((sum,item)=>sum+item[key],0)};};
    const weight=totals('weight'),value=totals('value'),format=value=>Number(value.toFixed(2)).toLocaleString('it-IT');
    if(weight.count||value.count)html+='<div class="inventory-overview" aria-label="Riepilogo inventario"><div><span>Peso registrato</span><strong>'+(weight.count?format(weight.value)+' <small>lb</small>':'—')+'</strong>'+(weight.count&&weight.count<owned.length?'<small>Dati parziali</small>':'')+'</div><div><span>Valore degli oggetti</span><strong>'+(value.count?format(value.value)+' <small>mo</small>':'—')+'</strong>'+(value.count&&value.count<owned.length?'<small>Dati parziali</small>':'')+'</div></div>';
  }
  // The search selects all the owner's containers; it does not hide rows.
  const highlighted=new Set(view.inventoryHighlightedIndices||[]);
  html+='<div class="inventory-search-area">'+
    '<label class="play-search inventory-global-search">'+icon('search')+
    '<input type="search" data-play-search value="'+esc(view.search||'')+
    '" placeholder="Cerca nell’inventario e nel catalogo" aria-label="Cerca oggetti posseduti o nel catalogo" autocomplete="off" aria-controls="inventory-search-results"></label>'+
    '<div id="inventory-search-results" class="inventory-search-results vtt-selection-list" role="region" aria-label="Risultati ricerca inventario" aria-live="polite" hidden></div></div>';
  const renderItem=({info,i},section)=>{
    const item=c.inventory[i],key='item:'+i,scroll=section==='scrolls';
    const row=bank.querySelector('[data-inventory-row="'+i+'"]');
    const documentRow=bank.querySelector('[data-document-card="'+i+'"]');
    const node=document.createElement('section');node.className='play-item-editor';
    if(row&&Number(view.inventorySelectedIndex)===i){
      const form=document.createElement('div');form.className='play-item-fields';
      const field=(caption,control,holder=form)=>{
        if(!control)return;
        const label=document.createElement('label');
        const title=document.createElement('span');title.textContent=caption;
        label.append(title,control);holder.append(label);
      };
      const name=row.querySelector('[data-item-key="name"]');
      const quantity=row.querySelector('.inventory-quantity-controls');
      const kind=itemKind(item);
      const slots=Array.isArray(item.equipped_slots)?item.equipped_slots:[];
      const mainItem=(c.inventory||[]).find(entry=>entry.equipped_slots?.includes('main'));
      const mainResolved=mainItem?resolveOwnedItem(mainItem):null;
      const offBlocked=c.hand_off_with_two_handed!==true&&mainResolved&&(
        hasProperty(mainResolved,'2H')||c.hand_grip_two_handed&&hasProperty(mainResolved,'V'));
      const equipOptions=kind==='weapon'?[['main','Mano primaria'],['off','Mano secondaria']]:
        kind==='armor'?[['body','Indossa armatura']]:
        kind==='shield'?[['off','Equipaggia scudo']]:[];
      const equipButtons=equipOptions.map(([slot,label])=>{
        const equipped=slots.includes(slot);
        // Even blocked saved offhand equipment must remain removable.
        const disabled=!validSlot(item,slot)||!equipped&&slot==='off'&&offBlocked;
        return '<button type="button" class="inventory-equip-action'+(equipped?' is-equipped':'')+
          '" data-act="inventory-equip-slot" data-index="'+i+'" data-slot="'+slot+'"'+
          (disabled?' disabled':'')+' aria-pressed="'+equipped+'"'+
          (disabled?' title="Mano secondaria occupata o arma a due mani non compatibile"':'')+'>'+
          (equipped?'✓ ':'')+esc(label)+'</button>';
      }).join('');
      if(name)field('Nome oggetto',name);
      const primary=document.createElement('div');primary.className='play-item-main-fields';
      field('Quantità',quantity,primary);
      const location=document.createElement('select');
      location.setAttribute('aria-label','Sezione dell’oggetto');
      if(section==='scrolls'||section==='documents'){
        const option=document.createElement('option');option.textContent=section==='scrolls'?'Pergamene':'Documenti';
        location.append(option);location.disabled=true;
      }else{
        location.dataset.itemContainer=String(i);
        for(const container of containers){
          const option=document.createElement('option');option.value=container.id;
          option.textContent=container.name;
          option.selected=itemContainerId(item,containers)===container.id;
          location.append(option);
        }
      }
      field('Sezione',location,primary);
      form.append(primary);
      if(requiresAttunement(resolveOwnedItem(item))){
        form.insertAdjacentHTML('beforeend',inventoryAttunementControl(c,i,d,false));
      }
      if(equipButtons){
        const equipField=document.createElement('div');
        equipField.className='play-item-equip-field';
        equipField.innerHTML='<span class="play-item-equip-caption">Equipaggiamento</span>'+
          '<div class="play-item-equip-actions">'+equipButtons+'</div>';
        form.append(equipField);
      }
      row.replaceChildren(form);
    }
    if(row)node.append(row);
    if(documentRow){documentRow.open=true;node.append(documentRow);}
    if(row&&Number(view.inventorySelectedIndex)===i){
      const description=bank.querySelector('.inventory-description-panel');
      if(description)node.append(description);
    }
    bind(key,node);
    const search=[info.displayName,item.name,spellScrollName(item),spellScrollLevel(item),info.type,info.source,info.properties,...info.status].filter(Boolean).join(' ').toLocaleLowerCase('it');
    const level=spellScrollLevel(item),levelLabel=level==='0'?'Trucchetto':level==='—'?'—':level+'°';
    if(scroll)return '<div data-play-filter="'+esc(search)+'" data-inventory-search-index="'+i+'" class="'+(highlighted.has(i)?'inventory-search-highlight':'')+'"><button type="button" class="inventory-play-item inventory-play-scroll" data-act="sheet-context" data-sheet-context="'+key+'" title="'+esc(item.name||'Pergamena')+'">'+
      '<span class="inventory-item-mark" aria-hidden="true">'+icon('scroll')+'</span>'+
      '<span class="inventory-item-content"><strong>'+esc(spellScrollName(item))+'</strong><small>'+esc(info.source||'Pergamena magica')+'</small></span>'+
      '<span class="inventory-scroll-stats"><span class="inventory-scroll-level" aria-label="Livello dell’incantesimo">'+esc(levelLabel)+'</span>'+
      '<span class="play-badge" aria-label="Quantità">×'+info.quantity+'</span></span></button></div>';
    return '<div data-play-filter="'+esc(search)+'" data-inventory-search-index="'+i+'" class="'+(highlighted.has(i)?'inventory-search-highlight':'')+'"><button type="button" class="inventory-play-item" data-act="sheet-context" data-sheet-context="'+key+'" title="'+esc(info.displayName)+'">'+
      '<span class="inventory-item-mark" aria-hidden="true">'+icon(info.glyph)+'</span><span class="inventory-item-content"><span class="inventory-item-heading"><strong>'+esc(info.displayName)+'</strong><span class="play-badge">×'+info.quantity+'</span></span>'+
      '<span class="inventory-item-type">'+esc([info.type,info.source].filter(Boolean).join(' · '))+'</span>'+
      (info.properties?'<span class="inventory-item-properties">'+esc(info.properties)+'</span>':'')+
      (info.facts.length?'<span class="inventory-item-facts">'+info.facts.map(fact=>'<span aria-label="'+esc(fact.label+': '+fact.value)+'">'+icon(fact.glyph)+'<span>'+esc(fact.label)+' <b>'+esc(fact.value)+'</b></span></span>').join('')+'</span>':'')+
      (info.status.length?'<span class="inventory-item-status">'+info.status.map(label=>'<span>'+esc(label)+'</span>').join('')+'</span>':'')+'</span></button></div>';
  };
  for(const section of selected){
    const isDocuments=section==='documents',isScrolls=section==='scrolls';
    const activeContainer=section.startsWith('container:')?
      containers.find(row=>row.id===section.slice('container:'.length)):null;
    const destination=activeContainer?.id||DEFAULT_INVENTORY_CONTAINER;
    const visible=readouts.map((info,i)=>({info,i})).filter(({info,i})=>
      isDocuments?info.kind==='document':
      isScrolls?isSpellScroll(c.inventory[i]):
      info.kind!=='document'&&!isSpellScroll(c.inventory[i])&&
        itemContainerId(c.inventory[i],containers)===destination);
    const name=isDocuments?'Documenti':isScrolls?'Pergamene magiche':activeContainer?.name||'Zaino';
    const add=document.createElement('div'),key='inventory-add:'+section;
    if(isScrolls)target('scroll-create','.inventory-scroll-create');
    else {
      const holder=isDocuments?bank.querySelector('.inventory-documents-panel'):
        bank.querySelector('[data-inventory-section="'+section+'"]');
      const selector=isDocuments?'[data-act="document-add"]':
        '[data-act="item-catalog"],[data-act="new-homebrew-item"]';
      for(const node of holder?.querySelectorAll(selector)||[])add.append(node);
      bind(key,add);
    }
    const controls=activeContainer?
      '<div class="inventory-container-management">'+
        btn('Rinomina '+name,'settings','data-act="inventory-container-rename" data-container-id="'+esc(activeContainer.id)+'"','<span>Rinomina</span>')+
      '</div>':'';
    const sectionMetrics=(!isDocuments&&!isScrolls)?(()=>{
      const metric=(field,unit,label)=>{
        const known=visible.filter(({info})=>info[field]!==null);
        const total=known.reduce((sum,{info})=>sum+info[field],0);
        return '<span><small>'+label+'</small><strong>'+
          (known.length?Number(total.toFixed(2)).toLocaleString('it-IT')+' '+unit:'—')+
          '</strong>'+(known.length&&known.length<visible.length?
          '<small>Dati parziali</small>':'')+'</span>';
      };
      return '<span class="inventory-section-metrics" role="group" aria-label="Peso e valore sezione">'+
        metric('weight','lb','Peso')+metric('value','mo','Valore')+'</span>';
    })():'';
    const addButton=isScrolls?edit('scroll-create','Crea pergamena','increase'):
      edit(key,isDocuments?'Aggiungi documento':'Aggiungi oggetto','increase');
    html+=card(name,
      visible.map(row=>'<div class="inventory-selectable-item" data-inventory-item-index="'+row.i+'">'+
        '<label class="inventory-item-batch-check" aria-label="Seleziona '+esc(c.inventory[row.i]?.name||'oggetto')+'">'+
        '<input type="checkbox" data-inventory-select="'+row.i+'"><span class="inventory-check-graphic" aria-hidden="true">✓</span></label>'+
        renderItem(row,section)+'</div>').join('')+
        (!visible.length?'<p class="play-empty">Nessuna voce disponibile.</p>':'')+
      controls,
      sectionMetrics?'<span class="inventory-section-head-tools">'+sectionMetrics+addButton+'</span>':addButton,
      'play-inventory-section'+(sectionMetrics?' has-section-metrics':''));
  }
 }
 if(sheet==='traits'){
  const groups=[...bank.querySelectorAll('.trait-card')];
  html+=card('Privilegi e tratti',groups.map((node,i)=>{bind('trait:'+i,node);return go('trait:'+i,node.querySelector('summary')?.textContent||'Tratto','proficiency');}).join('')||'<p class="play-empty">Nessun tratto disponibile.</p>');

 }
 if(sheet==='conditions'){
  target('conditions','.condition-sheet-panel');
  const plus=(key,title)=>'<button type="button" class="play-status-add" data-act="sheet-context" data-sheet-context="'+esc(key)+'" aria-label="'+esc(title)+'" title="'+esc(title)+'">＋</button>';
  const section=(title,key,body)=>'<section class="play-status-section" data-status-section="'+esc(key)+'">'+
    '<header class="play-status-section-head"><h3>'+esc(title)+'</h3>'+plus(key,'Aggiungi '+title.toLowerCase())+'</header>'+
    '<div class="play-status-section-content">'+body+'</div></section>';
  const conditionRows=activeConditions.map(({id,label})=>
    '<span class="play-condition-wrap" data-active-condition="'+esc(id)+'">'+
    '<button type="button" class="play-condition" data-act="state-trait-jump" data-state-trait="'+esc('state|condition:'+id)+'" aria-label="Apri tratto '+esc(label)+'">'+icon('condition')+esc(label)+'</button>'+
    '<button type="button" class="play-condition-remove" data-act="condition-remove" data-condition-id="'+esc(id)+'" aria-label="Rimuovi '+esc(label)+'" title="Rimuovi '+esc(label)+'"><span aria-hidden="true">×</span></button></span>').join('');
  const applied=(c.proficiency_origins||[]).filter(row=>row?.group==='spell'&&String(row.id||'').startsWith('spell:')&&!row.disabled&&c.origin_enabled?.[row.id]!==false);
  const activeLink=(key,glyph,label,detail='')=>'<button type="button" class="play-status-trait-link" data-act="state-trait-jump" data-state-trait="'+esc('state|'+key)+'" aria-label="Apri tratto '+esc(label)+'">'+icon(glyph)+'<span><strong>'+esc(label)+'</strong>'+
   (detail?'<small class="feature-effect-summary">'+esc(detail)+'</small>':'')+'</span></button>';
  const spellRows=applied.map(row=>'<div class="play-effect-row">'+
   activeLink(String(row.id),'spark',String(row.name||row.id).replace(/^Incantesimo · /,''))+
   btn('Rimuovi incantesimo','cross','data-act="condition-remove-spell" data-spell-id="'+esc(row.id.slice(6))+'"','<span class="sr-only">Rimuovi</span>')+'</div>').join('');
  const spellOptions=spells.filter(isPersistentSpell).filter(row=>row?.id&&row?.name);
  const picker='<div class="play-effect-add"><label class="vtt-list-search">Cerca incantesimo<input id="condition-spell-search" type="search" placeholder="Cerca nel catalogo"></label><label>Incantesimo<select id="condition-spell-picker">'+spellOptions.map(row=>'<option value="'+esc(row.id)+'">'+esc(row.name)+(row.source?' · '+esc(row.source):'')+'</option>').join('')+'</select></label>'+btn('Applica incantesimo','increase','data-act="condition-add-spell"','<span>Applica</span>')+'</div>';
  const spellEditor=document.createElement('div');spellEditor.innerHTML=picker;bind('apply-spell',spellEditor.firstElementChild);
  const active=Object.entries(c.active_class_features||{});
  const effectRows=active.map(([key,row])=>{
   const effect=(d.active_feature_effects||[]).find(e=>e.key===key);
   const detail=key==='wild_shape'?'Aspetto attuale: '+(c.current_miniature_id||''):
    effect?.effective?effect.summary:'Benefici sospesi: il tratto o le condizioni richieste non sono disponibili.';
   return '<div class="play-effect-row">'+activeLink(key,'buff',row?.name||key,detail)+
    btn('Termina capacità','cross','data-act="condition-remove-ability" data-ability-key="'+esc(key)+'"','<span class="sr-only">Termina</span>')+'</div>';
  }).join('');
  const toggleKeys=new Set(['rage','reckless_attack','innate_sorcery','patient_defense','step_of_the_wind']);
  const eligible=classActions.filter(row=>toggleKeys.has(row.class_feature_id)&&!c.active_class_features?.[row.class_feature_id]);
  const abilityPicker=eligible.length?'<div class="play-effect-add"><label>Capacità disponibile<select id="condition-ability-picker">'+eligible.map(row=>'<option value="'+esc(row.class_feature_id)+'">'+esc(row.name)+'</option>').join('')+'</select></label>'+btn('Attiva capacità','increase','data-act="condition-add-ability"','<span>Attiva</span>')+'</div>':'<p class="play-empty">Nessun’altra capacità persistente disponibile. Le capacità si sbloccano tramite i privilegi della scheda.</p>';
  const abilityEditor=document.createElement('div');abilityEditor.innerHTML='<div class="play-effect-add">'+abilityPicker+'</div>';bind('apply-ability',abilityEditor.firstElementChild);
  const infusionRows=infused.map(row=>
   '<div class="play-effect-row">'+activeLink('infusion:'+row.id,'spark',row.name,
    (row.item.name||row.item.id)+' · Infusione equipaggiata')+
   btn('Termina infusione','cross','data-act="infusion-clear" data-index="'+row.index+'"','<span class="sr-only">Termina</span>')+
   '</div>').join('');
  const concentrationRow=(c.conditions||[]).includes('concentrating')?
   '<div class="play-effect-row">'+activeLink('condition:concentrating','spark','Concentrazione',c.concentrating_spell_id||'Attiva')+
   btn('Interrompi concentrazione','cross','data-act="stop-concentration"','<span class="sr-only">Interrompi</span>')+'</div>':'';
  html+=card('Stati attivi',
    section('Condizioni','conditions',conditionRows||'<p class="play-empty">Nessuna condizione attiva.</p>')+
    section('Incantesimi','apply-spell',spellRows+concentrationRow||'<p class="play-empty">Nessun incantesimo applicato.</p>')+
    section('Capacità','apply-ability',effectRows+infusionRows||'<p class="play-empty">Nessuna capacità attiva.</p>'),
    '', 'play-status-card');
 }
 // The action variants shortcut belongs to the page title, not to an action group.
 // Preserve the 2014-only availability and the existing delegated popup action.
 if(sheet==='battle'&&c.rules_version!=='2024'){
  const title=app.querySelector(':scope > .page-head');
  if(title){
   title.classList.add('play-actions-page-title');
   title.insertAdjacentHTML('beforeend',btn('Varianti alle regole','settings',
    'data-act="action-variants"','<span>Varianti alle regole</span>'));
  }
 }
 // Keep the "show all" control alongside the inventory title, rather
 // than treating it as another section in the multi-select wrap.
 if(sheet==='inventory'){
  const title=app.querySelector(':scope > .page-head');
  if(title){
   const containers=inventoryContainers(c);
   const keys=['items','scrolls','documents',...containers.slice(1).map(row=>'container:'+row.id)];
   const selected=Array.isArray(view.inventorySelectedTabs)?view.inventorySelectedTabs:[view.inventorySubtab||'items'];
   const allVisible=keys.every(key=>selected.includes(key)||selected.includes('all'));
   const label=allVisible?'Mostra solo zaino':'Mostra tutti gli oggetti';
   title.classList.add('play-inventory-page-title');
   title.insertAdjacentHTML('beforeend',btn(label,'inventory',
    'data-act="inventory-toggle-all" aria-pressed="'+allVisible+'"',
    '<span>'+label+'</span>'));
  }
 }
 const main=document.createElement('div');main.id='sheet-play-view';main.className='sheet-play-view';main.dataset.sheet=sheet;main.innerHTML=html;
 root.prepend(main);
 const filter=sheet==='inventory'?'':String(view.search||'').trim().toLocaleLowerCase('it');
 for(const row of main.querySelectorAll('[data-play-filter]'))row.hidden=!matchesSearch(filter,row.dataset.playFilter);
 for(const warning of [...bank.querySelectorAll(':scope > [role=alert],:scope > .action-catalog-warning')])main.prepend(warning);
 const utilities=app.querySelector(':scope > .archive-tools');
 if(utilities){bind('sheet-tools',utilities);bank.append(utilities);}
 const note=bank.querySelector('[data-calculation-note]');if(note)bind('calculation',note);
 const more=document.createElement('div');more.className='play-sheet-tools';more.innerHTML=edit('sheet-tools','Opzioni della scheda','settings')+(note?edit('calculation','Calcoli e copertura','information'):'');main.append(more);
 // Native dialogs must never inherit hidden from the editor bank.
 for(const dialog of [...bank.querySelectorAll('dialog')])root.append(dialog);
 return sources;
}
export function refreshPlayReadouts(root,creature,calculated){
 for(const node of root.querySelectorAll('[data-read-field]'))node.textContent=String(creature[node.dataset.readField]??0);
 for(const progress of root.querySelectorAll('[data-hp-progress]')){progress.max=Math.max(1,Number(calculated.values?.hp)||1);progress.value=Number(creature.current_hp)||0;}
}
