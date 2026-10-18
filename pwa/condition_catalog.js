// Canonical condition IDs are persisted verbatim in character/token state.
// Italian is presentation-only; never translate a value sent to the desktop.
export const CORE_CONDITIONS = Object.freeze([
  "blinded","charmed","deafened","exhaustion","frightened",
  "grappled","incapacitated","invisible","paralyzed","petrified",
  "poisoned","prone","restrained","stunned","unconscious",
  "concentrating","surprised","hidden","helped","dead"
]);
const ITALIAN_NAMES = Object.freeze({
  blinded:"Accecato",charmed:"Affascinato",deafened:"Assordato",
  exhaustion:"Indebolimento",frightened:"Spaventato",grappled:"Afferrato",
  incapacitated:"Incapacitato",invisible:"Invisibile",paralyzed:"Paralizzato",
  petrified:"Pietrificato",poisoned:"Avvelenato",prone:"Prono",
  restrained:"Trattenuto",stunned:"Stordito",unconscious:"Privo di sensi",
  concentrating:"Concentrazione",surprised:"Sorpreso",hidden:"Nascosto",
  helped:"Aiutato",dead:"Morto",
  "5etools:effects:xphb:bloodied":"Sanguinante"
});
const compareItalian = new Intl.Collator("it", {sensitivity:"base"}).compare;
export function conditionLabel(id, nativeName="") {
  return ITALIAN_NAMES[id] || nativeName || id;
}
export function conditionOptions(catalog, edition="2014", active=[]) {
  const version=edition==="2024"?"2024":"2014";
  const nativeRows=catalog?.editions?.[version];
  const source=Array.isArray(nativeRows)&&nativeRows.length
    ? nativeRows : CORE_CONDITIONS.map(id=>({id,name:id,category:"conditions"}));
  const result=[], seen=new Set();
  for (const row of source) {
    const id=String(row?.id||"");
    if(!id||seen.has(id))continue;
    seen.add(id);
    result.push({id,label:conditionLabel(id,String(row.name||"")),category:String(row.category||"conditions")});
  }
  // An already applied custom condition must remain visible and removable even
  // when its source catalog is temporarily unavailable (offline or changed).
  for(const raw of Array.isArray(active)?active:[]){
    const id=String(raw||"");
    if(!id||seen.has(id))continue;
    seen.add(id);
    result.push({id,label:conditionLabel(id),category:"conditions"});
  }
  return result.sort((a,b)=>compareItalian(a.label,b.label)||a.id.localeCompare(b.id));
}
