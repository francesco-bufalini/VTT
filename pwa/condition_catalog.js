// Persist native IDs unchanged. Italian labels are display-only.
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
export const CONDITION_CATEGORIES = Object.freeze([
  ["conditions","Condizioni"],["diseases","Malattie"],["effects","Effetti"]
]);
 
// Exhaustion uses the existing numeric field on the creature, also read by
// desktop rules and rest recovery. Virtual condition IDs expose each level
// through the same selector without altering native condition identifiers.
export const EXHAUSTION_CONDITION_CATEGORY = "exhaustion_levels";
export function exhaustionLevel(record={}){
  const value=Number(record.exhaustion??record.exhaustion_level??0);
  return Number.isFinite(value)?Math.max(0,Math.min(6,Math.trunc(value))):0;
}
export function exhaustionConditionRows(edition="2014",source=null){
  const version=edition==="2024"?"2024":"2014";
  return Array.from({length:6},(_,index)=>{
    const level=index+1;
    return {id:"exhaustion:"+level,name:"Exhaustion "+level,
      label:"Indebolimento · Livello "+level,category:EXHAUSTION_CONDITION_CATEGORY,
      source:source?.source||"D&D "+version,page:source?.page,
      entries:[
        "Indebolimento di livello "+level+". Gli effetti del livello seguono le regole "+version+".",
        ...(source?.entries==null?[]:[source.entries])
      ]};
  });
}
export function exhaustionSelectionPatch(record,id,checked){
  const match=/^exhaustion:([1-6])$/.exec(String(id||""));
  if(!match)return null;
  const previous=exhaustionLevel(record),selected=Number(match[1]);
  const next=checked?selected:previous===selected?0:previous;
  // Clean up stale legacy marker(s), but leave all other conditions intact.
  const conditions=(Array.isArray(record.conditions)?record.conditions:[])
    .filter(value=>value!=="exhaustion"&&!/^exhaustion:[1-6]$/.test(String(value)));
  return {exhaustion:next,conditions};
}

const compareItalian = new Intl.Collator("it",{sensitivity:"base"}).compare;
export function conditionLabel(id,nativeName=""){
  return ITALIAN_NAMES[id] || nativeName || id;
}
export function conditionOptions(catalog,edition="2014",active=[]){
  const version=edition==="2024"?"2024":"2014";
  const nativeRows=catalog?.editions?.[version];
  const source=Array.isArray(nativeRows)&&nativeRows.length
    ? nativeRows : CORE_CONDITIONS.map(id=>({id,name:id,category:"conditions"}));
  const result=[],seen=new Set();
  for(const row of source){
    const id=String(row?.id||"");
    if(!id||seen.has(id))continue;
    seen.add(id);
    result.push({...row,id,label:conditionLabel(id,String(row.name||"")),category:String(row.category||"conditions")});
  }
  // Keep existing unknown/homebrew statuses removable when their source is offline.
  for(const raw of Array.isArray(active)?active:[]){
    const id=String(raw||"");
    if(!id||seen.has(id))continue;
    seen.add(id);
    result.push({id,label:conditionLabel(id),category:"conditions"});
  }
  return result.sort((a,b)=>compareItalian(a.label,b.label)||a.id.localeCompare(b.id));
}

// Build the same selectable 2014/2024 5etools conditions, diseases and effects
// as ContentCatalog.condition_definitions() without requiring a live desktop.
// Legacy IDs are retained for condition effects already saved in creature sheets.
export function conditionCatalogFrom5etools(payload){
  const effects=Array.isArray(payload?.entries)?payload.entries:[];
  const editions={};
  for(const edition of ["2014","2024"]){
    const rows=[],seen=new Set();
    for(const id of CORE_CONDITIONS){
      const effect=effects.find(row=>row?.edition===edition&&(
        row.legacy_id===id ||
        (id==="concentrating"&&row.name==="Concentration") ||
        (id==="surprised"&&row.name==="Surprised")
      ));
      if(effect){
        rows.push({...effect,id});
        seen.add(id);
      }else if(["helped","hidden","dead"].includes(id)){
        rows.push({id,name:id,category:"conditions",source:"VTT",
          entries:["Marcatore tattico senza effetti automatici."]});
        seen.add(id);
      }
    }
    for(const effect of effects){
      if(effect?.edition!==edition||effect.legacy_id||
        ["Concentration","Surprised"].includes(effect.name)||!effect.id||seen.has(effect.id))continue;
      rows.push(effect);
      seen.add(effect.id);
    }
    editions[edition]=rows;
  }
  return {editions};
}

// Live desktop rows carry optional homebrew content and override bundled rows.
// An absent connection never discards the local 5etools catalog.
export function mergeConditionCatalog(local,desktop){
  if(!local)return desktop||null;
  if(!desktop)return local;
  const editions={};
  for(const edition of ["2014","2024"]){
    const ids=new Map();
    for(const row of local.editions?.[edition]||[])if(row?.id)ids.set(row.id,row);
    for(const row of desktop.editions?.[edition]||[]){
      if(!row?.id)continue;
      ids.set(row.id,{...(ids.get(row.id)||{}),...row});
    }
    editions[edition]=[...ids.values()];
  }
  return {editions};
}

const escapeHtml=value=>String(value??"").replace(/[&<>"']/g,c=>({
  "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
})[c]);
// Strip 5etools reference markup while keeping its visible label. Never
// interpret raw compendium strings as HTML.
export function fiveToolsVisibleText(value){
  return String(value??"").replace(/\{@([\w]+) ([^{}]+)\}/g,(_,kind,parts)=>{
    const fields=parts.split("|");
    return fields[2]||fields[0];
  });
}
function renderEntry(value,depth=0){
  if(depth>12||value==null)return "";
  if(typeof value==="string")return '<p>'+escapeHtml(fiveToolsVisibleText(value))+'</p>';
  if(Array.isArray(value))return value.map(v=>renderEntry(v,depth+1)).join("");
  if(typeof value!=="object")return '<p>'+escapeHtml(value)+'</p>';
  const name=value.name?'<h4>'+escapeHtml(fiveToolsVisibleText(value.name))+'</h4>':"";
  if(value.type==="list")return name+'<ul>'+((value.items||[]).map(item=>
    '<li>'+renderEntry(item,depth+1).replace(/^<p>/,"").replace(/<\/p>$/,"")+'</li>').join(""))+'</ul>';
  if(value.type==="table")return name+'<div class="condition-table-scroll"><table><thead><tr>'+
    (value.colLabels||[]).map(cell=>'<th>'+escapeHtml(fiveToolsVisibleText(cell))+'</th>').join("")+
    '</tr></thead><tbody>'+(value.rows||[]).map(row=>'<tr>'+
      (Array.isArray(row)?row:[]).map(cell=>'<td>'+escapeHtml(fiveToolsVisibleText(
        typeof cell==="object"?cell?.entry??cell?.roll?.exact??"":cell
      ))+'</td>').join("")+'</tr>').join("")+'</tbody></table></div>';
  const contents=[value.entry,...(Array.isArray(value.entries)?value.entries:[]),
    ...(Array.isArray(value.items)?value.items:[])].filter(v=>v!=null);
  return name+contents.map(item=>renderEntry(item,depth+1)).join("");
}
export function conditionDescriptionHtml(row){
  const category=row?.category===EXHAUSTION_CONDITION_CATEGORY?"Indebolimento":
    CONDITION_CATEGORIES.find(([id])=>id===row?.category)?.[1]||"Stato";
  const source=String(row?.source||row?.origin||"");
  const metadata=[category,source&&(source==="VTT"?"VTT":source),
    row?.page!=null?"pag. "+row.page:""].filter(Boolean);
  const entries=row?.entries??row?.description;
  const content=renderEntry(entries);
  return '<div class="condition-description" data-condition-detail="'+escapeHtml(row?.id||"")+'">'+
    '<p class="condition-description-source">'+escapeHtml(metadata.join(" · "))+'</p>'+
    (content||'<p>Descrizione non disponibile nel catalogo locale.</p>')+'</div>';
}
