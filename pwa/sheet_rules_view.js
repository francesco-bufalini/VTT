// Render local/offline calculations; no desktop sessions or API calls.
import {ABILITIES,SKILLS} from "./sheet_rules.js";
const esc=v=>String(v??"—").replace(/[&<>"']/g,c=>({
  "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const signed=value=>value===null||value===undefined?"—":Number(value)>=0?"+"+value:String(value);
const metric=(label,value)=>'<div class="derived-metric"><span>'+esc(label)+'</span><strong>'+esc(value)+'</strong></div>';
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
export function formulaReadout(data,target,label,{signed:sign=false,suffix="",bonusTarget=target,scoreAbility=''}={}){
  const rollable=/^(?:ability_mod:|save:|skill:|attack_hit:|casting_hit:)/.test(target)||target==='initiative';
  const tag=rollable||scoreAbility?'button':'output';
  const click=scoreAbility?' type="button" class="sheet-result score-editor-trigger" data-act="edit-score" data-ability-key="'+esc(scoreAbility)+'"':
   rollable?' type="button" class="sheet-result" data-act="sheet-roll" data-target="'+esc(target)+'" data-label="'+esc(label)+'"':'';
  return '<span class="sheet-formula"><'+tag+click+' data-calculated="'+esc(target)+
    '" data-signed="'+sign+'" data-suffix="'+esc(suffix)+'" title="'+
    esc(data?.explanations?.[target]||label)+'" aria-label="'+esc(label)+'">'+
    esc(calculatedValue(data,target,{signed:sign,suffix}))+'</'+tag+'>'+
    '<button type="button" class="btn small formula-bonus" data-act="edit-bonus" data-target="'+
    esc(bonusTarget)+'" aria-label="Modifica bonus: '+esc(label)+'">±</button></span>';
}
export function calculationNote(data,loadError=""){
  const warnings=[...new Set([...(data?.warnings||[]),...(loadError?[loadError]:[])])];
  return '<details class="calculation-note" data-calculation-note><summary>Calcoli e copertura della scheda</summary>'+
    '<p class="hint">Calcolato localmente sul dispositivo, anche offline.</p>'+
    (warnings.length?'<ul>'+warnings.map(w=>'<li>'+esc(w)+'</li>').join('')+'</ul>':'')+'</details>';
}
export function refreshCalculatedValues(root,data){
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
