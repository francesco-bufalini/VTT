// Read-only 5etools/Fight Club-derived catalogs are the SAME packaged datasets
// used by the native VTT, not scraped at runtime or reimplemented game rules.
import { listRecords } from "./storage.js";

export const CATALOG_CATEGORIES = [
  ["spells","Incantesimi"],["items","Oggetti"],["magic_items","Oggetti magici"],["weapons","Armi"],
  ["armor","Armature"],["tools","Strumenti"],["mundane_items","Oggetti mondani"],
  ["races","Specie"],["classes","Classi"],["feats","Talenti"],
  ["backgrounds","Background"],["class_features","Privilegi di classe"],
  ["species_traits","Tratti razziali"],["optional_features","Privilegi opzionali"]
];
const GROUPS = {
  backgrounds:"/catalog/backgrounds.json",races:"/catalog/features.json",
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
const supplementary = new Map();
async function supplementalCatalog(category){
  if(category==='races'){
    // Descriptive indexes omit speed and stable native race IDs.
    const {loadRuleCatalogs}=await import('./sheet_rules.js');
    const rules=await loadRuleCatalogs();
    if(Array.isArray(rules.classMechanics?.races))return [...rules.classMechanics.races,...(rules.classMechanics.subraces||[])];
  }
  const path=(["classes","subclasses","class_features","subclass_features"].includes(category))?
    "/catalog/classes.json":category==="races"?"/catalog/features.json":"/catalog/backgrounds.json";
  if(!supplementary.has(path)){
    const response=await fetch(path,{cache:"no-store"});
    if(!response.ok)throw new Error("Riferimenti offline non disponibili: "+category);
    supplementary.set(path,await response.json());
  }
  const data=supplementary.get(path);
  if(["classes","subclasses","class_features","subclass_features"].includes(category)){
    if(data?.version!==1||!Array.isArray(data[category]))throw Error("Indice classi non valido");
    return data[category];
  }
  const rows=data?.[category];
  if(!rows||typeof rows!=="object")return [];
  if(Array.isArray(rows))return rows;
  return Object.entries(rows).map(([key,record])=>{
    const parts=key.split("|");
    const original=String(record?.name||parts[0]);
    const name=original.replace(/(^|[\s-])([a-z])/g,(_m,p,c)=>p+c.toUpperCase());
    return {name,source:String(record?.source||parts[1]||"").toUpperCase()};
  });
}
let packagedSpells=null;
async function spellCatalog(){
  if(packagedSpells)return packagedSpells;
  const response=await fetch("/catalog/spells.json",{cache:"no-store"});
  if(!response.ok)throw new Error("Catalogo incantesimi non disponibile offline.");
  const data=await response.json();
  if(data?.version!==1||!Array.isArray(data.spells))throw new Error("Catalogo incantesimi non valido.");
  let legacy=[];
  try{const {loadRuleCatalogs}=await import('./sheet_rules.js');legacy=(await loadRuleCatalogs()).classMechanics?.legacy_spells||[];}catch{ /* The current catalog remains available independently of numeric indexes. */ }
  packagedSpells=[...new Map([...data.spells,...legacy].map(s=>[s.id,s])).values()];
  return packagedSpells;
}
export async function catalogEntries(category) {
  if(category==="spells"){
    const spells=await spellCatalog();
    const known=await listRecords("global","homebrew");
    return [...spells.map(spell=>({...spell,_category:"spells",_homebrew:false})),
      ...known.filter(record=>record.id?.split(":")[2]==="spells")
        .map(record=>({...record.data.data,...record.data,_category:"spells",_homebrew:true}))];
  }
  const extra=["classes","subclasses","class_features","subclass_features","races","backgrounds"].includes(category);
  const data=extra?null:await loadReferenceCatalog();
  const keys=category==="items"?
    ["weapons","armor","tools","mundane_items","magic_items"]:[category];
  const source=extra?await supplementalCatalog(category):keys.flatMap(key=>
    Array.isArray(data[key])?data[key].map(row=>({...row,_category:key})):[]
  );
  const rows=source.map(row=>({...row,_category:row._category||category,_homebrew:false}));
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
