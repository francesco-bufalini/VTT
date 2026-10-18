// Read-only 5etools/Fight Club-derived catalogs are the SAME packaged datasets
// used by the native VTT, not scraped at runtime or reimplemented game rules.
import { listRecords, getRecord, deleteRecordIfRevision } from "./storage.js";
import { saveHomebrewDefinition, listCreatures } from "./creatures.js";

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
let speciesTypePromise;
async function speciesTypeLookup(){
 if(!speciesTypePromise)speciesTypePromise=fetch('/catalog/species_types.json')
  .then(response=>{if(!response.ok)throw Error('Indice tipi specie non disponibile');return response.json();})
  .then(data=>data?.version===1&&Array.isArray(data.races)?data.races:[])
  .catch(()=>{speciesTypePromise=null;return [];});
 return speciesTypePromise;
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
  const types=category==='races'?await speciesTypeLookup():[];
  const typedById=new Map(types.map(row=>[String(row.id||''),row]));
  const typedByName=new Map(types.map(row=>[String(row.name||'').toLowerCase()+'|'+String(row.source||'').toLowerCase(),row]));
  const rows=source.map(row=>{
    const matched=category==='races'?(typedById.get(String(row.id||''))||
      typedByName.get(String(row.name||'').toLowerCase()+'|'+String(row.source||'').toLowerCase())):null;
    return {...row,...(matched?{creatureTypes:matched.creatureTypes}:{}),_category:row._category||category,_homebrew:false};
  });
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

// Portable quick homebrew domain in a URL already allowed by the native PWA server.
// Native quick_custom_catalog.gd equivalent. Save the exact portable
// homebrew definition shape used by Godot, never modify packaged 5etools data.
const TYPES=new Set(["weapon","shield","armor","tool","magic","other"]);
const ALLOWED=new Set(["items","feats","backgrounds"]);
const FIELDS={skill:"skillProficiencies",tool:"toolProficiencies",
  language:"languageProficiencies",weapon:"weaponProficiencies",
  armor:"armorProficiencies",save:"saveProficiencies",expertise:"expertise"};
const str=v=>String(v??"").trim();
export const QUICK_NAMESPACE="quick_local";
export function quickDefinition(category,name,description="",proficiencies=[],details={},id=""){
  name=str(name);
  if(!ALLOWED.has(category)||!name||name.length>120||typeof description!=="string"||
     description.length>12000)throw Error("Nome o categoria homebrew non validi.");
  const suffix=id||"local_"+crypto.randomUUID().replace(/-/g,"").slice(0,32);
  if(!/^local_[a-z0-9_-]{1,59}$/.test(suffix))throw Error("Identificativo homebrew non valido.");
  const text=description.trim();
  const data={description:text,entries:[text]};
  if(category==="items"){
    const type=str(details.custom_item_type||"other");
    if(!TYPES.has(type))throw Error("Tipo di oggetto non valido.");
    const value=Number(details.value??0);
    if(!Number.isInteger(value)||value<0||value>100000000)
      throw Error("Valore dell'oggetto non valido.");
    Object.assign(data,{type:str(details.type||"OTH"),custom_item_type:type,
      rarity:str(details.rarity||"none"),value,value_gp:value});
  }else{
    if(!Array.isArray(proficiencies))throw Error("Competenze non valide.");
    for(const grant of proficiencies){
      const kind=str(grant?.kind),key=str(grant?.key).toLowerCase();
      const field=FIELDS[kind];
      if(!field||!key||key.length>120||!/^[a-z0-9 _-]+$/.test(key))
        throw Error("Competenza homebrew non valida.");
      (data[field]??=[]);
      if(!data[field].some(item=>item[key]===true))data[field].push({[key]:true});
    }
  }
  return {id:"homebrew:"+QUICK_NAMESPACE+":"+category+":"+suffix,
    name,source:"Personalizzato",category,data};
}
export async function createQuickHomebrew(category,name,description="",proficiencies=[],details={}){
  const definition=quickDefinition(category,name,description,proficiencies,details);
  const records=await listRecords("global","homebrew");
  if(category!=="items"&&records.some(row=>
    row.data.id?.startsWith("homebrew:"+QUICK_NAMESPACE+":"+category+":")&&
    str(row.data.name).toLowerCase()===definition.name.toLowerCase()))
    throw Error("Nome personalizzato già in uso in questa categoria.");
  await saveHomebrewDefinition(definition);
  return definition;
}
// Legacy refs to quick custom feats/backgrounds use source + name; keep
// stable source IDs so removal of an origin stops applying its grants.
export function quickGrantPatch(creature,definition){
  if(!["feats","backgrounds"].includes(definition?.category))return {};
  const label=definition.name,source=definition.source;
  const sid=(definition.category==="feats"?"feat":"background")+
    "|"+source.toLowerCase()+"|"+label.toLowerCase();
  const proficiency_choices=Array.isArray(creature.proficiency_choices)?
    structuredClone(creature.proficiency_choices):[];
  for(const [kind,field] of Object.entries(FIELDS)){
    for(const entry of definition.data?.[field]||[]){
      if(!entry||typeof entry!=="object")continue;
      for(const [key,on] of Object.entries(entry)){
        if(on!==true)continue;
        if(!proficiency_choices.some(row=>row.origin_id===sid&&row.kind===kind&&row.key===key))
          proficiency_choices.push({kind,key,origin_id:sid,
            origin_name:label,disabled:false,automatic:false});
      }
    }
  }
  return {proficiency_choices};
}

export async function deleteQuickHomebrew(id){
  if(typeof id!=="string"||!/^homebrew:quick_local:(items|feats|backgrounds):local_[a-z0-9_-]+$/.test(id))
    throw Error("Solo contenuti rapidi locali possono essere eliminati.");
  const stored=await getRecord("global","homebrew",id);
  if(!stored)return false;
  const category=stored.data.category,characters=await listCreatures();
  for(const {creature:c} of characters){
    const used=(c.inventory||[]).some(row=>row?.id===id)||
      (c.feats_catalog||[]).some(row=>row?.id===id)||
      (category==="backgrounds"&&(c.background_id===id||
        (c.background===stored.data.name&&c.background_source===stored.data.source)));
    if(used)throw Error("Contenuto ancora in uso da una creatura: rimuovi prima il riferimento.");
  }
  return deleteRecordIfRevision("global","homebrew",id,stored.revision);
}
