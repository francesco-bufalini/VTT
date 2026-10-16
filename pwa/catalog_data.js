// Read-only 5etools/Fight Club-derived catalogs are the SAME packaged datasets
// used by the native VTT, not scraped at runtime or reimplemented game rules.
import { listRecords } from "./storage.js";

export const CATALOG_CATEGORIES = [
  ["items","Oggetti"],["magic_items","Oggetti magici"],["weapons","Armi"],
  ["armor","Armature"],["tools","Strumenti"],["mundane_items","Oggetti mondani"],
  ["races","Specie"],["classes","Classi"],["feats","Talenti"],
  ["backgrounds","Background"],["class_features","Privilegi di classe"],
  ["species_traits","Tratti razziali"],["optional_features","Privilegi opzionali"]
];
const GROUPS = {
  backgrounds:"/catalog/backgrounds.json",
  feats:"/catalog/features.json",optional_features:"/catalog/features.json",
  species_traits:"/catalog/features.json",class_features:"/catalog/features.json",
  items:"/catalog/items.json",magic_items:"/catalog/items.json",
  weapons:"/catalog/items.json",armor:"/catalog/items.json",
  tools:"/catalog/items.json",mundane_items:"/catalog/items.json"
};
let catalog=null;
const details=new Map();
export async function loadReferenceCatalog() {
  if(catalog)return catalog;
  const response=await fetch("/catalog/player.json",{cache:"no-store"});
  if(!response.ok)throw new Error("Catalogo del desktop non disponibile o non ancora installato offline.");
  const value=await response.json();
  if(!value || typeof value!=="object" || !Array.isArray(value.items||value.weapons||[])) {
    throw new Error("Struttura del catalogo non valida.");
  }
  catalog=value;
  return catalog;
}
export async function catalogEntries(category) {
  const data=await loadReferenceCatalog();
  const keys=category==="items"?
    ["weapons","armor","tools","mundane_items","magic_items"]:[category];
  const rows=keys.flatMap(key=>Array.isArray(data[key])?data[key].map(row=>({
    ...row, _category:key, _homebrew:false
  })):[]);
  const homebrew=await listRecords("global","homebrew");
  for(const stored of homebrew){
    const value=stored.data;
    const key=value?.id?.split(":")[2];
    const matches=category==="items"?
      ["items","weapons","armor","tools","mundane_items","magic_items"].includes(key):
      category===key;
    if(matches)rows.push({...value.data,...value,_category:key,_homebrew:true});
  }
  return rows.sort((a,b)=>String(a.name||"").localeCompare(String(b.name||"")));
}
function textOf(value,items,depth=0){
  if(depth>7||items.length>75||value==null)return;
  if(typeof value==="string")items.push(value);
  else if(Array.isArray(value))for(const part of value)textOf(part,items,depth+1);
  else if(typeof value==="object"){
    for(const field of ["name","entry","entries","items","description","text","fluff","additionalEntries"])
      if(field in value)textOf(value[field],items,depth+1);
  }
}
export function flattenDescription(value) {
  const result=[];
  for(const key of ["entries","description","text","fluff","additionalEntries"]){
    if(value?.[key]!==undefined)textOf(value[key],result);
  }
  return result.join("\n\n").replace(/\{@[^ ]+ ([^}|]+)(?:\|[^}]*)?\}/g,"$1").slice(0,15000);
}
export async function detailedEntry(category,entry) {
  const path=GROUPS[category]||GROUPS[entry?._category];
  if(!path)return entry;
  if(!details.has(path)){
    try {
      const res=await fetch(path,{cache:"no-store"});
      if(!res.ok)throw new Error("Descrizioni non disponibili");
      details.set(path,await res.json());
    }catch(error){
      return {...entry,_description_warning:"Descrizione estesa offline non ancora scaricata."};
    }
  }
  const index=details.get(path);
  const cat=entry._category||category;
  const name=String(entry.name||"").trim().toLowerCase();
  const source=String(entry.source||"").trim().toLowerCase();
  const lookup=name+"|"+source;
  const candidate=index?.[cat]?.[lookup];
  if(!candidate || typeof candidate!=="object")return entry;
  const copy={...entry};
  for(const field of ["entries","description","text","fluff","feats"]){
    if(copy[field]==null||copy[field]===""||(Array.isArray(copy[field])&&!copy[field].length)){
      if(candidate[field]!=null)copy[field]=candidate[field];
    }
  }
  return copy;
}
