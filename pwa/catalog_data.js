// Read-only 5etools/Fight Club-derived catalogs are the SAME packaged datasets
// used by the native VTT, not scraped at runtime or reimplemented game rules.
import { listRecords, getRecord, deleteRecordIfRevision } from "./storage.js";
import { saveHomebrewDefinition, listCreatures } from "./creatures.js";
import {racialPowerSubraces} from "./species_powers.js";
import {expandSpeciesVariantFamilies,selectableVariantSubraces} from "./species_variant_families.js";
import { characterHomebrewEntries, appendSharedHomebrew } from "./character_homebrew.js";

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
// Display the two mutually exclusive 2014 Custom Lineage options as distinct
// species picker entries. Both retain the original 5etools race identity in
// saved characters, so existing score, language and feat origins stay valid.
export function customLineageRaceOptions(races=[]){
 return (Array.isArray(races)?races:[]).flatMap(race=>{
  if(race?.name!=='Custom Lineage'||String(race.source||'').toUpperCase()!=='TCE'||
     race.raceName)return [race];
  return [
   {choice:'darkvision',suffix:'Scurovisione (60 ft)'},
   {choice:'skill',suffix:'Competenza in abilità'}
  ].map(option=>({...race,
    id:'vtt:races:tce:custom-lineage:'+option.choice,
    name:'Custom Lineage — '+option.suffix,
    canonical_race_name:race.name,canonical_race_id:race.id,
    origin_sense_choice:option.choice}));
 });
}
// Only canonical species + independent subrace entries are selectable.
// Full 5etools variant records remain the source of subtype descriptions.
export function canonicalSpeciesReferences(races=[],subraces=[]){
 const key=(name,source)=>String(name||'').trim().toLowerCase()+'|'+String(source||'').trim().toLowerCase();
 const flattened=new Set(subraces.filter(row=>row?.raceName&&row?.name).map(row=>
  key(row.raceName+' ('+row.name+')',row.source)));
 // Transfer still-packaged subtype metadata to the canonical reference.
 const canonicalSubraces=subraces.map(subrace=>{
  if(!subrace?.raceName)return subrace;
  const native=races.find(row=>key(row.name,row.source)===
   key(subrace.raceName+' ('+subrace.name+')',subrace.source));
  return native?{...subrace,
   ...(subrace.speed===undefined&&native.speed!==undefined?{speed:native.speed}:{}),
   ...(subrace.size===undefined&&native.size!==undefined?{size:native.size}:{}),
   ...(subrace.creatureTypes===undefined&&native.creatureTypes!==undefined?
    {creatureTypes:native.creatureTypes}:{})}:subrace;
 });
 return [...races.filter(row=>!row?.raceName&&!flattened.has(key(row.name,row.source))),...canonicalSubraces];
}
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
    if(Array.isArray(rules.classMechanics?.races)){
      const subraces=selectableVariantSubraces([...(rules.classMechanics.subraces||[]),
        ...racialPowerSubraces(rules.speciesPowers)]);
      const expanded=expandSpeciesVariantFamilies(rules.classMechanics.races,subraces,rules.speciesPowers);
      return customLineageRaceOptions(canonicalSpeciesReferences(expanded.races,expanded.subraces));
    }
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
let packagedSpellsPromise=null;
// A single full-catalog transfer is shared by background prefetch and any
// foreground search. Never download the whole compendium per character render.
async function spellCatalog(){
  if(packagedSpells)return packagedSpells;
  if(!packagedSpellsPromise)packagedSpellsPromise=(async()=>{
    const response=await fetch("/catalog/spells.json",{cache:"no-store"});
    if(!response.ok)throw new Error("Catalogo incantesimi non disponibile offline.");
    const data=await response.json();
    if(data?.version!==1||!Array.isArray(data.spells))throw new Error("Catalogo incantesimi non valido.");
    let legacy=[];
    try{const {loadRuleCatalogs}=await import('./sheet_rules.js');legacy=(await loadRuleCatalogs()).classMechanics?.legacy_spells||[];}
    catch{ /* The current catalog remains available independently of numeric indexes. */ }
    packagedSpells=[...new Map([...data.spells,...legacy].map(s=>[s.id,s])).values()];
    return packagedSpells;
  })().catch(error=>{packagedSpellsPromise=null;throw error;});
  return packagedSpellsPromise;
}

const scopedSpells=new Map();
const scopedRequests=new Map();
// Request the spell records currently visible on a character sheet. Class
// filters are only sent by the preparation popup, not the normal sheet.
export async function selectedSpellEntries(ids=[],classes=[]){
  const wanted=[...new Set(ids.map(id=>String(id||'')).filter(Boolean))].sort();
  const scopes=classes.filter(row=>row?.name).map(row=>({
    name:String(row.name),max_level:Math.max(0,Math.min(9,Number(row.max_level)||0))
  })).sort((a,b)=>a.name.localeCompare(b.name)||a.max_level-b.max_level);
  if(packagedSpells){
    const identifiers=new Set(wanted);
    return packagedSpells.filter(row=>identifiers.has(row.id)||scopes.some(scope=>
      Number(row.level)<=scope.max_level&&
      (row.classes||[]).some(name=>String(name).toLowerCase()===scope.name.toLowerCase())));
  }
  const key=JSON.stringify([wanted,scopes]);
  if(!scopedRequests.has(key)){
    const request=(async()=>{
      let selected;
      try{
        const response=await fetch("/catalog/spells/selected",{
          method:"POST",headers:{"Content-Type":"application/json"},
          body:JSON.stringify({ids:wanted,classes:scopes})
        });
        if(!response.ok)throw new Error("Riferimenti incantesimi non disponibili.");
        const data=await response.json();
        if(data?.version!==1||!Array.isArray(data.spells))
          throw new Error("Riferimenti incantesimi non validi.");
        selected=data.spells;
      }catch(error){
        // Older desktop bridges and static offline exports do not expose POST.
        // Reuse the already-cached full offline catalog if it is available,
        // without ever making it a requirement for opening a character sheet.
        const full=await spellCatalog();
        const keys=new Set(wanted);
        selected=full.filter(row=>keys.has(row.id)||scopes.some(scope=>
          Number(row.level)<=scope.max_level&&
          (row.classes||[]).some(name=>String(name).toLowerCase()===scope.name.toLowerCase())));
      }
      for(const spell of selected)if(spell?.id)scopedSpells.set(spell.id,spell);
      const homebrew=await listRecords("global","homebrew");
      for(const record of homebrew){
        if(record.id?.split(":")[2]!=="spells")continue;
        const spell={...record.data.data,...record.data,_category:"spells",_homebrew:true};
        if(spell.id)scopedSpells.set(spell.id,spell);
      }
      // Embedded homebrew can belong to a different character in this archive.
      for(const spell of characterHomebrewEntries("spells",await listCreatures()))
        if(spell.id&&!scopedSpells.has(spell.id))scopedSpells.set(spell.id,spell);
      return [...scopedSpells.values()];
    })();
    scopedRequests.set(key,request);
    request.catch(()=>scopedRequests.delete(key));
  }
  return scopedRequests.get(key);
}
let genericVariantsPromise;
export function genericItemVariants(){
 if(!genericVariantsPromise)genericVariantsPromise=fetch('/catalog/generic_item_variants.json')
  .then(async response=>{if(!response.ok)throw Error('Varianti 5eTools non disponibili offline.');
   const data=await response.json();
   if(data?.version!==1||!Array.isArray(data.variants))throw Error('Catalogo varianti non valido.');
   return data.variants;
  }).catch(error=>{genericVariantsPromise=null;throw error;});
 return genericVariantsPromise;
}
export async function catalogEntries(category) {
  if(category==='generic_variants')return genericItemVariants();
  if(category==="spells"){
    const spells=await spellCatalog();
    const known=await listRecords("global","homebrew");
    const base=[...spells.map(spell=>({...spell,_category:"spells",_homebrew:false})),
      ...known.filter(record=>record.id?.split(":")[2]==="spells")
        .map(record=>({...record.data.data,...record.data,_category:"spells",_homebrew:true}))];
    return appendSharedHomebrew(base,characterHomebrewEntries("spells",await listCreatures()))
      .sort((a,b)=>String(a.name||"").localeCompare(String(b.name||"")));
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
  // Include complete custom records kept in other local character sheets.
  return appendSharedHomebrew(rows,characterHomebrewEntries(category,await listCreatures()))
    .sort((a,b)=>String(a.name||"").localeCompare(String(b.name||"")));
}
function textOf(value,items,depth=0){
  if(depth>7||items.length>75||value==null)return;
  if(typeof value==="string")items.push(value);
  else if(Array.isArray(value))for(const part of value)textOf(part,items,depth+1);
  else if(typeof value==="object"){
    for(const field of ["name","entry","entries","items","description","text","fluff","additionalEntries","entriesTemplate","itemTypeAdditionalEntries"])
      if(field in value)textOf(value[field],items,depth+1);
  }
}
const DESCRIPTION_FIELDS=["entries","description","text","fluff","additionalEntries","entriesTemplate","itemTypeAdditionalEntries"];
export function flattenDescription(value) {
 const result=[];
 for(const key of DESCRIPTION_FIELDS)
  if(value?.[key]!==undefined)textOf(value[key],result);
 // 5etools tattoos and some other items keep descriptive text in inherits.
 if(value?.inherits&&typeof value.inherits==="object")
  for(const key of DESCRIPTION_FIELDS)
   if(value.inherits[key]!==undefined)textOf(value.inherits[key],result);
 return [...new Set(result)].join("\n\n")
  .replace(/\{@[^ ]+ ([^}|]+)(?:\|[^}]*)?\}/g,"$1").slice(0,15000);
}
// 5etools uses {#itemEntry Name|Source} for shared magic-item prose.
// Offline item indexes omit some item-group parents; resolve what is packaged
// and provide a compact rule summary for the missing Absorbing Tattoo group.
const ITEM_ENTRY_REF=/^\{#itemEntry\s+([^|}]+?)(?:\|([^}]+))?\}$/i;
const ABSORBING_DAMAGE_TYPES=new Set(["acid","cold","fire","force","lightning",
 "necrotic","poison","psychic","radiant","thunder"]);
function missingItemGroupDescription(reference,owner){
 if(reference!=="absorbing tattoo|tce")return null;
 const type=/^([a-z]+) absorbing tattoo$/i.exec(String(owner?.name||""))?.[1]?.toLowerCase();
 if(!ABSORBING_DAMAGE_TYPES.has(type))return null;
 return [
  "Magic tattoo (very rare; requires attunement). When attuned, its needle turns into the tattoo. The tattoo vanishes and the needle returns when attunement ends.",
  "Damage Resistance: While you wear the tattoo, you have resistance to "+type+" damage.",
  "Damage Absorption: When you take "+type+" damage, you may use your reaction to become immune to that instance of damage and regain hit points equal to half the damage you would otherwise take. This reaction is available again at the next dawn."
 ];
}
function resolveItemEntryReferences(value,index,categories,owner,seen=new Set(),depth=0){
 if(depth>12)return value;
 if(Array.isArray(value))
  return value.map(part=>resolveItemEntryReferences(part,index,categories,owner,seen,depth+1));
 if(typeof value==="string"){
  const match=ITEM_ENTRY_REF.exec(value.trim());
  if(!match)return value;
  const name=match[1].trim(),source=String(match[2]||owner?.source||"").trim();
  const ref=(name+"|"+source).toLowerCase();
  if(seen.has(ref))return "Riferimento circolare 5etools: "+name;
  const referenced=categories.map(category=>index?.[category]?.[ref])
   .find(row=>row&&typeof row==="object");
  if(!referenced){
   return missingItemGroupDescription(ref,owner)||
    "Descrizione condivisa con "+name+" ("+source+") non inclusa nel catalogo offline.";
  }
  const next=new Set(seen);next.add(ref);
  const description=referenced.entries??referenced.description??referenced.text??referenced.fluff;
  return resolveItemEntryReferences(description??value,index,categories,owner,next,depth+1);
 }
 if(value&&typeof value==="object"){
  const out={...value};
  for(const key of ["entries","entry","items","additionalEntries","entriesTemplate","description","text","fluff"])
   if(value[key]!==undefined)
    out[key]=resolveItemEntryReferences(value[key],index,categories,owner,seen,depth+1);
  return out;
 }
 return value;
}
export async function detailedEntry(category,entry) {
  // Keep homebrew entries independent from the published compendium.
  if(entry?._homebrew||String(entry?.origin||'').toLowerCase()==='homebrew')return entry;
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
 // Owned inventory uses "items"; the complete compendium is categorized.
 const itemCategories=["magic_items","mundane_items","weapons","armor","tools"];
 const prefix=String(entry.id||"").toLowerCase().split(":")[0];
 const byId={magic_item:"magic_items",mundane_item:"mundane_items",
  weapon:"weapons",armor:"armor",tool:"tools"}[prefix];
 const categories=cat==="items"||category==="items"?
  [...new Set([cat!=="items"?cat:null,byId,...itemCategories].filter(Boolean))]:[cat];
 const candidate=categories.map(key=>index?.[key]?.[lookup])
  .find(value=>value&&typeof value==="object");
 if(!candidate)return entry;
 const copy={...entry};
 for(const field of ["entries","description","text","fluff","additionalEntries",
  "entriesTemplate","itemTypeAdditionalEntries","inherits","feats","feature_sections"]){
  if(copy[field]==null||copy[field]===""||(Array.isArray(copy[field])&&!copy[field].length))
   if(candidate[field]!=null)copy[field]=candidate[field];
 }
 if(path===GROUPS.items&&categories.length){
  for(const field of DESCRIPTION_FIELDS)
   if(copy[field]!==undefined)
    copy[field]=resolveItemEntryReferences(copy[field],index,itemCategories,entry);
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
