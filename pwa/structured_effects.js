import {removedBenefitIds} from './trait_benefit_editor.js';
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
// Treat older single-background characters as having a first background.
export function effectiveBackgrounds(record={}){
 const primary=record.background?[{name:record.background,id:record.background_id||'',source:record.background_source||''}]:[];
 const rows=[...primary,...array(record.backgrounds_catalog)].filter(row=>row?.name&&!row.disabled);
 const seen=new Set();
 return rows.filter(row=>{
  const key=norm(row.name)+'|'+norm(row.source);
  if(seen.has(key))return false;
  seen.add(key);return true;
 });
}
export function selectedSources(record,index={}){
  const selected=[];
  const push=(group,source,origin,mode="starting")=>{
    if(!source?.name)return;
    const id=identity(group,source);
    if(!selected.some(x=>x.id===id))selected.push({id,group,source,origin,mode});
  };
  for(const [group,field,sourceField] of [["race","species","species_source"]]){
    if(!record[field])continue;
    for(const source of array(index[group]).filter(x=>match(x.name,record[field])&&
        (group==="background"&&!record[sourceField]||match(x.source,record[sourceField]))))
      push(group,source,record[field]);
  }
  for(const background of effectiveBackgrounds(record))
    for(const source of array(index.background).filter(x=>match(x.name,background.name)&&
      (!background.source||match(x.source,background.source))))
      push("background",source,background.name);
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
export function grantedFields(source,kind){
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
        // Some 5etools class sources describe optional firearms proficiency as
        // {proficiency:"firearms",optional:true}. These are metadata fields,
        // not proficiency names ("weapon:optional" was previously leaked).
        if(typeof row.proficiency==="string"){
          const key=grantLiteral(kind,row.proficiency);
          if(key)result.push({kind,key});
        }
        for(const [name,value] of Object.entries(row)){
          if(["proficiency","optional"].includes(name))continue;
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
function liveSource(record,id){
  if(!id)return true;
  const parts=String(id).split("|"),group=parts[0],
    source=parts[1]||"",name=parts.slice(2).join("|");
  if(group==="race")return match(record.species,name)&&match(record.species_source,source);
  if(group==="subrace")return match(record.subrace,name)&&match(record.subrace_source,source);
  if(group==="background")return effectiveBackgrounds(record).some(row=>match(row.name,name)&&
    (!source||!row.source||match(row.source,source)));
  if(group==="class")return classMembers(record).some(c=>match(c.name,name)&&match(c.source,source));
  if(group==="feat")return array(record.feats_catalog).some(f=>!f?.disabled&&(
    match(f.id,parts.slice(1).join("|"))||
    match(f.name,name)&&match(f.source,source)));
  if(id.startsWith("item:"))return array(record.inventory).some(row=>
    "item:"+row?.id===id&&Number(row.quantity??1)>0);
  return true; // Saved custom origins are not automatically invalidated by changing class.
}
export function fixedProficiencies(record,index={}){
  const suppressed=removedBenefitIds(record);
  const excluded=(source,kind,key)=>suppressed.has("proficiency:"+source+":"+kind+":"+norm(key));
  const stored=array(record.proficiency_choices).filter(x=>x&&!x.disabled&&
    !muted(record,String(x.origin_id||""))&&liveSource(record,String(x.origin_id||"")));
  const result=new Map();
  const add=(kind,key)=>result.set(kind+":"+norm(key),true);
  for(const row of stored)if(kinds.includes(row.kind)&&row.key&&
    !excluded(row.origin_id||'',row.kind,row.key))add(row.kind,row.key);
  const migrate=!Object.hasOwn(record,"proficiency_choices")||
    (!stored.length&&!array(record.proficiency_choices).length&&
      !Object.hasOwn(record,"proficiency_origins"));
  if(migrate)for(const [kind,field] of Object.entries(legacy))
    for(const item of array(record[field]))add(kind,item);
  for(const source of selectedSources(record,index)){
    if(muted(record,source.id))continue;
    for(const grant of fixedGrants(source)){
      if(excluded(source.id,grant.kind,grant.key))continue;
      const saved=array(record.proficiency_choices).find(x=>x.kind===grant.kind&&
        norm(x.key)===grant.key&&x.origin_id===source.id);
      if(saved?.disabled)continue;
      add(grant.kind,grant.key);
    }
  }
  return result;
}
// Expose the actual grant sources, not a guessed name from the skill.
export function proficiencyGrantOrigins(record={},index={},kind,key){
 const suppressed=removedBenefitIds(record);
 const excluded=id=>suppressed.has('proficiency:'+id+':'+kind+':'+norm(key));
 const wanted=String(key||'').toLowerCase(),sources=[],seen=new Set();
 const add=(id,name)=>{
   if(!id||seen.has(id))return;
   seen.add(id);sources.push({id,name:name||id});
 };
 for(const row of array(record.proficiency_choices))
   if(row&&!row.disabled&&row.kind===kind&&norm(row.key)===wanted&&
     !muted(record,row.origin_id)&&liveSource(record,row.origin_id)&&!excluded(row.origin_id))
     add(row.origin_id,row.origin_name||row.origin_id);
 for(const source of selectedSources(record,index)){
   if(muted(record,source.id)||excluded(source.id))continue;
   if(!fixedGrants(source).some(grant=>grant.kind===kind&&grant.key===wanted))continue;
   const override=array(record.proficiency_choices).find(row=>row.kind===kind&&
     norm(row.key)===wanted&&row.origin_id===source.id);
   if(!override?.disabled)add(source.id,source.origin||source.source?.name);
 }
 return sources;
}
export const automaticId=(sid,field,target,suffix="")=>
  "auto|"+sid+"|"+field+"|"+target+suffix;
export function numericGrant(sid,name,field,target,value,suffix=""){
  if(!target||!validAmount(value))return null;
  return {id:automaticId(sid,field,target,suffix),
    origin_id:sid,origin_name:name,target,expression:String(value),
    automatic:true,disabled:false};
}
// Native CreatureFeatures.collect_features identity scheme. These are
// data-driven projections, not inferred mechanics from English descriptions.
export function collectStructuredFeatures(record,catalogs={}){
  const results=[],seen=new Set();
  const members=classMembers(record),total=Number(record.level??members.reduce((n,c)=>n+Math.max(0,Number(c.level)||0),0)??1)||1;
  const classLevel=(name,source)=>members.filter(c=>match(c.name,name)&&(!source||!c.source||match(c.source,source)))
    .reduce((n,c)=>Math.max(n,Number(c.level)||0),0);
  function append(row,origin,level=1,scope="character",className="",classSource="",inactive=false){
    if(!row||typeof row!=="object"||!String(row.name||"").trim())return;
    const gate={scope,min_level:level,...(scope==="class"?{class_name:className,class_source:classSource}:{}),...(row.requirements||{})};
    const at=gate.scope==="class"?classLevel(gate.class_name||className,gate.class_source||classSource):total;
    if(at<Number(gate.min_level||0)||gate.max_level!==undefined&&gate.max_level!==""&&at>Number(gate.max_level))return;
    const id=String(row.id||"").trim()||origin+"|"+level+"|"+norm(row.name);
    const key=origin+"|"+id;if(seen.has(key))return;seen.add(key);
    results.push({...row,key,origin_key:origin,origin_id:"feature:"+key,
      level,requirements:gate,inactive:inactive||row.inactive===true,
      bonuses:array(row.bonuses),action_type:row.action_type||row.activation_type||row.activation||row.time||"",
      action_kind:row.action_kind||"Capacità"});
  }
  if(record.kind==="monster"){
    for(const section of ["trait","action","bonus","reaction","legendary","mythic","lairActions"])
      for(const row of array(record.stat_block?.[section]))
        append(row,"monster|"+section,0);
  }else{
    const details=catalogs.originDetails||{};
    const lookup=(category,name,source)=>{
      const entries=details[category];if(!entries||!name)return null;
      if(Array.isArray(entries))return entries.find(r=>match(r.name,name)&&(!source||match(r.source,source)))||null;
      const candidate=entries[norm(name)+"|"+norm(source)];if(candidate)return candidate;
      if(source)return null;
      const matching=Object.entries(entries).filter(([key])=>key.startsWith(norm(name)+"|"));
      return matching.length===1?matching[0][1]:null;
    };
    if(record.species){
      const full=record.subrace&&lookup("races",record.species+" ("+record.subrace+")",record.subrace_source);
      const race=full||lookup("races",record.species,record.species_source);
      const origin="species|"+(record.species_id||norm(record.species))+"|"+norm(record.species_source);
      array(race?.entries).forEach((row,i)=>{
        if(row&&typeof row==="object")append({...row,name:row.name||"Altri tratti · "+(i+1)},origin,
          Number(row.level||1));
      });
    }
    for(const selection of effectiveBackgrounds(record)){
      const background=lookup("backgrounds",selection.name,selection.source);
      const origin="background|"+norm(background?.source||selection.source)+"|"+norm(selection.name);
      for(const row of array(background?.entries))
        if(row?.name&&(row.entries!==undefined||row.entry!==undefined))
          append({...row,entries:row.entries??row.entry},origin,1);
    }
    for(const feat of array(record.feats_catalog)){
      if(!feat?.name)continue;
      const info=lookup("feats",feat.name,feat.source);
      const origin="feat|"+String(feat.id||norm(feat.name)+"|"+norm(feat.source));
      const sections=Array.isArray(info?.feature_sections)?info.feature_sections:
        Array.isArray(feat.feature_sections)?feat.feature_sections:null;
      const entries=sections||info?.entries||feat.entries||[];
      array(entries).forEach((row,i)=>{
        if(row?.name&&(sections||row.entries!==undefined||row.entry!==undefined))
          append({...row,...(!sections&&!row.id?{id:"section-"+i}:{})},origin,
            Number(row.requirements?.min_level??row.min_level??1),"character","","",Boolean(feat.disabled));
      });
    }
  }
  const featureIndex=catalogs.classFeatures||{
    class_features:array(catalogs.classMechanics?.resource_features).filter(f=>!f.subclass_name&&!f.subclass_short_name),
    subclass_features:array(catalogs.classMechanics?.resource_features).filter(f=>f.subclass_name||f.subclass_short_name)
  };
  const selectedEdition=record.rules_version==="2024"?"XPHB":"PHB";
  for(const member of members){
    if(!member?.name||match(member.name,"Mostro"))continue;
    const name=member.name,source=String(member.source||record.class_source||selectedEdition);
    const level=Math.max(0,Number(member.level)||0),base="class|"+norm(source)+"|"+norm(name);
    for(const row of [...array(featureIndex.class_features),...array(member.features)]){
      if(row?.class_name&&!match(row.class_name,name))continue;
      if(row?.class_source&&!match(row.class_source,source))continue;
      const at=Number(row?.level??1);
      if(at>=1&&at<=level)append(row,base,at,"class",name,source);
    }
    const primary=match(member.name,record.class)&&match(source,record.class_source||selectedEdition);
    const sub=member.subclass||(primary?record.subclass:'');
    if(!sub)continue;
    const subsource=String(member.subclass_source||(primary?record.subclass_source:'')||"");
    const origin=base+"|subclass|"+norm(sub)+"|"+norm(subsource);
    for(const row of [...array(featureIndex.subclass_features),...array(member.subclass_features)]){
      if(row?.class_name&&!match(row.class_name,name))continue;
      if(row?.class_source&&!match(row.class_source,source))continue;
      if((row?.subclass_name||row?.subclass_short_name)&&
        !match(row.subclass_name,sub)&&!match(row.subclass_short_name,sub))continue;
      if(subsource&&row?.subclass_source&&!match(row.subclass_source,subsource))continue;
      const at=Number(row?.level??1);
      if(at>=1&&at<=level)append(row,origin,at,"class",name,source);
    }
  }
  return results;
}
export function structuredFeatureGrants(record,catalogs={},features=collectStructuredFeatures(record,catalogs)){
  const result=[];
  for(const feature of features){
    if(feature.inactive)continue;
    const classSource=String(feature.class_source||String(feature.origin_key||'').split('|')[1]||'').toUpperCase();
    const owner=String(feature.class_name||feature.requirements?.class_name||String(feature.origin_key||'').split('|')[2]||'').toLowerCase();
    if(owner==='artificer'&&classSource==='TCE'){
      // State-dependent speed grants live in the trait-state catalog.
      const level=Number(classMembers(record).find(c=>match(c.name,'Artificer')&&c.source==='TCE')?.level||0);
      let amount=0;
      if(feature.name==='Magic Item Adept'&&level<14)amount=1;
      if(feature.name==='Magic Item Savant'&&level<18)amount=2;
      if(feature.name==='Magic Item Master')amount=3;
      if(amount)result.push(numericGrant(feature.origin_id,'Tratto · '+feature.name,'attunement','attunement_max',amount));
      if(feature.name==='Soul of Artifice'){
        const count=array(record.inventory).filter(i=>i.attuned&&Number(i.quantity??1)>0).length;
        for(const ability of ['str','dex','con','int','wis','cha'])result.push(numericGrant(feature.origin_id,'Tratto · '+feature.name,'soul','save:'+ability,count));
      }
    }
    for(const row of feature.bonuses){
      if(!row||typeof row!=="object")continue;
      const target=String(row.target||"");
      const grant=numericGrant(feature.origin_id,"Tratto · "+feature.name,
        "bonuses",target,row.expression,"|"+target);
      if(grant)result.push({...grant,requirements:feature.requirements,
        parent_origin:feature.origin_key});
    }
  }
  return result;
}
export function structuredOrigins(record,index={}){
  return selectedSources(record,index).map(row=>({id:row.id,
    active:!muted(record,row.id),group:row.group,name:row.origin,
    mode:row.mode}));
}
