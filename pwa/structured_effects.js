// Generic structured effects and fixed proficiency projection based on
// creature_structured_bonuses.gd and creature_proficiency_rules.gd.
// No mechanics are inferred from descriptions or HTML/prose.
const array=v=>Array.isArray(v)?v:[];
const norm=s=>String(s??"").trim().toLowerCase();
const match=(a,b)=>norm(a)===norm(b);
const validAmount=v=>typeof v==="number"&&Number.isFinite(v)||
  typeof v==="string"&&v.trim()!==""&&Number.isFinite(Number(v));
const identity=(group,row)=>group+"|"+norm(row.source)+"|"+norm(row.name);
const kinds=["weapon","armor","skill","expertise","save","tool","language"];
const fields={weapon:"weaponProficiencies",armor:"armorProficiencies",
  skill:"skillProficiencies",expertise:"expertise",tool:"toolProficiencies",
  language:"languageProficiencies",save:"saveProficiencies"};
const legacy={skill:"skill_proficiencies",expertise:"skill_expertise",save:"saving_throw_proficiencies"};
const classMembers=record=>array(record.classes).length?array(record.classes):
  record.class?[{name:record.class,source:record.class_source||"",level:record.level||1}]:[];
function selectedSources(record,index={}){
  const selected=[];
  const push=(group,source,origin,mode="starting")=>{
    if(!source?.name)return;
    const id=identity(group,source);
    if(!selected.some(x=>x.id===id))selected.push({id,group,source,origin,mode});
  };
  for(const [group,field,sourceField] of [["race","species","species_source"],
      ["background","background","background_source"]]){
    if(!record[field])continue;
    for(const source of array(index[group]).filter(x=>match(x.name,record[field])&&
        (group==="background"&&!record[sourceField]||match(x.source,record[sourceField]))))
      push(group,source,record[field]);
  }
  if(record.subrace)for(const source of array(index.subrace).filter(x=>
    match(x.raceName,record.species)&&match(x.name,record.subrace)&&
    match(x.source,record.subrace_source)&&
    match(x.raceSource,record.species_source)))
    push("subrace",source,record.subrace);
  for(const feat of array(record.feats_catalog)){
    if(!feat||feat.disabled)continue;
    for(const source of array(index.feat).filter(x=>match(x.name,feat.name)&&
        match(x.source,feat.source)))push("feat",source,feat.name);
  }
  let first=true;
  for(const member of classMembers(record)){
    for(const source of array(index.class).filter(x=>match(x.name,member?.name)&&
        match(x.source,member.source)))
      push("class",source,member.name,first?"starting":"multiclass");
    first=false;
  }
  return selected;
}
function grantedFields(source,kind){
  if(source.group==="class"){
    if(kind==="save")return source.mode==="starting"?source.source.savingThrows:[];
    const data=source.mode==="starting"?source.source.startingProficiencies:
      source.source.multiclassProficiencies;
    if(kind==="skill")return data?.skills??[];
    if(kind==="weapon")return data?.weaponProficiencies??data?.weapons??[];
    if(kind==="armor")return data?.armorProficiencies??data?.armor??[];
    if(kind==="tool")return data?.toolProficiencies??data?.tools??[];
    return [];
  }
  return source.source[fields[kind]]??[];
}
function grantLiteral(kind,raw){
  let key=norm(raw);
  if(key.startsWith("{@item ")&&key.endsWith("}"))
    key=key.slice(7,-1).split("|")[0].trim();
  else if(key.includes(" ")&&!["skill","language"].includes(kind)&&
      !["simple","martial","all"].includes(key))return "";
  if(key.startsWith("{@")||!key)return "";
  return key;
}
function fixedGrants(source){
  const result=[];
  for(const kind of kinds){
    const raw=grantedFields(source,kind);
    for(const row of array(raw)){
      if(typeof row==="string"){
        const key=grantLiteral(kind,row);
        if(key)result.push({kind,key});
      }else if(row&&typeof row==="object"&&!Array.isArray(row)){
        for(const [name,value] of Object.entries(row)){
          if(value===true&&!("choose any anyArtisansTool anyGamingSet anyMusicalInstrument anyStandard anyExotic anyProficientSkill".split(" ")).includes(name))
            result.push({kind,key:norm(name.split("|")[0])});
        }
      }
    }
  }
  return result;
}
function muted(record,id){
  if(!id)return false;
  if(record.origin_enabled&&Object.hasOwn(record.origin_enabled,id)&&!record.origin_enabled[id])return true;
  return array(record.proficiency_origins).some(x=>x.id===id&&x.disabled);
}
export function fixedProficiencies(record,index={}){
  const stored=array(record.proficiency_choices).filter(x=>x&&!x.disabled&&
    !muted(record,String(x.origin_id||"")));
  const result=new Map();
  const add=(kind,key)=>result.set(kind+":"+norm(key),true);
  for(const row of stored)if(kinds.includes(row.kind)&&row.key)add(row.kind,row.key);
  const migrate=!Object.hasOwn(record,"proficiency_choices")||
    (!stored.length&&!array(record.proficiency_choices).length&&
      !Object.hasOwn(record,"proficiency_origins"));
  if(migrate)for(const [kind,field] of Object.entries(legacy))
    for(const item of array(record[field]))add(kind,item);
  for(const source of selectedSources(record,index)){
    if(muted(record,source.id))continue;
    for(const grant of fixedGrants(source)){
      const saved=array(record.proficiency_choices).find(x=>x.kind===grant.kind&&
        norm(x.key)===grant.key&&x.origin_id===source.id);
      if(saved?.disabled)continue;
      add(grant.kind,grant.key);
    }
  }
  return result;
}
export const automaticId=(sid,field,target,suffix="")=>
  "auto|"+sid+"|"+field+"|"+target+suffix;
export function numericGrant(sid,name,field,target,value,suffix=""){
  if(!target||!validAmount(value))return null;
  return {id:automaticId(sid,field,target,suffix),
    origin_id:sid,origin_name:name,target,expression:String(value),
    automatic:true,disabled:false};
}
function structuredFeatures(record){
  const collected=[];
  const append=(row,originKey,gate={},fallbackId="")=>{
    if(!row||typeof row!=="object"||!Array.isArray(row.bonuses)||!row.bonuses.length)return;
    if(row.inactive)return;
    const id=String(row.id||fallbackId||"").trim()||
      (originKey+"|"+String(gate.min_level??0)+"|"+norm(row.name));
    const featureKey=originKey+"|"+id;
    collected.push({key:featureKey,originKey,source:row,requirements:{
      scope:gate.scope||"character",min_level:Number(gate.min_level??row.min_level??0),
      class_name:gate.class_name||"",class_source:gate.class_source||""}});
  };
  if(record.kind==="monster"){
    const stat=record.stat_block||{};
    for(const section of ["trait","action","bonus","reaction","legendary","mythic","lairActions"])
      for(const [i,row] of array(stat[section]).entries())
        append(row,"monster|"+section,{min_level:0},String(i));
  }
  // Structured features already present in portable/homebrew definitions.
  // Mirror Features._append() IDs and leave prose-only traits untouched.
  for(const feat of array(record.feats_catalog)){
    if(feat?.disabled)continue;
    const featId=String(feat.id||norm(feat.name)+"|"+norm(feat.source));
    const originKey="feat|"+featId;
    append(feat,originKey,{min_level:1},"overview");
    for(const [i,row] of array(feat.feature_sections).entries())
      append(row,originKey,{min_level:Number(row.min_level??1)},String(i));
  }
  for(const member of classMembers(record)){
    const classKey="class|"+norm(member.source)+"|"+norm(member.name);
    for(const [i,row] of array(member.features).entries())
      append(row,classKey,{scope:"class",class_name:member.name,
        class_source:member.source,min_level:Number(row.level??1)},String(i));
    for(const [i,row] of array(member.subclass_features).entries()){
      const subclassKey=classKey+"|subclass|"+norm(member.subclass)+"|"+
        norm(member.subclass_source);
      append(row,subclassKey,{scope:"class",class_name:member.name,
        class_source:member.source,min_level:Number(row.level??1)},String(i));
    }
  }
  return collected;
}
export function structuredFeatureGrants(record){
  const results=[];
  for(const f of structuredFeatures(record)){
    const sid="feature:"+f.key;
    for(const entry of f.source.bonuses){
      if(!entry||typeof entry!=="object")continue;
      const target=String(entry.target||"");
      const grant=numericGrant(sid,"Tratto · "+(f.source.name||f.key),"bonuses",
        target,entry.expression,"|"+target);
      if(grant)results.push({...grant,requirements:f.requirements,
        parent_origin:f.originKey});
    }
  }
  return results;
}
export function structuredOrigins(record,index={}){
  return selectedSources(record,index).map(row=>({id:row.id,
    active:!muted(record,row.id),group:row.group,name:row.origin,
    mode:row.mode}));
}
