// Render local/offline calculations; no desktop sessions or API calls.
import {ABILITIES,SKILLS} from "./sheet_rules.js";
const esc=v=>String(v??"—").replace(/[&<>"']/g,c=>({
  "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const signed=value=>value===null||value===undefined?"—":Number(value)>=0?"+"+value:String(value);
const metric=(label,value)=>'<div class="derived-metric"><span>'+esc(label)+'</span><strong>'+esc(value)+'</strong></div>';
// A single readout contract is shared by every native-style section. Refresh
// only the outputs, leaving focused editors and pending user input in place.
export function calculatedValue(data,target,{signed:sign=false,suffix=""}={}){
  const value=data?.values?.[target];
  return (sign?signed(value):value??"—")+suffix;
}
export function formulaReadout(data,target,label,{signed:sign=false,suffix="",bonusTarget=target}={}){
  const rollable=/^(?:ability_mod:|save:|skill:|attack_hit:|casting_hit:)/.test(target)||target==='initiative';
  const tag=rollable?'button':'output';
  return '<span class="sheet-formula"><'+tag+(rollable?' type="button" class="sheet-result" data-act="sheet-roll" data-target="'+esc(target)+'" data-label="'+esc(label)+'"':'')+' data-calculated="'+esc(target)+
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
