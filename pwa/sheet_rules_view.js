import {hitDicePools} from './character_core.js';
// Render local/offline calculations; no desktop sessions or API calls.
import {ABILITIES,SKILLS,localClasses} from "./sheet_rules.js";
import {actionGlyphKey} from "./action_economy.js";
import {itemKind,resolveOwnedItem,requiresAttunement,spellScrollLevel,spellScrollName} from "./item_controls.js";
import {isDocument} from "./documents.js";
const esc=v=>String(v??"—").replace(/[&<>"']/g,c=>({
  "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const signed=value=>value===null||value===undefined?"—":Number(value)>=0?"+"+value:String(value);
const metric=(label,value)=>'<div class="derived-metric"><span>'+esc(label)+'</span><strong>'+esc(value)+'</strong></div>';
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
 if(target.startsWith('ability_mod:')){
  const key=target.slice('ability_mod:'.length),score=Number(data?.values?.['ability:'+key]);
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
export function sheetRollFormula(modifier,bonuses=[]){
 const number=Number(modifier);
 if(!Number.isFinite(number))throw Error('Modificatore del tiro non disponibile');
 const fixed='1d20'+(number<0?' − '+Math.abs(number):' + '+number);
 return fixed+bonuses.map(row=>' + '+String(row.dice)).join('');
}
export function rollSheetDice(modifier,bonuses=[],die){
 if(typeof die!=='function')throw Error('Generatore dadi non disponibile');
 const base=Number(modifier);
 if(!Number.isFinite(base))throw Error('Modificatore non valido');
 const d20=die(20);
 if(!Number.isInteger(d20)||d20<1||d20>20)throw Error('Risultato d20 non valido');
 const parts=[{name:'d20',notation:'1d20',rolls:[d20],subtotal:d20}];
 for(const bonus of bonuses){
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
 const notation=sheetRollFormula(base,bonuses);
 const detail=parts.map(row=>row.name+' ['+row.rolls.join(', ')+']'+(row.flat?(row.flat>0?' + ':' − ')+Math.abs(row.flat):'')+' = '+row.subtotal).join(' · ')+
  ' · modificatore '+(base>=0?'+':'')+base+' · totale '+total;
 return {sides:20,count:1,modifier:base,rolls:[d20],total,notation,detail,parts};
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
  const rollable=/^(?:ability_mod:|save:|skill:|attack_hit:|casting_hit:)/.test(target)||target==='initiative';
  const tag=rollable||scoreAbility?'button':'output';
  const click=scoreAbility?' type="button" class="sheet-result score-editor-trigger" data-act="edit-score" data-ability-key="'+esc(scoreAbility)+'"':
   rollable?' type="button" class="sheet-result" data-act="sheet-roll" data-target="'+esc(target)+'" data-label="'+esc(label)+'"':'';
  return '<span class="sheet-formula"><'+tag+click+' data-calculated="'+esc(target)+
    '" data-signed="'+sign+'" data-suffix="'+esc(suffix)+'" title="'+
    esc(data?.explanations?.[target]||label)+'" aria-label="'+esc(label)+'">'+
    esc(calculatedValue(data,target,{signed:sign,suffix}))+'</'+tag+'>'+
    (showBonus?'<button type="button" class="btn small formula-bonus" data-act="edit-bonus" data-target="'+
    esc(bonusTarget)+'" aria-label="Modifica bonus: '+esc(label)+'">±</button>':'')+'</span>';
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
        metric("Percezione passiva",stats.passive_perception??"—")+'</div>'+
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
 if(effective.range)facts.push({label:'Gittata',value:effective.range+' ft',glyph:'target'});
 if(weight!==null)facts.push({label:quantity>1?'Peso totale':'Peso',value:format(weight*quantity)+' lb',glyph:'inventory'});
 if(value!==null)facts.push({label:quantity>1?'Valore totale':'Valore',value:format(value*quantity)+' mo',glyph:'coins'});
 const slots={main:'Mano principale',off:'Mano secondaria',body:'Indossato'};
 const status=(Array.isArray(item.equipped_slots)?item.equipped_slots:[]).map(slot=>slots[slot]||slot);
 if(item.equipped&&!status.length)status.push('Equipaggiato');
 if(item.attuned)status.push('In sintonia');else if(requiresAttunement(effective))status.push('Richiede sintonia');
 if(item.active===false)status.push('Disattivato');
 if(item.infusion)status.push('Infuso');
 return {kind,type,glyph,quantity,source:String(item.source||''),properties:propertyText==='—'?'':String(propertyText||''),facts,status,
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
 if(['rage','reckless_attack','innate_sorcery','patient_defense','step_of_the_wind'].includes(action.class_feature_id)||
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
  const id=String(action.id||action.ability_id||action.name||'');
  // The native action projector can describe a granted class action twice
  // (once as an action grant and once as its structured feature).
  const repeated=rows.some(row=>row.source==='class'&&(
   row.id===id||(powerIdentity(row.classAction)===powerIdentity(action)&&
    String(row.tracker_id||'')===String(action.tracker_id||''))));
  if(repeated)continue;
  const cost=Math.max(0,Number(action.cost??0)||0);
  const identity=powerIdentity(action);
  const same=rows.find(row=>row.kind==='ability'&&row.source==='activated'&&(
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
export function mountPlaySheet(app,{creature:c,calculated:d,sheet,view={},icon,conditionLabel,inventoryProperties=()=>'',isSpellScroll=()=>false,spells=[],classActions=[]}){
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
 const card=(title,body,tools='',extra='')=>'<section class="play-card '+extra+'"><header class="play-card-head"><h2>'+esc(title)+'</h2>'+tools+'</header>'+body+'</section>';
 const output=(key,sign=false,suffix='')=>'<output data-calculated="'+esc(key)+'" data-signed="'+sign+'" data-suffix="'+esc(suffix)+'">'+esc(calculatedValue(d,key,{signed:sign,suffix}))+'</output>';
 const val=(key)=>'<span data-read-field="'+key+'">'+esc(c[key]??0)+'</span>';
 const roll=(key,label,body,glyph='')=>btn(label,glyph,'data-act="sheet-roll" data-target="'+esc(key)+'" data-label="'+esc(label)+'"',body||output(key,true));
 const heading=(node)=>node?.querySelector(':scope > h2')?.textContent.trim()||'';
 const panels=[...bank.querySelectorAll(':scope > .panel')];
 panels.forEach((node,i)=>bind('panel:'+i,node));
 const panelNamed=(name)=>panels.find(node=>heading(node).includes(name));
 const list=(title,rows,empty='Nessuna voce.')=>card(title,rows||'<p class="play-empty">'+esc(empty)+'</p>');
 let html='';
 if(sheet==='battle'){
  target('hp','.battle-hp-panel');target('defense','.battle-defense-panel');target('movement','.battle-movement-panel');
  // Both battle entry points display the exact same editor and computed AC.
  bind('equipment',bank.querySelector('.battle-defense-panel'));
  const max=Math.max(1,Number(d.values?.hp)||1),hp=Number(c.current_hp)||0;
  html='<section class="play-health"><header><span>Punti ferita</span><div class="play-health-tools">'+btn('Riposi e recuperi','rest_short','data-act="sheet-context" data-sheet-context="rests"','<span>Riposi</span>')+edit('hp','Gestisci punti ferita','settings')+'</div></header><div class="play-hp-number">'+val('current_hp')+'<small> / '+output('hp')+'</small></div><progress data-hp-progress value="'+hp+'" max="'+max+'" aria-label="Punti ferita rimanenti"></progress><div class="play-health-extra"><span>Temporanei <b>'+val('temporary_hp')+'</b></span>'+(Number(d.values?.second_max)>0?'<span>Seconda forma <b>'+val('second_form_hp')+' / '+output('second_max')+'</b></span>':'')+'</div><div class="play-hp-actions">'+btn('Danni','decrease','data-act="hp-damage"')+btn('Cura','healing','data-act="hp-heal"')+'</div></section>';
  const fastest=fastestMovement(d);
  html+='<div class="play-vitals">'+btn('Classe armatura','shield','data-act="sheet-context" data-sheet-context="defense"','<small>CA</small>'+output('ac'))+roll('initiative','Iniziativa','<small>Iniziativa</small>'+output('initiative',true),'lightning')+btn('Movimento e velocità','dash','data-act="sheet-context" data-sheet-context="movement"','<small data-fastest-movement-label>'+esc(fastest.label)+'</small>'+output(fastest.key,false,' ft').replace(' data-calculated=',' data-fastest-movement-value data-calculated='))+'</div>';
  const appliedSpells=(c.proficiency_origins||[]).filter(row=>row?.group==='spell'&&String(row.id||'').startsWith('spell:')&&!row.disabled&&c.origin_enabled?.[row.id]!==false);
  const activeAbilities=Object.entries(c.active_class_features||{});
  html+='<div class="play-status-strip">'+btn('Condizioni, incantesimi e capacità','condition','data-act="sheet" data-sheet="conditions"','<span>Stati</span>')+(c.conditions||[]).map(id=>'<button type="button" class="play-status-tag" data-act="sheet" data-sheet="conditions">'+esc(conditionLabel(id))+'</button>').join('')+appliedSpells.map(row=>'<button type="button" class="play-status-tag" data-act="sheet" data-sheet="conditions">✦ '+esc(String(row.name||row.id).replace(/^Incantesimo · /,''))+'</button>').join('')+activeAbilities.map(([key,value])=>'<button type="button" class="play-status-tag" data-act="sheet" data-sheet="conditions">✧ '+esc(value?.name||key)+'</button>').join('')+'</div>';
  const dice=hitDicePools(c,d);
  const diceControls=dice.map(pool=>'<label class="play-rest-die">'+
    '<span>d'+pool.die+' · '+pool.available+' / '+pool.total+'</span>'+
    '<input type="number" inputmode="numeric" data-rest-die="'+pool.die+'" min="0" max="'+pool.available+'" value="0" aria-label="Dadi Vita d'+pool.die+' da spendere"></label>').join('');
  const rest=document.createElement('div');
  rest.innerHTML=(dice.length?'<div class="play-rest-dice"><strong>Dadi Vita</strong>'+diceControls+'</div>':'')+
    '<div class="play-rest-choices">'+[['tracker-short','rest_short','Riposo breve'],['tracker-long','rest_long','Riposo lungo'],['tracker-turn','reset','Inizio turno']].map(([a,g,l])=>btn(l,g,'data-act="'+a+'"')).join('')+'</div>';
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
  const traits=view.battleTraits||[];
  const cleanOrigin=id=>String(id||'').replace(/^feature:/,'');
  const featureFor=(ids=[],name='')=>{
   const candidates=ids.map(cleanOrigin).filter(Boolean);
   const exact=traits.find(feature=>[feature.origin_id,feature.origin_key,feature.feature_key]
     .some(value=>value&&candidates.includes(cleanOrigin(value))));
   if(exact)return exact;
   const normalized=powerName(name);
   return normalized?traits.find(feature=>powerName(feature.name)===normalized):null;
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
   source.insertAdjacentHTML('beforeend',detail);
  }
  const abilityButtons=key=>powerRows.filter(row=>row.key===key).map(row=>{
   const tracker=(d.trackers||[]).find(t=>String(t.id)===String(row.tracker_id));
   const available=tracker?Math.max(0,Number(tracker.max||0)-Number(tracker.spent||0)):0;
   const disabled=row.cost>0&&(!tracker||tracker.disabled||available<row.cost);
   const glyph=icon(row.kind==='spell'?'spell_cast':
     actionGlyphKey({...row.classAction,...row.power,name:row.name,type:'Capacità'}));
   const caption=row.kind==='spell'?row.casting_time_label:
     (timeLabels[row.timing]||row.timing||'Secondo il privilegio');
   const note=row.kind==='spell'?(row.cost>1?' · Costo '+row.cost:''):
     ' · '+(row.cost?'Costo '+row.cost:'Nessun costo');
   if(row.kind==='spell')return '<div class="play-resource-power-row" data-power-spell-id="'+esc(row.id)+'">'+
    '<button type="button" class="play-resource-power-open" data-act="power-spell" data-spell-key="origin" data-grant-id="'+esc(row.id)+'"'+
    ' aria-label="Dettagli '+esc(row.name)+'">'+glyph+'<span><strong>'+esc(row.name)+'</strong><small>'+esc(caption+note)+'</small></span></button>'+
    '<button type="button" class="play-resource-use" data-act="battle-cast-resource-spell" data-grant-id="'+esc(row.id)+'"'+(disabled?' disabled':'')+
    ' aria-label="Lancia '+esc(row.name)+'">Lancia</button></div>';
   const id=row.id,action=row.classAction||{},power=row.power||{};
   const trait=featureFor([power.feature_id,power.origin_id,action.origin_id,action.feature_id],
     action.feature||row.name);
   const originId=trait?.origin_id||power.feature_id||power.origin_id||action.origin_id||'';
   const originLabel=trait?.origin_key||power.origin||action.origin_id||'';
   const description=trait?.description||power.description||action.description||'';
   const detail=document.createElement('section');
   detail.className='panel play-battle-power-detail';
   detail.innerHTML='<h2>'+esc(row.name)+'</h2>'+
    '<dl class="power-privilege-facts">'+
     '<div><dt>Origine</dt><dd>'+esc(originLabel||'Non specificata')+'</dd></div>'+
     '<div><dt>Attivazione</dt><dd>'+esc(caption)+'</dd></div>'+
     '<div><dt>Costo</dt><dd>'+esc(row.cost?row.cost+' utilizzi'+(tracker?' · '+tracker.name:''):'Nessun costo')+'</dd></div></dl>'+
    (description?'<div class="power-privilege-description"><h3>Descrizione del tratto</h3><p class="trait-description">'+esc(description)+'</p></div>':'')+
    (originId?'<button type="button" class="play-button power-origin-link" data-act="power-trait" data-origin-id="'+esc(originId)+'">'+icon('proficiency')+'<span>Apri il tratto di origine</span></button>':'');
   const powerDetail=(powerGroups.get(key)||[]).find(ability=>row.power&&String(ability.id)===String(power.id));
   const context=bind(powerDetail?.key||'battle-power:'+id,detail);
   const persistent=persistentBattleAbility(row);
   const statusKey=action.class_feature_id||'battle:'+String(id);
   const active=!!c.active_class_features?.[statusKey];
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
   return '<div class="play-resource-group" data-resource-tracker="'+esc(t.id)+'"><div class="play-resource"><button class="play-resource-info" type="button" data-act="sheet-context" data-sheet-context="'+esc(context)+'" aria-label="Gestisci '+esc(t.name)+'">'+
    '<span class="play-resource-copy"><strong class="play-resource-name">'+esc(t.name)+'</strong><small class="play-resource-recovery">'+esc(trackerRecoveryText(t))+'</small></span>'+
    '<span class="play-resource-count">'+left+' <small>/ '+esc(t.max)+'</small></span></button>'+
    '</div>'+abilityButtons(key)+'</div>';
  }).join('');
  const untracked=['missing','free'].map(key=>{
   const powers=abilityButtons(key);
   const freeActions=key==='free'?view.battleActions?.freeActions||'':'';
   return powers||freeActions?'<div class="play-resource-ungrouped" data-ability-resource="'+esc(key)+'"><div class="play-resource"><span class="play-resource-heading">'+
    (key==='free'?'Nessun costo':'Tracker non disponibile')+'</span></div>'+powers+
    (freeActions?'<div class="play-resource-free-actions"><h4>Azioni gratuite</h4>'+freeActions+'</div>':'')+'</div>':'';
  }).join('');
  // Keep buttons independent from the summary to preserve their actions.
  const disclosure=(key,title,glyph,body,open=false,tools='')=>'<section class="play-card play-battle-shell">'+
   '<details class="play-battle-disclosure" data-battle-action="'+esc(key)+'"'+(open?' open':'')+'>'+
   '<summary class="play-battle-summary">'+icon(glyph)+'<h2>'+esc(title)+'</h2></summary>'+body+'</details>'+
   (tools?'<div class="play-battle-heading-tools">'+tools+'</div>':'')+'</section>';
  html+=disclosure('resources','Risorse','reset',
   resources+untracked||'<p class="play-empty">Nessuna risorsa o capacità disponibile.</p>');
  html+=disclosure('attacks','Attacchi fisici','weapon',
   view.battleActions?.attacks||'<p class="play-empty">Nessuna opzione di attacco.</p>',true,
   btn('Equipaggiamento','weapon','data-act="sheet-context" data-sheet-context="equipment"','<span>Equipaggiamento</span>'));
  html+=disclosure('others','Altre azioni','hand',
   view.battleActions?.others||'<p class="play-empty">Nessun’altra azione disponibile.</p>');
  html+=disclosure('movement','Spostamento','dash',
   view.battleActions?.movement||'<p class="play-empty">Nessuna opzione di spostamento.</p>');
  html+=disclosure('checks','Prove abilità','skill',
   view.battleActions?.checks||'<p class="play-empty">Nessuna prova disponibile.</p>');
  html+=disclosure('spells','Incantesimi','spell_cast',
   view.battleActions?.spells||'<p class="play-empty">Nessun incantesimo disponibile.</p>',false,
   btn('Gestisci incantesimi','spell_cast','data-act="action-open-spells"','<span>Gestisci</span>'));
 }
 if(sheet==='info'){
  const identity=panelNamed('Identità');bind('identity',identity);
  const classMembers=localClasses(c),totalClassLevel=classMembers.reduce((sum,member)=>sum+Math.max(1,Number(member.level)||1),0);
  const classNames=classMembers.map(member=>member.name+' '+Math.max(1,Number(member.level)||1)).join(' · ');
  html='<section class="play-identity"><div class="play-identity-mark">'+icon(c.kind==='monster'?'wild_shape':'proficiency')+'</div><h2 data-read-field="name">'+esc(c.name)+'</h2>'+
   '<p>'+esc([c.species,c.subrace].filter(Boolean).join(' · '))+'</p>'+
   (classMembers.length?'<p class="play-identity-classes">'+esc(classNames+' · Liv. totale '+totalClassLevel)+'</p>':'')+
   edit('identity','Modifica identità','settings')+'</section>';
  html+='<div class="play-passives"><span>'+esc(c.alignment||'Completamente neutrale')+'</span><span>Regole '+esc(c.rules_version||'2014')+'</span></div>';
  for(const node of panels.filter(n=>n!==identity)){
   const title=heading(node),i=panels.indexOf(node);
   if(['Caratteristiche','Riepilogo','Abilità','Altre competenze','Tratti'].includes(title))continue;
   const sub=title==='Aspetto'?
    ['Specie '+(c.species||'da definire'),c.subrace?'Sottorazza '+c.subrace:'',
     'Taglia '+(c.size_name||'Medium'),
     c.default_miniature_id?'Miniatura base assegnata':'Miniatura base da assegnare',
     c.current_miniature_id&&c.current_miniature_id!==c.default_miniature_id?'Forma alternativa attiva':''].filter(Boolean).join(' · '):
    title==='Background'?(c.background||'Nessun background assegnato'):
    title.includes('Classi')?
     [classNames||'Nessuna classe assegnata',c.subclass?'Sottoclasse '+c.subclass:'',
      'Livello totale '+totalClassLevel,c.xp!=null?c.xp+' XP':''].filter(Boolean).join(' · '):
    title==='Talenti'?(c.feats_catalog||[]).map(f=>typeof f==='string'?f:f.name).join(' · '):'';
   html+=go('panel:'+i,title,title==='Aspetto'?'eye':title==='Talenti'?'spark':'book',sub);
  }
  html+='<div class="play-abilities">'+ABILITIES.map(key=>'<article class="play-ability"><header><span>'+key.toUpperCase()+'</span>'+proxy(bank.querySelector('[data-act="edit-score"][data-ability-key="'+key+'"]'),'Modifica '+key.toUpperCase(),'settings','<span class="sr-only">Modifica punteggio</span>')+'</header>'+roll('ability_mod:'+key,'Prova di '+key.toUpperCase(),output('ability_mod:'+key,true))+'<small>Punteggio '+output('ability:'+key)+'</small>'+roll('save:'+key,'Tiro salvezza '+key.toUpperCase(),'<small>TS</small>'+output('save:'+key,true))+'</article>').join('')+'</div>';
  html+='<div class="play-passives"><span>Competenza <b>'+output('proficiency',true)+'</b></span><span>Percezione passiva <b>'+output('passive_perception')+'</b></span></div>';
  html+=card('Abilità','<label class="play-search">'+icon('search')+'<input type="search" data-play-search value="'+esc(view.search||'')+'" placeholder="Cerca un’abilità" aria-label="Cerca un’abilità"></label><div class="play-skills">'+SKILLS.map(([key,label,ability])=>'<div data-play-filter="'+esc(label.toLocaleLowerCase('it'))+'">'+roll('skill:'+key,label,'<span>'+esc(label)+'<small>'+ability.toUpperCase()+((d.proficiencies||[]).includes('expertise:'+key)?' · Maestria':(d.proficiencies||[]).includes('skill:'+key)?' · Competente':'')+'</small></span><b>'+output('skill:'+key,true)+'</b>')+'</div>').join('')+'</div>',proxy(bank.querySelector('[data-detail="proficiency_choices"]'),'Modifica competenze','settings'));
  const tools=panelNamed('Altre competenze');bind('tools',tools);html+=go('tools','Altre competenze','proficiency');
  // Traits belong at the end of Info, as visible cards grouped by origin.
  // The old traits tab flattened them into a list of context buttons.
  const traits=panelNamed('Tratti');
  if(traits){
   const content=[...traits.children].filter(child=>child.tagName!=='H2')
     .map(child=>child.outerHTML).join('');
   html+=card('Tratti','<div class="play-info-traits-content">'+content+'</div>','','play-info-traits');
  }
 }
 if(sheet==='magic'){
  const tools=bank.querySelector('.magic-toolbar');bind('magic-tools',tools);
  html='<div class="play-inline-tools"><span>'+((c.conditions||[]).includes('concentrating')?'Concentrazione attiva':'Nessuna concentrazione')+'</span>'+edit('magic-tools','Gestisci poteri e incantesimi','settings')+'</div>';
  const slots=[...bank.querySelectorAll('.magic-level-slot')].filter((node,i,all)=>all.findIndex(n=>n.dataset.level===node.dataset.level&&n.dataset.act===node.dataset.act)===i);
  if(slots.length)html+=card('Slot incantesimo','<div class="play-slots">'+slots.map(node=>proxy(node,node.getAttribute('aria-label')||'Consuma slot','', '<small>'+esc(node.dataset.level==='0'?'Patto':node.dataset.level+'°')+'</small><b>'+esc(node.textContent.trim())+'</b>')).join('')+'</div>',proxy(bank.querySelector('[data-magic-tool="slots"]'),'Gestisci slot','reset'));
  for(const source of bank.querySelectorAll('.magic-source')){
   const title=source.querySelector('h3')?.textContent||'Poteri';
   const titleKey='casting:'+sources.size;bind(titleKey,source.querySelector('.casting-statistics'));
   const rows=[...source.querySelectorAll('.magic-spell-row')].map(row=>{
    const node=row.querySelector('[data-act="power-spell"]');if(!node)return '';
    const level=row.closest('[data-magic-level]')?.dataset.magicLevel;
    return '<div class="play-spell">'+proxy(node,node.textContent,'spark','<span>'+esc(node.textContent)+'</span><small class="play-spell-level">'+esc(level==='0'?'Trucchetto':level?level+'°':'')+'</small>')+'</div>';
   }).join('');
   const casting=source.querySelector('.casting-statistics'),ability=casting?.querySelector('select')?.value||'int';
   const stats='CD '+(d.values?.['casting_dc:'+ability]??'—')+' · Attacco '+signed(d.values?.['casting_hit:'+ability]);
   // Reuse the class selector in the native mobile sheet rather than hiding it
   // inside the source bank or inventing another spell-selection state.
   const choices=[...source.querySelectorAll('.magic-source-controls .magic-selection-button')]
     .map(node=>proxy(node,node.textContent.trim(),'book','<span>'+esc(node.textContent.trim())+'</span>')).join('');
   html+=card(title,'<p class="play-casting-facts">'+esc(stats)+(source.querySelector('.magic-source-count')?' · '+esc(source.querySelector('.magic-source-count').textContent):'')+'</p>'+
     (choices?'<div class="play-magic-selection">'+choices+'</div>':'')+
     (rows||'<p class="play-empty">Nessun incantesimo disponibile.</p>'),edit(titleKey,'Caratteristica e bonus di '+title,'settings'));
  }
  const originPanels=[...bank.querySelectorAll(':scope > .panel')].filter(n=>heading(n)!=='Incantesimi disponibili');
  originPanels.forEach((node,i)=>{
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
  const documentsTab=view.inventorySubtab==='documents',scrollsTab=view.inventorySubtab==='scrolls';
  html+='<nav class="inventory-subtabs" role="tablist" aria-label="Sezioni inventario">'+
    [['items','Oggetti','inventory'],['scrolls','Pergamene','scroll'],['documents','Documenti','book']].map(([key,label,glyph])=>
      '<button type="button" role="tab" data-act="inventory-subtab" data-subtab="'+key+
      '" aria-selected="'+(view.inventorySubtab===key)+'" aria-label="'+label+'">'+icon(glyph)+
      '<span>'+label+'</span></button>').join('')+'</nav>';
  if(!documentsTab&&!scrollsTab){
    target('equipment','.inventory-equipment');target('attunement','.inventory-attunement');
    // The coin editor is already generated from the saved creature model.
    // Move its content into the shortcut row instead of hiding it behind a dialog.
    const coinPanel=bank.querySelector('.inventory-coins-panel');
    const coinFields=coinPanel?.querySelector('.inventory-coin-grid')?.outerHTML||'';
    const coinTotal=coinPanel?.querySelector('.inventory-coin-total')?.outerHTML||'';
    coinPanel?.remove(); // Avoid duplicate hidden controls and stale total updates.
    const equipped=(c.inventory||[]).filter(item=>item.equipped_slots?.length).map(item=>item.name).filter(Boolean).join(' · ');
    html+='<div class="inventory-shortcuts">'+
      go('equipment','Equipaggiamento','weapon',equipped||'Mani e armatura')+
      go('attunement','Sintonia','spark',(c.inventory||[]).filter(item=>item.attuned).length+
        ' / '+(c.attunement_max_base??3)+' oggetti')+
      '<section class="inventory-play-coins" aria-label="Monete possedute">'+
        '<div class="inventory-play-coins-title">'+icon('coins')+'<strong>Monete</strong></div>'+
        '<div class="inventory-play-coins-fields">'+coinFields+coinTotal+'</div>'+
      '</section></div>';
  }
  const readouts=(c.inventory||[]).map(item=>inventoryReadout(item,inventoryProperties(item),isSpellScroll(item)));
  const visible=readouts.map((info,i)=>({info,i})).filter(({info,i})=>
    documentsTab?info.kind==='document':scrollsTab?isSpellScroll(c.inventory[i]):
    info.kind!=='document'&&!isSpellScroll(c.inventory[i]));
  if(!documentsTab&&!scrollsTab){
    const owned=readouts.filter(item=>item.kind!=='document');
    const totals=key=>{const known=owned.filter(item=>item[key]!==null);return {count:known.length,value:known.reduce((sum,item)=>sum+item[key],0)};};
    const weight=totals('weight'),value=totals('value'),format=value=>Number(value.toFixed(2)).toLocaleString('it-IT');
    if(weight.count||value.count)html+='<div class="inventory-overview" aria-label="Riepilogo inventario"><div><span>Peso registrato</span><strong>'+(weight.count?format(weight.value)+' <small>lb</small>':'—')+'</strong>'+(weight.count&&weight.count<owned.length?'<small>Dati parziali</small>':'')+'</div><div><span>Valore degli oggetti</span><strong>'+(value.count?format(value.value)+' <small>mo</small>':'—')+'</strong>'+(value.count&&value.count<owned.length?'<small>Dati parziali</small>':'')+'</div></div>';
  }
  const add=document.createElement('div');
  if(scrollsTab)target('scroll-create','.inventory-scroll-create');
  else{
    for(const node of bank.querySelectorAll(documentsTab?
      '[data-act="document-add"]':
      '[data-act="item-catalog"],[data-act="new-homebrew-item"]'))add.append(node);
    bind('inventory-add',add);
  }
  html+=card(documentsTab?'Documenti':scrollsTab?'Pergamene magiche':'Nello zaino',
    '<p class="inventory-list-count">'+visible.length+' voci · '+
    visible.reduce((total,{info})=>total+info.quantity,0)+' unità</p>'+
    '<label class="play-search">'+icon('search')+'<input type="search" data-play-search value="'+esc(view.search||'')+'" placeholder="Cerca '+(documentsTab?'nei documenti':scrollsTab?'tra le pergamene':'nello zaino')+'" aria-label="Cerca nell’inventario"></label>'+
    visible.map(({info,i})=>{
      const item=c.inventory[i],key='item:'+i;
      const row=bank.querySelector('[data-inventory-row="'+i+'"]'),documentRow=bank.querySelector('[data-document-card="'+i+'"]');
      const node=document.createElement('section');node.className='play-item-editor';
      if(row&&Number(view.inventorySelectedIndex)===i){
        const form=document.createElement('div');form.className='play-item-fields';
        const field=(caption,control)=>{if(!control)return;const label=document.createElement('label');label.append(document.createTextNode(caption),control);form.append(label);};
        const name=row.querySelector('[data-item-key="name"]'),quantity=row.querySelector('.inventory-quantity-controls'),equip=row.querySelector('.inventory-equip-toggle'),more=row.querySelector('.inventory-more'),actions=row.querySelector('.inventory-context-actions'),select=row.querySelector('.inventory-select');
        field('Nome oggetto',name);field('Quantità',quantity);field('Equipaggiamento',equip);
        const toolbar=document.createElement('div');toolbar.className='play-item-toolbar';if(more)toolbar.append(more);if(actions)toolbar.append(actions);
        row.replaceChildren(form,toolbar);if(select){select.hidden=true;row.append(select);}
      }
      if(row)node.append(row);if(documentRow){documentRow.open=true;node.append(documentRow);}
      if(row&&Number(view.inventorySelectedIndex)===i){const description=bank.querySelector('.inventory-description-panel');if(description)node.append(description);}
      bind(key,node);
      const search=[item.name,spellScrollName(item),spellScrollLevel(item),info.type,info.source,info.properties,...info.status].filter(Boolean).join(' ').toLocaleLowerCase('it');
      const scrollLevel=spellScrollLevel(item),scrollLevelLabel=scrollLevel==='0'?'Trucchetto':scrollLevel==='—'?'—':scrollLevel+'°';
      if(scrollsTab)return '<div data-play-filter="'+esc(search)+'"><button type="button" class="inventory-play-item inventory-play-scroll" data-act="sheet-context" data-sheet-context="'+key+'" title="'+esc(item.name||'Pergamena')+'">'+
        '<span class="inventory-item-mark" aria-hidden="true">'+icon('scroll')+'</span>'+
        '<span class="inventory-item-content"><strong>'+esc(spellScrollName(item))+'</strong><small>'+esc(info.source||'Pergamena magica')+'</small></span>'+
        '<span class="inventory-scroll-stats"><span class="inventory-scroll-level" aria-label="Livello dell’incantesimo">'+esc(scrollLevelLabel)+'</span>'+
        '<span class="play-badge" aria-label="Quantità">×'+info.quantity+'</span></span></button></div>';
      return '<div data-play-filter="'+esc(search)+'"><button type="button" class="inventory-play-item" data-act="sheet-context" data-sheet-context="'+key+'" title="'+esc(item.name||'Oggetto')+'">'+
        '<span class="inventory-item-mark" aria-hidden="true">'+icon(info.glyph)+'</span><span class="inventory-item-content"><span class="inventory-item-heading"><strong>'+esc(item.name||'Oggetto')+'</strong><span class="play-badge">×'+info.quantity+'</span></span>'+
        '<span class="inventory-item-type">'+esc([info.type,info.source].filter(Boolean).join(' · '))+'</span>'+
        (info.properties?'<span class="inventory-item-properties">'+esc(info.properties)+'</span>':'')+
        (info.facts.length?'<span class="inventory-item-facts">'+info.facts.map(fact=>'<span aria-label="'+esc(fact.label+': '+fact.value)+'">'+icon(fact.glyph)+'<span>'+esc(fact.label)+' <b>'+esc(fact.value)+'</b></span></span>').join('')+'</span>':'')+
        (info.status.length?'<span class="inventory-item-status">'+info.status.map(label=>'<span>'+esc(label)+'</span>').join('')+'</span>':'')+'</span></button></div>';
    }).join('')||'<p class="play-empty">Nessuna voce disponibile.</p>',
    scrollsTab?edit('scroll-create','Crea pergamena','increase'):
      edit('inventory-add',documentsTab?'Aggiungi documento':'Aggiungi oggetto','increase'));
  if(!documentsTab&&!scrollsTab){
    const infusion=panelNamed('Infusioni');
    if(infusion){bind('infusions',infusion);html+=go('infusions','Infusioni','infusion','Conosciute, applicate e disponibili');}
  }
 }
 if(sheet==='traits'){
  const groups=[...bank.querySelectorAll('.trait-card')];
  html+=card('Privilegi e tratti',groups.map((node,i)=>{bind('trait:'+i,node);return go('trait:'+i,node.querySelector('summary')?.textContent||'Tratto','proficiency');}).join('')||'<p class="play-empty">Nessun tratto disponibile.</p>');

 }
 if(sheet==='conditions'){
  target('conditions','.condition-sheet-panel');
  html+=card('Stati attivi',(c.conditions||[]).map(id=>'<button type="button" class="play-condition" data-act="sheet-context" data-sheet-context="conditions" aria-label="Gestisci '+esc(conditionLabel(id))+'">'+icon('condition')+esc(conditionLabel(id))+'</button>').join('')||'<div class="play-calm">'+icon('shield')+'<strong>Nessuna condizione attiva</strong></div>',edit('conditions','Aggiungi o rimuovi condizioni','increase'));
  const applied=(c.proficiency_origins||[]).filter(row=>row?.group==='spell'&&String(row.id||'').startsWith('spell:')&&!row.disabled&&c.origin_enabled?.[row.id]!==false);
  const spellRows=applied.map(row=>'<div class="play-effect-row"><span>'+icon('spark')+'<strong>'+esc(String(row.name||row.id).replace(/^Incantesimo · /,''))+'</strong></span>'+btn('Rimuovi incantesimo','cross','data-act="condition-remove-spell" data-spell-id="'+esc(row.id.slice(6))+'"','<span class="sr-only">Rimuovi</span>')+'</div>').join('');
  const spellOptions=spells.filter(isPersistentSpell).filter(row=>row?.id&&row?.name).slice(0,80);
  const picker='<div class="play-effect-add"><label>Cerca incantesimo<input id="condition-spell-search" type="search" placeholder="Cerca nel catalogo"></label><label>Incantesimo<select id="condition-spell-picker">'+spellOptions.map(row=>'<option value="'+esc(row.id)+'">'+esc(row.name)+(row.source?' · '+esc(row.source):'')+'</option>').join('')+'</select></label>'+btn('Applica incantesimo','increase','data-act="condition-add-spell"','<span>Applica</span>')+'</div>';
  const spellEditor=document.createElement('div');spellEditor.innerHTML=picker;bind('apply-spell',spellEditor.firstElementChild);
  html+=card('Incantesimi applicati',spellRows||'<p class="play-empty">Nessun incantesimo applicato.</p>','', 'play-effect-card')+go('apply-spell','Applica un incantesimo','spark','Scegli un incantesimo con durata dal catalogo');
  const active=Object.entries(c.active_class_features||{});
  const effectRows=active.map(([key,row])=>'<div class="play-effect-row"><span>'+icon('buff')+'<strong>'+esc(row?.name||key)+'</strong></span>'+btn('Termina capacità','cross','data-act="condition-remove-ability" data-ability-key="'+esc(key)+'"','<span class="sr-only">Termina</span>')+'</div>').join('');
  const toggleKeys=new Set(['rage','reckless_attack','innate_sorcery','patient_defense','step_of_the_wind']);
  const eligible=classActions.filter(row=>toggleKeys.has(row.class_feature_id)&&!c.active_class_features?.[row.class_feature_id]);
  const abilityPicker=eligible.length?'<div class="play-effect-add"><label>Capacità disponibile<select id="condition-ability-picker">'+eligible.map(row=>'<option value="'+esc(row.class_feature_id)+'">'+esc(row.name)+'</option>').join('')+'</select></label>'+btn('Attiva capacità','increase','data-act="condition-add-ability"','<span>Attiva</span>')+'</div>':'<p class="play-empty">Nessun’altra capacità persistente disponibile. Le capacità si sbloccano tramite i privilegi della scheda.</p>';
  const abilityEditor=document.createElement('div');abilityEditor.innerHTML='<div class="play-effect-add">'+abilityPicker+'</div>';bind('apply-ability',abilityEditor.firstElementChild);
  html+=card('Capacità attive',effectRows||'<p class="play-empty">Nessuna capacità attiva.</p>','', 'play-effect-card')+go('apply-ability','Applica una capacità','buff','Attiva un privilegio persistente disponibile');
  html+=go('conditions','Indebolimento','debuff','Livello '+(c.exhaustion_level??c.exhaustion??0));
  if((c.conditions||[]).includes('concentrating'))html+=card('Concentrazione','<p>'+esc(c.concentrating_spell_id||'Attiva')+'</p>'+btn('Interrompi concentrazione','cross','data-act="stop-concentration"'));
 }
 if(sheet==='origins'){
  const select=bank.querySelector('#native-details');
  const options=[...(select?.options||[])];
  html+=card('Configurazione del personaggio',options.map(option=>'<button type="button" class="play-list-row" data-act="sheet-origin-editor" data-detail="'+esc(option.value)+'">'+icon(option.value==='resources'?'reset':'settings')+'<span class="play-row-copy"><strong>'+esc(option.textContent)+'</strong></span><span class="play-chevron">›</span></button>').join(''));
  bind('origin-editor',panels[0]);
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
 const main=document.createElement('div');main.id='sheet-play-view';main.className='sheet-play-view';main.dataset.sheet=sheet;main.innerHTML=html;
 root.prepend(main);
 const filter=String(view.search||'').trim().toLocaleLowerCase('it');
 for(const row of main.querySelectorAll('[data-play-filter]'))row.hidden=!row.dataset.playFilter.includes(filter);
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
