// Structured action economy overview; all computations remain local.
export const GROUPS=[["action","Azione"],["bonus","Azione bonus"],["free","Azione gratuita"],["movement","Movimento"],["reaction","Reazione"]];
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
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;','\'':'&#39;'}[c]));
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
 const known=new Set([...(record.prepared_spells||[]),...(record.known_spells||[])].map(x=>typeof x==="string"?x:String(x.id||x.spell_id||"")));
 for(const grant of record.origin_spell_grants||[])if(!grant.disabled)known.add(String(grant.spell_id||""));
 for(const spell of spells){
  if(!known.has(String(spell.id||"")))continue;
  const time=Array.isArray(spell.time)?spell.time[0]?.unit:spell.casting_time||spell.time;
  const grant=(record.origin_spell_grants||[]).find(g=>g.spell_id===spell.id&&!g.disabled);
  add(spell.name||spell.id,time,"incantesimo",spell.description||"",grant?.tracker_id||(Number(spell.level)>0?"Slot incantesimo":""));
 }
 for(const feature of [...(record.action_grants||[]),...(calculated.actions||[])])
  if(feature&&!feature.disabled)add(feature.name||feature.title,feature.action_type||feature.activation||feature.time,"capacità",feature.description||feature.text,feature.tracker_id);
 return entries;
}
export function actionEconomyView(record,calculated,spells=[]){
 const entries=actionEntries(record,calculated,spells);
 return GROUPS.map(([id,title])=>'<section class="panel"><h2>'+title+'</h2>'+
  entries.filter(e=>e.time===id).map(e=>'<details class="native-entry"><summary><strong>'+esc(e.name)+'</strong> · '+esc(e.type)+(e.tracker?' · '+esc(e.tracker):'')+'</summary><p>'+esc(e.description)+'</p></details>').join('')+
  (!entries.some(e=>e.time===id)?'<p class="hint">Nessuna azione.</p>':'')+'</section>').join('');
}
