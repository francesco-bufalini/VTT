// Native quick_custom_catalog.gd equivalent. Save the exact portable
// homebrew definition shape used by Godot, never modify packaged 5etools data.
import {listRecords, getRecord, deleteRecordIfRevision} from "./storage.js";
import {saveHomebrewDefinition, listCreatures} from "./creatures.js";
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
