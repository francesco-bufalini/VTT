// Canonical species descriptions are sourced from 5eTools. Structured grants
// must never reconstruct rules by parsing these presentation-only texts.
const norm=value=>String(value??'').trim().toLowerCase();
function namedEntry(value,name){
 if(!value||!name)return null;
 if(Array.isArray(value)){
  for(const part of value){const found=namedEntry(part,name);if(found)return found;}
  return null;
 }
 if(typeof value!=='object')return null;
 if(norm(value.name)===norm(name))return value;
 for(const key of ['entries','entry','items']){
  const found=namedEntry(value[key],name);
  if(found)return found;
 }
 return null;
}
function entryText(value,includeOptions=true){
 if(typeof value==='string')return value;
 if(Array.isArray(value))return value.map(row=>entryText(row,includeOptions)).filter(Boolean).join('\n');
 if(!value||typeof value!=='object'||!includeOptions&&value.type==='list')return '';
 const body=entryText(value.entries??value.entry??value.items??value.text??'',includeOptions);
 return value.type==='item'&&value.name&&body?value.name+': '+body:body;
}
// Only inline 5eTools annotation syntax is unwrapped; source wording is retained.
const plainText=value=>String(value||'').replace(/\{@([a-z][a-z0-9]*)\s+([^{}]*?)\}/gi,(_match,_kind,body)=>{
 const parts=body.split('|');
 return parts.length>=3?parts.at(-1):parts[0];
}).trim();
function sourceTrait(originDetails,raceName,raceSource,trait,owner){
 const races=originDetails?.races||{};
 const race=Array.isArray(races)?
  races.find(row=>norm(row.name)===norm(raceName)&&norm(row.source)===norm(raceSource)):
  races[norm(raceName)+'|'+norm(raceSource)];
 return namedEntry(race?.entries,trait)||
  (norm(owner?.name)===norm(trait)&&owner?.entries!==undefined?owner:null);
}
export function speciesTraitDescription(originDetails={},raceName='',raceSource='',trait='',
 {owner=null,option='',includeOptions=true}={}){
 const source=sourceTrait(originDetails,raceName,raceSource,trait,owner);
 const selected=option?namedEntry(source?.entries,option):source;
 return plainText(entryText(selected,includeOptions));
}
export function speciesTraitOptionName(originDetails={},raceName='',raceSource='',trait='',option=''){
 const source=sourceTrait(originDetails,raceName,raceSource,trait,null);
 return namedEntry(source?.entries,option)?.name||'';
}
