// Portable basic calculations work offline. Anything involving origins,
// armor, conditions, class progression or grants must come from native Godot.
export const ABILITIES=[["str","Forza"],["dex","Destrezza"],["con","Costituzione"],
  ["int","Intelligenza"],["wis","Saggezza"],["cha","Carisma"]];
export const SKILLS=[
  ["acrobatics","Acrobazia"],["animal handling","Addestrare animali"],
  ["arcana","Arcano"],["athletics","Atletica"],["deception","Inganno"],
  ["history","Storia"],["insight","Intuizione"],["intimidation","Intimidire"],
  ["investigation","Indagare"],["medicine","Medicina"],["nature","Natura"],
  ["perception","Percezione"],["performance","Intrattenere"],
  ["persuasion","Persuasione"],["religion","Religione"],
  ["sleight of hand","Rapidità di mano"],["stealth","Furtività"],
  ["survival","Sopravvivenza"]
];
export function offlineBasics(record={}){
  const abilities={};
  for(const [id] of ABILITIES){
    const raw=Number(record.abilities?.[id]??10),score=Number.isFinite(raw)?raw:10;
    abilities[id]={score,modifier:Math.floor((score-10)/2)};
  }
  const classes=Array.isArray(record.classes)?record.classes:[];
  const classLevels=classes.filter(row=>String(row?.name||"").trim()).reduce((sum,row)=>sum+
    Math.max(0,Math.min(20,Number(row?.level)||0)),0);
  // Godot disregards the 'level' field when no class is actually selected.
  const level=Math.max(1,Math.min(20,classLevels||
    (record.class?Number(record.level)||1:1)));
  const proficiency=record.kind==="monster"?null:2+Math.floor((level-1)/4);
  return {source:"offline",schema:1,abilities,
    stats:{proficiency,level},saves:{},skills:{},spell_slots:[],attacks:[]};
}
const html=value=>String(value??"").replace(/[&<>"']/g,c=>({
  "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const signed=n=>Number(n)>=0?"+"+n:String(n);
const metric=(name,value,note="")=>'<div class="derived-metric"><span>'+html(name)+
  '</span><strong>'+html(value)+'</strong>'+(note?'<small>'+html(note)+'</small>':'')+'</div>';
const NA="—";
export function derivedContent(section,data){
  const native=data?.source==="godot",a=data?.abilities||{},stats=data?.stats||{};
  if(section==="info")return '<div class="derived-metrics">'+
    metric("Bonus competenza",stats.proficiency??NA)+
    (native?metric("CA",stats.armor_class)+metric("Iniziativa",signed(stats.initiative))+
      metric("PF massimi",stats.max_hp)+metric("Camminata",String(stats.speeds?.walk??0)+" ft"):'')+
    '</div>';
  if(section==="stats"){
    const mods=ABILITIES.map(([id,name])=>metric(name,
      a[id]?signed(a[id].modifier):NA,"Punteggio "+(a[id]?.score??10))).join("");
    if(!native)return '<div class="derived-metrics">'+mods+
      metric("Competenza",stats.proficiency??NA)+'</div>';
    const saves=ABILITIES.map(([id,name])=>metric(name,
      data.saves?.[id]!==undefined?signed(data.saves[id]):NA)).join("");
    const skills=SKILLS.map(([id,name])=>metric(name,
      data.skills?.[id]!==undefined?signed(data.skills[id]):NA)).join("");
    return '<h3>Caratteristiche effettive</h3><div class="derived-metrics">'+mods+
      metric("Competenza",stats.proficiency??NA)+
      metric("Percezione passiva",stats.passive_perception??NA)+'</div>'+
      '<details><summary>Tiri salvezza calcolati</summary><div class="derived-metrics">'+saves+
      '</div></details><details><summary>Abilità calcolate</summary><div class="derived-metrics">'+skills+
      '</div></details>';
  }
  if(!native)return '<p class="hint">CA, iniziativa, attacchi, punti ferita effettivi e slot dipendono dal motore Godot. Per visualizzarli associa la PWA al desktop e attiva il calcolo nativo.</p>';
  if(section==="battle"){
    const speeds=stats.speeds||{};
    const basic=metric("Classe armatura",stats.armor_class)+metric("Iniziativa",signed(stats.initiative))+
      metric("PF massimi effettivi",stats.max_hp)+metric("Camminata",String(speeds.walk??0)+" ft")+
      ["climb","swim","fly","burrow"].filter(id=>Number(speeds[id])>0).map(id=>
        metric({climb:"Scalata",swim:"Nuoto",fly:"Volo",burrow:"Scavo"}[id],
          String(speeds[id])+" ft")).join("")+
      (stats.automatic_hp?.available?metric("PF automatici",stats.automatic_hp.value,
        stats.automatic_hp.detail||""):"");
    const attacks=(data.attacks||[]).map(x=>
      '<div class="derived-attack"><strong>'+html(x.name)+'</strong> · '+html(signed(x.hit))+
      ' per colpire · '+html(x.damage||NA)+
      (x.range_feet?' · '+html(x.range_feet)+' ft':'')+
      (x.hit_formula?'<details><summary>Formula tiro per colpire</summary><p>'+
        html(x.hit_formula)+'</p></details>':'')+'</div>').join("");
    const explain=Object.entries(data.explanations||{}).filter(([,value])=>value).map(([id,value])=>
      '<p><strong>'+html({armor_class:"CA",initiative:"Iniziativa",hit_points:"PF",speed:"Movimento"}[id]||id)+
      ':</strong> '+html(value)+'</p>').join("");
    return '<div class="derived-metrics">'+basic+'</div>'+
      (attacks?'<details><summary>Attacchi calcolati ('+(data.attacks||[]).length+')</summary>'+
      attacks+'</details>':'')+
      (explain?'<details><summary>Origine dei bonus</summary>'+explain+'</details>':'');
  }
  if(section==="magic"){
    const slots=(data.spell_slots||[]).filter(x=>x.total>0||x.spent>0);
    return '<div class="derived-metrics">'+slots.map(x=>metric("Slot livello "+x.level,
      Math.max(0,x.total-x.spent)+" / "+x.total,"Usati: "+x.spent)).join("")+
      (data.pact_slots?.total>0?metric("Magia del Patto",
        Math.max(0,data.pact_slots.total-data.pact_slots.spent)+" / "+data.pact_slots.total,
        "Slot di livello "+data.pact_slots.level):'')+'</div>'+
      (!slots.length&&!data.pact_slots?.total?'<p class="hint">Nessuno slot disponibile.</p>':'');
  }
  return "";
}
